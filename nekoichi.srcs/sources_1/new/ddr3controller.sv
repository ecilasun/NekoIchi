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
	output logic [31:0] ddr3dataout,
	
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
localparam MAIN_FINISH_READ = 3'd4;
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
logic [152:0] ddr3cmdin;
wire [152:0] ddr3cmdout;

wire ddr3readfull, ddr3readempty, ddr3readvalid;
logic ddr3readwe = 1'b0, ddr3readre = 1'b0;
logic [127:0] ddr3readin = 128'd0;

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
				ddr3readwe <= 1'b0;
				if (~ddr3cmdempty) begin
					ddr3cmdre <= 1'b1;
					state <= DECODECMD;
				end
			end
			
			DECODECMD: begin
				ddr3cmdre <= 1'b0;
				if (ddr3cmdvalid) begin
					if (ddr3cmdout[152]==1'b1) // Write request?
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
					app_addr <= {1'b0, ddr3cmdout[151:128], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits, top bit is supposed to stay zero
					app_wdf_mask <= 16'h0000; // Always write the full 128bits
					app_cmd <= CMD_WRITE;
					app_wdf_data <= ddr3cmdout[127:0]; // 128bit value from cache
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
					state <= IDLE;
				end
			end

			READ: begin
				if (app_rdy) begin
					app_en <= 1;
					app_addr <= {1'b0, ddr3cmdout[151:128], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits, top bit is supposed to stay zero
					app_cmd <= CMD_READ;
					state <= READ_DONE;
				end
			end

			READ_DONE: begin
				if (app_rdy & app_en) begin
					app_en <= 0;
				end
			
				if (app_rd_data_valid) begin
					// After this step, full 128bit value will be available on the
					// ddr3readre when read is asserted and ddr3readvalid is high
					ddr3readwe <= 1'b1;
					ddr3readin <= app_rd_data;
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
	
// read done queue
wire [127:0] ddr3readout;
ddr3readdonequeue DDR3ReadDone(
	.full(ddr3readfull),
	.din(ddr3readin),
	.wr_en(ddr3readwe),
	.wr_clk(ui_clk),
	.empty(ddr3readempty),
	.dout(ddr3readout),
	.rd_en(ddr3readre),
	.valid(ddr3readvalid),
	.rd_clk(cpuclock),
	.rst(ui_clk_sync_rst) );


// ------------------
// DDR3 cache
// ------------------

//logic [31:0] ddr3datain; // Shadow of busdatain

wire [15:0] ctag = busaddress[27:12]; // Ignore 4 highest bits since only r/w for DDR3 are routed here
wire [7:0] cline = busaddress[11:4];
wire [1:0] coffset = busaddress[3:2]; // 4xDWORD (128bits) aligned
wire [31:0] cwidemask = {{8{buswe[3]}}, {8{buswe[2]}}, {8{buswe[1]}}, {8{buswe[0]}}};
wire [31:0] cwidemaskn = {{8{~buswe[3]}}, {8{~buswe[2]}}, {8{~buswe[1]}}, {8{~buswe[0]}}};

// The division of address into cache, device and byte index data is as follows
// device  tag              line     offset  byteindex
// 0000    0000000000000000 00000000 00      00

logic cachedirty[0:255];
logic [15:0] cachetags[0:255];
logic [127:0] cache[0:255];

initial begin
	integer i;
	// All pages are 'clean', but all tags are invalid and cache is zeroed out by default
	for (int i=0;i<256;i=i+1) begin
		cachedirty[i] = 1'b0;
		cachetags[i] = 16'hFFFF;
		cache[i] = 128'd0;
	end
end

localparam DDR3_IDLE = 3'd0;
localparam DDR3_WRITEBACK = 3'd1;
localparam DDR3_POPULATE = 3'd2;
localparam DDR3_READWAIT = 3'd3;
localparam DDR3_UPDATECACHELINE = 3'd4;

logic [3:0] DDR3state = DDR3_IDLE; // Default to idle
logic DDR3ready = 1'b0;
wire DDR3cachehit = (deviceDDR3 & (cachetags[cline] == ctag)) ? 1'b1 : 1'b0;

always_ff @(posedge cpuclock) begin
	if (~resetn) begin
		// 
	end else begin
	
		DDR3ready <= 1'b0;
	
		case(DDR3state)
			DDR3_IDLE: begin
				// This should only happen for ARAM
				if (deviceDDR3 & (busre | (|buswe))) begin
	
					if (cachetags[cline] == ctag) begin // Entry in cache
					
						// Read dword at offset
						if (busre) begin
							case (coffset)
								2'b00: ddr3dataout <= cache[cline][31:0];
								2'b01: ddr3dataout <= cache[cline][63:32];
								2'b10: ddr3dataout <= cache[cline][95:64];
								2'b11: ddr3dataout <= cache[cline][127:96];
							endcase
						end
	
						// Write onto dword at offset using write mask to update modified section only
						if (|buswe) begin
							case (coffset)
								// TODO: we have a write mask in this device...
								2'b00: cache[cline][31:0] <= (cwidemaskn&cache[cline][31:0]) | (cwidemask&busdatain);
								2'b01: cache[cline][63:32] <= (cwidemaskn&cache[cline][63:32]) | (cwidemask&busdatain);
								2'b10: cache[cline][95:64] <= (cwidemaskn&cache[cline][95:64]) | (cwidemask&busdatain);
								2'b11: cache[cline][127:96] <= (cwidemaskn&cache[cline][127:96]) | (cwidemask&busdatain);
							endcase
							// This cache line is now dirty
							cachedirty[cline] <= 1'b1;
						end
						
						DDR3ready <= (|buswe) | busre;

					end else begin // Entry not in cache
						// Do we need to flush then populate?
						if (cachedirty[cline]) begin
							DDR3state <= DDR3_WRITEBACK; // WRITEBACK chains to POPULATE
						end else begin
							DDR3state <= DDR3_POPULATE; // Only POPULATE required
						end
					end
				end
			end

			DDR3_WRITEBACK: begin
				// Write back old cache line contents to old address
				ddr3cmdin <= {1'b1, cachetags[cline], cline, cache[cline]};
				ddr3cmdwe <= 1'b1;
				// NOTE: commands are executed sequentially on the DDR3 interface side
				// Therefore we can queue up a write and then a read
				// and do not require a wait afterwards except for the read.
				// Re-populate this cache line
				DDR3state <= DDR3_POPULATE;
			end

			DDR3_POPULATE: begin
				// Load contents to new address, discarding current cache line (either evicted or discarded)
				ddr3cmdin <= {1'b0, ctag, cline, 128'd0};
				ddr3cmdwe <= 1'b1;
				// Wait for read result
				DDR3state <= DDR3_READWAIT;
			end

			DDR3_READWAIT: begin
				ddr3cmdwe <= 1'b0;
				if (~ddr3readempty) begin
					// Read result available for this cache line
					// Request to read it
					ddr3readre <= 1'b1;
					DDR3state <= DDR3_UPDATECACHELINE;
				end else begin
					DDR3state <= DDR3_READWAIT;
				end
			end

			DDR3_UPDATECACHELINE: begin
				// Stop result read request
				ddr3readre <= 1'b0;
				if (ddr3readvalid) begin
					// Update the tag for this line
					cachetags[cline] <= ctag;
					// Grab the data output at this address
					cache[cline] <= ddr3readout; // NOTE: This needs to be notified by DDR3 driver
					// No longer dirty
					cachedirty[cline] <= 1'b0;
					DDR3state <= DDR3_IDLE;
				end else begin
					// Wait in this state until a 
					DDR3state <= DDR3_UPDATECACHELINE;
				end
			end

		endcase

	end
end

assign ddr3stall = deviceDDR3 ? ~(DDR3cachehit & DDR3ready) : 1'b0; // Stall during cache miss

endmodule
