// imem.sv  -  instruction memory (BRAM)
//
// ROM-ish memory; populated from program.hex at sim start (and at FPGA bitstream
// load via $readmemh, which Vivado reads during synthesis).
//
// Read is combinational — fine for single-cycle, sketchy for real BRAM. When we
// move to a true synchronous BRAM read, IF stage gets one cycle deeper.

import rv32im_pkg::*;

module imem #(
    parameter int    MEM_WORDS = 4096,             // 4096 * 4 B = 16 KB
    parameter string INIT_FILE = "program.hex"
) (
    input  logic [XLEN-1:0]   addr_i,
    output logic [INST_W-1:0] inst_o
);

    localparam int ADDR_W = $clog2(MEM_WORDS);

    logic [INST_W-1:0] mem [0:MEM_WORDS-1];

    initial begin
        // Vivado will warn but not fail if INIT_FILE isn't found — fine, the
        // user might be running a separate tool.
        $readmemh(INIT_FILE, mem);
    end

    // word-aligned: drop the lower 2 bits, mask to MEM_WORDS range
    wire [ADDR_W-1:0] word_addr = addr_i[ADDR_W+1:2];
    assign inst_o = mem[word_addr];

endmodule : imem
