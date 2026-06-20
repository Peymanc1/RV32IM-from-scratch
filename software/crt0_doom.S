# crt0_doom.S  -  C runtime startup for DOOM (stack high in DDR via __stack_top)
    .section .text.start, "ax"
    .global _start
_start:
    la    sp, __stack_top
.option push
.option norelax
    la    gp, __global_pointer$
.option pop
    la    a0, __bss_start
    la    a1, __bss_end
1:  bgeu  a0, a1, 2f
    sw    zero, 0(a0)
    addi  a0, a0, 4
    j     1b
2:  call  main
3:  j     3b
