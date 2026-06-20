// rv32im_core.sv  -  single-cycle RV32IM
//
// One instruction completes per clock. Long critical path; really only useful
// as a teaching baseline and a reference for the pipelined version.
//
// IMEM and DMEM are external to keep this module testbench-friendly.

import rv32im_pkg::*;

module rv32im_core (
    input  logic              clk,
    input  logic              rst_n,

    // imem
    output logic [XLEN-1:0]   imem_addr_o,
    input  logic [INST_W-1:0] imem_data_i,

    // dmem
    output logic [XLEN-1:0]   dmem_addr_o,
    output logic              dmem_we_o,
    output logic              dmem_re_o,
    output logic [2:0]        dmem_funct3_o,
    output logic [XLEN-1:0]   dmem_wdata_o,
    input  logic [XLEN-1:0]   dmem_rdata_i
);

    // ---- nets ----
    logic [XLEN-1:0] pc_cur, pc_plus4;
    pc_sel_e         pc_sel;
    logic [XLEN-1:0] branch_target, jalr_target;
    logic            stall;

    opcode_e             opcode;
    logic [REG_ADDR-1:0] rd_addr, rs1_addr, rs2_addr;
    logic [2:0]          funct3;
    logic [6:0]          funct7;

    logic [XLEN-1:0] rs1_data, rs2_data, rd_data;
    logic            reg_we;

    imm_type_e       imm_type;
    logic [XLEN-1:0] imm;

    alu_a_sel_e      alu_a_sel;
    alu_b_sel_e      alu_b_sel;
    alu_op_e         alu_op;
    logic [XLEN-1:0] alu_a, alu_b, alu_result;
    logic            alu_zero;

    logic            mdiv_start, mdiv_busy, mdiv_done;
    logic [XLEN-1:0] mdiv_result;
    logic            is_mdiv;

    logic            is_branch, is_jal, is_jalr;
    branch_e         br_type;
    logic            br_taken;

    logic            mem_we, mem_re;
    wb_sel_e         wb_sel;

    // ---- modules ----

    pc u_pc (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall_i         (stall),
        .pc_sel_i        (pc_sel),
        .branch_target_i (branch_target),
        .jalr_target_i   (jalr_target),
        .pc_o            (pc_cur),
        .pc_plus4_o      (pc_plus4)
    );

    assign imem_addr_o = pc_cur;

    decoder u_decoder (
        .inst_i   (imem_data_i),
        .opcode_o (opcode),
        .rd_o     (rd_addr),
        .rs1_o    (rs1_addr),
        .rs2_o    (rs2_addr),
        .funct3_o (funct3),
        .funct7_o (funct7)
    );

    control_unit u_ctrl (
        .opcode_i    (opcode),
        .funct3_i    (funct3),
        .funct7_i    (funct7),
        .reg_we_o    (reg_we),
        .alu_a_sel_o (alu_a_sel),
        .alu_b_sel_o (alu_b_sel),
        .alu_op_o    (alu_op),
        .imm_type_o  (imm_type),
        .mem_we_o    (mem_we),
        .mem_re_o    (mem_re),
        .wb_sel_o    (wb_sel),
        .is_branch_o (is_branch),
        .is_jal_o    (is_jal),
        .is_jalr_o   (is_jalr),
        .br_type_o   (br_type),
        .is_mdiv_o   (is_mdiv)
    );

    // gate reg writes during multi-cycle MDIV — we only commit on the done
    // pulse, otherwise we'd write garbage every busy cycle.
    wire reg_we_gated = reg_we && !mdiv_busy && (!is_mdiv || mdiv_done);

    regfile u_regfile (
        .clk        (clk),
        .rst_n      (rst_n),
        .rs1_addr_i (rs1_addr),
        .rs1_data_o (rs1_data),
        .rs2_addr_i (rs2_addr),
        .rs2_data_o (rs2_data),
        .we_i       (reg_we_gated),
        .rd_addr_i  (rd_addr),
        .rd_data_i  (rd_data)
    );

    immgen u_immgen (
        .inst_i     (imem_data_i),
        .imm_type_i (imm_type),
        .imm_o      (imm)
    );

    // ALU input muxes
    assign alu_a = (alu_a_sel == ALU_A_PC)  ? pc_cur   : rs1_data;
    assign alu_b = (alu_b_sel == ALU_B_IMM) ? imm      : rs2_data;

    alu u_alu (
        .operand_a_i (alu_a),
        .operand_b_i (alu_b),
        .alu_op_i    (alu_op),
        .result_o    (alu_result),
        .zero_o      (alu_zero)
    );

    assign mdiv_start = is_mdiv;
    mul_div u_mul_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (mdiv_start),
        .funct3_i    (funct3),
        .operand_a_i (rs1_data),
        .operand_b_i (rs2_data),
        .result_o    (mdiv_result),
        .busy_o      (mdiv_busy),
        .done_o      (mdiv_done)
    );

    branch_unit u_branch (
        .rs1_i     (rs1_data),
        .rs2_i     (rs2_data),
        .br_type_i (br_type),
        .taken_o   (br_taken)
    );

    // We reuse the ALU output for branch target (control_unit routes PC into
    // operand A and imm into B). One adder, less area. The pipelined version
    // gets its own dedicated adder for branch-target so it can flush sooner.
    assign branch_target = alu_result;
    assign jalr_target   = alu_result & ~32'd1;     // mask LSB per spec

    always_comb begin
        if      (is_jalr)                pc_sel = PC_JALR;
        else if (is_jal)                 pc_sel = PC_BRANCH;
        else if (is_branch && br_taken)  pc_sel = PC_BRANCH;
        else                             pc_sel = PC_PLUS4;
    end

    // freeze PC while DIV/REM is grinding
    assign stall = mdiv_busy;

    assign dmem_addr_o   = alu_result;
    assign dmem_we_o     = mem_we && !stall;
    assign dmem_re_o     = mem_re;
    assign dmem_funct3_o = funct3;
    assign dmem_wdata_o  = rs2_data;

    // writeback mux
    always_comb begin
        unique case (wb_sel)
            WB_ALU : rd_data = is_mdiv ? mdiv_result : alu_result;
            WB_MEM : rd_data = dmem_rdata_i;
            WB_PC4 : rd_data = pc_plus4;
            WB_IMM : rd_data = imm;
            default: rd_data = alu_result;
        endcase
    end

endmodule : rv32im_core
