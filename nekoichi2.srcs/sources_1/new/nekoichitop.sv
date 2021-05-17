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
	
	// LEDs
	output wire [3:0] led,
	
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
	input wire uart_txd_in,

	// SD Card PMOD on port C
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck,
	//inout wire [1:0] dat,
	input wire spi_cd

	// DDR3
/*	,inout wire [15:0] ddr3_dq,
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
// UART (Tx/Rx) @115200
// =====================================================================================================

logic transmitbyte = 1'b0;
logic [7:0] datatotransmit = 8'h00;
wire uarttxbusy, outfifofull, outfifoempty, infifofull, infifoempty;
logic outuartfifowe = 1'b0;
logic outfifore = 1'b0;
wire outfifovalid;
logic infifowe = 1'b0;
logic infifore;
wire infifovalid;
wire uartbyteavailable;
logic [7:0] outfifoin;
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
    // In
    .full(outfifofull),
    .din(outfifoin), // data from CPU
    .wr_en(outuartfifowe), // CPU controls write, high for one clock
    // Out
    .empty(outfifoempty),
    .dout(outfifoout), // to transmitter
    .rd_en(outfifore), // transmitter can send
    .wr_clk(sysclock60), // CPU write clock
    .rd_clk(uartclk), // transmitter runs slower
    .valid(outfifovalid),
    // Ctl
    .rst(reset_p),
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
    // In
    .full(infifofull),
    .din(inuartbyte),
    .wr_en(infifowe),
    // Out
    .empty(infifoempty),
    .dout(infifoout),
    .rd_en(infifore),
    .wr_clk(uartclk),
    .rd_clk(sysclock60),
    .valid(infifovalid),
    // Ctl
    .rst(reset_p),
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
// CPU Bus
// =====================================================================================================

wire gpu_fifowrfull;
wire gpu_fifordempty;
wire gpu_fifodatavalid;
logic [31:0] gpu_fifocommand;
logic gpu_fifowe;
wire gpu_fifore;
wire [31:0] gpu_fifodataout;

wire [31:0] mem_address;
wire [31:0] mem_writeword;
wire [31:0] sysmem_dataout;
wire [3:0] mem_writeena;
wire mem_readena;

logic [31:0] bus_address;
logic [31:0] bus_writeword;
logic [3:0] bus_writeena;
logic bus_readena;

wire sdwq_full;
logic [7:0] sdwq_datain;
logic sdwq_we=1'b0;

wire sdrq_empty, sqrq_valid;
wire [7:0] sdrq_dataout;
logic sdrq_re=1'b0;

wire sddatainready, sddataoutready;

// Device selector based on address
wire deviceSPIWrite				= mem_address[31:28] == 4'b0010 ? 1'b1 : 1'b0;	// 0x20000000
wire deviceSPIRead				= mem_address[31:28] == 4'b0011 ? 1'b1 : 1'b0;	// 0x30000000
wire deviceUARTTxWrite			= mem_address[31:28] == 4'b0100 ? 1'b1 : 1'b0;	// 0x40000000
wire deviceUARTRxRead			= mem_address[31:28] == 4'b0101 ? 1'b1 : 1'b0;	// 0x50000000
wire deviceUARTByteCountRead	= mem_address[31:28] == 4'b0110 ? 1'b1 : 1'b0;	// 0x60000000
wire deviceGPUFIFOWrite			= mem_address[31:28] == 4'b1000 ? 1'b1 : 1'b0;	// 0x80000000

wire [5:0] deviceRTPort			= {deviceSPIWrite, deviceSPIRead, deviceUARTRxRead, deviceUARTByteCountRead, deviceUARTTxWrite, deviceGPUFIFOWrite};

// Reads are routed from the correct device to one wire
wire [31:0] uartdataout = {24'd0, infifoout};
wire [31:0] uartbytecountout = {22'd0, infifodatacount};
wire [31:0] bus_dataout = deviceUARTRxRead ? uartdataout : (deviceUARTByteCountRead ? uartbytecountout : (deviceSPIRead ? sdrq_dataout : sysmem_dataout));

// This is high if any of the device FIFOs are full or empty depending on read/write
// It allows the CPU side to stall and wait for data access
wire gpustall = deviceGPUFIFOWrite ? gpu_fifowrfull : 1'b0;
wire uartwritestall = deviceUARTTxWrite ? outfifofull : 1'b0;
wire uartreadstall = deviceUARTRxRead ? infifoempty : 1'b0;
wire spiwritestall = deviceSPIWrite ? sdwq_full : 1'b0;
wire spireadstall = deviceSPIRead ? sdrq_empty : 1'b0;
wire bus_stall = gpustall | uartwritestall | uartreadstall | spiwritestall | spireadstall;

// SYSMEM and memory mapped device r/w router
always_comb begin
	// SYSMEM r/w
	bus_address = mem_address;
	bus_writeword = mem_writeword;
	bus_writeena = deviceRTPort == 6'b000000 ? mem_writeena : 4'b0000;
	bus_readena = deviceRTPort == 6'b000000 ? mem_readena : 0;

	// GPU FIFO
	gpu_fifocommand = mem_writeword; // Dword writes, no masking
	gpu_fifowe = deviceGPUFIFOWrite ? ((~gpu_fifowrfull) & (|mem_writeena)) : 1'b0;

	// UART (receive)
	infifore = deviceUARTRxRead ? mem_readena : 1'b0;
	
	// SPI (receive)
	sdrq_re = (deviceSPIRead & (~sdrq_empty)) ? mem_readena : 1'b0;

	// UART (transmit)
	case (mem_writeena)
		4'b1000: begin outfifoin = mem_writeword[31:24]; end
		4'b0100: begin outfifoin = mem_writeword[23:16]; end
		4'b0010: begin outfifoin = mem_writeword[15:8]; end
		4'b0001: begin outfifoin = mem_writeword[7:0]; end
	endcase
	outuartfifowe = deviceUARTTxWrite ? ((~outfifofull) & (|mem_writeena)) : 1'b0;
	
	// SPI (transmit)
	case (mem_writeena)
		4'b1000: begin sdwq_datain = mem_writeword[31:24]; end
		4'b0100: begin sdwq_datain = mem_writeword[23:16]; end
		4'b0010: begin sdwq_datain = mem_writeword[15:8]; end
		4'b0001: begin sdwq_datain = mem_writeword[7:0]; end
	endcase
	sdwq_we = deviceSPIWrite ? ((~sdwq_full) & |mem_writeena) : 1'b0;
end

// =====================================================================================================
// CPU + GPU + System RAM (true dual port) / GPU FIFO (1024 DWORDs)
// =====================================================================================================

wire [31:0] dma_address;
wire [31:0] dma_writeword;
wire [31:0] dma_dataout;
wire [3:0] dma_writeena;

FastSystemMemory SYSRAM(
	// ----------------------------
	// CPU bus for CPU read-write
	// ----------------------------
	.addra(bus_address[16:2]), // 128Kb RAM, 32768 DWORDs, 15 bit address space
	.clka(sysclock60),
	.dina(bus_writeword),
	.douta(sysmem_dataout),
	.wea(bus_address[31]==1'b0 ? bus_writeena : 4'b0000),
	.ena(reset_n & (bus_readena | (|bus_writeena))),
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
	.full(gpu_fifowrfull),
	.din(gpu_fifocommand),
	.wr_en(gpu_fifowe),
	// read
	.empty(gpu_fifordempty),
	.dout(gpu_fifodataout),
	.rd_en(gpu_fifore),
	// ctl
	.wr_clk(sysclock60),
	.rd_clk(gpuclock),
	.rst(reset_p),
	.valid(gpu_fifodatavalid) );

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
	.fifoempty(gpu_fifordempty),
	.fifodout(gpu_fifodataout),
	.fifdoutvalid(gpu_fifodatavalid),
	.fiford_en(gpu_fifore),
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
	.busstall(bus_stall),
	.reset(reset_p),
	// Memory and memory mapped device access
	.memaddress(mem_address),
	.writeword(mem_writeword),
	.mem_data(bus_dataout),
	.mem_writeena(mem_writeena),
	.mem_readena(mem_readena)
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

// -----------------
// SD Card Write
// -----------------
wire sdwq_empty, sqwq_valid;
wire [7:0] sdwq_dataout;
logic sdwq_re=1'b0;
SPIFIFO SDCardWriteFifo(
	// In
	.full(sdwq_full),
	.din(sdwq_datain),
	.wr_en(sdwq_we),
	.wr_clk(sysclock60),
	// Out
	.empty(sdwq_empty),
	.dout(sdwq_dataout),
	.rd_en(sdwq_re),
	.rd_clk(sysclock60),
	.valid(sqwq_valid),
	// Clt
	.rst(reset_p) );

// Pull from write queue and send through SD controller
logic sddatawe = 1'b0;
logic [7:0] sddataout;
logic [1:0] sdqwritestate = 2'b00;
always @(posedge sysclock60) begin

	sdwq_re <= 1'b0;
	sddatawe <= 1'b0;

	if (sdqwritestate == 2'b00) begin
		if ((~sdwq_empty) & sddataoutready) begin
			sdwq_re <= 1'b1;
			sdqwritestate <= 2'b10;
		end
	end else begin
		if (sqwq_valid & sdqwritestate== 2'b10) begin
			sddatawe <= 1'b1;
			sddataout <= sdwq_dataout;
			sdqwritestate <= 2'b01;
		end
		// One clock delay to catch with sddataoutready properly
		if (sdqwritestate <= 2'b01) begin
			sdqwritestate <= 2'b00;
		end
	end

end

// -----------------
// SD Card Read
// -----------------
wire sdrq_full;
logic [7:0] sdrq_datain;
logic sdrq_we = 1'b0;
SPIFIFO SDCardReadFifo(
	// In
	.full(sdrq_full),
	.din(sdrq_datain),
	.wr_en(sdrq_we),
	.wr_clk(sysclock60),
	// Out
	.empty(sdrq_empty),
	.dout(sdrq_dataout),
	.rd_en(sdrq_re),
	.rd_clk(sysclock60),
	.valid(sqrq_valid),
	// Clt
	.rst(reset_p) );

// Push incoming data from SD controller to read queue
wire [7:0] sddatain;
always @(posedge sysclock60) begin
	sdrq_we <= 1'b0;
	if (sddatainready) begin
		sdrq_we <= 1'b1;
		sdrq_datain <= sddatain;
	end
end

// -----------------
// SD Card Controller
// -----------------
SPI_MASTER SDCardController(
        .CLK(sysclock60),
        .RST(reset_p), // spi_cd?
        // SPI MASTER INTERFACE
        .SCLK(spi_sck),
        .CS_N(spi_cs_n),
        .MOSI(spi_mosi),
        .MISO(spi_miso),
        // INPUT USER INTERFACE
        .DIN(sddataout),
        //.DIN_ADDR(1'b0), // this range is [-1:0] since we have only one client to pick, therefure unused
        .DIN_LAST(1'b0),
        .DIN_VLD(sddatawe),
        .DIN_RDY(sddataoutready),
        // OUTPUT USER INTERFACE
        .DOUT(sddatain),
        .DOUT_VLD(sddatainready) );

// =====================================================================================================
// Diagnosis LEDs
// =====================================================================================================

assign led = {spireadstall, spiwritestall, deviceSPIRead, deviceSPIWrite};

endmodule
