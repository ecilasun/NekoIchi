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

logic [31:0] PC = 32'h20000000;			// Boot from AudioRAM/BootROM device
logic [31:0] nextPC = 32'h20000000;		// Has to be same as PC at startup

// Assume no ebreak
logic ebreak = 1'b0;
// Assume valid instruction
logic illegalinstruction = 1'b0;

// Write address has to be set at the same time
// as read or write enable, this shadow ensures that
logic [31:0] targetaddress;

// Integer and float file write control lines
wire rwen, fwen;
// Delayed write enable copy for EXEC step
logic intregisterwriteenable = 1'b0;
logic floatregisterwriteenable = 1'b0;

// Data input for register writes
logic [31:0] rdata = 32'd0;
logic [31:0] fdata = 32'd0;

// Data for memory store
logic [31:0] storedata = 32'd0;

// Instruction decoder and related wires
wire [6:0] Wopcode;
wire [4:0] Waluop;
wire [2:0] Wfunc3;
wire [6:0] Wfunc7;
wire [11:0] Wfunc12;
wire [4:0] Wrs1;
wire [4:0] Wrs2;
wire [4:0] Wrs3;
wire [4:0] Wrd;
wire [11:0] Wcsrindex;
wire [31:0] Wimmed;
wire Wselectimmedasrval2;

// Decoder will attempt to operate on all memory input
logic decodeenable = 1'b0;
decoder mydecoder(
	.clock(clock),
	.enable(decodeenable),
	.instruction(cpudatain),
	.opcode(Wopcode),
	.rwen(rwen),
	.fwen(fwen),
	.aluop(Waluop),
	.func3(Wfunc3),
	.func7(Wfunc7),
	.func12(Wfunc12),
	.rs1(Wrs1),
	.rs2(Wrs2),
	.rs3(Wrs3), // Used for fused multiply-add/sub float instructions 
	.rd(Wrd),
	.immed(Wimmed),
	.csrindex(Wcsrindex),
	.selectimmedasrval2(Wselectimmedasrval2) );

// Read results from integer and float registers
wire [31:0] rval1;
wire [31:0] rval2;
wire [31:0] frval1;
wire [31:0] frval2;
wire [31:0] frval3;

// Integer register file
registerfile myintegerregs(
	.clock(clock),					// Writes are clocked, reads are not
	.rs1(Wrs1),						// Source register 1
	.rs2(Wrs2),						// Source register 2
	.rd(Wrd),						// Destination register
	.wren(intregisterwriteenable),	// Write enable bit for writing to register rd (delayed copy)
	.datain(rdata),					// Data into register rd (write)
	.rval1(rval1),					// Value of rs1 (read)
	.rval2(rval2) );				// Value of rs2 (read)

// Floating point register file
floatregisterfile myfloatregs(
	.clock(clock),
	.rs1(Wrs1),
	.rs2(Wrs2),
	.rs3(Wrs3),
	.rd(Wrd),
	.wren(floatregisterwriteenable),
	.datain(fdata),
	.rval1(frval1),
	.rval2(frval2),
	.rval3(frval3) );

// Output from ALU unit based on current op
wire [31:0] aluout;

// Integer ALU unit
ALU myalu(
	.aluout(aluout),								// Result of current ALU op
	.func3(Wfunc3),									// Sub instruction
	.val1(rval1),									// Input value one (rs1)
	.val2(Wselectimmedasrval2 ? Wimmed : rval2),	// Input value two (rs2 or immed)
	.aluop(Waluop) );								// ALU op to apply
	
// Branch decision result
wire branchout;

// Branch ALU unit
branchALU mybranchalu(
	.branchout(branchout),							// High if we should take the branch
	.val1(rval1),									// Input value one (rs1)
	.val2(Wselectimmedasrval2 ? Wimmed : rval2),	// Input value two (rs2 or immed)
	.aluop(Waluop) );								// Compare opearation for branch decision

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
wire isexecutingfloatop = isexecuting & (Wopcode==`OPCODE_FLOAT_OP);

// Pulses to kick math operations
wire mulstart = isexecuting & (Waluop==`ALU_MUL) & (Wopcode == `OPCODE_OP);
multiplier themul(
    .clk(clock),
    .reset(reset),
    .start(mulstart),
    .busy(mulbusy),           // calculation in progress
    .func3(Wfunc3),
    .multiplicand(rval1),
    .multiplier(rval2),
    .product(product) );

wire divstart = isexecuting & (Waluop==`ALU_DIV | Waluop==`ALU_REM) & (Wopcode == `OPCODE_OP);
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
// Floating point math
// -----------------------------------------------------------------------

