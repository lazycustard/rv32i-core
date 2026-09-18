//==========================================================================
// imem.v - Instruction memory
//
// Word-addressed read-only memory with an asynchronous read: the
// instruction at PC is available in the same cycle the PC is presented.
//
// PHASE 5 NOTE: an asynchronous read cannot be mapped to FPGA block RAM.
// Xilinx will infer distributed (LUT) RAM instead, and at any useful depth
// that does not fit. Converting this to a synchronous read -- which makes
// the memory's own output register serve as the IF/ID instruction register
// -- is planned FPGA work, not an oversight. It is deferred because the
// asynchronous version keeps the fetch stage simple while the pipeline
// control logic is being brought up and verified.
//
// The default contents are NOP, so a PC that runs off the end of a loaded
// program executes no-ops rather than random bits.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module imem #(
    parameter integer WORDS     = 4096,     // 16 KiB
    parameter         INIT_FILE = ""
) (
    input  wire [31:0] addr_i,
    output wire [31:0] instr_o
);

    localparam integer AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            mem[i] = `NOP;
        end
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // Instructions are word aligned, so the low two bits of the byte
    // address are discarded. Addresses beyond the memory wrap.
    wire [AW-1:0] word_addr = addr_i[AW+1:2];

    assign instr_o = mem[word_addr];

endmodule

`default_nettype wire
