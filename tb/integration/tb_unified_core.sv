// tb_unified_core.sv  -  M3: verify code AND data both run from DDR
//
// Two DDR slaves (one per master), both preloaded with the program image. The
// I-cache reads .text from the I-slave; the D-cache reads/writes the disjoint
// data/stack region of the D-slave. PASS = LED 0b0101. Run: make sim-unified

`timescale 1ns/1ps
import rv32im_pkg::*;

module tb_unified_core;
    localparam int CYCLE_LIMIT = 3000000;
    logic clk = 0, rst_n;
    always #5 clk = ~clk;
    logic [3:0] led;

    // master I
    logic [31:0] iaw, iwd, iar; logic [7:0] iawl, iarl; logic [2:0] iaws, iars;
    logic [1:0] iawb, iarb, ibr, irr2; logic [3:0] iws;
    logic iawv, iawr, iwv, iwr, iwl, ibv, ibrd, iarv, iarr, irv, irl, irrd;
    logic [31:0] ird;
    // master D
    logic [31:0] daw, dwd, dar; logic [7:0] dawl, darl; logic [2:0] daws, dars;
    logic [1:0] dawb, darb, dbr, drr2; logic [3:0] dws;
    logic dawv, dawr, dwv, dwr, dwl, dbv, dbrd, darv, darr, drv, drl, drrd;
    logic [31:0] drd;

    rv32im_unified_core u_dut (
        .clk(clk), .rst_n(rst_n), .led(led),
        .m_axi_i_awaddr(iaw), .m_axi_i_awlen(iawl), .m_axi_i_awsize(iaws), .m_axi_i_awburst(iawb),
        .m_axi_i_awvalid(iawv), .m_axi_i_awready(iawr),
        .m_axi_i_wdata(iwd), .m_axi_i_wstrb(iws), .m_axi_i_wlast(iwl), .m_axi_i_wvalid(iwv), .m_axi_i_wready(iwr),
        .m_axi_i_bresp(ibr), .m_axi_i_bvalid(ibv), .m_axi_i_bready(ibrd),
        .m_axi_i_araddr(iar), .m_axi_i_arlen(iarl), .m_axi_i_arsize(iars), .m_axi_i_arburst(iarb),
        .m_axi_i_arvalid(iarv), .m_axi_i_arready(iarr),
        .m_axi_i_rdata(ird), .m_axi_i_rresp(irr2), .m_axi_i_rlast(irl), .m_axi_i_rvalid(irv), .m_axi_i_rready(irrd),
        .m_axi_d_awaddr(daw), .m_axi_d_awlen(dawl), .m_axi_d_awsize(daws), .m_axi_d_awburst(dawb),
        .m_axi_d_awvalid(dawv), .m_axi_d_awready(dawr),
        .m_axi_d_wdata(dwd), .m_axi_d_wstrb(dws), .m_axi_d_wlast(dwl), .m_axi_d_wvalid(dwv), .m_axi_d_wready(dwr),
        .m_axi_d_bresp(dbr), .m_axi_d_bvalid(dbv), .m_axi_d_bready(dbrd),
        .m_axi_d_araddr(dar), .m_axi_d_arlen(darl), .m_axi_d_arsize(dars), .m_axi_d_arburst(darb),
        .m_axi_d_arvalid(darv), .m_axi_d_arready(darr),
        .m_axi_d_rdata(drd), .m_axi_d_rresp(drr2), .m_axi_d_rlast(drl), .m_axi_d_rvalid(drv), .m_axi_d_rready(drrd)
    );

    axi_slave_ddr #(.MEM_WORDS(1<<20), .LATENCY(12), .INIT_FILE("program.hex")) u_iddr (
        .clk(clk), .rst_n(rst_n),
        .awaddr(iaw), .awlen(iawl), .awsize(iaws), .awburst(iawb), .awvalid(iawv), .awready(iawr),
        .wdata(iwd), .wstrb(iws), .wlast(iwl), .wvalid(iwv), .wready(iwr),
        .bresp(ibr), .bvalid(ibv), .bready(ibrd),
        .araddr(iar), .arlen(iarl), .arsize(iars), .arburst(iarb), .arvalid(iarv), .arready(iarr),
        .rdata(ird), .rresp(irr2), .rlast(irl), .rvalid(irv), .rready(irrd)
    );
    axi_slave_ddr #(.MEM_WORDS(1<<20), .LATENCY(12), .INIT_FILE("program.hex")) u_dddr (
        .clk(clk), .rst_n(rst_n),
        .awaddr(daw), .awlen(dawl), .awsize(daws), .awburst(dawb), .awvalid(dawv), .awready(dawr),
        .wdata(dwd), .wstrb(dws), .wlast(dwl), .wvalid(dwv), .wready(dwr),
        .bresp(dbr), .bvalid(dbv), .bready(dbrd),
        .araddr(dar), .arlen(darl), .arsize(dars), .arburst(darb), .arvalid(darv), .arready(darr),
        .rdata(drd), .rresp(drr2), .rlast(drl), .rvalid(drv), .rready(drrd)
    );

    initial begin
        rst_n = 0; repeat (4) @(posedge clk); rst_n = 1;
        $display("=== rv32im_unified_core sim start (code+data from DDR) ===");
    end

    // DEBUG: dump memset args (a0/a1/a2=len) on first entry
    logic mseen=0;
    always @(posedge clk) if (rst_n && !mseen && u_dut.imem_addr==32'h10000030) begin
        mseen<=1;
        $display("  memset args: a0(ptr)=%08h a1(val)=%08h a2(len)=%08h",
                 u_dut.u_cpu.u_regfile.regs[10], u_dut.u_cpu.u_regfile.regs[11], u_dut.u_cpu.u_regfile.regs[12]);
    end

        // catch a jump out of the DDR code region (a crash) for diagnostics
    logic [31:0] last_pc = 0; logic caught = 0;
    always @(posedge clk) if (rst_n) begin
        if (u_dut.imem_addr[31:28] == 4'h1) last_pc <= u_dut.imem_addr;
        else if (!caught) begin caught <= 1;
            $display("  CRASH: jumped from %08h to %08h", last_pc, u_dut.imem_addr); end
    end
    initial begin
        int cyc = 0;
        @(posedge rst_n);
        forever begin
            @(posedge clk); cyc++;
            if (led == 4'b0101) begin $display("=== PASS: led=0101 after %0d cycles (code+data from DDR) ===", cyc); $finish; end
            if (led == 4'b1010) begin $display("=== FAIL: led=1010 ==="); $finish; end
            if (cyc >= CYCLE_LIMIT) begin
                $display("=== TIMEOUT at %0d, led=%b PC=%08h dPC=%08h dwe=%b dre=%b dready=%b imready=%b",
                         cyc, led, u_dut.imem_addr, u_dut.d_addr, u_dut.d_we, u_dut.d_re, u_dut.d_ready, u_dut.imem_ready);
                $display("    icache.state=%0d dcache.state=%0d | I:arv=%b arr=%b rv=%b | D:arv=%b arr=%b rv=%b awv=%b wv=%b bv=%b",
                         u_dut.u_icache.state, u_dut.u_dcache.state, iarv, iarr, irv, darv, darr, drv, dawv, dwv, dbv);
                $display("    mem_stall=%b stall_pc=%b stall_ifid=%b stall_idex=%b mdiv_busy=%b exmem_valid=%b exmem_re=%b exmem_we=%b",
                         u_dut.u_cpu.mem_stall, u_dut.u_cpu.stall_pc, u_dut.u_cpu.stall_ifid, u_dut.u_cpu.stall_idex,
                         u_dut.u_cpu.mdiv_busy, u_dut.u_cpu.exmem_valid, u_dut.u_cpu.exmem_mem_re, u_dut.u_cpu.exmem_mem_we);
                $display("    imem_data(@PC)=%08h  a3(regs13)=%08h a4(regs14)=%08h a0(regs10)=%08h",
                         u_dut.imem_data, u_dut.u_cpu.u_regfile.regs[13], u_dut.u_cpu.u_regfile.regs[14], u_dut.u_cpu.u_regfile.regs[10]);
                $display("    icache line[3] tag=%05h valid=%b data=%064h", u_dut.u_icache.tag_arr[3], u_dut.u_icache.valid_arr[3], u_dut.u_icache.data_arr[3]);
                $finish;
            end
        end
    end
endmodule : tb_unified_core
