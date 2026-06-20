// test_pattern.sv  -  8 vertical colour bars from the active pixel column
//
// The classic first HDMI image: put up colour bars to confirm the monitor
// locks to the timing and the TMDS chain works, BEFORE worrying about a
// framebuffer. Takes the timing generator's x and de; outputs 24-bit RGB
// (blanked to black outside active video, as the standard requires).
//
// 640 wide / 8 bars = 80 px each:
//   white  yellow  cyan  green  magenta  red  blue  black

module test_pattern (
    input  logic        de,
    input  logic [11:0] x,
    output logic [7:0]  r,
    output logic [7:0]  g,
    output logic [7:0]  b
);
    logic [2:0] bar;
    always_comb begin
        if      (x >= 560) bar = 3'd7;
        else if (x >= 480) bar = 3'd6;
        else if (x >= 400) bar = 3'd5;
        else if (x >= 320) bar = 3'd4;
        else if (x >= 240) bar = 3'd3;
        else if (x >= 160) bar = 3'd2;
        else if (x >=  80) bar = 3'd1;
        else               bar = 3'd0;
    end

    logic [23:0] rgb;
    always_comb begin
        unique case (bar)
            3'd0: rgb = 24'hFFFFFF;  // white
            3'd1: rgb = 24'hFFFF00;  // yellow
            3'd2: rgb = 24'h00FFFF;  // cyan
            3'd3: rgb = 24'h00FF00;  // green
            3'd4: rgb = 24'hFF00FF;  // magenta
            3'd5: rgb = 24'hFF0000;  // red
            3'd6: rgb = 24'h0000FF;  // blue
            3'd7: rgb = 24'h000000;  // black
            default: rgb = 24'h000000;
        endcase
    end

    // blank outside active video
    assign {r, g, b} = de ? rgb : 24'h000000;

endmodule : test_pattern
