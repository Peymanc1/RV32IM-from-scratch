// forwarding_unit.sv  -  RAW bypass for EX.
// 1-back (EX/MEM) wins ties over 2-back (MEM/WB). Skip when rd == x0.
// Load-use is hazard_unit's job — by the time we get here MEM/WB has data.

import rv32im_pkg::*;

module forwarding_unit (
    input  logic [REG_ADDR-1:0] ex_rs1_i,
    input  logic [REG_ADDR-1:0] ex_rs2_i,

    input  logic [REG_ADDR-1:0] mem_rd_i,
    input  logic                mem_reg_we_i,

    input  logic [REG_ADDR-1:0] wb_rd_i,
    input  logic                wb_reg_we_i,

    output fwd_sel_e            fwd_a_o,
    output fwd_sel_e            fwd_b_o
);

    always_comb begin
        // rs1
        if      (mem_reg_we_i && mem_rd_i != 5'd0 && mem_rd_i == ex_rs1_i) fwd_a_o = FWD_FROM_M;
        else if (wb_reg_we_i  && wb_rd_i  != 5'd0 && wb_rd_i  == ex_rs1_i) fwd_a_o = FWD_FROM_W;
        else                                                                fwd_a_o = FWD_NONE;

        // rs2
        if      (mem_reg_we_i && mem_rd_i != 5'd0 && mem_rd_i == ex_rs2_i) fwd_b_o = FWD_FROM_M;
        else if (wb_reg_we_i  && wb_rd_i  != 5'd0 && wb_rd_i  == ex_rs2_i) fwd_b_o = FWD_FROM_W;
        else                                                                fwd_b_o = FWD_NONE;
    end

endmodule : forwarding_unit
