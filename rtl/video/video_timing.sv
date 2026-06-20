// video_timing.sv  -  640x480 @ 60 Hz VGA/DVI timing generator
//
// The heart of the HDMI pipeline. Runs on the 25.175 MHz pixel clock (25 MHz
// is close enough for most monitors) and produces the raster scan: horizontal
// and vertical counters, HSYNC/VSYNC, a data-enable (active video) strobe, and
// the active-region pixel coordinates (x, y).
//
// 640x480@60 standard timing (VESA):
//   H: visible 640, front 16, sync 96, back 48  -> 800 total, HSYNC active-low
//   V: visible 480, front 10, sync 2,  back 33  -> 525 total, VSYNC active-low
//
// Downstream: feed x/y (or a framebuffer read) into a pixel source, then the
// {rgb, hsync, vsync, de} bundle goes to a TMDS encoder (Digilent rgb2dvi on
// hardware) for HDMI out. This module is fully testable in simulation.

module video_timing #(
    // horizontal
    parameter int H_VISIBLE = 640,
    parameter int H_FRONT   = 16,
    parameter int H_SYNC    = 96,
    parameter int H_BACK    = 48,
    // vertical
    parameter int V_VISIBLE = 480,
    parameter int V_FRONT   = 10,
    parameter int V_SYNC    = 2,
    parameter int V_BACK    = 33
) (
    input  logic        pclk,        // pixel clock (~25 MHz)
    input  logic        rst_n,

    output logic [11:0] hcount,      // 0 .. H_TOTAL-1
    output logic [11:0] vcount,      // 0 .. V_TOTAL-1
    output logic        hsync,       // active low
    output logic        vsync,       // active low
    output logic        de,          // data enable (1 = active video)
    output logic [11:0] x,           // active pixel column (valid when de)
    output logic [11:0] y            // active pixel row    (valid when de)
);
    localparam int H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;  // 800
    localparam int V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;  // 525

    localparam int H_SYNC_START = H_VISIBLE + H_FRONT;               // 656
    localparam int H_SYNC_END   = H_VISIBLE + H_FRONT + H_SYNC;      // 752
    localparam int V_SYNC_START = V_VISIBLE + V_FRONT;               // 490
    localparam int V_SYNC_END   = V_VISIBLE + V_FRONT + V_SYNC;      // 492

    // ---- raster counters ----
    always_ff @(posedge pclk) begin
        if (!rst_n) begin
            hcount <= 12'd0;
            vcount <= 12'd0;
        end else if (hcount == H_TOTAL-1) begin
            hcount <= 12'd0;
            vcount <= (vcount == V_TOTAL-1) ? 12'd0 : vcount + 12'd1;
        end else begin
            hcount <= hcount + 12'd1;
        end
    end

    // ---- sync / active (combinational from counters) ----
    wire h_active = (hcount < H_VISIBLE);
    wire v_active = (vcount < V_VISIBLE);

    assign hsync = ~((hcount >= H_SYNC_START) && (hcount < H_SYNC_END)); // active low
    assign vsync = ~((vcount >= V_SYNC_START) && (vcount < V_SYNC_END)); // active low
    assign de    = h_active && v_active;
    assign x     = h_active ? hcount : 12'd0;
    assign y     = v_active ? vcount : 12'd0;

endmodule : video_timing
