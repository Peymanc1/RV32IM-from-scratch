// video_fb.sv  -  framebuffer-backed video source (replaces test_pattern)
//
// Reads the 320x200 framebuffer in raster order, pixel-doubled to 640x400 and
// centred in the 640x480 frame (80px black border top/bottom), looks each index
// up in the palette, and outputs RGB + sync aligned to the pixel stream.
//
// Read latency: framebuffer (1 cyc) + palette (1 cyc) = 2 cyc. We delay de /
// hsync / vsync / in-image by 2 cycles so colour lines up with the timing.
//
// The CPU writes the framebuffer and palette through the write ports (driven
// from the MMIO bridge in the SoC). On HDMI this feeds rgb2dvi exactly like
// test_pattern did.

module video_fb (
    input  logic        pclk,
    input  logic        rst_n,

    // CPU write side (cpu_clk domain)
    input  logic        clk_w,
    input  logic        fb_we,
    input  logic [15:0] fb_waddr,
    input  logic [7:0]  fb_wdata,
    input  logic        pal_we,
    input  logic [7:0]  pal_waddr,
    input  logic [23:0] pal_wdata,

    // video out (to rgb2dvi)
    output logic        hsync,
    output logic        vsync,
    output logic        de,
    output logic [7:0]  r,
    output logic [7:0]  g,
    output logic [7:0]  b
);
    // ---- raster ----
    logic [11:0] hcount, vcount, x, y;
    logic        hs0, vs0, de0;
    video_timing u_tim (
        .pclk(pclk), .rst_n(rst_n),
        .hcount(hcount), .vcount(vcount),
        .hsync(hs0), .vsync(vs0), .de(de0), .x(x), .y(y)
    );

    // ---- framebuffer address (2x doubling, 640x400 centred in 640x480) ----
    wire        in_img = (y >= 40) && (y < 440);     // 400 active rows, 40px border
    wire [8:0]  fb_x   = x[9:1];                       // x / 2  -> 0..319
    wire [7:0]  fb_y   = (y - 12'd40) >> 1;            // (y-40)/2 -> 0..199
    wire [15:0] raddr  = fb_y * 16'd320 + {7'd0, fb_x};

    // ---- framebuffer -> index -> palette -> rgb (2-cycle path) ----
    logic [7:0]  idx;
    logic [23:0] rgb;
    framebuffer u_fb (
        .clk_w(clk_w), .we(fb_we), .waddr(fb_waddr), .wdata(fb_wdata),
        .clk_r(pclk),  .raddr(raddr), .rdata(idx)
    );
    palette u_pal (
        .clk_w(clk_w), .we(pal_we), .waddr(pal_waddr), .wdata(pal_wdata),
        .clk_r(pclk),  .raddr(idx), .rdata(rgb)
    );

    // ---- delay sync/de/in-image by 2 cycles to match the read latency ----
    logic [1:0] de_d, hs_d, vs_d, img_d;
    always_ff @(posedge pclk) begin
        de_d  <= {de_d[0],  de0};
        hs_d  <= {hs_d[0],  hs0};
        vs_d  <= {vs_d[0],  vs0};
        img_d <= {img_d[0], in_img};
    end

    assign hsync = hs_d[1];
    assign vsync = vs_d[1];
    assign de    = de_d[1];

    wire show = de_d[1] && img_d[1];          // active video AND inside the image
    assign {r, g, b} = show ? rgb : 24'h000000;

endmodule : video_fb
