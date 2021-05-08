`timescale 1ns / 1ps

`include "cpuops.vh"
`include "gpuops.vh"

// ==============================================================
// Edge equation / mask generator
// ==============================================================

module LineRasterMask(
	input wire reset,
	input wire signed [8:0] pX,
	input wire signed [8:0] pY,
	input wire signed [8:0] x0,
	input wire signed [8:0] y0,
	input wire signed [8:0] x1,
	input wire signed [8:0] y1,
	output wire outmask );

logic signed [17:0] lineedge;
always_comb begin
	if (reset) begin
		// lineedge = 0;
	end else begin
		lineedge = (pX-x0)*(y1-y0) + (pY-y0)*(x0-x1);
	end
end

assign outmask = lineedge[17]; // Only care about the sign bit

endmodule

// ==============================================================
// GPU register file
// ==============================================================

module gpuregisterfile(
	input wire reset,
	input wire clock,
	input wire [2:0] rs1,
	input wire [2:0] rs2,
	input wire [2:0] rd,
	input wire wren, 
	input wire [31:0] datain,
	output wire [31:0] rval1,
	output wire [31:0] rval2 );

logic [31:0] registers[0:7]; 

always @(posedge clock) begin
	if (reset) begin
		// noop
	end else begin
		if (wren & rd != 0)
			registers[rd] <= datain;
	end
end

assign rval1 = rs1 == 0 ? 32'd0 : registers[rs1];
assign rval2 = rs2 == 0 ? 32'd0 : registers[rs2];

endmodule

// ==============================================================
// GPU main
// ==============================================================

module GPU (
	input wire clock,
	input wire reset,
	input wire [31:0] vsync,
	// GPU FIFO
	input wire fifoempty,
	input wire [31:0] fifodout,
	input wire fifdoutvalid,
	output logic fiford_en,
	// VRAM
	output logic [13:0] vramaddress,
	output logic [3:0] vramwe,
	output logic [31:0] vramwriteword,
	output logic [11:0] lanemask,
	// SYSRAM DMA channel
	output logic [31:0] dmaaddress,
	output logic [31:0] dmawriteword,
	output logic [3:0] dmawe,
	input wire [31:0] dma_data );
	
logic [`GPUSTATEBITS-1:0] gpustate = `GPUSTATEIDLE_MASK;

logic [31:0] rdatain;
wire [31:0] rval1;
wire [31:0] rval2;
logic rwren = 1'b0;
logic [2:0] rs1;
logic [2:0] rs2;
logic [2:0] rd;
logic [2:0] cmd;
logic [13:0] dmacount;
logic [21:0] immshort;
logic [27:0] imm;
gpuregisterfile gpuregs(
	.reset(reset),
	.clock(clock),
	.rs1(rs1),
	.rs2(rs2),
	.rd(rd),
	.wren(rwren),
	.datain(rdatain),
	.rval1(rval1),
	.rval2(rval2) );

// ==============================================================
// Coarse rasterizer
// ==============================================================

logic [8:0] tileXCount, tileYCount;
logic signed [8:0] tileX0, tileY0, tileXSweepDirection;
logic signed [8:0] x0, y0, x1, y1, x2, y2;
wire signed [8:0] tileYW0;

assign tileYW0 = {tileY0[8:2],2'b0}; // wide tile height=4

// Tile crossing mask
wire tilemask, widetilemask;
wire [3:0] tilecoverage;

// Masks for individual wide and narrow tiles
wire [11:0] edgemask;
wire [11:0] wideedgemask;

// Narrow mask for edge 0
LineRasterMask m0(reset, tileX0,         tileY0,        x0,y0, x1,y1, edgemask[0]);
LineRasterMask m1(reset, tileX0+9'sd1,   tileY0,        x0,y0, x1,y1, edgemask[1]);
LineRasterMask m2(reset, tileX0+9'sd2,   tileY0,        x0,y0, x1,y1, edgemask[2]);
LineRasterMask m3(reset, tileX0+9'sd3,   tileY0,        x0,y0, x1,y1, edgemask[3]);

// Narrow mask for edge 1
LineRasterMask m4(reset, tileX0,         tileY0,        x1,y1, x2,y2, edgemask[4]);
LineRasterMask m5(reset, tileX0+9'sd1,   tileY0,        x1,y1, x2,y2, edgemask[5]);
LineRasterMask m6(reset, tileX0+9'sd2,   tileY0,        x1,y1, x2,y2, edgemask[6]);
LineRasterMask m7(reset, tileX0+9'sd3,   tileY0,        x1,y1, x2,y2, edgemask[7]);

// Narrow mask for edge 2
LineRasterMask m8(reset,  tileX0,        tileY0,        x2,y2, x0,y0, edgemask[8]);
LineRasterMask m9(reset,  tileX0+9'sd1,  tileY0,        x2,y2, x0,y0, edgemask[9]);
LineRasterMask m10(reset, tileX0+9'sd2,  tileY0,        x2,y2, x0,y0, edgemask[10]);
LineRasterMask m11(reset, tileX0+9'sd3,  tileY0,        x2,y2, x0,y0, edgemask[11]);

// Wide mask for edge 0
LineRasterMask mw0(reset, tileX0,        tileYW0,       x0,y0, x1,y1, wideedgemask[0]);
LineRasterMask mw1(reset, tileX0+9'sd3,  tileYW0,       x0,y0, x1,y1, wideedgemask[1]);
LineRasterMask mw2(reset, tileX0,        tileYW0+9'sd3, x0,y0, x1,y1, wideedgemask[2]);
LineRasterMask mw3(reset, tileX0+9'sd3,  tileYW0+9'sd3, x0,y0, x1,y1, wideedgemask[3]);

// Wide mask for edge 1
LineRasterMask mw4(reset, tileX0,        tileYW0,       x1,y1, x2,y2, wideedgemask[4]);
LineRasterMask mw5(reset, tileX0+9'sd3,  tileYW0,       x1,y1, x2,y2, wideedgemask[5]);
LineRasterMask mw6(reset, tileX0,        tileYW0+9'sd3, x1,y1, x2,y2, wideedgemask[6]);
LineRasterMask mw7(reset, tileX0+9'sd3,  tileYW0+9'sd3, x1,y1, x2,y2, wideedgemask[7]);

// Wide mask for edge 2
LineRasterMask mw8(reset,  tileX0,       tileYW0,       x2,y2, x0,y0, wideedgemask[8]);
LineRasterMask mw9(reset,  tileX0+9'sd3, tileYW0,       x2,y2, x0,y0, wideedgemask[9]);
LineRasterMask mw10(reset, tileX0,       tileYW0+9'sd3, x2,y2, x0,y0, wideedgemask[10]);
LineRasterMask mw11(reset, tileX0+9'sd3, tileYW0+9'sd3, x2,y2, x0,y0, wideedgemask[11]);

// Composite tile mask
// If any bit of a tile is set, an edge crosses it
// If all edges cross a tile, it's inside the triangle
assign tilemask = (|edgemask[3:0]) & (|edgemask[7:4]) & (|edgemask[11:8]);
assign tilecoverage = edgemask[3:0] & edgemask[7:4] & edgemask[11:8];
// Wide mask (4x4) for fast sweep
assign widetilemask = (|wideedgemask[3:0]) & (|wideedgemask[7:4]) & (|wideedgemask[11:8]);

// ==============================================================
// Polygon facing check
// ==============================================================

logic [17:0] polydet;
logic triFacing;
always_comb begin
	if (reset) begin
		//
	end else begin
		polydet = (x2-x0)*(y1-y0) + (y2-y0)*(x0-x1);
	end
end
assign triFacing = polydet[17];

// ==============================================================
// Tile scan area min-max calculation
// ==============================================================

logic signed [8:0] minXval, maxXval;
logic signed [8:0] minYval, maxYval;

wire signed [8:0] minx01 = x0 < x1 ? x0 : x1;
wire signed [8:0] minx12 = x1 < x2 ? x1 : x2;
wire signed [8:0] maxx01 = x0 >= x1 ? x0 : x1;
wire signed [8:0] maxx12 = x1 >= x2 ? x1 : x2;

wire signed [8:0] miny01 = y0 < y1 ? y0 : y1;
wire signed [8:0] miny12 = y1 < y2 ? y1 : y2;
wire signed [8:0] maxy01 = y0 >= y1 ? y0 : y1;
wire signed [8:0] maxy12 = y1 >= y2 ? y1 : y2;

always_comb begin
	if (reset) begin
		// 
	end else begin
		// Pick actual min/max
		minXval = minx01 < minx12 ? minx01 : minx12;
		maxXval = maxx01 >= maxx12 ? maxx01 : maxx12;
		minYval = miny01 < miny12 ? miny01 : miny12;
		maxYval = maxy01 >= maxy12 ? maxy01 : maxy12;

		// Clamp to viewport min coords (0,0)
		minXval = minXval < 0 ? 0 : minXval;
		maxXval = maxXval < 0 ? 0 : maxXval;
		minYval = minYval < 0 ? 0 : minYval;
		maxYval = maxYval < 0 ? 0 : maxYval;
	
		// Clamp to viewport max coords (255,191)
		minXval = minXval < 256 ? minXval : 255;
		maxXval = maxXval < 256 ? maxXval : 255;
		minYval = minYval < 192 ? minYval : 191;
		maxYval = maxYval < 192 ? maxYval : 191;
		
		// Truncate X and Y min/max to nearest multiple of 4
		minXval = {minXval[8:2],2'b00};
		maxXval = {maxXval[8:2],2'b00};
		minYval = {minYval[8:2],2'b00};
		maxYval = {maxYval[8:2],2'b00};
	end
end

// ==============================================================
// Main state machine
// ==============================================================
logic [31:0] vsyncrequestpoint = 32'd0;
always_ff @(posedge clock) begin
	if (reset) begin
		gpustate <= `GPUSTATEIDLE_MASK;
		//vramaddress <= 14'd0;
		//vramwriteword <= 32'd0;
		vramwe <= 4'b0000;
		lanemask <= 12'h000;
		//rdatain <= 32'd0;
		//dmaaddress <= 32'd0;
		//dmawriteword <= 32'd0;
		dmawe <= 4'b0000;
		//dmacount <= 14'd0;
		fiford_en <= 1'b0;
		//frfifowe <= 1'b0;

	end else begin
	
		gpustate <= `GPUSTATENONE_MASK;
	
		unique case (1'b1)
		
			gpustate[`GPUSTATEIDLE]: begin
				// Stop writes to memory and registers
				vramwe <= 4'b0000;
				rwren <= 1'b0;
				// Also turn off parallel writes
				lanemask <= 12'h000;
				// And DMA writes
				dmawe <= 4'b0000;
				
				// See if there's something on the fifo
				if (~fifoempty) begin
					fiford_en <= 1'b1;
					gpustate[`GPUSTATELATCHCOMMAND] <= 1'b1;
				end else begin
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end
			end

			gpustate[`GPUSTATELATCHCOMMAND]: begin
				// Turn off fifo read request on the next clock
				fiford_en <= 1'b0;
				if (fifdoutvalid) begin
					// Data is available, latch and jump to execute
					cmd <= fifodout[2:0];		// command
					// fifodout[3] unused for now
					rs1 <= fifodout[6:4];		// source register 1
					rs2 <= fifodout[9:7];		// source register 2 (==destination register)
					rd <= fifodout[9:7];			// destination register
					immshort <= fifodout[31:10];	// 22 bit immediate
					imm <= fifodout[31:4];		// 28 bit immediate
					vsyncrequestpoint <= vsync;
					gpustate[`GPUSTATEEXEC] <= 1'b1;
				end else begin
					// Data is not available yet, spin
					gpustate[`GPUSTATELATCHCOMMAND] <= 1'b1;
				end
			end

			// Command execute state
			gpustate[`GPUSTATEEXEC]: begin
				unique case (cmd)
					`GPUCMD_VSYNC: begin
						if (vsync > vsyncrequestpoint)
							gpustate[`GPUSTATEIDLE] <= 1'b1;
						else
							gpustate[`GPUSTATEEXEC] <= 1'b1;
					end

					`GPUCMD_SETREG: begin
						rwren <= 1'b1;
						if (rs1==3'd0) // set LOW if source register is zero register
							rdatain <= {10'd0, immshort};
						else // set HIGH if source register is not zero register
							rdatain <= {immshort[9:0], rval1[21:0]};
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end

					`GPUCMD_MEMOUT: begin
						vramaddress <= immshort[17:4];
						vramwriteword <= rval1;
						vramwe <= immshort[3:0];
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end

					`GPUCMD_CLEAR: begin
						vramaddress <= 14'd0;
						vramwriteword <= rval1;
						// Enable all 4 bytes since clears are 32bit per write
						vramwe <= 4'b1111;
						lanemask <= 12'hFFF; // Turn on all lanes for parallel writes
						gpustate[`GPUSTATECLEAR] <= 1'b1;
					end

					`GPUCMD_SYSDMA: begin
						dmaaddress <= rval1; // rs1: source
						dmacount <= 14'd0;
						dmawe <= 4'b0000; // Reading from SYSRAM
						gpustate[`GPUSTATEDMAKICK] <= 1'b1;
					end

					`GPUCMD_RASTER: begin
						// Grab primitive vertex data from rs&rd
						x0 <= {1'b0, rval1[7:0]};
						y0 <= {1'b0, rval1[15:8]};
						x1 <= {1'b0, rval1[23:16]};
						y1 <= {1'b0, rval1[31:24]};
						x2 <= {1'b0, rval2[7:0]};
						y2 <= {1'b0, rval2[15:8]};

						// DEBUG: Solid color output during development
						// Full DWORD color from r2, mask selects which to write
						vramwriteword <= {rval2[23:16], rval2[23:16], rval2[23:16], rval2[23:16]};

						gpustate[`GPUSTATERASTERKICK] <= 1'b1;
					end

					`GPUCMD_SYSMEMOUT: begin
						dmaaddress <= rval2; // rs1: source
						dmawriteword <= rval1; // rs2: output word (same as rd)
						dmawe <= 4'b1111;
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end

					`GPUCMD_UNUSED1: begin
						// WiP
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
				endcase
			end
			
			gpustate[`GPUSTATECLEAR]: begin // CLEAR
				if (vramaddress == 14'h400) begin // 12*(256*192/4) (DWORD addresses) -> 0xC*0x400
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin
					vramaddress <= vramaddress + 14'd1;
					// Loop in same state
					gpustate[`GPUSTATECLEAR] <= 1'b1;
				end
			end

			gpustate[`GPUSTATEDMAKICK]: begin
				// Delay for first read
				dmaaddress <= dmaaddress + 32'd4;
				gpustate[`GPUSTATEDMA] <= 1'b1;
			end

			gpustate[`GPUSTATEDMA]: begin // SYSDMA
				if (dmacount == immshort[13:0]) begin
					// DMA done
					vramwe <= 4'b0000;
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin
					// Write the previous DWORD to absolute address
					vramaddress <= rval2[13:0] + dmacount;
					vramwriteword <= dma_data;
					
					if (immshort[14]==1'b1) begin
						// Zero-masked DMA
						vramwe <= {|dma_data[31:24], |dma_data[23:16], |dma_data[15:8], |dma_data[7:0]};
					end else begin
						// Unmasked DM
						vramwe <= 4'b1111;
					end

					// Step to next DWORD to read
					dmaaddress <= dmaaddress + 32'd4;
					dmacount <= dmacount + 14'd1;
					gpustate[`GPUSTATEDMA] <= 1'b1;
				end
			end

			gpustate[`GPUSTATERASTERKICK]: begin
				// Set up scan extents (4x1 tiles for a 4bit mask)
				tileX0 <= {minXval[8:2],2'b0}; // tile width=4
				tileY0 <= minYval; // tile height=1 (but using 4 aligned at start)
				tileXCount <= (maxXval-minXval)>>2; // W/4
				tileYCount <= (maxYval-minYval); // H/1
				tileXSweepDirection <= 9'd4;
				if (triFacing == 1'b1) begin
					// Start by figuring out if we have something to rasterize
					// on this scanline.
					// No pixels found means we're backfacing and can bail out early
					gpustate[`GPUSTATERASTER] <= 1'b1;
				end else begin
					// Backfacing polygons don't go into raster state
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end
			end

			gpustate[`GPUSTATERASTER]: begin

				// Stop fifo writes from previous clock
				//frfifowe <= 1'b0;

				if (tileYCount == 0) begin
					// We have exhausted all rows to rasterize
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin
				
					// Output tile mask for this tile

					// Record current value
					// NOTE: We could have a zero mask OR be at the end
					// tile. Record the value regardless just in case
					// otherwise we'll have gaps when landing on the last tile with full value in it.
					vramaddress <= {tileY0[7:0], tileX0[7:2]};
					//vramwriteword <= {28'd0, tilecoverage}; // DEBUG
					// This effectively turns off writes for unoccupied tiles since tilecoverage == 0
					vramwe <= tilecoverage;//{4{tilemask}};

					// Did we run out of tiles in this direction, or hit a zero tile mask?
					if (/*(~widetilemask) |*/ tileXCount == 0) begin
						// Reverse direction
						//tileXSweepDirection = -tileXSweepDirection;
						tileX0 <= {minXval[8:2],2'b0}; // <<
						// Step one tile down
						tileY0 <= tileY0 + 9'd1; // tile height=1
						// Actually this is too large but since we stop at empty tiles anyways, doesn't seem to hurt
						tileXCount <= (maxXval-minXval)>>2; // W/4
						tileYCount <= tileYCount - 9'sd1;
					end else begin
						// Step to next tile on scanline
						tileXCount <= tileXCount - 9'sd1;
						tileX0 <= tileX0 + tileXSweepDirection;
					end
					gpustate[`GPUSTATERASTER] <= 1'b1;
				end
			end

			default: begin
				// noop
			end

		endcase
	end
end
	
endmodule
