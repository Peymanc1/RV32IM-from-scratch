// rv32im_core_pipelined.sv  -  5-stage in-order RV32IM pipeline
//
// IF -> ID -> EX -> MEM -> WB
// Branches resolve in EX (predict-not-taken, 2-cycle flush on taken).
// Load-use: 1-cycle stall. Forwarding: EX/MEM + MEM/WB into EX, plus a
// WB->ID bypass for the 3-back case. MUL is combinational, DIV holds ID/EX.

import rv32im_pkg::*;

module rv32im_core_pipelined #(
    parameter logic [31:0] RESET_VEC = RESET_VECTOR   // override to boot from DDR
) (
    input  logic              clk,
    input  logic              rst_n,

    // imem
    output logic [XLEN-1:0]   imem_addr_o,
    input  logic [INST_W-1:0] imem_data_i,
    // imem_ready_i: 0 = miss, hold PC + bubble IF/ID. Tie high for BRAM.
    input  logic              imem_ready_i,

    // dmem
    output logic [XLEN-1:0]   dmem_addr_o,
    output logic              dmem_we_o,
    output logic              dmem_re_o,
    output logic [2:0]        dmem_funct3_o,
    output logic [XLEN-1:0]   dmem_wdata_o,
    input  logic [XLEN-1:0]   dmem_rdata_i,
    // dmem_ready_i: 0 = MEM-stage waiting, freeze pipeline. Tie high for BRAM.
    input  logic              dmem_ready_i
);

    // ------- pipeline control nets (declared up-front, driven below) -------
    logic            stall_pc, stall_ifid, stall_idex;
    logic            bubble_idex, bubble_exmem;
    logic            flush_ifid, flush_idex;
    logic            mdiv_busy, mdiv_done;
    logic            ex_branch_taken;
    logic [XLEN-1:0] ex_branch_target;
    logic            mem_stall;          // MEM-stage access not yet serviced
    wire             if_stall = !imem_ready_i;   // IF: instruction not fetched yet

    // ============================ IF ====================================
    logic [XLEN-1:0] if_pc, if_pc_plus4;
    pc_sel_e         if_pc_sel;
    logic [XLEN-1:0] if_branch_target_in, if_jalr_target_in;

    // EX-resolved branch wins; otherwise just PC+4
    assign if_pc_sel           = ex_branch_taken ? PC_BRANCH : PC_PLUS4;
    assign if_branch_target_in = ex_branch_target;
    assign if_jalr_target_in   = ex_branch_target;     // single target path is fine

    pc #(.RESET_VEC(RESET_VEC)) u_pc (
        .clk             (clk),
        .rst_n           (rst_n),
        // if_stall holds PC during an I-cache miss, but a resolved branch must
        // still redirect PC (ex_branch_taken is a 1-cycle pulse; the missed
        // wrong-path fetch is flushed anyway).
        .stall_i         (stall_pc || mem_stall || (if_stall && !ex_branch_taken)),
        .pc_sel_i        (if_pc_sel),
        .branch_target_i (if_branch_target_in),
        .jalr_target_i   (if_jalr_target_in),
        .pc_o            (if_pc),
        .pc_plus4_o      (if_pc_plus4)
    );

    assign imem_addr_o = if_pc;
    wire [INST_W-1:0] if_inst = imem_data_i;

    // =========================== IF/ID ==================================
    logic [XLEN-1:0]   ifid_pc, ifid_pc_plus4;
    logic [INST_W-1:0] ifid_inst;
    logic              ifid_valid;       // 0 = behave like NOP (post-flush)

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ifid_pc       <= 32'd0;
            ifid_pc_plus4 <= 32'd0;
            ifid_inst     <= 32'h00000013;   // canonical NOP (ADDI x0,x0,0)
            ifid_valid    <= 1'b0;
        end else if (mem_stall) begin
            // freeze the front-end while MEM waits; ignore flush this cycle
            // (a pending branch in EX is held too, so it resolves on release)
        end else if (flush_ifid) begin
            ifid_pc       <= 32'd0;
            ifid_pc_plus4 <= 32'd0;
            ifid_inst     <= 32'h00000013;
            ifid_valid    <= 1'b0;
        end else if (stall_ifid) begin
            // load-use hold: instruction stays (no assignment)
        end else if (if_stall) begin
            // instruction not fetched yet (I-cache miss): inject a NOP bubble;
            // the front-end's current instruction advances, PC is held.
            ifid_pc       <= 32'd0;
            ifid_pc_plus4 <= 32'd0;
            ifid_inst     <= 32'h00000013;
            ifid_valid    <= 1'b0;
        end else begin
            ifid_pc       <= if_pc;
            ifid_pc_plus4 <= if_pc_plus4;
            ifid_inst     <= if_inst;
            ifid_valid    <= 1'b1;
        end
    end

    // ============================ ID ====================================
    opcode_e             id_opcode;
    logic [REG_ADDR-1:0] id_rd, id_rs1, id_rs2;
    logic [2:0]          id_funct3;
    logic [6:0]          id_funct7;

    decoder u_decoder (
        .inst_i   (ifid_inst),
        .opcode_o (id_opcode),
        .rd_o     (id_rd),
        .rs1_o    (id_rs1),
        .rs2_o    (id_rs2),
        .funct3_o (id_funct3),
        .funct7_o (id_funct7)
    );

    logic        id_reg_we, id_mem_we, id_mem_re;
    alu_a_sel_e  id_alu_a_sel;
    alu_b_sel_e  id_alu_b_sel;
    alu_op_e     id_alu_op;
    imm_type_e   id_imm_type;
    wb_sel_e     id_wb_sel;
    logic        id_is_branch, id_is_jal, id_is_jalr, id_is_mdiv;
    branch_e     id_br_type;

    control_unit u_ctrl (
        .opcode_i    (id_opcode),
        .funct3_i    (id_funct3),
        .funct7_i    (id_funct7),
        .reg_we_o    (id_reg_we),
        .alu_a_sel_o (id_alu_a_sel),
        .alu_b_sel_o (id_alu_b_sel),
        .alu_op_o    (id_alu_op),
        .imm_type_o  (id_imm_type),
        .mem_we_o    (id_mem_we),
        .mem_re_o    (id_mem_re),
        .wb_sel_o    (id_wb_sel),
        .is_branch_o (id_is_branch),
        .is_jal_o    (id_is_jal),
        .is_jalr_o   (id_is_jalr),
        .br_type_o   (id_br_type),
        .is_mdiv_o   (id_is_mdiv)
    );

    logic [XLEN-1:0] id_imm;
    immgen u_immgen (
        .inst_i     (ifid_inst),
        .imm_type_i (id_imm_type),
        .imm_o      (id_imm)
    );

    // regfile read in ID, write driven from WB
    logic [XLEN-1:0]     id_rs1_data, id_rs2_data;
    logic                wb_reg_we;
    logic [REG_ADDR-1:0] wb_rd;
    logic [XLEN-1:0]     wb_rd_data;

    regfile u_regfile (
        .clk        (clk),
        .rst_n      (rst_n),
        .rs1_addr_i (id_rs1),
        .rs1_data_o (id_rs1_data),
        .rs2_addr_i (id_rs2),
        .rs2_data_o (id_rs2_data),
        .we_i       (wb_reg_we),
        .rd_addr_i  (wb_rd),
        .rd_data_i  (wb_rd_data)
    );

    // WB->ID bypass (3-back race): WB writing rd same cycle ID reads it.
    // Regfile read is comb, write is sync, so ID gets the old value and
    // the forwarding mux doesn't catch it (N already left). Bypass here.
    wire wb_bypass_rs1 = wb_reg_we && (wb_rd != 5'd0) && (wb_rd == id_rs1);
    wire wb_bypass_rs2 = wb_reg_we && (wb_rd != 5'd0) && (wb_rd == id_rs2);
    wire [XLEN-1:0] id_rs1_eff = wb_bypass_rs1 ? wb_rd_data : id_rs1_data;
    wire [XLEN-1:0] id_rs2_eff = wb_bypass_rs2 ? wb_rd_data : id_rs2_data;

    // gate writes when ID stage holds an invalid (NOP'd / flushed) instr
    wire id_reg_we_g  = id_reg_we   && ifid_valid;
    wire id_mem_we_g  = id_mem_we   && ifid_valid;
    wire id_mem_re_g  = id_mem_re   && ifid_valid;
    wire id_is_br_g   = id_is_branch && ifid_valid;
    wire id_is_jal_g  = id_is_jal    && ifid_valid;
    wire id_is_jalr_g = id_is_jalr   && ifid_valid;
    wire id_is_mdiv_g = id_is_mdiv   && ifid_valid;

    // =========================== ID/EX ==================================
    logic [XLEN-1:0]      idex_pc, idex_pc_plus4, idex_imm, idex_rs1_data, idex_rs2_data;
    logic [REG_ADDR-1:0]  idex_rs1, idex_rs2, idex_rd;
    logic [2:0]           idex_funct3;
    logic                 idex_reg_we, idex_mem_we, idex_mem_re;
    alu_a_sel_e           idex_alu_a_sel;
    alu_b_sel_e           idex_alu_b_sel;
    alu_op_e              idex_alu_op;
    wb_sel_e              idex_wb_sel;
    logic                 idex_is_branch, idex_is_jal, idex_is_jalr, idex_is_mdiv;
    branch_e              idex_br_type;
    logic                 idex_valid;

    // ID/EX update policy:
    //   reset / flush_idex / bubble_idex -> NOP it
    //   stall_idex (mdiv busy)           -> HOLD value (no assignment)
    //   otherwise                        -> latch from ID
    wire idex_clear = !rst_n || flush_idex || bubble_idex;

    always_ff @(posedge clk) begin
        if (mem_stall) begin
            // hold the EX-stage instruction in place while MEM waits.
            // Takes priority over flush/bubble so nothing is lost during stall.
        end else if (idex_clear) begin
            idex_pc        <= 32'd0;
            idex_pc_plus4  <= 32'd0;
            idex_imm       <= 32'd0;
            idex_rs1_data  <= 32'd0;
            idex_rs2_data  <= 32'd0;
            idex_rs1       <= 5'd0;
            idex_rs2       <= 5'd0;
            idex_rd        <= 5'd0;
            idex_funct3    <= 3'd0;
            idex_reg_we    <= 1'b0;
            idex_mem_we    <= 1'b0;
            idex_mem_re    <= 1'b0;
            idex_alu_a_sel <= ALU_A_RS1;
            idex_alu_b_sel <= ALU_B_RS2;
            idex_alu_op    <= ALU_ADD;
            idex_wb_sel    <= WB_ALU;
            idex_is_branch <= 1'b0;
            idex_is_jal    <= 1'b0;
            idex_is_jalr   <= 1'b0;
            idex_is_mdiv   <= 1'b0;
            idex_br_type   <= BR_BEQ;
            idex_valid     <= 1'b0;
        end else if (!stall_idex) begin
            idex_pc        <= ifid_pc;
            idex_pc_plus4  <= ifid_pc_plus4;
            idex_imm       <= id_imm;
            idex_rs1_data  <= id_rs1_eff;       // WB->ID bypass applied
            idex_rs2_data  <= id_rs2_eff;
            idex_rs1       <= id_rs1;
            idex_rs2       <= id_rs2;
            idex_rd        <= id_rd;
            idex_funct3    <= id_funct3;
            idex_reg_we    <= id_reg_we_g;
            idex_mem_we    <= id_mem_we_g;
            idex_mem_re    <= id_mem_re_g;
            idex_alu_a_sel <= id_alu_a_sel;
            idex_alu_b_sel <= id_alu_b_sel;
            idex_alu_op    <= id_alu_op;
            idex_wb_sel    <= id_wb_sel;
            idex_is_branch <= id_is_br_g;
            idex_is_jal    <= id_is_jal_g;
            idex_is_jalr   <= id_is_jalr_g;
            idex_is_mdiv   <= id_is_mdiv_g;
            idex_br_type   <= id_br_type;
            idex_valid     <= ifid_valid;
        end
        // stall_idex high -> hold (no assignment)
    end

    // ============================ EX ====================================
    fwd_sel_e fwd_a, fwd_b;
    logic [XLEN-1:0] ex_rs1_fwd, ex_rs2_fwd;

    // forward declarations for sources/sinks — actual flops further down
    logic [XLEN-1:0]     exmem_alu_result;
    logic [REG_ADDR-1:0] exmem_rd;
    logic                exmem_reg_we;
    logic [XLEN-1:0]     memwb_rd_data;
    logic [XLEN-1:0]     mem_wb_data;   // MEM-stage result (alu/load-data/pc+4) — used for M-stage forwarding

    forwarding_unit u_fwd (
        .ex_rs1_i     (idex_rs1),
        .ex_rs2_i     (idex_rs2),
        .mem_rd_i     (exmem_rd),
        .mem_reg_we_i (exmem_reg_we),
        .wb_rd_i      (wb_rd),
        .wb_reg_we_i  (wb_reg_we),
        .fwd_a_o      (fwd_a),
        .fwd_b_o      (fwd_b)
    );

    always_comb begin
        // Forward the MEM-stage instruction's ACTUAL result (mem_wb_data), not
        // exmem_alu_result. For a LOAD that's the loaded data (not the address)
        // and for JAL/JALR that's pc+4 (not the jump target) — exmem_alu_result
        // was wrong for both. (Load-use is also stall-guarded, but JAL/JALR rd
        // forwarding from M was an unguarded corruption.)
        unique case (fwd_a)
            FWD_FROM_M: ex_rs1_fwd = mem_wb_data;
            FWD_FROM_W: ex_rs1_fwd = wb_rd_data;
            default   : ex_rs1_fwd = idex_rs1_data;
        endcase
        unique case (fwd_b)
            FWD_FROM_M: ex_rs2_fwd = mem_wb_data;
            FWD_FROM_W: ex_rs2_fwd = wb_rd_data;
            default   : ex_rs2_fwd = idex_rs2_data;
        endcase
    end

    logic [XLEN-1:0] ex_alu_a, ex_alu_b;
    assign ex_alu_a = (idex_alu_a_sel == ALU_A_PC)  ? idex_pc  : ex_rs1_fwd;
    assign ex_alu_b = (idex_alu_b_sel == ALU_B_IMM) ? idex_imm : ex_rs2_fwd;

    logic [XLEN-1:0] ex_alu_result;
    logic            ex_alu_zero;
    alu u_alu (
        .operand_a_i (ex_alu_a),
        .operand_b_i (ex_alu_b),
        .alu_op_i    (idex_alu_op),
        .result_o    (ex_alu_result),
        .zero_o      (ex_alu_zero)
    );

    logic ex_br_taken_raw;
    branch_unit u_branch (
        .rs1_i     (ex_rs1_fwd),
        .rs2_i     (ex_rs2_fwd),
        .br_type_i (idex_br_type),
        .taken_o   (ex_br_taken_raw)
    );

    // Branch target reuses the ALU result (control_unit routes PC and imm
    // appropriately for B/J/JAL — same as in single-cycle). JALR needs the
    // LSB masked.
    wire [XLEN-1:0] ex_br_target =
        idex_is_jalr ? (ex_alu_result & ~32'd1) : ex_alu_result;

    assign ex_branch_taken  = idex_valid &&
                              (idex_is_jal || idex_is_jalr ||
                               (idex_is_branch && ex_br_taken_raw));
    assign ex_branch_target = ex_br_target;

    // ----- M-extension start -----
    // Note: do NOT gate start with !mdiv_busy. That makes a comb loop:
    // start = ... && !busy, busy = start || ... — no stable solution.
    // mul_div ignores start_i while in S_BUSY/S_DONE so leaving it asserted
    // throughout is safe.
    logic [XLEN-1:0] ex_mdiv_result;
    wire ex_mdiv_start = idex_is_mdiv && idex_valid;

    mul_div u_mul_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (ex_mdiv_start),
        .funct3_i    (idex_funct3),
        .operand_a_i (ex_rs1_fwd),
        .operand_b_i (ex_rs2_fwd),
        .result_o    (ex_mdiv_result),
        .busy_o      (mdiv_busy),
        .done_o      (mdiv_done)
    );

    // result that goes into EX/MEM
    wire [XLEN-1:0] ex_result_final =
        idex_is_mdiv ? ex_mdiv_result : ex_alu_result;

    // ============================ EX/MEM ===============================
    logic [XLEN-1:0]     exmem_rs2_data;        // for stores
    logic [REG_ADDR-1:0] exmem_rd_int;          // unused mirror, kept for debug
    logic [2:0]          exmem_funct3;
    logic                exmem_mem_we, exmem_mem_re;
    wb_sel_e             exmem_wb_sel;
    logic [XLEN-1:0]     exmem_pc_plus4;
    logic                exmem_valid;

    // bubble_exmem fires while mdiv is busy: NOP the stage so we don't sample
    // a partial result.
    always_ff @(posedge clk) begin
        if (mem_stall) begin
            // hold the load/store in MEM until the slave services it
        end else if (!rst_n || bubble_exmem) begin
            exmem_alu_result <= 32'd0;
            exmem_rs2_data   <= 32'd0;
            exmem_rd         <= 5'd0;
            exmem_rd_int     <= 5'd0;
            exmem_funct3     <= 3'd0;
            exmem_reg_we     <= 1'b0;
            exmem_mem_we     <= 1'b0;
            exmem_mem_re     <= 1'b0;
            exmem_wb_sel     <= WB_ALU;
            exmem_pc_plus4   <= 32'd0;
            exmem_valid      <= 1'b0;
        end else begin
            exmem_alu_result <= ex_result_final;
            exmem_rs2_data   <= ex_rs2_fwd;
            exmem_rd         <= idex_rd;
            exmem_rd_int     <= idex_rd;
            exmem_funct3     <= idex_funct3;
            exmem_reg_we     <= idex_reg_we;
            exmem_mem_we     <= idex_mem_we;
            exmem_mem_re     <= idex_mem_re;
            exmem_wb_sel     <= idex_wb_sel;
            exmem_pc_plus4   <= idex_pc_plus4;
            exmem_valid      <= idex_valid;
        end
    end

    // memory back-pressure: a load/store sitting in MEM whose slave hasn't
    // asserted ready freezes the whole pipeline (PC..MEM held, WB bubbled).
    // With a BRAM/single-cycle memory dmem_ready_i is tied high, so mem_stall
    // is always 0 and the pipeline behaves exactly as the verified core did.
    assign mem_stall = exmem_valid && (exmem_mem_re || exmem_mem_we) && !dmem_ready_i;

    // ============================ MEM ==================================
    assign dmem_addr_o   = exmem_alu_result;
    assign dmem_we_o     = exmem_mem_we;
    assign dmem_re_o     = exmem_mem_re;
    assign dmem_funct3_o = exmem_funct3;
    assign dmem_wdata_o  = exmem_rs2_data;

    always_comb begin
        unique case (exmem_wb_sel)
            WB_ALU : mem_wb_data = exmem_alu_result;
            WB_MEM : mem_wb_data = dmem_rdata_i;
            WB_PC4 : mem_wb_data = exmem_pc_plus4;
            WB_IMM : mem_wb_data = exmem_alu_result;   // LUI already passed through ALU
            default: mem_wb_data = exmem_alu_result;
        endcase
    end

    // ============================ MEM/WB ===============================
    logic                memwb_reg_we;
    logic [REG_ADDR-1:0] memwb_rd;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            memwb_rd_data <= 32'd0;
            memwb_rd      <= 5'd0;
            memwb_reg_we  <= 1'b0;
        end else if (mem_stall) begin
            // HOLD the WB stage during a multi-cycle MEM stall. (Previously this
            // bubbled WB.) Bubbling dropped the just-retired producer out of WB
            // after one cycle, so a CONSUMER frozen in EX across the stall lost
            // its FWD_FROM_W path and fell back to its STALE idex_rs operand
            // (captured in ID before the producer's regfile write) -> wrong
            // result. This is a load(/ALU)->use across a stalling store; it is
            // exactly the timing-sensitive corruption that broke DOOM. Holding
            // keeps the producer in WB so FWD_FROM_W stays valid; the repeated
            // regfile write is idempotent. The stalling MEM op latches into WB
            // normally on the cycle mem_stall deasserts.
            memwb_rd_data <= memwb_rd_data;
            memwb_rd      <= memwb_rd;
            memwb_reg_we  <= memwb_reg_we;
        end else begin
            memwb_rd_data <= mem_wb_data;
            memwb_rd      <= exmem_rd;
            memwb_reg_we  <= exmem_reg_we && exmem_valid;
        end
    end

    // ============================ WB ===================================
    assign wb_rd      = memwb_rd;
    assign wb_rd_data = memwb_rd_data;
    assign wb_reg_we  = memwb_reg_we;

    // ====================== hazard unit ================================
    hazard_unit u_hazard (
        .id_rs1_i       (id_rs1),
        .id_rs2_i       (id_rs2),
        .ex_rd_i        (idex_rd),
        .ex_mem_re_i    (idex_mem_re && idex_valid),
        .mdiv_busy_i    (mdiv_busy),
        .mdiv_done_i    (mdiv_done),
        .stall_pc_o     (stall_pc),
        .stall_ifid_o   (stall_ifid),
        .stall_idex_o   (stall_idex),
        .bubble_idex_o  (bubble_idex),
        .bubble_exmem_o (bubble_exmem)
    );

    // ====================== flush logic ================================
    // Branch resolved in EX -> the two younger instrs (IF/ID, ID stage) are
    // wrong-path. Wipe them.
    assign flush_ifid = ex_branch_taken;
    assign flush_idex = ex_branch_taken;

endmodule : rv32im_core_pipelined
