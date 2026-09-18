//==========================================================================
// rv32i_core.v - Five stage pipelined RV32I core
//
//   IF   fetch the instruction at PC
//   ID   decode it, read the register file, build the immediate
//   EX   ALU, branch comparison, branch/jump target
//   MEM  data memory access with byte lane alignment
//   WB   write the result back to the register file
//
// The pipeline registers are written inline here rather than as separate
// modules. Each one is pure plumbing -- a module per register would mean
// four twenty-port instantiations, and every new signal would have to be
// threaded through three places instead of one. Real logic (hazards,
// decode, alignment) lives in its own module and is tested on its own.
//
// Branches and jumps resolve in EX, which costs two flushed instructions
// when one is taken. Resolving earlier is a Phase 4 optimisation, together
// with branch prediction.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module rv32i_core #(
    parameter [31:0]  RESET_ADDR = 32'h0000_0000,
    parameter integer IMEM_WORDS = 4096,
    parameter integer DMEM_WORDS = 4096,
    parameter         IMEM_INIT  = "",
    parameter         DMEM_INIT  = ""
) (
    input  wire        clk_i,
    input  wire        rst_i,          // synchronous, active high

    // UART transmit. One character per cycle that uart_valid_o is high.
    // On an FPGA this drives a real serial transmitter; in simulation the
    // testbench collects the bytes.
    output wire        uart_valid_o,
    output wire [7:0]  uart_data_o,

    // Performance counters. cycles and instret are 64 bits because that is
    // what mcycle and minstret are in the specification -- they become those
    // CSRs when Zicsr lands. The other two are not architectural; they exist
    // to show where the cycles went.
    output wire [63:0] perf_cycles_o,
    output wire [63:0] perf_instret_o,
    output wire [31:0] perf_stalls_o,      // cycles lost to load-use stalls
    output wire [31:0] perf_redirects_o,   // taken branches and jumps
    output wire [31:0] perf_branches_o,    // conditional branches executed
    output wire [31:0] perf_br_taken_o,    // of those, how many were taken

    // Trace outputs. Not part of the architecture; testbenches use these to
    // know when a program has finished and whether it executed cleanly.
    output wire [31:0] dbg_pc_o,
    output wire        dbg_ecall_o,
    output wire        dbg_illegal_o
);

    //======================================================================
    // Cross-stage control from the hazard unit
    //======================================================================
    wire              stall_if, stall_id, flush_id, flush_ex;
    wire [`FWD_W-1:0] fwd_a, fwd_b;

    //======================================================================
    // IF - instruction fetch
    //======================================================================
    reg  [31:0] if_pc;
    wire [31:0] if_pc_plus4 = if_pc + 32'd4;
    wire [31:0] if_instr;

    wire        ex_redirect;
    wire [31:0] ex_target;

    imem #(
        .WORDS     (IMEM_WORDS),
        .INIT_FILE (IMEM_INIT)
    ) u_imem (
        .addr_i  (if_pc),
        .instr_o (if_instr)
    );

    always @(posedge clk_i) begin
        if (rst_i)
            if_pc <= RESET_ADDR;
        else if (ex_redirect)
            if_pc <= ex_target;
        else if (!stall_if)
            if_pc <= if_pc_plus4;
    end

    //======================================================================
    // IF/ID pipeline register
    //
    // A flushed slot is filled with NOP, not with zero. The all-zero word
    // is not a no-op in RV32I -- opcode 0000000 is not defined, so a zeroed
    // slot would raise an illegal instruction on every taken branch.
    //======================================================================
    reg [31:0] id_pc, id_pc_plus4, id_instr;

    // Does this slot hold a real instruction? A flushed slot carries a NOP,
    // which is a perfectly valid instruction to execute but must not be
    // counted as one that retired -- the program never issued it. Without
    // this bit, instructions-retired would count the pipeline's own
    // bookkeeping and the CPI figure would be wrong in the flattering
    // direction.
    reg id_valid;

    always @(posedge clk_i) begin
        if (rst_i || flush_id) begin
            id_pc       <= 32'b0;
            id_pc_plus4 <= 32'b0;
            id_instr    <= `NOP;
            id_valid    <= 1'b0;
        end else if (!stall_id) begin
            id_pc       <= if_pc;
            id_pc_plus4 <= if_pc_plus4;
            id_instr    <= if_instr;
            id_valid    <= 1'b1;
        end
    end

    //======================================================================
    // ID - decode and register read
    //======================================================================
    wire [4:0]            id_rs1_addr, id_rs2_addr, id_rd_addr;
    wire [2:0]            id_funct3;
    wire                  id_uses_rs1, id_uses_rs2;
    wire                  id_reg_write;
    wire [`ALU_OP_W-1:0]  id_alu_op;
    wire                  id_alu_src_a, id_alu_src_b;
    wire [`IMM_SEL_W-1:0] id_imm_sel;
    wire [`WB_SEL_W-1:0]  id_wb_sel;
    wire                  id_mem_read, id_mem_write;
    wire                  id_is_branch, id_is_jump, id_target_src;
    wire                  id_is_ecall, id_is_ebreak, id_illegal;

    decoder u_decoder (
        .instr_i      (id_instr),
        .rs1_addr_o   (id_rs1_addr),
        .rs2_addr_o   (id_rs2_addr),
        .rd_addr_o    (id_rd_addr),
        .funct3_o     (id_funct3),
        .uses_rs1_o   (id_uses_rs1),
        .uses_rs2_o   (id_uses_rs2),
        .reg_write_o  (id_reg_write),
        .alu_op_o     (id_alu_op),
        .alu_src_a_o  (id_alu_src_a),
        .alu_src_b_o  (id_alu_src_b),
        .imm_sel_o    (id_imm_sel),
        .wb_sel_o     (id_wb_sel),
        .mem_read_o   (id_mem_read),
        .mem_write_o  (id_mem_write),
        .is_branch_o  (id_is_branch),
        .is_jump_o    (id_is_jump),
        .target_src_o (id_target_src),
        .is_ecall_o   (id_is_ecall),
        .is_ebreak_o  (id_is_ebreak),
        .illegal_o    (id_illegal)
    );

    wire [31:0] id_imm;

    imm_gen u_imm_gen (
        .instr_i (id_instr),
        .sel_i   (id_imm_sel),
        .imm_o   (id_imm)
    );

    wire [31:0] id_rs1_data, id_rs2_data;
    wire [4:0]  wb_rd_addr;
    wire        wb_reg_write;
    wire [31:0] wb_data;

    reg_file u_reg_file (
        .clk_i      (clk_i),
        .rs1_addr_i (id_rs1_addr),
        .rs2_addr_i (id_rs2_addr),
        .rs1_data_o (id_rs1_data),
        .rs2_data_o (id_rs2_data),
        .we_i       (wb_reg_write),
        .rd_addr_i  (wb_rd_addr),
        .rd_data_i  (wb_data)
    );

    //======================================================================
    // ID/EX pipeline register
    //
    // A flush produces a bubble: every side-effecting control is cleared
    // and rd is forced to x0 so the hazard unit cannot match on it.
    //======================================================================
    reg [31:0]            ex_pc, ex_pc_plus4, ex_rs1_data, ex_rs2_data, ex_imm;
    reg [4:0]             ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    reg [2:0]             ex_funct3;
    reg                   ex_reg_write;
    reg [`ALU_OP_W-1:0]   ex_alu_op;
    reg                   ex_alu_src_a, ex_alu_src_b;
    reg [`WB_SEL_W-1:0]   ex_wb_sel;
    reg                   ex_mem_read, ex_mem_write;
    reg                   ex_is_branch, ex_is_jump, ex_target_src;
    reg                   ex_is_ecall, ex_illegal;
    reg                   ex_valid;

    always @(posedge clk_i) begin
        if (rst_i || flush_ex) begin
            ex_pc         <= 32'b0;
            ex_pc_plus4   <= 32'b0;
            ex_rs1_data   <= 32'b0;
            ex_rs2_data   <= 32'b0;
            ex_imm        <= 32'b0;
            ex_rs1_addr   <= 5'd0;
            ex_rs2_addr   <= 5'd0;
            ex_rd_addr    <= 5'd0;
            ex_funct3     <= 3'b000;
            ex_reg_write  <= 1'b0;
            ex_alu_op     <= `ALU_ADD;
            ex_alu_src_a  <= `SRC_A_RS1;
            ex_alu_src_b  <= `SRC_B_RS2;
            ex_wb_sel     <= `WB_ALU;
            ex_mem_read   <= 1'b0;
            ex_mem_write  <= 1'b0;
            ex_is_branch  <= 1'b0;
            ex_is_jump    <= 1'b0;
            ex_target_src <= `TGT_PC;
            ex_is_ecall   <= 1'b0;
            ex_illegal    <= 1'b0;
            ex_valid      <= 1'b0;
        end else begin
            ex_pc         <= id_pc;
            ex_pc_plus4   <= id_pc_plus4;
            ex_rs1_data   <= id_rs1_data;
            ex_rs2_data   <= id_rs2_data;
            ex_imm        <= id_imm;
            ex_rs1_addr   <= id_rs1_addr;
            ex_rs2_addr   <= id_rs2_addr;
            ex_rd_addr    <= id_rd_addr;
            ex_funct3     <= id_funct3;
            ex_reg_write  <= id_reg_write;
            ex_alu_op     <= id_alu_op;
            ex_alu_src_a  <= id_alu_src_a;
            ex_alu_src_b  <= id_alu_src_b;
            ex_wb_sel     <= id_wb_sel;
            ex_mem_read   <= id_mem_read;
            ex_mem_write  <= id_mem_write;
            ex_is_branch  <= id_is_branch;
            ex_is_jump    <= id_is_jump;
            ex_target_src <= id_target_src;
            ex_is_ecall   <= id_is_ecall;
            ex_illegal    <= id_illegal;
            ex_valid      <= id_valid;
        end
    end

    //======================================================================
    // EX - execute
    //======================================================================
    wire [31:0] mem_fwd_value;

    // Forwarding muxes. These feed the ALU, the branch comparator, the JALR
    // target adder and the store data path, so every consumer of a register
    // value in EX sees the same forwarded result.
    reg [31:0] ex_fwd_a, ex_fwd_b;

    always @(*) begin
        case (fwd_a)
            `FWD_MEM : ex_fwd_a = mem_fwd_value;
            `FWD_WB  : ex_fwd_a = wb_data;
            default  : ex_fwd_a = ex_rs1_data;
        endcase
    end

    always @(*) begin
        case (fwd_b)
            `FWD_MEM : ex_fwd_b = mem_fwd_value;
            `FWD_WB  : ex_fwd_b = wb_data;
            default  : ex_fwd_b = ex_rs2_data;
        endcase
    end

    wire [31:0] ex_alu_a = (ex_alu_src_a == `SRC_A_PC)  ? ex_pc  : ex_fwd_a;
    wire [31:0] ex_alu_b = (ex_alu_src_b == `SRC_B_IMM) ? ex_imm : ex_fwd_b;
    wire [31:0] ex_alu_result;

    alu u_alu (
        .a_i      (ex_alu_a),
        .b_i      (ex_alu_b),
        .op_i     (ex_alu_op),
        .result_o (ex_alu_result)
    );

    wire ex_branch_taken;

    branch_unit u_branch_unit (
        .rs1_data_i    (ex_fwd_a),
        .rs2_data_i    (ex_fwd_b),
        .funct3_i      (ex_funct3),
        .is_branch_i   (ex_is_branch),
        .take_branch_o (ex_branch_taken)
    );

    // JALR clears bit 0 of the computed target. The specification requires
    // it, and it is what makes "jalr x0, 0(x1)" a safe return even if the
    // link register picked up an odd value.
    wire [31:0] ex_target_pc   = ex_pc + ex_imm;
    wire [31:0] ex_target_jalr = (ex_fwd_a + ex_imm) & ~32'd1;

    assign ex_target   = (ex_target_src == `TGT_RS1) ? ex_target_jalr
                                                     : ex_target_pc;
    assign ex_redirect = ex_is_jump || ex_branch_taken;

    //======================================================================
    // EX/MEM pipeline register
    //======================================================================
    reg [31:0]          mem_alu_result, mem_store_data, mem_pc_plus4;
    reg [4:0]           mem_rd_addr;
    reg [2:0]           mem_funct3;
    reg                 mem_reg_write;
    reg [`WB_SEL_W-1:0] mem_wb_sel;
    reg                 mem_mem_read, mem_mem_write;
    reg                 mem_is_ecall, mem_illegal;
    reg                 mem_valid;

    always @(posedge clk_i) begin
        if (rst_i) begin
            mem_alu_result <= 32'b0;
            mem_store_data <= 32'b0;
            mem_pc_plus4   <= 32'b0;
            mem_rd_addr    <= 5'd0;
            mem_funct3     <= 3'b000;
            mem_reg_write  <= 1'b0;
            mem_wb_sel     <= `WB_ALU;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_is_ecall   <= 1'b0;
            mem_illegal    <= 1'b0;
            mem_valid      <= 1'b0;
        end else begin
            mem_alu_result <= ex_alu_result;
            mem_store_data <= ex_fwd_b;       // forwarded, not the stale read
            mem_pc_plus4   <= ex_pc_plus4;
            mem_rd_addr    <= ex_rd_addr;
            mem_funct3     <= ex_funct3;
            mem_reg_write  <= ex_reg_write;
            mem_wb_sel     <= ex_wb_sel;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_is_ecall   <= ex_is_ecall;
            mem_illegal    <= ex_illegal;
            mem_valid      <= ex_valid;
        end
    end

    //======================================================================
    // MEM - data memory and peripherals
    //
    // Address decode, such as it is: anything in 0x1xxx_xxxx is peripheral
    // space, everything else is data memory. One comparator on four bits is
    // enough while there is exactly one peripheral; a real bus arrives when
    // there is a second one.
    //======================================================================
    wire [3:0]  mem_byte_en;
    wire [31:0] mem_store_word, mem_load_data;
    wire        mem_misaligned;

    wire mem_is_periph = (mem_alu_result[31:28] == 4'h1);

    lsu u_lsu (
        .funct3_i     (mem_funct3),
        .addr_lsb_i   (mem_alu_result[1:0]),
        .is_load_i    (mem_mem_read),
        .is_store_i   (mem_mem_write),
        .store_data_i (mem_store_data),
        .byte_en_o    (mem_byte_en),
        .store_word_o (mem_store_word),
        .load_word_i  (mem_raw_rdata),
        .load_data_o  (mem_load_data),
        .misaligned_o (mem_misaligned)
    );

    // A store to peripheral space must not also land in memory.
    wire [3:0]  dmem_byte_en = mem_is_periph ? 4'b0000 : mem_byte_en;
    wire [31:0] dmem_rdata;

    dmem #(
        .WORDS     (DMEM_WORDS),
        .INIT_FILE (DMEM_INIT)
    ) u_dmem (
        .clk_i     (clk_i),
        .addr_i    (mem_alu_result),
        .wdata_i   (mem_store_word),
        .byte_en_i (dmem_byte_en),
        .rdata_o   (dmem_rdata)
    );

    //----------------------------------------------------------------------
    // UART, memory mapped at 0x1000_0000:
    //
    //   +0  transmit, write only  -- the low byte is sent
    //   +4  status,   read only   -- bit 0 set means ready to transmit
    //
    // The status register is always ready. Software still polls it, because
    // that is what a driver for real hardware has to do, and the register
    // has to exist for that code to be written against.
    //----------------------------------------------------------------------
    wire uart_tx_sel     = mem_is_periph && (mem_alu_result[7:0] == 8'h00);
    wire uart_status_sel = mem_is_periph && (mem_alu_result[7:0] == 8'h04);

    // byte_en is already zero for a misaligned store, so a bad address
    // cannot transmit a character either.
    assign uart_valid_o = mem_mem_write && uart_tx_sel && (mem_byte_en != 4'b0);
    assign uart_data_o  = mem_store_data[7:0];

    wire [31:0] periph_rdata = uart_status_sel ? 32'h0000_0001 : 32'h0000_0000;
    wire [31:0] mem_raw_rdata = mem_is_periph ? periph_rdata : dmem_rdata;

    // The value this instruction will write back.
    wire [31:0] mem_result = (mem_wb_sel == `WB_MEM) ? mem_load_data  :
                             (mem_wb_sel == `WB_PC4) ? mem_pc_plus4   :
                                                       mem_alu_result;

    // What MEM offers to the forwarding network deliberately excludes load
    // data. Forwarding a load result from here would run memory output ->
    // mux -> ALU inside one cycle, which would dominate the critical path,
    // and the path disappears entirely once the memory becomes a
    // synchronous block RAM in Phase 5. The load-use stall guarantees the
    // case never arises: a dependent instruction cannot reach EX while the
    // load it depends on is still in MEM.
    assign mem_fwd_value = (mem_wb_sel == `WB_PC4) ? mem_pc_plus4
                                                   : mem_alu_result;

    //======================================================================
    // MEM/WB pipeline register
    //======================================================================
    reg [31:0] wb_data_r;
    reg [4:0]  wb_rd_addr_r;
    reg        wb_reg_write_r;
    reg        wb_is_ecall_r, wb_illegal_r;
    reg        wb_valid_r;

    always @(posedge clk_i) begin
        if (rst_i) begin
            wb_data_r      <= 32'b0;
            wb_rd_addr_r   <= 5'd0;
            wb_reg_write_r <= 1'b0;
            wb_is_ecall_r  <= 1'b0;
            wb_illegal_r   <= 1'b0;
            wb_valid_r     <= 1'b0;
        end else begin
            wb_data_r      <= mem_result;
            wb_rd_addr_r   <= mem_rd_addr;
            wb_reg_write_r <= mem_reg_write;
            wb_is_ecall_r  <= mem_is_ecall;
            wb_illegal_r   <= mem_illegal;
            wb_valid_r     <= mem_valid;
        end
    end

    //======================================================================
    // WB - writeback
    //======================================================================
    assign wb_data      = wb_data_r;
    assign wb_rd_addr   = wb_rd_addr_r;
    assign wb_reg_write = wb_reg_write_r;

    //======================================================================
    // Hazard control
    //======================================================================
    hazard_unit u_hazard_unit (
        .id_rs1_addr_i   (id_rs1_addr),
        .id_rs2_addr_i   (id_rs2_addr),
        .id_uses_rs1_i   (id_uses_rs1),
        .id_uses_rs2_i   (id_uses_rs2),
        .ex_rs1_addr_i   (ex_rs1_addr),
        .ex_rs2_addr_i   (ex_rs2_addr),
        .ex_rd_addr_i    (ex_rd_addr),
        .ex_mem_read_i   (ex_mem_read),
        .mem_rd_addr_i   (mem_rd_addr),
        .mem_reg_write_i (mem_reg_write),
        .wb_rd_addr_i    (wb_rd_addr),
        .wb_reg_write_i  (wb_reg_write),
        .pc_redirect_i   (ex_redirect),
        .stall_if_o      (stall_if),
        .stall_id_o      (stall_id),
        .flush_id_o      (flush_id),
        .flush_ex_o      (flush_ex),
        .fwd_a_o         (fwd_a),
        .fwd_b_o         (fwd_b)
    );

    //======================================================================
    // Performance counters
    //
    // Cycles and retired instructions are the two numbers CPI is computed
    // from. The other three say where the difference went: a cycle that
    // retires nothing was either a stall or part of a branch's shadow.
    //
    // Counting retirement in WB rather than issue in IF matters. An
    // instruction that is fetched and then flushed never retires, so it
    // must not be counted -- otherwise the wasted work disappears from the
    // measurement and CPI comes out looking better than the core is.
    //======================================================================
    reg [63:0] perf_cycles;
    reg [63:0] perf_instret;
    reg [31:0] perf_stalls;
    reg [31:0] perf_redirects;
    reg [31:0] perf_branches;
    reg [31:0] perf_br_taken;

    always @(posedge clk_i) begin
        if (rst_i) begin
            perf_cycles    <= 64'b0;
            perf_instret   <= 64'b0;
            perf_stalls    <= 32'b0;
            perf_redirects <= 32'b0;
            perf_branches  <= 32'b0;
            perf_br_taken  <= 32'b0;
        end else begin
            perf_cycles <= perf_cycles + 64'd1;

            if (wb_valid_r) begin
                perf_instret <= perf_instret + 64'd1;
            end

            // One cycle of the pipeline held still.
            if (stall_if) begin
                perf_stalls <= perf_stalls + 32'd1;
            end

            // A taken branch or a jump. Each one costs two flushed
            // instructions, so this number times two is the control-flow
            // penalty in cycles.
            if (ex_redirect) begin
                perf_redirects <= perf_redirects + 32'd1;
            end

            // Every conditional branch reaching EX, taken or not, and how
            // many of those were taken. The taken rate is the baseline a
            // branch predictor has to beat -- always-not-taken is what this
            // core effectively does today.
            //
            // Counted separately from perf_redirects because that one also
            // includes jumps, which are unconditional and have nothing to
            // predict.
            if (ex_valid && ex_is_branch) begin
                perf_branches <= perf_branches + 32'd1;
                if (ex_branch_taken) begin
                    perf_br_taken <= perf_br_taken + 32'd1;
                end
            end
        end
    end

    assign perf_cycles_o    = perf_cycles;
    assign perf_instret_o   = perf_instret;
    assign perf_stalls_o    = perf_stalls;
    assign perf_redirects_o = perf_redirects;
    assign perf_branches_o  = perf_branches;
    assign perf_br_taken_o  = perf_br_taken;

    //======================================================================
    // Trace
    //======================================================================
    assign dbg_pc_o      = if_pc;
    assign dbg_ecall_o   = wb_is_ecall_r;
    assign dbg_illegal_o = wb_illegal_r;

endmodule

`default_nettype wire
