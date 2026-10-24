//==========================================================================
// tb_core.v - Self-checking testbench for the whole pipeline
//
// Each test is a real RV32I program. It is loaded into instruction memory,
// run until it executes ECALL, and then the architectural state -- the
// register file -- is compared against what the program should have
// produced. Nothing here inspects internal pipeline signals: if forwarding,
// stalling or flushing is wrong, the final register values are wrong, which
// is exactly the property that matters.
//
// Every program also asserts that no illegal instruction was executed, so a
// decoding mistake cannot pass by accident.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_core;

    // Included inside the module so the assembler helpers are module-local
    // functions rather than compilation-unit items.
    `include "rv32i_asm.vh"

    localparam integer MEM_WORDS  = 256;
    localparam integer MAX_CYCLES = 300;

    reg         clk;
    reg         rst;
    wire [31:0] dbg_pc;
    wire        dbg_ecall;
    wire        dbg_illegal;

    integer checks;
    integer errors;
    integer cycles;
    integer i;

    reg saw_illegal;

    rv32i_soc #(
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

    // Latch any illegal instruction seen while a program runs.
    always @(posedge clk) begin
        if (!rst && dbg_illegal) begin
            saw_illegal <= 1'b1;
        end
    end

    //----------------------------------------------------------------------
    // Program assembly buffer
    //----------------------------------------------------------------------
    reg [31:0] prog [0:MEM_WORDS-1];
    integer    prog_len;

    task start_prog;
        begin
            prog_len = 0;
        end
    endtask

    task p;                         // append one instruction
        input [31:0] instr;
        begin
            prog[prog_len] = instr;
            prog_len       = prog_len + 1;
        end
    endtask

    //----------------------------------------------------------------------
    // Load the assembled program and run it to completion
    //----------------------------------------------------------------------
    reg [8*28-1:0] prog_name;

    task run_prog;
        input [8*28-1:0] name;
        begin
            prog_name = name;

            for (i = 0; i < MEM_WORDS; i = i + 1) begin
                dut.u_imem.mem[i] = `NOP;
                dut.u_dmem.mem[i] = 32'b0;
            end
            for (i = 0; i < prog_len; i = i + 1) begin
                dut.u_imem.mem[i] = prog[i];
            end
            for (i = 0; i < 32; i = i + 1) begin
                dut.u_core.u_reg_file.regs[i] = 32'b0;
            end

            saw_illegal = 1'b0;
            rst = 1'b1;
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

            checks = checks + 1;
            if (cycles >= MAX_CYCLES) begin
                errors = errors + 1;
                $display("  FAIL  %0s: never reached ecall (%0d cycles)",
                         name, MAX_CYCLES);
            end

            checks = checks + 1;
            if (saw_illegal) begin
                errors = errors + 1;
                $display("  FAIL  %0s: executed an illegal instruction", name);
            end
        end
    endtask

    // Compare one architectural register against its expected value.
    task chk_reg;
        input [4:0]  regnum;
        input [31:0] expected;
        begin
            checks = checks + 1;
            if (dut.u_core.u_reg_file.regs[regnum] !== expected) begin
                errors = errors + 1;
                $display("  FAIL  %0s: x%0d = %h, expected %h",
                         prog_name, regnum,
                         dut.u_core.u_reg_file.regs[regnum], expected);
            end
        end
    endtask

    initial begin
        clk    = 1'b0;
        rst    = 1'b1;
        checks = 0;
        errors = 0;

        $dumpfile("sim/tb_core.vcd");
        $dumpvars(0, tb_core);

        $display("=== tb_core ===");

        //==================================================================
        // 1. Back-to-back dependencies.
        //
        // Every instruction here needs a value the previous one has not
        // written back yet. Without forwarding, all of them read stale
        // zeros and every result is wrong.
        //==================================================================
        start_prog();
        p(rv_addi(1, 0, 10));           // x1 = 10
        p(rv_addi(2, 0, 20));           // x2 = 20
        p(rv_add (3, 1, 2));            // x3 = 30   x2 from MEM, x1 from WB
        p(rv_sub (4, 3, 1));            // x4 = 20   x3 from MEM
        p(rv_add (5, 4, 4));            // x5 = 40   x4 forwarded to both
        p(rv_ecall(0));
        run_prog("forwarding chain");
        chk_reg(1, 32'd10);
        chk_reg(2, 32'd20);
        chk_reg(3, 32'd30);
        chk_reg(4, 32'd20);
        chk_reg(5, 32'd40);

        //==================================================================
        // 2. Every ALU operation, through the real datapath
        //==================================================================
        start_prog();
        p(rv_addi(1, 0, -8));           // x1 = 0xFFFFFFF8
        p(rv_addi(2, 0, 3));            // x2 = 3
        p(rv_and (3, 1, 2));            // 0
        p(rv_or  (4, 1, 2));            // 0xFFFFFFFB
        p(rv_xor (5, 1, 2));            // 0xFFFFFFFB
        p(rv_sll (6, 2, 2));            // 3 << 3 = 24
        p(rv_srl (7, 1, 2));            // 0x1FFFFFFF
        p(rv_sra (8, 1, 2));            // -1
        p(rv_slt (9, 1, 2));            // signed:   -8 < 3  -> 1
        p(rv_sltu(10, 1, 2));           // unsigned: huge < 3 -> 0
        p(rv_ecall(0));
        run_prog("all ALU ops");
        chk_reg(3,  32'h0000_0000);
        chk_reg(4,  32'hFFFF_FFFB);
        chk_reg(5,  32'hFFFF_FFFB);
        chk_reg(6,  32'd24);
        chk_reg(7,  32'h1FFF_FFFF);
        chk_reg(8,  32'hFFFF_FFFF);
        chk_reg(9,  32'd1);
        chk_reg(10, 32'd0);

        //==================================================================
        // 3. Immediate shifts. srli and srai share a funct3 and differ only
        //    in instr[30], the same bit that must NOT reach the ALU for
        //    addi -- so these two confirm the gating works in both
        //    directions.
        //==================================================================
        start_prog();
        p(rv_addi(1, 0, -16));          // 0xFFFFFFF0
        p(rv_srli(2, 1, 4));            // 0x0FFFFFFF
        p(rv_srai(3, 1, 4));            // 0xFFFFFFFF
        p(rv_slli(4, 1, 4));            // 0xFFFFFF00
        p(rv_addi(5, 0, -1));           // bit 30 of the immediate is 1
        p(rv_ecall(0));
        run_prog("immediate shifts");
        chk_reg(2, 32'h0FFF_FFFF);
        chk_reg(3, 32'hFFFF_FFFF);
        chk_reg(4, 32'hFFFF_FF00);
        chk_reg(5, 32'hFFFF_FFFF);      // still an add, not a sub

        //==================================================================
        // 4. Load-use hazard. The addi needs the loaded value one cycle
        //    before memory can produce it, so the pipeline must stall.
        //==================================================================
        start_prog();
        p(rv_addi(2, 0, 85));           // x2 = 85
        p(rv_sw  (2, 0, 0));            // mem[0] = 85
        p(rv_lw  (3, 0, 0));            // x3 = 85
        p(rv_addi(4, 3, 1));            // x4 = 86   <- load-use stall here
        p(rv_ecall(0));
        run_prog("load-use stall");
        chk_reg(3, 32'd85);
        chk_reg(4, 32'd86);

        //==================================================================
        // 5. Byte and halfword memory, and sign vs zero extension
        //==================================================================
        start_prog();
        p(rv_addi(1, 0, 127));          // 0x7F
        p(rv_addi(2, 0, -1));           // 0xFFFFFFFF
        p(rv_sb  (1, 0, 4));            // byte 4 = 0x7F
        p(rv_sb  (2, 0, 5));            // byte 5 = 0xFF
        p(rv_lb  (3, 0, 4));            // x3 =  127
        p(rv_lb  (4, 0, 5));            // x4 =   -1   sign extended
        p(rv_lbu (5, 0, 5));            // x5 =  255   zero extended
        p(rv_lw  (6, 0, 4));            // x6 = 0x0000FF7F
        p(rv_sh  (2, 0, 10));           // halfword at 10 = 0xFFFF
        p(rv_lh  (7, 0, 10));           // x7 =   -1
        p(rv_lhu (8, 0, 10));           // x8 = 65535
        p(rv_ecall(0));
        run_prog("byte and halfword");
        chk_reg(3, 32'd127);
        chk_reg(4, 32'hFFFF_FFFF);
        chk_reg(5, 32'd255);
        chk_reg(6, 32'h0000_FF7F);
        chk_reg(7, 32'hFFFF_FFFF);
        chk_reg(8, 32'd65535);

        //==================================================================
        // 6. Branches. A taken branch must flush the two instructions
        //    already fetched behind it -- if the flush fails, the skipped
        //    instruction writes 99 and the check catches it.
        //==================================================================
        start_prog();
        p(rv_addi(1, 0, 5));            // 0
        p(rv_addi(2, 0, 5));            // 4
        p(rv_beq (1, 2, 12));           // 8  -> taken, skip two
        p(rv_addi(3, 0, 99));           // 12 must not execute
        p(rv_addi(3, 0, 98));           // 16 must not execute
        p(rv_addi(4, 0, 1));            // 20
        p(rv_bne (1, 2, 8));            // 24 -> not taken
        p(rv_addi(5, 0, 2));            // 28 executes
        p(rv_addi(6, 0, 3));            // 32
        p(rv_ecall(0));
        run_prog("branch taken/not");
        chk_reg(3, 32'd0);              // both skipped instructions flushed
        chk_reg(4, 32'd1);
        chk_reg(5, 32'd2);
        chk_reg(6, 32'd3);

        //==================================================================
        // 7. Signed versus unsigned branches on the same two values.
        //    blt takes, bltu does not. A core that decides branches from a
        //    zero flag cannot tell these apart.
        //==================================================================
        start_prog();
        p(rv_addi(1, 0, -1));           // 0xFFFFFFFF
        p(rv_addi(2, 0, 1));
        p(rv_blt (1, 2, 8));            // signed: -1 < 1  -> taken
        p(rv_addi(3, 0, 99));           // skipped
        p(rv_bltu(1, 2, 8));            // unsigned: huge < 1 -> not taken
        p(rv_addi(4, 0, 7));            // executes
        p(rv_bge (2, 1, 8));            // signed: 1 >= -1 -> taken
        p(rv_addi(5, 0, 99));           // skipped
        p(rv_bgeu(1, 2, 8));            // unsigned: huge >= 1 -> taken
        p(rv_addi(6, 0, 99));           // skipped
        p(rv_addi(7, 0, 4));
        p(rv_ecall(0));
        run_prog("signed vs unsigned br");
        chk_reg(3, 32'd0);
        chk_reg(4, 32'd7);
        chk_reg(5, 32'd0);
        chk_reg(6, 32'd0);
        chk_reg(7, 32'd4);

        //==================================================================
        // 8. A function call and return. This is the one thing a core
        //    without JALR can never do.
        //==================================================================
        start_prog();
        p(rv_jal (1, 12));              //  0  call byte 12, x1 = 4
        p(rv_addi(3, 0, 7));            //  4  runs after the return
        p(rv_ecall(0));                 //  8
        p(rv_addi(2, 0, 42));           // 12  the callee
        p(rv_jalr(0, 1, 0));            // 16  return to x1
        run_prog("call and return");
        chk_reg(1, 32'd4);              // link register holds the return PC
        chk_reg(2, 32'd42);             // callee ran
        chk_reg(3, 32'd7);              // and we came back

        //==================================================================
        // 9. Upper immediates. LUI must not sign-extend a 12-bit field,
        //    and AUIPC must add to the PC rather than to rs1.
        //==================================================================
        start_prog();
        p(rv_lui  (1, 20'h12345));      //  0  x1 = 0x12345000
        p(rv_addi (2, 1, 12'h678));     //  4  x2 = 0x12345678
        p(rv_auipc(3, 20'h00000));      //  8  x3 = 8
        p(rv_auipc(4, 20'h00001));      // 12  x4 = 0x100C
        p(rv_ecall(0));
        run_prog("lui and auipc");
        chk_reg(1, 32'h1234_5000);
        chk_reg(2, 32'h1234_5678);
        chk_reg(3, 32'h0000_0008);
        chk_reg(4, 32'h0000_100C);

        //==================================================================
        // 10. A real loop: sum 1..10 . Exercises a backward branch, a
        //     dependency chain through the accumulator, and a counter.
        //==================================================================
        start_prog();
        p(rv_addi(1, 0, 0));            //  0  sum   = 0
        p(rv_addi(2, 0, 1));            //  4  i     = 1
        p(rv_addi(3, 0, 11));           //  8  limit = 11
        p(rv_add (1, 1, 2));            // 12  sum += i
        p(rv_addi(2, 2, 1));            // 16  i++
        p(rv_bne (2, 3, -8));           // 20  loop back to byte 12
        p(rv_ecall(0));                 // 24
        run_prog("loop: sum 1..10");
        chk_reg(1, 32'd55);
        chk_reg(2, 32'd11);

        //==================================================================
        // 11. x0 stays zero no matter what is written to it.
        //==================================================================
        start_prog();
        p(rv_addi(0, 0, 99));           // discarded
        p(rv_lui (0, 20'hFFFFF));       // discarded
        p(rv_addi(1, 0, 5));
        p(rv_add (0, 1, 1));            // discarded
        p(rv_add (2, 0, 0));            // x2 = 0 + 0
        p(rv_ecall(0));
        run_prog("x0 stays zero");
        chk_reg(0, 32'd0);
        chk_reg(2, 32'd0);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
