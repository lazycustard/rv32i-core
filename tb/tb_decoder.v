//==========================================================================
// tb_decoder.v - Self-checking testbench for decoder.v
//
// Every stimulus is a real hand-encoded RV32I instruction word. The checks
// assert the control bundle the datapath will actually consume, so a wrong
// mux select shows up here rather than as a mysterious wrong answer three
// pipeline stages later.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_decoder;

    reg  [31:0]             instr;

    wire [4:0]              rs1_addr, rs2_addr, rd_addr;
    wire [2:0]              funct3;
    wire                    reg_write;
    wire [`ALU_OP_W-1:0]    alu_op;
    wire                    alu_src_a, alu_src_b;
    wire [`IMM_SEL_W-1:0]   imm_sel;
    wire [`WB_SEL_W-1:0]    wb_sel;
    wire                    mem_read, mem_write;
    wire                    is_branch, is_jump, target_src;
    wire                    is_ecall, is_ebreak, illegal;

    integer checks;
    integer errors;

    decoder dut (
        .instr_i      (instr),
        .rs1_addr_o   (rs1_addr),
        .rs2_addr_o   (rs2_addr),
        .rd_addr_o    (rd_addr),
        .funct3_o     (funct3),
        .reg_write_o  (reg_write),
        .alu_op_o     (alu_op),
        .alu_src_a_o  (alu_src_a),
        .alu_src_b_o  (alu_src_b),
        .imm_sel_o    (imm_sel),
        .wb_sel_o     (wb_sel),
        .mem_read_o   (mem_read),
        .mem_write_o  (mem_write),
        .is_branch_o  (is_branch),
        .is_jump_o    (is_jump),
        .target_src_o (target_src),
        .is_ecall_o   (is_ecall),
        .is_ebreak_o  (is_ebreak),
        .illegal_o    (illegal)
    );

    task feed;
        input [31:0] word;
        begin
            instr = word;
            #1;
        end
    endtask

    task chk;
        input [8*30-1:0] label;
        input [31:0]     got;
        input [31:0]     expected;
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("  FAIL  %0s  instr=%h -> got %h, expected %h",
                         label, instr, got, expected);
            end
        end
    endtask

    // An illegal instruction must be flagged AND must have no architectural
    // effect: no register write, no memory access, no control transfer.
    // Flagging alone is not enough -- a decoder that raises illegal_o while
    // still asserting reg_write will quietly corrupt a register.
    task chk_illegal;
        input [8*20-1:0] label;
        input [31:0]     word;
        begin
            feed(word);
            chk({label, " flagged"},   illegal,    32'd1);
            chk({label, " no write"},  reg_write,  32'd0);
            chk({label, " no mem"},    {mem_read, mem_write}, 32'd0);
            chk({label, " no branch"}, is_branch,  32'd0);
            chk({label, " no jump"},   is_jump,    32'd0);
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;

        $dumpfile("sim/tb_decoder.vcd");
        $dumpvars(0, tb_decoder);

        $display("=== tb_decoder ===");

        //------------------------------------------------------------------
        // R-type
        //------------------------------------------------------------------
        feed(32'h0031_00B3);                        // add x1, x2, x3
        chk("add: rd",         rd_addr,   32'd1);
        chk("add: rs1",        rs1_addr,  32'd2);
        chk("add: rs2",        rs2_addr,  32'd3);
        chk("add: reg_write",  reg_write, 32'd1);
        chk("add: alu_op",     alu_op,    `ALU_ADD);
        chk("add: src_a",      alu_src_a, `SRC_A_RS1);
        chk("add: src_b",      alu_src_b, `SRC_B_RS2);
        chk("add: wb_sel",     wb_sel,    `WB_ALU);
        chk("add: no mem",     {mem_read, mem_write}, 32'd0);
        chk("add: legal",      illegal,   32'd0);

        feed(32'h4031_00B3);                        // sub x1, x2, x3
        chk("sub: alu_op",     alu_op,    `ALU_SUB);
        chk("sub: legal",      illegal,   32'd0);

        feed(32'h0073_62B3);                        // or x5, x6, x7
        chk("or: alu_op",      alu_op,    `ALU_OR);
        chk("or: rd",          rd_addr,   32'd5);
        chk("or: legal",       illegal,   32'd0);

        feed(32'h0031_50B3);                        // srl x1, x2, x3
        chk("srl: alu_op",     alu_op,    `ALU_SRL);
        feed(32'h4031_50B3);                        // sra x1, x2, x3
        chk("sra: alu_op",     alu_op,    `ALU_SRA);

        //------------------------------------------------------------------
        // I-type ALU.
        //
        // The critical case: "addi x1, x2, -1" has immediate 0xFFF, so
        // instr[30] is 1. If the decoder blindly used bit 30 as the ALU
        // alternate bit, this would decode as SUB.
        //------------------------------------------------------------------
        feed(32'hFFF1_0093);                        // addi x1, x2, -1
        chk("addi -1: alu_op ADD", alu_op,    `ALU_ADD);
        chk("addi -1: src_b imm",  alu_src_b, `SRC_B_IMM);
        chk("addi -1: imm_sel I",  imm_sel,   `IMM_I);
        chk("addi -1: reg_write",  reg_write, 32'd1);
        chk("addi -1: legal",      illegal,   32'd0);

        feed(32'h0031_5093);                        // srli x1, x2, 3
        chk("srli: alu_op",    alu_op,    `ALU_SRL);
        chk("srli: legal",     illegal,   32'd0);

        feed(32'h4031_5093);                        // srai x1, x2, 3
        chk("srai: alu_op",    alu_op,    `ALU_SRA);
        chk("srai: legal",     illegal,   32'd0);

        feed(32'h0000_0013);                        // nop = addi x0, x0, 0
        chk("nop: rd is x0",   rd_addr,   32'd0);
        chk("nop: legal",      illegal,   32'd0);

        //------------------------------------------------------------------
        // Loads
        //------------------------------------------------------------------
        feed(32'h0081_2083);                        // lw x1, 8(x2)
        chk("lw: reg_write",   reg_write, 32'd1);
        chk("lw: mem_read",    mem_read,  32'd1);
        chk("lw: mem_write",   mem_write, 32'd0);
        chk("lw: alu_op ADD",  alu_op,    `ALU_ADD);
        chk("lw: src_b imm",   alu_src_b, `SRC_B_IMM);
        chk("lw: imm_sel I",   imm_sel,   `IMM_I);
        chk("lw: wb_sel MEM",  wb_sel,    `WB_MEM);
        chk("lw: funct3",      funct3,    `LS_W);
        chk("lw: legal",       illegal,   32'd0);

        feed(32'h0001_4083);                        // lbu x1, 0(x2)
        chk("lbu: funct3",     funct3,    `LS_BU);
        chk("lbu: legal",      illegal,   32'd0);

        //------------------------------------------------------------------
        // Stores
        //------------------------------------------------------------------
        feed(32'h0055_2423);                        // sw x5, 8(x10)
        chk("sw: no reg_write", reg_write, 32'd0);
        chk("sw: mem_write",    mem_write, 32'd1);
        chk("sw: mem_read",     mem_read,  32'd0);
        chk("sw: imm_sel S",    imm_sel,   `IMM_S);
        chk("sw: alu_op ADD",   alu_op,    `ALU_ADD);
        chk("sw: rs2 is data",  rs2_addr,  32'd5);
        chk("sw: legal",        illegal,   32'd0);

        feed(32'h0055_0023);                        // sb x5, 0(x10)
        chk("sb: funct3",       funct3,    `LS_B);
        chk("sb: legal",        illegal,   32'd0);

        //------------------------------------------------------------------
        // Branches
        //------------------------------------------------------------------
        feed(32'h0020_8863);                        // beq x1, x2, +16
        chk("beq: is_branch",   is_branch, 32'd1);
        chk("beq: no reg_write",reg_write, 32'd0);
        chk("beq: imm_sel B",   imm_sel,   `IMM_B);
        chk("beq: target PC",   target_src,`TGT_PC);
        chk("beq: not jump",    is_jump,   32'd0);
        chk("beq: funct3",      funct3,    `BR_EQ);
        chk("beq: legal",       illegal,   32'd0);

        feed(32'h0020_E863);                        // bltu x1, x2, +16
        chk("bltu: is_branch",  is_branch, 32'd1);
        chk("bltu: funct3",     funct3,    `BR_LTU);
        chk("bltu: legal",      illegal,   32'd0);

        //------------------------------------------------------------------
        // Jumps
        //------------------------------------------------------------------
        feed(32'h0010_00EF);                        // jal x1, +2048
        chk("jal: is_jump",     is_jump,   32'd1);
        chk("jal: reg_write",   reg_write, 32'd1);
        chk("jal: wb_sel PC4",  wb_sel,    `WB_PC4);
        chk("jal: imm_sel J",   imm_sel,   `IMM_J);
        chk("jal: target PC",   target_src,`TGT_PC);
        chk("jal: legal",       illegal,   32'd0);

        feed(32'h0001_00E7);                        // jalr x1, 0(x2)
        chk("jalr: is_jump",    is_jump,   32'd1);
        chk("jalr: reg_write",  reg_write, 32'd1);
        chk("jalr: wb_sel PC4", wb_sel,    `WB_PC4);
        chk("jalr: imm_sel I",  imm_sel,   `IMM_I);
        chk("jalr: target RS1", target_src,`TGT_RS1);
        chk("jalr: rs1",        rs1_addr,  32'd2);
        chk("jalr: legal",      illegal,   32'd0);

        //------------------------------------------------------------------
        // Upper immediate
        //------------------------------------------------------------------
        feed(32'h1234_50B7);                        // lui x1, 0x12345
        chk("lui: reg_write",   reg_write, 32'd1);
        chk("lui: alu PASS_B",  alu_op,    `ALU_PASS_B);
        chk("lui: src_b imm",   alu_src_b, `SRC_B_IMM);
        chk("lui: imm_sel U",   imm_sel,   `IMM_U);
        chk("lui: wb_sel ALU",  wb_sel,    `WB_ALU);
        chk("lui: legal",       illegal,   32'd0);

        feed(32'h0000_1097);                        // auipc x1, 0x1
        chk("auipc: src_a PC",  alu_src_a, `SRC_A_PC);
        chk("auipc: src_b imm", alu_src_b, `SRC_B_IMM);
        chk("auipc: alu ADD",   alu_op,    `ALU_ADD);
        chk("auipc: imm_sel U", imm_sel,   `IMM_U);
        chk("auipc: wb_sel ALU",wb_sel,    `WB_ALU);
        chk("auipc: legal",     illegal,   32'd0);

        //------------------------------------------------------------------
        // System and fence
        //------------------------------------------------------------------
        feed(32'h0000_0073);                        // ecall
        chk("ecall: flagged",   is_ecall,  32'd1);
        chk("ecall: no write",  reg_write, 32'd0);
        chk("ecall: legal",     illegal,   32'd0);

        feed(32'h0010_0073);                        // ebreak
        chk("ebreak: flagged",  is_ebreak, 32'd1);
        chk("ebreak: legal",    illegal,   32'd0);

        feed(32'h0000_000F);                        // fence
        chk("fence: no write",  reg_write, 32'd0);
        chk("fence: no mem",    {mem_read, mem_write}, 32'd0);
        chk("fence: legal",     illegal,   32'd0);

        //------------------------------------------------------------------
        // Illegal encodings. Each must raise illegal_o and, just as
        // importantly, must not write a register or touch memory.
        //------------------------------------------------------------------
        chk_illegal("bad opcode",    32'hFFFF_FFFF);  // opcode 1111111
        chk_illegal("mul (M ext)",   32'h0231_00B3);  // funct7 = 0000001
        chk_illegal("add bad f7",    32'h0231_00B3);
        chk_illegal("jalr f3=001",   32'h0001_10E7);
        chk_illegal("branch f3=010",32'h0020_A863);
        chk_illegal("branch f3=011",32'h0020_B863);
        chk_illegal("load f3=011",   32'h0001_3083);
        chk_illegal("load f3=111",   32'h0001_7083);
        chk_illegal("store f3=011",  32'h0055_3023);
        chk_illegal("slli bad f7",   32'h4031_1093);
        chk_illegal("xor bad f7",    32'h4031_40B3);
        chk_illegal("system junk",   32'h0020_0073);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
