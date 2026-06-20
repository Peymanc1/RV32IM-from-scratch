// tb_rv32im_core_pipelined.sv
//
// Same shape as the single-cycle TB — different DUT, longer cycle budget
// since pipeline stalls + DIV slow things down for the same program.

`timescale 1ns/1ps

import rv32im_pkg::*;

module tb_rv32im_core_pipelined;

    localparam logic [31:0] TOHOST_ADDR = 32'h8000_1000;
    localparam int          CYCLE_LIMIT = 30000;

    logic clk;
    logic rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    logic [31:0] imem_addr, imem_data;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_we, dmem_re;
    logic [2:0]  dmem_funct3;

    rv32im_core_pipelined u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .imem_addr_o   (imem_addr),
        .imem_data_i   (imem_data),
        .imem_ready_i  (1'b1),
        .dmem_addr_o   (dmem_addr),
        .dmem_we_o     (dmem_we),
        .dmem_re_o     (dmem_re),
        .dmem_funct3_o (dmem_funct3),
        .dmem_wdata_o  (dmem_wdata),
        .dmem_rdata_i  (dmem_rdata),
        .dmem_ready_i  (1'b1)              // BRAM is single-cycle
    );

    imem #(.MEM_WORDS(4096), .INIT_FILE("program.hex")) u_imem (
        .addr_i (imem_addr),
        .inst_o (imem_data)
    );

    dmem #(.MEM_WORDS(4096)) u_dmem (
        .clk          (clk),
        .addr_i       (dmem_addr),
        .we_i         (dmem_we),
        .re_i         (dmem_re),
        .funct3_i     (dmem_funct3),
        .write_data_i (dmem_wdata),
        .read_data_o  (dmem_rdata)
    );

    logic halted;
    logic [31:0] tohost_value;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halted       <= 1'b0;
            tohost_value <= 32'd0;
        end else if (dmem_we && dmem_addr == TOHOST_ADDR && dmem_wdata == 32'd1) begin
            halted       <= 1'b1;
            tohost_value <= dmem_wdata;
            $display("[%0t] tohost write detected: 0x%08h (halt)", $time, dmem_wdata);
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        $display("=== pipelined sim start ===");
    end

    initial begin
        int cycle_count;
        cycle_count = 0;
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            cycle_count++;
            if (halted) begin
                $display("=== program halted via tohost after %0d cycles ===", cycle_count);
                dump_registers();
                $finish;
            end
            if (cycle_count >= CYCLE_LIMIT) begin
                $display("=== timeout at %0d cycles ===", cycle_count);
                dump_registers();
                $finish;
            end
        end
    end

    // regfile lives at the same hierarchy in the pipelined top, conveniently.
    task automatic dump_registers();
        $display("=================================================");
        $display("=== final register state (pipelined) ===");
        for (int i = 0; i < 32; i++) begin
            $display("REGDUMP x%0d 0x%08h", i, u_dut.u_regfile.regs[i]);
        end
        $display("=================================================");
    endtask

    initial begin
        $dumpfile("sim/waveform_pipe.vcd");
        $dumpvars(0, tb_rv32im_core_pipelined);
    end

endmodule : tb_rv32im_core_pipelined
