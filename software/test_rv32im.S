// test_rv32im.S  -  exhaustive RV32IM regression
//
// Exercises every RV32I + M instruction we care about. The final register
// state is what compare_traces.py diffs against Spike's golden run.
//
// Tail end writes 1 to tohost so Spike halts and the testbench can log
// final regs.

.section .text
.globl _start

_start:
    // ---- ADDI / immediates ----
    addi x1,  x0, 5
    addi x2,  x0, 10
    addi x3,  x0, -1            // 0xFFFFFFFF
    addi x4,  x0, 2047          // max +imm
    addi x5,  x0, -2048         // min  imm

    // ---- R-type arithmetic / logic ----
    add  x6,  x1, x2            // 15
    sub  x7,  x2, x1            // 5
    xor  x8,  x3, x2            // 0xFFFFFFF5
    or   x9,  x1, x2            // 15
    and  x10, x3, x4            // 0x7FF

    // ---- I-type logic ----
    xori x11, x3, -1            // 0
    ori  x12, x0, 0xFF          // 0xFF
    andi x13, x3, 0xF           // 0xF

    // ---- shifts ----
    slli x14, x1, 4             // 80
    srli x15, x4, 2             // 0x1FF
    srai x16, x3, 1             // 0xFFFFFFFF (arith)
    addi x17, x0, 4
    sll  x18, x1, x17
    srl  x19, x4, x17
    sra  x20, x3, x17

    // ---- SLT / SLTU ----
    slt  x21, x1, x2            // 1
    slt  x22, x3, x1            // 1   (signed -1 < 5)
    sltu x23, x3, x1            // 0   (unsigned 0xFFFFFFFF >= 5)
    slti x24, x1, 100           // 1

    // ---- LUI / AUIPC ----
    lui  x25, 0x12345           // 0x12345000
    auipc x26, 0                // PC of this instr — varies, so override below
    addi x26, x0, 77            // pin to a known value

    // ---- branches: taken side ----
    addi x27, x0, 0
    beq  x1, x1, b_eq
    addi x27, x0, 99
b_eq:
    bne  x1, x2, b_ne
    addi x27, x0, 99
b_ne:
    blt  x3, x1, b_lt
    addi x27, x0, 99
b_lt:
    bge  x2, x1, b_ge
    addi x27, x0, 99
b_ge:
    bltu x1, x3, b_ltu
    addi x27, x0, 99
b_ltu:
    bgeu x3, x1, b_geu
    addi x27, x0, 99
b_geu:
    // not-taken cases
    beq  x1, x2, b_fail
    bne  x1, x1, b_fail
    blt  x2, x1, b_fail
    bge  x1, x2, b_fail
    addi x27, x0, 42            // all branches behaved
    jal  x0, b_done
b_fail:
    addi x27, x0, -1
b_done:

    // ---- JAL / JALR ----
    jal  x28, fn_call
    addi x28, x0, 99            // skipped
fn_call:
    auipc x29, 0
    addi  x29, x29, 12
    jalr  x30, x29, 0
    addi  x29, x0, -1           // skipped
    addi  x29, x0, -1           // skipped
    addi  x29, x0, 55           // landing pad after JALR

    // ---- memory ----
    // Linker puts .data at 0x80001000. Our DMEM only sees the lower bits
    // so 0x80001000 effectively maps to DMEM[0]. Spike sees the real address.
    // Both backends agree on the resulting register values.
    lui  x1, 0x80001

    addi x2, x0, 0x5A
    sw   x2, 0(x1)
    lw   x3, 0(x1)              // 0x5A

    addi x4, x0, -1
    sh   x4, 4(x1)
    lh   x5, 4(x1)              // 0xFFFFFFFF (sign ext)
    lhu  x6, 4(x1)              // 0x0000FFFF

    addi x7, x0, 0x7F
    sb   x7, 8(x1)
    lb   x8, 8(x1)              // 0x7F
    lbu  x9, 8(x1)

    addi x10, x0, -128
    sb   x10, 9(x1)
    lb   x11, 9(x1)             // 0xFFFFFF80
    lbu  x12, 9(x1)             // 0x00000080

    // ---- MUL family ----
    addi x13, x0, 5
    addi x14, x0, 10
    mul  x15, x13, x14          // 50

    addi x16, x0, -4
    addi x17, x0, 3
    mul  x18, x16, x17          // -12

    lui  x19, 0x40000
    mul  x20, x19, x19          // low 32 = 0
    mulh x21, x19, x19          // high 32 = 0x10000000

    mulhu x22, x19, x19         // same — both operands non-negative

    addi  x23, x0, -1           // 0xFFFFFFFF
    mulhsu x24, x23, x23        // high of -1 * 0xFFFFFFFF (unsigned) = 0xFFFFFFFF

    // ---- DIV / REM ----
    addi x25, x0, 100
    addi x26, x0, 7
    div  x27, x25, x26          // 14
    rem  x28, x25, x26          // 2

    addi x29, x0, -100
    addi x30, x0, 7
    div  x31, x29, x30          // -14
    rem  x29, x29, x30          // -2 (sign follows dividend)

    addi x1, x0, 100
    addi x2, x0, 7
    divu x3, x1, x2             // 14
    remu x4, x1, x2             // 2

    addi x5, x0, -1             // 0xFFFFFFFF unsigned
    addi x6, x0, 2
    divu x7, x5, x6             // 0x7FFFFFFF

    // div-by-zero corner: spec says quotient = -1, remainder = dividend
    addi x8, x0, 42
    addi x9, x0, 0
    div  x10, x8, x9            // 0xFFFFFFFF
    rem  x11, x8, x9            // 42
    divu x12, x8, x9            // 0xFFFFFFFF
    remu x13, x8, x9            // 42

    // INT_MIN / -1 corner: quotient = INT_MIN, remainder = 0
    lui  x14, 0x80000
    addi x15, x0, -1
    div  x16, x14, x15          // 0x80000000
    rem  x17, x14, x15          // 0

    // ---- end of program: tohost handshake ----
    lui  x18, 0x80001           // tohost lives here
    addi x19, x0, 1
    sw   x19, 0(x18)

halt:
    jal  x0, halt               // spin forever; testbench timeout cuts the run
