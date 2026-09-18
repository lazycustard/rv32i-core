//==========================================================================
// reg_file.v - RV32I general purpose registers
//
// 32 registers of 32 bits, two read ports and one write port.
//
// Two details that are easy to get wrong:
//
// 1. x0 is hardwired to zero. Reads of x0 return zero and writes to x0 are
//    discarded. This is architectural, not an optimisation -- compilers rely
//    on it (a NOP is literally "addi x0, x0, 0").
//
// 2. Read-during-write returns the NEW value ("write-first"). In a 5-stage
//    pipeline, writeback happens in stage 5 while a later instruction is
//    reading in stage 2, and those can land in the same cycle. The common
//    shortcut is to clock the write on the falling edge so the read half of
//    the cycle sees it, but that builds a design that depends on both clock
//    edges and does not map cleanly to FPGA memory. An explicit bypass mux
//    does the same job on a single edge.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps

module reg_file (
    input  wire        clk_i,

    // Read ports (combinational)
    input  wire [4:0]  rs1_addr_i,
    input  wire [4:0]  rs2_addr_i,
    output wire [31:0] rs1_data_o,
    output wire [31:0] rs2_data_o,

    // Write port (synchronous)
    input  wire        we_i,
    input  wire [4:0]  rd_addr_i,
    input  wire [31:0] rd_data_i
);

    reg [31:0] regs [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            regs[i] = 32'b0;
        end
    end

    // A write to x0 is silently dropped.
    wire write_en = we_i && (rd_addr_i != 5'd0);

    always @(posedge clk_i) begin
        if (write_en) begin
            regs[rd_addr_i] <= rd_data_i;
        end
    end

    // Forward the value being written this cycle to any read port asking
    // for the same register.
    wire rs1_fwd = write_en && (rd_addr_i == rs1_addr_i);
    wire rs2_fwd = write_en && (rd_addr_i == rs2_addr_i);

    assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'b0 :
                        rs1_fwd              ? rd_data_i :
                                               regs[rs1_addr_i];

    assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'b0 :
                        rs2_fwd              ? rd_data_i :
                                               regs[rs2_addr_i];

endmodule

`default_nettype wire
