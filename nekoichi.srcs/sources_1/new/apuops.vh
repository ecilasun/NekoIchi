// ======================== APU States ==========================
`define APUSTATEBITS 5

`define APUSTATEIDLE			0
`define APUSTATELATCHCOMMAND	1
`define APUSTATEEXEC			2
`define APUSTATEDMAKICK			3
`define APUSTATEDMA				4

`define APUSTATENONE_MASK			0

`define APUSTATEIDLE_MASK			1
`define APUSTATELATCHCOMMAND_MASK	2
`define APUSTATEEXEC_MASK			4
`define APUSTATEDMAKICK_MASK		8
`define APUSTATEDMA_MASK			16
// ==============================================================

// =================== APU Commands =============================

`define APUCMD_UNUSED0		3'b000
`define APUCMD_SETREG		3'b001
`define APUCMD_UNUSED2		3'b010
`define APUCMD_UNUSED3		3'b011
`define APUCMD_UNUSED4		3'b100
`define APUCMD_UNUSED5		3'b101
`define APUCMD_AMEMOUT		3'b110
`define APUCMD_UNUSED7		3'b111

	// Instruction forms
	// Form 0 (immshort + rd + rs + cmd)
	// [iiiiiiiiiiiiiiiiii iiii][DDD][SSS][-CCC]
	// Form 1 (imm + cmd)
	// [iiiiiiiiiiiiiiiiiiiiiiiiiiii][-CCC]

	// APUCMD_UNUSED0
	// unused

	// APUCMD_SETREG
	// if SSS==0
	//   Sets lower 22 bits of register sd to V
	//   [VVVVVVVVVVVVVVVVVV VVVV][DDD][SSS][-001]
	// if SSS!=0
	//   Sets higher 10 bits of register sd to V
	//   [------------VVVVVV VVVV][DDD][SSS][-001]	

	// APUCMD_UNUSED2
	// unused

	// APUCMD_UNUSED3
	// unused

	// APUCMD_UNUSED4
	// unused

	// APUCMD_UNUSED5
	// unused

	// APUCMD_AMEMOUT
	// Write the DWORD in rs onto AMEM memory address at rs
	// This is to be used as a means to signal CPU from GPU
	// [---- ---- --------------][DDD][SSS][-110]

	// APUCMD_UNUSED7
	// unused

// ==============================================================
