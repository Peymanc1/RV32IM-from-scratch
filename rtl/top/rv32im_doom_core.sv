// rv32im_doom_core.sv  -  the SoC core that runs DOOM.
//
// Unified DDR memory (I-cache for code, D-cache for data/heap/stack/WAD) PLUS
// the MMIO bridge for the screen: the CPU writes the 320x200 framebuffer (0xA)
// and palette (0xB) which go out HDMI, reads the switches (0x90000008) and the
// free-running cycle counter (0x90000004). Two AXI masters -> SmartConnect ->
// S_AXI_HP -> PS DDR.
//
//   fetch (0x1) -> I-cache -> m_axi_i -> DDR
//   data  (0x1) -> D-cache -> m_axi_d -> DDR      (heap, stack, WAD @0x18000000)
//   data  (0x9/0xA/0xB) -> mmio_bridge -> LED / cycle / switches / fb / palette

import rv32im_pkg::*;

module rv32im_doom_core #(
    parameter logic [31:0] RESET_VEC      = 32'h1000_0000,
    parameter int          NUM_LINES      = 256,
    parameter int          WORDS_PER_LINE = 8
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [3:0]  sw,
    output logic [3:0]  led,

    // framebuffer / palette write ports -> video_fb (pixel-clock side elsewhere)
    output logic        fb_we_o,
    output logic [15:0] fb_waddr_o,
    output logic [7:0]  fb_wdata_o,
    output logic        pal_we_o,
    output logic [7:0]  pal_waddr_o,
    output logic [23:0] pal_wdata_o,

    // AXI master I (instruction fills)
    output logic [31:0] m_axi_i_awaddr,  output logic [7:0] m_axi_i_awlen,
    output logic [2:0]  m_axi_i_awsize,  output logic [1:0] m_axi_i_awburst,
    output logic        m_axi_i_awvalid, input  logic        m_axi_i_awready,
    output logic [31:0] m_axi_i_wdata,   output logic [3:0] m_axi_i_wstrb,
    output logic        m_axi_i_wlast,   output logic        m_axi_i_wvalid,
    input  logic        m_axi_i_wready,
    input  logic [1:0]  m_axi_i_bresp,   input  logic        m_axi_i_bvalid,
    output logic        m_axi_i_bready,
    output logic [31:0] m_axi_i_araddr,  output logic [7:0] m_axi_i_arlen,
    output logic [2:0]  m_axi_i_arsize,  output logic [1:0] m_axi_i_arburst,
    output logic        m_axi_i_arvalid, input  logic        m_axi_i_arready,
    input  logic [31:0] m_axi_i_rdata,   input  logic [1:0] m_axi_i_rresp,
    input  logic        m_axi_i_rlast,   input  logic        m_axi_i_rvalid,
    output logic        m_axi_i_rready,

    // AXI master D (data fills + write-backs)
    output logic [31:0] m_axi_d_awaddr,  output logic [7:0] m_axi_d_awlen,
    output logic [2:0]  m_axi_d_awsize,  output logic [1:0] m_axi_d_awburst,
    output logic        m_axi_d_awvalid, input  logic        m_axi_d_awready,
    output logic [31:0] m_axi_d_wdata,   output logic [3:0] m_axi_d_wstrb,
    output logic        m_axi_d_wlast,   output logic        m_axi_d_wvalid,
    input  logic        m_axi_d_wready,
    input  logic [1:0]  m_axi_d_bresp,   input  logic        m_axi_d_bvalid,
    output logic        m_axi_d_bready,
    output logic [31:0] m_axi_d_araddr,  output logic [7:0] m_axi_d_arlen,
    output logic [2:0]  m_axi_d_arsize,  output logic [1:0] m_axi_d_arburst,
    output logic        m_axi_d_arvalid, input  logic        m_axi_d_arready,
    input  logic [31:0] m_axi_d_rdata,   input  logic [1:0] m_axi_d_rresp,
    input  logic        m_axi_d_rlast,   input  logic        m_axi_d_rvalid,
    output logic        m_axi_d_rready
);
    localparam int LINE_W = WORDS_PER_LINE * XLEN;

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

    // ---- I-cache (fetch -> DDR) ----
    logic ic_req, ic_we, ic_done; logic [XLEN-1:0] ic_maddr;
    logic [LINE_W-1:0] ic_wline, ic_rline;
    cache #(.NUM_LINES(NUM_LINES), .WORDS_PER_LINE(WORDS_PER_LINE)) u_icache (
        .clk(clk), .rst_n(rst_n),
        .c_addr(imem_addr), .c_re(1'b1), .c_we(1'b0), .c_funct3(3'b010), .c_wdata(32'd0),
        .c_rdata(imem_data), .c_ready(imem_ready),
        .m_req(ic_req), .m_we(ic_we), .m_addr(ic_maddr),
        .m_wline(ic_wline), .m_rline(ic_rline), .m_done(ic_done)
    );
    axi_burst_master #(.WORDS_PER_LINE(WORDS_PER_LINE)) u_iburst (
        .clk(clk), .rst_n(rst_n),
        .m_req(ic_req), .m_we(ic_we), .m_addr(ic_maddr), .m_wline(ic_wline), .m_rline(ic_rline), .m_done(ic_done),
        .awaddr(m_axi_i_awaddr), .awlen(m_axi_i_awlen), .awsize(m_axi_i_awsize), .awburst(m_axi_i_awburst),
        .awvalid(m_axi_i_awvalid), .awready(m_axi_i_awready),
        .wdata(m_axi_i_wdata), .wstrb(m_axi_i_wstrb), .wlast(m_axi_i_wlast), .wvalid(m_axi_i_wvalid), .wready(m_axi_i_wready),
        .bresp(m_axi_i_bresp), .bvalid(m_axi_i_bvalid), .bready(m_axi_i_bready),
        .araddr(m_axi_i_araddr), .arlen(m_axi_i_arlen), .arsize(m_axi_i_arsize), .arburst(m_axi_i_arburst),
        .arvalid(m_axi_i_arvalid), .arready(m_axi_i_arready),
        .rdata(m_axi_i_rdata), .rresp(m_axi_i_rresp), .rlast(m_axi_i_rlast), .rvalid(m_axi_i_rvalid), .rready(m_axi_i_rready)
    );

    // ---- data routing: 0x1 -> D-cache, else -> mmio_bridge ----
    wire is_ddr = (d_addr[31:28] == 4'h1);

    logic dc_req, dc_we, dc_done; logic [XLEN-1:0] dc_maddr;
    logic [LINE_W-1:0] dc_wline, dc_rline;
    logic [XLEN-1:0] dc_rdata; logic dc_ready;
    cache #(.NUM_LINES(NUM_LINES), .WORDS_PER_LINE(WORDS_PER_LINE)) u_dcache (
        .clk(clk), .rst_n(rst_n),
        .c_addr(d_addr), .c_re(d_re & is_ddr), .c_we(d_we & is_ddr),
        .c_funct3(d_funct3), .c_wdata(d_wdata),
        .c_rdata(dc_rdata), .c_ready(dc_ready),
        .m_req(dc_req), .m_we(dc_we), .m_addr(dc_maddr),
        .m_wline(dc_wline), .m_rline(dc_rline), .m_done(dc_done)
    );
    axi_burst_master #(.WORDS_PER_LINE(WORDS_PER_LINE)) u_dburst (
        .clk(clk), .rst_n(rst_n),
        .m_req(dc_req), .m_we(dc_we), .m_addr(dc_maddr), .m_wline(dc_wline), .m_rline(dc_rline), .m_done(dc_done),
        .awaddr(m_axi_d_awaddr), .awlen(m_axi_d_awlen), .awsize(m_axi_d_awsize), .awburst(m_axi_d_awburst),
        .awvalid(m_axi_d_awvalid), .awready(m_axi_d_awready),
        .wdata(m_axi_d_wdata), .wstrb(m_axi_d_wstrb), .wlast(m_axi_d_wlast), .wvalid(m_axi_d_wvalid), .wready(m_axi_d_wready),
        .bresp(m_axi_d_bresp), .bvalid(m_axi_d_bvalid), .bready(m_axi_d_bready),
        .araddr(m_axi_d_araddr), .arlen(m_axi_d_arlen), .arsize(m_axi_d_arsize), .arburst(m_axi_d_arburst),
        .arvalid(m_axi_d_arvalid), .arready(m_axi_d_arready),
        .rdata(m_axi_d_rdata), .rresp(m_axi_d_rresp), .rlast(m_axi_d_rlast), .rvalid(m_axi_d_rvalid), .rready(m_axi_d_rready)
    );

    // ---- MMIO bridge for the non-DDR data (LED / cycle / switches / fb / palette) ----
    logic [XLEN-1:0] bridge_rdata; logic bridge_ready;
    mmio_bridge u_bridge (
        .clk(clk), .rst_n(rst_n),
        .core_addr_i(d_addr), .core_we_i(d_we & ~is_ddr), .core_re_i(d_re & ~is_ddr),
        .core_funct3_i(d_funct3), .core_wdata_i(d_wdata),
        .core_rdata_o(bridge_rdata), .core_ready_o(bridge_ready),
        .dmem_addr_o(), .dmem_we_o(), .dmem_re_o(), .dmem_funct3_o(), .dmem_wdata_o(),
        .dmem_rdata_i(32'd0),
        .axi_addr_o(), .axi_we_o(), .axi_re_o(), .axi_funct3_o(), .axi_wdata_o(),
        .axi_rdata_i(32'd0), .axi_ready_i(1'b1),
        .mbox_o(), .mbox_ack_i(1'b0), .sw_i(sw),
        .fb_we_o(fb_we_o), .fb_waddr_o(fb_waddr_o), .fb_wdata_o(fb_wdata_o),
        .pal_we_o(pal_we_o), .pal_waddr_o(pal_waddr_o), .pal_wdata_o(pal_wdata_o),
        .led_o(led)
    );

    assign d_rdata = is_ddr ? dc_rdata : bridge_rdata;
    assign d_ready = is_ddr ? dc_ready : bridge_ready;

endmodule : rv32im_doom_core
