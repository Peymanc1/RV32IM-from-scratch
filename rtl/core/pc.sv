// pc.sv  -  program counter
//
// Synchronous reset (preferred for Xilinx 7-series flops).
// stall_i freezes the PC for pipeline hazards.

import rv32im_pkg::*;

module pc #(
    parameter logic [31:0] RESET_VEC = RESET_VECTOR   // override to run from DDR
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic              stall_i,
    input  pc_sel_e           pc_sel_i,
    input  logic [XLEN-1:0]   branch_target_i,
    input  logic [XLEN-1:0]   jalr_target_i,

    output logic [XLEN-1:0]   pc_o,
    output logic [XLEN-1:0]   pc_plus4_o
);

    logic [XLEN-1:0] pc_reg;
    logic [XLEN-1:0] pc_next;

    // PC+4 is exposed because the link path (JAL/JALR) needs it too.
    assign pc_plus4_o = pc_reg + 32'd4;

    always_comb begin
        unique case (pc_sel_i)
            PC_PLUS4 : pc_next = pc_plus4_o;
            PC_BRANCH: pc_next = branch_target_i;
            PC_JALR  : pc_next = jalr_target_i;
            default  : pc_next = pc_plus4_o;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n)             pc_reg <= RESET_VEC;
        else if (!stall_i)      pc_reg <= pc_next;
        // stall_i held -> no update
    end

    assign pc_o = pc_reg;

endmodule : pc
