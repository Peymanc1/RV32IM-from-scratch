// ddr_model.sv  -  behavioural DDR for simulation (NOT synthesizable as-is)
//
// Answers the cache's line-granular request interface with a fixed latency,
// standing in for the real PS DDR (reached over AXI on hardware). In sim the
// "program/data already in DRAM" story is just: preload this array with
// $readmemh — there is no real loader involved (that's a hardware/PS concern).
//
//   m_req & !m_we  -> after LATENCY cycles, drive m_rline with the line, pulse m_done
//   m_req &  m_we  -> after LATENCY cycles, store m_wline,                pulse m_done
//
// Handshake: m_done is high for exactly one cycle; the model then waits for the
// master to drop m_req before accepting the next request.

module ddr_model #(
    parameter int    WORDS_PER_LINE = 8,
    parameter int    MEM_WORDS      = 1 << 20,   // 4 MB of sim DRAM
    parameter int    LATENCY        = 20,        // round-trip cycles to first word
    parameter string INIT_FILE      = ""
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic                m_req,
    input  logic                m_we,
    input  logic [31:0]         m_addr,
    input  logic [LINE_W-1:0]   m_wline,
    output logic [LINE_W-1:0]   m_rline,
    output logic                m_done
);
    localparam int LINE_W   = WORDS_PER_LINE * 32;
    localparam int ADDR_W   = $clog2(MEM_WORDS);

    logic [31:0] mem [0:MEM_WORDS-1];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    // word index of the line base (line-aligned address / 4), masked to range
    wire [ADDR_W-1:0] base_word = m_addr[ADDR_W+1:2];

    typedef enum logic [1:0] { D_IDLE, D_WAIT, D_HOLD } state_e;
    state_e state;
    int     cnt;

    integer w;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state   <= D_IDLE;
            cnt     <= 0;
            m_done  <= 1'b0;
            m_rline <= '0;
        end else begin
            unique case (state)
                D_IDLE: begin
                    m_done <= 1'b0;
                    if (m_req) begin cnt <= 0; state <= D_WAIT; end
                end

                D_WAIT: begin
                    if (cnt == LATENCY) begin
                        if (m_we) begin
                            for (w = 0; w < WORDS_PER_LINE; w = w + 1)
                                mem[base_word + w] <= m_wline[w*32 +: 32];
                        end else begin
                            for (w = 0; w < WORDS_PER_LINE; w = w + 1)
                                m_rline[w*32 +: 32] <= mem[base_word + w];
                        end
                        m_done <= 1'b1;
                        state  <= D_HOLD;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end

                D_HOLD: begin
                    m_done <= 1'b0;          // one-cycle done pulse
                    if (!m_req) state <= D_IDLE;
                end

                default: state <= D_IDLE;
            endcase
        end
    end

endmodule : ddr_model
