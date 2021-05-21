`timescale 1ns / 1ps

`include "cpuops.vh"

module rv32cpu(
	input wire reset,
	input wire clock,
	input wire wallclock,
	input wire busstall,
	output logic[31:0] memaddress = 32'h80000000,
	output logic [31:0] writeword = 32'h00000000,
	input wire [31:0] mem_data,
	output logic [3:0] mem_writeena = 4'b0000,
	output logic mem_readena = 1'b0,
	input wire externalirq_uart );

// =====================================================================================================
// CPU Internal State & Instruction Decomposition
// =====================================================================================================

logic [31:0] PC;
logic [31:0] nextPC;
logic [`CPUSTAGECOUNT-1:0] cpustate;
wire [`CPUSTAGECOUNT-1:0] nextstage;

// Floating point control register - unused for now
//logic [31:0] fcsr;

logic [31:0] fullinstruction;
wire [4:0] aluop;
wire [31:0] aluout;
wire branchout;
wire [31:0] imm;
wire selectimmedasrval2;

wire [6:0] opcode;
wire [4:0] rs1;
wire [4:0] rs2;
wire [4:0] rs3;
wire [4:0] rd;
wire [2:0] func3;
wire [6:0] func7;

logic registerWriteEnable;
logic fregisterWriteEnable;
logic [31:0] registerdata;
logic [31:0] fregisterdata;
wire decoderwren;
wire decoderfwren;
wire [31:0] rval1;
wire [31:0] rval2;
wire [31:0] frval1;
wire [31:0] frval2;
wire [31:0] frval3;

wire mulbusy;
wire [31:0] product;

wire [31:0] quotient, quotientu;
wire [31:0] remainder, remainderu;
wire divbusy, divbusyu;

// =====================================================================================================
// Cycle/Timer/Reti CSRs
// =====================================================================================================

logic [31:0] CSRmepc = 32'd0;
logic [31:0] CSRmcause = 32'd0;
logic [31:0] CSRmip = 32'd0;
logic [31:0] CSRmtvec = 32'd0;
logic [31:0] CSRmie = 32'd0;
logic [31:0] CSRmstatus = 32'd0;

logic [63:0] CSRTime = 64'd0;

// Custom CSR pair at 0x800/0x801, not using memory mapped timecmp
logic [63:0] CSRTimeCmp = 64'hFFFFFFFFFFFFFFFF;

logic [63:0] CSRCycle = 64'd0;
logic [63:0] CSRReti = 64'd0;

// TODO: Other custom CSRs r/w between 0x802-0x8FF

// Advancing cycles is simple since clocks = cycles
always @(posedge clock) begin
	CSRCycle <= CSRCycle + 64'd1;
end

// Time is also simple since we know we have 10M ticks per second
// from which we can derive seconds elapsed
always @(posedge wallclock) begin
	CSRTime <= CSRTime + 64'd1;
end

// =====================================================================================================
// CPU Components
// =====================================================================================================

wire isdecoding = cpustate[`CPUDECODE]==1'b1;
wire isdecodingfloatop = isdecoding & (opcode==`OPCODE_FLOAT_OP);

// Pulses to kick math operations
wire mulstart = isdecoding & (aluop==`ALU_MUL) & (opcode == `OPCODE_OP);
multiplier themul(
    .clk(clock),
    .reset(reset),
    .start(mulstart),
    .busy(mulbusy),           // calculation in progress
    .func3(func3),
    .multiplicand(rval1),
    .multiplier(rval2),
    .product(product) );

wire divstart = isdecoding & (aluop==`ALU_DIV | aluop==`ALU_REM) & (opcode == `OPCODE_OP); // High only during DECODE and if opcode is regular ALU op
DIVU unsigneddivider (
	.clk(clock),
	.reset(reset),
	.start(divstart),		// start signal
	.busy(divbusyu),		// calculation in progress
	.dividend(rval1),		// dividend
	.divisor(rval2),		// divisor
	.quotient(quotientu),	// result: quotient
	.remainder(remainderu)	// result: remainer
);

DIV signeddivider (
	.clk(clock),
	.reset(reset),
	.start(divstart),		// start signal
	.busy(divbusy),			// calculation in progress
	.dividend(rval1),		// dividend
	.divisor(rval2),		// divisor
	.quotient(quotient),	// result: quotient
	.remainder(remainder)	// result: remainder
);

wire fmaddvalid = isdecoding & (opcode==`OPCODE_FLOAT_MADD);
logic [31:0] fmaddresult;
logic fmaddresultvalid;
fp_madd floatfmadd(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(fmaddvalid),
	.s_axis_b_tdata(frval2), // *B
	.s_axis_b_tvalid(fmaddvalid),
	.s_axis_c_tdata(frval3), // -C
	.s_axis_c_tvalid(fmaddvalid),
	.aclk(clock),
	.m_axis_result_tdata(fmaddresult),
	.m_axis_result_tvalid(fmaddresultvalid) );

wire fmsubvalid = isdecoding & (opcode==`OPCODE_FLOAT_MSUB);
logic [31:0] fmsubresult;
logic fmsubresultvalid;
fp_msub floatfmsub(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(fmsubvalid),
	.s_axis_b_tdata(frval2), // *B
	.s_axis_b_tvalid(fmsubvalid),
	.s_axis_c_tdata(frval3), // -C
	.s_axis_c_tvalid(fmsubvalid),
	.aclk(clock),
	.m_axis_result_tdata(fmsubresult),
	.m_axis_result_tvalid(fmsubresultvalid) );

wire fnmsubvalid = isdecoding & (opcode==`OPCODE_FLOAT_NMSUB); // is actually MADD!
logic [31:0] fnmsubresult;
logic fnmsubresultvalid; 
fp_madd floatfnmsub(
	.s_axis_a_tdata({~frval1[31], frval1[30:0]}), // -A
	.s_axis_a_tvalid(fnmsubvalid),
	.s_axis_b_tdata(frval2), // *B
	.s_axis_b_tvalid(fnmsubvalid),
	.s_axis_c_tdata(frval3), // +C
	.s_axis_c_tvalid(fnmsubvalid),
	.aclk(clock),
	.m_axis_result_tdata(fnmsubresult),
	.m_axis_result_tvalid(fnmsubresultvalid) );

