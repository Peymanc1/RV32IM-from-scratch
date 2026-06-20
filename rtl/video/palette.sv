// palette.sv  -  256-entry colour lookup table (8-bit index -> 24-bit RGB)
//
// The framebuffer stores indices; this turns each index into a real colour.
// CPU writes the palette (cpu_clk), video reads it (pixel clock). 256 x 24-bit.

module palette (
    // write side (CPU)
    input  logic        clk_w,
    input  logic        we,
    input  logic [7:0]  waddr,
    input  logic [23:0] wdata,
    // read side (video)
    input  logic        clk_r,
    input  logic [7:0]  raddr,
    output logic [23:0] rdata
);
    logic [23:0] pal [0:255];

    always_ff @(posedge clk_w) if (we) pal[waddr] <= wdata;
    always_ff @(posedge clk_r) rdata <= pal[raddr];   // 1-cycle synchronous read

endmodule : palette
