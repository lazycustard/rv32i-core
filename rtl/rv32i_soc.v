//==========================================================================
// rv32i_soc.v - The core with its memories attached
//
// rv32i_core is the pipeline and nothing else: instructions and data arrive
// through ports. This module is the small system around it -- core plus
// instruction memory plus data memory -- and is what simulation runs.
//
// The split exists because of a synthesis result. With the memories inside
// the core, the instruction stream was a compile-time constant: imem is
// filled with NOP by an initial block and nothing outside could change it.
// Vivado propagated that through the whole pipeline and reported a design
// of three LUTs, with only the free-running performance counters left
// standing. The reported 273 MHz was the Fmax of those three LUTs.
//
// It was also a real limitation rather than only a measurement artefact:
// a core with its program sealed inside has no way to be given one on
// hardware. Testbenches reached in and wrote the arrays directly, which
// works in simulation and nowhere else.
//
// So synthesis targets rv32i_core, where the instruction stream genuinely
// comes from outside and cannot be folded away, and this module keeps
// simulation working exactly as before. It is also the shape Phase 5 needs
// in order to swap these memories for block RAM.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps

module rv32i_soc #(
    parameter [31:0]  RESET_ADDR = 32'h0000_0000,
    parameter integer IMEM_WORDS = 4096,
    parameter integer DMEM_WORDS = 4096,
    parameter         IMEM_INIT  = "",
    parameter         DMEM_INIT  = "",
    parameter integer BP_ENTRIES = 64,
    parameter integer BP_ENABLE  = 1,
    parameter integer RAS_DEPTH  = 8
) (
    input  wire        clk_i,
    input  wire        rst_i,

    output wire        uart_valid_o,
    output wire [7:0]  uart_data_o,

    output wire [63:0] perf_cycles_o,
    output wire [63:0] perf_instret_o,
    output wire [31:0] perf_stalls_o,
    output wire [31:0] perf_mispredicts_o,
    output wire [31:0] perf_branches_o,
    output wire [31:0] perf_br_taken_o,

    output wire [31:0] dbg_pc_o,
    output wire        dbg_ecall_o,
    output wire        dbg_illegal_o
);

    wire [31:0] imem_addr, imem_data;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_byte_en;

    rv32i_core #(
        .RESET_ADDR (RESET_ADDR),
        .BP_ENTRIES (BP_ENTRIES),
        .BP_ENABLE  (BP_ENABLE),
        .RAS_DEPTH  (RAS_DEPTH)
    ) u_core (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .imem_addr_o        (imem_addr),
        .imem_data_i        (imem_data),
        .dmem_addr_o        (dmem_addr),
        .dmem_wdata_o       (dmem_wdata),
        .dmem_byte_en_o     (dmem_byte_en),
        .dmem_rdata_i       (dmem_rdata),
        .uart_valid_o       (uart_valid_o),
        .uart_data_o        (uart_data_o),
        .perf_cycles_o      (perf_cycles_o),
        .perf_instret_o     (perf_instret_o),
        .perf_stalls_o      (perf_stalls_o),
        .perf_mispredicts_o (perf_mispredicts_o),
        .perf_branches_o    (perf_branches_o),
        .perf_br_taken_o    (perf_br_taken_o),
        .dbg_pc_o           (dbg_pc_o),
        .dbg_ecall_o        (dbg_ecall_o),
        .dbg_illegal_o      (dbg_illegal_o)
    );

    imem #(
        .WORDS     (IMEM_WORDS),
        .INIT_FILE (IMEM_INIT)
    ) u_imem (
        .addr_i  (imem_addr),
        .instr_o (imem_data)
    );

    dmem #(
        .WORDS     (DMEM_WORDS),
        .INIT_FILE (DMEM_INIT)
    ) u_dmem (
        .clk_i     (clk_i),
        .addr_i    (dmem_addr),
        .wdata_i   (dmem_wdata),
        .byte_en_i (dmem_byte_en),
        .rdata_o   (dmem_rdata)
    );

endmodule

`default_nettype wire
