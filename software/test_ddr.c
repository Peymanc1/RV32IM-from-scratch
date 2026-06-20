// test_ddr.c  -  exercise the cache+DDR data path from a real program
//
// Writes 16 words to the DDR region (0x10000000, spanning 2 cache lines ->
// forces miss/fill + dirty), reads them back (hits), sums them, and stores the
// result to a BRAM address the testbench can check directly. Then halts via
// tohost. No .data/.rodata (everything is immediates / registers), so the
// .text-only program.hex flow is enough.
//
// Expected sum = sum_{i=1..16} 7*i = 7*136 = 952 = 0x3B8.

#include <stdint.h>

#define DDR    ((volatile uint32_t *)0x10000000)   // cached DDR region
#define RESULT (*(volatile uint32_t *)0x80001100)  // BRAM, checked by the TB
#define TOHOST (*(volatile uint32_t *)0x80001000)  // write 1 -> halt

int main(void)
{
    for (int i = 0; i < 16; i++)
        DDR[i] = (uint32_t)((i + 1) * 7);     // stores: miss->fill->write (dirty)

    uint32_t sum = 0;
    for (int i = 0; i < 16; i++)
        sum += DDR[i];                        // loads: hits after the fills

    RESULT = sum;                             // BRAM store, directly checkable
    TOHOST = 1;                               // halt
    for (;;) { }
    return 0;
}

__attribute__((naked, section(".text.start"))) void _start(void)
{
    __asm__ volatile(
        "li   sp, 0x80002000\n"
        "call main\n"
        "1: j 1b\n"
    );
}
