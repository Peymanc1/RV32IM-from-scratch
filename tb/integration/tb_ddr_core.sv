// tb_ddr_core.sv  -  verify rv32im_ddr_core against the sim DDR slave
//
// Drops the synthesizable BD-cell (CPU + cache + axi_burst_master + LED) onto
// the behavioural axi_slave_ddr standing in for the PS DDR, runs ddr_hw_test,
// and checks the LEDs read 0b0101 (PASS). This is the same hardware datapath
// minus the real PS DDR controller. Run: make sim-ddrcore

`timescale 1ns/1ps
import rv32im_pkg::*;

module tb_ddr_core;
    localparam int CYCLE_LIMIT = 200000;

    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [3:0] led;

    // AXI master <-> sim DDR slave
    logic [31:0] awaddr; logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst;
    logic awvalid, awready;
    logic [31:0] wdata;  logic [3:0] wstrb; logic wlast, wvalid, wready;
    logic [1:0] bresp;   logic bvalid, bready;
    logic [31:0] araddr; logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst;
    logic arvalid, arready;
    logic [31:0] rdata;  logic [1:0] rresp; logic rlast, rvalid, rready;

    rv32im_ddr_core u_dut (
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

    initial begin
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        $display("=== rv32im_ddr_core sim start ===");
    end

    initial begin
        int cyc = 0;
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            cyc++;
            if (led == 4'b0101) begin
                $display("=== PASS: led=0101 after %0d cycles (CPU reached DDR, sum correct) ===", cyc);
                $finish;
            end
            if (led == 4'b1010) begin
                $display("=== FAIL: led=1010 (sum mismatch) ===");
                $finish;
            end
            if (cyc >= CYCLE_LIMIT) begin
                $display("=== TIMEOUT at %0d cycles, led=%b (CPU hung / no DDR response) ===", cyc, led);
                $finish;
            end
        end
    end
endmodule : tb_ddr_core
