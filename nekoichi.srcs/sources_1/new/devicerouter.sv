`timescale 1ns / 1ps

module devicerouter(
	// Clocks/reset lines
	input uartbase,
	input cpuclock,
	input gpuclock,
	input apuclock,
	input vgaclock,
	input spiclock,
	input audiomasterclock,
	input sys_clk_i,
	input clk_ref_i,
	input reset_p,
	input reset_n,
	// Bus requests/stall
	input [31:0] busaddress,
	input [31:0] busdatain,
	output logic [31:0] busdataout,
	input [3:0] buswe,
	input busre,
	output busstall,
	// UART
	output uart_rxd_out,
	input uart_txd_in,
	// DVI
	output [3:0] DVI_R,
	output [3:0] DVI_G,
	output [3:0] DVI_B,
	output DVI_HS,
	output DVI_VS,
	output DVI_DE,
	output DVI_CLK,
	// Switches/buttons
	input [3:0] switches,
	input [2:0] buttons,
	// SPI
	output spi_cs_n,
	output spi_mosi,
	input spi_miso,
	output spi_sck,
	input spi_cd,
	// DDR3
    output          ddr3_reset_n,
    output  [0:0]   ddr3_cke,
    output  [0:0]   ddr3_ck_p, 
    output  [0:0]   ddr3_ck_n,
    output  [0:0]   ddr3_cs_n,
    output          ddr3_ras_n, 
    output          ddr3_cas_n, 
    output          ddr3_we_n,
    output  [2:0]   ddr3_ba,
    output  [13:0]  ddr3_addr,
    output  [0:0]   ddr3_odt,
    output  [1:0]   ddr3_dm,
    inout   [1:0]   ddr3_dqs_p,
    inout   [1:0]   ddr3_dqs_n,
    inout   [15:0]  ddr3_dq,
	// I2S2 audio
    output tx_mclk,
    output tx_lrck,
    output tx_sclk,
    output tx_sdout,
    // IRQ
	output logic SWITCH_IRQ = 1'b0,
	output logic UART_IRQ = 1'b0 );

// -----------------------------------------------------------------------
// Device selection
// -----------------------------------------------------------------------

wire deviceDDR3					= (busaddress[31:28]==4'b0000) ? 1'b1 : 1'b0;							// 0x00000000 - 0x0FFFFFFF (8Mbytes-128Kbytes due to overlap)
wire deviceGRAM					= (busaddress[31:28]==4'b0001) ? 1'b1 : 1'b0;							// 0x10000000 - 0x1FFFFFFF (Actual range is 128Kbytes; 0x0001FFFF)
wire deviceARAM					= (busaddress[31:28]==4'b0010) ? 1'b1 : 1'b0;							// 0x20000000 - 0x2FFFFFFF (Actual range is 64Kbytes;  0x0000FFFF)
wire deviceGPUFIFOWrite			= {busaddress[31:28], busaddress[5:2]} == 8'b10000000 ? 1'b1 : 1'b0;	// 0x8xxxxx00 GPU command queue
wire deviceUARTByteCountRead	= {busaddress[31:28], busaddress[5:2]} == 8'b10000001 ? 1'b1 : 1'b0;	// 0x8xxxxx04 UART incoming queue byte count
wire deviceUARTRxRead			= {busaddress[31:28], busaddress[5:2]} == 8'b10000010 ? 1'b1 : 1'b0;	// 0x8xxxxx08 UART read port
wire deviceUARTTxWrite			= {busaddress[31:28], busaddress[5:2]} == 8'b10000011 ? 1'b1 : 1'b0;	// 0x8xxxxx0C UART write port
wire deviceSPIRead				= {busaddress[31:28], busaddress[5:2]} == 8'b10000100 ? 1'b1 : 1'b0;	// 0x8xxxxx10 SPI interface to SDCard read port
wire deviceSPIWrite				= {busaddress[31:28], busaddress[5:2]} == 8'b10000101 ? 1'b1 : 1'b0;	// 0x8xxxxx14 SPI interface to SDCart write port
wire deviceSwitchRead			= {busaddress[31:28], busaddress[5:2]} == 8'b10000110 ? 1'b1 : 1'b0;	// 0x8xxxxx18 Device switch states
wire deviceSwitchCountRead		= {busaddress[31:28], busaddress[5:2]} == 8'b10000111 ? 1'b1 : 1'b0;	// 0x8xxxxx1C Switch incoming queue byte count
wire deviceAudioWrite			= {busaddress[31:28], busaddress[5:2]} == 8'b10001000 ? 1'b1 : 1'b0;	// 0x8xxxxx20 Raw audio output port
wire deviceAPUFIFOWrite			= {busaddress[31:28], busaddress[5:2]} == 8'b10001001 ? 1'b1 : 1'b0;	// 0x8xxxxx24 APU command queue

// -----------------------------------------------------------------------
// I2S2 Audio output
// -----------------------------------------------------------------------

wire abfull, abempty, abvalid;
logic [31:0] abdin;
logic abwe = 1'b0;
wire abre;
wire [31:0] abdout;
audiofifo AudioBuffer(
	.wr_clk(cpuclock),
	.full(abfull),
	.din(abdin),
	.wr_en(abwe),
	.rd_clk(audiomasterclock),
	.empty(abempty),
	.dout(abdout),
	.rd_en(abre),
	.valid(abvalid),
	.rst(reset_p) );

i2s2audio soundoutput(
	.resetn(reset_n),
	.cpuclock(cpuclock),
    .audioclock(audiomasterclock),

	.abempty(abempty),
	.abvalid(abvalid),
	.audiore(abre),
    .leftrightchannels(abdout),	// Joint stereo DWORD input

    .tx_mclk(tx_mclk),
    .tx_lrck(tx_lrck),
    .tx_sclk(tx_sclk),
    .tx_sdout(tx_sdout) );

// -----------------------------------------------------------------------
// Device: DDR3
// -----------------------------------------------------------------------

logic [31:0] ddr3datain; // Shadow of busdatain
wire [31:0] ddr3dataout;
wire ddr3stall;

ddr3controller ddr3memory(
	.reset(reset_p),
	.resetn(reset_n),
	.cpuclock(cpuclock),
	.sys_clk_i(sys_clk_i),
	.clk_ref_i(clk_ref_i),
	.deviceDDR3(deviceDDR3),
	.busre(busre),
	.buswe(buswe),
	.busaddress(busaddress),
	.busdatain(ddr3datain),
	.ddr3stall(ddr3stall),
	.ddr3dataout(ddr3dataout),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_ck_p(ddr3_ck_p), 
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_cs_n(ddr3_cs_n),
    .ddr3_ras_n(ddr3_ras_n), 
    .ddr3_cas_n(ddr3_cas_n), 
    .ddr3_we_n(ddr3_we_n),
    .ddr3_ba(ddr3_ba),
    .ddr3_addr(ddr3_addr),
    .ddr3_odt(ddr3_odt),
    .ddr3_dm(ddr3_dm),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dq(ddr3_dq) );

// -----------------------------------------------------------------------
// Device: Switches
// FIFO storing state transitions of device switches
// The switches include:
// SPIChipDetect
// 4 onboard switches
// 3 leftmost pushbuttons
// -----------------------------------------------------------------------

wire switchfull, switchempty;
logic [7:0] switchdatain;
wire [7:0] switchdataout;
wire [9:0] switchdatacount;
wire switchvalid;
logic switchwe=1'b0;
logic switchre=1'b0;

switchfifo DeviceSwitshStates(
	// In
	.full(switchfull),
	.din(switchdatain),
	.wr_en(switchwe),
	.wr_clk(cpuclock),
	// Out
	.empty(switchempty),
	.dout(switchdataout),
	.rd_en(switchre),
	.rd_clk(cpuclock),
	.valid(switchvalid),
	.rd_data_count(switchdatacount),
	// Clt
	.rst(reset_p) );

logic [7:0] prevswitchstate = 8'h00;
logic [7:0] interswitchstate = 8'h00;
logic [7:0] newswitchstate = 8'h00;
wire [7:0] currentswitchstate = {spi_cd, buttons, switches};

always @(posedge cpuclock) begin
	if (reset_p) begin
		prevswitchstate <= currentswitchstate;
	end else begin

		switchwe <= 1'b0;

		// Pipelined action
		interswitchstate <= currentswitchstate;
		newswitchstate <= interswitchstate;
		
		// Check if switch states have changed 
		if (newswitchstate != prevswitchstate) begin
			// Save previous state, and push switch state onto stack
			prevswitchstate <= newswitchstate;
			// Stash switch states into fifo
			switchwe <= 1'b1;
			switchdatain <= newswitchstate;
		end
	end
end

// -----------------------------------------------------------------------
// Device: SPI
// Controls the SDCard unit on PMOD port C
// -----------------------------------------------------------------------

// ------------------
// SD Card Write FIFO
// ------------------

wire sdwq_empty, sqwq_valid;
wire [7:0] sdwq_dataout;
wire sdwq_full;
wire sddataoutready;
logic sdwq_re=1'b0;
logic sdwq_we=1'b0;
logic [7:0] sdwq_datain;
SPIFIFO SDCardWriteFifo(
	// In
	.full(sdwq_full),
	.din(sdwq_datain),
	.wr_en(sdwq_we),
	.wr_clk(cpuclock),
	// Out
	.empty(sdwq_empty),
	.dout(sdwq_dataout),
	.rd_en(sdwq_re),
	.rd_clk(spiclock),
	.valid(sqwq_valid),
	// Clt
	.rst(reset_p) );

// Pull from write queue and send through SD controller
logic sddatawe = 1'b0;
logic [7:0] sddataout;
logic [1:0] sdqwritestate = 2'b00;
always @(posedge spiclock) begin

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
// SD Card Read FIFO
// -----------------

logic sdrq_re = 1'b0;
wire sdrq_full;
wire sdrq_empty;
wire [7:0] sdrq_dataout;
wire sqrq_valid;
logic [7:0] sdrq_datain;
logic sdrq_we = 1'b0;
SPIFIFO SDCardReadFifo(
	// In
	.full(sdrq_full),
	.din(sdrq_datain),
	.wr_en(sdrq_we),
	.wr_clk(spiclock),
	// Out
	.empty(sdrq_empty),
	.dout(sdrq_dataout),
	.rd_en(sdrq_re),
	.rd_clk(cpuclock),
	.valid(sqrq_valid),
	// Clt
	.rst(reset_p) );

// Push incoming data from SD controller to read queue
wire [7:0] sddatain;
wire sddatainready;
always @(posedge cpuclock) begin
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
        .CLK(spiclock),
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

// -----------------------------------------------------------------------
// Device : UART
// Serial communications at 115200bps
// -----------------------------------------------------------------------

// Transmitter (CPU -> FIFO -> Tx)

wire [9:0] outfifodatacount;
wire [7:0] outfifoout;
wire uarttxbusy, outfifofull, outfifoempty, outfifovalid;
logic [7:0] datatotransmit = 8'h00;
logic [7:0] outfifoin; // This will create a latch since it keeps its value
logic transmitbyte = 1'b0;
logic txstate = 1'b0;
logic outuartfifowe = 1'b0;
logic outfifore = 1'b0;

async_transmitter UART_transmit(
	.clk(uartbase),
	.TxD_start(transmitbyte),
	.TxD_data(datatotransmit),
	.TxD(uart_rxd_out),
	.TxD_busy(uarttxbusy) );

// Output FIFO
uartfifo UART_out_fifo(
    // In
    .full(outfifofull),
    .din(outfifoin),		// Data latched from CPU
    .wr_en(outuartfifowe),	// CPU controls write, high for one clock
    // Out
    .empty(outfifoempty),	// Nothing to read
    .dout(outfifoout),		// To transmitter
    .rd_en(outfifore),		// Transmitter can send
    .wr_clk(cpuclock),		// CPU write clock
    .rd_clk(uartbase),		// Transmitter clock runs much slower
    .valid(outfifovalid),	// Read result valid
    // Ctl
    .rst(reset_p),
    .rd_data_count(outfifodatacount) );

// Fifo output serializer
always @(posedge uartbase) begin
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

// Receiver (Rx -> FIFO -> CPU)

wire [9:0] infifodatacount;
wire [7:0] infifoout, uartbytein;
wire infifofull, infifoempty, infifovalid, uartbyteavailable;
logic [7:0] inuartbyte;
logic infifowe = 1'b0;

async_receiver UART_receive(
	.clk(uartbase),
	.RxD(uart_txd_in),
	.RxD_data_ready(uartbyteavailable),
	.RxD_data(uartbytein),
	.RxD_idle(),
	.RxD_endofpacket() );

// Input FIFO
uartfifo UART_in_fifo(
    // In
    .full(infifofull),
    .din(inuartbyte),
    .wr_en(infifowe),
    // Out
    .empty(infifoempty),
    .dout(infifoout),
    .rd_en(busre & deviceUARTRxRead),
    .wr_clk(uartbase),
    .rd_clk(cpuclock),
    .valid(infifovalid),
    // Ctl
    .rst(reset_p),
    .rd_data_count(infifodatacount) );

// Fifo input control
always @(posedge uartbase) begin
	if (uartbyteavailable) begin
		infifowe <= 1'b1;
		inuartbyte <= uartbytein;
	end else begin
		infifowe <= 1'b0;
	end
end

// -----------------------------------------------------------------------
// Machine external interrupt generators
// -----------------------------------------------------------------------

always @(posedge cpuclock) begin
	UART_IRQ <= 1'b0;
	SWITCH_IRQ <= 1'b0;

	// Keep forcing interrupts until the FIFOs are empty
	if (~infifoempty) begin
		UART_IRQ <= 1'b1;
	end
	if (~switchempty) begin
		SWITCH_IRQ <= 1'b1;
	end
end

// -----------------------------------------------------------------------
// Graphics RAM - GPU/CPU shared - 128Kbytes
// CPU can execute code from this area while GPU is accessing it
// 0x10000000
// -----------------------------------------------------------------------

logic [31:0] videomemdatain; // Shadow of busdatain
wire [31:0] vmemdataout;
wire [31:0] gdmaaddress;
wire [31:0] gdmadatain;
wire [31:0] gdmadataout;
wire [3:0] gdmawe;

sysmem GraphicsRAM(
	// CPU direct access port
	.clka(cpuclock),											// Synchronized to CPU clock
	.addra(busaddress[16:2]),									// 15 bit DWORD aligned memory address
	.dina(videomemdatain),										// Data in from CPU
	.douta(vmemdataout),										// Data out from RAM address to CPU
	.wea(deviceGRAM ? buswe : 4'b0000),							// Write control line from CPU 
	.ena(deviceGRAM ? (reset_n & (busre | (|buswe))) : 1'b0),	// Unit enabled only when not in reset and reading or writing 
	// GPU DMA port
	.clkb(gpuclock),											// Synchronized to GPU clock
	.addrb(gdmaaddress[16:2]),									// 15 bit DWORD aligned GPU address
	.dinb(gdmadatain),											// Data from GPU
	.doutb(gdmadataout),										// Data to GPU
	.web(gdmawe),												// GPU write control line
	.enb(reset_n) );											// Reads are always enabled for GPU when not in reset

// -----------------------------------------------------------------------
// Audio RAM - APU/CPU shared - 64Kbytes
// (Doubles as BOOT ROM at startup)
// CPU can execute code from this area while APU is accessing it
// 0x20000000
// -----------------------------------------------------------------------

logic [31:0] audiomemdatain; // Shadow of busdatain
wire [31:0] amemdataout;
wire [31:0] admaaddress;
wire [31:0] admadatain;
wire [31:0] admadataout;
wire [3:0] admawe;

bootmem AudioRAMAndBootROM(
	// CPU direct access port
	.clka(cpuclock),											// Synchronized to CPU clock
	.addra(busaddress[15:2]),									// 14 bit DWORD aligned memory address
	.dina(audiomemdatain),										// Data in from CPU
	.douta(amemdataout),										// Data out from RAM address to CPU
	.wea(deviceARAM ? buswe : 4'b0000),							// Write control line from CPU
	.ena(deviceARAM ? (reset_n & (busre | (|buswe))) : 1'b0),	// Unit enabled only when not in reset and reading or writing
	// APU DMA port
	.clkb(apuclock),											// Synchronized to APU clock
	.addrb(admaaddress[15:2]),									// 14 bit DWORD aligned APU address
	.dinb(admadatain),											// Data from APU
	.doutb(admadataout),										// Data to APU
	.web(admawe),												// APU write control line
	.enb(reset_n) );											// Reads are always enabled for GPU when not in reset

// -----------------------------------------------------------------------
// Color palette
// -----------------------------------------------------------------------

wire palettewe;
wire [7:0] paletteaddress;
wire [7:0] palettereadaddress;
wire [31:0] palettedata;

logic [31:0] paletteentries[0:255];

initial begin
	$readmemh("colorpalette.mem", paletteentries);
end

always @(posedge gpuclock) begin
	if (palettewe)
		paletteentries[paletteaddress] <= palettedata;
end

wire [31:0] paletteout;
assign paletteout = paletteentries[palettereadaddress];

// -----------------------------------------------------------------------
// GPU
// -----------------------------------------------------------------------

wire [31:0] gpu_fifodataout;
wire gpu_fifowrfull;
wire gpu_fifordempty;
wire gpu_fifodatavalid;
wire gpu_fifore;
wire videopage;

logic [31:0] gpu_fifocommand;
logic [31:0] vsync_signal = 32'd0;
logic gpu_fifowe;

wire [14:0] gpuwriteaddress;
wire [3:0] gpuwriteena;
wire [31:0] gpuwriteword;
wire [12:0] gpulanewritemask;

GPU rv32gpu(
	.clock(gpuclock),					// GPU clock
	.reset(reset_p),					// Reset line
	.vsync(vsync_signal),				// Input from vsync FIFO
	.videopage(videopage),				// Video page select line
	// FIFO control
	.fifoempty(gpu_fifordempty),
	.fifodout(gpu_fifodataout),
	.fifdoutvalid(gpu_fifodatavalid),
	.fiford_en(gpu_fifore),
	// VRAM output
	.vramaddress(gpuwriteaddress),		// VRAM write address
	.vramwe(gpuwriteena),				// VRAM write enable line
	.vramwriteword(gpuwriteword),		// Data to write to VRAM
	.lanemask(gpulanewritemask),		// Video memory lane force enable mask
	// GRAM input/output 
	.dmaaddress(gdmaaddress),			// DMA memory address in GRAM
	.dmawriteword(gdmadatain),			// Input to DMA channel of GRAM
	.dma_data(gdmadataout),				// Output from DMA channel of GRAM
	.dmawe(gdmawe),	 					// DMA write control
	// Color palette write channel
	.palettewe(palettewe),				// Color palette write control
	.paletteaddress(paletteaddress),	// Address to write the color value to
	.palettedata(palettedata) );		// Color value to write to the palette

// -----------------------------------------------------------------------
// GPU FIFO
// -----------------------------------------------------------------------

gpufifo GPUCommands(
	// Write
	.full(gpu_fifowrfull),
	.din(gpu_fifocommand),
	.wr_en(gpu_fifowe),
	// Read
	.empty(gpu_fifordempty),
	.dout(gpu_fifodataout),
	.rd_en(gpu_fifore),
	// Control
	.wr_clk(cpuclock),
	.rd_clk(gpuclock),
	.rst(reset_p),
	.valid(gpu_fifodatavalid) );
	
// -----------------------------------------------------------------------
// APU
// -----------------------------------------------------------------------

wire [31:0] apu_fifodataout;
wire apu_fifowrfull;
wire apu_fifordempty;
wire apu_fifodatavalid;
wire apu_fifore;

logic [31:0] apu_fifocommand;
logic apu_fifowe;

APU rv32apu(
	.clock(apuclock),					// APU clock
	.reset(reset_p),					// Reset line
	// FIFO control
	.fifoempty(apu_fifordempty),
	.fifodout(apu_fifodataout),
	.fifdoutvalid(apu_fifodatavalid),
	.fiford_en(apu_fifore),
	// GRAM input/output 
	.dmaaddress(admaaddress),			// DMA memory address in ARAM
	.dmawriteword(admadatain),			// Input to DMA channel of ARAM
	.dma_data(admadataout),				// Output from DMA channel of ARAM
	.dmawe(admawe) ); 					// DMA write control

// -----------------------------------------------------------------------
// APU FIFO
// -----------------------------------------------------------------------

gpufifo APUCommands(
	// Write
	.full(apu_fifowrfull),
	.din(apu_fifocommand),
	.wr_en(apu_fifowe),
	// Read
	.empty(apu_fifordempty),
	.dout(apu_fifodataout),
	.rd_en(apu_fifore),
	// Control
	.wr_clk(cpuclock),
	.rd_clk(apuclock),
	.rst(reset_p),
	.valid(apu_fifodatavalid) );

// -----------------------------------------------------------------------
// DVI
// -----------------------------------------------------------------------

wire [11:0] video_x;
wire [11:0] video_y;
wire [7:0] PALETTEINDEX_ONE;
wire [7:0] PALETTEINDEX_TWO;

wire dataEnableA, dataEnableB;
wire inDisplayWindowA, inDisplayWindowB;

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
	.paletteindex(PALETTEINDEX_ONE),
	.dataEnable(dataEnableA),
	.inDisplayWindow(inDisplayWindowA) );

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
	.paletteindex(PALETTEINDEX_TWO),
	.dataEnable(dataEnableB),
	.inDisplayWindow(inDisplayWindowB) );

wire vsync_we;
logic [31:0] vsynccounter;

wire dataEnable = videopage == 1'b0 ? dataEnableA : dataEnableB;
wire inDisplayWindow = videopage == 1'b0 ? inDisplayWindowA : inDisplayWindowB;
assign DVI_DE = dataEnable;
assign palettereadaddress = (videopage == 1'b0) ? PALETTEINDEX_ONE : PALETTEINDEX_TWO;
// TODO: Depending on video more, use palette out or the byte (PALETTEINDEX_ONE/PALETTEINDEX_TWO) as RGB color
// May also want to introduce a secondary palette?
wire [3:0] VIDEO_B = paletteout[7:4];
wire [3:0] VIDEO_R = paletteout[15:12];
wire [3:0] VIDEO_G = paletteout[23:20];

// TODO: Border color
assign DVI_R = inDisplayWindow ? (dataEnable ? VIDEO_R : 4'b0010) : 1'b0;
assign DVI_G = inDisplayWindow ? (dataEnable ? VIDEO_G : 4'b0010) : 1'b0;
assign DVI_B = inDisplayWindow ? (dataEnable ? VIDEO_B : 4'b0010) : 1'b0;
assign DVI_CLK = vgaclock;

vgatimer VideoScanout(
		.rst_i(reset_p),
		.clk_i(vgaclock),
        .hsync_o(DVI_HS),
        .vsync_o(DVI_VS),
        .counter_x(video_x),
        .counter_y(video_y),
        .vsynctrigger_o(vsync_we),
        .vsynccounter(vsynccounter) );

// -----------------------------------------------------------------------
// Domain crossing Vsync
// -----------------------------------------------------------------------

wire [31:0] vsync_fastdomain;
wire vsyncfifoempty;
wire vsyncfifofull;
wire vsyncfifovalid;

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

// -----------------------------------------------------------------------
// Bus traffic control and routing
// -----------------------------------------------------------------------

wire [31:0] uartdataout = {24'd0, infifoout};
wire [31:0] uartbytecountout = {22'd0, infifodatacount};
wire [31:0] switchdatacountout = {22'd0, switchdatacount};
wire [31:0] sddatawide = {24'd0, sdrq_dataout};
wire [31:0] switchdatawide = switchempty ? {24'd0, newswitchstate} : {24'd0, switchdataout};

always_comb begin
	unique case(1'b1)
		deviceUARTRxRead: busdataout = uartdataout;
		deviceUARTByteCountRead: busdataout = uartbytecountout;
		deviceSPIRead: busdataout = sddatawide;
		deviceSwitchRead: busdataout = switchdatawide;
		deviceSwitchCountRead: busdataout = switchdatacountout;
		deviceDDR3: busdataout = ddr3dataout;
		deviceGRAM: busdataout = vmemdataout;
		deviceARAM: busdataout = amemdataout;
	endcase
end

wire gpustall = deviceGPUFIFOWrite ? gpu_fifowrfull : 1'b0;
wire apustall = deviceAPUFIFOWrite ? apu_fifowrfull : 1'b0;
wire uartwritestall = deviceUARTTxWrite ? outfifofull : 1'b0;
wire uartreadstall = deviceUARTRxRead ? infifoempty : 1'b0;
wire spiwritestall = deviceSPIWrite ? sdwq_full : 1'b0;
wire spireadstall = deviceSPIRead ? sdrq_empty : 1'b0;
wire audiostall = deviceAudioWrite ? abfull : 1'b0;
// NOTE: Switch reads will never stall, but either return instant state or cached state from FIFO

assign busstall = uartwritestall | uartreadstall | gpustall | apustall | spiwritestall | spireadstall | ddr3stall | audiostall;

always_comb begin

	ddr3datain = busdatain;

	abdin = busdatain;
	abwe = deviceAudioWrite ? ((~abfull) & (|buswe)) : 1'b0;

	// For graphics memory writes from CPU
	if (deviceGRAM & (|buswe)) videomemdatain = busdatain;

	// For audio memory writes from CPU
	if (deviceARAM & (|buswe)) audiomemdatain = busdatain;

	// GPU command fifo write control
	gpu_fifocommand = busdatain; // DWORD writes only, no byte masking
	gpu_fifowe = deviceGPUFIFOWrite ? ((~gpu_fifowrfull) & (|buswe)) : 1'b0;

	// Audio command fifo write control
	apu_fifocommand = busdatain; // DWORD writes only, no byte masking
	apu_fifowe = deviceAPUFIFOWrite ? ((~apu_fifowrfull) & (|buswe)) : 1'b0;

	// SPI (receive)
	sdrq_re = (deviceSPIRead & (~sdrq_empty)) ? busre : 1'b0;

	// Switch (receive)
	switchre = (deviceSwitchRead & (~switchempty)) ? busre : 1'b0;

	// UART (transmit)
	case (buswe)
		4'b1000: begin outfifoin = busdatain[31:24]; end
		4'b0100: begin outfifoin = busdatain[23:16]; end
		4'b0010: begin outfifoin = busdatain[15:8]; end
		4'b0001: begin outfifoin = busdatain[7:0]; end
	endcase
	outuartfifowe = deviceUARTTxWrite ? ((~outfifofull) & (|buswe)) : 1'b0;

	// SPI (transmit)
	case (buswe)
		4'b1000: begin sdwq_datain = busdatain[31:24]; end
		4'b0100: begin sdwq_datain = busdatain[23:16]; end
		4'b0010: begin sdwq_datain = busdatain[15:8]; end
		4'b0001: begin sdwq_datain = busdatain[7:0]; end
	endcase
	sdwq_we = deviceSPIWrite ? ((~sdwq_full) & (|buswe)) : 1'b0;
end

endmodule
