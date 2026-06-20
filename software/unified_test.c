#include <stdint.h>
#define LED (*(volatile uint32_t *)0x90000000u)
int main(void){
    volatile uint32_t *S = (volatile uint32_t *)0x1007ff00u;  // a "saved reg" slot
    S[0] = 0xABCD;                                            // write it (dirty line)
    // touch many DDR lines to force eviction of S[0]'s line (and write-back)
    volatile uint32_t *T = (volatile uint32_t *)0x10010000u;
    for (int i = 0; i < 600; i++) T[i * 8] = (uint32_t)i;     // 1 word per cache line
    uint32_t back = S[0];                                     // re-read after evictions
    LED = (back == 0xABCD) ? 0x5u : 0xAu;
    for (;;){}
    return 0;
}
__attribute__((naked, section(".text.start"))) void _start(void){
    __asm__ volatile("li sp,0x10080000\n call main\n 1: j 1b\n");
}
