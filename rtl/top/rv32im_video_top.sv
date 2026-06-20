// rv32im_video_top.sv  -  RV32IM draws to an HDMI framebuffer (pure PL, no PS)
//
// Combines the CPU SoC with the video pipeline so the RV32IM's own program
// fills a framebuffer that comes out HDMI:
//
//   board 125MHz ─┬─ rv32im_fpga_top (CPU + bridge + BRAM)  [cpu_clk]
//                 │     └─ writes fb/palette (0xA / 0xB region)
//                 └─ clk_wiz ─ 25MHz pixel + 125MHz serial
//                       └─ video_fb (framebuffer read + palette) [pixel clk]
//                             └─ rgb2dvi (TMDS) ─ HDMI TX
//
// The framebuffer is the dual-clock bridge: CPU writes on cpu_clk, video reads
// on the pixel clock. No PS, no Vitis, no program loader — just a bitstream
// with the drawing program (software/demo_draw.c) baked into BRAM.

module rv32im_video_top (
    input  logic        clk,            // 125 MHz board oscillator (K17)
    input  logic        btn_rst,
    input  logic [3:0]  sw,             // slide switches (game input)
    output logic [3:0]  led,

    output logic        hdmi_tx_clk_p,
    output logic        hdmi_tx_clk_n,
    output logic [2:0]  hdmi_tx_p,
    output logic [2:0]  hdmi_tx_n
);
    // ---- pixel + serial clocks ----
    logic pixclk, serclk, locked;
    clk_wiz_0 u_clk (
        .clk_in1(clk), .clk_out1(pixclk), .clk_out2(serclk), .locked(locked)
    );

    // ---- CPU SoC (board clk); exposes fb/palette writes + cpu_clk ----
    logic        cpu_clk;
    logic        fb_we, pal_we;
    logic [15:0] fb_waddr;
    logic [7:0]  fb_wdata, pal_waddr;
    logic [23:0] pal_wdata;

    // unused AXI master / mailbox ports of the SoC top
    logic [31:0] na_awaddr, na_wdata, na_araddr;
    logic [2:0]  na_awprot, na_arprot;
    logic [3:0]  na_wstrb;
    logic        na_awvalid, na_wvalid, na_bready, na_arvalid, na_rready;
    logic [8:0]  na_mbox;

    rv32im_fpga_top u_soc (
        .clk(clk), .btn_rst(btn_rst), .sw(sw), .led(led),
        .cpu_clk_o(cpu_clk), .cpu_rst_n_o(),
        .mbox_o(na_mbox), .mbox_ack_i(1'b0),
        .fb_we_o(fb_we), .fb_waddr_o(fb_waddr), .fb_wdata_o(fb_wdata),
        .pal_we_o(pal_we), .pal_waddr_o(pal_waddr), .pal_wdata_o(pal_wdata),
        .m_axi_awaddr(na_awaddr), .m_axi_awprot(na_awprot), .m_axi_awvalid(na_awvalid), .m_axi_awready(1'b0),
        .m_axi_wdata(na_wdata),   .m_axi_wstrb(na_wstrb),   .m_axi_wvalid(na_wvalid),   .m_axi_wready(1'b0),
        .m_axi_bresp(2'b00), .m_axi_bvalid(1'b0), .m_axi_bready(na_bready),
        .m_axi_araddr(na_araddr), .m_axi_arprot(na_arprot), .m_axi_arvalid(na_arvalid), .m_axi_arready(1'b0),
        .m_axi_rdata(32'd0), .m_axi_rresp(2'b00), .m_axi_rvalid(1'b0), .m_axi_rready(na_rready)
    );

    // ---- framebuffer-backed video source ----
    logic        hs, vs, de;
    logic [7:0]  r, g, b;
    video_fb u_vid (
        .pclk(pixclk), .rst_n(locked),
        .clk_w(cpu_clk),
        .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata),
        .pal_we(pal_we), .pal_waddr(pal_waddr), .pal_wdata(pal_wdata),
        .hsync(hs), .vsync(vs), .de(de), .r(r), .g(g), .b(b)
    );

    // ---- RGB -> TMDS -> HDMI ----
    rgb2dvi_0 u_dvi (
        .TMDS_Clk_p(hdmi_tx_clk_p), .TMDS_Clk_n(hdmi_tx_clk_n),
        .TMDS_Data_p(hdmi_tx_p),    .TMDS_Data_n(hdmi_tx_n),
        .aRst(~locked),
        .vid_pData({r, g, b}), .vid_pVDE(de), .vid_pHSync(hs), .vid_pVSync(vs),
        .PixelClk(pixclk), .SerialClk(serclk)
    );

endmodule : rv32im_video_top
