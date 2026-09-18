//==========================================================================
// tb_reg_file.v - Self-checking testbench for reg_file.v
//==========================================================================

`default_nettype none
`timescale 1ns/1ps

module tb_reg_file;

    reg         clk;
    reg  [4:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] rd_data;
    reg         we;
    wire [31:0] rs1_data, rs2_data;

    integer checks;
    integer errors;

    reg_file dut (
        .clk_i      (clk),
        .rs1_addr_i (rs1_addr),
        .rs2_addr_i (rs2_addr),
        .rs1_data_o (rs1_data),
        .rs2_data_o (rs2_data),
        .we_i       (we),
        .rd_addr_i  (rd_addr),
        .rd_data_i  (rd_data)
    );

    always #5 clk = ~clk;

    task check;
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

    // One complete clocked write.
    task write_reg;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            we      = 1'b1;
            rd_addr = addr;
            rd_data = data;
            @(posedge clk);
            #1;
            we = 1'b0;
        end
    endtask

    initial begin
        clk      = 1'b0;
        we       = 1'b0;
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        rd_addr  = 5'd0;
        rd_data  = 32'b0;
        checks   = 0;
        errors   = 0;

        $dumpfile("sim/tb_reg_file.vcd");
        $dumpvars(0, tb_reg_file);

        $display("=== tb_reg_file ===");

        // ---- Registers start at zero ----
        rs1_addr = 5'd0;  rs2_addr = 5'd31; #1;
        check("x0 initially zero",  rs1_data, 32'h0000_0000);
        check("x31 initially zero", rs2_data, 32'h0000_0000);

        // ---- Basic write then read ----
        write_reg(5'd5, 32'hDEAD_BEEF);
        rs1_addr = 5'd5; #1;
        check("x5 holds written value", rs1_data, 32'hDEAD_BEEF);

        write_reg(5'd17, 32'h1234_5678);
        rs1_addr = 5'd17; #1;
        check("x17 holds written value", rs1_data, 32'h1234_5678);

        // ---- Writes must not disturb neighbours ----
        rs1_addr = 5'd5; rs2_addr = 5'd16; #1;
        check("x5 unchanged by x17 write", rs1_data, 32'hDEAD_BEEF);
        check("x16 still zero",            rs2_data, 32'h0000_0000);

        // ---- x0 is hardwired: writes to it are discarded ----
        write_reg(5'd0, 32'hFFFF_FFFF);
        rs1_addr = 5'd0; #1;
        check("x0 ignores writes", rs1_data, 32'h0000_0000);

        // ---- Both read ports work independently ----
        rs1_addr = 5'd5; rs2_addr = 5'd17; #1;
        check("port 1 reads x5",  rs1_data, 32'hDEAD_BEEF);
        check("port 2 reads x17", rs2_data, 32'h1234_5678);

        rs1_addr = 5'd17; rs2_addr = 5'd5; #1;
        check("ports swap cleanly A", rs1_data, 32'h1234_5678);
        check("ports swap cleanly B", rs2_data, 32'hDEAD_BEEF);

        // ---- Same register on both ports ----
        rs1_addr = 5'd5; rs2_addr = 5'd5; #1;
        check("same reg both ports A", rs1_data, 32'hDEAD_BEEF);
        check("same reg both ports B", rs2_data, 32'hDEAD_BEEF);

        // ---- Write-first bypass: read the value being written, in the
        //      same cycle, before the clock edge commits it. This is the
        //      writeback-to-decode path in the pipeline. ----
        @(negedge clk);
        we       = 1'b1;
        rd_addr  = 5'd9;
        rd_data  = 32'hCAFE_F00D;
        rs1_addr = 5'd9;
        rs2_addr = 5'd9;
        #1;
        check("bypass port 1 pre-edge", rs1_data, 32'hCAFE_F00D);
        check("bypass port 2 pre-edge", rs2_data, 32'hCAFE_F00D);
        @(posedge clk);
        #1;
        we = 1'b0;
        check("value committed after edge", rs1_data, 32'hCAFE_F00D);

        // ---- No bypass when write enable is low ----
        @(negedge clk);
        we       = 1'b0;
        rd_addr  = 5'd5;
        rd_data  = 32'hAAAA_AAAA;
        rs1_addr = 5'd5;
        #1;
        check("no bypass when we low", rs1_data, 32'hDEAD_BEEF);

        // ---- Bypass must never resurrect x0 ----
        @(negedge clk);
        we       = 1'b1;
        rd_addr  = 5'd0;
        rd_data  = 32'hBBBB_BBBB;
        rs1_addr = 5'd0;
        #1;
        check("x0 not bypassed", rs1_data, 32'h0000_0000);
        @(posedge clk);
        #1;
        we = 1'b0;

        $display("--- %0d checks, %0d failures", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
