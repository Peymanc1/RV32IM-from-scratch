// control_unit.sv
//
// Pure combinational. Maps opcode/funct3/funct7 to every datapath select.
// Defaults are NOP-safe — anything not handled produces no side effects.

import rv32im_pkg::*;

module control_unit (
    input  opcode_e    opcode_i,
    input  logic [2:0] funct3_i,
    input  logic [6:0] funct7_i,

    output logic       reg_we_o,
    output alu_a_sel_e alu_a_sel_o,
    output alu_b_sel_e alu_b_sel_o,
    output alu_op_e    alu_op_o,
    output imm_type_e  imm_type_o,
    output logic       mem_we_o,
    output logic       mem_re_o,
    output wb_sel_e    wb_sel_o,
    output logic       is_branch_o,
    output logic       is_jal_o,
    output logic       is_jalr_o,
    output branch_e    br_type_o,
    output logic       is_mdiv_o
);

    assign br_type_o = branch_e'(funct3_i);

    // M-extension is just R-type with funct7 = 0000001
    wire is_m_ext = (opcode_i == OP_RTYPE) && (funct7_i == 7'b0000001);
    assign is_mdiv_o = is_m_ext;

    always_comb begin
        // safe defaults (NOP)
        reg_we_o    = 1'b0;
        alu_a_sel_o = ALU_A_RS1;
        alu_b_sel_o = ALU_B_RS2;
        alu_op_o    = ALU_ADD;
        imm_type_o  = IMM_X;
        mem_we_o    = 1'b0;
        mem_re_o    = 1'b0;
        wb_sel_o    = WB_ALU;
        is_branch_o = 1'b0;
        is_jal_o    = 1'b0;
        is_jalr_o   = 1'b0;

        unique case (opcode_i)

            // R-type — ADD/SUB/shifts/logic, plus M-ext
            OP_RTYPE: begin
                reg_we_o = 1'b1;
                if (!is_m_ext) begin
                    unique case (funct3_i)
                        3'b000 : alu_op_o = funct7_i[5] ? ALU_SUB : ALU_ADD;
                        3'b001 : alu_op_o = ALU_SLL;
                        3'b010 : alu_op_o = ALU_SLT;
                        3'b011 : alu_op_o = ALU_SLTU;
                        3'b100 : alu_op_o = ALU_XOR;
                        3'b101 : alu_op_o = funct7_i[5] ? ALU_SRA : ALU_SRL;
                        3'b110 : alu_op_o = ALU_OR;
                        3'b111 : alu_op_o = ALU_AND;
                        default: alu_op_o = ALU_ADD;
                    endcase
                end
                // for M-ext, top steers wb_sel to mul_div output instead
            end

            // I-type ALU
            OP_ITYPE: begin
                reg_we_o    = 1'b1;
                alu_b_sel_o = ALU_B_IMM;
                imm_type_o  = IMM_I;
                unique case (funct3_i)
                    3'b000 : alu_op_o = ALU_ADD;     // ADDI
                    3'b010 : alu_op_o = ALU_SLT;     // SLTI
                    3'b011 : alu_op_o = ALU_SLTU;    // SLTIU
                    3'b100 : alu_op_o = ALU_XOR;     // XORI
                    3'b110 : alu_op_o = ALU_OR;      // ORI
                    3'b111 : alu_op_o = ALU_AND;     // ANDI
                    3'b001 : alu_op_o = ALU_SLL;     // SLLI
                    3'b101 : alu_op_o = funct7_i[5] ? ALU_SRA : ALU_SRL; // SRAI/SRLI
                    default: alu_op_o = ALU_ADD;
                endcase
            end

            OP_LOAD: begin
                reg_we_o    = 1'b1;
                alu_b_sel_o = ALU_B_IMM;
                imm_type_o  = IMM_I;
                mem_re_o    = 1'b1;
                wb_sel_o    = WB_MEM;
            end

            OP_STORE: begin
                alu_b_sel_o = ALU_B_IMM;
                imm_type_o  = IMM_S;
                mem_we_o    = 1'b1;
            end

            OP_BRANCH: begin
                alu_a_sel_o = ALU_A_PC;
                alu_b_sel_o = ALU_B_IMM;
                imm_type_o  = IMM_B;
                is_branch_o = 1'b1;
            end

            OP_JAL: begin
                reg_we_o    = 1'b1;
                alu_a_sel_o = ALU_A_PC;
                alu_b_sel_o = ALU_B_IMM;
                imm_type_o  = IMM_J;
                wb_sel_o    = WB_PC4;
                is_jal_o    = 1'b1;
            end

            OP_JALR: begin
                reg_we_o    = 1'b1;
                alu_b_sel_o = ALU_B_IMM;
                imm_type_o  = IMM_I;
                wb_sel_o    = WB_PC4;
                is_jalr_o   = 1'b1;
            end

            OP_LUI: begin
                reg_we_o    = 1'b1;
                alu_b_sel_o = ALU_B_IMM;
                alu_op_o    = ALU_PASSB;    // just pass imm through
                imm_type_o  = IMM_U;
            end

            OP_AUIPC: begin
                reg_we_o    = 1'b1;
                alu_a_sel_o = ALU_A_PC;
                alu_b_sel_o = ALU_B_IMM;
                imm_type_o  = IMM_U;
            end

            // FENCE and SYSTEM are NOPs for now. CSR/trap support comes later.
            OP_FENCE, OP_SYSTEM: ;

            default: ;
        endcase
    end

endmodule : control_unit
