#include <stdio.h>
#include <stdint.h>
#define LED (*(volatile uint32_t *)0x90000000u)
int main(void){
    char buf[32];
    int len = sprintf(buf, "val=%d", 12345);   // newlib sprintf (the crasher)
    LED = (len==9 && buf[0]=='v') ? 0x5u : 0xAu;
    for(;;){}
}
