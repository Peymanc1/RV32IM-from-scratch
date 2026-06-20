// tb_core_ddr.sv
//
// Full-stack integration test: pipelined RV32IM running a real program, with
// the data port split between BRAM (low addresses, single-cycle) and a cached
// DDR region (0x1xxxxxxx -> cache -> ddr_model, multi-cycle). Proves the whole
// chain works together: pipeline + mem_stall back-pressure + cache miss/fill/
// write-back + DDR latency, all while executing compiled C.
//
// Instructions still come from BRAM imem (I-cache is the next step). The
// program (test_ddr.c) writes/reads the DDR region and leaves a checkable
// result in BRAM. Run: make sim-ddr

`timescale 1ns/1ps

import rv32im_pkg::*;

module tb_core_ddr;
    localparam logic [31:0] TOHOST_ADDR  = 32'h8000_1000;
    localparam logic [31:0] RESULT_ADDR  = 32'h8000_1100;
    localparam int          CYCLE_LIMIT  = 50000;
    localparam int          LINE_W       = 8 * 32;

    logic clk;
    logic rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    logic [31:0] imem_addr, imem_data;

    // core data port
    logic [31:0] d_addr, d_wdata, d_rdata;
    logic        d_we, d_re, d_ready;
    logic [2:0]  d_funct3;

    // routing: 0x1xxxxxxx -> cached DDR; everything else -> BRAM dmem
    wire is_ddr = (d_addr[31:28] == 4'h1);

    rv32im_core_pipelined u_dut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr_o(imem_addr), .imem_data_i(imem_data), .imem_ready_i(1'b1),
        .dmem_addr_o(d_addr), .dmem_we_o(d_we), .dmem_re_o(d_re),
        .dmem_funct3_o(d_funct3), .dmem_wdata_o(d_wdata),
        .dmem_rdata_i(d_rdata), .dmem_ready_i(d_ready)
    );

    imem #(.MEM_WORDS(4096), .INIT_FILE("program.hex")) u_imem (
        .addr_i(imem_addr), .inst_o(imem_data)
    );

    // ---- BRAM data memory (non-DDR addresses) ----
    logic [31:0] bram_rdata;
    dmem #(.MEM_WORDS(4096)) u_dmem (
        .clk(clk), .addr_i(d_addr),
        .we_i(d_we & ~is_ddr), .re_i(d_re & ~is_ddr),
        .funct3_i(d_funct3), .write_data_i(d_wdata), .read_data_o(bram_rdata)
    );

    // ---- cache -> AXI burst master -> AXI DDR slave (the real-protocol path) ----
    logic [31:0]     cache_rdata;
    logic            cache_ready;
    logic            m_req, m_we, m_done;
    logic [31:0]     m_addr;
    logic [LINE_W-1:0] m_wline, m_rline;

    cache #(.NUM_LINES(256), .WORDS_PER_LINE(8)) u_cache (
        .clk(clk), .rst_n(rst_n),
        .c_addr(d_addr), .c_re(d_re & is_ddr), .c_we(d_we & is_ddr),
        .c_funct3(d_funct3), .c_wdata(d_wdata),
        .c_rdata(cache_rdata), .c_ready(cache_ready),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr),
        .m_wline(m_wline), .m_rline(m_rline), .m_done(m_done)
    );

    logic [31:0] awaddr; logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst;
    logic awvalid, awready;
    logic [31:0] wdata;  logic [3:0] wstrb; logic wlast, wvalid, wready;
    logic [1:0] bresp;   logic bvalid, bready;
    logic [31:0] araddr; logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst;
    logic arvalid, arready;
    logic [31:0] rdata;  logic [1:0] rresp; logic rlast, rvalid, rready;

    axi_burst_master #(.WORDS_PER_LINE(8)) u_burst (
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

    axi_slave_ddr #(.MEM_WORDS(1<<20), .LATENCY(12)) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
        .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
        .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    // ---- data-port mux ----
    assign d_rdata = is_ddr ? cache_rdata : bram_rdata;
    assign d_ready = is_ddr ? cache_ready : 1'b1;

    // ---- halt detection ----
    logic halted;
    always_ff @(posedge clk) begin
        if (!rst_n) halted <= 1'b0;
        else if (d_we & ~is_ddr & (d_addr == TOHOST_ADDR) & (d_wdata == 32'd1))
            halted <= 1'b1;
    end

    initial begin
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        $display("=== core+DDR integration sim start ===");
    end

    initial begin
        int cyc;
        logic [31:0] result;
        cyc = 0;
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            cyc++;
            if (halted) begin
                result = u_dmem.mem[RESULT_ADDR[13:2]];
                $display("=== halted after %0d cycles ===", cyc);
                $display("RESULT @0x%08h = %0d (0x%08h)", RESULT_ADDR, result, result);
                if (result == 32'd952)
                    $display("=== PASS: cache+DDR sum correct (952) ===");
                else
                    $display("=== FAIL: expected 952, got %0d ===", result);
                $finish;
            end
            if (cyc >= CYCLE_LIMIT) begin
                $display("=== TIMEOUT at %0d cycles ===", cyc);
                $display("RESULT word = %0d", u_dmem.mem[RESULT_ADDR[13:2]]);
                $finish;
            end
        end
    end

    initial begin
        $dumpfile("sim/waveform_ddr.vcd");
        $dumpvars(0, tb_core_ddr);
    end

endmodule : tb_core_ddr
