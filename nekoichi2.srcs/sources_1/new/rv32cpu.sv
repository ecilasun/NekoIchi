`timescale 1ns / 1ps

`include "cpuops.vh"

module rv32cpu(
	input wire reset,
	input wire clock,
	input wire wallclock,
	input wire gpufifofull,
	output logic[31:0] gpufifocommand,
	output logic gpufifowe,
	output logic uartfifowe,
	output logic [7:0] uartoutdata,
	input wire uartfifovalid,
	output logic uartfifore,
	input wire [7:0] uartindata,
	input wire [9:0] uartinputbytecount,
	output logic[31:0] memaddress = 32'h80000000,
	output logic [31:0] writeword = 32'h00000000,
	input wire [31:0] mem_data,
	output logic [3:0] mem_writeena = 4'b0000 );

// =====================================================================================================
// CPU Internal State & Instruction Decomposition
// =====================================================================================================

logic [31:0] PC;
logic [31:0] nextPC;
logic [`CPUSTAGECOUNT-1:0] cpustate;
wire [`CPUSTAGECOUNT-1:0] nextstage;

// Floating point control register
logic [31:0] fcsr;

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

logic [63:0] CSRCycle = 64'd0;
logic [63:0] CSRTime = 64'd0;
logic [63:0] CSRReti = 64'd0;

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
		registerdata <= 32'd0;
		fregisterWriteEnable <= 1'b0;
		fregisterdata <= 32'd0;
		fcsr <= 32'd0; // [7:5] == 000 -> RNE (round to nearest even), [4:0] -> NotValid|DivbyZero|OverFlow|UnderFlow|iNeXact (exceptions), ignored for now
		gpufifocommand <= 32'd0;
		gpufifowe <= 1'b0;
		uartfifowe <= 1'b0;
		uartfifore <= 1'b0;

	end else begin

		cpustate <= `CPUNONE_MASK;
		
		// cpu state uses one-hot encoding
		unique case (1'b1)

			cpustate[`CPUFETCH]: begin
				// Instruction read takes place here, to be latched at the start of next state
				cpustate[`CPUDECODE] <= 1'b1;
			end

			cpustate[`CPUDECODE]: begin
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
						// Only implements timer CSR reads for now
						if (func3 == 3'b010) begin // CSRRS
							case ({func7,rs2}) // csr index
								12'hC00: begin registerdata <= CSRCycle[31:0]; end
								12'hC01: begin registerdata <= CSRTime[31:0]; end
								12'hC02: begin registerdata <= CSRReti[31:0]; end
								12'hC80: begin registerdata <= CSRCycle[63:32]; end
								12'hC81: begin registerdata <= CSRTime[63:32]; end
								12'hC82: begin registerdata <= CSRReti[63:32]; end
							endcase
						end
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
				if (opcode == `OPCODE_FLOAT_LDW) begin
					cpustate[`CPULOADFCOMPLETE] <= 1'b1;
				end else begin
					cpustate[`CPULOADCOMPLETE] <= 1'b1;
				end
			end

			cpustate[`CPULOADCOMPLETE]: begin
				if (memaddress[31:28] == 4'b0101) begin // 0x50000000 UART Rx read
					uartfifore <= 1'b1;
					cpustate[`CPULOADUARTCOMPLETE] <= 1'b1;
				end else if (memaddress[31:28] == 4'b0110) begin // 0x60000000 UART pending received byte count
					registerdata <= {22'd0, uartinputbytecount};
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
				end else begin
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
			end
			
			cpustate[`CPULOADUARTCOMPLETE]: begin
				if (uartfifovalid) begin
					uartfifore <= 1'b0;
					registerdata <= {24'd0, uartindata};
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
				end else begin
					cpustate[`CPULOADUARTCOMPLETE] <= 1'b1;
				end
			end

			cpustate[`CPULOADFCOMPLETE]: begin
				// Already aligned on read, regular DWORD read
				fregisterdata <= mem_data[31:0];
				cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
			end

			cpustate[`CPUSTORE]: begin
				if (memaddress[31:28] == 4'b1000) begin // 0x80000000 GPU command queue, VRAM write command (4'b0001)
					if (gpufifofull) begin
						// Stall writes until GPU processes more data
						cpustate[`CPUSTORE] <= 1'b1;
					end else begin
						// GPU commands are always 32 bits, no byte writes possible to this address range
						gpufifocommand <= registerdata;
						gpufifowe <= 1'b1;
						cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
					end
				end else if (memaddress[31:28] == 4'b0100) begin // 0x40000000 UART Tx write
					uartoutdata <= registerdata[7:0];
					uartfifowe <= 1'b1;
					cpustate[`CPURETIREINSTRUCTION] <= 1'b1;
				end else begin
					unique case (func3)
						// Byte
						3'b000: begin
							unique case (memaddress[1:0])
								2'b11: begin mem_writeena <= 4'b1000; writeword <= {registerdata[7:0], 24'd0}; end
								2'b10: begin mem_writeena <= 4'b0100; writeword <= {8'd0, registerdata[7:0], 16'd0}; end
								2'b01: begin mem_writeena <= 4'b0010; writeword <= {16'd0, registerdata[7:0], 8'd0}; end
								2'b00: begin mem_writeena <= 4'b0001; writeword <= {24'd0, registerdata[7:0]}; end
							endcase
						end
						// Word
						3'b001: begin
							unique case (memaddress[1])
								1'b1: begin mem_writeena <= 4'b1100; writeword <= {registerdata[15:0], 16'd0}; end
								1'b0: begin mem_writeena <= 4'b0011; writeword <= {16'd0, registerdata[15:0]}; end
							endcase
						end
						// Dword
						default: begin
							mem_writeena <= 4'b1111;
							writeword <= registerdata;
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
				// Stop GPU/UART fifo writes
				gpufifowe <= 1'b0;
				uartfifowe <= 1'b0;
				// Stop register writes
				registerWriteEnable <= 1'b0;
				fregisterWriteEnable <= 1'b0;
				// Stop memory writes
				mem_writeena <= 4'b0000;
				// Set next PC
				PC <= {nextPC[31:1],1'b0}; // Truncate to 16bit aligned addresses to align to instructions
				// Also reflect to the memaddress so we end up reading next instruction
				memaddress <= {nextPC[31:1], 1'b0};
				// Update retired instruction CRS
				CSRReti <= CSRReti + 64'd1;
				// Loop back to fetch (actually fetch wait) state
				cpustate[`CPUFETCH] <= 1'b1;
			end

		endcase

	end
end
	
endmodule
