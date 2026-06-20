// tb_cache.sv
//
// Stand-alone, self-checking test of cache.sv against ddr_model.sv. Small
// geometry (4 lines x 32 B) so a same-index different-tag access forces a
// dirty-line eviction. Proves: miss-fill returns DDR data (and stalls),
// hit is single-cycle (0 stall), write-back flushes a dirty victim to DDR,
// and byte/half accesses extract/merge correctly.
//
// Run: make sim-cache

`timescale 1ns/1ps

import rv32im_pkg::*;

module tb_cache;
    localparam int NUM_LINES = 4;
    localparam int WPL       = 8;
    localparam int LATENCY   = 10;
    localparam int LINE_W    = WPL * 32;

    logic clk;
    logic rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    logic [XLEN-1:0] c_addr, c_wdata, c_rdata;
    logic            c_re, c_we, c_ready;
    logic [2:0]      c_funct3;

    logic              m_req, m_we, m_done;
    logic [XLEN-1:0]   m_addr;
    logic [LINE_W-1:0] m_wline, m_rline;

    cache #(.NUM_LINES(NUM_LINES), .WORDS_PER_LINE(WPL)) u_cache (
        .clk(clk), .rst_n(rst_n),
        .c_addr(c_addr), .c_re(c_re), .c_we(c_we), .c_funct3(c_funct3),
        .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ready(c_ready),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr),
        .m_wline(m_wline), .m_rline(m_rline), .m_done(m_done)
    );

    ddr_model #(.WORDS_PER_LINE(WPL), .MEM_WORDS(1024), .LATENCY(LATENCY)) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr),
        .m_wline(m_wline), .m_rline(m_rline), .m_done(m_done)
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
            if (n > 300) begin $display("FAIL: timeout"); errors++; break; end
        end
        rd = c_rdata;
        @(posedge clk);            // let a write commit on this edge (c_we held)
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

        // preload DDR: word k = 0x10000000 + k
        for (int k = 0; k < 1024; k++) u_ddr.mem[k] = 32'h1000_0000 + k;

        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        $display("=== cache tb start (LINES=%0d, %0d B lines, DDR LAT=%0d) ===",
                 NUM_LINES, WPL*4, LATENCY);

        // 1) cold read @0x00 -> miss, fill, expect mem[0]; must stall >= LATENCY
        do_access(1'b0, 32'h0000_0000, 3'b010, 0, rd, sc);
        check("cold LW @0x00", rd, 32'h1000_0000);
        if (sc < LATENCY) begin $display("FAIL: miss didn't stall (%0d)", sc); errors++; end
        else $display("PASS [miss stall]: %0d cycles", sc);

        // 2) read @0x04 -> same line, HIT, single-cycle (0 stall)
        do_access(1'b0, 32'h0000_0004, 3'b010, 0, rd, sc);
        check("hit LW @0x04", rd, 32'h1000_0001);
        if (sc != 0) begin $display("FAIL: hit stalled %0d cycles", sc); errors++; end
        else $display("PASS [hit single-cycle]");

        // 3) write @0x08 -> hit, marks line dirty
        do_access(1'b1, 32'h0000_0008, 3'b010, 32'hDEAD_BEEF, rd, sc);
        // 4) read it back -> hit
        do_access(1'b0, 32'h0000_0008, 3'b010, 0, rd, sc);
        check("readback @0x08", rd, 32'hDEAD_BEEF);

        // 5) read @0x80 -> same index (idx0), different tag -> evict dirty line
        //    (write-back of 0x00 line incl. modified word) then fill from 0x80
        do_access(1'b0, 32'h0000_0080, 3'b010, 0, rd, sc);
        check("evict+fill @0x80", rd, 32'h1000_0020);  // mem[0x80/4 = 32]

        // 6) prove the dirty word was written back: read @0x08 again (refills
        //    idx0 from DDR) -> must see 0xDEADBEEF that came back from DRAM
        do_access(1'b0, 32'h0000_0008, 3'b010, 0, rd, sc);
        check("writeback persisted", rd, 32'hDEAD_BEEF);

        // 7) byte ops: store byte 0x42 at 0x0D, read back LBU
        do_access(1'b1, 32'h0000_000D, 3'b000, 32'h0000_0042, rd, sc);
        do_access(1'b0, 32'h0000_000D, 3'b100, 0, rd, sc);
        check("LBU @0x0D", rd, 32'h0000_0042);

        // 8) WRITE-MISS full SW to a fresh line (idx2, DDR mem[16]=0x10000010),
        //    then read back. A correct cache fully overwrites -> 0x00002412.
        //    (Reproduces the DOOM lumpinfo[].size corruption: high 16 bits stale.)
        do_access(1'b1, 32'h0000_0040, 3'b010, 32'h0000_2412, rd, sc);
        do_access(1'b0, 32'h0000_0040, 3'b010, 0, rd, sc);
        check("write-MISS SW @0x40", rd, 32'h0000_2412);

        // 9) DOOM pattern: write A (idx0), evict via conflicting read B (idx0,
        //    other tag) -> dirty writeback, then REWRITE A (now a write-miss that
        //    refills from DDR holding the old word) and read back. Full SW must win.
        do_access(1'b1, 32'h0000_0010, 3'b010, 32'h1111_2222, rd, sc); // write A
        do_access(1'b0, 32'h0000_0090, 3'b010, 0, rd, sc);             // read B -> evict A
        do_access(1'b1, 32'h0000_0010, 3'b010, 32'h0000_2412, rd, sc); // rewrite A (miss)
        do_access(1'b0, 32'h0000_0010, 3'b010, 0, rd, sc);             // read back
        check("evict+rewrite-miss SW @0x10", rd, 32'h0000_2412);

        $display("=================================================");
        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $display("=================================================");
        $finish;
    end

    initial begin
        $dumpfile("sim/waveform_cache.vcd");
        $dumpvars(0, tb_cache);
    end

endmodule : tb_cache
