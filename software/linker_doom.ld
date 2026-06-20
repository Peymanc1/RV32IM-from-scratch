/* linker_doom.ld  -  DOOM memory map in DDR
 *
 *   0x10000000  .text/.rodata/.data/.bss   (~700 KB)
 *   ~0x100B0000 heap (malloc + DOOM zone), grows UP        [_end .. stack]
 *   0x14000000  stack top, grows DOWN  (so ~64 MB of heap room below it)
 *   0x18000000  DOOM1.WAD (loaded separately into DDR by XSCT) — see doom_syscalls.c
 *
 * Everything is in DDR (I-cache for code, D-cache for data). The PS DDR is 1 GB,
 * so we are not tight on space.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

__stack_top = 0x14000000;

MEMORY { DDR (rwx) : ORIGIN = 0x10000000, LENGTH = 0x04000000 }   /* 64 MB image+heap window */

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
    _end = .;                 /* heap base */
    PROVIDE(end = .);
}
