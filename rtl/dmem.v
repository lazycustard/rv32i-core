//==========================================================================
// dmem.v - Data memory
//
// Word-wide storage with per-byte write enables, so a byte store modifies
// one lane and leaves the other three untouched. A memory that can only be
// written a full word at a time cannot implement sb or sh at all: a
// read-modify-write would be needed, and the other three bytes would be
// clobbered by whatever happened to be in the register.
//
// The write enables arrive already gated by lsu.v -- they are low for
// loads, for idle cycles, and for misaligned stores -- so no separate
// write-enable input is needed here. One signal that can be wrong instead
// of two.
//
// Reads are asynchronous. See the Phase 5 note in imem.v: this becomes a
// synchronous block RAM when the design is taken to an FPGA.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps

module dmem #(
    parameter integer WORDS     = 4096,     // 16 KiB
    parameter         INIT_FILE = ""
) (
    input  wire        clk_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    input  wire [3:0]  byte_en_i,
    output wire [31:0] rdata_o
);

    localparam integer AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            mem[i] = 32'b0;
        end
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    wire [AW-1:0] word_addr = addr_i[AW+1:2];

    assign rdata_o = mem[word_addr];

    always @(posedge clk_i) begin
        if (byte_en_i[0]) mem[word_addr][7:0]   <= wdata_i[7:0];
        if (byte_en_i[1]) mem[word_addr][15:8]  <= wdata_i[15:8];
        if (byte_en_i[2]) mem[word_addr][23:16] <= wdata_i[23:16];
        if (byte_en_i[3]) mem[word_addr][31:24] <= wdata_i[31:24];
    end

endmodule

`default_nettype wire