logic fmaddvalid = 1'b0;
logic fmsubvalid = 1'b0;
logic fnmsubvalid = 1'b0;
logic fnmaddvalid = 1'b0;
logic faddvalid = 1'b0;
logic fsubvalid = 1'b0;
logic fmulvalid = 1'b0;
logic fdivvalid = 1'b0;
logic fi2fvalid = 1'b0;
logic fui2fvalid = 1'b0;
logic ff2ivalid = 1'b0;
logic ff2uivalid = 1'b0;
logic fsqrtvalid = 1'b0;
logic feqvalid = 1'b0;
logic fltvalid = 1'b0;
logic flevalid = 1'b0;

wire fmaddresultvalid;
wire fmsubresultvalid;
wire fnmsubresultvalid; 
wire fnmaddresultvalid;
wire faddresultvalid;
wire fsubresultvalid;
wire fmulresultvalid;
wire fdivresultvalid;
wire fi2fresultvalid;
wire fui2fresultvalid;
wire ff2iresultvalid;
wire ff2uiresultvalid;
wire fsqrtresultvalid;
wire feqresultvalid;
wire fltresultvalid;
wire fleresultvalid;

wire [31:0] fmaddresult;
wire [31:0] fmsubresult;
wire [31:0] fnmsubresult;
wire [31:0] fnmaddresult;
wire [31:0] faddresult;
wire [31:0] fsubresult;
wire [31:0] fmulresult;
wire [31:0] fdivresult;
wire [31:0] fi2fresult;
wire [31:0] fui2fresult;
wire [31:0] ff2iresult;
wire [31:0] ff2uiresult;
wire [31:0] fsqrtresult;
wire [7:0] feqresult;
wire [7:0] fltresult;
wire [7:0] fleresult;

