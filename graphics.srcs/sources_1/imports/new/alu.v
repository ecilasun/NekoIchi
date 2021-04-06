`default_nettype none
`timescale 1ns / 1ps

`include "cpuops.vh"
`include "aluops.vh"

module ALU(
	input wire clock,
	input wire reset,
	output reg [31:0] aluout,
	input wire [2:0] func3,
	input wire [31:0] val1,
	input wire [31:0] val2,
	input wire [4:0] aluop);
// Integet ALU
always @(*) begin

    if (reset) begin

        aluout = 32'd0;

    end else begin

        case (aluop)
            // I
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
    
            // BRANCH ALU
            `ALU_EQ:   begin aluout = val1 == val2 ? 32'd1 : 32'd0; end
            `ALU_NE:   begin aluout = val1 != val2 ? 32'd1 : 32'd0; end
            `ALU_L:    begin aluout = $signed(val1) < $signed(val2) ? 32'd1 : 32'd0; end
            `ALU_GE:   begin aluout = $signed(val1) >= $signed(val2) ? 32'd1 : 32'd0; end
            `ALU_LU:   begin aluout = val1 < val2 ? 32'd1 : 32'd0; end
            `ALU_GEU:  begin aluout = val1 >= val2 ? 32'd1 : 32'd0; end
    
            // None
            default:   begin aluout = 32'd0; end
        endcase

    end

end

endmodule
