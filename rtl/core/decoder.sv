// decoder.sv
//
// Pure bit slicing — no control logic here. Control unit consumes these.

import rv32im_pkg::*;

module decoder (
    input  logic [INST_W-1:0]   inst_i,

    output opcode_e             opcode_o,
    output logic [REG_ADDR-1:0] rd_o,
    output logic [REG_ADDR-1:0] rs1_o,
    output logic [REG_ADDR-1:0] rs2_o,
    output logic [2:0]          funct3_o,
    output logic [6:0]          funct7_o
);

    assign opcode_o = opcode_e'(inst_i[6:0]);
    assign rd_o     = inst_i[11:7];
    assign funct3_o = inst_i[14:12];
    assign rs1_o    = inst_i[19:15];
    assign rs2_o    = inst_i[24:20];
    assign funct7_o = inst_i[31:25];

endmodule : decoder
