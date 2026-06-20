// rv32im_unified_core.sv  -  M3: EVERYTHING in DDR (code + data + heap + stack)
//
// Both the fetch port and the data port go through their own cache to DDR:
//
//   fetch (0x1xxxxxxx)  -> I-cache (read-only)  -> i-burst -> M_AXI_I -> DDR
//   data  (0x1xxxxxxx)  -> D-cache (write-back) -> d-burst -> M_AXI_D -> DDR
//   data  (0x9.......)  -> MMIO (LED)                       (single-cycle)
//
// Two AXI masters; in the BD a SmartConnect with 2 SI arbitrates them onto one
// S_AXI_HP. No BRAM dmem/imem at all -> the whole program image (text, rodata,
// data, bss, heap, stack) lives in DDR. This is the memory model DOOM needs.

import rv32im_pkg::*;

module rv32im_unified_core #(
    parameter logic [31:0] RESET_VEC      = 32'h1000_0000,
    parameter int          NUM_LINES      = 256,
    parameter int          WORDS_PER_LINE = 8
) (
    input  logic        clk,
    input  logic        rst_n,
    output logic [3:0]  led,

    // ---- AXI master I (instruction fills) ----
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

    // ---- AXI master D (data load/store fills + write-backs) ----
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

    // ================= instruction path: I-cache -> DDR =================
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
        .m_req(ic_req), .m_we(ic_we), .m_addr(ic_maddr),
        .m_wline(ic_wline), .m_rline(ic_rline), .m_done(ic_done),
        .awaddr(m_axi_i_awaddr), .awlen(m_axi_i_awlen), .awsize(m_axi_i_awsize),
        .awburst(m_axi_i_awburst), .awvalid(m_axi_i_awvalid), .awready(m_axi_i_awready),
        .wdata(m_axi_i_wdata), .wstrb(m_axi_i_wstrb), .wlast(m_axi_i_wlast),
        .wvalid(m_axi_i_wvalid), .wready(m_axi_i_wready),
        .bresp(m_axi_i_bresp), .bvalid(m_axi_i_bvalid), .bready(m_axi_i_bready),
        .araddr(m_axi_i_araddr), .arlen(m_axi_i_arlen), .arsize(m_axi_i_arsize),
        .arburst(m_axi_i_arburst), .arvalid(m_axi_i_arvalid), .arready(m_axi_i_arready),
        .rdata(m_axi_i_rdata), .rresp(m_axi_i_rresp), .rlast(m_axi_i_rlast),
        .rvalid(m_axi_i_rvalid), .rready(m_axi_i_rready)
    );

    // ================= data path: D-cache (0x1) -> DDR, MMIO (0x9) ======
    wire is_ddr  = (d_addr[31:28] == 4'h1);
    wire is_mmio = (d_addr[31:28] == 4'h9);

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
        .m_req(dc_req), .m_we(dc_we), .m_addr(dc_maddr),
        .m_wline(dc_wline), .m_rline(dc_rline), .m_done(dc_done),
        .awaddr(m_axi_d_awaddr), .awlen(m_axi_d_awlen), .awsize(m_axi_d_awsize),
        .awburst(m_axi_d_awburst), .awvalid(m_axi_d_awvalid), .awready(m_axi_d_awready),
        .wdata(m_axi_d_wdata), .wstrb(m_axi_d_wstrb), .wlast(m_axi_d_wlast),
        .wvalid(m_axi_d_wvalid), .wready(m_axi_d_wready),
        .bresp(m_axi_d_bresp), .bvalid(m_axi_d_bvalid), .bready(m_axi_d_bready),
        .araddr(m_axi_d_araddr), .arlen(m_axi_d_arlen), .arsize(m_axi_d_arsize),
        .arburst(m_axi_d_arburst), .arvalid(m_axi_d_arvalid), .arready(m_axi_d_arready),
        .rdata(m_axi_d_rdata), .rresp(m_axi_d_rresp), .rlast(m_axi_d_rlast),
        .rvalid(m_axi_d_rvalid), .rready(m_axi_d_rready)
    );

    // LED register (the only MMIO needed here)
    logic [3:0] led_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                                          led_reg <= 4'd0;
        else if (is_mmio & d_we & (d_addr[7:0] == 8'h00))    led_reg <= d_wdata[3:0];
    end
    assign led = led_reg;

    assign d_rdata = is_ddr  ? dc_rdata :
                     is_mmio ? {28'd0, led_reg} : 32'd0;
    assign d_ready = is_ddr  ? dc_ready : 1'b1;

endmodule : rv32im_unified_core
