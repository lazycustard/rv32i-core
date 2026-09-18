//==========================================================================
// tb_ras.v - Self-checking testbench for ras.v and call_ret_hint
//==========================================================================

`default_nettype none
`timescale 1ns/1ps

module tb_ras;

    localparam integer DEPTH = 4;   // small, so overflow is easy to reach

    reg         clk, rst;
    reg         push, pop;
    reg  [31:0] push_addr;
    wire [31:0] top;
    wire        valid;

    reg  [31:0] instr;
    wire        is_call, is_ret;

    integer checks;
    integer errors;

    ras #(.DEPTH(DEPTH)) dut (
        .clk_i       (clk),
        .rst_i       (rst),
        .push_i      (push),
        .push_addr_i (push_addr),
        .pop_i       (pop),
        .top_o       (top),
        .valid_o     (valid)
    );

    call_ret_hint u_hint (
        .instr_i   (instr),
        .is_call_o (is_call),
        .is_ret_o  (is_ret)
    );

    always #5 clk = ~clk;

    task chk;
        input [8*32-1:0] label;
        input [31:0]     got;
        input [31:0]     expected;
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("  FAIL  %0s -> got %h, expected %h",
                         label, got, expected);
            end
        end
    endtask

    task do_push;
        input [31:0] addr;
        begin
            @(negedge clk);
            push = 1'b1; pop = 1'b0; push_addr = addr;
            @(posedge clk); #1;
            push = 1'b0;
        end
    endtask

    task do_pop;
        begin
            @(negedge clk);
            push = 1'b0; pop = 1'b1;
            @(posedge clk); #1;
            pop = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0; rst = 1'b1;
        push = 1'b0; pop = 1'b0; push_addr = 32'b0;
        instr = 32'b0;
        checks = 0; errors = 0;

        $dumpfile("sim/tb_ras.vcd");
        $dumpvars(0, tb_ras);

        $display("=== tb_ras ===");

        @(posedge clk); @(posedge clk); #1;
        rst = 1'b0;

        //------------------------------------------------------------------
        // Empty stack has nothing to predict with.
        //------------------------------------------------------------------
        chk("empty: not valid", {31'b0, valid}, 32'd0);

        //------------------------------------------------------------------
        // Nesting. Calls and returns nest, which is the whole reason a
        // stack is the right shape: the last address pushed is the first
        // one needed back.
        //------------------------------------------------------------------
        do_push(32'h0000_1000);
        chk("one entry valid",  {31'b0, valid}, 32'd1);
        chk("top is first addr", top, 32'h0000_1000);

        do_push(32'h0000_2000);
        chk("top is second addr", top, 32'h0000_2000);

        do_push(32'h0000_3000);
        chk("top is third addr",  top, 32'h0000_3000);

        do_pop();
        chk("pop returns to 2nd",  top, 32'h0000_2000);
        do_pop();
        chk("pop returns to 1st",  top, 32'h0000_1000);
        do_pop();
        chk("empty again",  {31'b0, valid}, 32'd0);

        //------------------------------------------------------------------
        // Popping an empty stack must not underflow into nonsense.
        //------------------------------------------------------------------
        do_pop();
        chk("pop on empty stays empty", {31'b0, valid}, 32'd0);

        //------------------------------------------------------------------
        // Deeper recursion than the stack holds. The oldest entry is
        // overwritten; the recent ones -- the only ones a predictor is
        // likely to need soon -- stay correct.
        //------------------------------------------------------------------
        do_push(32'h0000_00A0);
        do_push(32'h0000_00B0);
        do_push(32'h0000_00C0);
        do_push(32'h0000_00D0);
        do_push(32'h0000_00E0);     // one past DEPTH = 4
        chk("newest survives overflow", top, 32'h0000_00E0);
        do_pop();
        chk("previous still correct",   top, 32'h0000_00D0);

        //------------------------------------------------------------------
        // Push and pop together replaces the top instead of moving.
        //------------------------------------------------------------------
        @(negedge clk);
        push = 1'b1; pop = 1'b1; push_addr = 32'h0000_9999;
        @(posedge clk); #1;
        push = 1'b0; pop = 1'b0;
        chk("push+pop replaces top", top, 32'h0000_9999);

        //------------------------------------------------------------------
        // Reset empties it.
        //------------------------------------------------------------------
        @(negedge clk); rst = 1'b1; @(posedge clk); #1; rst = 1'b0;
        chk("reset empties", {31'b0, valid}, 32'd0);

        //------------------------------------------------------------------
        // The call/return hints. RV32I has no dedicated call or return
        // instruction -- both are JAL or JALR, and which registers they
        // touch is the only difference.
        //------------------------------------------------------------------
        instr = 32'h0000_00EF; #1;      // jal x1, 0        -> call
        chk("jal ra: call",  {31'b0, is_call}, 32'd1);
        chk("jal ra: not ret", {31'b0, is_ret}, 32'd0);

        instr = 32'h0000_006F; #1;      // jal x0, 0        -> plain jump
        chk("jal x0: not call", {31'b0, is_call}, 32'd0);
        chk("jal x0: not ret",  {31'b0, is_ret},  32'd0);

        instr = 32'h0000_80E7; #1;      // jalr x1, 0(x1)   -> call
        chk("jalr ra,ra: call", {31'b0, is_call}, 32'd1);

        instr = 32'h0000_8067; #1;      // jalr x0, 0(x1)   -> return
        chk("jalr x0,(ra): ret",   {31'b0, is_ret},  32'd1);
        chk("jalr x0,(ra): no call",{31'b0, is_call}, 32'd0);

        instr = 32'h0002_8067; #1;      // jalr x0, 0(x5)   -> return (alt link)
        chk("x5 is a link reg too", {31'b0, is_ret}, 32'd1);

        instr = 32'h0001_0067; #1;      // jalr x0, 0(x2)   -> plain indirect
        chk("jalr x0,(x2): not ret", {31'b0, is_ret}, 32'd0);

        instr = 32'h0000_0013; #1;      // nop
        chk("nop: neither", {30'b0, is_call, is_ret}, 32'd0);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
