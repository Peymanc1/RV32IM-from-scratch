// tb_video_timing.sv  -  self-checking test of the 640x480@60 timing generator
//
// Runs one full frame and verifies the raster numbers exactly:
//   - total pixel clocks per frame = 800 * 525 = 420000
//   - active (de=1) pixels         = 640 * 480 = 307200
//   - HSYNC low cycles per frame   = 96 * 525
//   - VSYNC low cycles per frame   = 2  * 800
//
// Run: make sim-video

`timescale 1ns/1ps

module tb_video_timing;
    localparam int H_TOTAL = 800;
    localparam int V_TOTAL = 525;
    localparam int H_VIS   = 640;
    localparam int V_VIS   = 480;
    localparam int H_SYNC  = 96;
    localparam int V_SYNC  = 2;

    logic pclk;
    logic rst_n;
    initial pclk = 0;
    always #20 pclk = ~pclk;   // ~25 MHz

    logic [11:0] hcount, vcount, x, y;
    logic hsync, vsync, de;

    video_timing u_dut (
        .pclk(pclk), .rst_n(rst_n),
        .hcount(hcount), .vcount(vcount),
        .hsync(hsync), .vsync(vsync), .de(de), .x(x), .y(y)
    );

    int errors;

    task automatic check(input string name, input int got, input int exp);
        if (got != exp) begin
            $display("FAIL [%s]: got %0d exp %0d", name, got, exp);
            errors++;
        end else $display("PASS [%s]: %0d", name, got);
    endtask

    initial begin
        int de_cnt, hs_low, vs_low, total;
        errors = 0;
        rst_n = 0;
        repeat (4) @(posedge pclk);
        rst_n = 1;
        $display("=== video_timing tb start (640x480@60) ===");

        // align to a clean frame boundary
        @(posedge pclk);
        while (!(hcount == 0 && vcount == 0)) @(posedge pclk);

        // tally over exactly one frame
        de_cnt = 0; hs_low = 0; vs_low = 0; total = 0;
        do begin
            de_cnt += de;
            hs_low += (hsync == 1'b0);   // hsync active low
            vs_low += (vsync == 1'b0);
            total++;
            @(posedge pclk);
        end while (!(hcount == 0 && vcount == 0));

        check("total pixels/frame", total,  H_TOTAL*V_TOTAL);
        check("active (de) pixels", de_cnt, H_VIS*V_VIS);
        check("hsync low cycles",   hs_low, H_SYNC*V_TOTAL);
        check("vsync low cycles",   vs_low, V_SYNC*H_TOTAL);

        $display("=================================================");
        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $display("=================================================");
        $finish;
    end

    initial begin
        $dumpfile("sim/waveform_video.vcd");
        $dumpvars(0, tb_video_timing);
    end

endmodule : tb_video_timing
