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

`endif
