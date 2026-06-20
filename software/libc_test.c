#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#define LED (*(volatile uint32_t *)0x90000000u)
int main(void){
    const int n=64;
    int *a=malloc(n*sizeof(int)); int *b=malloc(n*sizeof(int));
    if(!a||!b){LED=0xA;for(;;){}}
    for(int i=0;i<n;i++) a[i]=i+1;
    memset(b,0,n*sizeof(int)); memcpy(b,a,n*sizeof(int));
    long s=0; for(int i=0;i<n;i++) s+=b[i];
    char buf[32]; int len=sprintf(buf,"sum=%ld",s);
    free(a); free(b);
    LED = (s==2080 && len==8 && buf[4]=='2') ? 0x5u : 0xAu;
    for(;;){}
}
