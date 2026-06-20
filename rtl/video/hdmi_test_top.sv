// hdmi_test_top.sv  -  standalone HDMI colour-bar bring-up (no CPU/PS)
//
// Smallest design that proves the whole HDMI chain on the Zybo Z7-20: board
// 125 MHz -> clk_wiz -> 25 MHz pixel clock -> video_timing -> test_pattern ->
// rgb2dvi (TMDS) -> HDMI TX pins. No RV32IM, no PS, no program.hex — pure
// fabric. Get this showing colour bars on a monitor FIRST; then we add the
// framebuffer (CPU-drawn) and integrate with the SoC.
//
// IPs (created by scripts/build_hdmi.tcl):
//   clk_wiz_0  : 125 MHz in -> 25 MHz out (+ locked)
//   rgb2dvi_0  : Digilent rgb2dvi, kGenerateSerialClk=true (makes its own 5x
//                serial clock internally), kClkRange=5 (for ~25 MHz pixel)

module hdmi_test_top (
    input  logic        clk,            // 125 MHz board oscillator (K17)

    output logic        hdmi_tx_clk_p,
    output logic        hdmi_tx_clk_n,
    output logic [2:0]  hdmi_tx_p,
    output logic [2:0]  hdmi_tx_n
);
    // 125 MHz -> 25 MHz pixel clock + 125 MHz serial clock (5x, for rgb2dvi)
    logic pixclk, serclk, locked;
    clk_wiz_0 u_clk (
        .clk_in1 (clk),
        .clk_out1(pixclk),
        .clk_out2(serclk),
        .locked  (locked)
    );

    wire rst_n = locked;

    // raster + colour bars
    logic [11:0] hcount, vcount, x, y;
    logic        hsync, vsync, de;
    logic [7:0]  r, g, b;

    video_timing u_tim (
        .pclk(pixclk), .rst_n(rst_n),
        .hcount(hcount), .vcount(vcount),
        .hsync(hsync), .vsync(vsync), .de(de), .x(x), .y(y)
    );
    test_pattern u_pat (.de(de), .x(x), .r(r), .g(g), .b(b));

    // RGB + sync -> TMDS (HDMI). rgb2dvi makes its 5x serial clock internally.
    rgb2dvi_0 u_dvi (
        .TMDS_Clk_p  (hdmi_tx_clk_p),
        .TMDS_Clk_n  (hdmi_tx_clk_n),
        .TMDS_Data_p (hdmi_tx_p),
        .TMDS_Data_n (hdmi_tx_n),
        .aRst        (~locked),               // active-high reset until clocks lock
        .vid_pData   ({r, g, b}),             // {Red, Green, Blue}
        .vid_pVDE    (de),
        .vid_pHSync  (hsync),
        .vid_pVSync  (vsync),
        .PixelClk    (pixclk),
        .SerialClk   (serclk)               // 5x pixel clock from clk_wiz
    );

endmodule : hdmi_test_top
