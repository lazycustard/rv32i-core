//==========================================================================
// branch_predictor.v - Branch target buffer and 2-bit direction predictor
//
// Today the core resolves branches in EX and pays two flushed instructions
// every time one is taken. Measured on the C programs, 47% of branches are
// taken, and that penalty is most of the CPI above 1.0.
//
// Fixing it needs two separate predictions, and only having both is useful:
//
//   DIRECTION  will this branch be taken? A 2-bit saturating counter per
//              entry. Two bits rather than one because a loop branch is
//              taken many times and then falls through once at the end; a
//              1-bit predictor mispredicts twice for that -- once on the
//              exit, once again on the next entry -- where a 2-bit counter
//              absorbs the single exception without changing its mind.
//
//   TARGET     where does it go? The fetch stage has not decoded the
//              instruction yet, let alone extracted its immediate, so the
//              address has to come from somewhere. The BTB remembers where
//              this PC jumped to last time.
//
// Both are indexed by the low PC bits, so two branches far apart in memory
// can collide and read each other's history. That is a normal and accepted
// property of a direct-mapped predictor: a collision costs accuracy, never
// correctness, because EX checks every prediction against what actually
// happened and redirects when they disagree.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps

module branch_predictor #(
    parameter integer ENTRIES = 64
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // Lookup, in the fetch stage
    input  wire [31:0] pc_i,
    output wire        predict_taken_o,
    output wire [31:0] predict_target_o,

    // Update, from the execute stage once the branch is resolved
    input  wire        update_valid_i,    // a branch or jump resolved
    input  wire [31:0] update_pc_i,
    input  wire        update_taken_i,
    input  wire [31:0] update_target_i
);

    localparam integer IDX_W = $clog2(ENTRIES);

    // Instructions are word aligned, so bits 1:0 carry no information and
    // indexing with them would leave three quarters of the table unused.
    wire [IDX_W-1:0] rd_idx = pc_i[IDX_W+1:2];
    wire [IDX_W-1:0] wr_idx = update_pc_i[IDX_W+1:2];

    wire [29-IDX_W:0] rd_tag = pc_i[31:IDX_W+2];
    wire [29-IDX_W:0] wr_tag = update_pc_i[31:IDX_W+2];

    reg               btb_valid  [0:ENTRIES-1];
    reg [29-IDX_W:0]  btb_tag    [0:ENTRIES-1];
    reg [31:0]        btb_target [0:ENTRIES-1];
    reg [1:0]         bht        [0:ENTRIES-1];

    integer i;
    initial begin
        for (i = 0; i < ENTRIES; i = i + 1) begin
            btb_valid[i]  = 1'b0;
            btb_tag[i]    = {(30-IDX_W){1'b0}};
            btb_target[i] = 32'b0;
            bht[i]        = 2'b01;      // weakly not taken
        end
    end

    //----------------------------------------------------------------------
    // Lookup. A prediction of "taken" is only useful with a target to go
    // to, so a BTB miss predicts not-taken regardless of what the counter
    // says.
    //----------------------------------------------------------------------
    wire btb_hit = btb_valid[rd_idx] && (btb_tag[rd_idx] == rd_tag);

    assign predict_taken_o  = btb_hit && bht[rd_idx][1];
    assign predict_target_o = btb_target[rd_idx];

    //----------------------------------------------------------------------
    // Update.
    //
    // The counter moves one step towards the outcome that just happened,
    // saturating at both ends. The BTB is only written on a taken branch:
    // a branch that falls through has no target worth remembering, and
    // writing one would evict an entry that is actually being used.
    //----------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                btb_valid[i] <= 1'b0;
                bht[i]       <= 2'b01;
            end
        end else if (update_valid_i) begin
            if (update_taken_i) begin
                btb_valid[wr_idx]  <= 1'b1;
                btb_tag[wr_idx]    <= wr_tag;
                btb_target[wr_idx] <= update_target_i;

                if (bht[wr_idx] != 2'b11) begin
                    bht[wr_idx] <= bht[wr_idx] + 2'b01;
                end
            end else begin
                if (bht[wr_idx] != 2'b00) begin
                    bht[wr_idx] <= bht[wr_idx] - 2'b01;
                end
            end
        end
    end

endmodule

`default_nettype wire
