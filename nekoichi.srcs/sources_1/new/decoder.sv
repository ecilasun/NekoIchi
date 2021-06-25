`timescale 1ns / 1ps

`include "cpuops.vh"
`include "aluops.vh"

module decoder(
	input wire clock,
	input wire enable,
	input wire [31:0] instruction,		// Raw input instruction
	output logic [6:0] opcode,			// Current instruction class
	output logic [4:0] aluop,			// Current ALU op
	output logic rwen,					// Integer register writes enabled
	output logic fwen,					// Flaot register writes enabled
	output logic [2:0] func3,			// Sub-instruction
	output logic [6:0] func7,			// Sub-instruction
	output logic [11:0] func12,			// Sub-instruction
	output logic [4:0] rs1,				// Source register one
	output logic [4:0] rs2,				// Source register two
	output logic [4:0] rs3,				// Used by fused multiplyadd/sub
	output logic [4:0] rd,				// Destination register
	output logic [11:0] csrindex,		// Index of selected CSR register
	output logic [31:0] immed,			// Unpacked immediate integer value
	output logic selectimmedasrval2		// Select rval2 or unpacked integer during EXEC
);

always_ff @(posedge clock) begin

	if (enable) begin
		opcode <= instruction[6:0];
		rs1 <= instruction[19:15];
		rs2 <= instruction[24:20];
		rs3 <= instruction[31:27];
		rd <= instruction[11:7];
		func3 <= instruction[14:12];
		func7 <= instruction[31:25];
		func12 <= instruction[31:20];
		selectimmedasrval2 <= instruction[6:0]==`OPCODE_OP_IMM ? 1'b1 : 1'b0;
		csrindex <= {instruction[31:25], instruction[24:20]};

		immed <= 32'd0;
		rwen <= 1'b0;
		fwen <= 1'b0;
		aluop <= `ALU_NONE;

		unique case (instruction[6:0])
			`OPCODE_OP: begin
				rwen <= 1'b1;
				if (instruction[25]==1'b0) begin
					// Base integer ALU instructions
					unique case (instruction[14:12])
						3'b000: aluop <= instruction[30] == 1'b0 ? `ALU_ADD : `ALU_SUB;
						3'b001: aluop <= `ALU_SLL;
						3'b010: aluop <= `ALU_SLT;
						3'b011: aluop <= `ALU_SLTU;
						3'b100: aluop <= `ALU_XOR;
						3'b101: aluop <= instruction[30] == 1'b0 ? `ALU_SRL : `ALU_SRA;
						3'b110: aluop <= `ALU_OR;
						3'b111: aluop <= `ALU_AND;
					endcase
				end else begin
					// M-extension instructions
					unique case (instruction[14:12])
						3'b000, 3'b001, 3'b010, 3'b011: aluop <= `ALU_MUL;
						3'b100, 3'b101: aluop <= `ALU_DIV;
						3'b110, 3'b111: aluop <= `ALU_REM;
					endcase
				end
			end

			`OPCODE_OP_IMM: begin
				immed <= {{20{instruction[31]}},instruction[31:20]};
				rwen <= 1'b1;
				unique case (instruction[14:12])
					3'b000: aluop <= `ALU_ADD; // NOTE: No immediate mode sub exists
					3'b001: aluop <= `ALU_SLL;
					3'b010: aluop <= `ALU_SLT;
					3'b011: aluop <= `ALU_SLTU;
					3'b100: aluop <= `ALU_XOR;
					3'b101: aluop <= instruction[30] == 1'b0 ? `ALU_SRL : `ALU_SRA;
					3'b110: aluop <= `ALU_OR;
					3'b111: aluop <= `ALU_AND;
				endcase
			end

			`OPCODE_LUI: begin
				immed <= {instruction[31:12], 12'd0};
				rwen <= 1'b1;
			end

			`OPCODE_STORE: begin
				immed <= {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
			end

			`OPCODE_FLOAT_LDW, `OPCODE_LOAD: begin
				// NOTE: We have to write to a register, but will handle it in LOAD state not to cause double-writes
				immed <= {{20{instruction[31]}}, instruction[31:20]};
			end

			`OPCODE_JAL: begin
				immed <= {{11{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};
				rwen <= 1'b1;
			end

			`OPCODE_JALR: begin
				immed <= {{20{instruction[31]}}, instruction[31:20]};
				rwen <= 1'b1;
			end

			`OPCODE_BRANCH: begin
				immed <= {{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
				unique case (instruction[14:12])
					3'b000: aluop <= `ALU_EQ;
					3'b001: aluop <= `ALU_NE;
					3'b100: aluop <= `ALU_L;
					3'b101: aluop <= `ALU_GE;
					3'b110: aluop <= `ALU_LU;
					3'b111: aluop <= `ALU_GEU;
				endcase
			end
	
			`OPCODE_AUPC: begin
				immed <= {instruction[31:12], 12'd0};
				rwen <= 1'b1;
			end

			`OPCODE_FENCE: begin
				//
			end

			`OPCODE_SYSTEM: begin
				immed <= {27'd0, instruction[19:15]};
				// Register write flag depends on func3
				rwen <= (instruction[14:12] == 3'b000) ? 1'b0 : 1'b1;
			end

			`OPCODE_FLOAT_OP: begin
				unique case (instruction[31:25])
					`FADD,`FSUB,`FMUL,`FDIV,`FSGNJ,`FCVTWS,`FCVTSW,`FSQRT,`FEQ,`FMIN: begin // FCVTWUS and FCVTSWU implied by FCVTWS and FCVTSW, FSGNJ includes FSGNJN and FSGNJX, FEQ includes FLT and FLE, FMIN includes FMAX
						// For fcvtws (float to int) and FEQ/FLT/FLE, result is written back to integer register
						// All other output goes into float registers 
						rwen <= ((instruction[31:25] == `FCVTWS) | (instruction[31:25] == `FEQ)) ? 1'b1 : 1'b0;
						fwen <= ((instruction[31:25] == `FCVTWS) | (instruction[31:25] == `FEQ)) ? 1'b0 : 1'b1; // func7
					end
					`FMVXW: begin // move from float register to int register
						// NOTE: also overlaps with `FCLASS, check for func3==000 to make sure it's FMVXW (FCLASS has func3==001)
						rwen <= 1'b1;
					end
					`FMVWX: begin // move from int register to float register
						fwen <= 1'b1;
					end
				endcase
			end

			`OPCODE_FLOAT_MSUB, `OPCODE_FLOAT_MADD, `OPCODE_FLOAT_NMSUB, `OPCODE_FLOAT_NMADD: begin
				// Float writes are deferred to the end of CPUFFSTALL state
			end

			`OPCODE_FLOAT_STW: begin
				immed <= {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
			end
			
			default: begin
			end

		endcase
	end else begin
		// 
	end
end

endmodule
