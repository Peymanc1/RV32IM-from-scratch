// framebuffer.sv  -  320x200 8-bit indexed framebuffer (true dual-port BRAM)
//
// Write port: the RV32IM (cpu_clk domain) stores a colour index per pixel.
// Read port:  the video pipeline (pixel-clock domain) reads it in raster order.
// Two independent clocks -> true dual-port BRAM, which the Z7-20 has plenty of
// (64000 bytes ~= 16 BRAM36). DOOM's native format is exactly this: one byte
// (palette index) per pixel.

module framebuffer #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 200
) (
    // write side (CPU)
    input  logic        clk_w,
    input  logic        we,
    input  logic [15:0] waddr,
    input  logic [7:0]  wdata,
    // read side (video)
    input  logic        clk_r,
    input  logic [15:0] raddr,
    output logic [7:0]  rdata
);
    localparam int N = WIDTH * HEIGHT;   // 64000
    logic [7:0] mem [0:N-1];

    always_ff @(posedge clk_w) if (we) mem[waddr] <= wdata;
    always_ff @(posedge clk_r) rdata <= mem[raddr];   // 1-cycle synchronous read

endmodule : framebuffer
