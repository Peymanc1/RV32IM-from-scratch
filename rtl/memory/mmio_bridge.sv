// mmio_bridge.sv  -  data-bus splitter by top nibble.
//   0x8xxxxxxx -> BRAM dmem (single cycle)
//   0x9xxxxxxx -> MMIO regs here
//   0xExxxxxxx -> AXI-Lite master (Zynq PS UART1 @ 0xE0001000)
// MMIO map:
//   0x90000000 LED (low 4 bits)        0x90000004 cycle counter (RO)
//   0x90000008 switches (low 4 bits)   0x90000020 UART mailbox
//   0x90000024 mailbox ack             0xA / 0xB framebuffer / palette write
// BRAM/MMIO finish in one cycle. AXI region forwards the master's ready.

import rv32im_pkg::*;

module mmio_bridge (
    input  logic              clk,
    input  logic              rst_n,

    // from CPU
    input  logic [XLEN-1:0]   core_addr_i,
    input  logic              core_we_i,
    input  logic              core_re_i,
    input  logic [2:0]        core_funct3_i,
    input  logic [XLEN-1:0]   core_wdata_i,
    output logic [XLEN-1:0]   core_rdata_o,
    output logic              core_ready_o,    // -> core dmem_ready_i

    // to internal DMEM
    output logic [XLEN-1:0]   dmem_addr_o,
    output logic              dmem_we_o,
    output logic              dmem_re_o,
    output logic [2:0]        dmem_funct3_o,
    output logic [XLEN-1:0]   dmem_wdata_o,
    input  logic [XLEN-1:0]   dmem_rdata_i,

    // to AXI-Lite master (PS peripheral region)
    output logic [XLEN-1:0]   axi_addr_o,
    output logic              axi_we_o,
    output logic              axi_re_o,
    output logic [2:0]        axi_funct3_o,
    output logic [XLEN-1:0]   axi_wdata_o,
    input  logic [XLEN-1:0]   axi_rdata_i,
    input  logic              axi_ready_i,

    // UART mailbox to/from the PS via AXI GPIO
    output logic [8:0]        mbox_o,        // {req, char[7:0]} -> PS reads
    input  logic              mbox_ack_i,    // PS ack toggle    -> CPU reads

    // board slide switches (read at 0x90000008) — game input
    input  logic [3:0]        sw_i,

    // framebuffer write (CPU draws a pixel: sb to 0xA0000000 + y*320 + x)
    output logic              fb_we_o,
    output logic [15:0]       fb_waddr_o,
    output logic [7:0]        fb_wdata_o,
    // palette write (CPU: sw RGB to 0xB0000000 + index*4)
    output logic              pal_we_o,
    output logic [7:0]        pal_waddr_o,
    output logic [23:0]       pal_wdata_o,

    // to FPGA pins
    output logic [3:0]        led_o
);

    wire is_mmio = (core_addr_i[31:28] == 4'h9);
    wire is_axi  = (core_addr_i[31:28] == 4'hE);   // Zynq PS peripheral space
    wire is_fb   = (core_addr_i[31:28] == 4'hA);   // framebuffer (320x200 bytes)
    wire is_pal  = (core_addr_i[31:28] == 4'hB);   // palette (256 x RGB)
    wire is_dmem = ~is_mmio & ~is_axi & ~is_fb & ~is_pal;

    // forward to BRAM only when the address says so
    assign dmem_addr_o   = core_addr_i;
    assign dmem_we_o     = core_we_i & is_dmem;
    assign dmem_re_o     = core_re_i & is_dmem;
    assign dmem_funct3_o = core_funct3_i;
    assign dmem_wdata_o  = core_wdata_i;

    // forward to AXI master only for the PS region
    assign axi_addr_o   = core_addr_i;
    assign axi_we_o     = core_we_i & is_axi;
    assign axi_re_o     = core_re_i & is_axi;
    assign axi_funct3_o = core_funct3_i;
    assign axi_wdata_o  = core_wdata_i;

    // framebuffer / palette write ports (write-only; single-cycle BRAM writes)
    assign fb_we_o     = core_we_i & is_fb;
    assign fb_waddr_o  = core_addr_i[15:0];
    assign fb_wdata_o  = core_wdata_i[7:0];
    assign pal_we_o    = core_we_i & is_pal;
    assign pal_waddr_o = core_addr_i[9:2];          // word index 0..255
    assign pal_wdata_o = core_wdata_i[23:0];

    // ---- MMIO registers ----
    logic [3:0]  led_reg;
    logic [31:0] cycle_cnt;
    logic [8:0]  mbox_reg;    // {req, char} driven to the PS via AXI GPIO

    wire mmio_we_led  = is_mmio & core_we_i & (core_addr_i[7:0] == 8'h00);
    wire mmio_we_mbox = is_mmio & core_we_i & (core_addr_i[7:0] == 8'h20);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_reg   <= 4'b0000;
            cycle_cnt <= 32'd0;
            mbox_reg  <= 9'd0;
        end else begin
            cycle_cnt <= cycle_cnt + 32'd1;     // always tick
            if (mmio_we_led)  led_reg  <= core_wdata_i[3:0];
            if (mmio_we_mbox) mbox_reg <= core_wdata_i[8:0];
        end
    end

    assign led_o  = led_reg;
    assign mbox_o = mbox_reg;

    // MMIO read mux
    logic [31:0] mmio_rdata;
    always_comb begin
        unique case (core_addr_i[7:0])
            8'h00  : mmio_rdata = {28'd0, led_reg};
            8'h04  : mmio_rdata = cycle_cnt;
            8'h08  : mmio_rdata = {28'd0, sw_i};        // slide switches (game input)
            8'h20  : mmio_rdata = {23'd0, mbox_reg};
            8'h24  : mmio_rdata = {31'd0, mbox_ack_i};
            default: mmio_rdata = 32'h0;
        endcase
    end

    assign core_rdata_o = is_axi  ? axi_rdata_i :
                          is_mmio ? mmio_rdata  :
                                    dmem_rdata_i;

    // BRAM/MMIO are single-cycle (ready=1). The AXI region stalls the core
    // until the master signals completion.
    assign core_ready_o = is_axi ? axi_ready_i : 1'b1;

endmodule : mmio_bridge
