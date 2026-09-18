//==========================================================================
// riscv_tests_tb.v - Run one official riscv-tests program
//
// Deliberately NOT named tb_*.v: the normal runner globs tb/tb_*.v, and
// this testbench needs a program supplied through plusargs, so it would
// fail there. scripts/run_riscv_tests.sh drives it, once per test.
//
//   vvp sim/riscv_tests.vvp +NAME=add \
//       +IMEM=tests/build/add.imem.hex +DMEM=tests/build/add.dmem.hex
//
// Result protocol, defined by tests/env/riscv_test.h:
//   a0 == 0  every test case in the program passed
//   a0 != 0  a0 is the number of the test case that failed
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module riscv_tests_tb;

    // 64 KiB each, matching tests/env/link.ld
    localparam integer MEM_WORDS  = 16384;
    localparam integer MAX_CYCLES = 200000;

    reg         clk;
    reg         rst;
    wire [31:0] dbg_pc;
    wire        dbg_ecall;
    wire        dbg_illegal;

    integer cycles;
    integer i;
    reg     saw_illegal;

    reg [1023:0] imem_file;
    reg [1023:0] dmem_file;
    reg [1023:0] test_name;

    rv32i_core #(
        .IMEM_WORDS (MEM_WORDS),
        .DMEM_WORDS (MEM_WORDS)
    ) dut (
        .clk_i         (clk),
        .rst_i         (rst),
        .dbg_pc_o      (dbg_pc),
        .dbg_ecall_o   (dbg_ecall),
        .dbg_illegal_o (dbg_illegal)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst && dbg_illegal) begin
            saw_illegal <= 1'b1;
        end
    end

    // a0 is x10: the register the environment reports the result in.
    wire [31:0] a0 = dut.u_reg_file.regs[10];

    initial begin
        clk         = 1'b0;
        rst         = 1'b1;
        saw_illegal = 1'b0;

        if (!$value$plusargs("NAME=%s", test_name)) begin
            test_name = "unnamed";
        end
        if (!$value$plusargs("IMEM=%s", imem_file)) begin
            $display("RESULT: FAIL  (no +IMEM= given)");
            $finish;
        end

        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            dut.u_imem.mem[i] = `NOP;
            dut.u_dmem.mem[i] = 32'b0;
        end

        $readmemh(imem_file, dut.u_imem.mem);
        if ($value$plusargs("DMEM=%s", dmem_file)) begin
            $readmemh(dmem_file, dut.u_dmem.mem);
        end

        for (i = 0; i < 32; i = i + 1) begin
            dut.u_reg_file.regs[i] = 32'b0;
        end

        @(posedge clk);
        @(posedge clk);
        #1;
        rst = 1'b0;

        cycles = 0;
        while (!dbg_ecall && (cycles < MAX_CYCLES)) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        if (cycles >= MAX_CYCLES) begin
            $display("  %0s: no ecall after %0d cycles (hung or looping)",
                     test_name, MAX_CYCLES);
            $display("RESULT: FAIL");
        end else if (saw_illegal) begin
            $display("  %0s: executed an illegal instruction", test_name);
            $display("RESULT: FAIL");
        end else if (a0 !== 32'b0) begin
            $display("  %0s: test case %0d failed (a0=%0d)",
                     test_name, a0, a0);
            $display("RESULT: FAIL");
        end else begin
            $display("  %0s: %0d cycles", test_name, cycles);
            $display("RESULT: PASS");
        end

        $finish;
    end

endmodule

`default_nettype wire
