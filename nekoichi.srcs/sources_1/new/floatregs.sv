`timescale 1ns / 1ps

module floatregisterfile(
	input wire clock,			// Writes are clocked, reads are not
	input wire [4:0] rs1,		// Source register 1
	input wire [4:0] rs2,		// Source register 2
	input wire [4:0] rs3,		// Source register 3 (for fused ops)
	input wire [4:0] rd,		// Destination register
	input wire wren,			// Write enable bit for writing to register rd 
	input wire [31:0] datain,	// Data to write to register rd
	output wire [31:0] rval1,	// Register values for rs1 and rs2
	output wire [31:0] rval2,
	output wire [31:0] rval3 );

logic [31:0] registers[0:31]; 

always @(posedge clock) begin
	if (wren)
		registers[rd] <= datain;
end

assign rval1 = registers[rs1];
assign rval2 = registers[rs2];
assign rval3 = registers[rs3];

endmodule
