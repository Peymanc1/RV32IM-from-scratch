# crt0.S  -  minimal C runtime startup for the RV32IM (runs from DDR)
#
# Sets the stack, gp (for newlib's small-data relaxation), zeroes .bss (C globals
# assume 0), then calls main. We DON'T use newlib's crt0 (-nostartfiles) so this
# is the entry. Heap is set up lazily by _sbrk in syscalls.c.

    .section .text.start, "ax"
    .global _start
_start:
    li    sp, 0x10080000            # 512 KB stack top in DDR (heap grows up to it)

.option push
.option norelax
    la    gp, __global_pointer$     # gp for newlib gp-relative data
.option pop

    # zero .bss
    la    a0, __bss_start
    la    a1, __bss_end
1:
    bgeu  a0, a1, 2f
    sw    zero, 0(a0)
    addi  a0, a0, 4
    j     1b
2:
    call  main
3:
    j     3b
