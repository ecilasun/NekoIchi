`timescale 1ns / 1ps

module nekoichitop(
	input wire CLK_I,
	input wire RST_I,

	// VGA PMOD on ports A+B
	output wire [3:0] VGA_R,
	output wire [3:0] VGA_G,
	output wire [3:0] VGA_B,
	output wire VGA_HS_O,
	output wire VGA_VS_O,
	
	// DVI PMOD on ports A+B
	/*output wire [3:0] DVI_R,
	output wire [3:0] DVI_G,
	output wire [3:0] DVI_B,
	output wire DVI_HS,
	output wire DVI_VS,
	output wire DVI_DE,
	output wire DVI_CLK,*/

	// UART
	output wire uart_rxd_out,
	input wire uart_txd_in

	// SD Card PMOD on port C
/*	,output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck,
	//inout wire [1:0] dat,
	input wire spi_cd

	// DDR3
	,inout wire [15:0] ddr3_dq,
	output wire[1:0] ddr3_dm,
	inout wire [1:0] ddr3_dqs_p,
	inout wire [1:0] ddr3_dqs_n,
	output wire [13:0] ddr3_addr,
	output wire [2:0] ddr3_ba,
	output wire [0:0] ddr3_ck_p,
	output wire [0:0] ddr3_ck_n,
	output wire ddr3_ras_n,
	output wire ddr3_cas_n,
	output wire ddr3_we_n,
	output wire ddr3_reset_n,
	output wire [0:0] ddr3_cke,
	output wire [0:0] ddr3_odt,
	output wire [0:0] ddr3_cs_n*/ );

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
// GPU and CPU clocks vary, default at CPU@60Mhz & GPU@75Mhz
// Wall clock is for time CSR and runs at 10Mhz
wire sysclock60, wallclock, gpuclock, uartclk, vgaclock, spiclock100;
wire clockALocked, clockBLocked, clockCLocked;

wire [11:0] video_x;
wire [11:0] video_y;
wire vsync_we;

logic [31:0] vsynccounter;
wire [31:0] vsync_fastdomain;
wire vsyncfifoempty;
wire vsyncfifofull;
wire vsyncfifovalid;

// =====================================================================================================
// Clocks
// =====================================================================================================

SystemClockGen SysClockUnit(
	.clk_in1(CLK_I),
	.resetn(~RST_I),
	.sysclock60(sysclock60),
	.wallclock(wallclock),
	.locked(clockALocked) );

GPUClockGen GpuClockUnit(
	.clk_in1(CLK_I),
	.resetn(~RST_I),
	.gpuclock(gpuclock),
	.vgaclock(vgaclock),
	.locked(clockBLocked) );
	
PeripheralClockGen PeripheralClockUnit(
	.clk_in1(CLK_I),
	.resetn(~RST_I),
	.uartclk(uartclk),
	.spiclock100(spiclock100),
	.locked(clockCLocked) );

wire allClocksLocked = clockALocked & clockBLocked & clockCLocked;

wire reset_p = RST_I | (~allClocksLocked);
wire reset_n = (~RST_I) & allClocksLocked;


// =====================================================================================================
// Device router
// =====================================================================================================

/*logic [31:0] memaddress=0;
logic [31:0] writeword=0;
logic [31:0] mem_dataout;
logic[3:0] mem_writeena;

wire [31:0] busaddress;
wire [31:0] buswriteword;
wire [31:0] busdataout;
wire [3:0] buswriteena;

wire deviceUARTTxWrite			= busaddress[31:28] == 4'b0100 ? 1'b1 : 1'b0;	// 0x40000000
wire deviceUARTRxRead			= busaddress[31:28] == 4'b0101 ? 1'b1 : 1'b0;	// 0x50000000
wire deviceUARTByteCountRead	= busaddress[31:28] == 4'b0110 ? 1'b1 : 1'b0;	// 0x60000000
wire deviceGPUFIFOWrite			= busaddress[31:28] == 4'b1000 ? 1'b1 : 1'b0;	// 0x80000000
wire [3:0] deviceRTPort			= {deviceUARTTxWrite, deviceUARTRxRead, deviceUARTByteCountRead, deviceGPUFIFOWrite};

assign busdataout = deviceUARTRxRead ? {24'd0, infifoout} : ( deviceUARTByteCountRead ? infifodatacount : mem_dataout);

// =====================================================================================================
// Read arbitrator
// =====================================================================================================

always_comb begin
	unique case (deviceRTPort)
		4'b0000: begin // SYSRAM
			memaddress <= busaddress;
			mem_writeena <= buswriteena;
			mem_dataout <= busdataout;
		end
		4'b0001: begin // GPUFIFO
		end
		4'b0010: begin // UARTBYTECOUNT
		end
		4'b0100: begin // UARTRX
		end
		4'b1000: begin // UARTTX
		end 
	endcase
end*/

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
    .wr_clk(sysclock60), // CPU write clock
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
    .rd_clk(sysclock60),
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

wire [31:0] dma_address;
wire [31:0] dma_writeword;
wire [31:0] dma_dataout;
wire [3:0] dma_writeena;

wire [31:0] mem_address;
wire [31:0] mem_writeword;
wire [31:0] mem_dataout;
wire [3:0] mem_writeena;

FastSystemMemory SYSRAM(
	// ----------------------------
	// CPU bus for CPU read-write
	// ----------------------------
	.addra(mem_address[16:2]), // 128Kb RAM, 32768 DWORDs, 15 bit address space
	.clka(sysclock60),
	.dina(mem_writeword),
	.douta(mem_dataout),
	.wea(mem_address[31]==1'b0 ? mem_writeena : 4'b0000),
	.ena(reset_n),
	// ----------------------------
	// DMA bus for GPU read/write
	// ----------------------------
	.addrb(dma_address[16:2]),
	.clkb(gpuclock),
	.dinb(dma_writeword),
	.doutb(dma_dataout),
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
	.wr_clk(sysclock60),
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

wire videopage;

GPU rv32gpu(
	.clock(gpuclock),
	.reset(reset_p),
	.vsync(vsync_signal),
	.videopage(videopage),
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
	.dmaaddress(dma_address),
	.dmawriteword(dma_writeword),
	.dma_data(dma_dataout),
	.dmawe(dma_writeena) );

rv32cpu rv32cpu(
	.clock(sysclock60),
	.wallclock(wallclock),
	.reset(reset_p),
	// GPU: // 0x80000000 (read/write,32bits)
	.gpufifofull(fifowrfull),
	.gpufifocommand(gpufifocommand),
	.gpufifowe(gpufifowe),
	// UART Tx: // OutData: 0x40000000 (write,8bits)
	.uartfifowe(outuartfifowe),
	.uartoutdata(outfifoin),
	// UART Rx: // DataCount: 0x60000000 (read,32bits) InData: 0x50000000 (read,8bits)
	.uartfifovalid(infifovalid),
	.uartfifore(infifore),
	.uartindata(infifoout),
	.uartinputbytecount(infifodatacount),
	// SYSMEM: // 0x00000000 - 0x0001FFFF (read/write,32bit,16bits,8bitss)
	.memaddress(mem_address),//busaddress
	.writeword(mem_writeword),//buswriteword
	.mem_data(mem_dataout),//busdataout
	.mem_writeena(mem_writeena) //buswriteena
  );

// =====================================================================================================
// Video Unit
// =====================================================================================================

wire [3:0] VIDEO_R_ONE;
wire [3:0] VIDEO_G_ONE;
wire [3:0] VIDEO_B_ONE;
wire [3:0] VIDEO_R_TWO;
wire [3:0] VIDEO_G_TWO;
wire [3:0] VIDEO_B_TWO;

VideoControllerGen VideoUnitA(
	.gpuclock(gpuclock),
	.vgaclock(vgaclock),
	.reset_n(reset_n),
	.writesenabled(videopage),
	.video_x(video_x),
	.video_y(video_y),
	// Wire input
	.memaddress(gpuwriteaddress),
	.mem_writeena(gpuwriteena),
	.writeword(gpuwriteword),
	.lanemask(gpulanewritemask),
	// Video output
	.red(VIDEO_R_ONE),
	.green(VIDEO_G_ONE),
	.blue(VIDEO_B_ONE) );

VideoControllerGen VideoUnitB(
	.gpuclock(gpuclock),
	.vgaclock(vgaclock),
	.reset_n(reset_n),
	.writesenabled(~videopage),
	.video_x(video_x),
	.video_y(video_y),
	// Wire input
	.memaddress(gpuwriteaddress),
	.mem_writeena(gpuwriteena),
	.writeword(gpuwriteword),
	.lanemask(gpulanewritemask),
	// Video output
	.red(VIDEO_R_TWO),
	.green(VIDEO_G_TWO),
	.blue(VIDEO_B_TWO) );

// DVI
/*assign DVI_R = videopage == 1'b0 ? VIDEO_R_ONE : VIDEO_R_TWO;
assign DVI_G = videopage == 1'b0 ? VIDEO_G_ONE : VIDEO_G_TWO;
assign DVI_B = videopage == 1'b0 ? VIDEO_B_ONE : VIDEO_B_TWO;
assign DVI_CLK = vgaclock;

vgatimer VideoScanout(
		.rst_i(reset_p),
		.clk_i(vgaclock),
        .hsync_o(DVI_HS),
        .vsync_o(DVI_VS),
        .counter_x(video_x),
        .counter_y(video_y),
        .vsynctrigger_o(vsync_we),
        .vsynccounter(vsynccounter),
        .in_display_window(DVI_DE) );*/

// VGA
assign VGA_R = videopage == 1'b0 ? VIDEO_R_ONE : VIDEO_R_TWO;
assign VGA_G = videopage == 1'b0 ? VIDEO_G_ONE : VIDEO_G_TWO;
assign VGA_B = videopage == 1'b0 ? VIDEO_B_ONE : VIDEO_B_TWO;

vgatimer VideoScanout(
		.rst_i(reset_p),
		.clk_i(vgaclock),
        .hsync_o(VGA_HS_O),
        .vsync_o(VGA_VS_O),
        .counter_x(video_x),
        .counter_y(video_y),
        .vsynctrigger_o(vsync_we),
        .vsynccounter(vsynccounter) );

// =====================================================================================================
// SD Card controller
// =====================================================================================================

/*wire sddatavalid;
wire sdtxready;
wire sdtxdatavalid;
wire [7:0] sdtxdata;
wire [7:0] sdrcvdata;

SPI_Master_With_Single_CS SDCardController (
	// Control/Data Signals
	.i_Rst_L(reset_n),					// FPGA Reset
	.i_Clk(spiclock100),				// 100Mhz clock
   
	// TX (MOSI) Signals
	.i_TX_Count(2'b10),					// Bytes per CS low
	.i_TX_Byte(sdtxdata),				// Byte to transmit on MOSI
	.i_TX_DV(sdtxdatavalid),			// Data Valid Pulse with i_TX_Byte
	.o_TX_Ready(sdtxready),				// Transmit Ready for next byte

	// RX (MISO) Signals
	.o_RX_DV(sddatavalid),				// Data Valid pulse (1 clock cycle)
	.o_RX_Byte(sdrcvdata),				// Byte received on MISO
	.o_RX_Count(),						// Receive count - unused

	// SPI Interface
	.o_SPI_Clk(spi_sck),
	.i_SPI_MISO(spi_miso),
	.o_SPI_MOSI(spi_mosi),
	.o_SPI_CS_n(spi_cs_n) );
*/

endmodule
