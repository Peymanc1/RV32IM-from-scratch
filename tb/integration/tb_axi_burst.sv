// tb_axi_burst.sv
//
// Same cache exercise as tb_cache, but the cache's line interface now goes
// through axi_burst_master -> axi_slave_ddr — i.e. real AXI4 INCR bursts, the
// protocol the PS DDR controller speaks. Proves the burst adapter moves whole
// lines correctly (fill = read burst, write-back = write burst) and that the
// cache is unaffected by swapping the sim ddr_model for the AXI path.
//
// Run: make sim-burst

`timescale 1ns/1ps

import rv32im_pkg::*;

module tb_axi_burst;
    localparam int NUM_LINES = 4;
    localparam int WPL       = 8;
    localparam int LINE_W    = WPL * 32;

    logic clk;
    logic rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // cache core-side
    logic [XLEN-1:0] c_addr, c_wdata, c_rdata;
    logic            c_re, c_we, c_ready;
    logic [2:0]      c_funct3;

    // cache <-> burst master (line interface)
    logic              m_req, m_we, m_done;
    logic [XLEN-1:0]   m_addr;
    logic [LINE_W-1:0] m_wline, m_rline;

    // burst master <-> AXI slave DDR
    logic [31:0] awaddr;  logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst;
    logic        awvalid, awready;
    logic [31:0] wdata;   logic [3:0] wstrb; logic wlast, wvalid, wready;
    logic [1:0]  bresp;   logic bvalid, bready;
    logic [31:0] araddr;  logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst;
    logic        arvalid, arready;
    logic [31:0] rdata;   logic [1:0] rresp; logic rlast, rvalid, rready;

    cache #(.NUM_LINES(NUM_LINES), .WORDS_PER_LINE(WPL)) u_cache (
        .clk(clk), .rst_n(rst_n),
        .c_addr(c_addr), .c_re(c_re), .c_we(c_we), .c_funct3(c_funct3),
        .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ready(c_ready),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr),
        .m_wline(m_wline), .m_rline(m_rline), .m_done(m_done)
    );

    axi_burst_master #(.WORDS_PER_LINE(WPL)) u_burst (
        .clk(clk), .rst_n(rst_n),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr),
        .m_wline(m_wline), .m_rline(m_rline), .m_done(m_done),
        .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
        .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
        .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    axi_slave_ddr #(.MEM_WORDS(1024), .LATENCY(8)) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
        .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
        .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    int errors;

    task automatic do_access(input bit is_write, input [31:0] addr,
                             input [2:0] f3, input [31:0] wd,
                             output [31:0] rd, output int stalls);
        int n;
        n = 0;
        @(negedge clk);
        c_we = is_write; c_re = ~is_write;
        c_addr = addr; c_funct3 = f3; c_wdata = wd;
        #1;
        while (!c_ready) begin
            @(posedge clk); #1; n++;
            if (n > 400) begin $display("FAIL: timeout"); errors++; break; end
        end
        rd = c_rdata;
        @(posedge clk);
        @(negedge clk);
        c_we = 0; c_re = 0;
        stalls = n;
    endtask

    task automatic check(input string name, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL [%s]: got 0x%08h exp 0x%08h", name, got, exp);
            errors++;
        end else $display("PASS [%s]: 0x%08h", name, got);
    endtask

    initial begin
        int sc;
        logic [31:0] rd;

        errors = 0;
        c_re = 0; c_we = 0; c_addr = 0; c_funct3 = 3'b010; c_wdata = 0;
        for (int k = 0; k < 1024; k++) u_ddr.mem[k] = 32'h1000_0000 + k;

        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        $display("=== axi burst tb start (cache -> burst master -> AXI DDR) ===");

        do_access(1'b0, 32'h0000_0000, 3'b010, 0, rd, sc);
        check("cold LW @0x00 (read burst)", rd, 32'h1000_0000);
        if (sc < 8) begin $display("FAIL: miss didn't stall (%0d)", sc); errors++; end
        else $display("PASS [miss stall]: %0d cycles", sc);

        do_access(1'b0, 32'h0000_0004, 3'b010, 0, rd, sc);
        check("hit LW @0x04", rd, 32'h1000_0001);
        if (sc != 0) begin $display("FAIL: hit stalled %0d", sc); errors++; end
        else $display("PASS [hit single-cycle]");

        do_access(1'b1, 32'h0000_0008, 3'b010, 32'hDEAD_BEEF, rd, sc);
        do_access(1'b0, 32'h0000_0008, 3'b010, 0, rd, sc);
        check("readback @0x08", rd, 32'hDEAD_BEEF);

        // evict dirty line (write burst) + fill new line (read burst)
        do_access(1'b0, 32'h0000_0080, 3'b010, 0, rd, sc);
        check("evict(write burst)+fill @0x80", rd, 32'h1000_0020);

        // refill idx0 -> proves the dirty word went back to DDR via write burst
        do_access(1'b0, 32'h0000_0008, 3'b010, 0, rd, sc);
        check("writeback persisted", rd, 32'hDEAD_BEEF);

        $display("=================================================");
        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $display("=================================================");
        $finish;
    end

    initial begin
        $dumpfile("sim/waveform_burst.vcd");
        $dumpvars(0, tb_axi_burst);
    end

endmodule : tb_axi_burst
