`timescale 1ns / 1ps

module nekoichitop(
	input bit clk_i,
	input bit rst_i,
	output bit dvi_clk_p_o,
	output bit dvi_clk_n_o,
	output bit dvi_tx0_p_o,
	output bit dvi_tx0_n_o,
	output bit dvi_tx1_p_o,
	output bit dvi_tx1_n_o,
	output bit dvi_tx2_p_o,
	output bit dvi_tx2_n_o );

// =====================================================================================================
// Misc Wires
// =====================================================================================================

logic [11:0] video_x, video_y;
logic [7:0] blue, red, green;

wire [31:0] memaddress;
wire [31:0] writeword;
wire [31:0] mem_data;
wire [3:0] mem_writeena;

wire clockDVI;
wire sysclock, clockALocked;

// =====================================================================================================
// CPU Clock
// =====================================================================================================

clk_wiz_0 SClock(
	.clk_in1(clk_i),
	.resetn(~rst_i),
	.clk_out1(sysclock),
	.locked(clockALocked) );

wire clocksLocked = clockALocked;// & otherclocklocked etc;
wire reset_p = rst_i | (~clocksLocked);
wire reset_n = (~rst_i) & clocksLocked;


// =====================================================================================================
// CPU + System RAM
// =====================================================================================================

blk_mem_gen_1 SYSRAM(
	.addra(memaddress[16:2]), // 128Kb RAM, 32768 DWORDs, 15 bit address space
	.clka(sysclock),
	.dina(writeword),
	.douta(mem_data),
	.ena(reset_n),
	.wea(memaddress[31]==1'b0 ? mem_writeena : 4'b0000) ); // Address below 0x80000000 are system ram

wire fifowrfull;
wire fifordempty;
wire fifodatavalid;
wire [31:0] gpufifocommand;  // < from CPU
wire gpufifowe; // < from CPU
wire gpuready; // < from GPU
logic fifore = 1'b0;
logic [31:0] fifodataout;
logic [31:0] gpucommand;
logic gpupulse = 1'b0;
opqueue gpurwqueue(
	// write
	.full(fifowrfull),
	.din(gpufifocommand),
	.wr_en(gpufifowe),
	// read
	.empty(fifordempty),
	.dout(fifodataout),
	.rd_en(fifore),
	// ctl
	.clk(sysclock),
	.srst(reset_p),
	.valid(fifodatavalid) );

// Stream from command queue to GPU
always_ff @(posedge sysclock) begin

	// Turn off pulse and read enable if either were set on last clock
	gpupulse <= 1'b0;
	fifore <= 1'b0;

	// Trigger read when FIFO not empty and if GPU is ready
	if ((fifore == 1'b0) & (fifordempty == 1'b0) & gpuready) begin
		fifore <= 1'b1;
	end

	// Complete read from fifo and apply operation in the command bits
	if (fifodatavalid) begin
		gpucommand <= fifodataout;
		gpupulse <= 1'b1;
	end

end

wire [13:0] vramaddress;
wire [3:0] vramwe;
wire [31:0] vramdata;
wire [11:0] lanemask;
GPU rv32gpu(
	.clock(sysclock),
	.reset(reset_p),
	.gpucommand(gpucommand),
	.gpupulse(gpupulse),
	.gpuready(gpuready),
	// VRAM output
	.vramaddress(vramaddress),
	.vramwe(vramwe),
	.vramdata(vramdata),
	.lanemask(lanemask) );

rv32cpu rv32cpu(
	.clock(sysclock),
	.reset(reset_p),
	.gpufifocommand(gpufifocommand),
	.gpufifowe(gpufifowe),
	.memaddress(memaddress),
	.writeword(writeword),
	.mem_data(mem_data),
	.mem_writeena(mem_writeena),
	.gpuready(gpuready),
	.gpufifoempty(fifordempty),
	.gpufifofull(fifowrfull) );

// =====================================================================================================
// Video Unit
// =====================================================================================================

videocontroller VideoUnit(
		.sysclock(sysclock),
		.clockDVI(clockDVI),
		.reset_n(reset_n),
		.video_x(video_x),
		.video_y(video_y),
		.memaddress(vramaddress),
		.mem_writeena(vramwe), // Will recognize and trap its own writes using top address bit
		.writeword(vramdata),
		.lanemask(lanemask),
		.red(red),
		.green(green),
		.blue(blue));

dvi_tx DVIScanOut(
	.clk_i(clk_i), // Has its own MMCM generated from this input pin
	.rst_i(rst_i), // Has its own 'locked' dependent reset logic
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
