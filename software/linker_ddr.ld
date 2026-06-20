/* linker_ddr.ld  -  program runs FROM DDR (M2b)
 *
 *   .text/.rodata @ 0x10000000  (DDR, fetched via the I-cache)
 *   .data/.bss    @ 0x80001000  (BRAM dmem, single-cycle)
 *   stack          = 0x80002000 (top of BRAM, set in _start)
 *
 * Only .text is loaded into DDR (objcopy -> program.hex -> axi_slave_ddr / the
 * PS DDR). Keep .data/.bss empty (no initialised globals): nothing loads BRAM.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    DDR (rx) : ORIGIN = 0x10000000, LENGTH = 0x00100000   /* 1 MB text window */
    RAM (rw) : ORIGIN = 0x80001000, LENGTH = 0x00001000
}

SECTIONS
{
    .text 0x10000000 :
    {
        *(.text.start)
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
    } > DDR

    .data 0x80001000 :
    {
        *(.data) *(.data.*)
        *(.sdata) *(.sdata.*)
    } > RAM

    .bss :
    {
        *(.bss) *(.bss.*)
        *(.sbss) *(.sbss.*)
    } > RAM
}
