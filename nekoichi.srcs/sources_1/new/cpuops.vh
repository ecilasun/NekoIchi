// ========================== Memory ============================
`define CPU_RESET_VECTOR 32'h00000100
// ==============================================================

// ======================== CPU States ==========================
`define CPUSTAGECOUNT           12

`define CPUFETCH				0
`define CPUDECODE				1
`define CPUSTALLM				2
`define CPUEXEC					3
`define CPULOADCOMPLETE			4
`define CPULOADFCOMPLETE		5
`define CPULOADWAIT				6
`define CPUSTORE				7
`define CPUSTOREF				8
`define CPURETIREINSTRUCTION	9
`define CPUSTALLF				10
`define CPUSTALLFF				11

`define CPUNONE_MASK				12'b000000000000
`define CPUFETCH_MASK				12'b000000000001
`define CPUDECODE_MASK				12'b000000000010
`define CPUSTALLM_MASK				12'b000000000100
`define CPUEXEC_MASK				12'b000000001000
`define CPULOADCOMPLETE_MASK		12'b000000010000
`define CPULOADFCOMPLETE_MASK		12'b000000100000
`define CPULOADWAIT_MASK			12'b000001000000
`define CPUSTORE_MASK				12'b000010000000
`define CPUSTOREF_MASK				12'b000100000000
`define CPURETIREINSTRUCTION_MASK	12'b001000000000
`define CPUSTALLF_MASK				12'b010000000000
`define CPUSTALLFF_MASK				12'b100000000000
// ==============================================================

// ======================== RV32 I ==============================
//       			[6:0]		[14:12] [31:25] [24:20]
`define LUI			7'b0110111  //+
`define AUIPC		7'b0010111  //+
`define JAL			7'b1101111  //+
`define JALR		7'b1100111	//+ 000
`define BEQ			7'b1100011	//+ 000
`define BNE			7'b1100011	//+ 001
`define BLT			7'b1100011	//+ 100
`define BGE			7'b1100011	//+ 101
`define BLTU		7'b1100011	//+ 110
`define BGEU		7'b1100011	//+ 111
`define LB			7'b0000011	//+ 000
`define LH			7'b0000011	//+ 001
`define LW			7'b0000011	//+ 010
`define LBU			7'b0000011	//+ 100
`define LHU			7'b0000011	//+ 101
`define SB			7'b0100011	//+ 000
`define SH			7'b0100011	//+ 001
`define SW			7'b0100011	//+ 010
`define ADDI		7'b0010011	//+ 000
`define SLTI		7'b0010011	//+ 010
`define SLTIU		7'b0010011	//+ 011
`define XORI		7'b0010011	//+ 100
`define ORI			7'b0010011	//+ 110
`define ANDI		7'b0010011	//+ 111
`define SLLI		7'b0010011	//+ 001  0000000
`define SRLI		7'b0010011	//+ 101  0000000
`define SRAI		7'b0010011	//+ 101  0100000
`define ADD			7'b0110011	//+ 000  0000000
`define SUB			7'b0110011	//+ 000  0100000
`define SLL			7'b0110011	//+ 001  0000000
`define SLT			7'b0110011	//+ 010  0000000
`define SLTU		7'b0110011	//+ 011  0000000
`define XOR			7'b0110011	//+ 100  0000000
`define SRL			7'b0110011	//+ 101  0000000
`define SRA			7'b0110011	//+ 101  0100000
`define OR			7'b0110011	//+ 110  0000000
`define AND			7'b0110011	//+ 111  0000000
`define FENCE		7'b0001111	// 000
`define ECALL		7'b1110011	// 000  0000000  00000
`define EBREAK		7'b1110011	// 000  0000000  00001
// ==============================================================

// ======================== RV32 M ==============================
//       			[6:0]		[14:12] [31:25] [24:20]
`define MUL			7'b0110011	// 000  0000001
`define MULH		7'b0110011	// 001  0000001
`define MULHSU		7'b0110011	// 010  0000001
`define MULHU		7'b0110011	// 011  0000001
`define DIV			7'b0110011	// 100  0000001
`define DIVU		7'b0110011	// 101  0000001
`define REM			7'b0110011	// 110  0000001
`define REMU		7'b0110011	// 111  0000001
// ==============================================================

// ======================== RV32 F (single precision) ===========
// Memory ops
`define FLW         7'b0000111    //+
`define FSW         7'b0100111    //+

// Fused ops
`define FMADD       7'b1000011    //+
`define FMSUB       7'b1000111    //+
`define FNMSUB      7'b1001011    //+
`define FNMADD      7'b1001111    //+

//                    [31:25]         [24:20]    [14:12]
// Simple math
`define FADD        7'b0000000    //+ 
`define FSUB        7'b0000100    //+ 
`define FMUL        7'b0001000    //+  
`define FDIV        7'b0001100    //+  
`define FSQRT       7'b0101100    //+ 00000