wire fnmaddvalid = isdecoding & (opcode==`OPCODE_FLOAT_NMADD); // is actually MSUB!
logic [31:0] fnmaddresult;
logic fnmaddresultvalid;
fp_msub floatfnmadd(
	.s_axis_a_tdata({~frval1[31], frval1[30:0]}), // -A
	.s_axis_a_tvalid(fnmaddvalid),
	.s_axis_b_tdata(frval2), // *B
	.s_axis_b_tvalid(fnmaddvalid),
	.s_axis_c_tdata(frval3), // -C
	.s_axis_c_tvalid(fnmaddvalid),
	.aclk(clock),
	.m_axis_result_tdata(fnmaddresult),
	.m_axis_result_tvalid(fnmaddresultvalid) );

wire faddvalid = isdecodingfloatop & (func7==`FADD);
logic [31:0] faddresult;
logic faddresultvalid;
fp_add floatadd(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(faddvalid),
	.s_axis_b_tdata(frval2), // +B
	.s_axis_b_tvalid(faddvalid),
	.aclk(clock),
	.m_axis_result_tdata(faddresult),
	.m_axis_result_tvalid(faddresultvalid) );

wire fsubvalid = isdecodingfloatop & (func7==`FSUB);	
logic [31:0] fsubresult;
logic fsubresultvalid;
fp_sub floatsub(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(fsubvalid),
	.s_axis_b_tdata(frval2), // -B
	.s_axis_b_tvalid(fsubvalid),
	.aclk(clock),
	.m_axis_result_tdata(fsubresult),
	.m_axis_result_tvalid(fsubresultvalid) );

wire fmulvalid = isdecodingfloatop & (func7==`FMUL);	
logic [31:0] fmulresult;
logic fmulresultvalid;
fp_mul floatmul(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(fmulvalid),
	.s_axis_b_tdata(frval2), // *B
	.s_axis_b_tvalid(fmulvalid),
	.aclk(clock),
	.m_axis_result_tdata(fmulresult),
	.m_axis_result_tvalid(fmulresultvalid) );

