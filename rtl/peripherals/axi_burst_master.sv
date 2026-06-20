// axi_burst_master.sv  -  cache line handshake -> AXI4 INCR burst.
// A fill becomes a read burst of WORDS_PER_LINE beats, a write-back a
// write burst. Single outstanding (cache is stalled until m_done). 32-bit
// data path, one word per beat. PS interconnect handles ID ordering, so
// AWID/ARID are tied off in the wrapper.

import rv32im_pkg::*;

module axi_burst_master #(
    parameter int WORDS_PER_LINE = 8
) (
    input  logic                clk,
    input  logic                rst_n,

    // ---- cache (line) side ----
    input  logic                m_req,
    input  logic                m_we,       // 1 = write-back, 0 = fill
    input  logic [XLEN-1:0]      m_addr,     // line-aligned
    input  logic [LINE_W-1:0]    m_wline,
    output logic [LINE_W-1:0]    m_rline,
    output logic                m_done,

    // ---- AXI4 master side (32-bit) ----
    output logic [XLEN-1:0]     awaddr,
    output logic [7:0]          awlen,
    output logic [2:0]          awsize,
    output logic [1:0]          awburst,
    output logic                awvalid,
    input  logic                awready,

    output logic [31:0]         wdata,
    output logic [3:0]          wstrb,
    output logic                wlast,
    output logic                wvalid,
    input  logic                wready,

    input  logic [1:0]          bresp,
    input  logic                bvalid,
    output logic                bready,

    output logic [XLEN-1:0]     araddr,
    output logic [7:0]          arlen,
    output logic [2:0]          arsize,
    output logic [1:0]          arburst,
    output logic                arvalid,
    input  logic                arready,

    input  logic [31:0]         rdata,
    input  logic [1:0]          rresp,
    input  logic                rlast,
    input  logic                rvalid,
    output logic                rready
);
    localparam int LINE_W   = WORDS_PER_LINE * 32;
    localparam int BEAT_BITS = $clog2(WORDS_PER_LINE);

    localparam [7:0] LEN  = WORDS_PER_LINE - 1;   // AXI: beats = LEN + 1
    localparam [2:0] SIZE = 3'b010;               // 4 bytes/beat
    localparam [1:0] INCR = 2'b01;

    typedef enum logic [2:0] {
        S_IDLE,
        S_AR, S_R,                 // read burst (fill)
        S_AW, S_W, S_B,            // write burst (write-back)
        S_HOLD                     // wait for m_req to drop after m_done
    } state_e;
    state_e state;

    logic [XLEN-1:0]          addr_q;
    logic [LINE_W-1:0]        wline_q, rline_q;
    logic [BEAT_BITS-1:0]     beat;

    // constant-ish AXI fields
    assign awaddr  = addr_q;
    assign awlen   = LEN;
    assign awsize  = SIZE;
    assign awburst = INCR;
    assign awvalid = (state == S_AW);

    assign wdata   = wline_q[beat*32 +: 32];
    assign wstrb   = 4'b1111;                    // full words (whole line)
    assign wlast   = (state == S_W) && (beat == LEN[BEAT_BITS-1:0]);
    assign wvalid  = (state == S_W);
    assign bready  = (state == S_B);

    assign araddr  = addr_q;
    assign arlen   = LEN;
    assign arsize  = SIZE;
    assign arburst = INCR;
    assign arvalid = (state == S_AR);
    assign rready  = (state == S_R);

    assign m_rline = rline_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            beat    <= '0;
            m_done  <= 1'b0;
            addr_q  <= '0;
            wline_q <= '0;
            rline_q <= '0;
        end else begin
            m_done <= 1'b0;   // default; pulsed for one cycle below

            unique case (state)
                S_IDLE: begin
                    beat   <= '0;
                    addr_q <= m_addr;
                    if (m_req && m_we) begin
                        wline_q <= m_wline;
                        state   <= S_AW;
                    end else if (m_req && !m_we) begin
                        state   <= S_AR;
                    end
                end

                // ---- read burst (fill) ----
                S_AR: if (arready) state <= S_R;
                S_R : if (rvalid) begin
                    rline_q[beat*32 +: 32] <= rdata;
                    beat <= beat + 1'b1;
                    if (rlast) begin
                        m_done <= 1'b1;
                        state  <= S_HOLD;
                    end
                end

                // ---- write burst (write-back) ----
                S_AW: if (awready) state <= S_W;
                S_W : if (wready) begin
                    beat <= beat + 1'b1;
                    if (beat == LEN[BEAT_BITS-1:0]) state <= S_B;
                end
                S_B : if (bvalid) begin
                    m_done <= 1'b1;
                    state  <= S_HOLD;
                end

                S_HOLD: if (!m_req) state <= S_IDLE;  // one new req per deassert

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule : axi_burst_master
