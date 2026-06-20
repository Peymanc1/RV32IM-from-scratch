// hazard_unit.sv  -  load-use stall + MDIV hold.
// LOAD in EX, consumer in ID  -> stall PC + IF/ID, bubble ID/EX (1 cycle).
// MDIV busy  -> hold PC + IF/ID + ID/EX, bubble EX/MEM until done.
// Branch flush is in rv32im_core_pipelined (different shape, kept inline).

import rv32im_pkg::*;

module hazard_unit (
    input  logic [REG_ADDR-1:0] id_rs1_i,
    input  logic [REG_ADDR-1:0] id_rs2_i,

    input  logic [REG_ADDR-1:0] ex_rd_i,
    input  logic                ex_mem_re_i,     // is the EX-stage instr a LOAD?

    input  logic                mdiv_busy_i,
    input  logic                mdiv_done_i,

    output logic                stall_pc_o,
    output logic                stall_ifid_o,
    output logic                stall_idex_o,    // HOLD (mdiv)
    output logic                bubble_idex_o,   // NOP  (load-use)
    output logic                bubble_exmem_o   // NOP  (mdiv busy)
);

    wire load_use = ex_mem_re_i && (ex_rd_i != 5'd0) &&
                    ((ex_rd_i == id_rs1_i) || (ex_rd_i == id_rs2_i));

    // active mdiv = busy and not yet done. On the done cycle we let the
    // pipeline move so the result actually leaves EX/MEM.
    wire mdiv_stall = mdiv_busy_i && !mdiv_done_i;

    always_comb begin
        stall_pc_o     = 1'b0;
        stall_ifid_o   = 1'b0;
        stall_idex_o   = 1'b0;
        bubble_idex_o  = 1'b0;
        bubble_exmem_o = 1'b0;

        if (load_use) begin
            stall_pc_o    = 1'b1;
            stall_ifid_o  = 1'b1;
            bubble_idex_o = 1'b1;
        end

        if (mdiv_stall) begin
            stall_pc_o     = 1'b1;
            stall_ifid_o   = 1'b1;
            stall_idex_o   = 1'b1;   // hold, NOT bubble — keep MDIV in EX
            bubble_exmem_o = 1'b1;
        end
    end

endmodule : hazard_unit
