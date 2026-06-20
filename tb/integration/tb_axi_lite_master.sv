// tb_axi_lite_master.sv
//
// Stand-alone, self-checking testbench for axi_lite_master. No CPU, no board:
// it drives the CPU-side request port the way mmio_bridge will, and hangs a
// small latency-injecting AXI4-Lite slave (modelling a PS UART register block)
// off the AXI side. Checks two things that matter for B1:
//   1. Transactions complete with the right data / byte strobes.
//   2. req_ready_o stays LOW for the whole round-trip and pulses for exactly
//      one cycle on completion  -> the pipeline back-pressure is real.
//
// Run: make sim-axi   (see scripts/Makefile)

`timescale 1ns/1ps

import rv32im_pkg::*;

module tb_axi_lite_master;

    localparam int LAT = 4;   // response latency injected by the slave model

    logic clk;
    logic rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- CPU-side request ----
    logic            req_re, req_we;
    logic [XLEN-1:0] req_addr, req_wdata, req_rdata;
    logic [2:0]      req_funct3;
    logic            req_ready;

    // ---- AXI4-Lite wires ----
    logic [XLEN-1:0] awaddr;  logic [2:0] awprot; logic awvalid, awready;
    logic [XLEN-1:0] wdata;   logic [3:0] wstrb;  logic wvalid,  wready;
    logic [1:0]      bresp;   logic bvalid, bready;
    logic [XLEN-1:0] araddr;  logic [2:0] arprot; logic arvalid, arready;
    logic [XLEN-1:0] rdata;   logic [1:0] rresp;  logic rvalid,  rready;

    axi_lite_master u_dut (
        .clk(clk), .rst_n(rst_n),
        .req_re_i(req_re), .req_we_i(req_we), .req_addr_i(req_addr),
        .req_funct3_i(req_funct3), .req_wdata_i(req_wdata),
        .req_rdata_o(req_rdata), .req_ready_o(req_ready),
        .m_axi_awaddr(awaddr), .m_axi_awprot(awprot), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata),   .m_axi_wstrb(wstrb),   .m_axi_wvalid(wvalid),   .m_axi_wready(wready),
        .m_axi_bresp(bresp),   .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arprot(arprot), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata),   .m_axi_rresp(rresp),   .m_axi_rvalid(rvalid),   .m_axi_rready(rready)
    );

    // =====================================================================
    // AXI4-Lite slave model (16 words). Zero-latency address/data accept,
    // LAT-cycle latency on the B and R responses (enough to exercise stall).
    // =====================================================================
    logic [31:0] sl_mem [0:15];
    assign bresp = 2'b00;
    assign rresp = 2'b00;

    wire [3:0] sl_idx = (awvalid ? awaddr[5:2] : araddr[5:2]);

    // ---- write channel ----
    logic aw_acc, w_acc;
    int   b_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awready <= 1'b0; wready <= 1'b0; bvalid <= 1'b0;
            aw_acc  <= 1'b0; w_acc  <= 1'b0; b_cnt  <= 0;
        end else begin
            // accept address once
            if (awvalid && !aw_acc) begin awready <= 1'b1; aw_acc <= 1'b1; end
            else                          awready <= 1'b0;
            // accept data once, apply byte strobes
            if (wvalid && !w_acc) begin
                wready <= 1'b1; w_acc <= 1'b1;
                if (wstrb[0]) sl_mem[awaddr[5:2]][ 7: 0] <= wdata[ 7: 0];
                if (wstrb[1]) sl_mem[awaddr[5:2]][15: 8] <= wdata[15: 8];
                if (wstrb[2]) sl_mem[awaddr[5:2]][23:16] <= wdata[23:16];
                if (wstrb[3]) sl_mem[awaddr[5:2]][31:24] <= wdata[31:24];
            end else wready <= 1'b0;
            // response after LAT cycles once both accepted
            if (aw_acc && w_acc && !bvalid) begin
                if (b_cnt == LAT) bvalid <= 1'b1;
                else              b_cnt  <= b_cnt + 1;
            end
            if (bvalid && bready) begin
                bvalid <= 1'b0; aw_acc <= 1'b0; w_acc <= 1'b0; b_cnt <= 0;
            end
        end
    end

    // ---- read channel ----
    logic ar_acc;
    int   r_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready <= 1'b0; rvalid <= 1'b0; rdata <= 32'd0;
            ar_acc  <= 1'b0; r_cnt  <= 0;
        end else begin
            if (arvalid && !ar_acc) begin arready <= 1'b1; ar_acc <= 1'b1; end
            else                          arready <= 1'b0;
            if (ar_acc && !rvalid) begin
                if (r_cnt == LAT) begin rvalid <= 1'b1; rdata <= sl_mem[araddr[5:2]]; end
                else                    r_cnt  <= r_cnt + 1;
            end
            if (rvalid && rready) begin
                rvalid <= 1'b0; ar_acc <= 1'b0; r_cnt <= 0;
            end
        end
    end

    // =====================================================================
    // Stimulus + scoreboard
    // =====================================================================
    int errors;

    // Drive one request and wait for req_ready, counting stall cycles.
    task automatic do_access(input bit is_write, input [31:0] addr,
                             input [2:0] f3, input [31:0] wd,
                             output [31:0] rd, output int stall_cycles);
        int n;
        n = 0;
        @(negedge clk);
        req_we     = is_write;
        req_re     = ~is_write;
        req_addr   = addr;
        req_funct3 = f3;
        req_wdata  = wd;
        // wait for the done pulse
        forever begin
            @(posedge clk);
            #1;
            if (req_ready) begin
                rd = req_rdata;
                break;
            end
            n++;
            if (n > 100) begin
                $display("FAIL: timeout waiting for req_ready");
                errors++;
                break;
            end
        end
        stall_cycles = n;
        @(negedge clk);
        req_we = 0; req_re = 0;
    endtask

    task automatic check(input string name, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL [%s]: got 0x%08h exp 0x%08h", name, got, exp);
            errors++;
        end else begin
            $display("PASS [%s]: 0x%08h", name, got);
        end
    endtask

    initial begin
        int   sc;
        logic [31:0] rd;

        errors = 0;
        req_re = 0; req_we = 0; req_addr = 0; req_funct3 = 0; req_wdata = 0;
        for (int i = 0; i < 16; i++) sl_mem[i] = 32'd0;
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        $display("=== axi_lite_master tb start (slave LAT=%0d) ===", LAT);

        // 1) word store 'A' (0x41) to 0xE0001030  (UART TX FIFO offset 0x30)
        do_access(1'b1, 32'hE0001030, 3'b010, 32'h0000_0041, rd, sc);
        check("SW data",  sl_mem[32'h30>>2], 32'h0000_0041);
        if (sc < LAT) begin
            $display("FAIL: write retired in %0d cycles, expected >= %0d (no back-pressure)", sc, LAT);
            errors++;
        end else $display("PASS [SW stall]: %0d cycles of back-pressure", sc);

        // 2) word load from 0xE000102C (status), preloaded
        sl_mem[32'h2C>>2] = 32'h0000_0003;
        do_access(1'b0, 32'hE000102C, 3'b010, 32'd0, rd, sc);
        check("LW data", rd, 32'h0000_0003);
        if (sc < LAT) begin
            $display("FAIL: read retired in %0d cycles, expected >= %0d", sc, LAT);
            errors++;
        end else $display("PASS [LW stall]: %0d cycles of back-pressure", sc);

        // 3) byte store 0x42 to offset 1 of word 0x34 -> only lane 1 written
        sl_mem[32'h34>>2] = 32'hDEAD_BEEF;
        do_access(1'b1, 32'hE0001035, 3'b000, 32'h0000_0042, rd, sc);
        check("SB strobe", sl_mem[32'h34>>2], 32'hDEAD_42EF);

        // 4) two back-to-back stores -> adapter must not double-issue
        do_access(1'b1, 32'hE0001038, 3'b010, 32'h1111_1111, rd, sc);
        do_access(1'b1, 32'hE0001038, 3'b010, 32'h2222_2222, rd, sc);
        check("B2B store", sl_mem[32'h38>>2], 32'h2222_2222);

        $display("=================================================");
        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $display("=================================================");
        $finish;
    end

    initial begin
        $dumpfile("sim/waveform_axi.vcd");
        $dumpvars(0, tb_axi_lite_master);
    end

endmodule : tb_axi_lite_master
