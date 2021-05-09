`timescale 1ns / 1ps

module VideoControllerGen(
		input wire gpuclock,
		input wire vgaclock,
		input wire reset_n,
		input wire writesenabled,
		input wire [11:0] video_x,
		input wire [11:0] video_y,
		input wire [13:0] memaddress,
		input wire [3:0] mem_writeena,
		input wire [31:0] writeword,
		input wire [11:0] lanemask,
		output wire [3:0] red,
		output wire [3:0] green,
		output wire [3:0] blue);

logic [31:0] scanlinecache [0:63];
wire [11:0] pixelX = (video_x-12'd64);
wire [11:0] pixelY = (video_y-12'd48);

wire inDisplayWindow = (video_x >= 64) && (video_y >= 48) && (video_x < 576) && (video_y < 432);	// 512x384 window centered inside 640x480 image
wire [31:0] scanoutaddress = {pixelY[8:1], video_x[5:0]}; // video_x%64   //{pixelY[8:1], pixelX[8:1]} : 16'h0000;
wire [5:0] cachewriteaddress = video_x[5:0]-6'd1; // Since memory data delays 1 clock, run 1 address behind to sync properly
wire [5:0] cachereadaddress = pixelX[8:3];

wire isCachingRow = video_x > 64 ? 1'b0 : 1'b1; // Scanline cache enabled when we're in left window
wire [1:0] videobyteselect = video_x[2:1];

wire [31:0] vram_data[0:11];
logic [7:0] videooutbyte;

assign blue = {videooutbyte[7:6], 2'b00};
assign red = {videooutbyte[5:3], 1'b0}; // TODO: Scanline cache + byteselect to pick the right 8 bit value here
assign green = {videooutbyte[2:0], 1'b0};

// Generate 12 slices of 256*16 pixels of video memory
genvar slicegen;
generate for (slicegen = 0; slicegen < 12; slicegen = slicegen + 1) begin : vram_slices
	VideoMemSlice vramslice_inst(
		// Write to the matching slice
		.addra(memaddress[9:0]),
		.clka(gpuclock),
		.dina(writeword),
		.ena(reset_n),
		// If lane mask is enabled or if this vram slice is in the correct address range, enable writes
		// NOTE: lane mask enable still uses the mem_writeena to control which bytes to update
		.wea( writesenabled & (lanemask[slicegen] | (memaddress[13:10]==slicegen[3:0])) ? mem_writeena : 4'b0000 ),
		// Read out to respective vram_data elements for each slice
		.addrb(scanoutaddress[9:0]),
		.enb(reset_n & (scanoutaddress[13:10]==slicegen[3:0] ? 1'b1:1'b0)),
		.clkb(vgaclock),
		.doutb(vram_data[slicegen]) );
end endgenerate

always @(posedge(vgaclock)) begin
	if (isCachingRow) begin
		scanlinecache[cachewriteaddress] <= vram_data[scanoutaddress[13:10]];
	end else begin
		case (videobyteselect)
			2'b00: begin
				videooutbyte <= inDisplayWindow ? scanlinecache[cachereadaddress][7:0] : 8'd0;
			end
			2'b01: begin
				videooutbyte <= inDisplayWindow ? scanlinecache[cachereadaddress][15:8] : 8'd0;
			end
			2'b10: begin
				videooutbyte <= inDisplayWindow ? scanlinecache[cachereadaddress][23:16] : 8'd0;
			end
			2'b11: begin
				videooutbyte <= inDisplayWindow ? scanlinecache[cachereadaddress][31:24] : 8'd0;
			end
		endcase
	end
end

endmodule
