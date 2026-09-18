//==========================================================================
// lsu.v - Load/store alignment
//
// Memory is organised as 32-bit words, but RV32I can load and store bytes
// and halfwords. This module sits between the pipeline and the data memory
// and does the lane work in both directions:
//
//   STORE  place the low byte/halfword of rs2 into the correct lane of the
//          word, and produce a per-byte write enable so the other lanes are
//          left untouched.
//
//   LOAD   extract the addressed byte/halfword out of the word that came
//          back, then sign-extend it (lb, lh) or zero-extend it (lbu, lhu).
//
// Sign versus zero extension is the entire reason lb and lbu are separate
// instructions. Ignoring funct3 and always moving 32 bits -- which is what
// a word-only implementation does -- gets both of them wrong.
//
// RV32I also requires naturally aligned accesses: a halfword at an odd
// address, or a word not on a 4-byte boundary, is an address-misaligned
// exception. That is reported here, and the write enables are forced low so
// a misaligned store cannot corrupt memory while the trap is being taken.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module lsu (
    input  wire [2:0]  funct3_i,
    input  wire [1:0]  addr_lsb_i,     // low two bits of the byte address
    input  wire        is_load_i,
    input  wire        is_store_i,

    // Store path
    input  wire [31:0] store_data_i,   // raw rs2 value
    output reg  [3:0]  byte_en_o,      // one bit per byte lane
    output wire [31:0] store_word_o,   // rs2 replicated across the lanes

    // Load path
    input  wire [31:0] load_word_i,    // raw word read from memory
    output reg  [31:0] load_data_o,

    output wire        misaligned_o
);

    //----------------------------------------------------------------------
    // Alignment check. A byte access is always aligned.
    //----------------------------------------------------------------------
    reg misaligned;

    always @(*) begin
        case (funct3_i)
            `LS_H, `LS_HU : misaligned = (addr_lsb_i[0] != 1'b0);
            `LS_W         : misaligned = (addr_lsb_i    != 2'b00);
            default       : misaligned = 1'b0;   // LS_B, LS_BU
        endcase
    end

    assign misaligned_o = (is_load_i || is_store_i) && misaligned;

    //----------------------------------------------------------------------
    // Store path.
    //
    // The data is replicated across all four lanes rather than shifted into
    // position. The byte enables already select the destination lane, so
    // replication costs nothing and avoids a barrel shifter.
    //----------------------------------------------------------------------
    reg [31:0] store_word;

    always @(*) begin
        case (funct3_i)
            `LS_B   : store_word = {4{store_data_i[7:0]}};
            `LS_H   : store_word = {2{store_data_i[15:0]}};
            default : store_word = store_data_i;          // LS_W
        endcase
    end

    assign store_word_o = store_word;

    always @(*) begin
        if (!is_store_i || misaligned) begin
            byte_en_o = 4'b0000;
        end else begin
            case (funct3_i)
                `LS_B : begin
                    case (addr_lsb_i)
                        2'b00 : byte_en_o = 4'b0001;
                        2'b01 : byte_en_o = 4'b0010;
                        2'b10 : byte_en_o = 4'b0100;
                        2'b11 : byte_en_o = 4'b1000;
                    endcase
                end
                `LS_H : byte_en_o = addr_lsb_i[1] ? 4'b1100 : 4'b0011;
                `LS_W : byte_en_o = 4'b1111;
                default: byte_en_o = 4'b0000;
            endcase
        end
    end

    //----------------------------------------------------------------------
    // Load path: select the lane, then extend.
    //----------------------------------------------------------------------
    reg [7:0]  sel_byte;
    reg [15:0] sel_half;

    always @(*) begin
        case (addr_lsb_i)
            2'b00 : sel_byte = load_word_i[7:0];
            2'b01 : sel_byte = load_word_i[15:8];
            2'b10 : sel_byte = load_word_i[23:16];
            2'b11 : sel_byte = load_word_i[31:24];
        endcase
    end

    always @(*) begin
        sel_half = addr_lsb_i[1] ? load_word_i[31:16] : load_word_i[15:0];
    end

    always @(*) begin
        case (funct3_i)
            `LS_B   : load_data_o = {{24{sel_byte[7]}},  sel_byte};
            `LS_BU  : load_data_o = {24'b0,              sel_byte};
            `LS_H   : load_data_o = {{16{sel_half[15]}}, sel_half};
            `LS_HU  : load_data_o = {16'b0,              sel_half};
            `LS_W   : load_data_o = load_word_i;
            default : load_data_o = 32'b0;
        endcase
    end

endmodule

`default_nettype wire
