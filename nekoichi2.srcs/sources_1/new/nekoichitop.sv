`timescale 1ns / 1ps

module nekoichitop(
	input wire CLK_I,
	input wire RST_I,
	output wire [3:0] VGA_R,
	output wire [3:0] VGA_G,
	output wire [3:0] VGA_B,
	output wire VGA_HS_O,
	output wire VGA_VS_O,
	output wire uart_rxd_out,
	input wire uart_txd_in );

// =====================================================================================================
// Misc Wires
// =====================================================================================================

wire [13:0] gpuwriteaddress;
wire [3:0] gpuwriteena;
wire [31:0] gpuwriteword;
wire [11:0] gpulanewritemask;

wire fifowrfull;
wire fifordempty;
wire fifodatavalid;
wire [31:0] gpufifocommand;  // < from CPU
wire gpufifowe; // < from CPU
wire fifore;
wire [31:0] fifodataout;

// UART clock: 10Mhz, VGA clock: 25Mhz
// GPU and CPU clocks vary, default at CPU@60Mhz & GPU@80Mhz
wire sysclock, gpuclock, uartclk, vgaclock;
wire clockALocked, clockBLocked, clockCLocked;

wire [31:0] memaddress, dmaaddress;
wire [31:0] writeword, dmawriteword;
wire [31:0] mem_dataout, dma_data;
wire [3:0] mem_writeena, dma_writeena;

wire [11:0] video_x;
wire [11:0] video_y;
wire vsync_we;

logic [31:0] vsynccounter;
wire [31:0] vsync_fastdomain;
wire vsyncfifoempty;
wire vsyncfifofull;
wire vsyncfifovalid;

// =====================================================================================================
// CPU Clock
// =====================================================================================================

SystemClockGen SysClockUnit(
	.clk_in1(CLK_I),
	.resetn(~RST_I),
	.sysclock(sysclock),
	.vgaclock(vgaclock),
	.locked(clockALocked) );

GPUClockGen GpuClockUnit(
	.clk_in1(CLK_I),
	.resetn(~RST_I),
	.gpuclock(gpuclock),
	.locked(clockBLocked) );
	
PeripheralClockGen PeripheralClockUnit(
	.clk_in1(CLK_I),
	.resetn(~RST_I),
	.uartclk(uartclk),
	.locked(clockCLocked) );

wire allClocksLocked = clockALocked & clockBLocked & clockCLocked;

wire reset_p = RST_I | (~allClocksLocked);
wire reset_n = (~RST_I) & allClocksLocked;

// =====================================================================================================
// UART (Tx/Rx) @115200
// =====================================================================================================

logic transmitbyte = 1'b0;
logic [7:0] datatotransmit = 8'h00;
wire uarttxbusy, outfifofull, outfifoempty, infifofull, infifoempty;
wire outuartfifowe;
logic outfifore = 1'b0;
wire outfifovalid;
logic infifowe = 1'b0;
wire infifore;
wire infifovalid;
wire uartbyteavailable;
wire [7:0] outfifoin;
logic [7:0] inuartbyte;
wire [7:0] uartbytein;
wire [7:0] outfifoout,infifoout;
wire [9:0] outfifodatacount, infifodatacount;
logic txstate = 1'b0;

// ---------------------------------
// Transmitter (CPU -> FIFO -> Tx)
// ---------------------------------
async_transmitter UART_transmit(
	.clk(uartclk),
	.TxD_start(transmitbyte),
	.TxD_data(datatotransmit),
	.TxD(uart_rxd_out),
	.TxD_busy(uarttxbusy) );

// Output FIFO
UARTFifoGen UART_out_fifo(
    .rst(reset_p),
    .full(outfifofull),
    .din(outfifoin), // data from CPU
    .wr_en(outuartfifowe), // CPU controls write, high for one clock
    .empty(outfifoempty),
    .dout(outfifoout), // to transmitter
    .rd_en(outfifore), // transmitter can send
    .wr_clk(sysclock), // CPU write clock
    .rd_clk(uartclk), // transmitter runs slower
    .valid(outfifovalid),
    .rd_data_count(outfifodatacount) );

// Fifo output serializer
always @(posedge(uartclk)) begin
	if (txstate == 1'b0) begin // IDLE_STATE
		if (~uarttxbusy & (transmitbyte == 1'b0)) begin // Safe to attempt send, UART not busy or triggered
			if (~outfifoempty) begin // Something in FIFO? Trigger read and go to transmit 
				outfifore <= 1'b1;			
				txstate <= 1'b1;
			end else begin
				outfifore <= 1'b0;
				txstate <= 1'b0; // Stay in idle state
			end
		end else begin // Transmit hardware busy or we kicked a transmit (should end next clock)
			outfifore <= 1'b0;
			txstate <= 1'b0; // Stay in idle state
		end
		transmitbyte <= 1'b0;
	end else begin // TRANSMIT_STATE
		outfifore <= 1'b0; // Stop read request
		if (outfifovalid) begin // Kick send and go to idle
			datatotransmit <= outfifoout;
			transmitbyte <= 1'b1;
			txstate <= 1'b0;
		end else begin
			txstate <= 1'b1; // Stay in transmit state and wait for valid fifo data
		end
	end
end

// ---------------------------------
// Receiver (Rx -> FIFO -> CPU)
// ---------------------------------
async_receiver UART_receive(
	.clk(uartclk),
	.RxD(uart_txd_in),
	.RxD_data_ready(uartbyteavailable),
	.RxD_data(uartbytein),
	.RxD_idle(),
	.RxD_endofpacket() );

// Input FIFO
UARTFifoGen UART_in_fifo(
    .rst(reset_p),
    .full(infifofull),
    .din(inuartbyte),
    .wr_en(infifowe),
    .empty(infifoempty),
    .dout(infifoout),
    .rd_en(infifore),
    .wr_clk(uartclk),
    .rd_clk(sysclock),
    .valid(infifovalid),
    .rd_data_count(infifodatacount) );

// Fifo input control
always @(posedge(uartclk)) begin
	if (uartbyteavailable) begin
		infifowe <= 1'b1;
		inuartbyte <= uartbytein;
	end else begin
		infifowe <= 1'b0;
	end
end

// =====================================================================================================
// CPU + GPU + System RAM (true dual port) / GPU FIFO (1024 DWORDs)
// =====================================================================================================

FastSystemMemory SYSRAM(
	// ----------------------------
	// CPU bus for CPU read-write
	// ----------------------------
	.addra(memaddress[16:2]), // 128Kb RAM, 32768 DWORDs, 15 bit address space
	.clka(sysclock),
	.dina(writeword),
	.douta(mem_dataout),
	.wea(memaddress[31]==1'b0 ? mem_writeena : 4'b0000),
	.ena(reset_n),
	// ----------------------------
	// DMA bus for GPU read-write
	// ----------------------------
	.addrb(dmaaddress[16:2]),
	.clkb(gpuclock),
	.dinb(dmawriteword),
	.doutb(dma_data),
	.web(dma_writeena),
	.enb(reset_n) );

GPUCommandFIFO GPUCommands(
	// write
	.full(fifowrfull),
	.din(gpufifocommand),
	.wr_en(gpufifowe),
	// read
	.empty(fifordempty),
	.dout(fifodataout),
	.rd_en(fifore),
	// ctl
	.wr_clk(sysclock),
	.rd_clk(gpuclock),
	.rst(reset_p),
	.valid(fifodatavalid) );

// Cross clock domain for vsync, from DVI to sys
logic [31:0] vsync_signal = 32'd0;
logic vsync_re;
DomainCrossSignalFifo GPUVGAVSyncQueue(
	.full(vsyncfifofull),
	.din(vsynccounter),
	.wr_en(vsync_we),
	.empty(vsyncfifoempty),
	.dout(vsync_fastdomain),
	.rd_en(vsync_re),
	.wr_clk(vgaclock),
	.rd_clk(gpuclock),
	.rst(reset_p),
	.valid(vsyncfifovalid) );

// Drain the vsync fifo and set vsync signal for the GPU every time we find one
always @(posedge gpuclock) begin
	vsync_re <= 1'b0;
	if (~vsyncfifoempty) begin
		vsync_re <= 1'b1;
	end
	if (vsyncfifovalid) begin
		vsync_signal <= vsync_fastdomain;
	end
end

GPU rv32gpu(
	.clock(gpuclock),
	.reset(reset_p),
	.vsync(vsync_signal),
	// FIFO control
	.fifoempty(fifordempty),
	.fifodout(fifodataout),
	.fifdoutvalid(fifodatavalid),
	.fiford_en(fifore),
	// VRAM output
	.vramaddress(gpuwriteaddress),
	.vramwe(gpuwriteena),
	.vramwriteword(gpuwriteword),
	.lanemask(gpulanewritemask),
	.dmaaddress(dmaaddress[16:2]),
	.dmawriteword(dmawriteword),
	.dma_data(dma_data),
	.dmawe(dma_writeena) );

rv32cpu rv32cpu(
	.clock(sysclock),
	.reset(reset_p),
	// GPU
	.gpufifofull(fifowrfull),
	.gpufifocommand(gpufifocommand),
	.gpufifowe(gpufifowe),
	// UART Tx
	.uartfifowe(outuartfifowe),
	.uartoutdata(outfifoin),
	// UART Rx
	.uartfifovalid(infifovalid),
	.uartfifore(infifore),
	.uartindata(infifoout),
	.uartinputbytecount(infifodatacount),
	// Mem
	.memaddress(memaddress),
	.writeword(writeword),
	.mem_data(mem_dataout),
	.mem_writeena(mem_writeena) );

// =====================================================================================================
// Video Unit
// =====================================================================================================

VideoControllerGen VideoUnit(
	.gpuclock(gpuclock),
	.vgaclock(vgaclock),
	.reset_n(reset_n),
	.video_x(video_x),
	.video_y(video_y),
	.memaddress(gpuwriteaddress),
	.mem_writeena(gpuwriteena),
	.writeword(gpuwriteword),
	.lanemask(gpulanewritemask),
	.red(VGA_R),
	.green(VGA_G),
	.blue(VGA_B) );

vgatimer VGAScanout(
		.rst_i(),
		.clk_i(vgaclock),
        .hsync_o(VGA_HS_O),
        .vsync_o(VGA_VS_O),
        .counter_x(video_x),
        .counter_y(video_y),
        .vsynctrigger_o(vsync_we),
        .vsynccounter(vsynccounter) );

endmodule
