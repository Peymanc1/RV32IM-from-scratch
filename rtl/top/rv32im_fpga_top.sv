// rv32im_fpga_top.sv  -  synthesizable wrapper (Zybo Z7 default)
//
// Glues the pipelined core to BRAM IMEM/DMEM, the MMIO bridge and the
// physical board pins. Only top-level changes for porting to a new board
// are: clock rate (CLK_DIV) and the XDC pin map.
//
//   board_clk(125 MHz) -> /CLK_DIV -> cpu_clk(25 MHz)
//   btn_rst (active-H) -> ~btn_rst -> rst_n -> 2-FF sync -> cpu_rst_n
//
//   ┌───────────────────────────────────────────────────┐
//   │ rv32im_core_pipelined                             │
//   │   imem_addr ──────────►  imem (BRAM)              │
//   │   imem_data ◄──────────                           │
//   │   dmem bus  ◄──────►   mmio_bridge ──────►  led[] │
//   │                                  └─────►  dmem    │
//   └───────────────────────────────────────────────────┘

import rv32im_pkg::*;

module rv32im_fpga_top #(
    parameter int CLK_DIV    = 5,           // 125 / 5 = 25 MHz, comfortable
    parameter int IMEM_WORDS = 1024,        // 4 KB
    parameter int DMEM_WORDS = 1024
) (
    input  logic       clk,                  // 125 MHz on Zybo Z7
    input  logic       btn_rst,              // BTN0, active-HIGH (board pull-down)
    input  logic [3:0] sw,                   // slide switches (game input)
    output logic [3:0] led,

    // AXI4-Lite master -> Zynq PS M_AXI_GP0 (PS peripheral region, e.g. UART1).
    // Connected in the Vivado block design. For the pure-PL LED build these
    // are simply left unconnected (nothing ever targets the 0xE region).
    output logic [31:0] m_axi_awaddr,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] m_axi_araddr,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,

    // The whole AXI domain runs on cpu_clk; expose clk + active-low reset so
    // the block design clocks the PS + interconnect from the same net.
    output logic        cpu_clk_o,
    output logic        cpu_rst_n_o,

    // UART mailbox to the PS (via AXI GPIO): RV32IM pushes {req,char}, the ARM
    // relay reads it and prints to the PS UART out the single cable.
    output logic [8:0]  mbox_o,
    input  logic        mbox_ack_i,

    // framebuffer / palette write (CPU draws to HDMI via video_fb)
    output logic        fb_we_o,
    output logic [15:0] fb_waddr_o,
    output logic [7:0]  fb_wdata_o,
    output logic        pal_we_o,
    output logic [7:0]  pal_waddr_o,
    output logic [23:0] pal_wdata_o
);

    // Buttons on this board are active-high. Internal logic uses active-low
    // rst_n so flip it once here and forget about it.
    wire rst_n = ~btn_rst;

    // ---- clock divider ----
    // Toggle-flop divider. Crude but synthesizes fine. For higher target
    // frequencies use an MMCM/PLL — this just keeps the demo simple.
    logic [$clog2(CLK_DIV):0] clk_cnt;
    logic                     cpu_clk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= '0;
            cpu_clk <= 1'b0;
        end else if (clk_cnt == (CLK_DIV/2 - 1)) begin
            clk_cnt <= '0;
            cpu_clk <= ~cpu_clk;
        end else begin
            clk_cnt <= clk_cnt + 1'b1;
        end
    end

    // ---- reset CDC: board_clk domain into cpu_clk domain ----
    // 2-FF synchronizer. We don't debounce the button; not worth it for
    // a manual reset.
    logic [1:0] rst_sync;
    logic       cpu_rst_n;

    always_ff @(posedge cpu_clk or negedge rst_n) begin
        if (!rst_n) rst_sync <= 2'b00;
        else        rst_sync <= {rst_sync[0], 1'b1};
    end
    assign cpu_rst_n = rst_sync[1];

    assign cpu_clk_o   = cpu_clk;     // for PS S_AXI_GP0_ACLK + interconnect ACLK
    assign cpu_rst_n_o = cpu_rst_n;   // for interconnect ARESETN

    // ---- nets ----
    logic [XLEN-1:0]   imem_addr;
    logic [INST_W-1:0] imem_inst;

    logic [XLEN-1:0]   core_dmem_addr;
    logic              core_dmem_we, core_dmem_re;
    logic [2:0]        core_dmem_funct3;
    logic [XLEN-1:0]   core_dmem_wdata, core_dmem_rdata;
    logic              core_dmem_ready;

    logic [XLEN-1:0]   dmem_addr;
    logic              dmem_we, dmem_re;
    logic [2:0]        dmem_funct3;
    logic [XLEN-1:0]   dmem_wdata, dmem_rdata;

    // bridge <-> axi_lite_master
    logic [XLEN-1:0]   axi_req_addr, axi_req_wdata, axi_req_rdata;
    logic              axi_req_we, axi_req_re, axi_req_ready;
    logic [2:0]        axi_req_funct3;

    // ---- CPU ----
    rv32im_core_pipelined u_cpu (
        .clk           (cpu_clk),
        .rst_n         (cpu_rst_n),
        .imem_addr_o   (imem_addr),
        .imem_data_i   (imem_inst),
        .imem_ready_i  (1'b1),             // BRAM imem: always ready
        .dmem_addr_o   (core_dmem_addr),
        .dmem_we_o     (core_dmem_we),
        .dmem_re_o     (core_dmem_re),
        .dmem_funct3_o (core_dmem_funct3),
        .dmem_wdata_o  (core_dmem_wdata),
        .dmem_rdata_i  (core_dmem_rdata),
        .dmem_ready_i  (core_dmem_ready)   // 1 for BRAM/MMIO, AXI ready for PS region
    );

    // ---- IMEM ----
    // $readmemh inside imem.sv -> Vivado bakes program.hex into the BRAM
    // initialization, which becomes part of the bitstream.
    imem #(.MEM_WORDS(IMEM_WORDS), .INIT_FILE("program.hex")) u_imem (
        .addr_i (imem_addr),
        .inst_o (imem_inst)
    );

    // ---- MMIO bridge ----
    mmio_bridge u_bridge (
        .clk           (cpu_clk),
        .rst_n         (cpu_rst_n),
        .core_addr_i   (core_dmem_addr),
        .core_we_i     (core_dmem_we),
        .core_re_i     (core_dmem_re),
        .core_funct3_i (core_dmem_funct3),
        .core_wdata_i  (core_dmem_wdata),
        .core_rdata_o  (core_dmem_rdata),
        .core_ready_o  (core_dmem_ready),
        .dmem_addr_o   (dmem_addr),
        .dmem_we_o     (dmem_we),
        .dmem_re_o     (dmem_re),
        .dmem_funct3_o (dmem_funct3),
        .dmem_wdata_o  (dmem_wdata),
        .dmem_rdata_i  (dmem_rdata),
        .axi_addr_o    (axi_req_addr),
        .axi_we_o      (axi_req_we),
        .axi_re_o      (axi_req_re),
        .axi_funct3_o  (axi_req_funct3),
        .axi_wdata_o   (axi_req_wdata),
        .axi_rdata_i   (axi_req_rdata),
        .axi_ready_i   (axi_req_ready),
        .mbox_o        (mbox_o),
        .mbox_ack_i    (mbox_ack_i),
        .sw_i          (sw),
        .fb_we_o       (fb_we_o),
        .fb_waddr_o    (fb_waddr_o),
        .fb_wdata_o    (fb_wdata_o),
        .pal_we_o      (pal_we_o),
        .pal_waddr_o   (pal_waddr_o),
        .pal_wdata_o   (pal_wdata_o),
        .led_o         (led)
    );

    // ---- AXI-Lite master (bridge request -> PS M_AXI_GP0) ----
    axi_lite_master u_axi (
        .clk           (cpu_clk),
        .rst_n         (cpu_rst_n),
        .req_re_i      (axi_req_re),
        .req_we_i      (axi_req_we),
        .req_addr_i    (axi_req_addr),
        .req_funct3_i  (axi_req_funct3),
        .req_wdata_i   (axi_req_wdata),
        .req_rdata_o   (axi_req_rdata),
        .req_ready_o   (axi_req_ready),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awprot  (m_axi_awprot),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arprot  (m_axi_arprot),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready)
    );

    // ---- DMEM ----
    dmem #(.MEM_WORDS(DMEM_WORDS)) u_dmem (
        .clk          (cpu_clk),
        .addr_i       (dmem_addr),
        .we_i         (dmem_we),
        .re_i         (dmem_re),
        .funct3_i     (dmem_funct3),
        .write_data_i (dmem_wdata),
        .read_data_o  (dmem_rdata)
    );

endmodule : rv32im_fpga_top
