//==========================================================================
// rv32i_asm.vh - A tiny assembler, as Verilog functions
//
// Include this in a testbench and write test programs as readable calls:
//
//     prog[0] = rv_addi(1, 0, 10);      // addi x1, x0, 10
//     prog[1] = rv_add (3, 1, 2);       // add  x3, x1, x2
//     prog[2] = rv_beq (1, 2, 8);       // beq  x1, x2, +8
//
// rather than as hand-encoded hex. Hand encoding a branch immediate means
// scattering thirteen bits across four fields in the right order, by hand,
// every time -- and a test whose stimulus is wrong in the same way as the
// design under test proves nothing.
//
// Immediates are byte offsets exactly as written in assembly: rv_beq(..., 8)
// jumps eight bytes forward, and the encoder discards the implied zero bit.
//==========================================================================

`ifndef RV32I_ASM_VH
`define RV32I_ASM_VH

//--------------------------------------------------------------------------
// Format encoders
//--------------------------------------------------------------------------

function [31:0] rv_r;
    input [6:0] funct7;
    input [2:0] funct3;
    input [4:0] rd, rs1, rs2;
    begin
        rv_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
    end
endfunction

function [31:0] rv_i;
    input [6:0]  opcode;
    input [2:0]  funct3;
    input [4:0]  rd, rs1;
    input [11:0] imm;
    begin
        rv_i = {imm, rs1, funct3, rd, opcode};
    end
endfunction

function [31:0] rv_s;
    input [2:0]  funct3;
    input [4:0]  rs1, rs2;
    input [11:0] imm;
    begin
        rv_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
    end
endfunction

function [31:0] rv_b;
    input [2:0]  funct3;
    input [4:0]  rs1, rs2;
    input [12:0] imm;               // byte offset; bit 0 is discarded
    begin
        rv_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                imm[4:1], imm[11], 7'b1100011};
    end
endfunction

function [31:0] rv_u;
    input [6:0]  opcode;
    input [4:0]  rd;
    input [19:0] imm20;             // the UPPER 20 bits of the result
    begin
        rv_u = {imm20, rd, opcode};
    end
endfunction

function [31:0] rv_j;
    input [4:0]  rd;
    input [20:0] imm;               // byte offset; bit 0 is discarded
    begin
        rv_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    end
endfunction

//--------------------------------------------------------------------------
// Register-register
//--------------------------------------------------------------------------
function [31:0] rv_add;  input [4:0] rd, rs1, rs2;
    begin rv_add  = rv_r(7'b0000000, 3'b000, rd, rs1, rs2); end endfunction
function [31:0] rv_sub;  input [4:0] rd, rs1, rs2;
    begin rv_sub  = rv_r(7'b0100000, 3'b000, rd, rs1, rs2); end endfunction
function [31:0] rv_sll;  input [4:0] rd, rs1, rs2;
    begin rv_sll  = rv_r(7'b0000000, 3'b001, rd, rs1, rs2); end endfunction
function [31:0] rv_slt;  input [4:0] rd, rs1, rs2;
    begin rv_slt  = rv_r(7'b0000000, 3'b010, rd, rs1, rs2); end endfunction
function [31:0] rv_sltu; input [4:0] rd, rs1, rs2;
    begin rv_sltu = rv_r(7'b0000000, 3'b011, rd, rs1, rs2); end endfunction
function [31:0] rv_xor;  input [4:0] rd, rs1, rs2;
    begin rv_xor  = rv_r(7'b0000000, 3'b100, rd, rs1, rs2); end endfunction
function [31:0] rv_srl;  input [4:0] rd, rs1, rs2;
    begin rv_srl  = rv_r(7'b0000000, 3'b101, rd, rs1, rs2); end endfunction
function [31:0] rv_sra;  input [4:0] rd, rs1, rs2;
    begin rv_sra  = rv_r(7'b0100000, 3'b101, rd, rs1, rs2); end endfunction
function [31:0] rv_or;   input [4:0] rd, rs1, rs2;
    begin rv_or   = rv_r(7'b0000000, 3'b110, rd, rs1, rs2); end endfunction
function [31:0] rv_and;  input [4:0] rd, rs1, rs2;
    begin rv_and  = rv_r(7'b0000000, 3'b111, rd, rs1, rs2); end endfunction

//--------------------------------------------------------------------------
// Register-immediate
//--------------------------------------------------------------------------
function [31:0] rv_addi;  input [4:0] rd, rs1; input [11:0] imm;
    begin rv_addi  = rv_i(7'b0010011, 3'b000, rd, rs1, imm); end endfunction
function [31:0] rv_slti;  input [4:0] rd, rs1; input [11:0] imm;
    begin rv_slti  = rv_i(7'b0010011, 3'b010, rd, rs1, imm); end endfunction
function [31:0] rv_sltiu; input [4:0] rd, rs1; input [11:0] imm;
    begin rv_sltiu = rv_i(7'b0010011, 3'b011, rd, rs1, imm); end endfunction
function [31:0] rv_xori;  input [4:0] rd, rs1; input [11:0] imm;
    begin rv_xori  = rv_i(7'b0010011, 3'b100, rd, rs1, imm); end endfunction
