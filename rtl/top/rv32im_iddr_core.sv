// rv32im_iddr_core.sv  -  M2b: RV32IM FETCHES INSTRUCTIONS FROM DDR via I-cache
//
// Proves the new instruction path: the CPU boots at 0x10000000 (DDR) and every
// instruction comes through a read-only I-cache (a second cache.sv instance) ->
// axi_burst_master -> M_AXI -> (PS S_AXI_HP ->) DDR. The program's .text lives
// in DDR; its .data/.stack stay in BRAM (0x8) and it shows a verdict on the LED.
//
//   fetch (0x1xxxxxxx)  -> I-cache (read-only) -> burst -> M_AXI -> DDR
//   data  (0x8 / 0x9)   -> mmio_bridge -> BRAM dmem + LED   (single-cycle)
//
// This is the M1 datapath turned around onto the fetch port. Same m_axi_* names
// so the BD bundles it into an AXI4 master interface (later: 2 SI SmartConnect
// once the D-cache shares DDR too).

import rv32im_pkg::*;

module rv32im_iddr_core #(
    parameter logic [31:0] RESET_VEC     = 32'h1000_0000,  // boot from DDR
    parameter int          DMEM_WORDS    = 4096,
    parameter int          NUM_LINES     = 256,
    parameter int          WORDS_PER_LINE = 8
) (
    input  logic        clk,
    input  logic        rst_n,
    output logic [3:0]  led,

    // ---- AXI4 master (32-bit) for instruction fills -> DDR ----
    output logic [31:0] m_axi_awaddr,
    output logic [7:0]  m_axi_awlen,
    output logic [2:0]  m_axi_awsize,
    output logic [1:0]  m_axi_awburst,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wlast,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] m_axi_araddr,
    output logic [7:0]  m_axi_arlen,
    output logic [2:0]  m_axi_arsize,
    output logic [1:0]  m_axi_arburst,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rlast,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);
    localparam int LINE_W = WORDS_PER_LINE * XLEN;

    // ---- CPU ----
    logic [XLEN-1:0] imem_addr, imem_data;
    logic            imem_ready;
    logic [XLEN-1:0] d_addr, d_wdata, d_rdata;
    logic            d_we, d_re, d_ready;
    logic [2:0]      d_funct3;

    rv32im_core_pipelined #(.RESET_VEC(RESET_VEC)) u_cpu (
        .clk(clk), .rst_n(rst_n),
        .imem_addr_o(imem_addr), .imem_data_i(imem_data), .imem_ready_i(imem_ready),
        .dmem_addr_o(d_addr), .dmem_we_o(d_we), .dmem_re_o(d_re),
        .dmem_funct3_o(d_funct3), .dmem_wdata_o(d_wdata),
        .dmem_rdata_i(d_rdata), .dmem_ready_i(d_ready)
    );

    // ---- I-cache (read-only): fetch -> DDR ----
    logic              ic_req, ic_we, ic_done;
    logic [XLEN-1:0]   ic_maddr;
    logic [LINE_W-1:0] ic_wline, ic_rline;

    cache #(.NUM_LINES(NUM_LINES), .WORDS_PER_LINE(WORDS_PER_LINE)) u_icache (
        .clk(clk), .rst_n(rst_n),
        .c_addr(imem_addr), .c_re(1'b1), .c_we(1'b0),
        .c_funct3(3'b010),                       // word read
        .c_wdata(32'd0),
        .c_rdata(imem_data), .c_ready(imem_ready),
        .m_req(ic_req), .m_we(ic_we), .m_addr(ic_maddr),
        .m_wline(ic_wline), .m_rline(ic_rline), .m_done(ic_done)
    );

    axi_burst_master #(.WORDS_PER_LINE(WORDS_PER_LINE)) u_iburst (
        .clk(clk), .rst_n(rst_n),
        .m_req(ic_req), .m_we(ic_we), .m_addr(ic_maddr),
        .m_wline(ic_wline), .m_rline(ic_rline), .m_done(ic_done),
        .awaddr(m_axi_awaddr), .awlen(m_axi_awlen), .awsize(m_axi_awsize),
        .awburst(m_axi_awburst), .awvalid(m_axi_awvalid), .awready(m_axi_awready),
        .wdata(m_axi_wdata), .wstrb(m_axi_wstrb), .wlast(m_axi_wlast),
        .wvalid(m_axi_wvalid), .wready(m_axi_wready),
        .bresp(m_axi_bresp), .bvalid(m_axi_bvalid), .bready(m_axi_bready),
        .araddr(m_axi_araddr), .arlen(m_axi_arlen), .arsize(m_axi_arsize),
        .arburst(m_axi_arburst), .arvalid(m_axi_arvalid), .arready(m_axi_arready),
        .rdata(m_axi_rdata), .rresp(m_axi_rresp), .rlast(m_axi_rlast),
        .rvalid(m_axi_rvalid), .rready(m_axi_rready)
    );

    // ---- data side: BRAM + LED (single-cycle) ----
    logic [XLEN-1:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic            dmem_we, dmem_re;
    logic [2:0]      dmem_funct3;

    mmio_bridge u_bridge (
        .clk(clk), .rst_n(rst_n),
        .core_addr_i(d_addr), .core_we_i(d_we), .core_re_i(d_re),
        .core_funct3_i(d_funct3), .core_wdata_i(d_wdata),
        .core_rdata_o(d_rdata), .core_ready_o(d_ready),
        .dmem_addr_o(dmem_addr), .dmem_we_o(dmem_we), .dmem_re_o(dmem_re),
        .dmem_funct3_o(dmem_funct3), .dmem_wdata_o(dmem_wdata), .dmem_rdata_i(dmem_rdata),
        .axi_addr_o(), .axi_we_o(), .axi_re_o(), .axi_funct3_o(), .axi_wdata_o(),
        .axi_rdata_i(32'd0), .axi_ready_i(1'b1),
        .mbox_o(), .mbox_ack_i(1'b0), .sw_i(4'b0000),
        .fb_we_o(), .fb_waddr_o(), .fb_wdata_o(),
        .pal_we_o(), .pal_waddr_o(), .pal_wdata_o(),
        .led_o(led)
    );

    dmem #(.MEM_WORDS(DMEM_WORDS)) u_dmem (
        .clk(clk), .addr_i(dmem_addr),
        .we_i(dmem_we), .re_i(dmem_re), .funct3_i(dmem_funct3),
        .write_data_i(dmem_wdata), .read_data_o(dmem_rdata)
    );

endmodule : rv32im_iddr_core
