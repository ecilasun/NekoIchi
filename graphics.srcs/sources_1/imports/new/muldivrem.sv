`default_nettype none
`timescale 1ns / 1ps

`include "cpuops.vh"

module multiplier(
    input wire clk,
    input wire reset,
    input wire start,          // start signal
    output logic busy,           // calculation in progress
    output logic muldone,
    input wire [2:0] func3,
    input wire [31:0] multiplicand,
    input wire [31:0] multiplier,
    output logic [31:0] product );

reg [31:0] A = 32'd0;
reg [31:0] B = 32'd0;
reg [3:0] n = 4'd0;
wire [63:0] DSPproductSS, DSPproductSU, DSPproductUU;
mult_gen_0 mulSS(
	.CLK(clk),
	.A(A),
	.B(B),
	.P(DSPproductSS),
	.CE(~reset & (start | busy)) );

mult_gen_1 mulSU(
	.CLK(clk),
	.A(A),
	.B(B),
	.P(DSPproductSU),
	.CE(~reset & (start | busy)) );

mult_gen_2 mulUU(
	.CLK(clk),
	.A(A),
	.B(B),
	.P(DSPproductUU),
	.CE(~reset & (start | busy)) );

always @(posedge clk) begin
	if (reset) begin
		busy <= 1'b0;
		muldone <= 1'b1;
	end else begin
		if (start) begin
			A <= multiplicand;
			B <= multiplier;
			n <= 6;
			busy <= 1'b1;
			muldone <= 1'b0;
		end else begin
			if (busy) begin // 1 clock latency for multipliers on ArtyZ7-20
				if (n == 0) begin
					if (func3 == `F3_MUL)
						product <= DSPproductSS[31:0];
					else if (func3 == `F3_MULH)
						product <= DSPproductSS[63:32];
					else if (func3 == `F3_MULHSU)
						product <= DSPproductSU[63:32];
					else // F3_MULHU
						product <= DSPproductUU[63:32];
					muldone <= 1'b1;
					busy <= 1'b0;
				end else begin
					n <= n - 4'd1;
				end 
			end
		end
	end
end

endmodule

module unsigneddivider(
    input wire clk,
    input wire reset,
    input wire start,          // start signal
    output logic busy,           // calculation in progress
    output logic divdone,
    input wire [31:0] dividend,
    input wire [31:0] divisor,
    output logic [31:0] quotient,
    output logic [31:0] remainder
);

// 32+1 bit registers for M and A
reg [32:0] M_neg, A, prevA;
reg [31:0] Q;
reg [5:0] n;

always_ff @(posedge clk) begin
	if (reset) begin
		busy = 1'b0;
		divdone = 1'b1;
	end else begin
		if (start) begin
			if (divisor[30:0] == 31'd0) begin // Handle divide by zero
				quotient = 32'hFFFFFFFF;
				remainder = dividend;
				busy = 1'b0;
				divdone = 1'b1;
			end else begin
				Q = dividend;
				M_neg = ({1'b0, divisor}^33'h1FFFFFFFF) + 33'd1;
				A = 33'd0;
				prevA = 33'd0;
				n = 32;
				busy = 1'b1;
				divdone = 1'b0;
			end
		end else begin
			if (busy) begin
				if (n == 0) begin
					quotient = Q[31:0];
					remainder = A[31:0];
					divdone = 1'b1;
					busy = 0;
				end else begin
					{A, Q} = {A[31:0], Q[31:0], 1'b0};
					prevA = A;
					A = A + M_neg;
					Q[0] = ~A[32];
					if (A[32] == 1'b1)
						A = prevA;
					n = n - 6'd1;
				end
			end
		end
	end
end

endmodule

module signeddivider(
    input wire clk,
    input wire reset,
    input wire start,          // start signal
    output logic busy,           // calculation in progress
    output logic divdone,
    input wire [31:0] dividend,
    input wire [31:0] divisor,
    output logic [31:0] quotient,
    output logic [31:0] remainder
);

// 32+1 bit registers for M and A
reg [32:0] M_neg, A, prevA;
reg [31:0] Q;
reg [5:0] n;
reg signflip;
wire [32:0] extendeddivisor = {divisor[31], divisor};

always_ff @(posedge clk) begin
	if (reset) begin
		busy = 1'b0;
		divdone = 1'b1;
	end else begin
		if (start) begin
			if (divisor[30:0] == 31'd0) begin // Handle divide by zero
				quotient = 32'hFFFFFFFF;
				remainder = dividend;
				busy = 1'b0;
				divdone = 1'b1;
			end else begin
				signflip <= (divisor[31]^dividend[31]);
				Q = dividend[31] ? ((dividend^32'hFFFFFFFF)+32'd1)&32'h7FFFFFFF : dividend;
				M_neg = ((extendeddivisor[32]==1'b1 ? ((extendeddivisor^33'h1FFFFFFFF)+33'd1)&33'h0FFFFFFFF : extendeddivisor)^33'h1FFFFFFFF) + 33'd1;
				A = 33'd0;
				prevA = 33'd0;
				n = 32;
				busy = 1'b1;
				divdone = 1'b0;
			end
		end else begin
			if (busy) begin
				if (n == 0) begin
					quotient = signflip ? (Q[31:0]^32'hFFFFFFFF)+32'd1: Q[31:0];
					remainder = signflip ? (A[31:0]^32'hFFFFFFFF)+32'd1 : A[31:0];
					divdone = 1'b1;
					busy = 0;
				end else begin
					{A, Q} = {A[31:0], Q[31:0], 1'b0};
					prevA = A;
					A = A + M_neg;
					Q[0] = ~A[32];
					if (A[32] == 1'b1)
						A = prevA;
					n = n - 6'd1;
				end
			end
		end
	end
end

endmodule
