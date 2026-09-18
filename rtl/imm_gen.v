//==========================================================================
// imm_gen.v - Immediate extraction and sign extension
//
// RV32I scatters the immediate bits across the instruction word differently
// in each format. The scattering is not arbitrary: it keeps the sign bit at
// instr[31] and the register fields in fixed places for every format, so the
// register file can be read before the instruction is even decoded.
//
//   I  instr[31:20]                                  sign-extended
//   S  instr[31:25], instr[11:7]                     sign-extended
//   B  instr[31], instr[7], instr[30:25], instr[11:8], 0
//   U  instr[31:12] placed in the upper 20 bits, low 12 bits zero
//   J  instr[31], instr[19:12], instr[20], instr[30:21], 0
//
// B and J encode a byte offset whose lowest bit is always zero (branch and
// jump targets are 2-byte aligned), so that bit is not stored and is
// reinserted here as a constant 0.
//
// U is the one format with no sign extension at all: the 20 bits ARE the
// top 20 bits of the result. Treating LUI/AUIPC as if they carried a 12-bit
// signed I-type immediate is a common and silent bug.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module imm_gen (
    input  wire [31:0]              instr_i,
    input  wire [`IMM_SEL_W-1:0]    sel_i,
    output reg  [31:0]              imm_o
);

    always @(*) begin
        case (sel_i)
            `IMM_I : imm_o = {{20{instr_i[31]}}, instr_i[31:20]};

            `IMM_S : imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};

            `IMM_B : imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                              instr_i[30:25], instr_i[11:8], 1'b0};

            `IMM_U : imm_o = {instr_i[31:12], 12'b0};

            `IMM_J : imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                              instr_i[20], instr_i[30:21], 1'b0};

            default: imm_o = 32'b0;
        endcase
    end

endmodule

`default_nettype wire
