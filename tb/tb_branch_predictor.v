//==========================================================================
// tb_branch_predictor.v - Self-checking testbench for branch_predictor.v
//==========================================================================

`default_nettype none
`timescale 1ns/1ps

module tb_branch_predictor;

    localparam integer ENTRIES = 64;

    reg         clk, rst;
    reg  [31:0] pc;
    wire        predict_taken;
    wire [31:0] predict_target;
    reg         update_valid, update_taken;
    reg  [31:0] update_pc, update_target;

    integer checks;
    integer errors;

    branch_predictor #(.ENTRIES(ENTRIES)) dut (
        .clk_i            (clk),
        .rst_i            (rst),
        .pc_i             (pc),
        .predict_taken_o  (predict_taken),
        .predict_target_o (predict_target),
        .update_valid_i   (update_valid),
        .update_pc_i      (update_pc),
        .update_taken_i   (update_taken),
        .update_target_i  (update_target)
    );

    always #5 clk = ~clk;

    task chk;
        input [8*36-1:0] label;
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

    // Tell the predictor how one branch resolved.
    task resolve;
        input [31:0] branch_pc;
        input        taken;
        input [31:0] target;
        begin
            @(negedge clk);
            update_valid  = 1'b1;
            update_pc     = branch_pc;
            update_taken  = taken;
            update_target = target;
            @(posedge clk);
            #1;
            update_valid = 1'b0;
        end
    endtask

    task chk_predict;
        input [8*36-1:0] label;
        input [31:0]     at_pc;
        input            expect_taken;
        begin
            pc = at_pc;
            #1;
            chk(label, {31'b0, predict_taken}, {31'b0, expect_taken});
        end
    endtask

    initial begin
        clk          = 1'b0;
        rst          = 1'b1;
        update_valid = 1'b0;
        update_pc    = 32'b0;
        update_taken = 1'b0;
        update_target= 32'b0;
        pc           = 32'b0;
        checks       = 0;
        errors       = 0;

        $dumpfile("sim/tb_branch_predictor.vcd");
        $dumpvars(0, tb_branch_predictor);

        $display("=== tb_branch_predictor ===");

        @(posedge clk);
        @(posedge clk);
        #1;
        rst = 1'b0;

        //------------------------------------------------------------------
        // Cold. Nothing has been learned, so nothing is predicted taken --
        // a prediction with no target to jump to would be useless anyway.
        //------------------------------------------------------------------
        chk_predict("cold: not taken",      32'h0000_0100, 1'b0);
        chk_predict("cold: another PC",     32'h0000_0240, 1'b0);

        //------------------------------------------------------------------
        // One taken branch. The counter moves 01 -> 10, which is enough to
        // predict taken, and the target is remembered.
        //------------------------------------------------------------------
        resolve(32'h0000_0100, 1'b1, 32'h0000_0080);
        chk_predict("after 1 taken: taken", 32'h0000_0100, 1'b1);

        pc = 32'h0000_0100; #1;
        chk("target remembered", predict_target, 32'h0000_0080);

        //------------------------------------------------------------------
        // Saturation: more taken outcomes must not wrap the counter round
        // to not-taken.
        //------------------------------------------------------------------
        resolve(32'h0000_0100, 1'b1, 32'h0000_0080);
        resolve(32'h0000_0100, 1'b1, 32'h0000_0080);
        resolve(32'h0000_0100, 1'b1, 32'h0000_0080);
        chk_predict("saturated at taken",   32'h0000_0100, 1'b1);

        //------------------------------------------------------------------
        // Hysteresis, which is the entire reason for the second bit.
        //
        // A loop branch is taken many times and then falls through once on
        // the way out. A 1-bit predictor would flip on that single
        // exception and mispredict again on the next entry to the loop. A
        // 2-bit counter drops from 11 to 10 and keeps predicting taken.
        //------------------------------------------------------------------
        resolve(32'h0000_0100, 1'b0, 32'h0);
        chk_predict("one exception ignored", 32'h0000_0100, 1'b1);

        // A second disagreement does change its mind.
        resolve(32'h0000_0100, 1'b0, 32'h0);
        chk_predict("two in a row flips it", 32'h0000_0100, 1'b0);

        // And it recovers the same way.
        resolve(32'h0000_0100, 1'b1, 32'h0000_0080);
        resolve(32'h0000_0100, 1'b1, 32'h0000_0080);
        chk_predict("recovers to taken",     32'h0000_0100, 1'b1);

        //------------------------------------------------------------------
        // A new target for the same PC replaces the old one. This is what
        // makes an indirect jump through a changing register still work --
        // slowly, but correctly.
        //------------------------------------------------------------------
        resolve(32'h0000_0100, 1'b1, 32'h0000_0AB0);
        pc = 32'h0000_0100; #1;
        chk("target updated", predict_target, 32'h0000_0AB0);

        //------------------------------------------------------------------
        // Aliasing. 0x100 and 0x200 land on the same index but carry
        // different tags, so the second must not inherit the first's
        // prediction. Costing accuracy is acceptable; returning another
        // branch's target as if it were yours is not.
        //------------------------------------------------------------------
        chk_predict("tag mismatch not taken", 32'h0000_0200, 1'b0);

        //------------------------------------------------------------------
        // A branch that only ever falls through never enters the BTB, so
        // it stays predicted not-taken.
        //------------------------------------------------------------------
        resolve(32'h0000_0300, 1'b0, 32'h0);
        resolve(32'h0000_0300, 1'b0, 32'h0);
        resolve(32'h0000_0300, 1'b0, 32'h0);
        chk_predict("never-taken stays so",  32'h0000_0300, 1'b0);

        //------------------------------------------------------------------
        // Independent entries do not disturb each other.
        //------------------------------------------------------------------
        resolve(32'h0000_0400, 1'b1, 32'h0000_1111);
        resolve(32'h0000_0404, 1'b1, 32'h0000_2222);
        pc = 32'h0000_0400; #1;
        chk("entry A target", predict_target, 32'h0000_1111);
        pc = 32'h0000_0404; #1;
        chk("entry B target", predict_target, 32'h0000_2222);

        //------------------------------------------------------------------
        // Reset clears what was learned.
        //------------------------------------------------------------------
        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        rst = 1'b0;
        chk_predict("reset clears history",  32'h0000_0100, 1'b0);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
