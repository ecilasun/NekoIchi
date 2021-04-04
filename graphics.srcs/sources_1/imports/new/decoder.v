`default_nettype none
`timescale 1ns / 1ps

`include "cpuops.vh"
`include "aluops.vh"

module decoder(
	input wire clock,
	input wire reset,
	input wire [31:0] instruction,
	output reg [6:0] opcode,
	output reg [4:0] aluop,
	output reg [4:0] rs1,
	output reg [4:0] rs2,
	output reg [4:0] rd,
	output reg [2:0] func3,
	output reg [6:0] func7,
	output reg [31:0] imm,
	output reg [`CPUSTAGECOUNT-1:0] nextstage,
	output reg wren,
	output reg selectimmedasrval2);

always @(*) begin

	if (reset) begin

        wren = 1'b0;
		opcode = 7'd0;
		rs1 = 5'd0;
		rs2 = 5'd0;
		rd = 5'd0;
		func3 = 3'd0;
		func7 = 7'd0;
		imm = 32'd0;
		selectimmedasrval2 = 1'b0;
		aluop = `ALU_NONE;
		nextstage = `CPURETIREINSTRUCTION_MASK;

	end else begin

		opcode = instruction[6:0];
		rs1 = instruction[19:15];
		rs2 = instruction[24:20];
		rd = instruction[11:7];
		func3 = instruction[14:12];
		func7 = instruction[31:25];
		selectimmedasrval2 = opcode==`OPCODE_OP_IMM ? 1'b1 : 1'b0;

		case (instruction[6:0])
			`OPCODE_OP: begin
				wren = 1'b1;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				if (instruction[25]==1'b0) begin // Not M extension
					case (func3)
						3'b000: aluop = func7[5] == 1'b0 ? `ALU_ADD : `ALU_SUB;
						3'b001: aluop = `ALU_SLL;
						3'b010: aluop = `ALU_SLT;
						3'b011: aluop = `ALU_SLTU;
						3'b100: aluop = `ALU_XOR;
						3'b101: aluop = func7[5] == 1'b0 ? `ALU_SRL : `ALU_SRA;
						3'b110: aluop = `ALU_OR;
						3'b111: aluop = `ALU_AND;
					endcase
				end else begin
					case (func3)
						3'b000, 3'b001, 3'b010, 3'b011: aluop = `ALU_MUL;
						3'b100, 3'b101: aluop = `ALU_DIV;
						3'b110, 3'b111: aluop = `ALU_REM;
						//default: aluop = `ALU_NONE;
					endcase
				end
				imm = 32'd0;
			end

			`OPCODE_OP_IMM: begin
				wren = 1'b1;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				case (func3)
					3'b000: aluop = `ALU_ADD; // NOTE: No immediate mode sub exists
					3'b001: aluop = `ALU_SLL;
					3'b010: aluop = `ALU_SLT;
					3'b011: aluop = `ALU_SLTU;
					3'b100: aluop = `ALU_XOR;
					3'b101: aluop = func7[5] == 1'b0 ? `ALU_SRL : `ALU_SRA;
					3'b110: aluop = `ALU_OR;
					3'b111: aluop = `ALU_AND;
				endcase
				imm = {{20{instruction[31]}},instruction[31:20]};
			end

			`OPCODE_LUI: begin
				wren = 1'b1;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				aluop = `ALU_NONE;
				imm = {instruction[31:12],12'd0};
			end

			`OPCODE_STORE: begin
				wren = 1'b0;
				nextstage = `CPUSTORE_MASK;
				aluop = `ALU_NONE;
				imm = {{20{instruction[31]}},instruction[31:25],instruction[11:7]};
			end

			`OPCODE_LOAD: begin
				wren = 1'b1;
				nextstage = `CPULOADWAIT_MASK;
				aluop = `ALU_NONE;
				imm = {{20{instruction[31]}},instruction[31:20]};
			end

			`OPCODE_JAL: begin
				wren = 1'b1;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				aluop = `ALU_NONE;
				imm = {{11{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};
			end

			`OPCODE_JALR: begin
				wren = 1'b1;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				aluop = `ALU_NONE;
				imm = {{20{instruction[31]}},instruction[31:20]};
			end

			`OPCODE_BRANCH: begin
				wren = 1'b0;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				case (func3)
					3'b000: aluop = `ALU_EQ;
					3'b001: aluop = `ALU_NE;
					3'b100: aluop = `ALU_L;
					3'b101: aluop = `ALU_GE;
					3'b110: aluop = `ALU_LU;
					3'b111: aluop = `ALU_GEU;
					default: aluop = `ALU_NONE;
				endcase
				imm = {{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0};
			end

			`OPCODE_AUPC: begin
				wren = 1'b1;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				aluop = `ALU_NONE;
				imm = {instruction[31:12],12'd0};
			end

			`OPCODE_FENCE: begin
				wren = 1'b0;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				aluop = `ALU_NONE;
				imm = 32'd0;
			end

			`OPCODE_SYSTEM: begin
				wren = 1'b0;
				nextstage = `CPURETIREINSTRUCTION_MASK;
				aluop = `ALU_NONE;
				imm = 32'd0;
			end
			
			default: begin
				// TODO: These are illegal / unhandled instructions, signal EXCEPTION_ILLEGAL_INSTRUCTION
				wren = 1'b0;
				nextstage = `CPUFETCH_MASK; // OR `CPUEXCEPTION_MASK
				aluop = `ALU_NONE;
				imm = 32'd0;
			end
		endcase

	end

end

endmodule
