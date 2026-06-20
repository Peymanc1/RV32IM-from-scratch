// regfile.sv  -  32x32 register file
//
// Two combinational read ports, one synchronous write port.
// x0 is always zero — writes silently dropped, reads forced to 0.

import rv32im_pkg::*;

module regfile (
    input  logic                clk,
    input  logic                rst_n,

    input  logic [REG_ADDR-1:0] rs1_addr_i,
    output logic [XLEN-1:0]     rs1_data_o,

    input  logic [REG_ADDR-1:0] rs2_addr_i,
    output logic [XLEN-1:0]     rs2_data_o,

    input  logic                we_i,
    input  logic [REG_ADDR-1:0] rd_addr_i,
    input  logic [XLEN-1:0]     rd_data_i
);

    logic [XLEN-1:0] regs [0:31];

    // sync write. zeroing on reset is optional for synthesis but cleaner in sim.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) regs[i] <= 32'd0;
        end else if (we_i && rd_addr_i != 5'd0) begin
            regs[rd_addr_i] <= rd_data_i;
        end
    end

    // x0 short-circuit on reads (cheaper than relying on regs[0] staying 0)
    assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'd0 : regs[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'd0 : regs[rs2_addr_i];

endmodule : regfile
