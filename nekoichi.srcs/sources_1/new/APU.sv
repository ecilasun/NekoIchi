`timescale 1ns / 1ps

`include "cpuops.vh"
`include "apuops.vh"


// ==============================================================
// APU register file
// ==============================================================

module apuregisterfile(
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
	registers[7] <= 32'h00000000; // TODO: This one could be 'samples left to play' so we can APUCMD_AMEMOUT?
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
// APU main
// ==============================================================

module APU (
	input wire clock,
	input wire reset,
	// APU FIFO
	input wire fifoempty,
	input wire [31:0] fifodout,
	input wire fifdoutvalid,
	output logic fiford_en,
	// ARAM DMA channel
	output logic [31:0] dmaaddress,
	output logic [31:0] dmawriteword,
	output logic [3:0] dmawe,
	input wire [31:0] dma_data );

logic [`APUSTATEBITS-1:0] apustate = `APUSTATEIDLE_MASK;

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
apuregisterfile apuregs(
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

		apustate <= `APUSTATEIDLE_MASK;
		dmawe <= 4'b0000;
		fiford_en <= 1'b0;

	end else begin
	
		apustate <= `APUSTATENONE_MASK;
	
		unique case (1'b1)
		
			apustate[`APUSTATEIDLE]: begin
				// Stop writes to registers and DMA
				rwren <= 1'b0;
				dmawe <= 4'b0000;

				// See if there's something on the fifo
				if (~fifoempty) begin
					fiford_en <= 1'b1;
					apustate[`APUSTATELATCHCOMMAND] <= 1'b1;
				end else begin
					apustate[`APUSTATEIDLE] <= 1'b1;
				end
			end

			apustate[`APUSTATELATCHCOMMAND]: begin
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
					apustate[`APUSTATEEXEC] <= 1'b1;
				end else begin
					// Data is not available yet, spin
					apustate[`APUSTATELATCHCOMMAND] <= 1'b1;
				end
			end

			// Command execute state
			apustate[`APUSTATEEXEC]: begin
				unique case (cmd)
					`APUCMD_UNUSED0: begin
						apustate[`APUSTATEIDLE] <= 1'b1;
					end

					`APUCMD_SETREG: begin
						rwren <= 1'b1;
						if (rs1==3'd0) // set LOW if source register is zero register
							rdatain <= {10'd0, immshort};
						else // set HIGH if source register is not zero register
							rdatain <= {immshort[9:0], rval1[21:0]};
						apustate[`APUSTATEIDLE] <= 1'b1;
					end

					`APUCMD_UNUSED2: begin
						apustate[`APUSTATEIDLE] <= 1'b1;
					end

					`APUCMD_UNUSED3: begin
						apustate[`APUSTATEIDLE] <= 1'b1;
					end

					`APUCMD_UNUSED4: begin
						apustate[`APUSTATEIDLE] <= 1'b1;
					end

					`APUCMD_UNUSED5: begin
						apustate[`APUSTATEIDLE] <= 1'b1;
					end

					`APUCMD_AMEMOUT: begin
						dmaaddress <= rval2; // rs1: source
						dmawriteword <= rval1; // rs2: output word (same as rd)
						dmawe <= 4'b1111;
						apustate[`APUSTATEIDLE] <= 1'b1;
					end

					`APUCMD_UNUSED7: begin
						apustate[`APUSTATEIDLE] <= 1'b1;
					end
				endcase
			end
			
			apustate[`APUSTATEDMAKICK]: begin
				// Delay for first read
				dmaaddress <= dmaaddress + 32'd4;
				apustate[`APUSTATEDMA] <= 1'b1;
			end

			apustate[`APUSTATEDMA]: begin // SYSDMA
				if (dmacount == immshort[13:0]) begin
					// DMA done
					///vramwe <= 4'b0000; audio queue write enable
					apustate[`APUSTATEIDLE] <= 1'b1;
				end else begin
				
					// TODO: Write to audio output queue
					// TODO: Always provide number of samples left
					// TODO: Can this be a detached process on its own? No need to lock up
					// the APU for a DMA, while it could do other things (like volume control, fx, status check etc)

					// Write the previous DWORD to absolute address
					/*vramaddress <= rval2[13:0] + dmacount;
					vramwriteword <= dma_data;
					
					if (immshort[14]==1'b1) begin
						// Zero-masked DMA
						vramwe <= {|dma_data[31:24], |dma_data[23:16], |dma_data[15:8], |dma_data[7:0]};
					end else begin
						// Unmasked DM
						vramwe <= 4'b1111;
					end*/

					// Step to next DWORD to read
					dmaaddress <= dmaaddress + 32'd4;
					dmacount <= dmacount + 14'd1;
					apustate[`APUSTATEDMA] <= 1'b1;
				end
			end

			default: begin
				// noop
			end

		endcase
	end
end
	
endmodule
