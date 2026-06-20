/* linker.ld  -  bare-metal RV32IM
 *
 * Layout:
 *   .text @ 0x80000000  (IMEM, 4 KB)
 *   .data @ 0x80001000  (DMEM, 4 KB)
 *
 * 0x80000000 is the standard RISC-V DRAM base — Spike defaults here, and
 * RESET_VECTOR in the RTL is the same. IMEM only addresses the lower bits
 * so the upper part wraps; effectively IMEM[0] holds the first instruction.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 0x1000
    RAM (rw)  : ORIGIN = 0x80001000, LENGTH = 0x1000
}

SECTIONS
{
    .text 0x80000000 :
    {
        *(.text.start)
        *(.text)
        *(.text.*)
    } > ROM

    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > ROM

    .data 0x80001000 :
    {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    } > RAM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
    } > RAM

    /* tohost: Spike treats a write to this symbol as a halt request. */
    .tohost :
    {
        PROVIDE(tohost   = 0x80001000);
        PROVIDE(fromhost = 0x80001008);
    }
}
