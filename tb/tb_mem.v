//==========================================================================
// tb_mem.v - Self-checking testbench for imem.v and dmem.v
//
// The data memory half is an integration test: lsu.v and dmem.v are wired
// together exactly as the MEM stage will wire them, and real store/load
// sequences are run through the pair. Testing dmem on its own would only
// prove that byte enables work; testing them together proves that sb, sh,
// lb and lh actually do the right thing to the right byte.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_mem;

    integer checks;
    integer errors;

    //----------------------------------------------------------------------
    // Instruction memory, preloaded from a hex file
    //----------------------------------------------------------------------
    reg  [31:0] imem_addr;
    wire [31:0] imem_instr;

    imem #(
        .WORDS     (64),
        .INIT_FILE ("tests/imem_smoke.hex")
    ) u_imem (
        .addr_i  (imem_addr),
        .instr_o (imem_instr)
    );

    //----------------------------------------------------------------------
    // Data memory wired through the load/store unit, as in the MEM stage
    //----------------------------------------------------------------------
    reg         clk;
    reg  [31:0] addr;
    reg  [2:0]  funct3;
    reg         is_load, is_store;
    reg  [31:0] store_data;

    wire [3:0]  byte_en;
    wire [31:0] store_word;
    wire [31:0] mem_rdata;
    wire [31:0] load_data;
    wire        misaligned;

    lsu u_lsu (
        .funct3_i     (funct3),
        .addr_lsb_i   (addr[1:0]),
        .is_load_i    (is_load),
        .is_store_i   (is_store),
        .store_data_i (store_data),
        .byte_en_o    (byte_en),
        .store_word_o (store_word),
        .load_word_i  (mem_rdata),
        .load_data_o  (load_data),
        .misaligned_o (misaligned)
    );

    dmem #(
        .WORDS (64)
    ) u_dmem (
        .clk_i     (clk),
        .addr_i    (addr),
        .wdata_i   (store_word),
        .byte_en_i (byte_en),
        .rdata_o   (mem_rdata)
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

    // One complete store: drive the LSU, let the clock edge commit it.
    task store;
        input [2:0]  f3;
        input [31:0] byte_addr;
        input [31:0] data;
        begin
            @(negedge clk);
            funct3     = f3;
            addr       = byte_addr;
            store_data = data;
            is_store   = 1'b1;
            is_load    = 1'b0;
            @(posedge clk);
            #1;
            is_store = 1'b0;
        end
    endtask

    // Read back through the LSU and check the extended result.
    task load_chk;
        input [8*32-1:0] label;
        input [2:0]      f3;
        input [31:0]     byte_addr;
        input [31:0]     expected;
        begin
            funct3   = f3;
            addr     = byte_addr;
            is_load  = 1'b1;
            is_store = 1'b0;
            #1;
            chk(label, load_data, expected);
        end
    endtask

    initial begin
        clk        = 1'b0;
        checks     = 0;
        errors     = 0;
        addr       = 32'b0;
        funct3     = `LS_W;
        is_load    = 1'b0;
        is_store   = 1'b0;
        store_data = 32'b0;
        imem_addr  = 32'b0;

        $dumpfile("sim/tb_mem.vcd");
        $dumpvars(0, tb_mem);

        $display("=== tb_mem ===");

        //------------------------------------------------------------------
        // Instruction memory: contents come from the hex file, and the
        // byte address is converted to a word index.
        //------------------------------------------------------------------
        imem_addr = 32'h0000_0000; #1;
        chk("imem[0] add x1,x2,x3",  imem_instr, 32'h0031_00B3);
        imem_addr = 32'h0000_0004; #1;
        chk("imem[4] sub x1,x2,x3",  imem_instr, 32'h4031_00B3);
        imem_addr = 32'h0000_0008; #1;
        chk("imem[8] lw x1,8(x2)",   imem_instr, 32'h0081_2083);
        imem_addr = 32'h0000_000C; #1;
        chk("imem[C] sw x5,8(x10)",  imem_instr, 32'h0055_2423);
        imem_addr = 32'h0000_0010; #1;
        chk("imem[10] jal x1,2048",  imem_instr, 32'h0010_00EF);

        // Past the end of the loaded program: NOP, not garbage.
        imem_addr = 32'h0000_0014; #1;
        chk("imem past program = NOP", imem_instr, `NOP);

        //------------------------------------------------------------------
        // Word store and load
        //------------------------------------------------------------------
        store(`LS_W, 32'd0, 32'hAABB_CCDD);
        load_chk("lw after sw", `LS_W, 32'd0, 32'hAABB_CCDD);

        //------------------------------------------------------------------
        // Byte store into the middle of that word. Only lane 1 may change.
        //------------------------------------------------------------------
        store(`LS_B, 32'd1, 32'h0000_0011);
        load_chk("lw sees only lane 1 changed", `LS_W, 32'd0, 32'hAABB_11DD);
        load_chk("lb reads back the byte",      `LS_B, 32'd1, 32'h0000_0011);
        load_chk("lb lane 0 untouched",         `LS_B, 32'd0, 32'hFFFF_FFDD);
        load_chk("lbu lane 0 untouched",        `LS_BU,32'd0, 32'h0000_00DD);

        //------------------------------------------------------------------
        // Byte store into the top lane, with the sign bit set
        //------------------------------------------------------------------
        store(`LS_B, 32'd3, 32'h0000_00FF);
        load_chk("lw after sb @3",  `LS_W,  32'd0, 32'hFFBB_11DD);
        load_chk("lb  @3 sign ext", `LS_B,  32'd3, 32'hFFFF_FFFF);
        load_chk("lbu @3 zero ext", `LS_BU, 32'd3, 32'h0000_00FF);

        //------------------------------------------------------------------
        // Halfword store over the upper half
        //------------------------------------------------------------------
        store(`LS_H, 32'd2, 32'h0000_1234);
        load_chk("lw after sh @2",  `LS_W,  32'd0, 32'h1234_11DD);
        load_chk("lh  @2",          `LS_H,  32'd2, 32'h0000_1234);
        load_chk("lh  @0 lower",    `LS_H,  32'd0, 32'h0000_11DD);

        // A halfword store with the sign bit set, read both ways
        store(`LS_H, 32'd2, 32'h0000_8765);
        load_chk("lh  @2 sign ext", `LS_H,  32'd2, 32'hFFFF_8765);
        load_chk("lhu @2 zero ext", `LS_HU, 32'd2, 32'h0000_8765);

        //------------------------------------------------------------------
        // Neighbouring words must be independent
        //------------------------------------------------------------------
        store(`LS_W, 32'd4, 32'h1111_2222);
        load_chk("word 1 written",      `LS_W, 32'd4, 32'h1111_2222);
        load_chk("word 0 undisturbed",  `LS_W, 32'd0, 32'h8765_11DD);

        store(`LS_B, 32'd4, 32'h0000_0099);
        load_chk("sb did not spill up", `LS_W, 32'd4, 32'h1111_2299);
        load_chk("sb did not spill down",`LS_W,32'd0, 32'h8765_11DD);

        //------------------------------------------------------------------
        // A misaligned store must leave memory completely unchanged
        //------------------------------------------------------------------
        store(`LS_W, 32'd1, 32'hDEAD_BEEF);
        load_chk("misaligned sw changed nothing", `LS_W, 32'd0, 32'h8765_11DD);

        store(`LS_H, 32'd5, 32'hDEAD_BEEF);
        load_chk("misaligned sh changed nothing", `LS_W, 32'd4, 32'h1111_2299);

        //------------------------------------------------------------------
        // A load must never write, however tempting the operands look
        //------------------------------------------------------------------
        @(negedge clk);
        funct3     = `LS_W;
        addr       = 32'd0;
        store_data = 32'hFFFF_FFFF;
        is_load    = 1'b1;
        is_store   = 1'b0;
        @(posedge clk);
        #1;
        load_chk("load did not write", `LS_W, 32'd0, 32'h8765_11DD);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
