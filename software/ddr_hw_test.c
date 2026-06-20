// ddr_hw_test.c  -  prove the CPU reaches real PS DDR over AXI bursts (M1)
//
// Writes a known pattern into the cached DDR region (0x10000000), reads it
// back through the cache, sums it, and shows the verdict on the LEDs:
//   0b0101 = PASS (sum correct)      0b1010 = FAIL
// LEDs staying 0000 means the CPU hung (DDR/AXI never responded).
//
// Exercises the whole hardware path: pipeline + mem_stall + cache miss/fill/
// write-back + axi_burst_master + SmartConnect + PS S_AXI_HP + DDR controller.

#include <stdint.h>

#define DDR  ((volatile uint32_t *)0x10000000u)
#define LED  (*(volatile uint32_t *)0x90000000u)
#define N    64

int main(void)
{
    // write 1..N across several cache lines (forces fills + a write-back)
    for (int i = 0; i < N; i++)
        DDR[i] = (uint32_t)(i + 1);

    // read back and sum
    uint32_t sum = 0;
    for (int i = 0; i < N; i++)
        sum += DDR[i];

    uint32_t expected = (uint32_t)N * (N + 1) / 2;   // 64*65/2 = 2080

    LED = (sum == expected) ? 0x5u : 0xAu;

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
