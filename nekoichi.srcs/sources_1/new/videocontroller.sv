`timescale 1ns / 1ps

module VideoControllerGen(
		input wire gpuclock,
		input wire vgaclock,
		input wire reset_n,
		input wire writesenabled,
		input wire [11:0] video_x,
		input wire [11:0] video_y,
		input wire [14:0] memaddress,
		input wire [3:0] mem_writeena,
		input wire [31:0] writeword,
		input wire [12:0] lanemask,
		output wire [7:0] paletteindex,
		output wire dataEnable,
		output wire inDisplayWindow );

logic [31:0] scanlinecache [0:127];
wire [11:0] pixelY = (video_y-12'd32);

//           80 DWORDS              +48 DWORDS
// |------------------------------|............|

// In 640x480 region
assign dataEnable = (video_x < 640) && (video_y < 480);

// In 640*416 regioon (with borders on top and bottom)
assign inDisplayWindow = (video_y >= 32) && (video_x < 640) && (video_y < 448); // 320*208 -> 640*416

// video addrs = (Y<<9) + X where X is from 0 to 512 but we only use the 320 section for scanout
wire [31:0] scanoutaddress = {pixelY[9:1], video_x[6:0]}; // stride of 48 at the end of scanline

wire [6:0] cachewriteaddress = video_x[6:0]-7'd1; // Since memory data delays 1 clock, run 1 address behind to sync properly
wire [6:0] cachereadaddress = video_x[9:3];

wire isCachingRow = video_x > 128 ? 1'b0 : 1'b1; // Scanline cache enabled when we're in left window
wire [1:0] videobyteselect = video_x[2:1];

wire [31:0] vram_data[0:12];
logic [7:0] videooutbyte;

assign paletteindex = videooutbyte;

// Generate 13 slices of 512*16 pixels of video memory (out of which we use 320 pixels for each row)
genvar slicegen;
generate for (slicegen = 0; slicegen < 13; slicegen = slicegen + 1) begin : vram_slices
	VideoMemSlice vramslice_inst(
		// Write to the matching slice
		.addra(memaddress[10:0]),
		.clka(gpuclock),
		.dina(writeword),
		.ena(reset_n),
		// If lane mask is enabled or if this vram slice is in the correct address range, enable writes
		// NOTE: lane mask enable still uses the mem_writeena to control which bytes to update
		.wea( writesenabled & (lanemask[slicegen] | (memaddress[14:11]==slicegen[3:0])) ? mem_writeena : 4'b0000 ),
		// Read out to respective vram_data elements for each slice
		.addrb(scanoutaddress[10:0]),
		.enb(reset_n & (scanoutaddress[14:11]==slicegen[3:0] ? 1'b1:1'b0)),
		.clkb(vgaclock),
		.doutb(vram_data[slicegen]) );
end endgenerate

always @(posedge(vgaclock)) begin
	if (isCachingRow) begin
		scanlinecache[cachewriteaddress] <= vram_data[scanoutaddress[14:11]];
	end
end

always_comb begin
	case (videobyteselect)
		2'b00: begin
			videooutbyte <= scanlinecache[cachereadaddress][7:0];
		end
		2'b01: begin
			videooutbyte <= scanlinecache[cachereadaddress][15:8];
		end
		2'b10: begin
			videooutbyte <= scanlinecache[cachereadaddress][23:16];
		end
		2'b11: begin
			videooutbyte <= scanlinecache[cachereadaddress][31:24];
		end
	endcase
end

endmodule
