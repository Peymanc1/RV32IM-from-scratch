#include <stdint.h>
#define LED (*(volatile uint32_t *)0x90000000u)
__attribute__((noinline)) static int sumto(int n){ int a=0; for(int i=1;i<=n;i++) a+=i; return a; }
int main(void){
    volatile int m = 100;
    int s = sumto(m);                          // 5050
    int t = 0; for (int i = 0; i < 10; i++) t += sumto(i);  // 165, nested loops
    LED = (s == 5050 && t == 165) ? 0x5u : 0xAu;
    for(;;){}
    return 0;
}
__attribute__((naked, section(".text.start"))) void _start(void){
    __asm__ volatile("li sp,0x80002000\n call main\n 1: j 1b\n");
}
