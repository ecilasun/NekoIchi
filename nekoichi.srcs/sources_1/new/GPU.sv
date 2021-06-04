`timescale 1ns / 1ps

`include "cpuops.vh"
`include "gpuops.vh"

// ================================================================
// Find dividing vertex and generate max two triangles out of one
// ================================================================
/*module TriangleSplitter(
	input wire reset,
	input wire signed [15:0] y0,
	input wire signed [15:0] y1,
	input wire signed [15:0] y2,
	output logic hassplittris,
	output logic signed [15:0] splitY);

wire mid0 = ((y0>y1) & (y0<y2)) | ((y0>y2) & (y0<y1));
wire mid1 = ((y1>y0) & (y1<y2)) | ((y1>y2) & (y1<y0));
wire mid2 = ((y2>y1) & (y2<y0)) | ((y2>y0) & (y2<y1));

always_comb begin
	if (reset) begin
	end else begin
		hassplittris = (mid0 | mid1 | mid2);
		splitY = mid0 ? y0 : (mid1 ? y1 : (mid2 ? y2 : 16'hFFFF));
	end
end

endmodule*/

// ==============================================================
// Edge equation / mask generator
// ==============================================================

module LineRasterMask(
	input wire reset,
	input wire signed [15:0] pX,
	input wire signed [15:0] pY,
	input wire signed [15:0] x0,
	input wire signed [15:0] y0,
	input wire signed [15:0] x1,
	input wire signed [15:0] y1,
	output wire outmask );

logic signed [31:0] lineedge;
wire signed [15:0] A = (pY-y0);
wire signed [15:0] B = (pX-x0);
wire signed [15:0] dy = (y1-y0);
wire signed [15:0] dx = (x0-x1);

always_comb begin
	lineedge = A*dx + B*dy;
end

assign outmask = lineedge[31]; // Only care about the sign bit

endmodule

// ==============================================================
// GPU register file
// ==============================================================

module gpuregisterfile(
	input wire reset,
	input wire clock,
	input wire [2:0] rs1,
	input wire [2:0] rs2,
	input wire [2:0] rs3,
	input wire [2:0] rd,
	input wire wren, 
	input wire [31:0] datain,
	output wire [31:0] rval1,
	output wire [31:0] rval2,
	output wire [31:0] rval3 );

logic [31:0] registers[0:7]; 

initial begin
	registers[0] <= 32'h00000000;
	registers[1] <= 32'h00000000; 
	registers[2] <= 32'h00000000;
	registers[3] <= 32'h00000000;
	registers[4] <= 32'h00000000;
	registers[5] <= 32'h00000000;
	registers[6] <= 32'h00000000;
	registers[7] <= 32'h00000000;
end

always @(posedge clock) begin
	if (wren & rd != 0)
		registers[rd] <= datain;
end

assign rval1 = rs1 == 0 ? 32'd0 : registers[rs1];
assign rval2 = rs2 == 0 ? 32'd0 : registers[rs2];
assign rval3 = rs3 == 0 ? 32'd0 : registers[rs3];

endmodule

// ==============================================================
// GPU main
// ==============================================================

module GPU (
	input wire clock,
	input wire reset,
	input wire [31:0] vsync,
	output logic videopage = 1'b0,
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
wire [31:0] rval3;
logic rwren = 1'b0;
logic [2:0] rs1;
logic [2:0] rs2;
logic [2:0] rs3;
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
	.rs3(rs3),
	.rd(rd),
	.wren(rwren),
	.datain(rdatain),
	.rval1(rval1),
	.rval2(rval2),
	.rval3(rval3) );

// ==============================================================
// Coarse rasterizer
// ==============================================================

logic signed [15:0] tileX0, tileY0;
logic signed [15:0] x0, y0, x1, y1, x2, y2;

// Tile crossing mask
wire tilemask;
//wire widetilemask;
wire [3:0] tilecoverage;

// Masks for individual wide and narrow tiles
wire [11:0] edgemask;

// Triangle facing flag
logic triFacing;

// Narrow mask for edge 0
LineRasterMask m0(reset, tileX0,         tileY0, x0,y0, x1,y1, edgemask[0]);
LineRasterMask m1(reset, tileX0+16'sd1,  tileY0, x0,y0, x1,y1, edgemask[1]);
LineRasterMask m2(reset, tileX0+16'sd2,  tileY0, x0,y0, x1,y1, edgemask[2]);
LineRasterMask m3(reset, tileX0+16'sd3,  tileY0, x0,y0, x1,y1, edgemask[3]);

// Narrow mask for edge 1
LineRasterMask m4(reset, tileX0,         tileY0, x1,y1, x2,y2, edgemask[4]);
LineRasterMask m5(reset, tileX0+16'sd1,  tileY0, x1,y1, x2,y2, edgemask[5]);
LineRasterMask m6(reset, tileX0+16'sd2,  tileY0, x1,y1, x2,y2, edgemask[6]);
LineRasterMask m7(reset, tileX0+16'sd3,  tileY0, x1,y1, x2,y2, edgemask[7]);

// Narrow mask for edge 2
LineRasterMask m8(reset,  tileX0,        tileY0, x2,y2, x0,y0, edgemask[8]);
LineRasterMask m9(reset,  tileX0+16'sd1, tileY0, x2,y2, x0,y0, edgemask[9]);
LineRasterMask m10(reset, tileX0+16'sd2, tileY0, x2,y2, x0,y0, edgemask[10]);
LineRasterMask m11(reset, tileX0+16'sd3, tileY0, x2,y2, x0,y0, edgemask[11]);

// Triangle facing
LineRasterMask tfc(reset, x2, y2, x0,y0, x1,y1, triFacing);

// Splitter
/*wire hassplittris;
wire signed [15:0] splitY;
TriangleSplitter trisplitter(.reset(reset), .y0(y0),.y1(y1),.y2(y2), .hassplittris(hassplittris), .splitY(splitY));*/

// Composite tile mask
// If any bit of a tile is set, an edge crosses it
// If all edges cross a tile, it's inside the triangle
assign tilemask = (|edgemask[3:0]) & (|edgemask[7:4]) & (|edgemask[11:8]);
assign tilecoverage = edgemask[3:0] & edgemask[7:4] & edgemask[11:8];

// ==============================================================
// Tile scan area min-max calculation
// ==============================================================

logic signed [15:0] minXval, maxXval;
logic signed [15:0] minYval, maxYval;

wire signed [15:0] minx01 = x0 < x1 ? x0 : x1;
wire signed [15:0] minx12 = x1 < x2 ? x1 : x2;
wire signed [15:0] maxx01 = x0 >= x1 ? x0 : x1;
wire signed [15:0] maxx12 = x1 >= x2 ? x1 : x2;
wire signed [15:0] maxx2z = x2 >= 255 ? 255 : x2;

wire signed [15:0] miny01 = y0 < y1 ? y0 : y1;
wire signed [15:0] miny12 = y1 < y2 ? y1 : y2;
wire signed [15:0] maxy01 = y0 >= y1 ? y0 : y1;
wire signed [15:0] maxy12 = y1 >= y2 ? y1 : y2;

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
		minXval = minXval < 16'sd0 ? 16'sd0 : minXval;
		maxXval = maxXval < 16'sd0 ? 16'sd0 : maxXval;
		minYval = minYval < 16'sd0 ? 16'sd0 : minYval;
		maxYval = maxYval < 16'sd0 ? 16'sd0 : maxYval;
	
		// Clamp to viewport max coords (255,191)
		minXval = minXval < 16'sd256 ? minXval : 16'sd255;
		maxXval = maxXval < 16'sd256 ? maxXval : 16'sd255;
		minYval = minYval < 16'sd192 ? minYval : 16'sd191;
		maxYval = maxYval < 16'sd192 ? maxYval : 16'sd191;
		
		// Truncate X min/max to nearest multiple of 4
		minXval = {minXval[15:2],2'b00};
		maxXval = {maxXval[15:2],2'b00};
		//minYval = {minYval[15:2],2'b00};
		//maxYval = {maxYval[15:2],2'b00};
	end
end

// ==============================================================
// Triangle setup for barycentric generation
// ==============================================================

// See: https://fgiesen.wordpress.com/2013/02/10/optimizing-the-basic-rasterizer/
/*wire signed [15:0] A01 = (y0 - y1)*4;
wire signed [15:0] B01 = x1 - x0;
wire signed [15:0] A12 = (y1 - y2)*4;
wire signed [15:0] B12 = x2 - x1;
wire signed [15:0] A20 = (y2 - y0)*4; // We move 4 steps to the right
wire signed [15:0] B20 = x0 - x2;

logic signed [31:0] w0_init, w1_init, w2_init;
wire signed [15:0] t0A = (minYval-y0);
wire signed [15:0] t1A = (minYval-y1);
wire signed [15:0] t2A = (minYval-y2);
wire signed [15:0] t0B = (minXval-x0);
wire signed [15:0] t1B = (minXval-x1);
wire signed [15:0] t2B = (minXval-x2);
wire signed [15:0] t0dy = (y1-y0);
wire signed [15:0] t1dy = (y2-y1);
wire signed [15:0] t2dy = (y0-y2);
wire signed [15:0] t0dx = (x0-x1);
wire signed [15:0] t1dx = (x1-x2);
wire signed [15:0] t2dx = (x2-x0);
always_comb begin
	if (reset) begin
		// 
	end else begin
		w0_init = t0A*t0dx + t0B*t0dy;
		w1_init = t1A*t1dx + t1B*t1dy;
		w2_init = t2A*t2dx + t2B*t2dy;
	end
end
logic signed [31:0] w0_row, w1_row, w2_row;
logic signed [31:0] w0, w1, w2;*/

// ==============================================================
// Main state machine
// ==============================================================

logic [31:0] vsyncrequestpoint = 32'd0;

always_ff @(posedge clock) begin
	if (reset) begin

		gpustate <= `GPUSTATEIDLE_MASK;
		vramwe <= 4'b0000;
		lanemask <= 12'h000;
		dmawe <= 4'b0000;
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
					cmd <= fifodout[2:0];			// command
													// fifodout[3] is unused for now
					rs1 <= fifodout[6:4];			// source register 1
					rs2 <= fifodout[9:7];			// source register 2 (==destination register)
					rd <= fifodout[9:7];			// destination register
					rs3 <= fifodout[12:10];			// source register 3 (overlaps immediates) 
					immshort <= fifodout[31:10];	// 22 bit immediate
					imm <= fifodout[31:4];			// 28 bit immediate
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
						{y0, x0} <= rval1;
						{y1, x1} <= rval2;
						{y2, x2} <= rval3;

						// DEBU: Solid color output during development
						// Full DWORD color from immshort, mask selects which pixels to write
						vramwriteword <= {immshort[10:3], immshort[10:3], immshort[10:3], immshort[10:3]};

						gpustate[`GPUSTATERASTERKICK] <= 1'b1;
					end

					`GPUCMD_SYSMEMOUT: begin
						dmaaddress <= rval2; // rs1: source
						dmawriteword <= rval1; // rs2: output word (same as rd)
						dmawe <= 4'b1111;
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end

					`GPUCMD_SETVPAGE: begin
						videopage <= rval1;
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
				tileX0 <= minXval; // tile width=4
				tileY0 <= minYval; // tile height=1 (but using 4 aligned at start)
				//w0_row <= w0_init;
				//w1_row <= w1_init;
				//w2_row <= w2_init;
				//w0 <= w0_init;
				//w1 <= w1_init;
				//w2 <= w2_init;
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
				if (tileY0 >= maxYval) begin
					// We have exhausted all rows to rasterize
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin

					// Output tile mask for this tile
					vramaddress <= {tileY0[7:0], tileX0[7:2]};
					// This effectively turns off writes for unoccupied tiles since tilecoverage == 0
					vramwe <= tilecoverage;
					//vramwriteword <= {w0[15:8], w0[15:8]+A12, w0[15:8]+A12+A12, w0[15:8]+A12+A12+A12};

					// Did we run out of tiles in this direction, or hit a zero tile mask?
					if (tileX0 >= maxXval) begin // | (~widetilemask)
						tileX0 <= minXval;
						// Step one tile down
						tileY0 <= tileY0 + 16'sd1; // tile height=1
						//w0_row <= w0_row + B12;
						//w1_row <= w1_row + B20;
						//w2_row <= w2_row + B01;
						//w0 <= w0_row + B12;
						//w1 <= w1_row + B20;
						//w2 <= w2_row + B01;
					end else begin
						// Step to next tile on scanline
						tileX0 <= tileX0 + 16'sd4;
						//w0 <= w0 + A12;
						//w1 <= w1 + A20;
						//w2 <= w2 + A01;
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
