//==========================================================================
// tb_branch_unit.v - Self-checking testbench for branch_unit.v
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_branch_unit;

    reg  [31:0] a, b;
    reg  [2:0]  funct3;
    reg         is_branch;
    wire        take;

    integer checks;
    integer errors;

    branch_unit dut (
        .rs1_data_i    (a),
        .rs2_data_i    (b),
        .funct3_i      (funct3),
        .is_branch_i   (is_branch),
        .take_branch_o (take)
    );

    task run;
        input [8*24-1:0] label;
        input [2:0]      f3;
        input [31:0]     in_a;
        input [31:0]     in_b;
        input            expected;
        begin
            a         = in_a;
            b         = in_b;
            funct3    = f3;
            is_branch = 1'b1;
            #1;
            checks = checks + 1;
            if (take !== expected) begin
                errors = errors + 1;
                $display("  FAIL  %0s  a=%h b=%h -> got %b, expected %b",
                         label, in_a, in_b, take, expected);
            end
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;

        $dumpfile("sim/tb_branch_unit.vcd");
        $dumpvars(0, tb_branch_unit);

        $display("=== tb_branch_unit ===");

        // ---- BEQ / BNE ----
        run("beq equal",      `BR_EQ,  32'd7,  32'd7,  1'b1);
        run("beq not equal",  `BR_EQ,  32'd7,  32'd8,  1'b0);
        run("beq zeros",      `BR_EQ,  32'd0,  32'd0,  1'b1);
        run("bne equal",      `BR_NE,  32'd7,  32'd7,  1'b0);
        run("bne not equal",  `BR_NE,  32'd7,  32'd8,  1'b1);

        // ---- BLT / BGE, signed ----
        run("blt 1<2",        `BR_LT,  32'd1,  32'd2,  1'b1);
        run("blt 2<1",        `BR_LT,  32'd2,  32'd1,  1'b0);
        run("blt equal",      `BR_LT,  32'd5,  32'd5,  1'b0);
        run("blt -1 < 1",     `BR_LT,  -32'd1, 32'd1,  1'b1);
        run("blt -5 < -2",    `BR_LT,  -32'd5, -32'd2, 1'b1);
        run("bge 2>=1",       `BR_GE,  32'd2,  32'd1,  1'b1);
        run("bge equal",      `BR_GE,  32'd5,  32'd5,  1'b1);
        run("bge 1>=2",       `BR_GE,  32'd1,  32'd2,  1'b0);
        run("bge 1 >= -1",    `BR_GE,  32'd1,  -32'd1, 1'b1);

        // ---- BLTU / BGEU, unsigned. Same bits as the signed cases above,
        //      opposite answers. This is the distinction a zero flag cannot
        //      express. ----
        run("bltu 1<2",       `BR_LTU, 32'd1,  32'd2,  1'b1);
        run("bltu -1 < 1",    `BR_LTU, -32'd1, 32'd1,  1'b0);
        run("bltu 1 < -1",    `BR_LTU, 32'd1,  -32'd1, 1'b1);
        run("bltu equal",     `BR_LTU, 32'd9,  32'd9,  1'b0);
        run("bgeu -1 >= 1",   `BR_GEU, -32'd1, 32'd1,  1'b1);
        run("bgeu 1 >= -1",   `BR_GEU, 32'd1,  -32'd1, 1'b0);
        run("bgeu equal",     `BR_GEU, 32'd9,  32'd9,  1'b1);

        // ---- Boundary values ----
        run("blt INT_MIN<0",  `BR_LT,  32'h8000_0000, 32'd0, 1'b1);
        run("bltu INT_MIN<0", `BR_LTU, 32'h8000_0000, 32'd0, 1'b0);
        run("blt 0<INT_MAX",  `BR_LT,  32'd0, 32'h7FFF_FFFF, 1'b1);

        // ---- Undefined funct3 for BRANCH must not take ----
        run("funct3 010 illegal", 3'b010, 32'd1, 32'd1, 1'b0);
        run("funct3 011 illegal", 3'b011, 32'd1, 32'd1, 1'b0);

        // ---- Non-branch instructions must never take, whatever the
        //      operands happen to be ----
        a = 32'd7; b = 32'd7; funct3 = `BR_EQ; is_branch = 1'b0; #1;
        checks = checks + 1;
        if (take !== 1'b0) begin
            errors = errors + 1;
            $display("  FAIL  non-branch took a branch");
        end

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