wire fdivvalid = isdecodingfloatop & (func7==`FDIV);	
logic [31:0] fdivresult;
logic fdivresultvalid;
fp_div floatdiv(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(fdivvalid),
	.s_axis_b_tdata(frval2), // /B
	.s_axis_b_tvalid(fdivvalid),
	.aclk(clock),
	.m_axis_result_tdata(fdivresult),
	.m_axis_result_tvalid(fdivresultvalid) );

wire fi2fvalid = isdecodingfloatop & (func7==`FCVTSW) & (rs2==5'b00000); // Signed
logic [31:0] fi2fresult;
logic fi2fresultvalid;
fp_i2f floati2f(
	.s_axis_a_tdata(rval1), // A (integer register is source)
	.s_axis_a_tvalid(fi2fvalid),
	.aclk(clock),
	.m_axis_result_tdata(fi2fresult),
	.m_axis_result_tvalid(fi2fresultvalid) );
	
wire fui2fvalid = isdecodingfloatop & (func7==`FCVTSW) & (rs2==5'b00001); // Unsigned
logic [31:0] fui2fresult;
logic fui2fresultvalid;
fp_ui2f floatui2f(
	.s_axis_a_tdata(rval1), // A (integer register is source)
	.s_axis_a_tvalid(fui2fvalid),
	.aclk(clock),
	.m_axis_result_tdata(fui2fresult),
	.m_axis_result_tvalid(fui2fresultvalid) );

wire ff2ivalid = isdecodingfloatop & (func7==`FCVTWS) & (rs2==5'b00000); // Signed
logic [31:0] ff2iresult;
logic ff2iresultvalid;
fp_f2i floatf2i(
	.s_axis_a_tdata(frval1), // A (float register is source)
	.s_axis_a_tvalid(ff2ivalid),
	.aclk(clock),
	.m_axis_result_tdata(ff2iresult),
	.m_axis_result_tvalid(ff2iresultvalid) );

wire ff2uivalid = isdecodingfloatop & (func7==`FCVTWS) & (rs2==5'b00001); // Unsigned
logic [31:0] ff2uiresult;
logic ff2uiresultvalid;
// NOTE: Sharing same logic with f2i here, ignoring sign bit instead
fp_f2i floatf2ui(
	.s_axis_a_tdata({1'b0,frval1[30:0]}), // abs(A) (float register is source)
	.s_axis_a_tvalid(ff2uivalid),
	.aclk(clock),
	.m_axis_result_tdata(ff2uiresult),
	.m_axis_result_tvalid(ff2uiresultvalid) );
	
wire fsqrtvalid = isdecodingfloatop & (func7==`FSQRT);
logic [31:0] fsqrtresult;
logic fsqrtresultvalid;
fp_sqrt floatsqrt(
	.s_axis_a_tdata({1'b0,frval1[30:0]}), // abs(A) (float register is source)
	.s_axis_a_tvalid(fsqrtvalid),
	.aclk(clock),
	.m_axis_result_tdata(fsqrtresult),
	.m_axis_result_tvalid(fsqrtresultvalid) );

wire feqvalid = isdecodingfloatop & (func7==`FEQ) & (func3==3'b010); // FEQ
logic [7:0] feqresult;
logic feqresultvalid;
fp_eq floateq(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(feqvalid),
	.s_axis_b_tdata(frval2), // B
	.s_axis_b_tvalid(feqvalid),
	.aclk(clock),
	.m_axis_result_tdata(feqresult),
	.m_axis_result_tvalid(feqresultvalid) );

wire fltvalid = isdecodingfloatop & ( (func7 == `FMIN) | (func7 == `FMAX) | ((func7==`FEQ) & (func3==3'b001))); // FLT
logic [7:0] fltresult;
logic fltresultvalid;
fp_lt floatlt(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(fltvalid),
	.s_axis_b_tdata(frval2), // B
	.s_axis_b_tvalid(fltvalid),
	.aclk(clock),
	.m_axis_result_tdata(fltresult),
	.m_axis_result_tvalid(fltresultvalid) );

wire flevalid = isdecodingfloatop & (func7==`FEQ) & (func3==3'b000); // FLE
logic [7:0] fleresult;
logic fleresultvalid;
fp_le floatle(
	.s_axis_a_tdata(frval1), // A
	.s_axis_a_tvalid(flevalid),
	.s_axis_b_tdata(frval2), // B
	.s_axis_b_tvalid(flevalid),
	.aclk(clock),
	.m_axis_result_tdata(fleresult),
	.m_axis_result_tvalid(fleresultvalid) );

wire [11:0] csrindex;
decoder idecode(
	.clock(clock),
	.reset(reset),
	.instruction(fullinstruction),
	.opcode(opcode),
	.aluop(aluop),
	.rs1(rs1),
	.rs2(rs2),
	.rs3(rs3),
	.rd(rd),
	.func3(func3),
	.func7(func7),
	.imm(imm),
	.csrindex(csrindex),
	.nextstage(nextstage),
	.wren(decoderwren),
	.fwren(decoderfwren),
	.selectimmedasrval2(selectimmedasrval2) );

// Integer registers
registerfile regs(
	.reset(reset),
	.clock(clock),
	.rs1(rs1),
	.rs2(rs2),
	.rd(rd),
	.wren(registerWriteEnable),
	.datain(registerdata),
	.rval1(rval1),
	.rval2(rval2) );
	
// Floating point registers
floatregisterfile floatregs(
	.reset(reset),
	.clock(clock),
	.rs1(rs1),
	.rs2(rs2),
	.rs3(rs3),
	.rd(rd),
	.wren(fregisterWriteEnable),
	.datain(fregisterdata),
	.rval1(frval1),
	.rval2(frval2),
	.rval3(frval3) );

// ALU
ALU aluunit(
	.reset(reset),
	.clock(clock),
	.aluout(aluout),
	.func3(func3),
	.val1(rval1),
	.val2(rval2selector), // Either source register 2 or immediate
	.aluop(aluop));

// Branch condition
BRA braunit(
	.reset(reset),
	.clock(clock),
	.branchout(branchout),
	.val1(rval1),
	.val2(rval2selector),
	.aluop(aluop));
	
wire [31:0] rval2selector = selectimmedasrval2 ? imm : rval2;

// =====================================================================================================
// Instruction Logic
// =====================================================================================================

always_comb begin
	// Do not re-latch the instruction in other states as mem_data might change (for other reads+writes) 
	if (reset) begin
		fullinstruction = {25'd0, `ADDI}; // NOOP (add x0,x0,0)
	end else begin
		if (cpustate[`CPUDECODE] == 1'b1)
			fullinstruction = mem_data; // Latch, no else case
	end
end

// =====================================================================================================
// Math Unit Logic
// =====================================================================================================

// High during mul/div/rem operations
wire muldivstall = (divstart | divbusy | divbusyu) | (mulstart | mulbusy);

// =====================================================================================================
// CPU Logic
// =====================================================================================================

always_ff @(posedge clock) begin
	if (reset) begin

		PC <= `CPU_RESET_VECTOR;
		nextPC <= `CPU_RESET_VECTOR; // Start from reset vector as this is the first thing we read
		memaddress <= `CPU_RESET_VECTOR;
		cpustate <= `CPURETIREINSTRUCTION_MASK;
		mem_writeena <= 4'b0000;
		registerWriteEnable <= 1'b0;
		//registerdata <= 32'd0;
		fregisterWriteEnable <= 1'b0;
		//fregisterdata <= 32'd0;
		//fcsr <= 32'd0; // [7:5] == 000 -> RNE (round to nearest even), [4:0] -> NotValid|DivbyZero|OverFlow|UnderFlow|iNeXact (exceptions), ignored for now

	end else begin

		cpustate <= `CPUNONE_MASK;
		
		// cpu state uses one-hot encoding
		unique case (1'b1)

			cpustate[`CPUFETCH]: begin
				if (busstall) begin
					// Keep mem_readena high during stall
					cpustate[`CPUFETCH] <= 1'b1;
				end else begin
					mem_readena <= 1'b0;
					// Instruction read takes place here, to be latched at the start of next state
					cpustate[`CPUDECODE] <= 1'b1;
				end
			end

			cpustate[`CPUDECODE]: begin
				// NOTE: For external/different memory, reads might stall
				// if (busstall) begin cpustate[`CPUDECODE] <= 1'b1; else begin decode(); end

				// Instruction is now latched on to fullinstruction
				// Any decode checks since decoder should be done by now
				// Should have register values available from rs1 and rs2 now
				// as well as the opcode, rd, func3, func7, and the immediate
				if ((opcode == `OPCODE_OP) & ((aluop==`ALU_MUL) | (aluop==`ALU_DIV) | (aluop==`ALU_REM)))
					cpustate[`CPUSTALLM] <= 1'b1;
				else
					cpustate[`CPUEXEC] <= 1'b1;
			end

			cpustate[`CPUSTALLM]: begin
				if (muldivstall) begin
					cpustate[`CPUSTALLM] <= 1'b1;
				end else begin
					// Stall until we're released
					registerWriteEnable <= decoderwren;
					cpustate <= nextstage;
					nextPC <= PC + 32'd4; // NOTE: +32'd2 for compressed instructions
					unique case (aluop)
						`ALU_MUL: begin
							registerdata <= product;
						end
						`ALU_DIV: begin
							registerdata <= func3==`F3_DIV ? quotient : quotientu;
						end
						`ALU_REM: begin
							registerdata <= func3==`F3_REM ? remainder : remainderu;
						end
					endcase
				end
			end

			cpustate[`CPUEXEC]: begin
				// Figure out if we need to read/write memory or write back to registers
				// Also figure out the next PC

				registerWriteEnable <= decoderwren;
				fregisterWriteEnable <= decoderfwren;
				cpustate <= nextstage;
				nextPC <= PC + 32'd4; // NOTE: +32'd2 for compressed instructions
				
				unique case (opcode)
					`OPCODE_AUPC: begin
						registerdata <= PC + imm;
					end
					`OPCODE_LUI: begin
						registerdata <= imm;
					end
					`OPCODE_JAL: begin
						registerdata <= PC + 32'd4; // NOTE: +32'd2 for compressed instructions
						nextPC <= PC + imm;
					end
					`OPCODE_OP, `OPCODE_OP_IMM: begin
						registerdata <= aluout; // Non-M instructions
					end
					`OPCODE_FLOAT_LDW, `OPCODE_LOAD: begin
						memaddress <= rval1 + imm;
						mem_readena <= 1'b1;
					end
					`OPCODE_FLOAT_STW : begin
						fregisterdata <= frval2;
						memaddress <= rval1 + imm;
					end
					`OPCODE_STORE: begin
						registerdata <= rval2;
						memaddress <= rval1 + imm;
					end
					`OPCODE_FENCE: begin
						// TODO:
					end
					`OPCODE_SYSTEM: begin
						// machine trap setup
						// 0x300: mstatus machine status: [3:3]=MIE (machine interrupt enable)
						// 0x302: medeleg machine exception delegation
						// 0x303: mideleg machine interrupt delegation
						// 0x304: mie machine interrupt enable [...:MEIE:HEIE:SEIE:UEIE:MTIE:HTIE:STIE:UTIE:MSIE:HSIE:SSIE:USIE] MEIE=>machine external interrupts
						// 0x305: mtvec machine trap handler base address [31:1]=trap vector base, [0:0]=0

						// machine trap handling
						// 0x340: mscratch scratch register for machine trap handlers
						// 0x341: mepc machine exception program counter (trap return address)
						// 0x342: mcause machine trap cause
						// 0x343: mbadaddr machine bad address
						// 0x344: mip machine interrupt pending [...:MEIP:HEIP:SEIP:UEIP:MTIP:HTIP:STIP:UTIP:MSIP:HSIP:SSIP:USIP]
						
						// mcause:
						// 1 0 User software interrupt
						// 1 1 Supervisor software interrupt
						// 1 2 Hypervisor software interrupt
						// 1 3 Machine software interrupt
						// 1 4 User timer interrupt
						// 1 5 Supervisor timer interrupt
						// 1 6 Hypervisor timer interrupt
						// 1 7 Machine timer interrupt
						// 1 8 User external interrupt
						// 1 9 Supervisor external interrupt
						// 1 10 Hypervisor external interrupt
						// 1 11 Machine external interrupt
						// 1 >=12 Reserved
						// 0 0 Instruction address misaligned
						// 0 1 Instruction access fault
						// 0 2 Illegal instruction
						// 0 3 Breakpoint
						// 0 4 Load address misaligned
						// 0 5 Load access fault
						// 0 6 Store/AMO address misaligned
						// 0 7 Store/AMO access fault
						// 0 8 Environment call from U-mode
						// 0 9 Environment call from S-mode
						// 0 10 Environment call from H-mode
						// 0 11 Environment call from M-mode
						// 0 >=12 Reserved

						// Only implements timer CSR reads for now
						case (func3)
							3'b000: begin // ECALL/EBREAK
								case (fullinstruction[31:20])
									12'b000000000000: begin // ECALL
										// TBD
										// example: 
										// li a7, SBI_SHUTDOWN // also a0/a1/a2, retval in a0
  										// ecall
  									end
									12'b000000000001: begin // EBREAK

										// Raise 'breakpoint' 
										// MIE (Machine interrupt enable) & MSIE (Machine software interrupt enable)
										if (CSRmstatus[3] & CSRmie[3]) begin 
											//CSRmip[3] <= 1'b1; // Set machine interrupt pending for interrupt case
											CSRmstatus[7] <= CSRmstatus[3]; // MPIE = MIE
											CSRmstatus[3] <= 1'b0; // Clear MIE (disable interrupts)
											// Cause = 3=breakpoint(machine software int)
											// 7=machine timer int
											// 11=machine external int
											// 2=illegal instruction
											CSRmcause <= 32'd3;
											// WARNING: Store CURRENT instruction address (PC), NOT nextPC!
											// Debugger, before return, removes the EBREAK instruction, single steps, restores EBREAK, then resumes execution
											CSRmepc <= PC;
											nextPC <= CSRmtvec; // jump to mtvec, handler MUST return with mret instruction
											// For vectored interrupts:
											// nextPC <= CSRmtvec + 4*exception code
											// If lower 2 bits of mtvec are 0, it's a 'direct' address
											// If the lower 2 bits read 1, it's vectored
											// anything above 1 is reserved

											//CSRmip[11] <= 1'b1; // Machine external interrupt pending
											//CSRmip[7] <= 1'b1; // Machine timer interrupt pending
											//CSRmip[3] <= 1'b1; // Machine interrupt pending
											// interrupts are taken if both mip and mie bits are set and interrupts are globally enabled (M always globally enabled)
											// order:
											// external, software, timer, synchronous
										end
									end
									// privileged instructions
									12'b001100000010: begin // MRET
										if (CSRmcause == 32'd3) CSRmip[3] <= 1'b0; // Disable machine interrupt pending
										if (CSRmcause == 32'd7) CSRmip[7] <= 1'b0; // Disable machine timer interrupt pending
										if (CSRmcause == 32'd11) CSRmip[11] <= 1'b0; // Disable machine external interrupt pending
										CSRmstatus[3] <= CSRmstatus[7]; // MIE=MPIE - set to previous machine interrupt enable state
										CSRmstatus[7] <= 1'b0; // Clear MPIE
										nextPC <= CSRmepc;
									end
									// 001000000010: // HRET -> PC <= CSRhepc;
									// 000100000010: // SRET -> PC <= CSRsepc;
									// 000000000010: // URET -> PC <= CSRuepc;
									// 000100000101: // WFI wait for interrupt
									// 000100000100: // SFENCE.VM
									// Upon reset, a hart's privilege mode is set to M. The mstatus fields MIE and MPRV are reset to 0, and the VM field is reset to Mbare
									// The mcause values after reset have implementation-specific interpretation, but the value 0 should be returned on implementations that do not distinguish different reset conditions
								endcase
							end
							3'b001: begin // CSRRW
								// Swap rs1 and csr register values
								case (csrindex)
									12'hC00: begin registerdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=rval1;*/ end
									12'hC01: begin registerdata <= CSRTime[31:0]; /*CSRTime[31:0]<=rval1;*/ end
									12'hC02: begin registerdata <= CSRReti[31:0]; /*CSRReti[31:0]<=rval1;*/ end
									12'hC80: begin registerdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=rval1;*/ end
									12'hC81: begin registerdata <= CSRTime[63:32]; /*CSRTime[63:32]<=rval1;*/ end
									12'hC82: begin registerdata <= CSRReti[63:32]; /*CSRReti[63:32]<=rval1;*/ end
									12'h300: begin registerdata <= CSRmstatus; CSRmstatus<=rval1; end
									12'h304: begin registerdata <= CSRmie; CSRmie<=rval1; end
									12'h305: begin registerdata <= CSRmtvec; CSRmtvec<=rval1; end
									12'h341: begin registerdata <= CSRmepc; CSRmepc<=rval1; end
									12'h342: begin registerdata <= CSRmcause; CSRmcause<=rval1; end
									12'h344: begin registerdata <= CSRmip; CSRmip<=rval1; end
									12'h800: begin registerdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=rval1; end
									12'h801: begin registerdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=rval1; end

								endcase
							end
							3'b010: begin // CSRRS
								case (csrindex)
									// Need to trap special counter registers and use built-in hardware counters
									12'hC00: begin registerdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=CSRCycle[31:0]&rval1;*/ end
									12'hC01: begin registerdata <= CSRTime[31:0]; /*CSRTime[31:0]<=CSRTime[31:0]&rval1;*/ end
									12'hC02: begin registerdata <= CSRReti[31:0]; /*CSRReti[31:0]<=CSRReti[31:0]&rval1;*/ end
									12'hC80: begin registerdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=CSRCycle[63:32]&rval1;*/ end
									12'hC81: begin registerdata <= CSRTime[63:32]; /*CSRTime[63:32]<=CSRTime[63:32]&rval1;*/ end
									12'hC82: begin registerdata <= CSRReti[63:32]; /*CSRReti[63:32]<=CSRReti[63:32]&rval1;*/ end
									12'h300: begin registerdata <= CSRmstatus; CSRmstatus<=CSRmstatus&rval1; end
									12'h304: begin registerdata <= CSRmie; CSRmie<=CSRmie&rval1; end
									12'h305: begin registerdata <= CSRmtvec; CSRmtvec<=CSRmtvec&rval1; end
									12'h341: begin registerdata <= CSRmepc; CSRmepc<=CSRmepc&rval1; end
									12'h342: begin registerdata <= CSRmcause; CSRmcause<=CSRmcause&rval1; end
									12'h344: begin registerdata <= CSRmip; CSRmip<=CSRmip&rval1; end
									12'h800: begin registerdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=CSRTimeCmp[31:0]&rval1; end
									12'h801: begin registerdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=CSRTimeCmp[63:32]&rval1; end
								endcase
							end
							3'b011: begin // CSSRRC
								case (csrindex)
									// Need to trap special counter registers and use built-in hardware counters
									12'hC00: begin registerdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=CSRCycle[31:0]&(~rval1);*/ end
									12'hC01: begin registerdata <= CSRTime[31:0]; /*CSRTime[31:0]<=CSRTime[31:0]&(~rval1);*/ end
									12'hC02: begin registerdata <= CSRReti[31:0]; /*CSRReti[31:0]<=CSRReti[31:0]&(~rval1);*/ end
									12'hC80: begin registerdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=CSRCycle[63:32]&(~rval1);*/ end
									12'hC81: begin registerdata <= CSRTime[63:32]; /*CSRTime[63:32]<=CSRTime[63:32]&(~rval1);*/ end
									12'hC82: begin registerdata <= CSRReti[63:32]; /*CSRReti[63:32]<=CSRReti[63:32]&(~rval1);*/ end
									12'h300: begin registerdata <= CSRmstatus; CSRmstatus<=CSRmstatus&(~rval1); end
									12'h304: begin registerdata <= CSRmie; CSRmie<=CSRmie&(~rval1); end
									12'h305: begin registerdata <= CSRmtvec; CSRmtvec<=CSRmtvec&(~rval1); end
									12'h341: begin registerdata <= CSRmepc; CSRmepc<=CSRmepc&(~rval1); end
									12'h342: begin registerdata <= CSRmcause; CSRmcause<=CSRmcause&(~rval1); end
									12'h344: begin registerdata <= CSRmip; CSRmip<=CSRmip&(~rval1); end
									12'h800: begin registerdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=CSRTimeCmp[31:0]&(~rval1); end
									12'h801: begin registerdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=CSRTimeCmp[63:32]&(~rval1); end
								endcase
							end
							3'b101: begin // CSRRWI
								case (csrindex)
									12'hC00: begin registerdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=imm;*/ end
									12'hC01: begin registerdata <= CSRTime[31:0]; /*CSRTime[31:0]<=imm;*/ end
									12'hC02: begin registerdata <= CSRReti[31:0]; /*CSRReti[31:0]<=imm;*/ end
									12'hC80: begin registerdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=imm;*/ end
									12'hC81: begin registerdata <= CSRTime[63:32]; /*CSRTime[63:32]<=imm;*/ end
									12'hC82: begin registerdata <= CSRReti[63:32]; /*CSRReti[63:32]<=imm;*/ end
									12'h300: begin registerdata <= CSRmstatus; CSRmstatus<=imm; end
									12'h304: begin registerdata <= CSRmie; CSRmie<=imm; end
									12'h305: begin registerdata <= CSRmtvec; CSRmtvec<=imm; end
									12'h341: begin registerdata <= CSRmepc; CSRmepc<=imm; end
									12'h342: begin registerdata <= CSRmcause; CSRmcause<=imm; end
									12'h344: begin registerdata <= CSRmip; CSRmip<=imm; end
									12'h800: begin registerdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=imm; end
									12'h801: begin registerdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=imm; end
								endcase
							end
							3'b110: begin // CSRRSI
								case (csrindex)
									// Need to trap special counter registers and use built-in hardware counters
									12'hC00: begin registerdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=CSRCycle[31:0]&imm;*/ end
									12'hC01: begin registerdata <= CSRTime[31:0]; /*CSRTime[31:0]<=CSRTime[31:0]&imm;*/ end
									12'hC02: begin registerdata <= CSRReti[31:0]; /*CSRReti[31:0]<=CSRReti[31:0]&imm;*/ end
									12'hC80: begin registerdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=CSRCycle[63:32]&imm;*/ end
									12'hC81: begin registerdata <= CSRTime[63:32]; /*CSRTime[63:32]<=CSRTime[63:32]&imm;*/ end
									12'hC82: begin registerdata <= CSRReti[63:32]; /*CSRReti[63:32]<=CSRReti[63:32]&imm;*/ end
									12'h300: begin registerdata <= CSRmstatus; CSRmstatus<=CSRmstatus&imm; end
									12'h304: begin registerdata <= CSRmie; CSRmie<=CSRmie&imm; end
									12'h305: begin registerdata <= CSRmtvec; CSRmtvec<=CSRmtvec&imm; end
									12'h341: begin registerdata <= CSRmepc; CSRmepc<=CSRmepc&imm; end
									12'h342: begin registerdata <= CSRmcause; CSRmcause<=CSRmcause&imm; end
									12'h344: begin registerdata <= CSRmip; CSRmip<=CSRmip&imm; end
									12'h800: begin registerdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=CSRTimeCmp[31:0]&imm; end
									12'h801: begin registerdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=CSRTimeCmp[63:32]&imm; end
								endcase
							end
							3'b111: begin // CSRRCI
								case (csrindex)
									// Need to trap special counter registers and use built-in hardware counters
									12'hC00: begin registerdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=CSRCycle[31:0]&(~imm);*/ end
									12'hC01: begin registerdata <= CSRTime[31:0]; /*CSRTime[31:0]<=CSRTime[31:0]&(~imm);*/ end
									12'hC02: begin registerdata <= CSRReti[31:0]; /*CSRReti[31:0]<=CSRReti[31:0]&(~imm);*/ end
									12'hC80: begin registerdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=CSRCycle[63:32]&(~imm);*/ end
									12'hC81: begin registerdata <= CSRTime[63:32]; /*CSRTime[63:32]<=CSRTime[63:32]&(~imm);*/ end
									12'hC82: begin registerdata <= CSRReti[63:32]; /*CSRReti[63:32]<=CSRReti[63:32]&(~imm);*/ end
									12'h300: begin registerdata <= CSRmstatus; CSRmstatus<=CSRmstatus&(~imm); end
									12'h304: begin registerdata <= CSRmie; CSRmie<=CSRmie&(~imm); end
									12'h305: begin registerdata <= CSRmtvec; CSRmtvec<=CSRmtvec&(~imm); end
									12'h341: begin registerdata <= CSRmepc; CSRmepc<=CSRmepc&(~imm); end
									12'h342: begin registerdata <= CSRmcause; CSRmcause<=CSRmcause&(~imm); end
									12'h344: begin registerdata <= CSRmip; CSRmip<=CSRmip&(~imm); end
									12'h800: begin registerdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=CSRTimeCmp[31:0]&(~imm); end
									12'h801: begin registerdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=CSRTimeCmp[63:32]&(~imm); end
								endcase
							end
						endcase
					end
					`OPCODE_FLOAT_OP: begin
						// Sign injection is handled here, then retired.
						// Rest of the float operations fall through to stall states.
						if (func7 == `FSGNJ) begin
							unique case(func3)
								3'b000: begin // FSGNJ
									fregisterdata <= {frval2[31], frval1[30:0]}; 
								end
								3'b001: begin  // FSGNJN
									fregisterdata <= {~frval2[31], frval1[30:0]};
								end
								3'b010: begin  // FSGNJX
									fregisterdata <= {frval1[31]^frval2[31], frval1[30:0]};
								end
							endcase
						end else if (func7 == `FMVXW) begin // Float to Int register (overlaps `FCLASS)
							if (func3 == 3'b000) //FMVXW
								registerdata <= frval1;
							else // FCLASS
								registerdata <= 32'd0; // TBD
						end else if (func7 == `FMVWX) begin // Int to Float register
							fregisterdata <= rval1;
						end
					end
					`OPCODE_FLOAT_MADD, `OPCODE_FLOAT_MSUB, `OPCODE_FLOAT_NMSUB, `OPCODE_FLOAT_NMADD: begin
						// TODO: Kick into fused float op stall state
					end
					`OPCODE_JALR: begin
						registerdata <= PC + 32'd4; // NOTE: +32'd2 for compressed instructions
						nextPC <= rval1 + imm;
					end
					`OPCODE_BRANCH: begin
						nextPC <= branchout==1'b1 ? PC + imm : PC + 32'd4; // NOTE: +32'd2 for compressed instructions
					end
					default: begin
						// These are illegal / unhandled or non-op instructions, jump back to reset vector
						nextPC <= `CPU_RESET_VECTOR;
					end
				endcase
			end

			cpustate[`CPUSTALLFF]: begin
				if (fnmsubresultvalid | fnmaddresultvalid | fmsubresultvalid | fmaddresultvalid) begin
					fregisterWriteEnable <= decoderfwren;
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					nextPC <= PC + 32'd4; // NOTE: +32'd2 for compressed instructions
					unique case (opcode)
						`OPCODE_FLOAT_NMSUB: begin
							fregisterdata <= fnmsubresult;
						end
						`OPCODE_FLOAT_NMADD: begin
							fregisterdata <= fnmaddresult;
						end
						`OPCODE_FLOAT_MADD: begin
							fregisterdata <= fmaddresult;
						end
						`OPCODE_FLOAT_MSUB: begin
							fregisterdata <= fmsubresult;
						end
						default: begin
							fregisterdata <= 32'd0;
						end
					endcase
				end else begin
					cpustate[`CPUSTALLFF] <= 1'b1; // Stall for fused float
				end
			end
			
			cpustate[`CPUSTALLF]: begin
				if  (fmulresultvalid | fdivresultvalid | fi2fresultvalid | ff2iresultvalid | faddresultvalid | fsubresultvalid | fsqrtresultvalid | feqresultvalid | fltresultvalid | fleresultvalid) begin
					fregisterWriteEnable <= decoderfwren;
					registerWriteEnable <= decoderwren;
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					nextPC <= PC + 32'd4; // NOTE: +32'd2 for compressed instructions
					unique case (func7)
						`FADD: begin
							fregisterdata <= faddresult;
						end
						`FSUB: begin
							fregisterdata <= fsubresult;
						end
						`FMUL: begin
							fregisterdata <= fmulresult;
						end
						`FDIV: begin
							fregisterdata <= fdivresult;
						end
						`FCVTSW: begin // NOTE: FCVT.S.WU is unsigned version
							fregisterdata <= rs2==5'b00000 ? fi2fresult : fui2fresult; // Result goes to float register (signed int to float)
						end
						`FCVTWS: begin // NOTE: FCVT.WU.S is unsigned version
							registerdata <= rs2==5'b00000 ? ff2iresult : ff2uiresult; // Result goes to integer register (float to signed int)
						end
						`FSQRT: begin
							fregisterdata <= fsqrtresult;
						end
						`FEQ: begin
							if (func3==3'b010) // FEQ
								registerdata <= {31'd0,feqresult[0]};
							else if (func3==3'b001) // FLT
								registerdata <= {31'd0,fltresult[0]};
							else //if (func3==3'b000) // FLE
								registerdata <= {31'd0,fleresult[0]};
						end
						`FMIN: begin
							if (func3==3'b000) // FMIN
								fregisterdata <= fltresult[0]==1'b0 ? frval2 : frval1;
							else // FMAX
								fregisterdata <= fltresult[0]==1'b0 ? frval1 : frval2;
						end
						default: begin
							fregisterdata <= 32'd0;
						end
					endcase
				end else begin
					cpustate[`CPUSTALLF] <= 1'b1; // Stall for float
				end
			end

			cpustate[`CPULOADWAIT]: begin
				if (busstall) begin
					// Keep mem_readena high during stall
					cpustate[`CPULOADWAIT] <= 1'b1;
				end else begin
					mem_readena <= 1'b0;
					if (opcode == `OPCODE_FLOAT_LDW) begin
						cpustate[`CPULOADFCOMPLETE] <= 1'b1;
					end else begin
						cpustate[`CPULOADCOMPLETE] <= 1'b1;
					end
				end
			end

			cpustate[`CPULOADCOMPLETE]: begin
				unique case (func3) // lb:000 lh:001 lw:010 lbu:100 lhu:101
					3'b000: begin
						// Byte alignment based on {address[1:0]} with sign extension
						unique case (memaddress[1:0])
							2'b11: begin registerdata <= {{24{mem_data[31]}},mem_data[31:24]}; end
							2'b10: begin registerdata <= {{24{mem_data[23]}},mem_data[23:16]}; end
							2'b01: begin registerdata <= {{24{mem_data[15]}},mem_data[15:8]}; end
							2'b00: begin registerdata <= {{24{mem_data[7]}},mem_data[7:0]}; end
						endcase
					end
					3'b001: begin
						// short alignment based on {address[1],1'b0} with sign extension
						unique case (memaddress[1])
							1'b1: begin registerdata <= {{16{mem_data[31]}},mem_data[31:16]}; end
							1'b0: begin registerdata <= {{16{mem_data[15]}},mem_data[15:0]}; end
						endcase
					end
					3'b010: begin
						// Already aligned on read, regular DWORD read
						registerdata <= mem_data[31:0];
					end
					3'b100: begin
						// Byte alignment based on {address[1:0]} with zero extension
						unique case (memaddress[1:0])
							2'b11: begin registerdata <= {24'd0, mem_data[31:24]}; end
							2'b10: begin registerdata <= {24'd0, mem_data[23:16]}; end
							2'b01: begin registerdata <= {24'd0, mem_data[15:8]}; end
							2'b00: begin registerdata <= {24'd0, mem_data[7:0]}; end
						endcase
					end
					3'b101: begin
						// short alignment based on {address[1],1'b0} with zero extension
						unique case (memaddress[1])
							1'b1: begin registerdata <= {16'd0, mem_data[31:16]}; end
							1'b0: begin registerdata <= {16'd0, mem_data[15:0]}; end
						endcase
					end
				endcase
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end

			cpustate[`CPULOADFCOMPLETE]: begin
				// Already aligned on read, regular DWORD read
				fregisterdata <= mem_data[31:0];
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end

			cpustate[`CPUSTORE]: begin
				if (busstall) begin
					// Do not write to the bus while it's busy
					cpustate[`CPUSTORE] <= 1'b1;
				end else begin
					unique case (func3)
						// Byte
						3'b000: begin
							writeword <= {registerdata[7:0], registerdata[7:0], registerdata[7:0], registerdata[7:0]};
							unique case (memaddress[1:0])
								2'b11: begin mem_writeena <= 4'b1000; end
								2'b10: begin mem_writeena <= 4'b0100; end
								2'b01: begin mem_writeena <= 4'b0010; end
								2'b00: begin mem_writeena <= 4'b0001; end
							endcase
						end
						// Word
						3'b001: begin
							writeword <= {registerdata[15:0], registerdata[15:0]};
							unique case (memaddress[1])
								1'b1: begin mem_writeena <= 4'b1100; end
								1'b0: begin mem_writeena <= 4'b0011; end
							endcase
						end
						// Dword
						default: begin
							writeword <= registerdata;
							mem_writeena <= 4'b1111;
						end
					endcase
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
				end
			end

			cpustate[`CPUSTOREF]: begin
				// Word
				mem_writeena <= 4'b1111;
				writeword <= fregisterdata;
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end

			cpustate[`CPURETIREINSTRUCTION]: begin
				// Stop register writes
				registerWriteEnable <= 1'b0;
				fregisterWriteEnable <= 1'b0;
				// Stop memory writes
				mem_writeena <= 4'b0000;
				mem_readena <= 1'b1;

				// If timer interrupts and global machine interrupts enabled
				// Time interrupt stays pending
				// Stays posted until timecmp > time (usually after writing to timecmp)
				if (CSRmstatus[3] & CSRmie[7] & (CSRTime >= CSRTimeCmp)) begin
					// Timer interrupt
					CSRmip[7] <= 1'b1; // Set pending
					CSRmcause <= 32'd7;
					CSRmstatus[7] <= CSRmstatus[3]; // MPIE = MIE
					CSRmstatus[3] <= 1'b0; // Clear MIE (disable interrupts)
					// Remember where to return
					CSRmepc <= nextPC;
					// Go to trap handler
					PC <= {CSRmtvec[31:1],1'b0};
					memaddress <= {CSRmtvec[31:1], 1'b0};
				end else if (CSRmstatus[3] & CSRmie[11] & externalirq_uart) begin
					// External interrupt
					CSRmip[11] <= 1'b1; // Set pending
					CSRmcause <= 32'd11; // Machine External Interrupt
					CSRmstatus[7] <= CSRmstatus[3]; // MPIE = MIE
					CSRmstatus[3] <= 1'b0; // Clear MIE (disable interrupts)
					// Remember where to return
					CSRmepc <= nextPC;
					// Go to trap handler
					PC <= {CSRmtvec[31:1],1'b0};
					memaddress <= {CSRmtvec[31:1], 1'b0};
				end else begin
					// Set next PC
					PC <= {nextPC[31:1],1'b0}; // Truncate to 16bit aligned addresses to align to instructions
					// Also reflect to the memaddress so we end up reading next instruction
					memaddress <= {nextPC[31:1], 1'b0};
				end

				// Update retired instruction CSR
				CSRReti <= CSRReti + 64'd1;
				// Loop back to fetch (actually fetch wait) state
				cpustate[`CPUFETCH] <= 1'b1;
			end

		endcase

	end
end
	
endmodule
