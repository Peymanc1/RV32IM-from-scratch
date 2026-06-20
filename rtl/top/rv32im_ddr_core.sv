// rv32im_ddr_core.sv  -  RV32IM + D-cache + AXI4 burst master (PS DDR bring-up)
//
// The synthesizable logic that goes INTO the Vivado block design as a cell.
// Same CPU as everywhere else, but the data port is split:
//
//   addr[31:28] == 0x1  ->  D-cache -> axi_burst_master -> M_AXI -> PS S_AXI_HP -> DDR
//   addr[31:28] == 0x9  ->  MMIO (LED at 0x90000000) in the bridge
//   everything else      ->  BRAM dmem (single-cycle), incl. .data/.stack @ 0x8
//
// Instructions still come from BRAM imem (program.hex baked in). This is M1 of
// the DOOM plan: prove the CPU reaches real DDR over AXI bursts on hardware.
//
// One clock for the whole thing: FCLK_CLK0 from the PS (no divider, no CDC —
// the cache, burst master and S_AXI_HP all run synchronous to the CPU). The AXI
// port is named m_axi_* so Vivado's IP integrator auto-bundles it into an AXI4
// master interface when this module is dropped into the BD.

import rv32im_pkg::*;

module rv32im_ddr_core #(
    parameter int IMEM_WORDS     = 4096,
    parameter int DMEM_WORDS     = 4096,
    parameter int NUM_LINES      = 256,
    parameter int WORDS_PER_LINE = 8
) (
    input  logic        clk,            // FCLK_CLK0 from PS
    input  logic        rst_n,          // active-low (proc_sys_reset peripheral_aresetn)
    output logic [3:0]  led,

    // ---- AXI4 master (32-bit) -> SmartConnect -> PS S_AXI_HP0 -> DDR ----
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

    // ---- CPU data + instruction ports ----
    logic [XLEN-1:0]   imem_addr, imem_inst;

    logic [XLEN-1:0]   d_addr, d_wdata, d_rdata;
    logic              d_we, d_re, d_ready;
    logic [2:0]        d_funct3;

    wire is_ddr = (d_addr[31:28] == 4'h1);   // cached DDR region

    rv32im_core_pipelined u_cpu (
        .clk(clk), .rst_n(rst_n),
        .imem_addr_o(imem_addr), .imem_data_i(imem_inst), .imem_ready_i(1'b1),
        .dmem_addr_o(d_addr), .dmem_we_o(d_we), .dmem_re_o(d_re),
        .dmem_funct3_o(d_funct3), .dmem_wdata_o(d_wdata),
        .dmem_rdata_i(d_rdata), .dmem_ready_i(d_ready)
    );

    imem #(.MEM_WORDS(IMEM_WORDS), .INIT_FILE("program.hex")) u_imem (
        .addr_i(imem_addr), .inst_o(imem_inst)
    );

    // ---- MMIO bridge handles BRAM (0x8) + LED (0x9); gated off for DDR ----
    logic [XLEN-1:0] bridge_rdata;
    logic            bridge_ready;
    // bridge's internal DMEM/AXI-lite/fb/pal ports
    logic [XLEN-1:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic            dmem_we, dmem_re;
    logic [2:0]      dmem_funct3;
    logic [XLEN-1:0] al_addr, al_wdata, al_rdata;
    logic            al_we, al_re;
    logic [2:0]      al_funct3;

    mmio_bridge u_bridge (
        .clk(clk), .rst_n(rst_n),
        .core_addr_i(d_addr),
        .core_we_i(d_we & ~is_ddr),
        .core_re_i(d_re & ~is_ddr),
        .core_funct3_i(d_funct3),
        .core_wdata_i(d_wdata),
        .core_rdata_o(bridge_rdata),
        .core_ready_o(bridge_ready),
        .dmem_addr_o(dmem_addr), .dmem_we_o(dmem_we), .dmem_re_o(dmem_re),
        .dmem_funct3_o(dmem_funct3), .dmem_wdata_o(dmem_wdata), .dmem_rdata_i(dmem_rdata),
        .axi_addr_o(al_addr), .axi_we_o(al_we), .axi_re_o(al_re),
        .axi_funct3_o(al_funct3), .axi_wdata_o(al_wdata),
        .axi_rdata_i(32'd0), .axi_ready_i(1'b1),     // no PS-peripheral path here
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

    // ---- D-cache for the DDR region ----
    logic [XLEN-1:0]   cache_rdata;
    logic              cache_ready;
    logic              m_req, m_we, m_done;
    logic [XLEN-1:0]   m_addr;
    logic [LINE_W-1:0] m_wline, m_rline;

    cache #(.NUM_LINES(NUM_LINES), .WORDS_PER_LINE(WORDS_PER_LINE)) u_cache (
        .clk(clk), .rst_n(rst_n),
        .c_addr(d_addr), .c_re(d_re & is_ddr), .c_we(d_we & is_ddr),
        .c_funct3(d_funct3), .c_wdata(d_wdata),
        .c_rdata(cache_rdata), .c_ready(cache_ready),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr),
        .m_wline(m_wline), .m_rline(m_rline), .m_done(m_done)
    );

    axi_burst_master #(.WORDS_PER_LINE(WORDS_PER_LINE)) u_burst (
        .clk(clk), .rst_n(rst_n),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr),
        .m_wline(m_wline), .m_rline(m_rline), .m_done(m_done),
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

    // ---- data-port return mux ----
    assign d_rdata = is_ddr ? cache_rdata : bridge_rdata;
    assign d_ready = is_ddr ? cache_ready : bridge_ready;

endmodule : rv32im_ddr_core
