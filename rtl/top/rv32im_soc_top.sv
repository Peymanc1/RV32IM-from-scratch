// rv32im_soc_top.sv  -  PS + PL top, single-cable UART via ARM relay
//
// The RV32IM (PL) can't reach the PS UART directly (it's on the ARM's MIO pins,
// and PL->S_AXI_GP can't touch PS peripheral registers). So output goes out the
// single PROG/UART cable like this:
//
//   RV32IM --MMIO write--> mmio_bridge mailbox --9-bit GPIO--> AXI GPIO (in BD)
//          <--1-bit GPIO-- (ARM ack)                              |
//                                                          PS M_AXI_GP0 reads it
//                                                                 |
//                                              ARM relay -> PS UART1 -> micro-USB
//
// Key point: the PL touches ONLY simple GPIO wires (no AXI on our side), so the
// CPU can never stall on the PS. All AXI lives inside the block design between
// the PS and the AXI GPIO. The PL is clocked by the board oscillator, so the
// CPU runs (LEDs blink) regardless of PS state.
//
// Wrapper port names come from build_vivado_ps.tcl. If your Vivado names them
// differently (e.g. a trailing _0), adjust the ps_sys_wrapper connections.

module rv32im_soc_top (
    input  logic       clk,         // 125 MHz board oscillator (K17)
    input  logic       btn_rst,
    output logic [3:0] led
);

    logic [8:0]  mbox;              // {req, char} from CPU -> PS
    logic        mbox_ack;          // ARM ack -> CPU
    // cpu_clk_o / cpu_rst_n_o are no longer needed: the BD's AXI domain is
    // clocked by the PS FCLK internally, not by the PL.

    // unused AXI-Lite master from the (abandoned) direct-PS-UART path; left
    // unconnected — the relay uses the GPIO mailbox, not this bus.
    logic [31:0] na_awaddr, na_wdata, na_araddr, na_rdata;
    logic [2:0]  na_awprot, na_arprot;
    logic [3:0]  na_wstrb;
    logic [1:0]  na_bresp, na_rresp;
    logic        na_awvalid, na_wvalid, na_bvalid, na_arvalid, na_rvalid;

    rv32im_fpga_top u_core (
        .clk            (clk),
        .btn_rst        (btn_rst),
        .led            (led),
        .cpu_clk_o      (),               // unused now (AXI domain on PS FCLK)
        .cpu_rst_n_o    (),
        .mbox_o         (mbox),
        .mbox_ack_i     (mbox_ack),
        // AXI-Lite master ports unused in the relay design
        .m_axi_awaddr   (na_awaddr),  .m_axi_awprot (na_awprot), .m_axi_awvalid(na_awvalid), .m_axi_awready(1'b0),
        .m_axi_wdata    (na_wdata),   .m_axi_wstrb  (na_wstrb),  .m_axi_wvalid (na_wvalid),  .m_axi_wready (1'b0),
        .m_axi_bresp    (2'b00),      .m_axi_bvalid (1'b0),      .m_axi_bready (na_bvalid),
        .m_axi_araddr   (na_araddr),  .m_axi_arprot (na_arprot), .m_axi_arvalid(na_arvalid), .m_axi_arready(1'b0),
        .m_axi_rdata    (32'd0),      .m_axi_rresp  (2'b00),     .m_axi_rvalid (1'b0),       .m_axi_rready (na_rvalid)
    );

    // ---- Zynq PS + AXI GPIO (block design) ----
    // No external clock/reset: the BD clocks its AXI domain from the PS FCLK.
    ps_sys_wrapper u_ps (
        .mbox_in_tri_i  (mbox),          // PS reads {req, char}
        .mbox_ack_tri_o (mbox_ack)       // PS drives ack toggle
    );

endmodule : rv32im_soc_top
