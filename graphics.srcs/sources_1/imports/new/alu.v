`default_nettype none
`timescale 1ns / 1ps

`include "aluops.vh"

module ALU(
	input wire clock,
	input wire reset,
	input wire divstart,
	output reg [31:0] aluout,
	input wire [2:0] func3,
	input wire [31:0] val1,
	input wire [31:0] val2,
	input wire [4:0] aluop,
	output wire alustall );

// Integer multiplication unit
wire [31:0] multiplier_result;
// H/L signedxsigned, signedxunsigned, unsigned all included
multiplier themul(.func3(func3), .A(val1), .B(val2), .multiplier_result(multiplier_result));

// Integer division unit
wire [31:0] quotient;
wire [31:0] remainder;
wire divbusy;
wire divdone;
wire divbyzero;
/*unsigneddivider thediv (
	.reset(reset),
	.clk(clock),
	.start(divstart),	// start signal
	.busy(divbusy),		// calculation in progress
	.divdone(divdone),	// division complete
	.dbz(divbyzero),	// divide by zero
	.dividend(val1),
	.divisor(val2),
	.quotient(quotient),
	.remainder(remainder)
);*/
signeddivider thediv (
	.reset(reset),
	.clk(clock),
	.start(divstart),	// start signal
	.busy(divbusy),		// calculation in progress
	.divdone(divdone),	// division complete
	.dbz(divbyzero),	// divide by zero
	.dividend(val1),
	.divisor(val2),
	.quotient(quotient),
	.remainder(remainder)
);

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
    
            // M
            `ALU_MUL:  begin aluout = multiplier_result; end
            `ALU_DIV:  begin if(divdone) aluout = quotient; end
            `ALU_REM:  begin if(divdone) aluout = remainder; end
    
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

// If this is set to high, the CPU will stall until it's cleared
// Use this to wait for any long ALU operation to complete
assign alustall = ~reset & (divstart | divbusy);

endmodule
