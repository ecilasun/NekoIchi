`timescale 1ns / 1ps

`include "gpuops.vh"

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
	if (wren & rd != 0)
		registers[rd] <= datain;
end

assign rval1 = rs1 == 0 ? 32'd0 : registers[rs1];
assign rval2 = rs2 == 0 ? 32'd0 : registers[rs2];

endmodule

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
	
logic [`GPUOPWIDTH-1:0] gpustate = `GPUSTATEIDLE_MASK;
logic [31:0] commandlatch = 32'd0;

logic [31:0] rdatain;
wire [31:0] rval1;
wire [31:0] rval2;
logic rwren = 1'b0;
logic [2:0] rs1;
logic [2:0] rs2;
logic [2:0] rd;
logic [3:0] cmd;
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
	
always_comb begin
	cmd = commandlatch[3:0];		// command
	rs1 = commandlatch[6:4];		// source register 1
	rs2 = commandlatch[9:7];		// source register 2 (==destination register)
	rd = commandlatch[9:7];			// destination register
	immshort = commandlatch[31:10];	// 22 bit immediate
	imm = commandlatch[31:4];		// 28 bit immediate
end

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
					4'b0000: begin // NOOP/VSYNC
						if (vsync)
							gpustate[`GPUSTATEIDLE] <= 1'b1;
						else
							gpustate[`GPUSTATEEXEC] <= 1'b1;
					end
					4'b0001: begin // REGSETLOW/HI
						rwren <= 1'b1;
						if (rs1==3'd0) // set LOW if source register is zero register
							rdatain <= {10'd0, immshort};
						else // set HIGH if source register is not zero register
							rdatain <= {immshort[9:0], rval1[21:0]};
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b0010: begin // MEMWRITE
						vramaddress <= immshort[17:4];
						vramwriteword <= rval1;
						vramwe <= immshort[3:0];
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b0011: begin // CLEAR
						vramaddress <= 14'd0;
						vramwriteword <= rval1;
						// Enable all 4 bytes since clears are 32bit per write
						vramwe <= 4'b1111;
						lanemask <= 12'hFFF; // Turn on all lanes for parallel writes
						gpustate[`GPUSTATECLEAR] <= 1'b1;
					end
					4'b0100: begin // SYSDMA
						dmaaddress <= rval1[14:0]; // rs1: source
						dmacount <= 14'd0;
						dmawe <= 4'b0000; // Reading from SYSRAM
						gpustate[`GPUSTATEDMA] <= 1'b1;
					end
					4'b0101: begin //
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b0110: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b0111: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b1000: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b1001: begin //
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b1010: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b1011: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b1100: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b1101: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b1110: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b1111: begin // 
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

			gpustate[`GPUSTATEDMA]: begin // SYSDMA
				if (dmacount == immshort[13:0]) begin
					// DMA done
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin

					// Write the previous DWORD to absolute address
					vramwriteword <= dma_data;
					vramaddress <= rval2[13:0] + dmacount;
					vramwe <= 4'b1111;

					// Step to next DWORD to read
					dmaaddress <= dmaaddress + 15'd1;

					dmacount <= dmacount + 14'd1;
					gpustate[`GPUSTATEDMA] <= 1'b1;
				end
			end
			
		endcase
	end
end
	
endmodule
