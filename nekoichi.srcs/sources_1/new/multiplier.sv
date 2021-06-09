`timescale 1ns / 1ps

`include "cpuops.vh"

module multiplier(
    input wire clk,					// Clock input
    input wire reset,				// Reset line
    input wire start,				// Kick multiply operation (hold for one clock)
    output logic busy = 1'b0,		// Multiplier busy
    input wire [2:0] func3,			// To determine which mul op this is
    input wire [31:0] multiplicand,	// Input A
    input wire [31:0] multiplier,	// Input B
    output logic [31:0] product );	// Result

logic [32:0] A = 33'd0;
logic [32:0] B = 33'd0;
logic [3:0] n = 4'd0;
wire [65:0] DSPproduct;

mul_SS mulsignedsigned(
	.CLK(clk),
	.A(A),
	.B(B),
	.P(DSPproduct),
	.CE(~reset & (start | busy)) );

always_ff @(posedge clk) begin
	if (reset) begin
		//busy <= 1'b0;
	end else begin
		if (start) begin

			unique case (func3)
				`F3_MUL, `F3_MULH: begin
					A <= {multiplicand[31], multiplicand};
					B <= {multiplier[31], multiplier};
				end
				`F3_MULHSU: begin
					A <= {multiplicand[31], multiplicand};
					B <= {1'b0, multiplier};
				end
				`F3_MULHU: begin
					A <= {1'b0, multiplicand};
					B <= {1'b0, multiplier};
				end
				/*default: begin
					product = 0; // Do not enable 
				end*/
			endcase
			// Can use 1 clock latency for
			// multipliers on ArtyZ7-20, 7 is OK on ArtyA7-100T for area
			n <= 7;
			busy <= 1'b1;
		end else begin
			if (busy) begin
				if (n == 0) begin
					unique case (func3)
						`F3_MUL: begin
							product <= DSPproduct[31:0];
						end
						default : begin // `F3_MULH, `F3_MULHSU, `F3_MULHU
							product <= DSPproduct[63:32]; // Or is this 64:33 ?
						end
					endcase
					busy <= 1'b0;
				end else begin
					n <= n - 4'd1;
				end 
			end else begin
				product <= 32'd0;
			end
		end
	end
end

endmodule
