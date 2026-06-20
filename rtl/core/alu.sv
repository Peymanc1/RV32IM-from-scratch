// alu.sv  -  pure combinational ALU
//
// RV32 shifts use the lower 5 bits of operand_b — anything above is ignored.
// zero_o saves a bit of work for the branch unit when used standalone.

import rv32im_pkg::*;

module alu (
    input  logic [XLEN-1:0] operand_a_i,
    input  logic [XLEN-1:0] operand_b_i,
    input  alu_op_e         alu_op_i,
    output logic [XLEN-1:0] result_o,
    output logic            zero_o
);

    wire [4:0] shamt = operand_b_i[4:0];

    always_comb begin
        unique case (alu_op_i)
            ALU_ADD  : result_o = operand_a_i + operand_b_i;
            ALU_SUB  : result_o = operand_a_i - operand_b_i;
            ALU_SLL  : result_o = operand_a_i << shamt;
            ALU_SLT  : result_o = ($signed(operand_a_i) < $signed(operand_b_i)) ? 32'd1 : 32'd0;
            ALU_SLTU : result_o = (operand_a_i < operand_b_i) ? 32'd1 : 32'd0;
            ALU_XOR  : result_o = operand_a_i ^ operand_b_i;
            ALU_SRL  : result_o = operand_a_i >> shamt;
            ALU_SRA  : result_o = $signed(operand_a_i) >>> shamt;
            ALU_OR   : result_o = operand_a_i | operand_b_i;
            ALU_AND  : result_o = operand_a_i & operand_b_i;
            ALU_PASSB: result_o = operand_b_i;
            default  : result_o = 32'd0;
        endcase
    end

    assign zero_o = (result_o == 32'd0);

endmodule : alu
