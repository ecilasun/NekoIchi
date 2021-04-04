`default_nettype none
`timescale 1ns / 1ps

`include "cpuops.vh"

module instructiondecompressor(
    input wire [15:0] instr_highword,
    input wire [15:0] instr_lowword,
    output reg is_compressed,
    output reg [31:0] fullinstr
);

always @ (*) begin
	if (instr_lowword[1:0] == 2'b11) begin

		// Already decompressed
		is_compressed = 1'b0;

		fullinstr = {instr_highword, instr_lowword};

	end else begin

		// Needs decompression
		is_compressed = 1'b1;
		
		case ({instr_lowword[15:13], instr_lowword[1:0]})
			`CADDI4SPN: begin // rd = (zero extended nonzero immediate)*4+sp
				if (instr_lowword[12:2] != 11'h0 && instr_lowword[12:5] != 8'h0)
					fullinstr = { 2'b00, instr_lowword[10:7], instr_lowword[12:11], instr_lowword[5], instr_lowword[6], 2'b00, 5'd2, 3'b000, 2'b01, instr_lowword[4:2], `ADDI }; // CADDI4SPN
			end
			
			`CLW: begin // load word
				fullinstr = { 5'b00000, instr_lowword[5], instr_lowword[12:10], instr_lowword[6], 2'b00, 2'b01, instr_lowword[9:7], 3'b010, 2'b01, instr_lowword[4:2], `LW }; // CLW
			end
			
			`CSW: begin // store word
				fullinstr = { 5'b00000, instr_lowword[5], instr_lowword[12], 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b010, instr_lowword[11:10], instr_lowword[6], 2'b00, `SW }; // CSW
			end
			
			`CNOP: begin // noop == addi x0,x0,0
				if (instr_lowword[12:2] == 11'h0)
					fullinstr = { 25'h0, `ADDI }; // CNOP
				else if (instr_lowword[12] != 1'b0 || instr_lowword[6:2] != 5'h0)
					fullinstr = { {7{instr_lowword[12]}}, instr_lowword[6:2], instr_lowword[11:7], 3'b000, instr_lowword[11:7], `ADDI }; // CADDI
			end
			
			`CJAL: begin // jump and link register
				fullinstr = { instr_lowword[12], instr_lowword[8], instr_lowword[10:9], instr_lowword[6], instr_lowword[7], instr_lowword[2], instr_lowword[11], instr_lowword[5:3], instr_lowword[12], {8{instr_lowword[12]}}, 5'd1, `JAL }; // CJAL
			end
			
			`CLI: begin // load immediate
				if (instr_lowword[11:7] != 5'd0)
					fullinstr = { {7{instr_lowword[12]}}, instr_lowword[6:2], 5'd0, 3'b000, instr_lowword[11:7], `ADDI }; // CLI
			end
			
			`CADDI16SP: begin
				if ((instr_lowword[12] != 1'b0 || instr_lowword[6:2] != 5'h0) && instr_lowword[11:7] != 5'd0) begin
					if (instr_lowword[11:7] == 5'd2)
						fullinstr = { {3{instr_lowword[12]}}, instr_lowword[4], instr_lowword[3], instr_lowword[5], instr_lowword[2], instr_lowword[6], 4'b0000, 5'd2, 3'b000, 5'd2, `ADDI }; // CADDI16SP
					else
						fullinstr = { {15{instr_lowword[12]}}, instr_lowword[6:2], instr_lowword[11:7], 7'b0110111 }; // CLUI
				end
			end
			
			`CSRLI: begin // shift right logical immediate
				if (instr_lowword[12:10] == 3'b011 && instr_lowword[6:5] == 2'b00)
					fullinstr = { 7'b0100000, 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b000, 2'b01, instr_lowword[9:7], `SUB }; // CSUB
				else if (instr_lowword[12:10] == 3'b011 && instr_lowword[6:5] == 2'b01)
					fullinstr = { 7'b0000000, 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b100, 2'b01, instr_lowword[9:7], `XOR }; // CXOR
				else if (instr_lowword[12:10] == 3'b011 && instr_lowword[6:5] == 2'b10)
					fullinstr = { 7'b0000000, 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b110, 2'b01, instr_lowword[9:7], `OR }; // COR
				else if (instr_lowword[12:10] == 3'b011 && instr_lowword[6:5] == 2'b11)
					fullinstr = { 7'b0000000, 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b111, 2'b01, instr_lowword[9:7], `AND }; // CAND
				else if (instr_lowword[11:10] == 2'b10)
					fullinstr = { {7{instr_lowword[12]}}, instr_lowword[6:2], 2'b01, instr_lowword[9:7], 3'b111, 2'b01, instr_lowword[9:7], `ANDI }; // CANDI
				else if (instr_lowword[12] == 1'b0 && instr_lowword[6:2] == 5'h0)
					fullinstr = 32'h0; // UNDEF!
				else if (instr_lowword[11:10] == 2'b00)
					fullinstr = { 7'b0000000, instr_lowword[6:2], 2'b01, instr_lowword[9:7], 3'b101, 2'b01, instr_lowword[9:7], `SRLI }; // CSRLI
				else if (instr_lowword[11:10] == 2'b01)
					fullinstr = { 7'b0100000, instr_lowword[6:2], 2'b01, instr_lowword[9:7], 3'b101, 2'b01, instr_lowword[9:7], `SRAI }; // CSRAI
			end
			
			`CJ: begin // jump
				fullinstr = { instr_lowword[12], instr_lowword[8], instr_lowword[10:9], instr_lowword[6], instr_lowword[7], instr_lowword[2], instr_lowword[11], instr_lowword[5:3], instr_lowword[12], {8{instr_lowword[12]}}, 5'd0, `JAL }; // CJ
			end
			
			`CBEQZ: begin // branch if equal to zero
				fullinstr = { {4{instr_lowword[12]}}, instr_lowword[6], instr_lowword[5], instr_lowword[2], 5'd0, 2'b01, instr_lowword[9:7], 3'b000, instr_lowword[11], instr_lowword[10], instr_lowword[4], instr_lowword[3], instr_lowword[12], `BEQ }; // CBEQZ
			end
			
			`CBNEZ: begin // branch if not equal to zero
				fullinstr = { {4{instr_lowword[12]}}, instr_lowword[6], instr_lowword[5], instr_lowword[2], 5'd0, 2'b01, instr_lowword[9:7], 3'b001, instr_lowword[11], instr_lowword[10], instr_lowword[4], instr_lowword[3], instr_lowword[12], `BNE }; // CBNEZ
			end
			
			`CSLLI: begin // shift left logical immediate
				if (instr_lowword[11:7] != 5'd0)
					fullinstr = { 7'b0000000, instr_lowword[6:2], instr_lowword[11:7], 3'b001, instr_lowword[11:7], `SLLI }; // CSLLI
			end
			
			`CLWSP: begin // load word relative to stack pointer
				if (instr_lowword[11:7] != 5'h0) // rd!=0
					fullinstr = { 4'b0000, instr_lowword[3:2], instr_lowword[12], instr_lowword[6:4], 2'b0, 5'd2, 3'b010, instr_lowword[11:7], `LW }; // CLWSP
			end
			
			`CSWSP: begin // store word relative to stack pointer
				fullinstr = { 4'b0000, instr_lowword[8:7], instr_lowword[12], instr_lowword[6:2], 5'd2, 3'b010, instr_lowword[11:9], 2'b00, `SW }; // CSWSP
			end
			
			`CJR: begin // jump register
				if (instr_lowword[6:2] == 5'd0) begin
					if (instr_lowword[11:7] == 5'h0) begin
						if (instr_lowword[12] == 1'b1)
							fullinstr = { 11'h0, 1'b1, 13'h0, `EBREAK }; // CEBREAK
					end else if (instr_lowword[12])
						fullinstr = { 12'h0, instr_lowword[11:7], 3'b000, 5'd1, `JALR }; // CJALR
				else
					fullinstr = { 12'h0, instr_lowword[11:7], 3'b000, 5'd0, `JALR }; // CJR
				end else if (instr_lowword[11:7] != 5'h0) begin
					if (instr_lowword[12] == 1'b0)
						fullinstr = { 7'b0000000, instr_lowword[6:2], 5'd0, 3'b000, instr_lowword[11:7], `ADD }; // CMV
					else
						fullinstr = { 7'b0000000, instr_lowword[6:2], instr_lowword[11:7], 3'b000, instr_lowword[11:7], `ADD }; // CADD
				end
			end
			
			default: begin
				fullinstr = 32'd0; // UNDEF
			end
		endcase

	end
end

endmodule
