// axi_lite_master.sv  -  CPU memory-port -> AXI4-Lite adapter.
// Single outstanding transaction, drops `ready` until slave answers (the
// pipeline freezes for the round-trip via dmem_ready_i). WSTRB/WDATA
// alignment matches dmem.sv. Loads return the full 32-bit word (no sub-word
// sign-extension — fine for the UART register reads we use it for).

import rv32im_pkg::*;

module axi_lite_master (
    input  logic              clk,
    input  logic              rst_n,

    // ---- CPU-side request (from mmio_bridge, AXI-mapped region only) ----
    input  logic              req_re_i,      // load  targeting AXI region
    input  logic              req_we_i,      // store targeting AXI region
    input  logic [XLEN-1:0]   req_addr_i,
    input  logic [2:0]        req_funct3_i,
    input  logic [XLEN-1:0]   req_wdata_i,
    output logic [XLEN-1:0]   req_rdata_o,
    output logic              req_ready_o,   // 1-cycle done pulse (-> dmem_ready)

    // ---- AXI4-Lite master ----
    output logic [XLEN-1:0]   m_axi_awaddr,
    output logic [2:0]        m_axi_awprot,
    output logic              m_axi_awvalid,
    input  logic              m_axi_awready,

    output logic [XLEN-1:0]   m_axi_wdata,
    output logic [3:0]        m_axi_wstrb,
    output logic              m_axi_wvalid,
    input  logic              m_axi_wready,

    input  logic [1:0]        m_axi_bresp,
    input  logic              m_axi_bvalid,
    output logic              m_axi_bready,

    output logic [XLEN-1:0]   m_axi_araddr,
    output logic [2:0]        m_axi_arprot,
    output logic              m_axi_arvalid,
    input  logic              m_axi_arready,

    input  logic [XLEN-1:0]   m_axi_rdata,
    input  logic [1:0]        m_axi_rresp,
    input  logic              m_axi_rvalid,
    output logic              m_axi_rready
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_WADDR,   // AW + W outstanding
        S_WRESP,   // waiting for B
        S_RADDR,   // AR outstanding
        S_RDATA    // waiting for R
    } state_e;

    state_e state;

    // latched request (stable for the whole stall, but latch anyway so the
    // AXI side never depends on the core de-asserting at the wrong moment)
    logic [XLEN-1:0] addr_q, wdata_q;
    logic [3:0]      wstrb_q;

    // valid flags as flops so we honour the AXI rule "hold VALID until READY"
    logic awvalid_q, wvalid_q, arvalid_q;

    assign m_axi_awaddr  = addr_q;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awvalid = awvalid_q;
    assign m_axi_wdata   = wdata_q;
    assign m_axi_wstrb   = wstrb_q;
    assign m_axi_wvalid  = wvalid_q;
    assign m_axi_bready  = (state == S_WRESP);
    assign m_axi_araddr  = addr_q;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arvalid = arvalid_q;
    assign m_axi_rready  = (state == S_RDATA);

    // done pulse: the cycle the slave answers. Combinational so the core sees
    // ready this cycle and advances on the next edge, in lock-step with our
    // own return to S_IDLE.
    wire write_done = (state == S_WRESP) && m_axi_bvalid;
    wire read_done  = (state == S_RDATA) && m_axi_rvalid;
    assign req_ready_o = write_done || read_done;

    // read data straight through on the completing cycle (core latches it then)
    assign req_rdata_o = m_axi_rdata;

    // ---- byte/half/word strobe + aligned write data (mirrors dmem.sv) ----
    logic [3:0]  strobe;
    logic [31:0] aligned;
    wire  [1:0]  boff = req_addr_i[1:0];
    always_comb begin
        strobe  = 4'b0000;
        aligned = 32'd0;
        unique case (req_funct3_i[1:0])
            2'b00: begin strobe = 4'b0001 << boff;            aligned = {4{req_wdata_i[7:0]}};  end // SB
            2'b01: begin strobe = boff[1] ? 4'b1100 : 4'b0011; aligned = {2{req_wdata_i[15:0]}}; end // SH
            2'b10: begin strobe = 4'b1111;                     aligned = req_wdata_i;            end // SW
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            awvalid_q <= 1'b0;
            wvalid_q  <= 1'b0;
            arvalid_q <= 1'b0;
            addr_q    <= 32'd0;
            wdata_q   <= 32'd0;
            wstrb_q   <= 4'b0000;
        end else begin
            unique case (state)
                S_IDLE: begin
                    if (req_we_i) begin
                        state     <= S_WADDR;
                        addr_q    <= req_addr_i;
                        wdata_q   <= aligned;
                        wstrb_q   <= strobe;
                        awvalid_q <= 1'b1;
                        wvalid_q  <= 1'b1;
                    end else if (req_re_i) begin
                        state     <= S_RADDR;
                        addr_q    <= req_addr_i;
                        arvalid_q <= 1'b1;
                    end
                end

                S_WADDR: begin
                    if (m_axi_awready) awvalid_q <= 1'b0;
                    if (m_axi_wready)  wvalid_q  <= 1'b0;
                    // move on once both AW and W have been accepted
                    if ((!awvalid_q || m_axi_awready) &&
                        (!wvalid_q  || m_axi_wready)) begin
                        state <= S_WRESP;
                    end
                end

                S_WRESP: begin
                    if (m_axi_bvalid) state <= S_IDLE;   // bready asserted via state
                end

                S_RADDR: begin
                    if (m_axi_arready) begin
                        arvalid_q <= 1'b0;
                        state     <= S_RDATA;
                    end
                end

                S_RDATA: begin
                    if (m_axi_rvalid) state <= S_IDLE;   // rready asserted via state
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule : axi_lite_master
