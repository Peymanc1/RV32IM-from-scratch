// tb_raycast.sv  -  run the raycaster on the real core and ASCII-dump the frame
//
// Instantiates the CPU SoC (rv32im_fpga_top), lets it run the raycaster program
// (program.hex), captures every framebuffer write, and once drawing settles
// renders the 320x200 framebuffer as downsampled ASCII art so we can SEE the
// maze before touching the board. Run: make sim-raycast

`timescale 1ns/1ps

module tb_raycast;
    logic clk, btn_rst;
    initial clk = 0;
    always #5 clk = ~clk;

    // SoC outputs we capture / tie off
    logic [3:0]  led;
    logic        cpu_clk, cpu_rst_n;
    logic [8:0]  mbox;
    logic        fb_we;  logic [15:0] fb_waddr; logic [7:0] fb_wdata;
    logic        pal_we; logic [7:0]  pal_waddr; logic [23:0] pal_wdata;
    logic [31:0] aw, wd, ar; logic [2:0] awp, arp; logic [3:0] ws;
    logic awv, wv, bd, arv, rr;

    logic [3:0] sw_tb;
    rv32im_fpga_top #(.CLK_DIV(2)) u_soc (
        .clk(clk), .btn_rst(btn_rst), .sw(sw_tb), .led(led),
        .cpu_clk_o(cpu_clk), .cpu_rst_n_o(cpu_rst_n),
        .mbox_o(mbox), .mbox_ack_i(1'b0),
        .fb_we_o(fb_we), .fb_waddr_o(fb_waddr), .fb_wdata_o(fb_wdata),
        .pal_we_o(pal_we), .pal_waddr_o(pal_waddr), .pal_wdata_o(pal_wdata),
        .m_axi_awaddr(aw), .m_axi_awprot(awp), .m_axi_awvalid(awv), .m_axi_awready(1'b0),
        .m_axi_wdata(wd), .m_axi_wstrb(ws), .m_axi_wvalid(wv), .m_axi_wready(1'b0),
        .m_axi_bresp(2'b00), .m_axi_bvalid(1'b0), .m_axi_bready(bd),
        .m_axi_araddr(ar), .m_axi_arprot(arp), .m_axi_arvalid(arv), .m_axi_arready(1'b0),
        .m_axi_rdata(32'd0), .m_axi_rresp(2'b00), .m_axi_rvalid(1'b0), .m_axi_rready(rr)
    );

    // capture framebuffer writes (cpu_clk domain)
    logic [7:0] fbmem [0:64000-1];
    int writes, idle;
    always_ff @(posedge cpu_clk) begin
        if (!cpu_rst_n) begin
            writes <= 0; idle <= 0;
        end else if (fb_we) begin
            fbmem[fb_waddr] <= fb_wdata;
            writes <= writes + 1;
            idle   <= 0;
        end else begin
            idle <= idle + 1;
        end
    end

    // ASCII render once drawing has settled (many writes, then quiet)
    task automatic dump_ascii();
        string shades = " .:-=+*#%@";
        $display("=== framebuffer (320x200 -> ~80x40 ASCII) ===");
        for (int y = 0; y < 200; y += 5) begin
            string row = "";
            for (int x = 0; x < 320; x += 4) begin
                int v = fbmem[y*320 + x];
                int s = (v * 9) / 255;          // 0..9
                row = {row, shades[s]};
            end
            $display("%s", row);
        end
        $display("=== writes=%0d   led(=SW read by CPU)=%b ===", writes, led);
        // vertical slice of a few columns (each: 200 rows sampled every 4 -> 50 chars)
        // a correct raycaster shows ceiling(top) / wall(mid) / floor(bottom).
        for (int cx = 40; cx <= 280; cx += 120) begin
            string col = "";
            for (int yy = 0; yy < 200; yy += 4) begin
                int v = fbmem[yy*320 + cx];
                int s = (v * 9) / 255;
                col = {col, shades[s]};
            end
            $display("col x=%0d: %s", cx, col);
        end
        // DEBUG: row0 = lineH(clamped), row1 = dist, per column
        $write("lineH(row0):");
        for (int cx = 0; cx < 320; cx += 32) $write(" %0d", fbmem[cx]);
        $display("");
        $write("dist (row1):");
        for (int cx = 0; cx < 320; cx += 32) $write(" %0d", fbmem[320 + cx]);
        $display("");
        $write("fbmem[0..9]:");
        for (int k = 0; k < 10; k++) $write(" %0d", fbmem[k]);
        $display("");
    endtask

    initial begin
        btn_rst = 1'b1;
        sw_tb = 4'b0000;   // set e.g. 4'b0001 to test turn-left in sim
        #200; btn_rst = 1'b0;
        $display("=== raycaster sim start (SW0=turn-left held) ===");

        // a few rendered frames worth of writes -> view should be rotated
        wait (writes >= 64000 && idle > 2000);
        dump_ascii();
        $finish;
    end

    initial begin
        #50_000_000;                   // safety timeout
        $display("=== TIMEOUT (writes=%0d) ===", writes);
        dump_ascii();
        $finish;
    end

endmodule : tb_raycast