// Sign injection
`define FSGNJ       7'b0010000    //+            000
`define FSGNJN      7'b0010000    //+            001
`define FSGNJX      7'b0010000    //+            010

// Comparison / classification
`define FMIN        7'b0010100    //+            000
`define FMAX        7'b0010100    //+            001
`define FEQ         7'b1010000    //+            010
`define FLT         7'b1010000    //+            001
`define FLE         7'b1010000    //+            000
`define FCLASS      7'b1110000    //  00000      001

// Conversion from/to integer
`define FCVTWS      7'b1100000    //+ 00000
`define FCVTWUS     7'b1100000    //+ 00001
`define FCVTSW      7'b1101000    //+ 00000
`define FCVTSWU     7'b1101000    //+ 00001

// Move from/to integer registers
`define FMVXW       7'b1110000    //+ 00000      000
`define FMVWX       7'b1111000    //+ 00000      000
// ==============================================================

// ======================== RV32 C ==============================
// Quadrant 0
`define CADDI4SPN	5'b00000 // RES, nzuimm=0 +
//`define CFLD		5'b00100 // 32/64
//`define CLQ			5'b00100 // 128
`define CLW			5'b01000 // 32? +
//`define CFLW		5'b01100 // 32
//`define CLD			5'b01100 // 64/128 
//`define CFSD		5'b10100 // 32/64
//`define CSQ			5'b10100 // 128
`define CSW			5'b11000 // 32? +
//`define CFSW		5'b11100 // 32 
//`define CSD			5'b11100 // 61/128
// Quadrant 1									 [12] [11:10] [6:5]
`define CNOP		5'b00001 // HINT, nzimm!=0 +
`define CADDI		5'b00001 // HINT, nzimm=0 +
`define CJAL		5'b00101 // 32 +
//`define CADDIW		5'b00101 // 64/128
`define CLI			5'b01001 //+
`define CADDI16SP	5'b01101 //+
`define CLUI		5'b01101 //+
`define CSRLI		5'b10001 //+                      00      
`define CSRAI		5'b10001 //+                      01      
`define CANDI		5'b10001 //+                      10      
`define CSUB		5'b10001 //+                  0   11      00
`define CXOR		5'b10001 //+                  0   11      01
`define COR			5'b10001 //+                  0   11      10
`define CAND		5'b10001 //+                  0   11      11
//`define CSUBW		5'b10001 //-                  1   11      00
//`define CADDW		5'b10001 //-                  1   11      01
`define CJ			5'b10101 //+
`define CBEQZ		5'b11001 //+
`define CBNEZ		5'b11101 //+
// Quadrant 2
`define CSLLI		5'b00010 //+
//`define CFLDSP		5'b00110
//`define CLQSP		5'b00110
`define CLWSP		5'b01010 //+
//`define CFLWSP		5'b01110
//`define CLDSP		5'b01110
`define CJR			5'b10010 //+
`define CMV			5'b10010 //+
`define CEBREAK		5'b10010 //+
`define CJALR		5'b10010 //+
`define CADD		5'b10010 //+
//`define CFSDSP		5'b10110
//`define CSQSP		5'b10110
`define CSWSP		5'b11010 //+
//`define CFSWSP		5'b11110
//`define CSDSP		5'b11110
// ==============================================================

// ======================== GROUPS ==============================
`define OPCODE_OP_IMM 	    7'b0010011
`define OPCODE_OP		    7'b0110011
`define OPCODE_LUI		    7'b0110111
`define OPCODE_STORE	    7'b0100011
`define OPCODE_LOAD		    7'b0000011
`define OPCODE_JAL		    7'b1101111
`define OPCODE_JALR		    7'b1100111
`define OPCODE_BRANCH	    7'b1100011
`define OPCODE_AUPC		    7'b0010111
`define OPCODE_FENCE	    7'b0001111
`define OPCODE_SYSTEM	    7'b1110011
`define OPCODE_FLOAT_OP     7'b1010011 // ~
`define OPCODE_FLOAT_LDW    7'b0000111 // +
`define OPCODE_FLOAT_STW    7'b0100111 // +
`define OPCODE_FLOAT_MADD   7'b1000011 // 
`define OPCODE_FLOAT_MSUB   7'b1000111 // 
`define OPCODE_FLOAT_NMSUB  7'b1001011 // 
`define OPCODE_FLOAT_NMADD  7'b1001111 // 
// ==============================================================

// ======================== SUBGROUPS ===========================
`define F3_BEQ		3'b000
`define F3_BNE		3'b001
`define F3_BLT		3'b100
`define F3_BGE		3'b101
`define F3_BLTU		3'b110
`define F3_BGEU		3'b111

`define F3_ADD		3'b000
`define F3_SLL		3'b001
`define F3_SLT		3'b010
`define F3_SLTU		3'b011
`define F3_XOR		3'b100
`define F3_SR		3'b101
`define F3_OR		3'b110
`define F3_AND		3'b111

`define F3_MUL		3'b000
`define F3_MULH		3'b001
`define F3_MULHSU	3'b010
`define F3_MULHU	3'b011
`define F3_DIV		3'b100
`define F3_DIVU		3'b101
`define F3_REM		3'b110
`define F3_REMU		3'b111

`define F3_LB		3'b000
`define F3_LH		3'b001
`define F3_LW		3'b010
`define F3_LBU		3'b100
`define F3_LHU		3'b101

`define F3_SB		3'b000
`define F3_SH		3'b001
`define F3_SW		3'b010
// ==============================================================

// ======================== INTEGER ==============================
`define ALU_NONE		5'd0

`define ALU_ADD 		5'd1
`define ALU_SUB			5'd2
`define ALU_SLL			5'd3
`define ALU_SLT			5'd4
`define ALU_SLTU		5'd5
`define ALU_XOR			5'd6
`define ALU_SRL			5'd7
`define ALU_SRA			5'd8
`define ALU_OR			5'd9
`define ALU_AND			5'd10

`define ALU_MUL			5'd11
`define ALU_DIV			5'd12
`define ALU_REM			5'd13

`define ALU_EQ			5'd14
`define ALU_NE			5'd15
`define ALU_L			5'd16
`define ALU_GE			5'd17
`define ALU_LU			5'd18
`define ALU_GEU			5'd19
// ===============================================================

// ======================== FLOAT ==============================
`define ALU_FNONE       5'd0

`define ALU_FADD        5'd1
`define ALU_FMUL        5'd2
`define ALU_FDIV        5'd3
// =============================================================
