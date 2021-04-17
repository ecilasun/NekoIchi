// ======================== GPU States ==========================
`define GPUOPWIDTH 4

`define GPUSTATEIDLE	0
`define GPUSTATEEXEC	1
`define GPUSTATECLEAR	2
`define GPUSTATEDMA		3

`define GPUSTATENONE_MASK	4'b0000

`define GPUSTATEIDLE_MASK	4'b0001
`define GPUSTATEEXEC_MASK	4'b0010
`define GPUSTATECLEAR_MASK	4'b0100
`define GPUSTATEDMA_MASK	4'b1000
// ==============================================================

// =================== GPU Commands =============================
	// Instruction forms
	// Form 0 (immshort + rd + rs + cmd)
	// [iiiiiiiiiiiiiiiiii iiii][DDD][SSS][CCCC]
	// Form 1 (imm + cmd)
	// [iiiiiiiiiiiiiiiiiiiiiiiiiiii][CCCC]

	// REGSETLOW: Set lower 22 bits of register sd to V if SSS==0
	// [VVVVVVVVVVVVVVVVVV VVVV][DDD][SSS][0001]

	// REGSETHI: Set higher 10 bits of register sd to V if SSS!=0
	// [------------VVVVVV VVVV][DDD][SSS][0001]	

	// MEMWRITE: Write contents of sr to address A
	// [----AAAAAAAAAAAAAA WWWW][---][SSS][0010]

	// CLEAR: Clear the video memory using contents of register rs
	// [------------------ ----][---][SSS][0011]
	
	// SYSDMA: Transfer from SYSRAM to VRAM (from address rs to address rd) by C DWORDs
	// TODO: Source byte mask / destination byte mask?
	// [---- ---- CCCCCCCCCCCCCC][DDD][SSS][0100]
// ==============================================================
