// immgen.sv  -  immediate generator
//
// Stitches the immediate field for each format and sign-extends to 32 bits.
// Reference: unprivileged ISA spec, Fig 2.4.
//
// B and J formats are the painful ones — bits scattered across the instruction
// to share signals with R/I/S formats. We pay for that here.

import rv32im_pkg::*;

module immgen (
    input  logic [INST_W-1:0] inst_i,
    input  imm_type_e         imm_type_i,
    output logic [XLEN-1:0]   imm_o
);

    logic [XLEN-1:0] imm_i_type, imm_s_type, imm_b_type, imm_u_type, imm_j_type;

    // I-type:  [31:20] sign-extended.   ADDI, LOAD, JALR...
    assign imm_i_type = {{20{inst_i[31]}}, inst_i[31:20]};

    // S-type:  [31:25] || [11:7].       STORE
    assign imm_s_type = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};

    // B-type:  bit 0 = 0 (2-byte aligned branch targets)
    assign imm_b_type = {{19{inst_i[31]}}, inst_i[31], inst_i[7],
                         inst_i[30:25], inst_i[11:8], 1'b0};

    // U-type:  upper 20 bits, low 12 = 0.   LUI, AUIPC
    assign imm_u_type = {inst_i[31:12], 12'b0};

    // J-type:  bit 0 = 0.   JAL
    assign imm_j_type = {{11{inst_i[31]}}, inst_i[31], inst_i[19:12],
                         inst_i[20], inst_i[30:21], 1'b0};

    always_comb begin
        unique case (imm_type_i)
            IMM_I  : imm_o = imm_i_type;
            IMM_S  : imm_o = imm_s_type;
            IMM_B  : imm_o = imm_b_type;
            IMM_U  : imm_o = imm_u_type;
            IMM_J  : imm_o = imm_j_type;
            default: imm_o = 32'd0;
        endcase
    end

endmodule : immgen
