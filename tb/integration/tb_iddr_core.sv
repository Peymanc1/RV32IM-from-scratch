// tb_iddr_core.sv  -  M2b: verify the CPU fetches & runs code from DDR
//
// The DDR slave is PRELOADED with the program's .text (program.hex). The CPU
// boots at 0x10000000 and every instruction is fetched through the I-cache ->
// axi_burst_master -> DDR. Data/stack are BRAM (internal). PASS = LED 0b0101.
// Run: make sim-iddr

`timescale 1ns/1ps
import rv32im_pkg::*;

module tb_iddr_core;
    localparam int CYCLE_LIMIT = 300000;

    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [3:0] led;

    logic [31:0] awaddr; logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst;
    logic awvalid, awready;
    logic [31:0] wdata;  logic [3:0] wstrb; logic wlast, wvalid, wready;
    logic [1:0] bresp;   logic bvalid, bready;
    logic [31:0] araddr; logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst;
    logic arvalid, arready;
    logic [31:0] rdata;  logic [1:0] rresp; logic rlast, rvalid, rready;

    rv32im_iddr_core u_dut (
        .clk(clk), .rst_n(rst_n), .led(led),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    // DDR preloaded with the program .text (fetched by the I-cache)
    axi_slave_ddr #(.MEM_WORDS(1<<20), .LATENCY(12), .INIT_FILE("program.hex")) u_ddr (
        .clk(clk), .rst_n(rst_n),
        .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
        .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
        .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    initial begin
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        $display("=== rv32im_iddr_core sim start (fetch from DDR) ===");
    end

    initial begin
        int cyc = 0;
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            cyc++;
            if (led == 4'b0101) begin
                $display("=== PASS: led=0101 after %0d cycles (CPU ran from DDR) ===", cyc);
                $finish;
            end
            if (led == 4'b1010) begin
                $display("=== FAIL: led=1010 (wrong result) ===");
                $finish;
            end
            if (cyc >= CYCLE_LIMIT) begin
                $display("=== TIMEOUT at %0d cycles, led=%b ===", cyc, led);
                $finish;
            end
        end
    end
endmodule : tb_iddr_core
