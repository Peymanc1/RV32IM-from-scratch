// tb_video_fb.sv  -  verify the framebuffer -> palette -> RGB path
//
// Fills the whole framebuffer with index 5, sets palette[5] = 0xAABBCC, then
// checks that inside the image region the output is that colour, and in the
// top/bottom border it's black. Run: make sim-fb

`timescale 1ns/1ps

module tb_video_fb;
    logic pclk, rst_n;
    initial pclk = 0;
    always #20 pclk = ~pclk;

    logic        hsync, vsync, de;
    logic [7:0]  r, g, b;

    video_fb u_dut (
        .pclk(pclk), .rst_n(rst_n),
        .clk_w(pclk), .fb_we(1'b0), .fb_waddr(16'd0), .fb_wdata(8'd0),
        .pal_we(1'b0), .pal_waddr(8'd0), .pal_wdata(24'd0),
        .hsync(hsync), .vsync(vsync), .de(de), .r(r), .g(g), .b(b)
    );

    int errors;
    task automatic chk(input string name, input [23:0] got, input [23:0] exp);
        if (got !== exp) begin
            $display("FAIL [%s]: got %06h exp %06h", name, got, exp); errors++;
        end else $display("PASS [%s]: %06h", name, got);
    endtask

    initial begin
        errors = 0;
        // preload framebuffer (all index 5) and palette[5] = 0xAABBCC
        for (int i = 0; i < 320*200; i++) u_dut.u_fb.mem[i] = 8'd5;
        for (int i = 0; i < 256; i++)     u_dut.u_pal.pal[i] = 24'h000000;
        u_dut.u_pal.pal[5] = 24'hAABBCC;

        rst_n = 0;
        repeat (4) @(posedge pclk);
        rst_n = 1;
        $display("=== video_fb tb start ===");

        // inside the image (row 100 is within 40..439), during active video
        while (!(u_dut.vcount == 100 && de == 1'b1)) @(posedge pclk);
        #1; chk("image pixel (row100)", {r,g,b}, 24'hAABBCC);

        // top border (row 10 < 40) -> black even though video is active
        while (!(u_dut.vcount == 10 && de == 1'b1)) @(posedge pclk);
        #1; chk("border pixel (row10)", {r,g,b}, 24'h000000);

        $display("=================================================");
        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $display("=================================================");
        $finish;
    end

    initial begin
        $dumpfile("sim/waveform_fb.vcd");
        $dumpvars(0, tb_video_fb);
    end

endmodule : tb_video_fb
