`timescale 1ns / 1ps

module ddr3controller(
	input reset,
	input resetn,
	input cpuclock,
	input sys_clk_i,
	input clk_ref_i,
	input deviceDDR3,
	input busre,
	input [3:0] buswe,
	input [31:0] busaddress,
	input [31:0] busdatain,
	output ddr3stall,
	output wire [31:0] ddr3dataout,
	
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
    inout   [15:0]  ddr3_dq );

// DDR3 R/W controller
localparam MAIN_INIT = 3'd0;	
localparam MAIN_IDLE = 3'd1;
localparam MAIN_WAIT_WRITE = 3'd2;
localparam MAIN_WAIT_READ = 3'd3;
localparam MAIN_FINISH_WRITE = 3'd4;
localparam MAIN_FINISH_READ = 3'd5;
logic [2:0] mainstate = MAIN_INIT;

wire calib_done;
wire [11:0] device_temp;

logic [27:0] app_addr = 0;
logic [2:0]  app_cmd = 0;
logic app_en;
wire app_rdy;

logic [127:0] app_wdf_data;
logic app_wdf_wren;
wire app_wdf_rdy;

wire [127:0] app_rd_data;
logic [15:0] app_wdf_mask = 16'h0000; // WARNING: Active Low!
wire app_rd_data_end;
wire app_rd_data_valid;

wire app_sr_req = 0;
wire app_ref_req = 0;
wire app_zq_req = 0;
wire app_sr_active;
wire app_ref_ack;
wire app_zq_ack;

wire ddr3cmdfull, ddr3cmdempty, ddr3cmdvalid;
logic ddr3cmdre = 1'b0, ddr3cmdwe = 1'b0;
logic [64:0] ddr3cmdin;
wire [64:0] ddr3cmdout;

wire ddr3writefull, ddr3writeempty, ddr3writevalid;
logic ddr3writewe = 1'b0, ddr3writere = 1'b0;
logic ddr3writein = 1'b0;
wire ddr3writeout;

wire ddr3readfull, ddr3readempty, ddr3readvalid;
logic ddr3readwe = 1'b0, ddr3readre = 1'b0;
logic [31:0] ddr3readin = 32'd0;
//wire [31:0] ddr3readout;

wire ui_clk;
wire ui_clk_sync_rst;

// System memory - SLOW section
DDR3MIG SlowRAM (
   .ddr3_addr   (ddr3_addr),
   .ddr3_ba     (ddr3_ba),
   .ddr3_cas_n  (ddr3_cas_n),
   .ddr3_ck_n   (ddr3_ck_n),
   .ddr3_ck_p   (ddr3_ck_p),
   .ddr3_cke    (ddr3_cke),
   .ddr3_ras_n  (ddr3_ras_n),
   .ddr3_reset_n(ddr3_reset_n),
   .ddr3_we_n   (ddr3_we_n),
   .ddr3_dq     (ddr3_dq),
   .ddr3_dqs_n  (ddr3_dqs_n),
   .ddr3_dqs_p  (ddr3_dqs_p),
   .ddr3_cs_n   (ddr3_cs_n),
   .ddr3_dm     (ddr3_dm),
   .ddr3_odt    (ddr3_odt),

   .init_calib_complete (calib_done),
   .device_temp(device_temp), // TODO: Can map this to a memory location if needed

   // User interface ports
   .app_addr    (app_addr),
   .app_cmd     (app_cmd),
   .app_en      (app_en),
   .app_wdf_data(app_wdf_data),
   .app_wdf_end (app_wdf_wren),
   .app_wdf_wren(app_wdf_wren),
   .app_rd_data (app_rd_data),
   .app_rd_data_end (app_rd_data_end),
   .app_rd_data_valid (app_rd_data_valid),
   .app_rdy     (app_rdy),
   .app_wdf_rdy (app_wdf_rdy),
   .app_sr_req  (app_sr_req),
   .app_ref_req (app_ref_req),
   .app_zq_req  (app_zq_req),
   .app_sr_active(app_sr_active),
   .app_ref_ack (app_ref_ack),
   .app_zq_ack  (app_zq_ack),
   .ui_clk      (ui_clk),
   .ui_clk_sync_rst (ui_clk_sync_rst),
   .app_wdf_mask(app_wdf_mask),
   // Clock and Reset input ports
   .sys_clk_i (sys_clk_i),
   .clk_ref_i (clk_ref_i),
   .sys_rst (resetn)
  );

localparam INIT = 3'd0;
localparam IDLE = 3'd1;
localparam DECODECMD = 3'd2;
localparam WRITE = 3'd3;
localparam WRITE_DONE = 3'd4;
localparam READ = 3'd5;
localparam READ_DONE = 3'd6;
localparam PARK = 3'd7;
logic [2:0] state = INIT;

localparam CMD_WRITE = 3'b000;
localparam CMD_READ = 3'b001;

// ddr3 driver
always @ (posedge ui_clk) begin
	if (ui_clk_sync_rst) begin
		state <= INIT;
		app_en <= 0;
		app_wdf_wren <= 0;
	end else begin
	
		case (state)
			INIT: begin
				if (calib_done) begin
					state <= IDLE;
				end
			end
			
			IDLE: begin
				ddr3writewe <= 1'b0;
				ddr3readwe <= 1'b0;
				if (~ddr3cmdempty) begin
					ddr3cmdre <= 1'b1;
					state <= DECODECMD;
				end
			end
			
			DECODECMD: begin
				ddr3cmdre <= 1'b0;
				if (ddr3cmdvalid) begin
					if (ddr3cmdout[64]==1'b1)
						state <= WRITE;
					else
						state <= READ;
				end
			end
			
			WRITE: begin
				if (app_rdy & app_wdf_rdy) begin
					state <= WRITE_DONE;
					app_en <= 1;
					app_wdf_wren <= 1;
					app_addr <= {ddr3cmdout[59:35], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits

					unique case (ddr3cmdout[35:34]) // busaddress[3:2])
						2'b11: begin app_wdf_mask <= {ddr3cmdout[63:60],12'hFFF}; end
						2'b10: begin app_wdf_mask <= {4'hF, ddr3cmdout[63:60], 8'hFF}; end
						2'b01: begin app_wdf_mask <= {8'hFF, ddr3cmdout[63:60], 4'hF}; end
						2'b00: begin app_wdf_mask <= {12'hFFF, ddr3cmdout[63:60]}; end
					endcase

					//app_wdf_mask <= 16'h0000;

					app_cmd <= CMD_WRITE;
					app_wdf_data <= {ddr3cmdout[31:0], ddr3cmdout[31:0], ddr3cmdout[31:0], ddr3cmdout[31:0]};
				end
			end

			WRITE_DONE: begin
				if (app_rdy & app_en) begin
					app_en <= 0;
				end
			
				if (app_wdf_rdy & app_wdf_wren) begin
					app_wdf_wren <= 0;
				end
			
				if (~app_en & ~app_wdf_wren) begin
					ddr3writewe <= 1'b1;
					ddr3writein <= 1'b1;
					state <= IDLE;
				end
			end

			READ: begin
				if (app_rdy) begin
					app_en <= 1;
					app_addr <= {ddr3cmdout[59:35], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits
					app_cmd <= CMD_READ;
					state <= READ_DONE;
				end
			end

			READ_DONE: begin
				if (app_rdy & app_en) begin
					app_en <= 0;
				end
			
				if (app_rd_data_valid) begin
					ddr3readwe <= 1'b1;
					unique case (ddr3cmdout[35:34]) // busaddress[3:2])
						2'b11: begin ddr3readin <= app_rd_data[127:96]; end
						2'b10: begin ddr3readin <= app_rd_data[95:64]; end
						2'b01: begin ddr3readin <= app_rd_data[63:32]; end
						2'b00: begin ddr3readin <= app_rd_data[31:0]; end
					endcase
					//ddr3readin <= app_rd_data[31:0];
					state <= IDLE;
				end
			end

			default: state <= INIT;
		endcase
	end
end

// command fifo
ddr3cmdfifo DDR3Cmd(
	.full(ddr3cmdfull),
	.din(ddr3cmdin),
	.wr_en(ddr3cmdwe),
	.wr_clk(cpuclock),
	.empty(ddr3cmdempty),
	.dout(ddr3cmdout),
	.rd_en(ddr3cmdre),
	.valid(ddr3cmdvalid),
	.rd_clk(ui_clk),
	.rst(reset) );

// write done queue
ddr3writedonequeue DDR3WriteDone(
	.full(ddr3writefull),
	.din(ddr3writein),
	.wr_en(ddr3writewe),
	.wr_clk(ui_clk),
	.empty(ddr3writeempty),
	.dout(ddr3writeout),
	.rd_en(ddr3writere),
	.valid(ddr3writevalid),
	.rd_clk(cpuclock),
	.rst(ui_clk_sync_rst) );

// read done queue
ddr3readdonequeue DDR3ReadDone(
	.full(ddr3readfull),
	.din(ddr3readin),
	.wr_en(ddr3readwe),
	.wr_clk(ui_clk),
	.empty(ddr3readempty),
	.dout(ddr3dataout), //ddr3readout),
	.rd_en(ddr3readre),
	.valid(ddr3readvalid),
	.rd_clk(cpuclock),
	.rst(ui_clk_sync_rst) );

always @(posedge cpuclock) begin
	if (reset) begin
		mainstate <= MAIN_INIT;
	end else begin

		case (mainstate)
			MAIN_INIT: begin
				// TODO:
				mainstate <= MAIN_IDLE;
			end

			MAIN_IDLE: begin
				if (deviceDDR3) begin
					if (busre) begin
						ddr3cmdin <= {1'b0, 4'b0, busaddress[27:0], 32'd0};
						ddr3cmdwe <= 1'b1;
						mainstate <= MAIN_WAIT_READ;
					end else if (|buswe) begin
						ddr3cmdin <= {1'b1, ~buswe, busaddress[27:0], busdatain};
						ddr3cmdwe <= 1'b1;
						mainstate <= MAIN_WAIT_WRITE;
					end
				end
			end

			MAIN_WAIT_WRITE: begin
				ddr3cmdwe <= 1'b0;
				if (~ddr3writeempty) begin
					ddr3writere <= 1'b1;
					mainstate <= MAIN_FINISH_WRITE;
				end else begin
					mainstate <= MAIN_WAIT_WRITE;
				end
			end

			MAIN_FINISH_WRITE: begin
				ddr3writere <= 1'b0;
				if (ddr3writevalid) begin // Write ack arrived
					mainstate <= MAIN_IDLE;
				end else begin
					mainstate <= MAIN_FINISH_WRITE;
				end
			end

			MAIN_WAIT_READ: begin
				ddr3cmdwe <= 1'b0;
				if (~ddr3readempty) begin
					ddr3readre <= 1'b1;
					mainstate <= MAIN_FINISH_READ;
				end else begin
					mainstate <= MAIN_WAIT_READ;
				end
			end
			
			MAIN_FINISH_READ: begin
				ddr3readre <= 1'b0;
				if (ddr3readvalid) begin // Read ack arrived
					//ddr3dataout <= ddr3readout;
					mainstate <= MAIN_IDLE;
				end else begin
					mainstate <= MAIN_FINISH_READ;
				end
			end

		endcase

	end
end

// Stall until there's something in the output queues
assign ddr3stall = deviceDDR3 & ((busre&(~ddr3readvalid)) | ((~busre)&(~(mainstate==MAIN_IDLE))));

endmodule
