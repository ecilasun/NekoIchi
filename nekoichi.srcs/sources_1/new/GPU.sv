`timescale 1ns / 1ps

`include "cpuops.vh"
`include "gpuops.vh"

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
// Idea based on Larrabee rasterizer
// NOTE: No barycentric / gradient generation yet
// ==============================================================
module LineRasterMask(
	input wire reset,
	input wire signed [8:0] tileX,
	input wire signed [8:0] tileY,
	input wire signed [8:0] x0,
	input wire signed [8:0] y0,
	input wire signed [8:0] x1,
	input wire signed [8:0] y1,
	output wire outmask );

logic signed [8:0] B;
logic signed [8:0] C;
logic signed [8:0] dX;
logic signed [8:0] dY;
logic signed [17:0] mask;
always_comb begin
	if (reset) begin
		// mask = 0;
	end else begin
		B = y1-y0;
		C = x0-x1;
		// Need to add one here to the result since:
		// - pixel coordinate is at upper left corner
		// - line coordinates are at centers of pixels
		// - adding one approximates adding 0.5, rounded up
		// - this way we don't miss lines crossing the pixel (i.e. dx/dy==0) 
		dX = (tileX-x0)+1;
		dY = (tileY-y0)+1; 
		mask = (B*dX) + (C*dY);
	end
end

assign outmask = mask[17]; // Only care about the sign bit

endmodule

// ==============================================================
// GPU main
// ==============================================================
module GPU (
	input wire clock,
	input wire reset,
	input wire vsync,
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
	output logic [14:0] dmaaddress,
	output logic [31:0] dmaword,
	output logic [3:0] dmawe,
	input wire [31:0] dma_data );
	
logic [`GPUSTATEBITS-1:0] gpustate = `GPUSTATEIDLE_MASK;
logic [31:0] commandlatch = 32'd0;

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
// Decoder
// ==============================================================
always_comb begin
	cmd = commandlatch[2:0];		// command
	// commandlatch[3] unused for now
	rs1 = commandlatch[6:4];		// source register 1
	rs2 = commandlatch[9:7];		// source register 2 (==destination register)
	rd = commandlatch[9:7];			// destination register
	immshort = commandlatch[31:10];	// 22 bit immediate
	imm = commandlatch[31:4];		// 28 bit immediate
end

// ==============================================================
// Dynamic tile scanner with 4 check points
// ==============================================================
logic [7:0] tileXCount, tileYCount;
logic signed [8:0] tileX0, tileY0, tileXSweepDirection;
logic signed [8:0] x0, y0, x1, y1, x2, y2;

// 4x1 pixel tile
wire [3:0] tilemask;
// Masks for each edge
wire [11:0] edgemask;
// Edge 0
LineRasterMask m0(reset, tileX0,tileY0, x0,y0, x1,y1, edgemask[0]);
LineRasterMask m1(reset, tileX0+1,tileY0, x0,y0, x1,y1, edgemask[1]);
LineRasterMask m2(reset, tileX0+2,tileY0, x0,y0, x1,y1, edgemask[2]);
LineRasterMask m3(reset, tileX0+3,tileY0, x0,y0, x1,y1, edgemask[3]);
// Edge 1
LineRasterMask m4(reset, tileX0,tileY0, x1,y1, x2,y2, edgemask[4]);
LineRasterMask m5(reset, tileX0+1,tileY0, x1,y1, x2,y2, edgemask[5]);
LineRasterMask m6(reset, tileX0+2,tileY0, x1,y1, x2,y2, edgemask[6]);
LineRasterMask m7(reset, tileX0+3,tileY0, x1,y1, x2,y2, edgemask[7]);
// Edge 2
LineRasterMask m8(reset, tileX0,tileY0, x2,y2, x0,y0, edgemask[8]);
LineRasterMask m9(reset, tileX0+1,tileY0, x2,y2, x0,y0, edgemask[9]);
LineRasterMask m10(reset, tileX0+2,tileY0, x2,y2, x0,y0, edgemask[10]);
LineRasterMask m11(reset, tileX0+3,tileY0, x2,y2, x0,y0, edgemask[11]);
// Mask for 3 edges to form a triangle
assign tilemask = edgemask[3:0] & edgemask[7:4] & edgemask[11:8];

// ==============================================================
// Tile scan area min-max calculation
// ==============================================================
logic signed [8:0] minXval, maxXval;
logic signed [8:0] minYval, maxYval;
always_comb begin
	// 0-1 selection
	minXval = x0 < x1 ? x0 : x1;
	maxXval = x0 < x1 ? x1 : x0;
	minYval = y0 < y1 ? y0 : y1;
	maxYval = y0 < y1 ? y1 : y0;

	// 2-self selection
	minXval = minXval < x2 ? minXval : x2; // minXval = min(x0,min(x1,x2)) etc
	maxXval = maxXval < x2 ? x2 : maxXval;
	minYval = minYval < y2 ? minYval : y2;
	maxYval = maxYval < y2 ? y2 : maxYval;

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
end

// ==============================================================
// Main state machine
// ==============================================================
always_ff @(posedge clock) begin
	if (reset) begin

		gpustate <= `GPUSTATEIDLE_MASK;
		vramaddress <= 14'd0;
		vramwriteword <= 32'd0;
		vramwe <= 4'b0000;
		lanemask <= 12'h000;
		rdatain <= 32'd0;
		dmaaddress <= 15'd0;
		dmaword <= 32'd0;
		dmawe <= 4'b0000;
		dmacount <= 14'd0;
		fiford_en <= 1'b0;

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
					commandlatch <= fifodout;
					gpustate[`GPUSTATEEXEC] <= 1'b1;
				end else begin
					// Data is not available yet, spin
					gpustate[`GPUSTATELATCHCOMMAND] <= 1'b1;
				end
			end
	
			// Command execute state
			gpustate[`GPUSTATEEXEC]: begin
				unique case (cmd) // 4'bxxxx
					3'b000: begin // VSYNC
						if (vsync)
							gpustate[`GPUSTATEIDLE] <= 1'b1;
						else
							gpustate[`GPUSTATEEXEC] <= 1'b1;
					end
					3'b001: begin // REGSETLOW/HI
						rwren <= 1'b1;
						if (rs1==3'd0) // set LOW if source register is zero register
							rdatain <= {10'd0, immshort};
						else // set HIGH if source register is not zero register
							rdatain <= {immshort[9:0], rval1[21:0]};
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					3'b010: begin // MEMWRITE
						vramaddress <= immshort[17:4];
						vramwriteword <= rval1;
						vramwe <= immshort[3:0];
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					3'b011: begin // CLEAR
						vramaddress <= 14'd0;
						vramwriteword <= rval1;
						// Enable all 4 bytes since clears are 32bit per write
						vramwe <= 4'b1111;
						lanemask <= 12'hFFF; // Turn on all lanes for parallel writes
						gpustate[`GPUSTATECLEAR] <= 1'b1;
					end
					3'b100: begin // SYSDMA
						dmaaddress <= rval1[14:0]; // rs1: source
						dmacount <= 14'd0;
						dmawe <= 4'b0000; // Reading from SYSRAM
						gpustate[`GPUSTATEDMAKICK] <= 1'b1;
					end
					3'b101: begin // RASTERIZE
						// Grab primitive vertex data from rs+rd
						x0 <= {1'b0, rval1[7:0]};
						y0 <= {1'b0, rval1[15:8]};
						x1 <= {1'b0, rval1[23:16]};
						y1 <= {1'b0, rval1[31:24]};
						x2 <= {1'b0, rval2[7:0]};
						y2 <= {1'b0, rval2[15:8]};
						vramwriteword <= {rval2[23:16], rval2[23:16], rval2[23:16], rval2[23:16]}; // TODO: Use the color from rval2 to fill during development
						gpustate[`GPUSTATERASTERKICK] <= 1'b1;
					end
					3'b110: begin // TBD
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					3'b111: begin // TBD
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
				dmaaddress <= dmaaddress + 15'd1;
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
					vramwe <= 4'b1111;

					// Step to next DWORD to read
					dmaaddress <= dmaaddress + 15'd1;
					dmacount <= dmacount + 14'd1;
					gpustate[`GPUSTATEDMA] <= 1'b1;
				end
			end

			gpustate[`GPUSTATERASTERKICK]: begin
				// Set up scan extents (4x1 tiles for a 4bit mask)
				tileX0 <= {minXval[8:2],2'b0}; // 1/4th coordinate, tile width=4
				tileY0 <= minYval[8:0]; // full coordinate, tile height=1
				tileXCount <= ((maxXval-minXval)>>2); // W/4
				tileYCount <= (maxYval-minYval); // H
				tileXSweepDirection <= 9'd4;
				// Start by figuring out if we have something to rasterize
				// on this scanline.
				// No pixels found means we're backfacing and can bail out early
				gpustate[`GPUSTATERASTERDETECT] <= 1'b1;
			end
			
			gpustate[`GPUSTATERASTERDETECT]: begin
				// Did we find a valid mask here?
				if (|tilemask) begin
					// Yes, we can start rasterizing from this spot
					gpustate[`GPUSTATERASTER] <= 1'b1;
				end else begin
					// Did we reach the end and still no mask?
					if (tileXCount == 1'd0) begin
						// Abort, this polygon won't rasterize
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end else begin
						// Continue scanning
						tileXCount <= tileXCount - 8'd1;
						tileX0 <= tileX0 + tileXSweepDirection;
						gpustate[`GPUSTATERASTERDETECT] <= 1'b1;
					end
				end
			end

			gpustate[`GPUSTATERASTER]: begin
				// Output tile mask for this tile
				if (tileYCount == 0) begin
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin

					// Record current value
					// NOTE: We could have a zero mask OR be at the end
					// tile. Record the value regardless just in case
					// otherwise we'll have gaps when landing on the last tile with full value in it.
					vramaddress <= {tileY0[7:0], tileX0[7:2]};
					vramwe <= tilemask;

					// Did we run out of tiles in this direction, or hit a zero tile mask?
					if (((|tilemask)==1'b0) | (tileXCount == 1'd0)) begin
						// Reverse direction
						tileXSweepDirection = -tileXSweepDirection;
						// Step one down 
						tileY0 <= tileY0 + 9'd1;
						tileXCount <= ((maxXval-minXval)>>2); // W/4
						tileYCount <= tileYCount - 8'd1;
						// Search for a nonzero tile mask
						gpustate[`GPUSTATERASTERDETECT] <= 1'b1;
					end else begin
						// Step to next tile on scanline
						tileXCount <= tileXCount - 8'd1;
						tileX0 <= tileX0 + tileXSweepDirection;
						// Repeat
						gpustate[`GPUSTATERASTER] <= 1'b1;
					end
				end
			end
			
			default: begin
				// noop
			end
			
		endcase
	end
end
	
endmodule
