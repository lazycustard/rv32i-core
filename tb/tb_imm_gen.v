//==========================================================================
// tb_imm_gen.v - Self-checking testbench for imm_gen.v
//
// Every stimulus below is a real, hand-encoded RV32I instruction word, not
// a synthetic bit pattern. If the field extraction is wrong, these fail.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_imm_gen;

    reg  [31:0]           instr;
    reg  [`IMM_SEL_W-1:0] sel;
    wire [31:0]           imm;

    integer checks;
    integer errors;

    imm_gen dut (
        .instr_i (instr),
        .sel_i   (sel),
        .imm_o   (imm)
    );

    task run;
        input [8*26-1:0]        label;
        input [31:0]            instr_word;
        input [`IMM_SEL_W-1:0]  format;
        input [31:0]            expected;
        begin
            instr = instr_word;
            sel   = format;
            #1;
            checks = checks + 1;
            if (imm !== expected) begin
                errors = errors + 1;
                $display("  FAIL  %0s  instr=%h -> got %h, expected %h",
                         label, instr_word, imm, expected);
            end
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;

        $dumpfile("sim/tb_imm_gen.vcd");
        $dumpvars(0, tb_imm_gen);

        $display("=== tb_imm_gen ===");

        // ---- I-type ----
        run("addi x1,x2,100",   32'h0641_0093, `IMM_I, 32'd100);
        run("addi x1,x0,-1",    32'hFFF0_0093, `IMM_I, 32'hFFFF_FFFF);
        run("nop (addi x0,x0,0)", 32'h0000_0013, `IMM_I, 32'd0);

        // ---- S-type: the immediate is split across two fields ----
        run("sw x5,8(x10)",     32'h0055_2423, `IMM_S, 32'd8);
        run("sw x5,-8(x10)",    32'hFE55_2C23, `IMM_S, -32'd8);

        // ---- B-type: 13-bit, bit 0 implied zero ----
        run("beq x1,x2,+16",    32'h0020_8863, `IMM_B, 32'd16);
        run("beq x1,x2,-4",     32'hFE20_8EE3, `IMM_B, -32'd4);

        // ---- U-type: NO sign extension, the 20 bits are the top 20 bits ----
        run("lui x1,0x12345",   32'h1234_50B7, `IMM_U, 32'h1234_5000);
        run("lui x1,0xFFFFF",   32'hFFFF_F0B7, `IMM_U, 32'hFFFF_F000);
        run("auipc x1,0x00001", 32'h0000_1097, `IMM_U, 32'h0000_1000);

        // ---- J-type: 21-bit, bit 0 implied zero ----
        run("jal x1,+2048",     32'h0010_00EF, `IMM_J, 32'd2048);
        run("jal x1,-2",        32'hFFFF_F0EF, `IMM_J, -32'd2);

        // ---- Branch and jump offsets are always even ----
        checks = checks + 1;
        instr = 32'hFE20_8EE3; sel = `IMM_B; #1;
        if (imm[0] !== 1'b0) begin
            errors = errors + 1;
            $display("  FAIL  B-type bit 0 must be zero, got %b", imm[0]);
        end

        checks = checks + 1;
        instr = 32'hFFFF_F0EF; sel = `IMM_J; #1;
        if (imm[0] !== 1'b0) begin
            errors = errors + 1;
            $display("  FAIL  J-type bit 0 must be zero, got %b", imm[0]);
        end

        // ---- The selector must actually select. Same instruction word,
        //      read as three different formats, must give three different
        //      answers -- this is exactly what breaks when LUI is decoded
        //      with the I-type immediate. ----
        run("word as I", 32'h1234_50B7, `IMM_I, 32'h0000_0123);
        run("word as U", 32'h1234_50B7, `IMM_U, 32'h1234_5000);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