fp_madd floatfmadd(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(fmaddvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(fmaddvalid),
	.s_axis_c_tdata(frval3),
	.s_axis_c_tvalid(fmaddvalid),
	.aclk(clock),
	.m_axis_result_tdata(fmaddresult),
	.m_axis_result_tvalid(fmaddresultvalid) );

fp_msub floatfmsub(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(fmsubvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(fmsubvalid),
	.s_axis_c_tdata(frval3),
	.s_axis_c_tvalid(fmsubvalid),
	.aclk(clock),
	.m_axis_result_tdata(fmsubresult),
	.m_axis_result_tvalid(fmsubresultvalid) );

fp_madd floatfnmsub(
	.s_axis_a_tdata({~frval1[31], frval1[30:0]}), // -A
	.s_axis_a_tvalid(fnmsubvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(fnmsubvalid),
	.s_axis_c_tdata(frval3),
	.s_axis_c_tvalid(fnmsubvalid),
	.aclk(clock),
	.m_axis_result_tdata(fnmsubresult),
	.m_axis_result_tvalid(fnmsubresultvalid) );

fp_msub floatfnmadd(
	.s_axis_a_tdata({~frval1[31], frval1[30:0]}), // -A
	.s_axis_a_tvalid(fnmaddvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(fnmaddvalid),
	.s_axis_c_tdata(frval3),
	.s_axis_c_tvalid(fnmaddvalid),
	.aclk(clock),
	.m_axis_result_tdata(fnmaddresult),
	.m_axis_result_tvalid(fnmaddresultvalid) );

fp_add floatadd(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(faddvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(faddvalid),
	.aclk(clock),
	.m_axis_result_tdata(faddresult),
	.m_axis_result_tvalid(faddresultvalid) );
	
fp_sub floatsub(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(fsubvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(fsubvalid),
	.aclk(clock),
	.m_axis_result_tdata(fsubresult),
	.m_axis_result_tvalid(fsubresultvalid) );


fp_mul floatmul(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(fmulvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(fmulvalid),
	.aclk(clock),
	.m_axis_result_tdata(fmulresult),
	.m_axis_result_tvalid(fmulresultvalid) );

fp_div floatdiv(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(fdivvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(fdivvalid),
	.aclk(clock),
	.m_axis_result_tdata(fdivresult),
	.m_axis_result_tvalid(fdivresultvalid) );

fp_i2f floati2f(
	.s_axis_a_tdata(rval1), // Integer source
	.s_axis_a_tvalid(fi2fvalid),
	.aclk(clock),
	.m_axis_result_tdata(fi2fresult),
	.m_axis_result_tvalid(fi2fresultvalid) );

fp_ui2f floatui2f(
	.s_axis_a_tdata(rval1), // Integer source
	.s_axis_a_tvalid(fui2fvalid),
	.aclk(clock),
	.m_axis_result_tdata(fui2fresult),
	.m_axis_result_tvalid(fui2fresultvalid) );

fp_f2i floatf2i(
	.s_axis_a_tdata(frval1), // Float source
	.s_axis_a_tvalid(ff2ivalid),
	.aclk(clock),
	.m_axis_result_tdata(ff2iresult),
	.m_axis_result_tvalid(ff2iresultvalid) );

// NOTE: Sharing same logic with f2i here, ignoring sign bit instead
fp_f2i floatf2ui(
	.s_axis_a_tdata({1'b0,frval1[30:0]}), // abs(A) (float register is source)
	.s_axis_a_tvalid(ff2uivalid),
	.aclk(clock),
	.m_axis_result_tdata(ff2uiresult),
	.m_axis_result_tvalid(ff2uiresultvalid) );
	
fp_sqrt floatsqrt(
	.s_axis_a_tdata({1'b0,frval1[30:0]}), // abs(A) (float register is source)
	.s_axis_a_tvalid(fsqrtvalid),
	.aclk(clock),
	.m_axis_result_tdata(fsqrtresult),
	.m_axis_result_tvalid(fsqrtresultvalid) );

fp_eq floateq(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(feqvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(feqvalid),
	.aclk(clock),
	.m_axis_result_tdata(feqresult),
	.m_axis_result_tvalid(feqresultvalid) );

fp_lt floatlt(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(fltvalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(fltvalid),
	.aclk(clock),
	.m_axis_result_tdata(fltresult),
	.m_axis_result_tvalid(fltresultvalid) );

fp_le floatle(
	.s_axis_a_tdata(frval1),
	.s_axis_a_tvalid(flevalid),
	.s_axis_b_tdata(frval2),
	.s_axis_b_tvalid(flevalid),
	.aclk(clock),
	.m_axis_result_tdata(fleresult),
	.m_axis_result_tvalid(fleresultvalid) );

// -----------------------------------------------------------------------
// Cycle/Timer/Reti CSRs
// -----------------------------------------------------------------------

// MXL:1 (32 bits)
// Extensions: I M F
logic [31:0] CSRmisa = {2'b01, 4'b0000, 26'b00000000000001000100100000};

// Vendor: non-commercial
logic [31:0] CSRmvendorid = 0;

logic [31:0] CSRmtval = 32'd0;
logic [31:0] CSRmscratch = 32'd0;
logic [31:0] CSRmepc = 32'd0;
logic [31:0] CSRmcause = 32'd0;
logic [31:0] CSRmip = 32'd0;
logic [31:0] CSRmtvec = 32'd0;
logic [31:0] CSRmie = 32'd0;
logic [31:0] CSRmstatus = 32'd0;

//logic [31:0] CSRmhartid = 32'd0; // f14 Hart ID (at least one should be hart#0)

//logic [31:0] CSRdcsr = 32'd0; // 7b0 Debug control and status register
//logic [31:0] CSRdpc = 32'd0; // 7b1 Debug PC

//logic [31:0] CSRfflags = 32'd0; // 001
//logic [31:0] CSRfrm = 32'd0; // 002
//logic [31:0] CSRfcsr = 32'd0; // 003

logic [63:0] CSRTime = 64'd0;

// Custom CSR pair at 0x800/0x801, not using memory mapped timecmp
logic [63:0] CSRTimeCmp = 64'hFFFFFFFFFFFFFFFF;

logic [63:0] CSRCycle = 64'd0;
logic [63:0] CSRReti = 64'd0;

// Custom CSRs r/w between 0x802-0x8FF

// Advancing cycles is simple since clocks = cycles
logic [63:0] internalcyclecounter = 64'd0;
always @(posedge clock) begin
	internalcyclecounter <= internalcyclecounter + 64'd1;
end

// Time is also simple since we know we have 10M ticks per second
// from which we can derive seconds elapsed
logic [63:0] internalwallclockcounter = 64'd0;
always @(posedge wallclock) begin
	internalwallclockcounter <= internalwallclockcounter + 64'd1;
end

logic [63:0] internalretirecounter = 64'd0;
always @(posedge clock) begin
	if (cpustate[`CPURETIREINSTRUCTION] == 1'b1) begin
		internalretirecounter <= internalretirecounter + 64'd1;
	end
end

// -----------------------------------------------------------------------
// CPU Core
// -----------------------------------------------------------------------

always @(posedge clock) begin
	if (reset) begin

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
					decodeenable <= 1'b1;
					cpustate[`CPUDECODE] <= 1'b1;
				end
			end

			cpustate[`CPUDECODE]: begin
				decodeenable <= 1'b0;
				// Update counters
				CSRCycle <= internalcyclecounter;
				CSRTime <= internalwallclockcounter;
				CSRReti <= internalretirecounter;
				cpustate[`CPUEXEC] <= 1'b1;
			end

			cpustate[`CPUEXEC]: begin
				// We decide on the nextPC in EXEC
				nextPC <= PC + 32'd4;

				ebreak <= 1'b0;
				illegalinstruction <= 1'b0;

				// These actually work (and generate much better WNS) in synthesis, DO NOT remove!
				// Consider these as the catch-all for unassigned states, set to don't care value X.
				fdata <= 32'd0; // Don't care
				rdata <= 32'd0; // Don't care
				storedata <= 32'd0; // Don't care
				//memaddress <= 32'd0; // Don't touch without corresponding re/we set
				targetaddress <= 32'd0; // Don't care

				// Set this up at the appropriate time
				// so that the write happens after
				// any values are calculated.
				intregisterwriteenable <= rwen;
				floatregisterwriteenable <= fwen;

				// Set up any nextPC or register data
				unique case (Wopcode)
					`OPCODE_AUPC: begin
						rdata <= PC + Wimmed;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_LUI: begin
						rdata <= Wimmed;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_JAL: begin
						rdata <= PC + 32'd4;
						nextPC <= PC + Wimmed;
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
						memaddress <= rval1 + Wimmed;
						cpureadena <= 1'b1;
						// Load has to wait one extra clock
						// so that the memory load / register write
						// has time to complete.
						cpustate[`CPULOADSTALL] <= 1'b1;
					end
					`OPCODE_FLOAT_STW : begin
						storedata <= frval2;
						targetaddress <= rval1 + Wimmed;
						cpustate[`CPUFSTORE] <= 1'b1;
					end
					`OPCODE_STORE: begin
						storedata <= rval2;
						targetaddress <= rval1 + Wimmed;
						cpustate[`CPUSTORE] <= 1'b1;
					end
					`OPCODE_FENCE: begin
						// TODO:
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_SYSTEM: begin
						unique case (Wfunc3)
							3'b000: begin // ECALL/EBREAK
								cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
								unique case (Wfunc12)
									12'b000000000000: begin // ECALL
										// TBD
										// example: 
										// li a7, SBI_SHUTDOWN // also a0/a1/a2, retval in a0
  										// ecall
  									end
									12'b000000000001: begin // EBREAK
										ebreak <= 1'b1;
									end
									// privileged instructions
									12'b001100000010: begin // MRET
										if (CSRmcause[15:0] == 16'd2) CSRmip[2] <= 1'b0; // Disable illegal instruction exception pending
										if (CSRmcause[15:0] == 16'd3) CSRmip[3] <= 1'b0; // Disable machine interrupt pending
										if (CSRmcause[15:0] == 16'd7) CSRmip[7] <= 1'b0; // Disable machine timer interrupt pending
										if (CSRmcause[15:0] == 16'd11) CSRmip[11] <= 1'b0; // Disable machine external interrupt pending
										CSRmstatus[3] <= CSRmstatus[7]; // MIE=MPIE - set to previous machine interrupt enable state
										CSRmstatus[7] <= 1'b0; // Clear MPIE
										nextPC <= CSRmepc;
									end
								endcase
							end
							3'b001, // CSRRW
							3'b010, // CSRRS
							3'b011, // CSSRRC
							3'b101, // CSRRWI
							3'b110, // CSRRSI
							3'b111: begin // CSRRCI
								cpustate[`CPUUPDATECSR] <= 1'b1;
								// Swap rs1 and csr register values
								unique case (Wcsrindex)
									12'h300: begin rdata <= CSRmstatus;end
									12'h301: begin rdata <= CSRmisa; end
									12'h304: begin rdata <= CSRmie; end
									12'h305: begin rdata <= CSRmtvec; end
									12'h340: begin rdata <= CSRmscratch; end
									12'h341: begin rdata <= CSRmepc; end
									12'h342: begin rdata <= CSRmcause; end
									12'h343: begin rdata <= CSRmtval; end
									12'h344: begin rdata <= CSRmip; end
									12'h800: begin rdata <= CSRTimeCmp[31:0]; end
									12'h801: begin rdata <= CSRTimeCmp[63:32]; end
									12'hB00: begin rdata <= CSRCycle[31:0]; end
									12'hB80: begin rdata <= CSRCycle[63:32]; end
									12'hC01: begin rdata <= CSRTime[31:0]; end
									12'hC02: begin rdata <= CSRReti[31:0]; end
									12'hC81: begin rdata <= CSRTime[63:32]; end
									12'hC82: begin rdata <= CSRReti[63:32]; end
									12'hF11: begin rdata <= CSRmvendorid; end
								endcase
							end
							default: begin
								cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
							end
						endcase
					end
					`OPCODE_FLOAT_OP: begin
						unique case (Wfunc7)
							`FSGNJ: begin
								unique case(Wfunc3)
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
							end
							`FMVXW: begin
								if (Wfunc3 == 3'b000) //FMVXW
									rdata <= frval1;
								else // FCLASS
									rdata <= 32'd0; // TBD
								cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
							end
							`FMVWX: begin
								fdata <= rval1;
								cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
							end
							`FADD: begin
								faddvalid <= 1'b1;
								cpustate[`CPUFSTALL] <= 1'b1;
							end
							`FSUB: begin
								fsubvalid <= 1'b1;
								cpustate[`CPUFSTALL] <= 1'b1;
							end	
							`FMUL: begin
								fmulvalid <= 1'b1;
								cpustate[`CPUFSTALL] <= 1'b1;
							end	
							`FDIV: begin
								fdivvalid <= 1'b1;
								cpustate[`CPUFSTALL] <= 1'b1;
							end
							`FCVTSW: begin	
								fi2fvalid <= (Wrs2==5'b00000) ? 1'b1:1'b0; // Signed
								fui2fvalid <= (Wrs2==5'b00001) ? 1'b1:1'b0; // Unsigned
								cpustate[`CPUFSTALL] <= 1'b1;
							end
							`FCVTWS: begin
								ff2ivalid <= (Wrs2==5'b00000) ? 1'b1:1'b0; // Signed
								ff2uivalid <= (Wrs2==5'b00001) ? 1'b1:1'b0; // Unsigned
								cpustate[`CPUFSTALL] <= 1'b1;
							end
							`FSQRT: begin
								fsqrtvalid <= 1'b1;
								cpustate[`CPUFSTALL] <= 1'b1;
							end
							`FEQ: begin
								feqvalid <= (Wfunc3==3'b010) ? 1'b1:1'b0; // FEQ
								fltvalid <= (Wfunc3==3'b001) ? 1'b1:1'b0; // FLT
								flevalid <= (Wfunc3==3'b000) ? 1'b1:1'b0; // FLE
								cpustate[`CPUFSTALL] <= 1'b1;
							end
							`FMAX: begin
								fltvalid <= 1'b1; // FLT
								cpustate[`CPUFSTALL] <= 1'b1;
							end
						endcase
					end
					`OPCODE_FLOAT_MADD: begin
						fmaddvalid <= 1'b1;
						cpustate[`CPUFFSTALL] <= 1'b1;
					end
					`OPCODE_FLOAT_MSUB: begin
						fmsubvalid <= 1'b1;
						cpustate[`CPUFFSTALL] <= 1'b1;
					end
					`OPCODE_FLOAT_NMSUB: begin
						fnmsubvalid <= 1'b1; // is actually MADD!
						cpustate[`CPUFFSTALL] <= 1'b1;
					end
					`OPCODE_FLOAT_NMADD: begin
						fnmaddvalid <= 1'b1; // is actually MSUB!
						cpustate[`CPUFFSTALL] <= 1'b1;
					end
					`OPCODE_JALR: begin
						rdata <= PC + 32'd4;
						nextPC <= rval1 + Wimmed;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_BRANCH: begin
						nextPC <= branchout == 1'b1 ? PC + Wimmed : PC + 32'd4;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
					default: begin
						// This is an unhandled instruction
						illegalinstruction <= 1'b1;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
				endcase

			end
			
			cpustate[`CPUUPDATECSR]: begin
				// Write to r/w CSR
				unique case(Wfunc3)
					3'b001: begin // CSRRW
						// Swap rs1 and csr register values
						unique case (Wcsrindex)
							12'h300: begin CSRmstatus<=rval1; end
							12'h301: begin CSRmisa<=rval1; end
							12'h304: begin CSRmie<=rval1; end
							12'h305: begin CSRmtvec<=rval1; end
							12'h340: begin CSRmscratch<=rval1; end
							12'h341: begin CSRmepc<=rval1; end
							12'h342: begin CSRmcause<=rval1; end
							12'h343: begin CSRmtval<=rval1; end
							12'h344: begin CSRmip<=rval1; end
							12'h800: begin CSRTimeCmp[31:0]<=rval1; end
							12'h801: begin CSRTimeCmp[63:32]<=rval1; end
						endcase
					end
					3'b010: begin // CSRRS
						unique case (Wcsrindex)
							12'h300: begin CSRmstatus<=CSRmstatus | rval1; end
							12'h301: begin CSRmisa<=CSRmisa | rval1; end
							12'h304: begin CSRmie<=CSRmie | rval1; end
							12'h305: begin CSRmtvec<=CSRmtvec | rval1; end
							12'h340: begin CSRmscratch<=CSRmscratch | rval1; end
							12'h341: begin CSRmepc<=CSRmepc | rval1; end
							12'h342: begin CSRmcause<=CSRmcause | rval1; end
							12'h343: begin CSRmtval<=CSRmtval | rval1; end
							12'h344: begin CSRmip<=CSRmip | rval1; end
							12'h800: begin CSRTimeCmp[31:0]<=CSRTimeCmp[31:0] | rval1; end
							12'h801: begin CSRTimeCmp[63:32]<=CSRTimeCmp[63:32] | rval1; end
						endcase
					end
					3'b011: begin // CSSRRC
						unique case (Wcsrindex)
							12'h300: begin CSRmstatus<=CSRmstatus&(~rval1); end
							12'h301: begin CSRmisa<=CSRmisa&(~rval1); end
							12'h304: begin CSRmie<=CSRmie&(~rval1); end
							12'h305: begin CSRmtvec<=CSRmtvec&(~rval1); end
							12'h340: begin CSRmscratch<=CSRmscratch&(~rval1); end
							12'h341: begin CSRmepc<=CSRmepc&(~rval1); end
							12'h342: begin CSRmcause<=CSRmcause&(~rval1); end
							12'h343: begin CSRmtval<=CSRmtval&(~rval1); end
							12'h344: begin CSRmip<=CSRmip&(~rval1); end
							12'h800: begin CSRTimeCmp[31:0]<=CSRTimeCmp[31:0]&(~rval1); end
							12'h801: begin CSRTimeCmp[63:32]<=CSRTimeCmp[63:32]&(~rval1); end
						endcase
					end
					3'b101: begin // CSRRWI
						unique case (Wcsrindex)
							12'h300: begin CSRmstatus<=Wimmed; end
							12'h301: begin CSRmisa<=Wimmed; end
							12'h304: begin CSRmie<=Wimmed; end
							12'h305: begin CSRmtvec<=Wimmed; end
							12'h340: begin CSRmscratch<=Wimmed; end
							12'h341: begin CSRmepc<=Wimmed; end
							12'h342: begin CSRmcause<=Wimmed; end
							12'h343: begin CSRmtval<=Wimmed; end
							12'h344: begin CSRmip<=Wimmed; end
							12'h800: begin CSRTimeCmp[31:0]<=Wimmed; end
							12'h801: begin CSRTimeCmp[63:32]<=Wimmed; end
						endcase
					end
					3'b110: begin // CSRRSI
						unique case (Wcsrindex)
							12'h300: begin CSRmstatus<=CSRmstatus | Wimmed; end
							12'h301: begin CSRmisa<=CSRmisa | Wimmed; end
							12'h304: begin CSRmie<=CSRmie | Wimmed; end
							12'h305: begin CSRmtvec<=CSRmtvec | Wimmed; end
							12'h340: begin CSRmscratch<=CSRmscratch | Wimmed; end
							12'h341: begin CSRmepc<=CSRmepc | Wimmed; end
							12'h342: begin CSRmcause<=CSRmcause | Wimmed; end
							12'h343: begin CSRmtval<=CSRmtval | Wimmed; end
							12'h344: begin CSRmip<=CSRmip | Wimmed; end
							12'h800: begin CSRTimeCmp[31:0]<=CSRTimeCmp[31:0] | Wimmed; end
							12'h801: begin CSRTimeCmp[63:32]<=CSRTimeCmp[63:32] | Wimmed; end
						endcase
					end
					3'b111: begin // CSRRCI
						unique case (Wcsrindex)
							12'h300: begin CSRmstatus<=CSRmstatus&(~Wimmed); end
							12'h301: begin CSRmisa<=CSRmisa&(~Wimmed); end
							12'h304: begin CSRmie<=CSRmie&(~Wimmed); end
							12'h305: begin CSRmtvec<=CSRmtvec&(~Wimmed); end
							12'h340: begin CSRmscratch<=CSRmscratch&(~Wimmed); end
							12'h341: begin CSRmepc<=CSRmepc&(~Wimmed); end
							12'h342: begin CSRmcause<=CSRmcause&(~Wimmed); end
							12'h343: begin CSRmtval<=CSRmtval&(~Wimmed); end
							12'h344: begin CSRmip<=CSRmip&(~Wimmed); end
							12'h800: begin CSRTimeCmp[31:0]<=CSRTimeCmp[31:0]&(~Wimmed); end
							12'h801: begin CSRTimeCmp[63:32]<=CSRTimeCmp[63:32]&(~Wimmed); end
						endcase
					end
				endcase
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end
			
			cpustate[`CPUFSTALL]: begin

				faddvalid <= 1'b0;
				fsubvalid <= 1'b0;
				fmulvalid <= 1'b0;
				fdivvalid <= 1'b0;
				fi2fvalid <= 1'b0;
				fui2fvalid <= 1'b0;
				ff2ivalid <= 1'b0;
				ff2uivalid <= 1'b0;
				fsqrtvalid <= 1'b0;
				feqvalid <= 1'b0;
				fltvalid <= 1'b0;
				flevalid <= 1'b0;

				if  (fmulresultvalid | fdivresultvalid | fi2fresultvalid | fui2fresultvalid | ff2iresultvalid | ff2uiresultvalid | faddresultvalid | fsubresultvalid | fsqrtresultvalid | feqresultvalid | fltresultvalid | fleresultvalid) begin
					intregisterwriteenable <= rwen;
					floatregisterwriteenable <= fwen;
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					unique case (Wfunc7)
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
							fdata <= Wrs2==5'b00000 ? fi2fresult : fui2fresult; // Result goes to float register (signed int to float)
						end
						`FCVTWS: begin // NOTE: FCVT.WU.S is unsigned version
							rdata <= Wrs2==5'b00000 ? ff2iresult : ff2uiresult; // Result goes to integer register (float to signed int)
						end
						`FSQRT: begin
							fdata <= fsqrtresult;
						end
						`FEQ: begin
							if (Wfunc3==3'b010) // FEQ
								rdata <= {31'd0,feqresult[0]};
							else if (Wfunc3==3'b001) // FLT
								rdata <= {31'd0,fltresult[0]};
							else //if (Wfunc3==3'b000) // FLE
								rdata <= {31'd0,fleresult[0]};
						end
						`FMIN: begin
							if (Wfunc3==3'b000) // FMIN
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

				fmaddvalid <= 1'b0;
				fmsubvalid <= 1'b0;
				fnmsubvalid <= 1'b0;
				fnmaddvalid <= 1'b0;

				if (fnmsubresultvalid | fnmaddresultvalid | fmsubresultvalid | fmaddresultvalid) begin
					floatregisterwriteenable <= 1'b1;
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					unique case (Wopcode)
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
					unique case (Waluop)
						`ALU_MUL: begin
							rdata <= product;
						end
						`ALU_DIV: begin
							rdata <= Wfunc3==`F3_DIV ? quotient : quotientu;
						end
						`ALU_REM: begin
							rdata <= Wfunc3==`F3_REM ? remainder : remainderu;
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
					cpureadena <= 1'b0;
					if (Wopcode == `OPCODE_FLOAT_LDW) begin
						cpustate[`CPUFLOADCOMPLETE] <= 1'b1;
					end else begin
						cpustate[`CPULOADCOMPLETE] <= 1'b1;
					end
				end
			end

			cpustate[`CPUFLOADCOMPLETE]: begin
				// DWORD
				fdata <= cpudatain;
				floatregisterwriteenable <= 1'b1; // We can now write back
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end

			cpustate[`CPULOADCOMPLETE]: begin
				// Read complete, handle register write-back
				unique case (Wfunc3)
					3'b000: begin // BYTE with sign extension
						unique case (memaddress[1:0])
							2'b11: begin rdata <= {{24{cpudatain[31]}}, cpudatain[31:24]}; end
							2'b10: begin rdata <= {{24{cpudatain[23]}}, cpudatain[23:16]}; end
							2'b01: begin rdata <= {{24{cpudatain[15]}}, cpudatain[15:8]}; end
							2'b00: begin rdata <= {{24{cpudatain[7]}}, cpudatain[7:0]}; end
						endcase
					end
					3'b001: begin // WORD with sign extension
						unique case (memaddress[1])
							1'b1: begin rdata <= {{16{cpudatain[31]}}, cpudatain[31:16]}; end
							1'b0: begin rdata <= {{16{cpudatain[15]}}, cpudatain[15:0]}; end
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
				memaddress <= targetaddress;
				cpuwriteena <= 4'b1111;
				cpudataout <= storedata;
				cpustate[`CPUSTORECOMPLETE] <= 1'b1;
			end

			cpustate[`CPUSTORE]: begin
				// Request write of current register data to memory
				// with appropriate write mask and data size
				memaddress <= targetaddress;
				unique case (Wfunc3)
					3'b000: begin // BYTE
						cpudataout <= {storedata[7:0], storedata[7:0], storedata[7:0], storedata[7:0]};
						unique case (targetaddress[1:0])
							2'b11: begin cpuwriteena <= 4'b1000; end
							2'b10: begin cpuwriteena <= 4'b0100; end
							2'b01: begin cpuwriteena <= 4'b0010; end
							2'b00: begin cpuwriteena <= 4'b0001; end
						endcase
					end
					3'b001: begin // WORD
						cpudataout <= {storedata[15:0], storedata[15:0]};
						unique case (targetaddress[1])
							1'b1: begin cpuwriteena <= 4'b1100; end
							1'b0: begin cpuwriteena <= 4'b0011; end
						endcase
					end
					default: begin // DWORD
						cpudataout <= storedata;
						cpuwriteena <= 4'b1111;
					end
				endcase
				cpustate[`CPUSTORECOMPLETE] <= 1'b1;
			end
			
			cpustate[`CPUSTORECOMPLETE]: begin
				if (busstall) begin
					cpustate[`CPUSTORECOMPLETE] <= 1'b1;
				end else begin
					cpuwriteena <= 4'b0000;
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

				// About mcause register:
				// If high bit is set, it's an interrupt, otherwise it's an exception (such as illegal instruction)
				// Interrupt handlers are asynchronous (return via MRET)
				// Exception handlers are synchronous
				
				// Interrupts (hig bit set) 
				// User software interrupt: 0
				// Supervisor software interrupt: 1
				// Machine software interrupt: 3
				// User timer interrupt: 4
				// Supervisor timer interrupt: 5
				// Machine timer interrupt:7 
				// User external interrupt: 8
				// Supervisor external interrupt: 9
				// Machine external interrupts: 11
				// >=16: implementation specific

				// Exceptions (high bit zero)
				// Instruction address misaligned: 0
				// Instruction access fault: 1
				// Illegal instruction: 2
				// Breakpoint: 3
				// Load address misaligned: 4
				// Load access fault: 5
				// Store/AMO address misaligned: 6
				// Store/AMO access fault: 7
				// Env call from U-mode: 8
				// Env call from S-mode: 9
				// Env call from M-mode: 11
				// Instruction page fault: 12
				// Load page fault: 13
				// Store/AMI page fault: 15
				// >=16: reserved
				
				// Priority during multiple exceptions:
				// instruction address breakpoint
				// instruction page fault
				// instruction access fault
				// illegal instruction
				// instruction address misaligned
				// ecall (8,9,11)
				// ebreak (3)
				// ...

				// For handling vectored interrupts (CSRmtvec lowest 2 bits == 01):
				// nextPC <= {CSRmtvec[31:2],2'b00} + 4*cause
				// For handling non-vectored interrupts (CSRmtvec lowest 2 bits == 00):
				// nextPC <= {CSRmtvec[31:2],2'b00}
				// (Other bit combinations (10,11) are reserved for lowest 2 bits)

				// Default, assume no exceptions/interrupts
				PC <= nextPC;
				memaddress <= nextPC;
				// Turn on reads to fetch the next instruction
				cpureadena <= 1'b1;

				// If interrupts are enabled (MIE)
				if (CSRmstatus[3]) begin

					if ((CSRmie[2] & illegalinstruction) | (CSRmie[3] & ebreak) | CSRmie[7] & (CSRTime >= CSRTimeCmp) | (CSRmie[11] & IRQ)) begin
						CSRmstatus[7] <= CSRmstatus[3]; // Remember interrupt enable status in pending state (MPIE = MIE)
						CSRmstatus[3] <= 1'b0; // Clear interrupts during handler
						CSRmtval <= 32'd0; // Store interrupt/exception specific data (default=0)
						CSRmepc <= nextPC; // Remember where to return
						PC <= {CSRmtvec[31:2],2'b0}; // Jump to handler
						memaddress <= {CSRmtvec[31:2],2'b0};
					end

					if (CSRmie[2] & illegalinstruction) begin // EXCEPTION:ILLEGALINSTRUCTION
						CSRmip[2] <= 1'b1; // Set illegal instruction exception pending
						CSRmcause <= {1'b0, 31'd2}; // No extra cause, just illegal instruction exception (high bit clear)
						CSRmtval <= PC; // Store the address of the instruction with the exception
					end else if (CSRmie[3] & ebreak) begin // INTERRUPT:EBREAK
						CSRmip[3] <= 1'b1; // Set machine interrupt pending for interrupt case
						CSRmcause <= {1'b1, 31'd3}; // No extra cause, just a breakpoint interrupt
						// Special case; ebreak returns to same PC as breakpoint
						CSRmepc <= PC;
					end	else if (CSRmie[7] & (CSRTime >= CSRTimeCmp)) begin // INTERRUPT:MTIMER
						// Time interrupt stays pending until cleared
						CSRmip[7] <= 1'b1; // Set pending timer interrupt status
						CSRmcause[15:0] <= 32'd7; // Timer Interrupt
						CSRmcause[31:16] <= {1'b1, 15'd0}; // Type of timer interrupt is set to zero
					end else if (CSRmie[11] & IRQ) begin // INTERRUPT:MEXTERNAL
						// External interrupt of type IRQ_TYPE from buttons/switches/UART and other peripherals
						CSRmip[11] <= 1'b1; // Set pending machine interrupt status
						CSRmcause[15:0] <= 32'd11; // Machine External Interrupt
						CSRmcause[31:16] <= {1'b1, 13'd0, IRQ_TYPE}; // Mask generated for devices causing interrupt
					end
				end

				cpustate[`CPUFETCH] <= 1'b1;
			end
		endcase
	end
end

endmodule
