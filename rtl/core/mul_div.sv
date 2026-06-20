// mul_div.sv  -  M-extension
//
// MUL family: combinational. Synthesis maps these to DSP48 blocks on Xilinx.
// DIV family: 32-cycle restoring division FSM. Pipeline stalls while busy.
//
// funct3 (under OP_RTYPE, funct7=0000001):
//   000 MUL     low  32 of  signed * signed
//   001 MULH    high 32 of  signed * signed
//   010 MULHSU  high 32 of  signed * unsigned
//   011 MULHU   high 32 of  unsigned * unsigned
//   100 DIV     signed / signed
//   101 DIVU    unsigned / unsigned
//   110 REM     signed % signed
//   111 REMU    unsigned % unsigned

import rv32im_pkg::*;

module mul_div (
    input  logic              clk,
    input  logic              rst_n,
    input  logic              start_i,
    input  logic [2:0]        funct3_i,
    input  logic [XLEN-1:0]   operand_a_i,    // rs1
    input  logic [XLEN-1:0]   operand_b_i,    // rs2

    output logic [XLEN-1:0]   result_o,
    output logic              busy_o,
    output logic              done_o          // pulses one cycle when result ready
);

    // -------- MUL (combinational) --------
    logic signed [63:0] mul_ss;
    logic        [63:0] mul_uu;
    logic signed [63:0] mul_su;

    assign mul_ss = $signed(operand_a_i) * $signed(operand_b_i);
    assign mul_uu = operand_a_i * operand_b_i;
    assign mul_su = $signed(operand_a_i) * $signed({1'b0, operand_b_i});

    logic [XLEN-1:0] mul_result;
    always_comb begin
        unique case (funct3_i)
            3'b000 : mul_result = mul_ss[31:0];   // MUL
            3'b001 : mul_result = mul_ss[63:32];  // MULH
            3'b010 : mul_result = mul_su[63:32];  // MULHSU
            3'b011 : mul_result = mul_uu[63:32];  // MULHU
            default: mul_result = 32'd0;
        endcase
    end

    // -------- DIV/REM (multi-cycle) --------
    // Plain restoring divider. 32 iterations.
    typedef enum logic [1:0] { S_IDLE, S_BUSY, S_DONE } div_state_e;
    div_state_e state;

    logic [5:0]  counter;
    logic [63:0] dividend_ext;     // upper 32 = remainder, lower 32 = quotient shifted in
    logic [31:0] divisor;
    logic        neg_quot, neg_rem;
    logic        is_rem;
    logic        is_signed;

    // sign-fix on operands when starting a signed op
    wire [31:0] abs_a = (operand_a_i[31] && funct3_i[0] == 1'b0 && start_i)
                        ? -operand_a_i : operand_a_i;
    wire [31:0] abs_b = (operand_b_i[31] && funct3_i[0] == 1'b0 && start_i)
                        ? -operand_b_i : operand_b_i;

    wire is_mul        = (funct3_i[2] == 1'b0);
    wire is_div_op     = (funct3_i[2] == 1'b1);

    // combinational version — the registered is_signed is stale during S_IDLE
    // start cycle, so use this for the captures below
    wire is_signed_now = (funct3_i == 3'b100) || (funct3_i == 3'b110);

    // 33-bit subtract to detect underflow. Important: zero-extend on the LEFT
    // (high bit). I had this wrong once — appending a zero on the LSB doubled
    // the value. Cost me a day.
    wire [32:0] trial_sub = {1'b0, dividend_ext[62:31]} - {1'b0, divisor};

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            counter      <= 6'd0;
            dividend_ext <= 64'd0;
            divisor      <= 32'd0;
            neg_quot     <= 1'b0;
            neg_rem      <= 1'b0;
            is_rem       <= 1'b0;
            is_signed    <= 1'b0;
        end else begin
            case (state)
                S_IDLE: if (start_i && is_div_op) begin
                    // capture using is_signed_now (combinational) — the registered
                    // value is from the previous DIV and would be wrong here.
                    is_signed    <= is_signed_now;
                    is_rem       <= funct3_i[1];
                    neg_quot     <= is_signed_now && (operand_a_i[31] ^ operand_b_i[31])
                                    && (operand_b_i != 32'd0);
                    neg_rem      <= is_signed_now && operand_a_i[31];
                    dividend_ext <= {32'd0, is_signed_now ? abs_a : operand_a_i};
                    divisor      <= is_signed_now ? abs_b : operand_b_i;
                    counter      <= 6'd0;
                    state        <= S_BUSY;
                end
                S_BUSY: begin
                    // each iteration: try subtract, shift in 1 if it succeeded else 0
                    if (!trial_sub[32]) begin
                        dividend_ext <= {trial_sub[31:0], dividend_ext[30:0], 1'b1};
                    end else begin
                        dividend_ext <= {dividend_ext[62:0], 1'b0};
                    end
                    counter <= counter + 6'd1;
                    if (counter == 6'd31) state <= S_DONE;
                end
                S_DONE:  state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    wire [31:0] quotient_raw  = dividend_ext[31:0];
    wire [31:0] remainder_raw = dividend_ext[63:32];

    wire [31:0] div_result = neg_quot ? -quotient_raw  : quotient_raw;
    wire [31:0] rem_result = neg_rem  ? -remainder_raw : remainder_raw;

    always_comb begin
        if (is_mul) result_o = mul_result;
        else        result_o = is_rem ? rem_result : div_result;
    end

    // busy must be high on the START cycle too — otherwise the PC advances
    // before the FSM moves out of IDLE. Catches both that case and S_BUSY.
    assign busy_o = (state == S_BUSY) || (state == S_IDLE && start_i && is_div_op);
    assign done_o = (state == S_DONE) || (is_mul && start_i);

endmodule : mul_div
