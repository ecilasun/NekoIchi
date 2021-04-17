`timescale 1ns / 1ps

`include "gpuops.vh"

module gpuregisterfile(
	input wire reset,
	input wire clock,
	input wire [2:0] rs,
	input wire [2:0] rd,
	input wire wren, 
	input wire [31:0] datain,
	output wire [31:0] rval );

logic [31:0] registers[0:7]; 

always @(posedge clock) begin
	if (wren & rd != 0)
		registers[rd] <= datain;
end

assign rval = rs == 0 ? 32'd0 : registers[rs];

endmodule

module GPU (
	input wire clock,
	input wire reset,
	input wire [31:0] gpucommand,
	input wire gpupulse,
	output logic gpuready = 1'b1,
	output logic [13:0] vramaddress,
	output logic [3:0] vramwe,
	output logic [31:0] vramdata );
	
logic [`GPUOPWIDTH-1:0] gpustate = `GPUSTATEIDLE_MASK;
logic [31:0] commandlatch = 32'd0;

logic [31:0] rdatain = 32'd0;
wire [31:0] rval;
logic rwren = 1'b0;
logic [2:0] rs;
logic [2:0] rd;
logic [3:0] cmd;
logic [21:0] immshort;
logic [27:0] imm;
gpuregisterfile gpuregs(
	.reset(reset),
	.clock(clock),
	.rs(rs),
	.rd(rd),
	.wren(rwren),
	.datain(rdatain),
	.rval(rval) );
	
always_comb begin
	if (gpupulse == 1'b1)
		commandlatch = gpucommand;
end

always_comb begin

	// Instruction forms
	// Form 0
	// [iiiiiiiiiiiiiiiiii iiii][ddd][sss][cccc]
	// Form 1
	// [iiiiiiiiiiiiiiiiiiiiiiiiiiii][cccc]

	cmd = commandlatch[3:0];		// command
	rs = commandlatch[6:4];			// source register
	rd = commandlatch[9:7];			// destination register
	immshort = commandlatch[31:10];	// 22 bit immediate
	imm = commandlatch[31:4];		// 28 bit immediate

	// REGSETLOW: Set lower 22 bits of register sd to V if SSS==0
	// [VVVVVVVVVVVVVVVVVV VVVV][DDD][SSS][0001]

	// REGSETHI: Set higher 10 bits of register sd to V if SSS!=0
	// [------------VVVVVV VVVV][DDD][SSS][0001]	

	// MEMWRITE: Write contents of sr to address A
	// [----AAAAAAAAAAAAAA WWWW][---][SSS][0010]

	// CLEAR: Clear the video memory using contents of register rs
	// [------------------ ----][---][SSS][0011]
end

always_ff @(posedge clock) begin
	if (reset) begin

		gpuready <= 1'b1;
		gpustate <= `GPUSTATEIDLE_MASK;
		vramaddress <= 14'd0;
		vramdata <= 32'd0;
		vramwe <= 4'b0000;

	end else begin
	
		gpustate <= `GPUSTATENONE_MASK;
	
		unique case (1'b1)
		
			gpustate[`GPUSTATEIDLE]: begin
				// Stop writes to memory and registers
				vramwe <= 4'b0000;
				rwren <= 1'b0;

				// Check for pulse, execute if there's an incoming command
				if (gpupulse) begin
					gpustate[`GPUSTATEEXEC] <= 1'b1;
					gpuready <= 1'b0;
				end else begin
					gpustate[`GPUSTATEIDLE] <= 1'b1;
					gpuready <= 1'b1;
				end
			end
	
			// Command execute state
			gpustate[`GPUSTATEEXEC]: begin
				gpuready <= 1'b1;
				unique case (cmd) // 4'bxxxx
					4'b0000: begin // NOOP
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b0001: begin // REGSETLOW/HI
						rwren <= 1'b1;
						if (rs==3'd0) // set LOW if source register is zero register
							rdatain <= {rval[31:10], immshort};
						else // set HIGH if source register is not zero register
							rdatain <= {immshort[9:0], rval[21:0]};
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b0010: begin // MEMWRITE
						vramaddress <= immshort[17:4];
						vramdata <= rval;
						vramwe <= immshort[3:0];
						gpustate[`GPUSTATEIDLE] <= 1'b1;
					end
					4'b0011: begin // CLEAR
						vramaddress <= 14'd0;
						vramdata <= rval;
						vramwe <= 4'b1111;
						gpuready <= 1'b0; 
						gpustate[`GPUSTATECLEAR] <= 1'b1;
					end
					4'b0100: begin // 
						gpustate[`GPUSTATEIDLE] <= 1'b1;
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
				if (vramaddress == 14'h3000) begin // 256*192/4 (DWORD address)
					gpuready <= 1'b1;
					gpustate[`GPUSTATEIDLE] <= 1'b1;
				end else begin
					vramaddress <= vramaddress + 14'd1;
					// Loop in same state
					gpustate[`GPUSTATECLEAR] <= 1'b1;
					gpuready <= 1'b0;
				end
			end

			gpustate[`GPUSTATEDMA]: begin // Unused for now
				gpuready <= 1'b1;
				gpustate[`GPUSTATEIDLE] <= 1'b1;
			end
			
		endcase
	end
end
	
endmodule
