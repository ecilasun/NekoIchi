`default_nettype none
`timescale 1ns / 1ps

module multiplier(
	input wire [2:0] func3,
	input wire [31:0] A,
	input wire [31:0] B,
	output wire [31:0] multiplier_result );
	
reg [63:0] result;

always @(*) begin
	case(func3)
		3'b000, 3'b001: result = $signed(A) * $signed(B); // MUL, MULH
		3'b010: result = $signed(A) * B; // MULHSU
		3'b011: result = A * B; // MULHU
		default: result = 64'd0;
	endcase
end

assign multiplier_result = (func3 == 3'b000) ? result[31:0] : result[63:32];

endmodule

module unsigneddivider(
    input wire logic clk,
    input wire logic reset,
    input wire logic start,          // start signal
    output     logic busy,           // calculation in progress
    output     logic divdone,
    input wire logic [31:0] dividend,
    input wire logic [31:0] divisor,
    output     logic [31:0] quotient,
    output     logic [31:0] remainder
);

// 32+1 bit registers for M and A
reg [32:0] M_neg, A, prevA;
reg [31:0] Q;
reg [5:0] n;

always @(posedge clk) begin
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
			end else begin
				quotient = Q[31:0];
				remainder = A[31:0];
				divdone = 1;
				busy = 1'b0;
			end
		end
	end
end

endmodule

module signeddivider(
    input wire logic clk,
    input wire logic reset,
    input wire logic start,          // start signal
    output     logic busy,           // calculation in progress
    output     logic divdone,
    input wire logic [31:0] dividend,
    input wire logic [31:0] divisor,
    output     logic [31:0] quotient,
    output     logic [31:0] remainder
);

// 32+1 bit registers for M and A
reg [32:0] M_neg, A, prevA;
reg [31:0] Q;
reg [5:0] n;
reg signflip;
wire [32:0] extendeddivisor = {divisor[31], divisor};

always @(posedge clk) begin
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
			end else begin
				quotient = signflip ? (Q[31:0]^32'hFFFFFFFF)+32'd1: Q[31:0];
				remainder = signflip ? (A[31:0]^32'hFFFFFFFF)+32'd1 : A[31:0];
				divdone = 1;
				busy = 1'b0;
			end
		end
	end
end

endmodule
