`timescale 1ns / 1ps

module nekotop(
	// Input clock
	input CLK_I,

	// Reset on lower panel, rightmost button
	input RST_I,

	// UART pins
	output uart_rxd_out,
	input uart_txd_in,

	// DVI on PMOD ports A+B
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

	// SD Card PMOD on port C
	output spi_cs_n,
	output spi_mosi,
	input spi_miso,
	output spi_sck,
	//inout [1:0] dat, // UNUSED
	input spi_cd
);

wire cpuclock, wallclock, uartbase, gpuclock, vgaclock;
wire clockALocked, clockBLocked, clockCLocked;

clockgen myclock(
	.resetn(~RST_I),			// Incoming external reset (negated)
	.clk_in1(CLK_I),			// Input external clock
	.cpuclock(cpuclock),		// CPU clock
	.wallclock(wallclock),		// Wall clock reference
	.locked(clockALocked) );	// High when clock is stable

peripheralclock myotherclock(
	.resetn(~RST_I),			// Incoming external reset (negated)
	.clk_in1(CLK_I),			// Input external clock
	.uartbase(uartbase),		// Generated UART base clock 
	.locked(clockBLocked) );	// High when clock is stable
	
videoclocks myvideoclocks(
	.resetn(~RST_I),			// Incoming external reset (negated)
	.clk_in1(CLK_I),			// Input external clock
	.gpuclock(gpuclock),		// Generated GPU clock 
	.vgaclock(vgaclock),		// 25Mhz VGA clock
	.locked(clockCLocked) );	// High when clock is stable

// Clock, reset and status wires
wire allClocksLocked = clockALocked & clockBLocked & clockCLocked;
wire reset_p = RST_I | (~allClocksLocked);
wire reset_n = (~RST_I) & allClocksLocked;

// Full 32 bit BYTE address between CPU and devices
wire [31:0] memaddress;

// Data wires from/to CPU to/from RAM
wire [31:0] cpudataout;
wire [31:0] cpudatain;
wire [3:0] cpuwriteena;
wire busstall;
wire SWITCH_IRQ;
wire UART_IRQ;

// Sync to cpu clock
logic [3:0] switches0;
logic [3:0] switches1;
logic [2:0] buttons0;
logic [2:0] buttons1;
always @(posedge cpuclock) begin
	switches0 <= switches;
	buttons0 <= buttons;
	switches1 <= switches0;
	buttons1 <= buttons0;
end

// Data router
devicerouter mydevicetree(
	.uartbase(uartbase),
	.cpuclock(cpuclock),
	.gpuclock(gpuclock),
	.vgaclock(vgaclock),
	.reset_p(reset_p),
	.reset_n(reset_n),
	.busaddress(memaddress),
	.busdatain(cpudataout),
	.busdataout(cpudatain),
	.buswe(cpuwriteena),
	.busre(cpureadena),
	.busstall(busstall),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in),
	.DVI_R(DVI_R),
	.DVI_G(DVI_G),
	.DVI_B(DVI_B),
	.DVI_HS(DVI_HS),
	.DVI_VS(DVI_VS),
	.DVI_DE(DVI_DE),
	.DVI_CLK(DVI_CLK),
	.switches(switches1),
	.buttons(buttons1),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck),
	.spi_cd(spi_cd),
	.SWITCH_IRQ(SWITCH_IRQ),
	.UART_IRQ(UART_IRQ) );
	
wire IRQ = SWITCH_IRQ | UART_IRQ;
wire [1:0] IRQ_TYPE = { SWITCH_IRQ, UART_IRQ };

// CPU core
riscvcpu mycpu(
	.clock(cpuclock),			// CPU clock
	.wallclock(wallclock),		// Wall clock reference
	.reset(reset_p),			// CPU reset line
	.memaddress(memaddress),	// Memory address to operate on
	.cpudataout(cpudataout),	// CPU data to write to external device
	.cpuwriteena(cpuwriteena),	// Write control line
	.cpureadena(cpureadena),	// Read control line
	.cpudatain(cpudatain),		// Data from external device to CPU
	.busstall(busstall),		// Bus is busy, CPU should stall r/w
	.IRQ(IRQ),					// Interrupt request
	.IRQ_TYPE(IRQ_TYPE)			// Interrupt type
	);


endmodule
