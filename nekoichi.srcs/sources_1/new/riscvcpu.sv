`timescale 1ns / 1ps

`include "cpuops.vh"

module riscvcpu(
	input clock,
	input wallclock,
	input reset,
	output logic [31:0] memaddress = 32'd0,
	output logic [31:0] cpudataout = 32'd0,
	output logic [3:0] cpuwriteena = 4'b0000,
	output logic cpureadena = 1'b0,
	input [31:0] cpudatain,
	input busstall,
	input IRQ,
	input [1:0] IRQ_TYPE);

// Start from RETIRE state so that we can
// set up instruction fetch address and read
// data which will be available on the next
// clock, in FETCH state.
logic [`CPUSTAGECOUNT-1:0] cpustate = `CPUSTAGEMASK_RETIREINSTRUCTION;

logic [31:0] PC = 32'd0;
logic [31:0] nextPC = 32'd0;
logic [31:0] instruction = 32'd0; // Illegal instruction

// Integer and float file write control lines
wire rwen, fwen;
// Delayed write enable copy for EXEC step
logic intregisterwriteenable = 1'b0;
logic floatregisterwriteenable = 1'b0;

// Data input for register writes
logic [31:0] rdata = 32'd0;
logic [31:0] fdata = 32'd0;

// Instruction decoder and related wires
wire [6:0] opcode;
wire [4:0] aluop;
wire [2:0] func3;
wire [6:0] func7;
wire [4:0] rs1;
wire [4:0] rs2;
wire [4:0] rs3;
wire [4:0] rd;
wire [11:0] csrindex;
wire [31:0] immed;
wire selectimmedasrval2;

decoder mydecoder(
	.instruction(instruction),
	.opcode(opcode),
	.rwen(rwen),
	.fwen(fwen),
	.aluop(aluop),
	.func3(func3),
	.func7(func7),
	.rs1(rs1),
	.rs2(rs2),
	.rs3(rs3), // Used for fused multiply-add/sub float instructions 
	.rd(rd),
	.immed(immed),
	.csrindex(csrindex),
	.selectimmedasrval2(selectimmedasrval2) );

// Read results from integer and float registers
wire [31:0] rval1;
wire [31:0] rval2;
wire [31:0] frval1;
wire [31:0] frval2;
wire [31:0] frval3;

wire [31:0] rval2selector = selectimmedasrval2 ? immed : rval2;

// Integer register file
registerfile myintegerregs(
	.clock(clock),					// Writes are clocked, reads are not
	.rs1(rs1),						// Source register 1
	.rs2(rs2),						// Source register 2
	.rd(rd),						// Destination register
	.wren(intregisterwriteenable),	// Write enable bit for writing to register rd (delayed copy)
	.datain(rdata),					// Data into register rd (write)
	.rval1(rval1),					// Value of rs1 (read)
	.rval2(rval2) );				// Value of rs2 (read)

// Floating point register file
floatregisterfile myfloatregs(
	.clock(clock),
	.rs1(rs1),
	.rs2(rs2),
	.rs3(rs3),
	.rd(rd),
	.wren(floatregisterwriteenable),
	.datain(fdata),
	.rval1(frval1),
	.rval2(frval2),
	.rval3(frval3) );

// Output from ALU unit based on current op
wire [31:0] aluout;

// Integer ALU unit
ALU myalu(
	.aluout(aluout),		// Result of current ALU op
	.func3(func3),			// Sub instruction
	.val1(rval1),			// Input value one (rs1)
	.val2(rval2selector),	// Input value two (rs2 or immed)
	.aluop(aluop) );		// ALU op to apply
	
// Branch decision result
wire branchout;

// Branch ALU unit
branchALU mybranchalu(
	.branchout(branchout),	// High if we should take the branch
	.val1(rval1),			// Input value one (rs1)
	.val2(rval2selector),	// Input value two (rs2 or immed)
	.aluop(aluop) );		// Compare opearation for branch decision

// -----------------------------------------------------------------------
// Integer math
// -----------------------------------------------------------------------

wire mulbusy, divbusy, divbusyu;
wire [31:0] product;
wire [31:0] quotient;
wire [31:0] quotientu;
wire [31:0] remainder;
wire [31:0] remainderu;

wire isexecuting = cpustate[`CPUEXEC]==1'b1;
wire isexecutingfloatop = isexecuting & (opcode==`OPCODE_FLOAT_OP);

// Pulses to kick math operations
wire mulstart = isexecuting & (aluop==`ALU_MUL) & (opcode == `OPCODE_OP);
multiplier themul(
    .clk(clock),
    .reset(reset),
    .start(mulstart),
    .busy(mulbusy),           // calculation in progress
    .func3(func3),
    .multiplicand(rval1),
    .multiplier(rval2),
    .product(product) );

wire divstart = isexecuting & (aluop==`ALU_DIV | aluop==`ALU_REM) & (opcode == `OPCODE_OP);
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

// Stall status
wire imathstart = divstart | mulstart;
wire imathbusy = divbusy | divbusyu | mulbusy;

// -----------------------------------------------------------------------
// Floating point math - Reserved for future
// -----------------------------------------------------------------------

wire fmaddvalid = isexecuting & (opcode==`OPCODE_FLOAT_MADD);
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

wire fmsubvalid = isexecuting & (opcode==`OPCODE_FLOAT_MSUB);
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

wire fnmsubvalid = isexecuting & (opcode==`OPCODE_FLOAT_NMSUB); // is actually MADD!
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

wire fnmaddvalid = isexecuting & (opcode==`OPCODE_FLOAT_NMADD); // is actually MSUB!
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

wire faddvalid = isexecutingfloatop & (func7==`FADD);
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

wire fsubvalid = isexecutingfloatop & (func7==`FSUB);	
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

wire fmulvalid = isexecutingfloatop & (func7==`FMUL);	
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

wire fdivvalid = isexecutingfloatop & (func7==`FDIV);	
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

wire fi2fvalid = isexecutingfloatop & (func7==`FCVTSW) & (rs2==5'b00000); // Signed
logic [31:0] fi2fresult;
logic fi2fresultvalid;
fp_i2f floati2f(
	.s_axis_a_tdata(rval1), // A (integer register is source)
	.s_axis_a_tvalid(fi2fvalid),
	.aclk(clock),
	.m_axis_result_tdata(fi2fresult),
	.m_axis_result_tvalid(fi2fresultvalid) );
	
wire fui2fvalid = isexecutingfloatop & (func7==`FCVTSW) & (rs2==5'b00001); // Unsigned
logic [31:0] fui2fresult;
logic fui2fresultvalid;
fp_ui2f floatui2f(
	.s_axis_a_tdata(rval1), // A (integer register is source)
	.s_axis_a_tvalid(fui2fvalid),
	.aclk(clock),
	.m_axis_result_tdata(fui2fresult),
	.m_axis_result_tvalid(fui2fresultvalid) );

wire ff2ivalid = isexecutingfloatop & (func7==`FCVTWS) & (rs2==5'b00000); // Signed
logic [31:0] ff2iresult;
logic ff2iresultvalid;
fp_f2i floatf2i(
	.s_axis_a_tdata(frval1), // A (float register is source)
	.s_axis_a_tvalid(ff2ivalid),
	.aclk(clock),
	.m_axis_result_tdata(ff2iresult),
	.m_axis_result_tvalid(ff2iresultvalid) );

wire ff2uivalid = isexecutingfloatop & (func7==`FCVTWS) & (rs2==5'b00001); // Unsigned
logic [31:0] ff2uiresult;
logic ff2uiresultvalid;
// NOTE: Sharing same logic with f2i here, ignoring sign bit instead
fp_f2i floatf2ui(
	.s_axis_a_tdata({1'b0,frval1[30:0]}), // abs(A) (float register is source)
	.s_axis_a_tvalid(ff2uivalid),
	.aclk(clock),
	.m_axis_result_tdata(ff2uiresult),
	.m_axis_result_tvalid(ff2uiresultvalid) );
	
wire fsqrtvalid = isexecutingfloatop & (func7==`FSQRT);
logic [31:0] fsqrtresult;
logic fsqrtresultvalid;
fp_sqrt floatsqrt(
	.s_axis_a_tdata({1'b0,frval1[30:0]}), // abs(A) (float register is source)
	.s_axis_a_tvalid(fsqrtvalid),
	.aclk(clock),
	.m_axis_result_tdata(fsqrtresult),
	.m_axis_result_tvalid(fsqrtresultvalid) );

wire feqvalid = isexecutingfloatop & (func7==`FEQ) & (func3==3'b010); // FEQ
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

wire fltvalid = isexecutingfloatop & ( (func7 == `FMIN) | (func7 == `FMAX) | ((func7==`FEQ) & (func3==3'b001))); // FLT
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

wire flevalid = isexecutingfloatop & (func7==`FEQ) & (func3==3'b000); // FLE
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

// -----------------------------------------------------------------------
// Cycle/Timer/Reti CSRs
// -----------------------------------------------------------------------

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

// Custom CSRs r/w between 0x802-0x8FF

// Advancing cycles is simple since clocks = cycles
always @(posedge clock) begin
	CSRCycle <= CSRCycle + 64'd1;
end

// Time is also simple since we know we have 10M ticks per second
// from which we can derive seconds elapsed
always @(posedge wallclock) begin
	CSRTime <= CSRTime + 64'd1;
end

// -----------------------------------------------------------------------
// CPU Core
// -----------------------------------------------------------------------

always @(posedge clock) begin
	if (reset) begin
		instruction <= 32'd0;
		cpustate <= `CPUSTAGEMASK_RETIREINSTRUCTION;
	end else begin

		// Clear the state bits for next clock
		cpustate <= `CPUSTAGEMASK_NONE;

		// Selected state can now set the bit for the
		// next state for the next clock, which will
		// override the above zero-set.
		case (1'b1)
			cpustate[`CPUFETCH]: begin
				if (busstall) begin
					// Bus might stall during writes if busy
					// Wait in this state until it's freed
					cpustate[`CPUFETCH] <= 1'b1;
				end else begin
					// Can stop read request now
					// Read result will be available in DECODE stage
					cpureadena <= 1'b0;
					cpustate[`CPUDECODE] <= 1'b1;
				end
			end

			cpustate[`CPUDECODE]: begin
				// 'cpudatain' now contains our
				// instruction to decode
				// Set it as decoder input
				instruction <= cpudatain;
				cpustate[`CPUEXEC] <= 1'b1;
			end

			cpustate[`CPUEXEC]: begin
				// We decide on the nextPC in EXEC
				nextPC <= PC + 32'd4;

				// Set this up at the appropriate time
				// so that the write happens after
				// any values are calculated.
				intregisterwriteenable <= rwen;
				floatregisterwriteenable <= fwen;

				// Set up any nextPC or register data
				unique case (opcode)
					`OPCODE_AUPC: begin
						rdata <= PC + immed;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_LUI: begin
						rdata <= immed;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_JAL: begin
						rdata <= PC + 32'd4;
						nextPC <= PC + immed;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_OP, `OPCODE_OP_IMM: begin
						if (imathstart) begin
							// Shut down register writes before we damage something
							// since we need to route to a lengthy operation
							intregisterwriteenable <= 1'b0;
							cpustate[`CPUMSTALL] <= 1'b1;
						end else begin
							rdata <= aluout;
							cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
						end
					end
					`OPCODE_FLOAT_LDW, `OPCODE_LOAD: begin
						memaddress <= rval1 + immed;
						cpureadena <= 1'b1;
						// Load has to wait one extra clock
						// so that the memory load / register write
						// has time to complete.
						cpustate[`CPULOADSTALL] <= 1'b1;
					end
					`OPCODE_FLOAT_STW : begin
						fdata <= frval2;
						memaddress <= rval1 + immed;
						cpustate[`CPUFSTORE] <= 1'b1;
					end
					`OPCODE_STORE: begin
						rdata <= rval2;
						memaddress <= rval1 + immed;
						cpustate[`CPUSTORE] <= 1'b1;
					end
					`OPCODE_FENCE: begin
						// TODO:
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
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
						unique case (func3)
							3'b000: begin // ECALL/EBREAK
								unique case (instruction[31:20])
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
								unique case (csrindex)
									12'hC00: begin rdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=rval1;*/ end
									12'hC01: begin rdata <= CSRTime[31:0]; /*CSRTime[31:0]<=rval1;*/ end
									12'hC02: begin rdata <= CSRReti[31:0]; /*CSRReti[31:0]<=rval1;*/ end
									12'hC80: begin rdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=rval1;*/ end
									12'hC81: begin rdata <= CSRTime[63:32]; /*CSRTime[63:32]<=rval1;*/ end
									12'hC82: begin rdata <= CSRReti[63:32]; /*CSRReti[63:32]<=rval1;*/ end
									12'h300: begin rdata <= CSRmstatus; CSRmstatus<=rval1; end
									12'h304: begin rdata <= CSRmie; CSRmie<=rval1; end
									12'h305: begin rdata <= CSRmtvec; CSRmtvec<=rval1; end
									12'h341: begin rdata <= CSRmepc; CSRmepc<=rval1; end
									12'h342: begin rdata <= CSRmcause; CSRmcause<=rval1; end
									12'h344: begin rdata <= CSRmip; CSRmip<=rval1; end
									12'h800: begin rdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=rval1; end
									12'h801: begin rdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=rval1; end
								endcase
							end
							3'b010: begin // CSRRS
								unique case (csrindex)
									12'hC00: begin rdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=CSRCycle[31:0]&rval1;*/ end
									12'hC01: begin rdata <= CSRTime[31:0]; /*CSRTime[31:0]<=CSRTime[31:0]&rval1;*/ end
									12'hC02: begin rdata <= CSRReti[31:0]; /*CSRReti[31:0]<=CSRReti[31:0]&rval1;*/ end
									12'hC80: begin rdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=CSRCycle[63:32]&rval1;*/ end
									12'hC81: begin rdata <= CSRTime[63:32]; /*CSRTime[63:32]<=CSRTime[63:32]&rval1;*/ end
									12'hC82: begin rdata <= CSRReti[63:32]; /*CSRReti[63:32]<=CSRReti[63:32]&rval1;*/ end
									12'h300: begin rdata <= CSRmstatus; CSRmstatus<=CSRmstatus | rval1; end
									12'h304: begin rdata <= CSRmie; CSRmie<=CSRmie | rval1; end
									12'h305: begin rdata <= CSRmtvec; CSRmtvec<=CSRmtvec | rval1; end
									12'h341: begin rdata <= CSRmepc; CSRmepc<=CSRmepc | rval1; end
									12'h342: begin rdata <= CSRmcause; CSRmcause<=CSRmcause | rval1; end
									12'h344: begin rdata <= CSRmip; CSRmip<=CSRmip | rval1; end
									12'h800: begin rdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=CSRTimeCmp[31:0] | rval1; end
									12'h801: begin rdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=CSRTimeCmp[63:32] | rval1; end
								endcase
							end
							3'b011: begin // CSSRRC
								unique case (csrindex)
									12'hC00: begin rdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=CSRCycle[31:0]&(~rval1);*/ end
									12'hC01: begin rdata <= CSRTime[31:0]; /*CSRTime[31:0]<=CSRTime[31:0]&(~rval1);*/ end
									12'hC02: begin rdata <= CSRReti[31:0]; /*CSRReti[31:0]<=CSRReti[31:0]&(~rval1);*/ end
									12'hC80: begin rdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=CSRCycle[63:32]&(~rval1);*/ end
									12'hC81: begin rdata <= CSRTime[63:32]; /*CSRTime[63:32]<=CSRTime[63:32]&(~rval1);*/ end
									12'hC82: begin rdata <= CSRReti[63:32]; /*CSRReti[63:32]<=CSRReti[63:32]&(~rval1);*/ end
									12'h300: begin rdata <= CSRmstatus; CSRmstatus<=CSRmstatus&(~rval1); end
									12'h304: begin rdata <= CSRmie; CSRmie<=CSRmie&(~rval1); end
									12'h305: begin rdata <= CSRmtvec; CSRmtvec<=CSRmtvec&(~rval1); end
									12'h341: begin rdata <= CSRmepc; CSRmepc<=CSRmepc&(~rval1); end
									12'h342: begin rdata <= CSRmcause; CSRmcause<=CSRmcause&(~rval1); end
									12'h344: begin rdata <= CSRmip; CSRmip<=CSRmip&(~rval1); end
									12'h800: begin rdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=CSRTimeCmp[31:0]&(~rval1); end
									12'h801: begin rdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=CSRTimeCmp[63:32]&(~rval1); end
								endcase
							end
							3'b101: begin // CSRRWI
								unique case (csrindex)
									12'hC00: begin rdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=immed;*/ end
									12'hC01: begin rdata <= CSRTime[31:0]; /*CSRTime[31:0]<=immed;*/ end
									12'hC02: begin rdata <= CSRReti[31:0]; /*CSRReti[31:0]<=immed;*/ end
									12'hC80: begin rdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=immed;*/ end
									12'hC81: begin rdata <= CSRTime[63:32]; /*CSRTime[63:32]<=immed;*/ end
									12'hC82: begin rdata <= CSRReti[63:32]; /*CSRReti[63:32]<=immed;*/ end
									12'h300: begin rdata <= CSRmstatus; CSRmstatus<=immed; end
									12'h304: begin rdata <= CSRmie; CSRmie<=immed; end
									12'h305: begin rdata <= CSRmtvec; CSRmtvec<=immed; end
									12'h341: begin rdata <= CSRmepc; CSRmepc<=immed; end
									12'h342: begin rdata <= CSRmcause; CSRmcause<=immed; end
									12'h344: begin rdata <= CSRmip; CSRmip<=immed; end
									12'h800: begin rdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=immed; end
									12'h801: begin rdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=immed; end
								endcase
							end
							3'b110: begin // CSRRSI
								unique case (csrindex)
									12'hC00: begin rdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=CSRCycle[31:0]&immed;*/ end
									12'hC01: begin rdata <= CSRTime[31:0]; /*CSRTime[31:0]<=CSRTime[31:0]&immed;*/ end
									12'hC02: begin rdata <= CSRReti[31:0]; /*CSRReti[31:0]<=CSRReti[31:0]&immed;*/ end
									12'hC80: begin rdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=CSRCycle[63:32]&immed;*/ end
									12'hC81: begin rdata <= CSRTime[63:32]; /*CSRTime[63:32]<=CSRTime[63:32]&immed;*/ end
									12'hC82: begin rdata <= CSRReti[63:32]; /*CSRReti[63:32]<=CSRReti[63:32]&immed;*/ end
									12'h300: begin rdata <= CSRmstatus; CSRmstatus<=CSRmstatus | immed; end
									12'h304: begin rdata <= CSRmie; CSRmie<=CSRmie | immed; end
									12'h305: begin rdata <= CSRmtvec; CSRmtvec<=CSRmtvec | immed; end
									12'h341: begin rdata <= CSRmepc; CSRmepc<=CSRmepc | immed; end
									12'h342: begin rdata <= CSRmcause; CSRmcause<=CSRmcause | immed; end
									12'h344: begin rdata <= CSRmip; CSRmip<=CSRmip | immed; end
									12'h800: begin rdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=CSRTimeCmp[31:0] | immed; end
									12'h801: begin rdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=CSRTimeCmp[63:32] | immed; end
								endcase
							end
							3'b111: begin // CSRRCI
								unique case (csrindex)
									12'hC00: begin rdata <= CSRCycle[31:0]; /*CSRCycle[31:0]<=CSRCycle[31:0]&(~immed);*/ end
									12'hC01: begin rdata <= CSRTime[31:0]; /*CSRTime[31:0]<=CSRTime[31:0]&(~immed);*/ end
									12'hC02: begin rdata <= CSRReti[31:0]; /*CSRReti[31:0]<=CSRReti[31:0]&(~immed);*/ end
									12'hC80: begin rdata <= CSRCycle[63:32]; /*CSRCycle[63:32]<=CSRCycle[63:32]&(~immed);*/ end
									12'hC81: begin rdata <= CSRTime[63:32]; /*CSRTime[63:32]<=CSRTime[63:32]&(~immed);*/ end
									12'hC82: begin rdata <= CSRReti[63:32]; /*CSRReti[63:32]<=CSRReti[63:32]&(~immed);*/ end
									12'h300: begin rdata <= CSRmstatus; CSRmstatus<=CSRmstatus&(~immed); end
									12'h304: begin rdata <= CSRmie; CSRmie<=CSRmie&(~immed); end
									12'h305: begin rdata <= CSRmtvec; CSRmtvec<=CSRmtvec&(~immed); end
									12'h341: begin rdata <= CSRmepc; CSRmepc<=CSRmepc&(~immed); end
									12'h342: begin rdata <= CSRmcause; CSRmcause<=CSRmcause&(~immed); end
									12'h344: begin rdata <= CSRmip; CSRmip<=CSRmip&(~immed); end
									12'h800: begin rdata <= CSRTimeCmp[31:0]; CSRTimeCmp[31:0]<=CSRTimeCmp[31:0]&(~immed); end
									12'h801: begin rdata <= CSRTimeCmp[63:32]; CSRTimeCmp[63:32]<=CSRTimeCmp[63:32]&(~immed); end
								endcase
							end
						endcase
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_FLOAT_OP: begin
						// Sign injection is handled here, then retired.
						// Rest of the float operations fall through to stall states.
						if (func7 == `FSGNJ) begin
							unique case(func3)
								3'b000: begin // FSGNJ
									fdata <= {frval2[31], frval1[30:0]}; 
								end
								3'b001: begin  // FSGNJN
									fdata <= {~frval2[31], frval1[30:0]};
								end
								3'b010: begin  // FSGNJX
									fdata <= {frval1[31]^frval2[31], frval1[30:0]};
								end
							endcase
							cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
						end else if (func7 == `FMVXW) begin // Float to Int register (overlaps `FCLASS)
							cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
							if (func3 == 3'b000) //FMVXW
								rdata <= frval1;
							else // FCLASS
								rdata <= 32'd0; // TBD
						end else if (func7 == `FMVWX) begin // Int to Float register
							cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
							fdata <= rval1;
						end else begin
							intregisterwriteenable <= rwen;
							floatregisterwriteenable <= fwen;
							cpustate[`CPUFSTALL] <= 1'b1;
						end
					end
					`OPCODE_FLOAT_MADD, `OPCODE_FLOAT_MSUB, `OPCODE_FLOAT_NMSUB, `OPCODE_FLOAT_NMADD: begin
						floatregisterwriteenable <= 1'b0;
						cpustate[`CPUFFSTALL] <= 1'b1;
					end
					`OPCODE_JALR: begin
						rdata <= PC + 32'd4;
						nextPC <= rval1 + immed;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_BRANCH: begin
						nextPC <= branchout == 1'b1 ? PC + immed : PC + 32'd4;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					default: begin
						// This is an unhandled instruction
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
				endcase

			end
			
			cpustate[`CPUFSTALL]: begin
				if  (fmulresultvalid | fdivresultvalid | fi2fresultvalid | ff2iresultvalid | faddresultvalid | fsubresultvalid | fsqrtresultvalid | feqresultvalid | fltresultvalid | fleresultvalid) begin
					floatregisterwriteenable <= fwen;
					intregisterwriteenable <= rwen;
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					nextPC <= PC + 32'd4; // NOTE: +32'd2 for compressed instructions
					unique case (func7)
						`FADD: begin
							fdata <= faddresult;
						end
						`FSUB: begin
							fdata <= fsubresult;
						end
						`FMUL: begin
							fdata <= fmulresult;
						end
						`FDIV: begin
							fdata <= fdivresult;
						end
						`FCVTSW: begin // NOTE: FCVT.S.WU is unsigned version
							fdata <= rs2==5'b00000 ? fi2fresult : fui2fresult; // Result goes to float register (signed int to float)
						end
						`FCVTWS: begin // NOTE: FCVT.WU.S is unsigned version
							rdata <= rs2==5'b00000 ? ff2iresult : ff2uiresult; // Result goes to integer register (float to signed int)
						end
						`FSQRT: begin
							fdata <= fsqrtresult;
						end
						`FEQ: begin
							if (func3==3'b010) // FEQ
								rdata <= {31'd0,feqresult[0]};
							else if (func3==3'b001) // FLT
								rdata <= {31'd0,fltresult[0]};
							else //if (func3==3'b000) // FLE
								rdata <= {31'd0,fleresult[0]};
						end
						`FMIN: begin
							if (func3==3'b000) // FMIN
								fdata <= fltresult[0]==1'b0 ? frval2 : frval1;
							else // FMAX
								fdata <= fltresult[0]==1'b0 ? frval1 : frval2;
						end
						default: begin
							fdata <= 32'd0;
						end
					endcase
				end else begin
					cpustate[`CPUFSTALL] <= 1'b1; // Stall further for float op
				end
			end

			cpustate[`CPUFFSTALL]: begin
				if (fnmsubresultvalid | fnmaddresultvalid | fmsubresultvalid | fmaddresultvalid) begin
					floatregisterwriteenable <= 1'b1;
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					unique case (opcode)
						`OPCODE_FLOAT_NMSUB: begin
							fdata <= fnmsubresult;
						end
						`OPCODE_FLOAT_NMADD: begin
							fdata <= fnmaddresult;
						end
						`OPCODE_FLOAT_MADD: begin
							fdata <= fmaddresult;
						end
						`OPCODE_FLOAT_MSUB: begin
							fdata <= fmsubresult;
						end
						default: begin
							fdata <= 32'd0;
						end
					endcase
				end else begin
					cpustate[`CPUFFSTALL] <= 1'b1; // Stall further for fused float
				end
			end
			
			cpustate[`CPUMSTALL]: begin
				if (imathbusy) begin
					cpustate[`CPUMSTALL] <= 1'b1;
				end else begin
					// Re-enable register writes
					intregisterwriteenable <= 1'b1;
					unique case (aluop)
						`ALU_MUL: begin
							rdata <= product;
						end
						`ALU_DIV: begin
							rdata <= func3==`F3_DIV ? quotient : quotientu;
						end
						`ALU_REM: begin
							rdata <= func3==`F3_REM ? remainder : remainderu;
						end
					endcase
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
				end
			end
			
			cpustate[`CPULOADSTALL]: begin
				// Stall state for memory reads
				if (busstall) begin
					// Bus might stall during writes if busy
					// Wait in this state until it's freed
					cpustate[`CPULOADSTALL] <= 1'b1;
				end else begin
					// No more stall, can turn off read request
					cpureadena <= 1'b0;
					if (opcode == `OPCODE_FLOAT_LDW) begin
						cpustate[`CPUFLOADCOMPLETE] <= 1'b1;
					end else begin
						cpustate[`CPULOADCOMPLETE] <= 1'b1;
					end
				end
			end

			cpustate[`CPUFLOADCOMPLETE]: begin
				// DWORD
				fdata <= cpudatain;
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end

			cpustate[`CPULOADCOMPLETE]: begin
				// Read complete, handle register write-back
				unique case (func3)
					3'b000: begin // BYTE with sign extension
						unique case (memaddress[1:0])
							2'b11: begin rdata <= {{24{cpudatain[31]}},cpudatain[31:24]}; end
							2'b10: begin rdata <= {{24{cpudatain[23]}},cpudatain[23:16]}; end
							2'b01: begin rdata <= {{24{cpudatain[15]}},cpudatain[15:8]}; end
							2'b00: begin rdata <= {{24{cpudatain[7]}},cpudatain[7:0]}; end
						endcase
					end
					3'b001: begin // WORD with sign extension
						unique case (memaddress[1])
							1'b1: begin rdata <= {{16{cpudatain[31]}},cpudatain[31:16]}; end
							1'b0: begin rdata <= {{16{cpudatain[15]}},cpudatain[15:0]}; end
						endcase
					end
					3'b010: begin // DWORD
						rdata <= cpudatain[31:0];
					end
					3'b100: begin // BYTE with zero extension
						unique case (memaddress[1:0])
							2'b11: begin rdata <= {24'd0, cpudatain[31:24]}; end
							2'b10: begin rdata <= {24'd0, cpudatain[23:16]}; end
							2'b01: begin rdata <= {24'd0, cpudatain[15:8]}; end
							2'b00: begin rdata <= {24'd0, cpudatain[7:0]}; end
						endcase
					end
					3'b101: begin // WORD with zero extension
						unique case (memaddress[1])
							1'b1: begin rdata <= {16'd0, cpudatain[31:16]}; end
							1'b0: begin rdata <= {16'd0, cpudatain[15:0]}; end
						endcase
					end
				endcase
				intregisterwriteenable <= 1'b1; // We can now write back
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end

			cpustate[`CPUFSTORE]: begin
				// DWORD
				cpuwriteena <= 4'b1111;
				cpudataout <= fdata;
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end

			cpustate[`CPUSTORE]: begin
				if (busstall) begin
					// Bus might stall during writes if busy
					// Wait in this state until it's freed
					cpustate[`CPUSTORE] <= 1'b1;
				end else begin
					// Request write of current register data to memory
					// with appropriate write mask and data size
					unique case (func3)
						3'b000: begin // BYTE
							cpudataout <= {rdata[7:0], rdata[7:0], rdata[7:0], rdata[7:0]};
							unique case (memaddress[1:0])
								2'b11: begin cpuwriteena <= 4'b1000; end
								2'b10: begin cpuwriteena <= 4'b0100; end
								2'b01: begin cpuwriteena <= 4'b0010; end
								2'b00: begin cpuwriteena <= 4'b0001; end
							endcase
						end
						3'b001: begin // WORD
							cpudataout <= {rdata[15:0], rdata[15:0]};
							unique case (memaddress[1])
								1'b1: begin cpuwriteena <= 4'b1100; end
								1'b0: begin cpuwriteena <= 4'b0011; end
							endcase
						end
						default: begin // DWORD
							cpudataout <= rdata;
							cpuwriteena <= 4'b1111;
						end
					endcase
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
				end
			end

			cpustate[`CPURETIREINSTRUCTION]: begin
				// We need to turn off the
				// register write enable lines
				// before we fetch and decode a new
				// instruction so we don't destroy
				// any registers while rd changes
				intregisterwriteenable <= 1'b0;
				floatregisterwriteenable <= 1'b0;

				// Turn off memory writes in flight
				cpuwriteena <= 4'b0000;

				// Turn on reads to fetch the next instruction
				cpureadena <= 1'b1;

				// If timer interrupts and global machine interrupts enabled
				// Time interrupt stays pending
				// Stays posted until timecmp > time (usually after writing to timecmp)
				if (CSRmstatus[3] & CSRmie[7] & (CSRTime >= CSRTimeCmp)) begin
					// Timer interrupt
					CSRmip[7] <= 1'b1; // Set pending timer interrupt status
					CSRmcause <= 32'd7; // Timer Interrupt
					CSRmcause[31:16] <= 16'd0; // Type of timer interrupt is set to zero
					CSRmstatus[7] <= CSRmstatus[3]; // MPIE = MIE (save ie flag in previous ie)
					CSRmstatus[3] <= 1'b0; // Clear MIE (disable interrupts)
					// Remember where to return
					CSRmepc <= nextPC;
					// Go to trap handler
					PC <= CSRmtvec;
					memaddress <= CSRmtvec;
				end else if (CSRmstatus[3] & CSRmie[11] & IRQ) begin
					// External interrupt of type IRQ_TYPE
					CSRmip[11] <= 1'b1; // Set pending machine interrupt status
					CSRmcause <= 32'd11; // Machine External Interrupt
					CSRmcause[31:16] <= {14'd0, IRQ_TYPE};
					CSRmstatus[7] <= CSRmstatus[3]; // MPIE = MIE (save ie flag in previous ie)
					CSRmstatus[3] <= 1'b0; // Clear MIE (disable interrupts)
					// Remember where to return
					CSRmepc <= nextPC;
					// Go to trap handler
					PC <= CSRmtvec;
					memaddress <= CSRmtvec;
				end else begin
					// Set next PC
					PC <= nextPC;
					memaddress <= nextPC;
				end

				// Update retired instruction count CSR
				CSRReti <= CSRReti + 64'd1;

				cpustate[`CPUFETCH] <= 1'b1;
			end
		endcase
	end
end

endmodule
