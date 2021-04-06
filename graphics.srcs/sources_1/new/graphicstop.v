`timescale 1ns / 1ps

module graphicstop(
	input wire clk_i,
	input wire rst_i,
	output wire dvi_clk_p_o,
	output wire dvi_clk_n_o,
	output wire dvi_tx0_p_o,
	output wire dvi_tx0_n_o,
	output wire dvi_tx1_p_o,
	output wire dvi_tx1_n_o,
	output wire dvi_tx2_p_o,
	output wire dvi_tx2_n_o );
	
wire sysclock, peripheralclk, clockALocked, /*clockBLocked,*/ clocksLocked;

clk_wiz_0 SClock(
	.clk_in1(clk_i),
	.resetn(~rst_i),
	.sysclock(sysclock),
	.peripheralclk(peripheralclk),
	.locked(clockALocked) );

wire clocksLocked = clockALocked /*& clockBLocked*/;
wire reset_p = rst_i | (~clocksLocked);
wire reset_n = (~rst_i) & clocksLocked;

wire [31:0] memaddress;
wire [31:0] writeword;
wire [31:0] mem_data;
wire [3:0] mem_writeena;

wire [31:0] vram_data;
wire [11:0] video_x, video_y;
wire [7:0] blue, red, green;

wire clockDVI; // DVIOut instantiates an MMCM for this internally
VRAM VRAMController(
		.sysclock(sysclock),
		.clockDVI(clockDVI),
		.reset_n(reset_n),
		.video_x(video_x),
		.video_y(video_y),
		.memaddress(memaddress),
		.mem_writeena(mem_writeena), // Will recognize and trap its own writes using top address bit
		.writeword(writeword),
		.red(red),
		.green(green),
		.blue(blue));

blk_mem_gen_0 SYSRAM(
	.addra(memaddress[16:2]), // 128Kb RAM, 32768 DWORDs, 15 bit address space
	.clka(sysclock),
	.dina(writeword),
	.douta(mem_data),
	.ena(reset_n),
	.wea(memaddress[31]==1'b0 ? mem_writeena : 4'b0000) ); // address below 0x80000000

cputoplevel RV32CPU(
	.clock(sysclock),
	.reset(reset_p),
	.memaddress(memaddress),
	.writeword(writeword),
	.mem_data(mem_data),
	.mem_writeena(mem_writeena) );

dvi_tx DVIOut(
	.clk_i(clk_i), // Has its own MMCM generated from this input pin
	.rst_i(reset_p),
	.dvi_clk_p_o(dvi_clk_p_o),
	.dvi_clk_n_o(dvi_clk_n_o),
	.dvi_tx0_p_o(dvi_tx0_p_o),
	.dvi_tx0_n_o(dvi_tx0_n_o),
	.dvi_tx1_p_o(dvi_tx1_p_o),
	.dvi_tx1_n_o(dvi_tx1_n_o),
	.dvi_tx2_p_o(dvi_tx2_p_o),
	.dvi_tx2_n_o(dvi_tx2_n_o),
	.red(red),
	.green(green),
	.blue(blue),
	.counter_x(video_x),
	.counter_y(video_y),
	.pixel_clock(clockDVI) );

endmodule
