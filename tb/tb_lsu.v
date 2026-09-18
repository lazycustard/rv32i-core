//==========================================================================
// tb_lsu.v - Self-checking testbench for lsu.v
//
// The load word used throughout is 0xFF807F01, chosen so every byte lane
// holds a different value and both sign-bit-set (0x80, 0xFF) and
// sign-bit-clear (0x01, 0x7F) bytes are present. A sign-extension bug
// therefore cannot hide in whichever lane the test happens to pick.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_lsu;

    localparam [31:0] LOAD_WORD  = 32'hFF80_7F01;
    localparam [31:0] STORE_DATA = 32'hAABB_CCDD;

    reg  [2:0]  funct3;
    reg  [1:0]  addr_lsb;
    reg         is_load, is_store;
    reg  [31:0] store_data;
    reg  [31:0] load_word;

    wire [3:0]  byte_en;
    wire [31:0] store_word;
    wire [31:0] load_data;
    wire        misaligned;

    integer checks;
    integer errors;

    lsu dut (
        .funct3_i     (funct3),
        .addr_lsb_i   (addr_lsb),
        .is_load_i    (is_load),
        .is_store_i   (is_store),
        .store_data_i (store_data),
        .byte_en_o    (byte_en),
        .store_word_o (store_word),
        .load_word_i  (load_word),
        .load_data_o  (load_data),
        .misaligned_o (misaligned)
    );

    task chk;
        input [8*28-1:0] label;
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

    // Drive a load and check the extended result.
    task do_load;
        input [8*28-1:0] label;
        input [2:0]      f3;
        input [1:0]      lsb;
        input [31:0]     expected;
        begin
            funct3   = f3;
            addr_lsb = lsb;
            is_load  = 1'b1;
            is_store = 1'b0;
            #1;
            chk(label, load_data, expected);
        end
    endtask

    // Drive a store and check the byte enables.
    task do_store;
        input [8*28-1:0] label;
        input [2:0]      f3;
        input [1:0]      lsb;
        input [3:0]      expected_en;
        begin
            funct3   = f3;
            addr_lsb = lsb;
            is_load  = 1'b0;
            is_store = 1'b1;
            #1;
            chk(label, {28'b0, byte_en}, {28'b0, expected_en});
        end
    endtask

    task chk_misaligned;
        input [8*28-1:0] label;
        input [2:0]      f3;
        input [1:0]      lsb;
        input            expected;
        begin
            funct3   = f3;
            addr_lsb = lsb;
            is_load  = 1'b1;
            is_store = 1'b0;
            #1;
            chk(label, {31'b0, misaligned}, {31'b0, expected});
        end
    endtask

    initial begin
        checks     = 0;
        errors     = 0;
        store_data = STORE_DATA;
        load_word  = LOAD_WORD;
        is_load    = 1'b0;
        is_store   = 1'b0;
        funct3     = `LS_W;
        addr_lsb   = 2'b00;

        $dumpfile("sim/tb_lsu.vcd");
        $dumpvars(0, tb_lsu);

        $display("=== tb_lsu ===");

        //------------------------------------------------------------------
        // Loads: byte lane selection
        //------------------------------------------------------------------
        do_load("lb  @0 (0x01)",  `LS_B,  2'b00, 32'h0000_0001);
        do_load("lb  @1 (0x7F)",  `LS_B,  2'b01, 32'h0000_007F);
        do_load("lb  @2 (0x80)",  `LS_B,  2'b10, 32'hFFFF_FF80);
        do_load("lb  @3 (0xFF)",  `LS_B,  2'b11, 32'hFFFF_FFFF);

        //------------------------------------------------------------------
        // The same bytes, zero-extended. lb and lbu differ ONLY here, and
        // only for bytes with the high bit set.
        //------------------------------------------------------------------
        do_load("lbu @0",         `LS_BU, 2'b00, 32'h0000_0001);
        do_load("lbu @1",         `LS_BU, 2'b01, 32'h0000_007F);
        do_load("lbu @2 no sign", `LS_BU, 2'b10, 32'h0000_0080);
        do_load("lbu @3 no sign", `LS_BU, 2'b11, 32'h0000_00FF);

        //------------------------------------------------------------------
        // Halfwords
        //------------------------------------------------------------------
        do_load("lh  @0 (0x7F01)", `LS_H,  2'b00, 32'h0000_7F01);
        do_load("lh  @2 (0xFF80)", `LS_H,  2'b10, 32'hFFFF_FF80);
        do_load("lhu @0",          `LS_HU, 2'b00, 32'h0000_7F01);
        do_load("lhu @2 no sign",  `LS_HU, 2'b10, 32'h0000_FF80);

        //------------------------------------------------------------------
        // Word
        //------------------------------------------------------------------
        do_load("lw  @0",          `LS_W,  2'b00, LOAD_WORD);

        //------------------------------------------------------------------
        // Stores: byte enables must select exactly one lane for sb,
        // two for sh, four for sw.
        //------------------------------------------------------------------
        do_store("sb @0 byte_en", `LS_B, 2'b00, 4'b0001);
        do_store("sb @1 byte_en", `LS_B, 2'b01, 4'b0010);
        do_store("sb @2 byte_en", `LS_B, 2'b10, 4'b0100);
        do_store("sb @3 byte_en", `LS_B, 2'b11, 4'b1000);
        do_store("sh @0 byte_en", `LS_H, 2'b00, 4'b0011);
        do_store("sh @2 byte_en", `LS_H, 2'b10, 4'b1100);
        do_store("sw @0 byte_en", `LS_W, 2'b00, 4'b1111);

        //------------------------------------------------------------------
        // Store data replication. Whichever lane the byte enables pick,
        // the correct source byte must already be sitting there.
        //------------------------------------------------------------------
        funct3 = `LS_B; addr_lsb = 2'b00; is_store = 1'b1; is_load = 1'b0; #1;
        chk("sb replicates low byte",  store_word, 32'hDDDD_DDDD);
        funct3 = `LS_H; #1;
        chk("sh replicates low half",  store_word, 32'hCCDD_CCDD);
        funct3 = `LS_W; #1;
        chk("sw passes data through",  store_word, STORE_DATA);

        //------------------------------------------------------------------
        // Alignment. Bytes are always aligned; halfwords need an even
        // address; words need a 4-byte boundary.
        //------------------------------------------------------------------
        chk_misaligned("lb  @1 aligned",     `LS_B,  2'b01, 1'b0);
        chk_misaligned("lb  @3 aligned",     `LS_B,  2'b11, 1'b0);
        chk_misaligned("lbu @3 aligned",     `LS_BU, 2'b11, 1'b0);
        chk_misaligned("lh  @0 aligned",     `LS_H,  2'b00, 1'b0);
        chk_misaligned("lh  @1 misaligned",  `LS_H,  2'b01, 1'b1);
        chk_misaligned("lh  @2 aligned",     `LS_H,  2'b10, 1'b0);
        chk_misaligned("lh  @3 misaligned",  `LS_H,  2'b11, 1'b1);
        chk_misaligned("lhu @1 misaligned",  `LS_HU, 2'b01, 1'b1);
        chk_misaligned("lw  @0 aligned",     `LS_W,  2'b00, 1'b0);
        chk_misaligned("lw  @1 misaligned",  `LS_W,  2'b01, 1'b1);
        chk_misaligned("lw  @2 misaligned",  `LS_W,  2'b10, 1'b1);
        chk_misaligned("lw  @3 misaligned",  `LS_W,  2'b11, 1'b1);

        //------------------------------------------------------------------
        // A misaligned store must not be allowed to reach memory.
        //------------------------------------------------------------------
        funct3 = `LS_W; addr_lsb = 2'b01; is_store = 1'b1; is_load = 1'b0; #1;
        chk("misaligned sw writes nothing", {28'b0, byte_en}, 32'd0);
        chk("misaligned sw flagged", {31'b0, misaligned}, 32'd1);

        funct3 = `LS_H; addr_lsb = 2'b11; #1;
        chk("misaligned sh writes nothing", {28'b0, byte_en}, 32'd0);

        //------------------------------------------------------------------
        // Byte enables must be idle whenever this is not a store.
        //------------------------------------------------------------------
        funct3 = `LS_W; addr_lsb = 2'b00; is_store = 1'b0; is_load = 1'b1; #1;
        chk("load drives no byte_en", {28'b0, byte_en}, 32'd0);

        is_load = 1'b0; is_store = 1'b0; #1;
        chk("idle drives no byte_en", {28'b0, byte_en}, 32'd0);

        funct3 = `LS_W; addr_lsb = 2'b11; #1;
        chk("idle never misaligned", {31'b0, misaligned}, 32'd0);

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
