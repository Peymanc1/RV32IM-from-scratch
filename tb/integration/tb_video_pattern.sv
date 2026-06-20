// tb_video_pattern.sv  -  verify colour bars come out at the right columns
//
// Runs timing + test_pattern, and on an active row samples the RGB at a few
// columns, checking the expected bar colour. Run: make sim-pattern

`timescale 1ns/1ps

module tb_video_pattern;
    logic pclk;
    logic rst_n;
    initial pclk = 0;
    always #20 pclk = ~pclk;

    logic [11:0] hcount, vcount, x, y;
    logic hsync, vsync, de;
    logic [7:0] r, g, b;

    video_timing u_tim (
        .pclk(pclk), .rst_n(rst_n),
        .hcount(hcount), .vcount(vcount),
        .hsync(hsync), .vsync(vsync), .de(de), .x(x), .y(y)
    );
    test_pattern u_pat (.de(de), .x(x), .r(r), .g(g), .b(b));

    int errors;

    task automatic chk(input string name, input [23:0] got, input [23:0] exp);
        if (got !== exp) begin
            $display("FAIL [%s]: got %06h exp %06h", name, got, exp);
            errors++;
        end else $display("PASS [%s]: %06h", name, got);
    endtask

    // sample the colour at a given active column on the current row
    task automatic sample_at(input int col, input [23:0] exp, input string name);
        // advance within the active row until x == col while de
        while (!(de && x == col)) @(posedge pclk);
        #1;
        chk(name, {r, g, b}, exp);
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        repeat (4) @(posedge pclk);
        rst_n = 1;
        $display("=== video_pattern tb start ===");

        // get to an active row (y around 100)
        while (!(de && y == 100 && x == 0)) @(posedge pclk);

        sample_at(10,  24'hFFFFFF, "bar0 white  @x=10");
        sample_at(100, 24'hFFFF00, "bar1 yellow @x=100");
        sample_at(300, 24'h00FF00, "bar3 green  @x=300");  // 240..319
        sample_at(450, 24'hFF0000, "bar5 red    @x=450");
        sample_at(600, 24'h000000, "bar7 black  @x=600");

        $display("=================================================");
        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $display("=================================================");
        $finish;
    end

    initial begin
        $dumpfile("sim/waveform_pattern.vcd");
        $dumpvars(0, tb_video_pattern);
    end

endmodule : tb_video_pattern
