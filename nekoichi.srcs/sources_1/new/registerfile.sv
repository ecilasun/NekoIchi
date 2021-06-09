`timescale 1ns / 1ps

module registerfile(
	input wire clock,			// Writes are clocked, reads are not
	input wire [4:0] rs1,		// Source register 1
	input wire [4:0] rs2,		// Source register 2
	input wire [4:0] rd,		// Destination register
	input wire wren,			// Write enable bit for writing to register rd 
	input wire [31:0] datain,	// Data to write to register rd
	output wire [31:0] rval1,	// Register values for rs1 and rs2
	output wire [31:0] rval2 );

logic [31:0] registers[0:31];

initial begin
	registers[0] <= 32'h00000000; // Zero register
	registers[1] <= 32'h00000000; // Default return address 
	registers[2] <= 32'h0003FFF0; // Default stack pointer
	registers[3] <= 32'h00000000;
	registers[4] <= 32'h00000000;
	registers[5] <= 32'h00000000;
	registers[6] <= 32'h00000000;
	registers[7] <= 32'h00000000;
	registers[8] <= 32'h00000000;
	registers[9] <= 32'h00000000;
	registers[10] <= 32'h00000000;
	registers[11] <= 32'h00000000;
	registers[12] <= 32'h00000000;
	registers[13] <= 32'h00000000;
	registers[14] <= 32'h00000000;
	registers[15] <= 32'h00000000;
	registers[16] <= 32'h00000000;
	registers[17] <= 32'h00000000;
	registers[18] <= 32'h00000000;
	registers[19] <= 32'h00000000;
	registers[20] <= 32'h00000000;
	registers[21] <= 32'h00000000;
	registers[22] <= 32'h00000000;
	registers[23] <= 32'h00000000;
	registers[24] <= 32'h00000000;
	registers[25] <= 32'h00000000;
	registers[26] <= 32'h00000000;
	registers[27] <= 32'h00000000;
	registers[28] <= 32'h00000000;
	registers[29] <= 32'h00000000;
	registers[30] <= 32'h00000000;
	registers[31] <= 32'h00000000;
end


// Writes are clocked, and since writes happen at the end of the clock
// the new values are available on the 'next' clock.
always @(posedge clock) begin
	// Do not write over zero register when write enable is on
	if (wren & (rd != 5'd0))
		registers[rd] <= datain;
end

// Outputs are continously assigned,
// therefore their values are available 'this' clock.
assign rval1 = registers[rs1];
assign rval2 = registers[rs2];

endmodule
