`default_nettype none
`timescale 1ns / 1ps

`include "cpuops.vh"
`include "aluops.vh"

module ALU(
	input wire clock,
	input wire reset,
	input wire divstart,
	input wire mulstart,
	output reg [31:0] aluout,
	input wire [2:0] func3,
	input wire [31:0] val1,
	input wire [31:0] val2,
	input wire [4:0] aluop,
	output wire alustall );

// Integer multiplication unit
wire mulbusy;
wire muldone;
wire [31:0] product;
// H/L signedxsigned, signedxunsigned, unsigned all included
//multiplier themul(.func3(func3), .A(val1), .B(val2), .multiplier_result(product));
multiplier themul(
    .clk(clock),
    .reset(reset),
    .start(mulstart),
    .busy(mulbusy),           // calculation in progress
    .muldone(muldone),
    .func3(func3),
    .multiplicand(val1),
    .multiplier(val2),
    .product(product) );

// Integer division units for signed and unsigned
wire [31:0] quotient, quotientu;
wire [31:0] remainder, remainderu;
wire divbusy, divbusyu;
wire divdone, divdoneu;

unsigneddivider thedivu (
	.clk(clock),
	.reset(reset),
	.start(divstart),		// start signal
	.busy(divbusyu),		// calculation in progress
	.divdone(divdoneu),		// division complete
	.dividend(val1),		// dividend
	.divisor(val2),			// divisor
	.quotient(quotientu),	// result: quotient
	.remainder(remainderu)	// result: remainer
);

signeddivider thediv (
	.clk(clock),
	.reset(reset),
	.start(divstart),		// start signal
	.busy(divbusy),			// calculation in progress
	.divdone(divdone),		// division complete
	.dividend(val1),		// dividend
	.divisor(val2),			// divisor
	.quotient(quotient),	// result: quotient
	.remainder(remainder)	// result: remainder
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
            `ALU_MUL:  begin if(muldone) aluout = product; end
            `ALU_DIV:  begin if(divdone) aluout = func3==`F3_DIV ? quotient : quotientu; end // DIV or DIVU
            `ALU_REM:  begin if(divdone) aluout = func3==`F3_REM ? remainder : remainderu; end // REM or REMU
    
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
assign alustall = ~reset & ((divstart | divbusy | divbusyu) | (mulstart | mulbusy));

endmodule
