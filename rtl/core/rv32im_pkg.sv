// rv32im_pkg.sv
//
// Shared types and constants. Everything imports this.
// Keep it small — if a type is only used in one module, define it there.

package rv32im_pkg;

    // architecture constants
    parameter int XLEN     = 32;
    parameter int INST_W   = 32;
    parameter int REG_ADDR = 5;        // 32 regs -> 5-bit index

    // Standard RISC-V DRAM base. Spike + the GNU toolchain default to this.
    // IMEM/DMEM only use the lower bits so the address effectively wraps -
    // IMEM[0] still holds the first instruction.
    parameter logic [31:0] RESET_VECTOR = 32'h8000_0000;

    // RV32I opcodes (inst[6:0]). See unprivileged spec table 19.1.
    typedef enum logic [6:0] {
        OP_LUI    = 7'b0110111,
        OP_AUIPC  = 7'b0010111,
        OP_JAL    = 7'b1101111,
        OP_JALR   = 7'b1100111,
        OP_BRANCH = 7'b1100011,
        OP_LOAD   = 7'b0000011,
        OP_STORE  = 7'b0100011,
        OP_ITYPE  = 7'b0010011,   // ADDI / SLTI / shifts / etc
        OP_RTYPE  = 7'b0110011,   // ADD / SUB / shifts / M-ext
        OP_FENCE  = 7'b0001111,   // treated as NOP for now
        OP_SYSTEM = 7'b1110011    // ECALL/EBREAK/CSR — placeholder
    } opcode_e;

    // Internal ALU op encoding. 4 bits is plenty (we use 11).
    typedef enum logic [3:0] {
        ALU_ADD   = 4'b0000,
        ALU_SUB   = 4'b0001,
        ALU_SLL   = 4'b0010,
        ALU_SLT   = 4'b0011,
        ALU_SLTU  = 4'b0100,
        ALU_XOR   = 4'b0101,
        ALU_SRL   = 4'b0110,
        ALU_SRA   = 4'b0111,
        ALU_OR    = 4'b1000,
        ALU_AND   = 4'b1001,
        ALU_PASSB = 4'b1010    // pass operand B straight through (LUI)
    } alu_op_e;

    typedef enum logic [2:0] {
        BR_BEQ  = 3'b000,
        BR_BNE  = 3'b001,
        BR_BLT  = 3'b100,
        BR_BGE  = 3'b101,
        BR_BLTU = 3'b110,
        BR_BGEU = 3'b111
    } branch_e;

    // immediate format selector — five flavours plus "none" for R-type
    typedef enum logic [2:0] {
        IMM_I = 3'b000,
        IMM_S = 3'b001,
        IMM_B = 3'b010,
        IMM_U = 3'b011,
        IMM_J = 3'b100,
        IMM_X = 3'b111
    } imm_type_e;

    typedef enum logic [1:0] {
        PC_PLUS4 = 2'b00,
        PC_BRANCH= 2'b01,    // BEQ/BNE family + JAL  (PC + imm)
        PC_JALR  = 2'b10     // JALR  (rs1 + imm)
    } pc_sel_e;

    // what gets written back to rd
    typedef enum logic [1:0] {
        WB_ALU = 2'b00,
        WB_MEM = 2'b01,      // load result
        WB_PC4 = 2'b10,      // link reg for JAL/JALR
        WB_IMM = 2'b11       // alt path for LUI (we actually use ALU_PASSB instead)
    } wb_sel_e;

    typedef enum logic [0:0] {
        ALU_A_RS1 = 1'b0,
        ALU_A_PC  = 1'b1     // AUIPC, JAL link
    } alu_a_sel_e;

    typedef enum logic [0:0] {
        ALU_B_RS2 = 1'b0,
        ALU_B_IMM = 1'b1     // I-type, loads, stores
    } alu_b_sel_e;

    // ----- pipeline-only stuff below -----

    // Forwarding mux selector for EX operands.
    //   00 = no bypass, take rs from ID/EX register
    //   01 = bypass from MEM/WB (writeback data path)
    //   10 = bypass from EX/MEM (last cycle's ALU result)
    typedef enum logic [1:0] {
        FWD_NONE   = 2'b00,
        FWD_FROM_W = 2'b01,
        FWD_FROM_M = 2'b10
    } fwd_sel_e;

endpackage : rv32im_pkg
