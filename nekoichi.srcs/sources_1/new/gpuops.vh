// ======================== GPU States ==========================
`define GPUSTATEBITS 9

`define GPUSTATEIDLE			0
`define GPUSTATELATCHCOMMAND	1
`define GPUSTATEEXEC			2
`define GPUSTATECLEAR			3
`define GPUSTATEDMAKICK			4
`define GPUSTATEDMA				5
`define GPUSTATERASTERKICK		6
`define GPUSTATERASTERDETECT	7
`define GPUSTATERASTER			8

`define GPUSTATENONE_MASK			9'b000000000

`define GPUSTATEIDLE_MASK			9'b000000001
`define GPUSTATELATCHCOMMAND_MASK	9'b000000010
`define GPUSTATEEXEC_MASK			9'b000000100
`define GPUSTATECLEAR_MASK			9'b000001000
`define GPUSTATEDMAKICK_MASK		9'b000010000
`define GPUSTATEDMA_MASK			9'b000100000
`define GPUSTATERASTERKICK_MASK		9'b001000000
`define GPUSTATERASTERDETECT_MASK	9'b010000000
`define GPUSTATERASTER_MASK			9'b100000000
// ==============================================================

// =================== GPU Commands =============================

`define GPUCMD_VSYNC		3'b000
`define GPUCMD_SETREG		3'b001
`define GPUCMD_MEMOUT		3'b010
`define GPUCMD_CLEAR		3'b011
`define GPUCMD_SYSDMA		3'b100
`define GPUCMD_RASTER		3'b101
`define GPUCMD_SYSMEMOUT	3'b110
`define GPUCMD_SETVPAGE		3'b111

	// Instruction forms
	// Form 0 (immshort + rd + rs + cmd)
	// [iiiiiiiiiiiiiiiiii iiii][DDD][SSS][-CCC]
	// Form 1 (imm + cmd)
	// [iiiiiiiiiiiiiiiiiiiiiiiiiiii][-CCC]
	
	// GPUCMD_VSYNC
	// Waits for vsync counter greater than the one this command was issued on

	// GPUCMD_SETREG
	// if SSS==0
	//   Sets lower 22 bits of register sd to V
	//   [VVVVVVVVVVVVVVVVVV VVVV][DDD][SSS][-001]
	// if SSS!=0
	//   Sets higher 10 bits of register sd to V
	//   [------------VVVVVV VVVV][DDD][SSS][-001]	

	// GPUCMD_MEMOUT
	// Writes contents of sr to immediate address A
	// [----AAAAAAAAAAAAAA WWWW][---][SSS][-010]

	// GPUCMD_CLEAR
	// Clears the video memory using contents of register rs
	// [------------------ ----][---][SSS][-011]
	
	// GPUCMD_SYSDMA
	// Transfers from SYSRAM to VRAM (from address rs to address rd) by C DWORDs
	// Does zero-masked DMA if M==1 (where it won't copy any zeroes encountered)
	// [---- ---M CCCCCCCCCCCCCC][DDD][SSS][-100]
	
	// RASTER
	// Rasterizes a triangle packed in registers rs & rd (used as rs2)
	// rs contains the 8 bit xy positions for vertices 0 and 1
	// rd contains the 8 bit xy position for vertex 2, and an 8 bit color for fill 
	// [---- ---- --------------][DDD][SSS][-101]

	// GPUCMD_SYSMEMOUT
	// Write the DWORD in rs onto SYSRAM memory address at rs
	// This is to be used as a means to signal CPU from GPU
	// [---- ---- --------------][DDD][SSS][-110]
	
	// GPUCMD_SETVPAGE
	// Sets VRAM page for write to rs, and video scanout to ~rs
	// [---- ---- --------------][---][---][-111]

// ==============================================================

// ===================Fine Raster Stated=========================

`define FRSTATEBITS 3

`define FRSTATEIDLE			0
`define FRSTATELATCH		1
`define FRSTATERASTERIZE	2

`define FRSTATENONE_MASK		3'b000

`define FRSTATEIDLE_MASK		3'b001
`define FRSTATELATCH_MASK		3'b010
`define FRSTATERASTERIZE_MASK	3'b100
// ==============================================================
