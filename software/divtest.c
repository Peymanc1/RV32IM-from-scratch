// divtest.c  -  exercise the hardware DIV instruction directly with known values
// Writes results to framebuffer[0..] so the sim can read them back.
//   51200/2816=18, 100/4=25, 200/11=18, 1000/10=100, 255/5=51, 1234/7=176

#include <stdint.h>
#define FB ((volatile uint8_t *)0xA0000000u)

static int dv(int a, int b){ int r; __asm__ volatile("div %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }

int main(void)
{
    FB[0] = (uint8_t)dv(51200, 2816);  // 18
    FB[1] = (uint8_t)dv(100, 4);       // 25
    FB[2] = (uint8_t)dv(200, 11);      // 18
    FB[3] = (uint8_t)dv(1000, 10);     // 100
    FB[4] = (uint8_t)dv(255, 5);       // 51
    FB[5] = (uint8_t)dv(1234, 7);      // 176
    for (;;) { }
    return 0;
}

__attribute__((naked, section(".text.start"))) void _start(void)
{
    __asm__ volatile("li sp,0x80002000\n call main\n 1: j 1b\n");
}
