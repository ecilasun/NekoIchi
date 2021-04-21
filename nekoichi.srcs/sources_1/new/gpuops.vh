// ======================== GPU States ==========================
`define GPUSTATEBITS 6

`define GPUSTATEIDLE			0
`define GPUSTATELATCHCOMMAND	1
`define GPUSTATEEXEC			2
`define GPUSTATECLEAR			3
`define GPUSTATEDMAKICK			4
`define GPUSTATEDMA				5

`define GPUSTATENONE_MASK			6'b000000

`define GPUSTATEIDLE_MASK			6'b000001
`define GPUSTATELATCHCOMMAND_MASK	6'b000010
`define GPUSTATEEXEC_MASK			6'b000100
`define GPUSTATECLEAR_MASK			6'b001000
`define GPUSTATEDMAKICK_MASK		6'b010000
`define GPUSTATEDMA_MASK			6'b100000
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
	
	// TBD
	// [---- ---- --------------][---][---][-101]

	// TBD	
	// [---- ---- --------------][---][---][-110]
	
	// TBD
	// [---- ---- --------------][---][---][-111]

// ==============================================================
