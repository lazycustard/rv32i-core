//==========================================================================
// alu.v - RV32I arithmetic / logic unit
//
// Purely combinational. Supports all ten RV32I ALU operations plus a
// pass-through used by LUI.
//
// Note: there is no zero flag output. Branch decisions are made by a
// dedicated comparator (branch_unit.v), not by subtracting in the ALU and
// testing for zero. Reusing the ALU that way only ever gets BEQ right --
// BLT and BLTU need signed and unsigned comparisons that a zero flag
// cannot express.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module alu (
    input  wire [31:0]          a_i,
    input  wire [31:0]          b_i,
    input  wire [`ALU_OP_W-1:0] op_i,
    output reg  [31:0]          result_o
);

    // RV32I shifts use only the low 5 bits of the shift operand.
    wire [4:0] shamt = b_i[4:0];

    always @(*) begin
        case (op_i)
            `ALU_ADD    : result_o = a_i + b_i;
            `ALU_SUB    : result_o = a_i - b_i;
            `ALU_SLL    : result_o = a_i << shamt;
            `ALU_SLT    : result_o = {31'b0, ($signed(a_i) <  $signed(b_i))};
            `ALU_SLTU   : result_o = {31'b0, (a_i < b_i)};
            `ALU_XOR    : result_o = a_i ^ b_i;
            `ALU_SRL    : result_o = a_i >> shamt;
            `ALU_SRA    : result_o = $signed(a_i) >>> shamt;
            `ALU_OR     : result_o = a_i | b_i;
            `ALU_AND    : result_o = a_i & b_i;
            `ALU_PASS_B : result_o = b_i;
            default     : result_o = 32'b0;
        endcase
    end

endmodule

`default_nettype wire
