`timescale 1ns / 1ps

`include "aluops.vh"

module ALU(
	output logic [31:0] aluout,
	input wire [2:0] func3,
	input wire [31:0] val1,
	input wire [31:0] val2,
	input wire [4:0] aluop );

// Integer ALU
always_comb begin

	unique case (aluop)
		// Integer ops
		`ALU_ADD:  begin aluout = val1 + val2; end
		`ALU_SUB:  begin aluout = val1 + (~val2 + 32'd1); end
		`ALU_SLL:  begin aluout = val1 << val2[4:0]; end
		`ALU_SLT:  begin aluout = $signed(val1) < $signed(val2) ? 32'd1 : 32'd0; end
		`ALU_SLTU: begin aluout = val1 < val2 ? 32'd1 : 32'd0; end
		`ALU_XOR:  begin aluout = val1 ^ val2; end
		`ALU_SRL:  begin aluout = val1 >> val2[4:0]; end
		`ALU_SRA:  begin aluout = $signed(val1) >>> val2[4:0]; end
		`ALU_OR:   begin aluout = val1 | val2; end
		`ALU_AND:  begin aluout = val1 & val2; end
		default:  begin aluout = 1'b0; end
	endcase

end

endmodule
