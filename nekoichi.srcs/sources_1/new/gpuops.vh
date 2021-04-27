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
	// Instruction forms
	// Form 0 (immshort + rd + rs + cmd)
	// [iiiiiiiiiiiiiiiiii iiii][DDD][SSS][-CCC]
	// Form 1 (imm + cmd)
	// [iiiiiiiiiiiiiiiiiiiiiiiiiiii][-CCC]

	// REGSETLOW: Set lower 22 bits of register sd to V if SSS==0
	// [VVVVVVVVVVVVVVVVVV VVVV][DDD][SSS][-001]

	// REGSETHI: Set higher 10 bits of register sd to V if SSS!=0
	// [------------VVVVVV VVVV][DDD][SSS][-001]	

	// MEMWRITE: Write contents of sr to address A
	// [----AAAAAAAAAAAAAA WWWW][---][SSS][-010]

	// CLEAR: Clear the video memory using contents of register rs
	// [------------------ ----][---][SSS][-011]
	
	// SYSDMA: Transfer from SYSRAM to VRAM (from address rs to address rd) by C DWORDs
	// TODO: Source byte mask / destination byte mask?
	// [---- ---- CCCCCCCCCCCCCC][DDD][SSS][-100]
	
	// RASTER: Rasterize one edge packed in rs
	// [---- ---- --------------][---][SSS][-101]

	// TBD	
	// [---- ---- --------------][---][---][-110]
	
	// TBD
	// [---- ---- --------------][---][---][-111]

// ==============================================================

// ===================Fine Raster States=========================

`define FRSTATEBITS 3

`define FRSTATEIDLE			0
`define FRSTATELATCH		1
`define FRSTATERASTERIZE	2

`define FRSTATENONE_MASK		3'b000

`define FRSTATEIDLE_MASK		3'b001
`define FRSTATELATCH_MASK		3'b010
`define FRSTATERASTERIZE_MASK	3'b100
// ==============================================================
