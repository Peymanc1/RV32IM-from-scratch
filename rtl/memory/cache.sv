// cache.sv  -  direct-mapped write-back write-allocate cache.
// Default 256 lines * 32 byte = 8 KB.
//   addr = | tag (19) | index (8) | word_sel (3) | byte (2) |
// Hits are single-cycle. On a miss c_ready drops low until the line fill
// (and possibly a dirty write-back) completes.
// Memory-side handshake: m_req+m_we picks fill vs write-back, m_done pulses
// on completion. AXI burst conversion is layered on top by axi_burst_master.

import rv32im_pkg::*;

module cache #(
    parameter int NUM_LINES      = 256,
    parameter int WORDS_PER_LINE = 8
) (
    input  logic                clk,
    input  logic                rst_n,

    // ---- core side (CPU data port) ----
    input  logic [XLEN-1:0]     c_addr,
    input  logic                c_re,
    input  logic                c_we,
    input  logic [2:0]          c_funct3,
    input  logic [XLEN-1:0]     c_wdata,
    output logic [XLEN-1:0]     c_rdata,
    output logic                c_ready,

    // ---- memory (DDR) side, line granular ----
    output logic                m_req,
    output logic                m_we,
    output logic [XLEN-1:0]      m_addr,
    output logic [LINE_W-1:0]    m_wline,
    input  logic [LINE_W-1:0]    m_rline,
    input  logic                m_done
);
    // ---- derived geometry ----
    localparam int LINE_W      = WORDS_PER_LINE * XLEN;          // bits per line
    localparam int OFFSET_BITS = $clog2(WORDS_PER_LINE * 4);     // byte offset in line
    localparam int INDEX_BITS  = $clog2(NUM_LINES);
    localparam int TAG_BITS    = XLEN - OFFSET_BITS - INDEX_BITS;
    localparam int WSEL_BITS   = $clog2(WORDS_PER_LINE);

    // address fields (live c_addr — used for hits in S_IDLE)
    wire [1:0]            byte_off = c_addr[1:0];
    wire [WSEL_BITS-1:0]  word_sel = c_addr[OFFSET_BITS-1:2];
    wire [INDEX_BITS-1:0] index    = c_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0]   tag       = c_addr[XLEN-1:OFFSET_BITS+INDEX_BITS];

    // req_addr is LATCHED when a miss is detected, so the multi-cycle fill is
    // immune to c_addr moving on (e.g. a branch redirect changing the fetch PC
    // while if_stall propagates). Using live c_addr for the fill let it target
    // the wrong line and corrupt instruction fetch under I+D cache concurrency.
    logic [XLEN-1:0]     req_addr;
    wire [INDEX_BITS-1:0] fill_index = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0]   fill_tag   = req_addr[XLEN-1:OFFSET_BITS+INDEX_BITS];

    // ---- storage ----
    logic [LINE_W-1:0]   data_arr [0:NUM_LINES-1];
    logic [TAG_BITS-1:0] tag_arr  [0:NUM_LINES-1];
    logic                valid_arr[0:NUM_LINES-1];
    logic                dirty_arr[0:NUM_LINES-1];

    wire hit = valid_arr[index] && (tag_arr[index] == tag);

    // selected word out of the indexed line (combinational)
    logic [XLEN-1:0] sel_word;
    assign sel_word = data_arr[index][word_sel*XLEN +: XLEN];

    // ---- load extraction (funct3), mirrors dmem.sv ----
    logic [7:0]  byte_sel;
    logic [15:0] half_sel;
    always_comb begin
        unique case (byte_off)
            2'b00:  byte_sel = sel_word[ 7: 0];
            2'b01:  byte_sel = sel_word[15: 8];
            2'b10:  byte_sel = sel_word[23:16];
            2'b11:  byte_sel = sel_word[31:24];
            default:byte_sel = 8'd0;
        endcase
        half_sel = byte_off[1] ? sel_word[31:16] : sel_word[15:0];
    end
    always_comb begin
        unique case (c_funct3)
            3'b000 : c_rdata = {{24{byte_sel[7]}},  byte_sel};   // LB
            3'b001 : c_rdata = {{16{half_sel[15]}}, half_sel};   // LH
            3'b010 : c_rdata = sel_word;                          // LW
            3'b100 : c_rdata = {24'd0, byte_sel};                 // LBU
            3'b101 : c_rdata = {16'd0, half_sel};                 // LHU
            default: c_rdata = sel_word;
        endcase
    end

    // ---- store merge (byte strobes), mirrors dmem.sv ----
    logic [3:0]  strobe;
    logic [31:0] waligned;
    always_comb begin
        strobe   = 4'b0000;
        waligned = 32'd0;
        unique case (c_funct3[1:0])
            2'b00: begin strobe = 4'b0001 << byte_off;            waligned = {4{c_wdata[7:0]}};  end // SB
            2'b01: begin strobe = byte_off[1] ? 4'b1100 : 4'b0011; waligned = {2{c_wdata[15:0]}}; end // SH
            2'b10: begin strobe = 4'b1111;                         waligned = c_wdata;            end // SW
            default: ;
        endcase
    end
    // merged word to store into the line on a write hit
    function automatic [31:0] merge_word(input [31:0] old);
        merge_word[ 7: 0] = strobe[0] ? waligned[ 7: 0] : old[ 7: 0];
        merge_word[15: 8] = strobe[1] ? waligned[15: 8] : old[15: 8];
        merge_word[23:16] = strobe[2] ? waligned[23:16] : old[23:16];
        merge_word[31:24] = strobe[3] ? waligned[31:24] : old[31:24];
    endfunction

    // ---- FSM ----
    // S_FILL_GAP drops m_req for one cycle between a write-back and the fill,
    // because the memory handshake requires m_req to deassert before a new
    // transaction (otherwise the slave can't tell the fill from the write-back).
    typedef enum logic [1:0] { S_IDLE, S_WB, S_FILL_GAP, S_FILL } state_e;
    state_e state;

    wire need_wb = valid_arr[index] && dirty_arr[index];   // dirty victim (live, at S_IDLE)

    // line-aligned addresses (fill/write-back use the LATCHED req_addr)
    wire [XLEN-1:0] fill_addr = {req_addr[XLEN-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    wire [XLEN-1:0] wb_addr   = {tag_arr[fill_index], fill_index, {OFFSET_BITS{1'b0}}};

    assign m_we    = (state == S_WB);
    assign m_req   = (state == S_WB) || (state == S_FILL);
    assign m_addr  = (state == S_WB) ? wb_addr : fill_addr;
    assign m_wline = data_arr[fill_index];

    // hits are single-cycle; during a miss c_ready is low (pipeline stalls)
    assign c_ready = (state == S_IDLE) && hit;

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_arr[i] <= 1'b0;
                dirty_arr[i] <= 1'b0;
            end
        end else begin
            unique case (state)
                S_IDLE: begin
                    if ((c_re || c_we) && hit) begin
                        // single-cycle hit; commit a write into the line
                        if (c_we) begin
                            data_arr[index][word_sel*XLEN +: XLEN]
                                <= merge_word(sel_word);
                            dirty_arr[index] <= 1'b1;
                        end
                    end else if (c_re || c_we) begin
                        // miss: latch the request address, then write back a
                        // dirty victim first, else fill.
                        req_addr <= c_addr;
                        state <= need_wb ? S_WB : S_FILL;
                    end
                end

                S_WB: begin
                    if (m_done) begin
                        dirty_arr[fill_index] <= 1'b0;   // victim flushed
                        state <= S_FILL_GAP;             // drop m_req one cycle
                    end
                end

                S_FILL_GAP: state <= S_FILL;

                S_FILL: begin
                    if (m_done) begin
                        data_arr[fill_index]  <= m_rline;
                        tag_arr[fill_index]   <= fill_tag;
                        valid_arr[fill_index] <= 1'b1;
                        dirty_arr[fill_index] <= 1'b0;
                        state <= S_IDLE;            // next cycle it's a hit -> serve
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule : cache
