// video_fb_wrap.v - plain-Verilog wrapper around video_fb for the block design.
module video_fb_wrap (
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        clk_w,
    input  wire        fb_we,
    input  wire [15:0] fb_waddr,
    input  wire [7:0]  fb_wdata,
    input  wire        pal_we,
    input  wire [7:0]  pal_waddr,
    input  wire [23:0] pal_wdata,
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b
);
    video_fb u_fb (
        .pclk(pclk), .rst_n(rst_n), .clk_w(clk_w),
        .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata),
        .pal_we(pal_we), .pal_waddr(pal_waddr), .pal_wdata(pal_wdata),
        .hsync(hsync), .vsync(vsync), .de(de), .r(r), .g(g), .b(b)
    );
endmodule
