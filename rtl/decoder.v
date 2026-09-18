//==========================================================================
// decoder.v - Instruction decode and control signal generation
//
// Purely combinational. Takes a 32-bit instruction and produces every
// control signal the datapath needs, plus an illegal-instruction flag.
//
// Two decisions worth calling out:
//
// 1. instr[30] is the ALU "alternate operation" bit, but it is only valid
//    for R-type instructions and for the two I-type SHIFTS. For every other
//    I-type instruction, bit 30 is part of the immediate. "addi x1, x2, -1"
//    has an immediate of 0xFFF, so instr[30] is 1 -- feeding that to the ALU
//    would silently turn the ADDI into a SUB. The alt bit is therefore
//    gated on the opcode and funct3.
//
// 2. Reserved encodings are reported through illegal_o rather than quietly
//    decoding as something else. An undefined instruction that behaves like
//    a NOP is a debugging nightmare; Phase 6 turns this flag into a trap.
//==========================================================================

`default_nettype none
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module decoder (
    input  wire [31:0]              instr_i,

    // Instruction fields
    output wire [4:0]               rs1_addr_o,
    output wire [4:0]               rs2_addr_o,
    output wire [4:0]               rd_addr_o,
    output wire [2:0]               funct3_o,

    // Datapath control
    output reg                      reg_write_o,
    output reg  [`ALU_OP_W-1:0]     alu_op_o,
    output reg                      alu_src_a_o,
    output reg                      alu_src_b_o,
    output reg  [`IMM_SEL_W-1:0]    imm_sel_o,
    output reg  [`WB_SEL_W-1:0]     wb_sel_o,

    // Memory
    output reg                      mem_read_o,
    output reg                      mem_write_o,

    // Control transfer
    output reg                      is_branch_o,
    output reg                      is_jump_o,
    output reg                      target_src_o,

    // System / exceptions
    output reg                      is_ecall_o,
    output reg                      is_ebreak_o,
    output reg                      illegal_o
);

    wire [6:0] opcode = instr_i[6:0];
    wire [2:0] funct3 = instr_i[14:12];
    wire [6:0] funct7 = instr_i[31:25];
    wire       alt    = instr_i[30];

    assign rs1_addr_o = instr_i[19:15];
    assign rs2_addr_o = instr_i[24:20];
    assign rd_addr_o  = instr_i[11:7];
    assign funct3_o   = funct3;

    // Shifts are the only I-type operations allowed to use the alt bit.
    wire is_shift_funct3 = (funct3 == 3'b001) || (funct3 == 3'b101);

    // funct7 patterns that are architecturally valid
    wire funct7_zero = (funct7 == 7'b0000000);
    wire funct7_alt  = (funct7 == 7'b0100000);

    always @(*) begin
        // Safe defaults: do nothing, touch nothing.
        reg_write_o  = 1'b0;
        alu_op_o     = `ALU_ADD;
        alu_src_a_o  = `SRC_A_RS1;
        alu_src_b_o  = `SRC_B_RS2;
        imm_sel_o    = `IMM_I;
        wb_sel_o     = `WB_ALU;
        mem_read_o   = 1'b0;
        mem_write_o  = 1'b0;
        is_branch_o  = 1'b0;
        is_jump_o    = 1'b0;
        target_src_o = `TGT_PC;
        is_ecall_o   = 1'b0;
        is_ebreak_o  = 1'b0;
        illegal_o    = 1'b0;

        case (opcode)

            //--------------------------------------------------------------
            // Register-register ALU:
            //   add sub sll slt sltu xor srl sra or and
            //--------------------------------------------------------------
            `OP_REG: begin
                reg_write_o = 1'b1;
                alu_src_a_o = `SRC_A_RS1;
                alu_src_b_o = `SRC_B_RS2;
                wb_sel_o    = `WB_ALU;
                alu_op_o    = {alt, funct3};

                // Only ADD/SUB and SRL/SRA may set the alt bit.
                if (is_shift_funct3 || (funct3 == 3'b000))
                    illegal_o = !(funct7_zero || funct7_alt);
                else
                    illegal_o = !funct7_zero;
            end

            //--------------------------------------------------------------
            // Register-immediate ALU:
            //   addi slti sltiu xori ori andi slli srli srai
            //--------------------------------------------------------------
            `OP_IMM: begin
                reg_write_o = 1'b1;
                alu_src_a_o = `SRC_A_RS1;
                alu_src_b_o = `SRC_B_IMM;
                imm_sel_o   = `IMM_I;
                wb_sel_o    = `WB_ALU;

                // For anything but a shift, bit 30 belongs to the immediate.
                alu_op_o = is_shift_funct3 ? {alt, funct3} : {1'b0, funct3};

                if (funct3 == 3'b001)              // slli
                    illegal_o = !funct7_zero;
                else if (funct3 == 3'b101)         // srli / srai
                    illegal_o = !(funct7_zero || funct7_alt);
            end

            //--------------------------------------------------------------
            // Loads: lb lh lw lbu lhu   (address = rs1 + imm)
            //--------------------------------------------------------------
            `OP_LOAD: begin
                reg_write_o = 1'b1;
                alu_op_o    = `ALU_ADD;
                alu_src_a_o = `SRC_A_RS1;
                alu_src_b_o = `SRC_B_IMM;
                imm_sel_o   = `IMM_I;
                wb_sel_o    = `WB_MEM;
                mem_read_o  = 1'b1;

                illegal_o = !((funct3 == `LS_B)  || (funct3 == `LS_H) ||
                              (funct3 == `LS_W)  || (funct3 == `LS_BU) ||
                              (funct3 == `LS_HU));
            end

            //--------------------------------------------------------------
            // Stores: sb sh sw   (address = rs1 + imm, data = rs2)
            //--------------------------------------------------------------
            `OP_STORE: begin
                alu_op_o    = `ALU_ADD;
                alu_src_a_o = `SRC_A_RS1;
                alu_src_b_o = `SRC_B_IMM;
                imm_sel_o   = `IMM_S;
                mem_write_o = 1'b1;

                illegal_o = !((funct3 == `LS_B) || (funct3 == `LS_H) ||
                              (funct3 == `LS_W));
            end

            //--------------------------------------------------------------
            // Branches. The ALU is not involved: branch_unit compares the
            // two register values directly.
            //--------------------------------------------------------------
            `OP_BRANCH: begin
                imm_sel_o    = `IMM_B;
                is_branch_o  = 1'b1;
                target_src_o = `TGT_PC;

                illegal_o = (funct3 == 3'b010) || (funct3 == 3'b011);
            end

            //--------------------------------------------------------------
            // JAL: jump to PC + imm, write PC + 4 to rd
            //--------------------------------------------------------------
            `OP_JAL: begin
                reg_write_o  = 1'b1;
                imm_sel_o    = `IMM_J;
                wb_sel_o     = `WB_PC4;
                is_jump_o    = 1'b1;
                target_src_o = `TGT_PC;
            end

            //--------------------------------------------------------------
            // JALR: jump to (rs1 + imm) with bit 0 cleared, write PC + 4.
            // This is what makes a function return possible.
            //--------------------------------------------------------------
            `OP_JALR: begin
                reg_write_o  = 1'b1;
                imm_sel_o    = `IMM_I;
                wb_sel_o     = `WB_PC4;
                is_jump_o    = 1'b1;
                target_src_o = `TGT_RS1;

                illegal_o = (funct3 != 3'b000);
            end

            //--------------------------------------------------------------
            // LUI: rd = imm. Routed through the ALU as a pass-through so
            // the writeback mux does not need a fourth source.
            //--------------------------------------------------------------
            `OP_LUI: begin
                reg_write_o = 1'b1;
                alu_op_o    = `ALU_PASS_B;
                alu_src_b_o = `SRC_B_IMM;
                imm_sel_o   = `IMM_U;
                wb_sel_o    = `WB_ALU;
            end

            //--------------------------------------------------------------
            // AUIPC: rd = PC + imm. Operand A is the PC, not rs1.
            //--------------------------------------------------------------
            `OP_AUIPC: begin
                reg_write_o = 1'b1;
                alu_op_o    = `ALU_ADD;
                alu_src_a_o = `SRC_A_PC;
                alu_src_b_o = `SRC_B_IMM;
                imm_sel_o   = `IMM_U;
                wb_sel_o    = `WB_ALU;
            end

            //--------------------------------------------------------------
            // FENCE. This core executes in order with no caches and no
            // store buffer, so a fence is architecturally a no-op.
            //--------------------------------------------------------------
            `OP_MISC_MEM: begin
                illegal_o = (funct3 != 3'b000);
            end

            //--------------------------------------------------------------
            // ECALL / EBREAK. Flagged here; trap handling arrives with the
            // Zicsr work in Phase 6.
            //--------------------------------------------------------------
            `OP_SYSTEM: begin
                if (instr_i == 32'h0000_0073)
                    is_ecall_o = 1'b1;
                else if (instr_i == 32'h0010_0073)
                    is_ebreak_o = 1'b1;
                else
                    illegal_o = 1'b1;
            end

            default: begin
                illegal_o = 1'b1;
            end

        endcase

        // An illegal instruction must have no architectural effect. Several
        // branches above assert reg_write or a memory enable before they
        // discover that the funct3/funct7 field is reserved, so the guard
        // goes here, once, covering every case -- rather than being repeated
        // (and eventually forgotten) inside each one.
        if (illegal_o) begin
            reg_write_o = 1'b0;
            mem_read_o  = 1'b0;
            mem_write_o = 1'b0;
            is_branch_o = 1'b0;
            is_jump_o   = 1'b0;
        end
    end

endmodule

`default_nettype wire
