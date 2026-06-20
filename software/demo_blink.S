// demo_blink.S  -  smallest interesting program for the FPGA
//
// Writes a pattern to the LED MMIO register, spins a delay loop,
// flips the pattern, repeats forever.
//
// Map:
//   reset vector   0x80000000
//   stack          0x80002000  (top of DMEM; we don't actually use it)
//   LED reg        0x90000000  (low 4 bits drive led[3:0])
//   cycle counter  0x90000004  (read-only, free running)
//
// Build (one-shot):
//   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
//     -T linker.ld -o demo_blink.elf demo_blink.S
//   riscv64-unknown-elf-objcopy -O binary --only-section=.text \
//     demo_blink.elf demo_blink.bin
//   ../scripts/build_demo.sh  does this + the hex packing in one go.
//
// Timing: at 25 MHz CPU clock with DELAY=0x80000 the loop runs ~80 ms,
// so the LEDs toggle ~12 times per second.

    .section .text.start
    .globl _start

_start:
    li      sp, 0x80002000          // not strictly needed, just in case

    li      a0, 0x90000000          // LED MMIO base
    li      a1, 0x5                 // initial pattern: alternating

main_loop:
    sw      a1, 0(a0)               // write LEDs

    li      t0, 0x80000             // delay counter
delay:
    addi    t0, t0, -1
    bnez    t0, delay

    xori    a1, a1, 0xF             // flip pattern (0x5 <-> 0xA)
    j       main_loop

    // Spike halt symbol — never reached on hardware.
    .globl tohost
tohost: .word 0
