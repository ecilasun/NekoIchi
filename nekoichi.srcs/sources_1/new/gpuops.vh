// ======================== GPU States ==========================
`define GPUOPWIDTH 5

`define GPUSTATEIDLE			0
`define GPUSTATELATCHCOMMAND	1
`define GPUSTATEEXEC			2
`define GPUSTATECLEAR			3
`define GPUSTATEDMA				4

`define GPUSTATENONE_MASK			5'b00000

`define GPUSTATEIDLE_MASK			5'b00001
`define GPUSTATELATCHCOMMAND_MASK	5'b00010
`define GPUSTATEEXEC_MASK			5'b00100
`define GPUSTATECLEAR_MASK			5'b01000
`define GPUSTATEDMA_MASK			5'b10000
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
	
	// VSYNC: Wait for first scanline to be reached
	// [---- ---- --------------][---][---][0101]
// ==============================================================
