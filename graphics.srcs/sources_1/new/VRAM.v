`timescale 1ns / 1ps

module VRAM(
		input wire sysclock,
		input wire clockDVI,
		input wire reset_n,
		input wire [11:0] video_x,
		input wire [11:0] video_y,
		input wire [31:0] memaddress,
		input wire [3:0] mem_writeena,
		input wire [31:0] writeword,
		output wire [7:0] red,
		output wire [7:0] green,
		output wire [7:0] blue);
		
reg [31:0] scanlinecache [0:63];
wire [11:0] pixelX = (video_x-12'd64);
wire [11:0] pixelY = (video_y-12'd48);

wire inDisplayWindow = (video_x >= 64) && (video_y >= 48) && (video_x < 576) && (video_y < 432);	// 512x384 window centered inside 640x480 image
wire [31:0] scanoutaddress = {pixelY[8:1], video_x[5:0]}; // video_x%64   //{pixelY[8:1], pixelX[8:1]} : 16'h0000;
wire [5:0] cachewriteaddress = video_x[5:0]-6'd1; // Since memory data delays 1 clock, run 1 address behind to sync properly
wire [5:0] cachereadaddress = pixelX[8:3];

wire isCachingRow = video_x > 64 ? 1'b0 : 1'b1; // Scanline cache enabled when we're in left window
wire [1:0] videobyteselect = video_x[2:1];

wire [31:0] vram_data;
reg [7:0] videooutbyte;

assign blue = {1'b0, videooutbyte[7:6], 5'b00000};
assign red = {1'b0, videooutbyte[5:3], 4'b0000}; // TODO: Scanline cache + byteselect to pick the right 8 bit value here
assign green = {1'b0, videooutbyte[2:0], 4'b0000};

blk_mem_gen_1 videomemory(
	.addra(memaddress[15:2]), // 256x192x8bpp buffer, 12288 DWORDs, 14 bit address space
	.clka(sysclock),
	.dina(writeword),
	.ena(reset_n),
	.wea(memaddress[31]==1'b1 ? mem_writeena : 4'b0000), // address on or above 0x80000000
	.addrb(scanoutaddress[13:0]),
	.clkb(clockDVI),
	.doutb(vram_data) );

always @(posedge(clockDVI)) begin
	if (isCachingRow) begin
		scanlinecache[cachewriteaddress] <= vram_data;
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
