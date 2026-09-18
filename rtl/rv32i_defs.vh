//==========================================================================
// rv32i_defs.vh - Shared constants for the RV32I core
//==========================================================================

`ifndef RV32I_DEFS_VH
`define RV32I_DEFS_VH

//--------------------------------------------------------------------------
// ALU operation encoding
//
// The encoding is deliberately chosen as {alt, funct3} so that the decoder
// for R-type and I-type ALU instructions is almost free:
//
//     alu_op = { instr[30] , instr[14:12] }
//
// instr[30] is the "alternate operation" bit in funct7 that distinguishes
// ADD from SUB and SRL from SRA. Everything else comes straight from funct3.
//
// This is why the width is 4 bits and not 3. RV32I has ten distinct ALU
// operations (add sub sll slt sltu xor srl sra or and); three bits can only
// encode eight, which forces encodings to collide.
//--------------------------------------------------------------------------
`define ALU_OP_W 4

`define ALU_ADD    4'b0000   // funct3 000, alt 0
`define ALU_SLL    4'b0001   // funct3 001
`define ALU_SLT    4'b0010   // funct3 010  signed set-less-than
`define ALU_SLTU   4'b0011   // funct3 011  unsigned set-less-than
`define ALU_XOR    4'b0100   // funct3 100
`define ALU_SRL    4'b0101   // funct3 101, alt 0
`define ALU_OR     4'b0110   // funct3 110
`define ALU_AND    4'b0111   // funct3 111
`define ALU_SUB    4'b1000   // funct3 000, alt 1
`define ALU_SRA    4'b1101   // funct3 101, alt 1

// Pass operand B straight through. Used by LUI, which needs the immediate
// in the register file untouched rather than added to anything.
`define ALU_PASS_B 4'b1001

//--------------------------------------------------------------------------
// Opcodes (instr[6:0]). RV32I only defines these eleven.
//--------------------------------------------------------------------------
`define OP_LOAD     7'b0000011
`define OP_MISC_MEM 7'b0001111   // fence
`define OP_IMM      7'b0010011   // addi, slti, andi, slli, ...
`define OP_AUIPC    7'b0010111
`define OP_STORE    7'b0100011
`define OP_REG      7'b0110011   // add, sub, sll, ...
`define OP_LUI      7'b0110111
`define OP_BRANCH   7'b1100011
`define OP_JALR     7'b1100111
`define OP_JAL      7'b1101111
`define OP_SYSTEM   7'b1110011   // ecall, ebreak

//--------------------------------------------------------------------------
// Immediate formats. RV32I scrambles the immediate bits differently in each
// instruction format, so the selector needs five values -- which does not
// fit in the 2-bit field a subset implementation can get away with.
//--------------------------------------------------------------------------
`define IMM_SEL_W 3

`define IMM_I 3'd0   // instr[31:20]                       sign-extended
`define IMM_S 3'd1   // instr[31:25] | instr[11:7]         sign-extended
`define IMM_B 3'd2   // 13-bit, bit 0 always 0             sign-extended
`define IMM_U 3'd3   // instr[31:12] << 12                 no extension
`define IMM_J 3'd4   // 21-bit, bit 0 always 0             sign-extended

//--------------------------------------------------------------------------
// Branch conditions (funct3 of a BRANCH instruction)
//--------------------------------------------------------------------------
`define BR_EQ  3'b000
`define BR_NE  3'b001
`define BR_LT  3'b100   // signed
`define BR_GE  3'b101   // signed
`define BR_LTU 3'b110   // unsigned
`define BR_GEU 3'b111   // unsigned

//--------------------------------------------------------------------------
// Load / store width (funct3 of a LOAD or STORE instruction)
//--------------------------------------------------------------------------
`define LS_B  3'b000   // byte,     sign-extended on load
`define LS_H  3'b001   // halfword, sign-extended on load
`define LS_W  3'b010   // word
`define LS_BU 3'b100   // byte,     zero-extended on load
`define LS_HU 3'b101   // halfword, zero-extended on load

//--------------------------------------------------------------------------
// A canonical NOP: addi x0, x0, 0. Used to fill flushed pipeline slots.
//--------------------------------------------------------------------------
`define NOP 32'h0000_0013

//--------------------------------------------------------------------------
// Datapath control encodings
//--------------------------------------------------------------------------

// ALU operand A
`define SRC_A_RS1 1'b0
`define SRC_A_PC  1'b1   // AUIPC computes PC + imm

// ALU operand B
`define SRC_B_RS2 1'b0
`define SRC_B_IMM 1'b1

// What gets written back to rd
`define WB_SEL_W 2
`define WB_ALU 2'd0
`define WB_MEM 2'd1   // loads
`define WB_PC4 2'd2   // JAL and JALR save the return address

// Where a taken branch or jump gets its base address
`define TGT_PC  1'b0   // branches and JAL: PC + imm
`define TGT_RS1 1'b1   // JALR: rs1 + imm, with bit 0 cleared

`endif
