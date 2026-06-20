// rv32im_doom_wrap.v - plain-Verilog wrapper around rv32im_doom_core for the BD.
module rv32im_doom_wrap (
    input  wire        clk, rst_n,
    input  wire [3:0]  sw,
    output wire [3:0]  led,
    output wire        fb_we, output wire [15:0] fb_waddr, output wire [7:0] fb_wdata,
    output wire        pal_we, output wire [7:0] pal_waddr, output wire [23:0] pal_wdata,
    // m_axi_i
    output wire [31:0] m_axi_i_awaddr, output wire [7:0] m_axi_i_awlen, output wire [2:0] m_axi_i_awsize,
    output wire [1:0] m_axi_i_awburst, output wire m_axi_i_awvalid, input wire m_axi_i_awready,
    output wire [31:0] m_axi_i_wdata, output wire [3:0] m_axi_i_wstrb, output wire m_axi_i_wlast,
    output wire m_axi_i_wvalid, input wire m_axi_i_wready,
    input wire [1:0] m_axi_i_bresp, input wire m_axi_i_bvalid, output wire m_axi_i_bready,
    output wire [31:0] m_axi_i_araddr, output wire [7:0] m_axi_i_arlen, output wire [2:0] m_axi_i_arsize,
    output wire [1:0] m_axi_i_arburst, output wire m_axi_i_arvalid, input wire m_axi_i_arready,
    input wire [31:0] m_axi_i_rdata, input wire [1:0] m_axi_i_rresp, input wire m_axi_i_rlast,
    input wire m_axi_i_rvalid, output wire m_axi_i_rready,
    // m_axi_d
    output wire [31:0] m_axi_d_awaddr, output wire [7:0] m_axi_d_awlen, output wire [2:0] m_axi_d_awsize,
    output wire [1:0] m_axi_d_awburst, output wire m_axi_d_awvalid, input wire m_axi_d_awready,
    output wire [31:0] m_axi_d_wdata, output wire [3:0] m_axi_d_wstrb, output wire m_axi_d_wlast,
    output wire m_axi_d_wvalid, input wire m_axi_d_wready,
    input wire [1:0] m_axi_d_bresp, input wire m_axi_d_bvalid, output wire m_axi_d_bready,
    output wire [31:0] m_axi_d_araddr, output wire [7:0] m_axi_d_arlen, output wire [2:0] m_axi_d_arsize,
    output wire [1:0] m_axi_d_arburst, output wire m_axi_d_arvalid, input wire m_axi_d_arready,
    input wire [31:0] m_axi_d_rdata, input wire [1:0] m_axi_d_rresp, input wire m_axi_d_rlast,
    input wire m_axi_d_rvalid, output wire m_axi_d_rready
);
    rv32im_doom_core u_core (
        .clk(clk), .rst_n(rst_n), .sw(sw), .led(led),
        .fb_we_o(fb_we), .fb_waddr_o(fb_waddr), .fb_wdata_o(fb_wdata),
        .pal_we_o(pal_we), .pal_waddr_o(pal_waddr), .pal_wdata_o(pal_wdata),
        .m_axi_i_awaddr(m_axi_i_awaddr), .m_axi_i_awlen(m_axi_i_awlen), .m_axi_i_awsize(m_axi_i_awsize),
        .m_axi_i_awburst(m_axi_i_awburst), .m_axi_i_awvalid(m_axi_i_awvalid), .m_axi_i_awready(m_axi_i_awready),
        .m_axi_i_wdata(m_axi_i_wdata), .m_axi_i_wstrb(m_axi_i_wstrb), .m_axi_i_wlast(m_axi_i_wlast),
        .m_axi_i_wvalid(m_axi_i_wvalid), .m_axi_i_wready(m_axi_i_wready),
        .m_axi_i_bresp(m_axi_i_bresp), .m_axi_i_bvalid(m_axi_i_bvalid), .m_axi_i_bready(m_axi_i_bready),
        .m_axi_i_araddr(m_axi_i_araddr), .m_axi_i_arlen(m_axi_i_arlen), .m_axi_i_arsize(m_axi_i_arsize),
        .m_axi_i_arburst(m_axi_i_arburst), .m_axi_i_arvalid(m_axi_i_arvalid), .m_axi_i_arready(m_axi_i_arready),
        .m_axi_i_rdata(m_axi_i_rdata), .m_axi_i_rresp(m_axi_i_rresp), .m_axi_i_rlast(m_axi_i_rlast),
        .m_axi_i_rvalid(m_axi_i_rvalid), .m_axi_i_rready(m_axi_i_rready),
        .m_axi_d_awaddr(m_axi_d_awaddr), .m_axi_d_awlen(m_axi_d_awlen), .m_axi_d_awsize(m_axi_d_awsize),
        .m_axi_d_awburst(m_axi_d_awburst), .m_axi_d_awvalid(m_axi_d_awvalid), .m_axi_d_awready(m_axi_d_awready),
        .m_axi_d_wdata(m_axi_d_wdata), .m_axi_d_wstrb(m_axi_d_wstrb), .m_axi_d_wlast(m_axi_d_wlast),
        .m_axi_d_wvalid(m_axi_d_wvalid), .m_axi_d_wready(m_axi_d_wready),
        .m_axi_d_bresp(m_axi_d_bresp), .m_axi_d_bvalid(m_axi_d_bvalid), .m_axi_d_bready(m_axi_d_bready),
        .m_axi_d_araddr(m_axi_d_araddr), .m_axi_d_arlen(m_axi_d_arlen), .m_axi_d_arsize(m_axi_d_arsize),
        .m_axi_d_arburst(m_axi_d_arburst), .m_axi_d_arvalid(m_axi_d_arvalid), .m_axi_d_arready(m_axi_d_arready),
        .m_axi_d_rdata(m_axi_d_rdata), .m_axi_d_rresp(m_axi_d_rresp), .m_axi_d_rlast(m_axi_d_rlast),
        .m_axi_d_rvalid(m_axi_d_rvalid), .m_axi_d_rready(m_axi_d_rready)
    );
endmodule
