//==========================================================================
// ras.v - Return address stack, and the instruction hints that drive it
//
// A BTB remembers one target per branch PC. That works for a loop, whose
// branch goes to the same place every time, and fails for a function
// return, which goes back to whichever call site invoked it. Measured on
// the recursive fib program, the BTB alone got 66% of control transfers
// right -- the worst of the four test programs, and for exactly this
// reason.
//
// A return address stack fixes it by predicting returns from structure
// rather than from history: a call pushes the address it will come back
// to, and a return pops it. Calls and returns nest, so a stack is the
// right shape, and the prediction is usually exactly right rather than
// merely likely.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps

module ras #(
    parameter integer DEPTH = 8
) (
    input  wire        clk_i,
    input  wire        rst_i,

    input  wire        push_i,
    input  wire [31:0] push_addr_i,
    input  wire        pop_i,

    output wire [31:0] top_o,
    output wire        valid_o      // is there anything on the stack?
);

    localparam integer PTR_W = $clog2(DEPTH);

    reg [31:0]       stack [0:DEPTH-1];
    reg [PTR_W-1:0]  sp;             // next free slot
    reg [PTR_W:0]    count;          // entries held, for the valid flag

    wire [PTR_W-1:0] top_idx = sp - 1'b1;

    assign top_o   = stack[top_idx];
    assign valid_o = (count != 0);

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) stack[i] = 32'b0;
        sp    = {PTR_W{1'b0}};
        count = {(PTR_W+1){1'b0}};
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            sp    <= {PTR_W{1'b0}};
            count <= {(PTR_W+1){1'b0}};
        end else if (push_i && pop_i) begin
            // Both at once: replace the top rather than moving the pointer.
            stack[top_idx] <= push_addr_i;
        end else if (push_i) begin
            stack[sp] <= push_addr_i;
            sp        <= sp + 1'b1;
            // The pointer wraps, so a call chain deeper than DEPTH
            // overwrites the oldest entry instead of overflowing. Those
            // outermost returns then mispredict -- accuracy degrades, which
            // is the acceptable failure for a predictor. Refusing the push
            // would corrupt the order of everything above it, which is not.
            if (count != DEPTH[PTR_W:0]) count <= count + 1'b1;
        end else if (pop_i) begin
            if (count != 0) begin
                sp    <= sp - 1'b1;
                count <= count - 1'b1;
            end
        end
    end

endmodule


//==========================================================================
// call_ret_hint - Is this instruction a call, a return, or neither?
//
// RV32I has no distinct call or return instruction; both are JAL or JALR,
// and the difference is in which registers they touch. The specification
// spells out how hardware should read that:
//
//   a link register is x1 or x5
//   rd is a link register     ->  this is a call, push rd's value
//   rs1 is a link register
//     and rd is not           ->  this is a return, pop
//
// Kept as its own module because the answer is needed in two places at
// once: the fetch stage, to make the prediction, and the execute stage, to
// update the stack. One definition, so the two cannot drift apart.
//==========================================================================

module call_ret_hint (
    input  wire [31:0] instr_i,
    output wire        is_call_o,
    output wire        is_ret_o
);

    wire [6:0] opcode = instr_i[6:0];
    wire [2:0] funct3 = instr_i[14:12];
    wire [4:0] rd     = instr_i[11:7];
    wire [4:0] rs1    = instr_i[19:15];

    wire is_jal  = (opcode == 7'b1101111);
    wire is_jalr = (opcode == 7'b1100111) && (funct3 == 3'b000);

    wire rd_link  = (rd  == 5'd1) || (rd  == 5'd5);
    wire rs1_link = (rs1 == 5'd1) || (rs1 == 5'd5);

    assign is_call_o = (is_jal || is_jalr) && rd_link;
    assign is_ret_o  = is_jalr && rs1_link && !rd_link;

    // The specification also defines a pop-then-push case, for a jump that
    // both returns and calls in one instruction. Compilers do not emit it
    // for ordinary C, so it is treated as a plain call here: the stack
    // grows where it should have stayed level, and the prediction that
    // eventually falls off the bottom is wrong. Accuracy again, not
    // correctness -- EX checks every prediction regardless.

endmodule

`default_nettype wire
