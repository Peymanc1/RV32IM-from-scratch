/* linker_unified.ld  -  EVERYTHING in DDR (M3)
 *
 *   .text/.rodata/.data/.bss @ 0x10000000  (DDR, I-cache for code, D-cache for data)
 *   stack                     = 0x10080000 (DDR, 512 KB in; set in _start)
 *
 * Only .text(+.rodata) is loaded as the image; the program writes its data
 * (stack, DDR scratch) at runtime through the D-cache, so keep .data/.bss empty.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    DDR (rwx) : ORIGIN = 0x10000000, LENGTH = 0x00400000   /* 4 MB window */
}

SECTIONS
{
    . = 0x10000000;
    .text : { *(.text.start) *(.text) *(.text.*) } > DDR
    .rodata : { *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) } > DDR
    .data : {
        __global_pointer$ = . + 0x800;
        *(.data) *(.data.*) *(.sdata) *(.sdata.*)
    } > DDR
    .bss : {
        __bss_start = .;
        *(.bss) *(.bss.*) *(.sbss) *(.sbss.*) *(COMMON)
        __bss_end = .;
    } > DDR

    . = ALIGN(16);
    _end = .;                 /* malloc heap starts here, grows up to the stack */
    PROVIDE(end = .);
}
