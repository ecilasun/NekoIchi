`default_nettype none
`timescale 1ns / 1ps

module registerfile(
	input wire reset,			// Internal state resets when high
	input wire clock,			// Writes are clocked, reads are not
	input wire [4:0] rs1,		// Source register 1
	input wire [4:0] rs2,		// Source register 2
	input wire [4:0] rd,		// Destination register
	input wire wren,			// Write enable bit for writing to register rd 
	input wire [31:0] datain,	// Data to write to register rd
	output wire [31:0] rval1,	// Register values for rs1 and rs2
	output wire [31:0] rval2 );

reg [31:0] registers[0:31]; 

always @(posedge clock) begin
	if (wren && rd != 5'd0)
		registers[rd] <= datain;
end

assign rval1 = rs1==0 ? 32'd0 : registers[rs1];
assign rval2 = rs2==0 ? 32'd0 : registers[rs2];

endmodule
