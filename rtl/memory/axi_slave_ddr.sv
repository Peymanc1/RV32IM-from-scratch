// axi_slave_ddr.sv  -  behavioural AXI4 burst slave standing in for PS DDR (sim)
//
// NOT synthesizable as-is. Models the Zynq PS DDR controller's S_AXI port for
// simulation: services INCR read/write bursts into a memory array, with a few
// cycles of read latency. 32-bit data. No IDs (matches axi_burst_master).
// Preload via $readmemh if you want initial DRAM contents.

module axi_slave_ddr #(
    parameter int    MEM_WORDS = 1 << 20,
    parameter int    LATENCY   = 12,
    parameter string INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] awaddr,
    input  logic [7:0]  awlen,
    input  logic [2:0]  awsize,
    input  logic [1:0]  awburst,
    input  logic        awvalid,
    output logic        awready,

    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wlast,
    input  logic        wvalid,
    output logic        wready,

    output logic [1:0]  bresp,
    output logic        bvalid,
    input  logic        bready,

    input  logic [31:0] araddr,
    input  logic [7:0]  arlen,
    input  logic [2:0]  arsize,
    input  logic [1:0]  arburst,
    input  logic        arvalid,
    output logic        arready,

    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rlast,
    output logic        rvalid,
    input  logic        rready
);
    localparam int ADDR_W = $clog2(MEM_WORDS);

    logic [31:0] mem [0:MEM_WORDS-1];
    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

    assign bresp = 2'b00;
    assign rresp = 2'b00;

    // ---- write channel ----
    typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } wstate_e;
    wstate_e             wstate;
    logic [ADDR_W-1:0]   waddr_word;
    logic [7:0]          wbeat;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wstate  <= W_IDLE;
            awready <= 1'b0;
            wready  <= 1'b0;
            bvalid  <= 1'b0;
            wbeat   <= 8'd0;
        end else begin
            unique case (wstate)
                W_IDLE: begin
                    bvalid <= 1'b0;
                    awready <= 1'b1;
                    if (awvalid && awready) begin
                        awready    <= 1'b0;
                        waddr_word <= awaddr[ADDR_W+1:2];
                        wbeat      <= 8'd0;
                        wready     <= 1'b1;
                        wstate     <= W_DATA;
                    end
                end
                W_DATA: begin
                    if (wvalid && wready) begin
                        if (wstrb[0]) mem[waddr_word + wbeat][ 7: 0] <= wdata[ 7: 0];
                        if (wstrb[1]) mem[waddr_word + wbeat][15: 8] <= wdata[15: 8];
                        if (wstrb[2]) mem[waddr_word + wbeat][23:16] <= wdata[23:16];
                        if (wstrb[3]) mem[waddr_word + wbeat][31:24] <= wdata[31:24];
                        wbeat <= wbeat + 8'd1;
                        if (wlast) begin
                            wready <= 1'b0;
                            bvalid <= 1'b1;
                            wstate <= W_RESP;
                        end
                    end
                end
                W_RESP: begin
                    if (bvalid && bready) begin
                        bvalid <= 1'b0;
                        wstate <= W_IDLE;
                    end
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // ---- read channel ----
    typedef enum logic [1:0] { R_IDLE, R_LAT, R_DATA } rstate_e;
    rstate_e             rstate;
    logic [ADDR_W-1:0]   raddr_word;
    logic [7:0]          rbeat, rcnt;
    int                  lat;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rstate  <= R_IDLE;
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rlast   <= 1'b0;
            rdata   <= 32'd0;
            rbeat   <= 8'd0;
            rcnt    <= 8'd0;
            lat     <= 0;
        end else begin
            unique case (rstate)
                R_IDLE: begin
                    rvalid  <= 1'b0;
                    rlast   <= 1'b0;
                    arready <= 1'b1;
                    if (arvalid && arready) begin
                        arready    <= 1'b0;
                        raddr_word <= araddr[ADDR_W+1:2];
                        rcnt       <= arlen + 8'd1;
                        rbeat      <= 8'd0;
                        lat        <= 0;
                        rstate     <= R_LAT;
                    end
                end
                R_LAT: begin
                    if (lat == LATENCY) begin
                        rdata  <= mem[raddr_word];
                        rvalid <= 1'b1;
                        rlast  <= (rcnt == 8'd1);
                        rstate <= R_DATA;
                    end else lat <= lat + 1;
                end
                R_DATA: begin
                    if (rvalid && rready) begin
                        if (rbeat == rcnt - 8'd1) begin
                            rvalid <= 1'b0;
                            rlast  <= 1'b0;
                            rstate <= R_IDLE;
                        end else begin
                            rbeat  <= rbeat + 8'd1;
                            rdata  <= mem[raddr_word + rbeat + 8'd1];
                            rlast  <= (rbeat + 8'd1 == rcnt - 8'd1);
                        end
                    end
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

endmodule : axi_slave_ddr
