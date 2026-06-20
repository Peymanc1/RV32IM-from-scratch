// dmem.sv  -  data memory (BRAM)
//
// Synchronous write with byte strobes. Combinational read (single-cycle path).
//
// Funct3 layout for OP_LOAD / OP_STORE:
//   LOAD:  000 LB   001 LH   010 LW   100 LBU   101 LHU
//   STORE: 000 SB   001 SH   010 SW

import rv32im_pkg::*;

module dmem #(
    parameter int MEM_WORDS = 4096
) (
    input  logic              clk,
    input  logic [XLEN-1:0]   addr_i,
    input  logic              we_i,
    input  logic              re_i,         // unused for now — kept for future
    input  logic [2:0]        funct3_i,
    input  logic [XLEN-1:0]   write_data_i,
    output logic [XLEN-1:0]   read_data_o
);

    localparam int ADDR_W = $clog2(MEM_WORDS);
    logic [XLEN-1:0] mem [0:MEM_WORDS-1];

    wire [ADDR_W-1:0] word_addr = addr_i[ADDR_W+1:2];
    wire [1:0]        byte_off  = addr_i[1:0];

    // ---- write: byte strobed ----
    // funct3[1:0]: 00 byte, 01 half, 10 word
    logic [3:0]  byte_strobe;
    logic [31:0] write_aligned;

    always_comb begin
        byte_strobe   = 4'b0000;
        write_aligned = 32'd0;
        unique case (funct3_i[1:0])
            2'b00: begin // SB
                byte_strobe   = 4'b0001 << byte_off;
                write_aligned = {4{write_data_i[7:0]}};       // replicate to all lanes
            end
            2'b01: begin // SH
                byte_strobe   = byte_off[1] ? 4'b1100 : 4'b0011;
                write_aligned = {2{write_data_i[15:0]}};
            end
            2'b10: begin // SW
                byte_strobe   = 4'b1111;
                write_aligned = write_data_i;
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (we_i) begin
            if (byte_strobe[0]) mem[word_addr][ 7: 0] <= write_aligned[ 7: 0];
            if (byte_strobe[1]) mem[word_addr][15: 8] <= write_aligned[15: 8];
            if (byte_strobe[2]) mem[word_addr][23:16] <= write_aligned[23:16];
            if (byte_strobe[3]) mem[word_addr][31:24] <= write_aligned[31:24];
        end
    end

    // ---- read: combinational ----
    wire [31:0] raw_word = mem[word_addr];
    logic [7:0]  byte_sel;
    logic [15:0] half_sel;

    always_comb begin
        unique case (byte_off)
            2'b00  : byte_sel = raw_word[ 7: 0];
            2'b01  : byte_sel = raw_word[15: 8];
            2'b10  : byte_sel = raw_word[23:16];
            2'b11  : byte_sel = raw_word[31:24];
            default: byte_sel = 8'd0;
        endcase
        half_sel = byte_off[1] ? raw_word[31:16] : raw_word[15:0];
    end

    always_comb begin
        unique case (funct3_i)
            3'b000 : read_data_o = {{24{byte_sel[7]}},  byte_sel};    // LB
            3'b001 : read_data_o = {{16{half_sel[15]}}, half_sel};    // LH
            3'b010 : read_data_o = raw_word;                           // LW
            3'b100 : read_data_o = {24'd0, byte_sel};                  // LBU
            3'b101 : read_data_o = {16'd0, half_sel};                  // LHU
            default: read_data_o = raw_word;
        endcase
    end

endmodule : dmem