function [31:0] rv_ori;   input [4:0] rd, rs1; input [11:0] imm;
    begin rv_ori   = rv_i(7'b0010011, 3'b110, rd, rs1, imm); end endfunction
function [31:0] rv_andi;  input [4:0] rd, rs1; input [11:0] imm;
    begin rv_andi  = rv_i(7'b0010011, 3'b111, rd, rs1, imm); end endfunction

function [31:0] rv_slli;  input [4:0] rd, rs1; input [4:0] shamt;
    begin rv_slli = rv_i(7'b0010011, 3'b001, rd, rs1, {7'b0000000, shamt}); end
endfunction
function [31:0] rv_srli;  input [4:0] rd, rs1; input [4:0] shamt;
    begin rv_srli = rv_i(7'b0010011, 3'b101, rd, rs1, {7'b0000000, shamt}); end
endfunction
function [31:0] rv_srai;  input [4:0] rd, rs1; input [4:0] shamt;
    begin rv_srai = rv_i(7'b0010011, 3'b101, rd, rs1, {7'b0100000, shamt}); end
endfunction

//--------------------------------------------------------------------------
// Loads and stores
//--------------------------------------------------------------------------
function [31:0] rv_lb;  input [4:0] rd, rs1; input [11:0] imm;
    begin rv_lb  = rv_i(7'b0000011, 3'b000, rd, rs1, imm); end endfunction
function [31:0] rv_lh;  input [4:0] rd, rs1; input [11:0] imm;
    begin rv_lh  = rv_i(7'b0000011, 3'b001, rd, rs1, imm); end endfunction
function [31:0] rv_lw;  input [4:0] rd, rs1; input [11:0] imm;
    begin rv_lw  = rv_i(7'b0000011, 3'b010, rd, rs1, imm); end endfunction
function [31:0] rv_lbu; input [4:0] rd, rs1; input [11:0] imm;
    begin rv_lbu = rv_i(7'b0000011, 3'b100, rd, rs1, imm); end endfunction
function [31:0] rv_lhu; input [4:0] rd, rs1; input [11:0] imm;
    begin rv_lhu = rv_i(7'b0000011, 3'b101, rd, rs1, imm); end endfunction

function [31:0] rv_sb; input [4:0] rs2, rs1; input [11:0] imm;
    begin rv_sb = rv_s(3'b000, rs1, rs2, imm); end endfunction
function [31:0] rv_sh; input [4:0] rs2, rs1; input [11:0] imm;
    begin rv_sh = rv_s(3'b001, rs1, rs2, imm); end endfunction
function [31:0] rv_sw; input [4:0] rs2, rs1; input [11:0] imm;
    begin rv_sw = rv_s(3'b010, rs1, rs2, imm); end endfunction

//--------------------------------------------------------------------------
// Branches
//--------------------------------------------------------------------------
function [31:0] rv_beq;  input [4:0] rs1, rs2; input [12:0] imm;
    begin rv_beq  = rv_b(3'b000, rs1, rs2, imm); end endfunction
function [31:0] rv_bne;  input [4:0] rs1, rs2; input [12:0] imm;
    begin rv_bne  = rv_b(3'b001, rs1, rs2, imm); end endfunction
function [31:0] rv_blt;  input [4:0] rs1, rs2; input [12:0] imm;
    begin rv_blt  = rv_b(3'b100, rs1, rs2, imm); end endfunction
function [31:0] rv_bge;  input [4:0] rs1, rs2; input [12:0] imm;
    begin rv_bge  = rv_b(3'b101, rs1, rs2, imm); end endfunction
function [31:0] rv_bltu; input [4:0] rs1, rs2; input [12:0] imm;
    begin rv_bltu = rv_b(3'b110, rs1, rs2, imm); end endfunction
function [31:0] rv_bgeu; input [4:0] rs1, rs2; input [12:0] imm;
    begin rv_bgeu = rv_b(3'b111, rs1, rs2, imm); end endfunction

//--------------------------------------------------------------------------
// Jumps and upper immediates
//--------------------------------------------------------------------------
function [31:0] rv_jal;  input [4:0] rd; input [20:0] imm;
    begin rv_jal  = rv_j(rd, imm); end endfunction
function [31:0] rv_jalr; input [4:0] rd, rs1; input [11:0] imm;
    begin rv_jalr = rv_i(7'b1100111, 3'b000, rd, rs1, imm); end endfunction

function [31:0] rv_lui;   input [4:0] rd; input [19:0] imm20;
    begin rv_lui   = rv_u(7'b0110111, rd, imm20); end endfunction
function [31:0] rv_auipc; input [4:0] rd; input [19:0] imm20;
    begin rv_auipc = rv_u(7'b0010111, rd, imm20); end endfunction

//--------------------------------------------------------------------------
// System
//--------------------------------------------------------------------------
function [31:0] rv_ecall;  input dummy;
    begin rv_ecall  = 32'h0000_0073; end endfunction
function [31:0] rv_ebreak; input dummy;
    begin rv_ebreak = 32'h0010_0073; end endfunction
function [31:0] rv_nop;    input dummy;
    begin rv_nop    = 32'h0000_0013; end endfunction

`endif
