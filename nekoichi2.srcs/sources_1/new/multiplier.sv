`timescale 1ns / 1ps

`include "cpuops.vh"

module multiplier(
    input wire clk,
    input wire reset,
    input wire start,          // start signal
    output logic busy,           // calculation in progress
    input wire [2:0] func3,
    input wire [31:0] multiplicand,
    input wire [31:0] multiplier,
    output logic [31:0] product );

logic [31:0] A = 32'd0;
logic [31:0] B = 32'd0;
logic [3:0] n = 4'd0;
wire [63:0] DSPproductSS, DSPproductSU, DSPproductUU;

mul_SS mulsignedsigned(
	.CLK(clk),
	.A(A),
	.B(B),
	.P(DSPproductSS),
	.CE(~reset & (start | busy)) );

mul_SU mulsignedunsigned(
	.CLK(clk),
	.A(A),
	.B(B),
	.P(DSPproductSU),
	.CE(~reset & (start | busy)) );

mul_UU mulunsignedunsigned(
	.CLK(clk),
	.A(A),
	.B(B),
	.P(DSPproductUU),
	.CE(~reset & (start | busy)) );

always_ff @(posedge clk) begin
	if (reset) begin
		busy = 1'b0;
	end else begin
		if (start) begin
			A = multiplicand;
			B = multiplier;
			n = 7;
			busy = 1'b1;
		end else begin
			if (busy) begin // 1 clock latency for multipliers on ArtyZ7-20
				if (n == 0) begin
					unique case (func3)
						`F3_MUL: begin
							product = DSPproductSS[31:0];
						end
						`F3_MULH: begin
							product = DSPproductSS[63:32];
						end
						`F3_MULHSU: begin
							product = DSPproductSU[63:32];
						end
						`F3_MULHU: begin
							product = DSPproductUU[63:32];
						end
						/*default: begin
							product = 0; // Illegal multiply opcode
						end*/
					endcase
					busy = 1'b0;
				end else begin
					n = n - 4'd1;
				end 
			end else begin
				product = 32'd0;
			end
		end
	end
end

endmodule
