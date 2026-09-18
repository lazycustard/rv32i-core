//==========================================================================
// hazard_unit.v - Forwarding, stalling and flushing
//
// A pipeline lets five instructions overlap, which means an instruction can
// reach EX before the one it depends on has written its result back. There
// are exactly three things to do about that, and this module decides which:
//
//   FORWARD  The value exists somewhere further down the pipeline, just not
//            in the register file yet. Route it backwards to EX. Costs
//            nothing: no cycles lost.
//
//   STALL    The value does not exist yet at all. The only case in this
//            design is a load followed immediately by a use: the data comes
//            out of memory in MEM, one stage too late for the next
//            instruction's EX. Freeze fetch and decode for one cycle and
//            insert a bubble. After that single cycle, WB forwarding covers
//            it. Costs one cycle.
//
//   FLUSH    The instructions already fetched are the wrong ones. Branches
//            and jumps resolve in EX, by which point two later instructions
//            have entered the pipeline. Blank them. Costs two cycles.
//
// Two details that are easy to get wrong:
//
// 1. x0 is never a real dependency. It always reads as zero, so forwarding
//    a write to x0 would inject a value that architecturally does not exist.
//
// 2. A stall is only needed if the instruction in decode ACTUALLY READS the
//    register. Every instruction word has bits sitting in the rs1 and rs2
//    fields, but LUI, AUIPC and JAL never read them. Stalling on those bits
//    burns cycles for dependencies that do not exist, which is why this
//    module takes uses_rs1 / uses_rs2 from the decoder rather than
//    comparing register numbers blindly.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module hazard_unit (
    // Decode stage: what the next instruction wants to read
    input  wire [4:0]           id_rs1_addr_i,
    input  wire [4:0]           id_rs2_addr_i,
    input  wire                 id_uses_rs1_i,
    input  wire                 id_uses_rs2_i,

    // Execute stage: what is being computed right now
    input  wire [4:0]           ex_rs1_addr_i,
    input  wire [4:0]           ex_rs2_addr_i,
    input  wire [4:0]           ex_rd_addr_i,
    input  wire                 ex_mem_read_i,      // EX holds a load

    // Memory stage: a result that exists but is not written back yet
    input  wire [4:0]           mem_rd_addr_i,
    input  wire                 mem_reg_write_i,

    // Writeback stage: a result being written this very cycle
    input  wire [4:0]           wb_rd_addr_i,
    input  wire                 wb_reg_write_i,

    // A branch or jump in EX has redirected the PC
    input  wire                 pc_redirect_i,

    output wire                 stall_if_o,
    output wire                 stall_id_o,
    output wire                 flush_id_o,
    output wire                 flush_ex_o,
    output reg  [`FWD_W-1:0]    fwd_a_o,
    output reg  [`FWD_W-1:0]    fwd_b_o
);

    //----------------------------------------------------------------------
    // Forwarding.
    //
    // MEM is checked before WB. If both stages are writing the same
    // register, MEM holds the more recent instruction and its value is the
    // one the architecture says we should see.
    //----------------------------------------------------------------------
    wire a_is_real = (ex_rs1_addr_i != 5'd0);
    wire b_is_real = (ex_rs2_addr_i != 5'd0);

    always @(*) begin
        if (a_is_real && mem_reg_write_i && (mem_rd_addr_i == ex_rs1_addr_i))
            fwd_a_o = `FWD_MEM;
        else if (a_is_real && wb_reg_write_i && (wb_rd_addr_i == ex_rs1_addr_i))
            fwd_a_o = `FWD_WB;
        else
            fwd_a_o = `FWD_NONE;
    end

    always @(*) begin
        if (b_is_real && mem_reg_write_i && (mem_rd_addr_i == ex_rs2_addr_i))
            fwd_b_o = `FWD_MEM;
        else if (b_is_real && wb_reg_write_i && (wb_rd_addr_i == ex_rs2_addr_i))
            fwd_b_o = `FWD_WB;
        else
            fwd_b_o = `FWD_NONE;
    end

    //----------------------------------------------------------------------
    // Load-use stall.
    //
    // Only a load creates a value that forwarding cannot reach in time.
    // Every other producer has its result ready at the end of EX.
    //----------------------------------------------------------------------
    wire load_use_hazard =
        ex_mem_read_i && (ex_rd_addr_i != 5'd0) &&
        ((id_uses_rs1_i && (id_rs1_addr_i == ex_rd_addr_i)) ||
         (id_uses_rs2_i && (id_rs2_addr_i == ex_rd_addr_i)));

    //----------------------------------------------------------------------
    // Stall and flush.
    //
    // A stall holds IF and ID in place and drops a bubble into EX, so the
    // stalled instruction is not executed twice.
    //
    // A redirect invalidates both instructions already in flight behind the
    // branch: the one in decode and the one being fetched.
    //----------------------------------------------------------------------
    assign stall_if_o = load_use_hazard;
    assign stall_id_o = load_use_hazard;
    assign flush_id_o = pc_redirect_i;
    assign flush_ex_o = load_use_hazard || pc_redirect_i;

endmodule

`default_nettype wire
