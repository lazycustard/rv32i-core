//==========================================================================
// tb_hazard_unit.v - Self-checking testbench for hazard_unit.v
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_hazard_unit;

    reg  [4:0] id_rs1, id_rs2;
    reg        id_uses_rs1, id_uses_rs2;
    reg  [4:0] ex_rs1, ex_rs2, ex_rd;
    reg        ex_mem_read;
    reg  [4:0] mem_rd;
    reg        mem_reg_write;
    reg  [4:0] wb_rd;
    reg        wb_reg_write;
    reg        pc_redirect;

    wire       stall_if, stall_id, flush_id, flush_ex;
    wire [`FWD_W-1:0] fwd_a, fwd_b;

    integer checks;
    integer errors;

    hazard_unit dut (
        .id_rs1_addr_i   (id_rs1),
        .id_rs2_addr_i   (id_rs2),
        .id_uses_rs1_i   (id_uses_rs1),
        .id_uses_rs2_i   (id_uses_rs2),
        .ex_rs1_addr_i   (ex_rs1),
        .ex_rs2_addr_i   (ex_rs2),
        .ex_rd_addr_i    (ex_rd),
        .ex_mem_read_i   (ex_mem_read),
        .mem_rd_addr_i   (mem_rd),
        .mem_reg_write_i (mem_reg_write),
        .wb_rd_addr_i    (wb_rd),
        .wb_reg_write_i  (wb_reg_write),
        .pc_redirect_i   (pc_redirect),
        .stall_if_o      (stall_if),
        .stall_id_o      (stall_id),
        .flush_id_o      (flush_id),
        .flush_ex_o      (flush_ex),
        .fwd_a_o         (fwd_a),
        .fwd_b_o         (fwd_b)
    );

    task chk;
        input [8*34-1:0] label;
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

    // Put every input in a quiet state so each test only varies what it
    // is actually about.
    task idle;
        begin
            id_rs1        = 5'd0;
            id_rs2        = 5'd0;
            id_uses_rs1   = 1'b0;
            id_uses_rs2   = 1'b0;
            ex_rs1        = 5'd0;
            ex_rs2        = 5'd0;
            ex_rd         = 5'd0;
            ex_mem_read   = 1'b0;
            mem_rd        = 5'd0;
            mem_reg_write = 1'b0;
            wb_rd         = 5'd0;
            wb_reg_write  = 1'b0;
            pc_redirect   = 1'b0;
            #1;
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;

        $dumpfile("sim/tb_hazard_unit.vcd");
        $dumpvars(0, tb_hazard_unit);

        $display("=== tb_hazard_unit ===");

        //------------------------------------------------------------------
        // Quiet pipeline: nothing to do
        //------------------------------------------------------------------
        idle();
        chk("idle: no fwd a",  fwd_a,    `FWD_NONE);
        chk("idle: no fwd b",  fwd_b,    `FWD_NONE);
        chk("idle: no stall",  stall_if, 32'd0);
        chk("idle: no flush",  flush_ex, 32'd0);

        //------------------------------------------------------------------
        // Forward from MEM:  add x5,...  /  add x1, x5, x0
        //------------------------------------------------------------------
        idle();
        ex_rs1 = 5'd5; mem_rd = 5'd5; mem_reg_write = 1'b1; #1;
        chk("MEM->A forwarded", fwd_a, `FWD_MEM);
        chk("B untouched",      fwd_b, `FWD_NONE);

        idle();
        ex_rs2 = 5'd7; mem_rd = 5'd7; mem_reg_write = 1'b1; #1;
        chk("MEM->B forwarded", fwd_b, `FWD_MEM);
        chk("A untouched",      fwd_a, `FWD_NONE);

        //------------------------------------------------------------------
        // Forward from WB
        //------------------------------------------------------------------
        idle();
        ex_rs1 = 5'd9; wb_rd = 5'd9; wb_reg_write = 1'b1; #1;
        chk("WB->A forwarded",  fwd_a, `FWD_WB);

        idle();
        ex_rs2 = 5'd9; wb_rd = 5'd9; wb_reg_write = 1'b1; #1;
        chk("WB->B forwarded",  fwd_b, `FWD_WB);

        //------------------------------------------------------------------
        // Both stages write the same register. MEM is the more recent
        // instruction, so MEM must win.
        //------------------------------------------------------------------
        idle();
        ex_rs1 = 5'd3;
        mem_rd = 5'd3; mem_reg_write = 1'b1;
        wb_rd  = 5'd3; wb_reg_write  = 1'b1;
        #1;
        chk("MEM beats WB on A", fwd_a, `FWD_MEM);

        idle();
        ex_rs2 = 5'd3;
        mem_rd = 5'd3; mem_reg_write = 1'b1;
        wb_rd  = 5'd3; wb_reg_write  = 1'b1;
        #1;
        chk("MEM beats WB on B", fwd_b, `FWD_MEM);

        //------------------------------------------------------------------
        // No forwarding without a write enable
        //------------------------------------------------------------------
        idle();
        ex_rs1 = 5'd5; mem_rd = 5'd5; mem_reg_write = 1'b0; #1;
        chk("no fwd if MEM not writing", fwd_a, `FWD_NONE);

        idle();
        ex_rs1 = 5'd5; wb_rd = 5'd5; wb_reg_write = 1'b0; #1;
        chk("no fwd if WB not writing",  fwd_a, `FWD_NONE);

        //------------------------------------------------------------------
        // x0 is never forwarded. It reads as zero by definition, so
        // injecting a written value would be architecturally wrong.
        //------------------------------------------------------------------
        idle();
        ex_rs1 = 5'd0; mem_rd = 5'd0; mem_reg_write = 1'b1; #1;
        chk("x0 not forwarded from MEM", fwd_a, `FWD_NONE);

        idle();
        ex_rs2 = 5'd0; wb_rd = 5'd0; wb_reg_write = 1'b1; #1;
        chk("x0 not forwarded from WB",  fwd_b, `FWD_NONE);

        //------------------------------------------------------------------
        // Different registers must not forward
        //------------------------------------------------------------------
        idle();
        ex_rs1 = 5'd4; mem_rd = 5'd6; mem_reg_write = 1'b1; #1;
        chk("unrelated reg no fwd", fwd_a, `FWD_NONE);

        //------------------------------------------------------------------
        // Load-use hazard:  lw x5, 0(x2)  /  add x1, x5, x0
        //------------------------------------------------------------------
        idle();
        ex_rd = 5'd5; ex_mem_read = 1'b1;
        id_rs1 = 5'd5; id_uses_rs1 = 1'b1;
        #1;
        chk("load-use stalls IF", stall_if, 32'd1);
        chk("load-use stalls ID", stall_id, 32'd1);
        chk("load-use bubbles EX",flush_ex, 32'd1);
        chk("load-use no ID flush", flush_id, 32'd0);

        // Same hazard through the second source operand
        idle();
        ex_rd = 5'd5; ex_mem_read = 1'b1;
        id_rs2 = 5'd5; id_uses_rs2 = 1'b1;
        #1;
        chk("load-use on rs2 stalls", stall_if, 32'd1);

        //------------------------------------------------------------------
        // No stall when the next instruction does not read that register.
        // The register number is still sitting in the instruction word --
        // this is the case a naive comparison gets wrong.
        //------------------------------------------------------------------
        idle();
        ex_rd = 5'd5; ex_mem_read = 1'b1;
        id_rs1 = 5'd5; id_uses_rs1 = 1'b0;   // e.g. LUI: bits present, unused
        id_rs2 = 5'd5; id_uses_rs2 = 1'b0;
        #1;
        chk("no stall if rs unused", stall_if, 32'd0);

        //------------------------------------------------------------------
        // No stall when EX is not a load. An ALU result is ready at the end
        // of EX and gets forwarded instead.
        //------------------------------------------------------------------
        idle();
        ex_rd = 5'd5; ex_mem_read = 1'b0;
        id_rs1 = 5'd5; id_uses_rs1 = 1'b1;
        #1;
        chk("ALU producer does not stall", stall_if, 32'd0);

        //------------------------------------------------------------------
        // A load into x0 discards its result, so nothing depends on it.
        //------------------------------------------------------------------
        idle();
        ex_rd = 5'd0; ex_mem_read = 1'b1;
        id_rs1 = 5'd0; id_uses_rs1 = 1'b1;
        #1;
        chk("load to x0 does not stall", stall_if, 32'd0);

        //------------------------------------------------------------------
        // Different register: no stall
        //------------------------------------------------------------------
        idle();
        ex_rd = 5'd5; ex_mem_read = 1'b1;
        id_rs1 = 5'd6; id_uses_rs1 = 1'b1;
        #1;
        chk("unrelated load no stall", stall_if, 32'd0);

        //------------------------------------------------------------------
        // Taken branch: flush the two instructions already in flight, but
        // do NOT stall -- the pipeline keeps moving, it just discards.
        //------------------------------------------------------------------
        idle();
        pc_redirect = 1'b1; #1;
        chk("redirect flushes ID", flush_id, 32'd1);
        chk("redirect flushes EX", flush_ex, 32'd1);
        chk("redirect does not stall IF", stall_if, 32'd0);
        chk("redirect does not stall ID", stall_id, 32'd0);

        //------------------------------------------------------------------
        // Forwarding is orthogonal to redirecting: a branch does not
        // suppress a forward that a still-valid instruction needs.
        //------------------------------------------------------------------
        idle();
        pc_redirect = 1'b1;
        ex_rs1 = 5'd5; mem_rd = 5'd5; mem_reg_write = 1'b1;
        #1;
        chk("forward survives redirect", fwd_a, `FWD_MEM);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
