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

logic [31:0] registers[0:31]; 

always @(posedge clock) begin
	if (reset) begin
		registers[0] <= 32'h00000000; // Zero register
		registers[2] <= 32'h0001FFF0; // Default hard SP
	end else begin
		if (wren && rd != 5'd0)
			registers[rd] <= datain;
	end
end

assign rval1 = registers[rs1];
assign rval2 = registers[rs2];

endmodule
