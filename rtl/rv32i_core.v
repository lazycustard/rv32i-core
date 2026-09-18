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
// Branches and jumps resolve in EX. Fetch guesses the path with a branch
// predictor and EX checks the guess, so a taken branch costs nothing when
// predicted correctly and two flushed instructions when it is not.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module rv32i_core #(
    parameter [31:0]  RESET_ADDR = 32'h0000_0000,
    parameter integer IMEM_WORDS = 4096,
    parameter integer DMEM_WORDS = 4096,
    parameter         IMEM_INIT  = "",
    parameter integer BP_ENTRIES = 64,
    parameter integer BP_ENABLE  = 1,   // 0 reproduces the always-not-taken baseline
    parameter integer RAS_DEPTH  = 8,
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
    output wire [31:0] perf_mispredicts_o, // wrong guesses: 2 cycles each
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

    wire        ex_mispredict;
    wire [31:0] ex_correct_pc;

    imem #(
        .WORDS     (IMEM_WORDS),
        .INIT_FILE (IMEM_INIT)
    ) u_imem (
        .addr_i  (if_pc),
        .instr_o (if_instr)
    );

    //----------------------------------------------------------------------
    // Branch prediction happens here, before the instruction has even been
    // decoded. That is the point: by the time EX knows this is a branch and
    // where it goes, two later instructions have already been fetched.
    //
    // A prediction is a guess about the fetch path, never about results.
    // EX checks every one of them, so a wrong guess costs the same two
    // cycles the core paid unconditionally before -- and a right one costs
    // nothing.
    //----------------------------------------------------------------------
    wire        bp_predict_taken;
    wire        if_predict_taken;
    wire [31:0] bp_predict_target;
    wire [31:0] if_predict_target;
    wire        bp_update;
    wire        bp_update_taken;
    wire [31:0] bp_update_pc, bp_update_target;

    branch_predictor #(
        .ENTRIES (BP_ENTRIES)
    ) u_branch_predictor (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .pc_i             (if_pc),
        .predict_taken_o  (bp_predict_taken),
        .predict_target_o (bp_predict_target),
        .update_valid_i   (bp_update),
        .update_pc_i      (bp_update_pc),
        .update_taken_i   (bp_update_taken),
        .update_target_i  (bp_update_target)
    );

    //----------------------------------------------------------------------
    // Return address stack.
    //
    // The BTB holds one target per PC, which is right for a loop and wrong
    // for a function return: the same "ret" instruction goes back to
    // whichever call site invoked it. The stack predicts returns from
    // structure instead of history -- a call pushes where it will come
    // back to, and a return pops it.
    //
    // Reading the instruction here, in fetch, is only possible because the
    // instruction memory answers combinationally. Once it becomes a
    // synchronous block RAM in Phase 5 the instruction arrives a cycle
    // later and these two bits will have to be predecoded and stored
    // alongside it.
    //----------------------------------------------------------------------
    wire if_is_call, if_is_ret;

    call_ret_hint u_if_hint (
        .instr_i   (if_instr),
        .is_call_o (if_is_call),
        .is_ret_o  (if_is_ret)
    );

    wire        ras_push, ras_pop, ras_valid;
    wire [31:0] ras_top, ras_push_addr;

    ras #(
        .DEPTH (RAS_DEPTH)
    ) u_ras (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .push_i      (ras_push),
        .push_addr_i (ras_push_addr),
        .pop_i       (ras_pop),
        .top_o       (ras_top),
        .valid_o     (ras_valid)
    );

    // The stack wins over the BTB for returns, and only for returns. An
    // empty stack falls back to whatever the BTB remembers.
    wire use_ras = if_is_ret && ras_valid;

    // Setting BP_ENABLE to 0 pins the prediction to not-taken, which is
    // exactly what the core did before the predictor existed. The baseline
    // the speedup is measured against is therefore reproducible rather than
    // remembered.
    assign if_predict_taken  = (BP_ENABLE != 0) && (use_ras || bp_predict_taken);
    assign if_predict_target = use_ras ? ras_top : bp_predict_target;

    always @(posedge clk_i) begin
        if (rst_i)
            if_pc <= RESET_ADDR;
        else if (ex_mispredict)
            if_pc <= ex_correct_pc;     // EX found the fetch path was wrong
        else if (!stall_if)
            if_pc <= if_predict_taken ? if_predict_target : if_pc_plus4;
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

    // The guess made when this instruction was fetched, carried alongside it
    // so EX can check it against what actually happens.
    reg        id_predict_taken;
    reg [31:0] id_predict_target;

    always @(posedge clk_i) begin
        if (rst_i || flush_id) begin
            id_pc       <= 32'b0;
            id_pc_plus4 <= 32'b0;
            id_instr    <= `NOP;
            id_valid    <= 1'b0;
            id_predict_taken  <= 1'b0;
            id_predict_target <= 32'b0;
        end else if (!stall_id) begin
            id_pc       <= if_pc;
            id_pc_plus4 <= if_pc_plus4;
            id_instr    <= if_instr;
            id_valid    <= 1'b1;
            id_predict_taken  <= if_predict_taken;
            id_predict_target <= if_predict_target;
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

    // The same hint logic as in fetch, on this stage's instruction, so EX
    // can update the stack it predicted from.
    wire id_is_call, id_is_ret;

    call_ret_hint u_id_hint (
        .instr_i   (id_instr),
        .is_call_o (id_is_call),
        .is_ret_o  (id_is_ret)
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
    reg                   ex_predict_taken;
    reg [31:0]            ex_predict_target;
    reg                   ex_is_call, ex_is_ret;

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
            ex_predict_taken  <= 1'b0;
            ex_predict_target <= 32'b0;
            ex_is_call        <= 1'b0;
            ex_is_ret         <= 1'b0;
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
            ex_predict_taken  <= id_predict_taken;
            ex_predict_target <= id_predict_target;
            ex_is_call        <= id_is_call;
            ex_is_ret         <= id_is_ret;
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

    wire [31:0] ex_actual_target = (ex_target_src == `TGT_RS1) ? ex_target_jalr
                                                               : ex_target_pc;
    wire        ex_actual_taken  = ex_is_jump || ex_branch_taken;

    //----------------------------------------------------------------------
    // Check the fetch stage's guess.
    //
    // Two ways to be wrong, and both matter:
    //   - the direction was wrong, taken either way round;
    //   - the direction was right but the address was not, which is how an
    //     indirect jump through a changed register goes astray.
    //
    // The second case also catches a prediction made for an instruction
    // that turns out not to be a branch at all -- two unrelated PCs can
    // collide in the BTB, and then a plain ADD is fetched down a jump
    // target. It resolves here as predicted-taken against actually-not,
    // and the pipeline is put back on PC+4.
    //----------------------------------------------------------------------
    assign ex_mispredict = ex_valid &&
        ((ex_actual_taken != ex_predict_taken) ||
         (ex_actual_taken && (ex_actual_target != ex_predict_target)));

    assign ex_correct_pc = ex_actual_taken ? ex_actual_target : ex_pc_plus4;

    // Teach the predictor, whether it guessed right or wrong: a correct
    // prediction still needs its counter pushed further towards confidence.
    assign bp_update        = ex_valid && (ex_is_branch || ex_is_jump);
    assign bp_update_pc     = ex_pc;
    assign bp_update_taken  = ex_actual_taken;
    assign bp_update_target = ex_actual_target;

    // Maintain the return stack. Guarded by ex_valid so a flushed
    // instruction cannot push or pop -- a corrupted stack would mispredict
    // every return above it, not just its own.
    //----------------------------------------------------------------------
    // The return stack is updated in fetch, speculatively, not in EX when
    // the instruction is known to be real.
    //
    // It has to be. Unwinding a recursion is a run of returns with only an
    // instruction or two between them, so a second return is fetched before
    // the first has reached EX. Updating in EX means that second return
    // reads a top of stack that is one entry stale. Measured on the primes
    // program, moving the update to fetch removed 88 mispredictions.
    //
    // The cost is that a mispredicted path can push or pop entries that
    // should never have existed, and there is no checkpoint to restore
    // from -- so after a misprediction the stack can be left misaligned and
    // some later returns predict wrongly. That is an accuracy loss and
    // nothing more: EX checks every prediction, so a drifted stack can
    // never produce a wrong result, only a slower one. A real recovery
    // mechanism would snapshot the stack pointer per in-flight branch.
    //----------------------------------------------------------------------
    assign ras_push      = if_is_call && !stall_if && !ex_mispredict;
    assign ras_pop       = use_ras    && !stall_if && !ex_mispredict;
    assign ras_push_addr = if_pc_plus4;

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
        .pc_redirect_i   (ex_mispredict),
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
    reg [31:0] perf_mispredicts;
    reg [31:0] perf_branches;
    reg [31:0] perf_br_taken;

    always @(posedge clk_i) begin
        if (rst_i) begin
            perf_cycles    <= 64'b0;
            perf_instret   <= 64'b0;
            perf_stalls    <= 32'b0;
            perf_mispredicts <= 32'b0;
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

            // A wrong guess about the fetch path. Each one costs two
            // flushed instructions, so this number times two is the
            // control-flow penalty in cycles. A correct prediction, taken
            // or not, costs nothing and is not counted here.
            if (ex_mispredict) begin
                perf_mispredicts <= perf_mispredicts + 32'd1;
            end

            // Every conditional branch reaching EX, taken or not, and how
            // many of those were taken. The taken rate is the baseline a
            // branch predictor has to beat -- always-not-taken is what this
            // core effectively does today.
            //
            // Counted separately from perf_mispredicts because that one also
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
    assign perf_mispredicts_o = perf_mispredicts;
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
