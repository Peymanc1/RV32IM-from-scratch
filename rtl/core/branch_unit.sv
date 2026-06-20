// branch_unit.sv  -  resolve conditional branches
//
// Three comparators (eq, signed-lt, unsigned-lt) cover all six branch types.
// Output is just "taken? yes/no". The PC mux upstairs uses it.

import rv32im_pkg::*;

module branch_unit (
    input  logic [XLEN-1:0] rs1_i,
    input  logic [XLEN-1:0] rs2_i,
    input  branch_e         br_type_i,
    output logic            taken_o
);

    wire eq          = (rs1_i == rs2_i);
    wire lt_signed   = ($signed(rs1_i) < $signed(rs2_i));
    wire lt_unsigned = (rs1_i < rs2_i);

    always_comb begin
        unique case (br_type_i)
            BR_BEQ  : taken_o =  eq;
            BR_BNE  : taken_o = !eq;
            BR_BLT  : taken_o =  lt_signed;
            BR_BGE  : taken_o = !lt_signed;
            BR_BLTU : taken_o =  lt_unsigned;
            BR_BGEU : taken_o = !lt_unsigned;
            default : taken_o = 1'b0;
        endcase
    end

endmodule : branch_unit
