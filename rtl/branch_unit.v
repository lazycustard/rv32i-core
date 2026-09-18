//==========================================================================
// branch_unit.v - Branch condition evaluation
//
// RV32I has six conditional branches, and they need three different
// comparisons: equality, signed less-than, and unsigned less-than.
//
// A design that reuses the ALU by computing rs1 - rs2 and testing the zero
// flag can only ever implement BEQ and BNE. There is no flag combination
// that distinguishes BLT from BLTU, because the two differ only in how the
// same 32 bits are interpreted -- 0xFFFFFFFF is less than 1 as a signed
// value and greater than 1 as an unsigned one. Hence a dedicated comparator.
//
// funct3 values 010 and 011 are not defined for BRANCH; they decode as
// "do not take", and the decoder flags them as illegal separately.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module branch_unit (
    input  wire [31:0] rs1_data_i,
    input  wire [31:0] rs2_data_i,
    input  wire [2:0]  funct3_i,
    input  wire        is_branch_i,   // high only for BRANCH opcodes
    output wire        take_branch_o
);

    wire eq    = (rs1_data_i == rs2_data_i);
    wire lt_s  = ($signed(rs1_data_i) < $signed(rs2_data_i));
    wire lt_u  = (rs1_data_i < rs2_data_i);

    reg condition;

    always @(*) begin
        case (funct3_i)
            `BR_EQ  : condition =  eq;
            `BR_NE  : condition = !eq;
            `BR_LT  : condition =  lt_s;
            `BR_GE  : condition = !lt_s;
            `BR_LTU : condition =  lt_u;
            `BR_GEU : condition = !lt_u;
            default : condition = 1'b0;
        endcase
    end

    assign take_branch_o = is_branch_i && condition;

endmodule

`default_nettype wire
