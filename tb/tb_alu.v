//==========================================================================
// tb_alu.v - Self-checking testbench for alu.v
//
// Every check states the expected value up front. Nothing here requires a
// human to read a waveform: the last line is either
//   RESULT: PASS
// or
//   RESULT: FAIL
// and scripts/run_tests.sh keys off exactly that.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_alu;

    reg  [31:0]          a, b;
    reg  [`ALU_OP_W-1:0] op;
    wire [31:0]          result;

    integer checks;
    integer errors;

    alu dut (
        .a_i      (a),
        .b_i      (b),
        .op_i     (op),
        .result_o (result)
    );

    // Drive one operation and compare against the expected result.
    task run;
        input [8*20-1:0]        label;
        input [`ALU_OP_W-1:0]   opcode;
        input [31:0]            in_a;
        input [31:0]            in_b;
        input [31:0]            expected;
        begin
            a  = in_a;
            b  = in_b;
            op = opcode;
            #1;
            checks = checks + 1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("  FAIL  %0s  a=%h b=%h -> got %h, expected %h",
                         label, in_a, in_b, result, expected);
            end
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;

        $dumpfile("sim/tb_alu.vcd");
        $dumpvars(0, tb_alu);

        $display("=== tb_alu ===");

        // ---- ADD / SUB, including wraparound ----
        run("add",          `ALU_ADD,  32'd7,        32'd5,        32'd12);
        run("add negative", `ALU_ADD,  32'd10,       -32'd3,       32'd7);
        run("add wraps",    `ALU_ADD,  32'hFFFF_FFFF,32'd1,        32'd0);
        run("sub",          `ALU_SUB,  32'd20,       32'd8,        32'd12);
        run("sub to neg",   `ALU_SUB,  32'd5,        32'd9,        -32'd4);
        run("sub to zero",  `ALU_SUB,  32'd42,       32'd42,       32'd0);

        // ---- Shifts. Only b[4:0] may be used as the shift amount. ----
        run("sll by 1",     `ALU_SLL,  32'h0000_0001,32'd1,        32'h0000_0002);
        run("sll by 31",    `ALU_SLL,  32'h0000_0001,32'd31,       32'h8000_0000);
        run("sll by 0",     `ALU_SLL,  32'hDEAD_BEEF,32'd0,        32'hDEAD_BEEF);
        run("sll masks amt",`ALU_SLL,  32'h0000_0001,32'd33,       32'h0000_0002);

        run("srl",          `ALU_SRL,  32'h0000_0010,32'd4,        32'h0000_0001);
        run("srl zero fill",`ALU_SRL,  32'h8000_0000,32'd31,       32'h0000_0001);
        run("srl by 4",     `ALU_SRL,  32'hF000_0000,32'd4,        32'h0F00_0000);

        run("sra pos",      `ALU_SRA,  32'h0000_0010,32'd4,        32'h0000_0001);
        run("sra sign fill",`ALU_SRA,  32'h8000_0000,32'd31,       32'hFFFF_FFFF);
        run("sra by 4",     `ALU_SRA,  32'hF000_0000,32'd4,        32'hFF00_0000);
        run("sra of -8",    `ALU_SRA,  -32'd8,       32'd1,        -32'd4);

        // ---- Bitwise. OR and AND must be distinct operations. ----
        run("and",          `ALU_AND,  32'hFF00_FF00,32'h0F0F_0F0F,32'h0F00_0F00);
        run("and zero",     `ALU_AND,  32'hFFFF_FFFF,32'h0000_0000,32'h0000_0000);
        run("or",           `ALU_OR,   32'hFF00_FF00,32'h0F0F_0F0F,32'hFF0F_FF0F);
        run("or identity",  `ALU_OR,   32'hDEAD_BEEF,32'h0000_0000,32'hDEAD_BEEF);
        run("xor",          `ALU_XOR,  32'hFF00_FF00,32'h0F0F_0F0F,32'hF00F_F00F);
        run("xor self",     `ALU_XOR,  32'hDEAD_BEEF,32'hDEAD_BEEF,32'h0000_0000);

        // ---- SLT vs SLTU. Same bits, different answers: this is the whole
        //      reason both instructions exist. ----
        run("slt  1 < 2",   `ALU_SLT,  32'd1,        32'd2,        32'd1);
        run("slt  2 < 1",   `ALU_SLT,  32'd2,        32'd1,        32'd0);
        run("slt  eq",      `ALU_SLT,  32'd7,        32'd7,        32'd0);
        run("slt -1 < 1",   `ALU_SLT,  -32'd1,       32'd1,        32'd1);
        run("sltu -1 < 1",  `ALU_SLTU, -32'd1,       32'd1,        32'd0);
        run("sltu 1 < -1",  `ALU_SLTU, 32'd1,        -32'd1,       32'd1);

        // ---- LUI path ----
        run("pass b",       `ALU_PASS_B, 32'hDEAD_BEEF, 32'h1234_5000, 32'h1234_5000);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
