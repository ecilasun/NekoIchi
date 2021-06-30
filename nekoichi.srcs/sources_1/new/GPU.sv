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
	output logic [14:0] vramaddress,
	output logic [3:0] vramwe,
	output logic [31:0] vramwriteword,
	output logic [12:0] lanemask,
	// SYSRAM DMA channel
	output logic [31:0] dmaaddress,
	output logic [31:0] dmawriteword,
	output logic [3:0] dmawe,
	input wire [31:0] dma_data,
	output logic palettewe = 1'b0,
	output logic [7:0] paletteaddress,
	output logic [31:0] palettedata );

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
logic [14:0] dmacount;
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
// Main state machine
// ==============================================================

logic [31:0] vsyncrequestpoint = 32'd0;

always_ff @(posedge clock) begin
	if (reset) begin

		gpustate <= `GPUSTATEIDLE_MASK;
		vramwe <= 4'b0000;
		lanemask <= 13'd0;
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
				lanemask <= 13'd0;
				// And DMA writes
				dmawe <= 4'b0000;
				// Stop palette writes
				palettewe <= 1'b0;

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

					`GPUCMD_SETPALENT: begin
						paletteaddress <= immshort[7:0];
						palettedata <= rval1;
						palettewe <= 1'b1;
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end

					`GPUCMD_CLEAR: begin
						vramaddress <= 15'd0;
						vramwriteword <= rval1;
						// Enable all 4 bytes since clears are 32bit per write
						vramwe <= 4'b1111;
						lanemask <= 13'h1FFF; // Turn on all lanes for parallel writes
						gpustate[`GPUSTATECLEAR] <= 1'b1;
					end

					`GPUCMD_SYSDMA: begin
						dmaaddress <= rval1; // rs1: source
						dmacount <= 15'd0;
						dmawe <= 4'b0000; // Reading from SYSRAM
						gpustate[`GPUSTATEDMAKICK] <= 1'b1;
					end

					`GPUCMD_UNUSED: begin
						// NOOP
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end

					`GPUCMD_GMEMOUT: begin
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
				if (vramaddress == 15'h800) begin // (512*16/4) (DWORD addresses) -> 0x800 (2048, size of one slice of DWORDs, of which there are 13)
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin
					vramaddress <= vramaddress + 15'd1;
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
				if (dmacount == immshort[14:0]) begin
					// DMA done
					vramwe <= 4'b0000;
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin
					// Write the previous DWORD to absolute address
					vramaddress <= rval2[14:0] + dmacount;
					vramwriteword <= dma_data;
					
					if (immshort[15]==1'b1) begin
						// Zero-masked DMA
						vramwe <= {|dma_data[31:24], |dma_data[23:16], |dma_data[15:8], |dma_data[7:0]};
					end else begin
						// Unmasked DM
						vramwe <= 4'b1111;
					end

					// Step to next DWORD to read
					dmaaddress <= dmaaddress + 32'd4;
					dmacount <= dmacount + 15'd1;
					gpustate[`GPUSTATEDMA] <= 1'b1;
				end
			end

			default: begin
				// noop
			end

		endcase
	end
end
	
endmodule
