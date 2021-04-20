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

wire [31:0] dmaaddress;
wire [31:0] dmaword;
wire [31:0] dma_data;
wire [3:0] dma_writeena;

wire clockDVI;
wire sysclock, clockALocked;

wire fifowrfull;
wire fifordempty;
wire fifodatavalid;
wire [31:0] gpufifocommand;  // < from CPU
wire gpufifowe; // < from CPU
wire fifore;
wire [31:0] fifodataout;

wire [13:0] vramaddress;
wire [3:0] vramwe;
wire [31:0] vramwriteword;
wire [11:0] lanemask;

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
// CPU + GPU + System RAM (true dual port) / GPU FIFO (1024 DWORDs)
// =====================================================================================================

// Address below 0x80000000 reside in SYSRAM
// Addresses on or above 0x80000000 write to the GPU FIFO
blk_mem_gen_1 SYSRAM(
	// CPU bus for CPU read-write
	.addra(memaddress[16:2]), // 128Kb RAM, 32768 DWORDs, 15 bit address space
	.clka(sysclock),
	.dina(writeword),
	.douta(mem_data),
	.wea(memaddress[31]==1'b0 ? mem_writeena : 4'b0000),
	.ena(reset_n),
	// DMA bus for GPU read-write
	.addrb(dmaaddress[16:2]),
	.clkb(sysclock),
	.dinb(dmaword),
	.doutb(dma_data),
	.web(dma_writeena),
	.enb(reset_n) );

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

// Cross clock domain for vsync, from DVI to sys
wire vsync_fastdomain;
wire vsyncfifoempty;
wire vsyncfifofull;
wire vsyncfifovalid;
wire vsync_we;
logic vsync_signal = 1'b0;
logic vsync_re;
domaincrosssignalfifo gpucpusync(
	.full(vsyncfifofull),
	.din(1'b1),
	.wr_en(vsync_we),
	.empty(vsyncfifoempty),
	.dout(vsync_fastdomain),
	.rd_en(vsync_re),
	.wr_clk(clockDVI),
	.rd_clk(sysclock),
	.rst(reset_p),
	.valid(vsyncfifovalid) );

// Drain the vsync fifo and set vsync signal for the GPU every time we find one
always @(posedge sysclock) begin
	vsync_re <= 1'b0;
	vsync_signal <= 1'b0;
	if (~vsyncfifoempty) begin
		vsync_re <= 1'b1;
		vsync_signal <= 1'b1;
	end
end

GPU rv32gpu(
	.clock(sysclock),
	.reset(reset_p),
	.vsync(vsync_signal),
	// FIFO control
	.fifoempty(fifordempty),
	.fifodout(fifodataout),
	.fifdoutvalid(fifodatavalid),
	.fiford_en(fifore),
	// VRAM output
	.vramaddress(vramaddress),
	.vramwe(vramwe),
	.vramwriteword(vramwriteword),
	.lanemask(lanemask),
	.dmaaddress(dmaaddress[16:2]),
	.dmaword(dmaword),
	.dma_data(dma_data),
	.dmawe(dma_writeena) );

rv32cpu rv32cpu(
	.clock(sysclock),
	.reset(reset_p),
	.gpufifocommand(gpufifocommand),
	.gpufifowe(gpufifowe),
	.memaddress(memaddress),
	.writeword(writeword),
	.mem_data(mem_data),
	.mem_writeena(mem_writeena),
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
		.writeword(vramwriteword),
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
	.pixel_clock(clockDVI),
	.vsync_signal(vsync_we));

endmodule
