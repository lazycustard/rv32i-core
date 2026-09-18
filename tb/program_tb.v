//==========================================================================
// program_tb.v - Run one compiled program and capture its output
//
// Driven by scripts/run_programs.sh, one invocation per program:
//
//   vvp sim/program.vvp +NAME=hello \
//       +IMEM=tests/build/hello.imem.hex \
//       +DMEM=tests/build/hello.dmem.hex \
//       +OUT=tests/build/hello.out
//
// UART bytes are written to the +OUT file rather than mixed into stdout,
// so the runner can diff the program's output against an expected file
// without having to parse simulator chatter out of it first.
//
// Deliberately not named tb_*.v: the normal runner globs tb/tb_*.v and
// this testbench needs a program supplied through plusargs.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module program_tb;

    localparam integer MEM_WORDS  = 16384;      // 64 KiB each
    localparam integer MAX_CYCLES = 2000000;

    reg         clk;
    reg         rst;
    wire        uart_valid;
    wire [7:0]  uart_data;
    wire [31:0] dbg_pc;
    wire        dbg_ecall;
    wire        dbg_illegal;

    integer cycles;
    integer chars;
    integer i;
    integer out_fd;
    reg     saw_illegal;

    reg [1023:0] imem_file;
    reg [1023:0] dmem_file;
    reg [1023:0] out_file;
    reg [1023:0] test_name;

    rv32i_core #(
        .IMEM_WORDS (MEM_WORDS),
        .DMEM_WORDS (MEM_WORDS)
    ) dut (
        .clk_i         (clk),
        .rst_i         (rst),
        .uart_valid_o  (uart_valid),
        .uart_data_o   (uart_data),
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

    // Collect transmitted characters. One byte per cycle that the core
    // asserts uart_valid.
    always @(posedge clk) begin
        if (!rst && uart_valid) begin
            $fwrite(out_fd, "%c", uart_data);
            $write("%c", uart_data);
            chars <= chars + 1;
        end
    end

    initial begin
        clk         = 1'b0;
        rst         = 1'b1;
        chars       = 0;
        saw_illegal = 1'b0;

        if (!$value$plusargs("NAME=%s", test_name)) test_name = "program";

        if (!$value$plusargs("IMEM=%s", imem_file)) begin
            $display("RESULT: FAIL  (no +IMEM= given)");
            $finish;
        end
        if (!$value$plusargs("OUT=%s", out_file)) begin
            $display("RESULT: FAIL  (no +OUT= given)");
            $finish;
        end

        // Binary mode. In text mode on Windows a newline written by the
        // program becomes CRLF in the file, so the captured output would
        // never match an expected file checked in with LF endings -- and
        // the diff would look identical to the eye.
        out_fd = $fopen(out_file, "wb");
        if (out_fd == 0) begin
            $display("RESULT: FAIL  (cannot open output file)");
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

        $fclose(out_fd);
        $display("");

        if (cycles >= MAX_CYCLES) begin
            $display("  %0s: no ecall after %0d cycles (hung or looping)",
                     test_name, MAX_CYCLES);
            $display("RESULT: FAIL");
        end else if (saw_illegal) begin
            $display("  %0s: executed an illegal instruction", test_name);
            $display("RESULT: FAIL");
        end else begin
            // Distinct prefix: the program's own output is echoed to stdout
            // too, and a program that prints "fib:" would otherwise be
            // mistaken for this line by anything grepping for the name.
            $display("STATS: %0d cycles, %0d characters", cycles, chars);
            $display("RESULT: PASS");
        end

        $finish;
    end

endmodule

`default_nettype wire
