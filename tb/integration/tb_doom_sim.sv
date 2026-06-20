// tb_doom_sim.sv  -  run the FULL DOOM on the real rv32im_doom_core in Verilator.
//
// This is "DOOM on our chip, no FPGA board": the exact synthesizable SoC core
// (CPU + I/D caches + AXI burst masters + MMIO/framebuffer) driven against two
// behavioural DDR slaves preloaded with doom.bin (@0x10000000) and doom1.wad
// (@0x18000000). The framebuffer writes (0xA) + palette (0xB) are captured and
// dumped as a PPM image. LED stage markers are printed so we see how far init
// gets (8=M_Init ... E=ST_Init, F=game loop).
//
// Build/run: see scripts/run_doom_sim.sh

`timescale 1ns/1ps
import rv32im_pkg::*;

module tb_doom_sim;
    localparam longint CYCLE_LIMIT = 1200000000;   // hard cap
    logic clk = 0, rst_n;
    always #5 clk = ~clk;                            // 100 MHz sim clock

    logic [3:0] sw = 4'd0;
    logic [3:0] led;

    // framebuffer / palette capture
    logic        fb_we;  logic [15:0] fb_waddr; logic [7:0]  fb_wdata;
    logic        pal_we; logic [7:0]  pal_waddr; logic [23:0] pal_wdata;

    // --- AXI master I ---
    logic [31:0] iaw,iwd,iar; logic [7:0] iawl,iarl; logic [2:0] iaws,iars;
    logic [1:0] iawb,iarb,ibr,irr; logic [3:0] iws;
    logic iawv,iawr,iwv,iwr,iwl,ibv,ibrd,iarv,iarr,irv,irl,irrd; logic [31:0] ird;
    // --- AXI master D ---
    logic [31:0] daw,dwd,dar; logic [7:0] dawl,darl; logic [2:0] daws,dars;
    logic [1:0] dawb,darb,dbr,drr; logic [3:0] dws;
    logic dawv,dawr,dwv,dwr,dwl,dbv,dbrd,darv,darr,drv,drl,drrd; logic [31:0] drd;

    rv32im_doom_core u_dut (
        .clk(clk), .rst_n(rst_n), .sw(sw), .led(led),
        .fb_we_o(fb_we), .fb_waddr_o(fb_waddr), .fb_wdata_o(fb_wdata),
        .pal_we_o(pal_we), .pal_waddr_o(pal_waddr), .pal_wdata_o(pal_wdata),
        .m_axi_i_awaddr(iaw),.m_axi_i_awlen(iawl),.m_axi_i_awsize(iaws),.m_axi_i_awburst(iawb),
        .m_axi_i_awvalid(iawv),.m_axi_i_awready(iawr),
        .m_axi_i_wdata(iwd),.m_axi_i_wstrb(iws),.m_axi_i_wlast(iwl),.m_axi_i_wvalid(iwv),.m_axi_i_wready(iwr),
        .m_axi_i_bresp(ibr),.m_axi_i_bvalid(ibv),.m_axi_i_bready(ibrd),
        .m_axi_i_araddr(iar),.m_axi_i_arlen(iarl),.m_axi_i_arsize(iars),.m_axi_i_arburst(iarb),
        .m_axi_i_arvalid(iarv),.m_axi_i_arready(iarr),
        .m_axi_i_rdata(ird),.m_axi_i_rresp(irr),.m_axi_i_rlast(irl),.m_axi_i_rvalid(irv),.m_axi_i_rready(irrd),
        .m_axi_d_awaddr(daw),.m_axi_d_awlen(dawl),.m_axi_d_awsize(daws),.m_axi_d_awburst(dawb),
        .m_axi_d_awvalid(dawv),.m_axi_d_awready(dawr),
        .m_axi_d_wdata(dwd),.m_axi_d_wstrb(dws),.m_axi_d_wlast(dwl),.m_axi_d_wvalid(dwv),.m_axi_d_wready(dwr),
        .m_axi_d_bresp(dbr),.m_axi_d_bvalid(dbv),.m_axi_d_bready(dbrd),
        .m_axi_d_araddr(dar),.m_axi_d_arlen(darl),.m_axi_d_arsize(dars),.m_axi_d_arburst(darb),
        .m_axi_d_arvalid(darv),.m_axi_d_arready(darr),
        .m_axi_d_rdata(drd),.m_axi_d_rresp(drr),.m_axi_d_rlast(drl),.m_axi_d_rvalid(drv),.m_axi_d_rready(drrd)
    );

    // I-slave: code only (program @0). 4 MB is plenty.
    axi_slave_ddr #(.MEM_WORDS(1<<20), .LATENCY(2), .INIT_FILE("sim/sim_doom_i.hex")) u_islave (
        .clk(clk), .rst_n(rst_n),
        .awaddr(iaw),.awlen(iawl),.awsize(iaws),.awburst(iawb),.awvalid(iawv),.awready(iawr),
        .wdata(iwd),.wstrb(iws),.wlast(iwl),.wvalid(iwv),.wready(iwr),
        .bresp(ibr),.bvalid(ibv),.bready(ibrd),
        .araddr(iar),.arlen(iarl),.arsize(iars),.arburst(iarb),.arvalid(iarv),.arready(iarr),
        .rdata(ird),.rresp(irr),.rlast(irl),.rvalid(irv),.rready(irrd)
    );
    // D-slave: program @0 + WAD @word 0x2000000 (=0x18000000 masked). 256 MB array
    // so WAD (word 32M) and stack (word 16M) do NOT alias the program (word 0).
    axi_slave_ddr #(.MEM_WORDS(1<<26), .LATENCY(2), .INIT_FILE("sim/sim_doom_d.hex")) u_dslave (
        .clk(clk), .rst_n(rst_n),
        .awaddr(daw),.awlen(dawl),.awsize(daws),.awburst(dawb),.awvalid(dawv),.awready(dawr),
        .wdata(dwd),.wstrb(dws),.wlast(dwl),.wvalid(dwv),.wready(dwr),
        .bresp(dbr),.bvalid(dbv),.bready(dbrd),
        .araddr(dar),.arlen(darl),.arsize(dars),.arburst(darb),.arvalid(darv),.arready(darr),
        .rdata(drd),.rresp(drr),.rlast(drl),.rvalid(drv),.rready(drrd)
    );

    // ---- capture framebuffer + palette ----
    logic [7:0]  fbmem [0:64000-1];
    logic [23:0] palette [0:255];
    longint fb_writes = 0;
    always @(posedge clk) if (rst_n) begin
        if (fb_we  && fb_waddr < 16'd64000) begin fbmem[fb_waddr] <= fb_wdata; fb_writes <= fb_writes + 1; end
        if (pal_we) palette[pal_waddr] <= pal_wdata;
    end

    // ===== GOLDEN-MEMORY CHECKER =====
    // Mirror every committed D-cache store; on each LW compare the cache's
    // returned value to the golden value. First mismatch = the exact corruption
    // (address, the load PC, and the PC that last wrote that word). Lazy/trust-
    // first-read for never-written locations (program/WAD), so it flags only
    // store->read-back corruption — exactly our bug.
    logic [7:0]  gmem [longint];
    logic [31:0] gwpc [longint];     // PC that last wrote this word's base
    longint      gchk_errs = 0;
    function automatic bit known4(input longint a);
        return gmem.exists(a) && gmem.exists(a+1) && gmem.exists(a+2) && gmem.exists(a+3);
    endfunction
    always @(posedge clk) if (rst_n) begin
        if (u_dut.is_ddr && u_dut.dc_ready && u_dut.d_we) begin
            longint a; a = u_dut.d_addr;
            unique case (u_dut.d_funct3[1:0])
                2'b00: gmem[a] = u_dut.d_wdata[7:0];
                2'b01: begin gmem[a]=u_dut.d_wdata[7:0]; gmem[a+1]=u_dut.d_wdata[15:8]; end
                2'b10: begin gmem[a]=u_dut.d_wdata[7:0]; gmem[a+1]=u_dut.d_wdata[15:8];
                             gmem[a+2]=u_dut.d_wdata[23:16]; gmem[a+3]=u_dut.d_wdata[31:24];
                             gwpc[a]=u_dut.imem_addr; end
                default:;
            endcase
        end
        else if (u_dut.is_ddr && u_dut.dc_ready && u_dut.d_re) begin
            longint a; logic [31:0] exp; bit kn; int w;
            a = u_dut.d_addr;
            unique case (u_dut.d_funct3)
                3'b000: begin w=1; kn=gmem.exists(a); exp={{24{gmem[a][7]}},gmem[a]}; end          // LB
                3'b100: begin w=1; kn=gmem.exists(a); exp={24'd0,gmem[a]}; end                       // LBU
                3'b001: begin w=2; a=u_dut.d_addr&~32'd1; kn=gmem.exists(a)&&gmem.exists(a+1); exp={{16{gmem[a+1][7]}},gmem[a+1],gmem[a]}; end // LH
                3'b101: begin w=2; a=u_dut.d_addr&~32'd1; kn=gmem.exists(a)&&gmem.exists(a+1); exp={16'd0,gmem[a+1],gmem[a]}; end             // LHU
                3'b010: begin w=4; a=u_dut.d_addr&~32'd3; kn=known4(a); exp={gmem[a+3],gmem[a+2],gmem[a+1],gmem[a]}; end                      // LW
                default: begin w=0; kn=0; exp=0; end
            endcase
            if (w != 0) begin
                if (kn) begin
                    if (exp !== u_dut.dc_rdata && gchk_errs < 12) begin
                        gchk_errs <= gchk_errs + 1;
                        $display("!!! MEM CORRUPTION @cyc %0d: f3=%b addr=%08h got=%08h golden=%08h loadPC=%08h lastStorePC=%08h",
                                 cyc, u_dut.d_funct3, u_dut.d_addr, u_dut.dc_rdata, exp, u_dut.imem_addr, gwpc.exists(a)?gwpc[a]:32'hX);
                    end
                end else begin   // first touch: trust the value (program/WAD initial data)
                    if (w>=1) gmem[a]   = u_dut.dc_rdata[7:0];
                    if (w>=2) gmem[a+1] = u_dut.dc_rdata[15:8];
                    if (w>=4) begin gmem[a+2]=u_dut.dc_rdata[23:16]; gmem[a+3]=u_dut.dc_rdata[31:24]; end
                end
            end
        end
    end

    // Read the I_Error format string that i_system.c copies to DDR @0x13000000.
    // 0x13000000 -> D-slave word index (0x13000000>>2)&(2^26-1) = 0x0C00000.
    task dump_ierror;
        integer i, j; logic [31:0] w; logic [7:0] ch; string s;
        s = "";
        for (i = 0; i < 96; i++) begin
            w = u_dslave.mem[26'h0C00000 + i];
            for (j = 0; j < 4; j++) begin
                ch = w[8*j +: 8];
                if (ch == 8'd0) begin $display("  I_ERROR string @0x13000000: \"%s\"", s); return; end
                s = {s, string'(ch)};
            end
        end
        $display("  I_ERROR string (no null in 384B): \"%s\"", s);
    endtask

    // Failing lump name that W_GetNumForName wrote to 0x13002000 -> word 0x0C00800.
    task dump_lumpname;
        integer j; logic [31:0] w0, w1; logic [7:0] ch; string s;
        w0 = u_dslave.mem[26'h0C00800]; w1 = u_dslave.mem[26'h0C00801]; s = "";
        for (j=0;j<4;j++) begin ch=w0[8*j+:8]; if(ch)s={s,string'(ch)}; end
        for (j=0;j<4;j++) begin ch=w1[8*j+:8]; if(ch)s={s,string'(ch)}; end
        $display("  FAILING LUMP NAME (@0x13002000): \"%s\"", s);
    endtask

    task dump_ppm(input string fname);
        integer fd, i; logic [23:0] rgb;
        fd = $fopen(fname, "wb");
        $fwrite(fd, "P6\n320 200\n255\n");
        for (i = 0; i < 64000; i++) begin
            rgb = palette[fbmem[i]];
            $fwrite(fd, "%c%c%c", rgb[23:16], rgb[15:8], rgb[7:0]);
        end
        $fclose(fd);
        $display("  >> wrote %s", fname);
    endtask

    // ---- LED stage tracking + run control ----
    logic [3:0] led_prev = 4'hX;
    longint     cyc = 0;
    longint     f_cyc = 0;          // cycle LED first hit 0xF
    bit         seen_f = 0;
    longint     fbw_last = 0;
    longint     stuck = 0;
    longint     fbw_at_f = 0;
    initial begin
        rst_n = 0; repeat (8) @(posedge clk); rst_n = 1;
        $display("=== DOOM-on-RV32IM (Verilator, no board) start ===");
    end

    always @(posedge clk) if (rst_n) begin
        cyc <= cyc + 1;
        if (led !== led_prev) begin
            $display("[cyc %0d] LED = %h  (fb_writes=%0d)", cyc, led, fb_writes);
            led_prev <= led;
            if (led == 4'hF && !seen_f) begin seen_f <= 1; f_cyc <= cyc; fbw_at_f <= fb_writes; end
        end
        // after the game loop starts, wait for one FULL frame to be drawn
        // (DG_DrawFrame copies 64000 px) then snapshot the real DOOM screen.
        if (seen_f && (fb_writes - fbw_at_f) >= 128000) begin
            $display("=== game loop: full frame drawn @cyc %0d (fb_writes=%0d) ===", cyc, fb_writes);
            dump_ppm("sim/doom_frame.ppm");
            $finish;
        end
        // stuck detection: LED + fb_writes unchanged for 3M cycles -> dump why
        if (fb_writes != fbw_last) begin fbw_last <= fb_writes; stuck <= 0; end
        else if (led == led_prev)   stuck <= stuck + 1;
        if (stuck > 40000000) begin
            $display("=== STUCK: LED=%h fb_writes=%0d PC(imem_addr)=%08h dPC(d_addr)=%08h @cyc %0d ===",
                     led, fb_writes, u_dut.imem_addr, u_dut.d_addr, cyc);
            dump_ierror;
            dump_lumpname;
            dump_ppm("sim/doom_frame.ppm");
            $finish;
        end
        if (cyc >= CYCLE_LIMIT) begin
            $display("=== CYCLE_LIMIT, last LED=%h fb_writes=%0d ===", led, fb_writes);
            dump_ppm("sim/doom_frame.ppm");
            $finish;
        end
    end

    // periodic heartbeat so we see it's alive
    initial forever begin
        #50000000;  // every 5 ms sim = 500k cycles
        $display("  ...alive: cyc=%0d LED=%h fb_writes=%0d", cyc, led, fb_writes);
    end
endmodule : tb_doom_sim
