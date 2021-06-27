// ======================== GPU States ==========================
`define GPUSTATEBITS 6

`define GPUSTATEIDLE			0
`define GPUSTATELATCHCOMMAND	1
`define GPUSTATEEXEC			2
`define GPUSTATECLEAR			3
`define GPUSTATEDMAKICK			4
`define GPUSTATEDMA				5

`define GPUSTATENONE_MASK			0

`define GPUSTATEIDLE_MASK			1
`define GPUSTATELATCHCOMMAND_MASK	2
`define GPUSTATEEXEC_MASK			4
`define GPUSTATECLEAR_MASK			8
`define GPUSTATEDMAKICK_MASK		16
`define GPUSTATEDMA_MASK			32
// ==============================================================

// =================== GPU Commands =============================

`define GPUCMD_VSYNC		3'b000
`define GPUCMD_SETREG		3'b001
`define GPUCMD_SETPALENT	3'b010
`define GPUCMD_CLEAR		3'b011
`define GPUCMD_SYSDMA		3'b100
`define GPUCMD_UNUSED		3'b101
`define GPUCMD_GMEMOUT		3'b110
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

	// GPUCMD_SETPALENT
	// Writes contents of sr to palette entry at P (256 entries,24bit RGB each)
	// [--------------PPPP PPPP][---][SSS][-010]

	// GPUCMD_CLEAR
	// Clears the video memory using contents of register rs
	// [------------------ ----][---][SSS][-011]

	// GPUCMD_SYSDMA
	// Transfers from GMEM to VRAM (from address rs to address rd) by C DWORDs
	// Does zero-masked DMA if M==1 (where it won't copy any zeroes encountered)
	// [---- ---M CCCCCCCCCCCCCC][DDD][SSS][-100]

	// GPUCMD_UNUSED
	// Not used yet
	// [---- ---- --------------][DDD][SSS][-101]

	// GPUCMD_GMEMOUT
	// Write the DWORD in rs onto GMEM memory address at rs
	// This is to be used as a means to signal CPU from GPU
	// [---- ---- --------------][DDD][SSS][-110]

	// GPUCMD_SETVPAGE
	// Sets VRAM page for write to rs, and video scanout to ~rs
	// [---- ---- --------------][---][---][-111]

// ==============================================================
