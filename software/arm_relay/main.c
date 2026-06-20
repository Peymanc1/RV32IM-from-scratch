// arm_relay/main.c  -  ARM UART relay (with staged diagnostics)
//
// Reads the AXI GPIO mailbox the RV32IM (PL) pushes into, and writes each byte
// to PS UART1 (the FT2232 on the single PROG/UART micro-USB). The staged
// prints below pinpoint exactly where things stop if there's no output:
//
//   (nothing)        -> ELF not running on the ARM, or wrong UART
//   "ARM START"      -> ELF runs + UART1 works
//   "GPIO OK"        -> the AXI GPIO is reachable over M_AXI_GP0
//   "....." (dots)   -> relay loop alive; only the mailbox handshake is left
//
// Strings are fine here (this is the ARM, with normal memory), unlike the RV32IM.

#include "xparameters.h"
#include "xgpio.h"
#include "xuartps.h"

static void uputs(u32 base, const char *s) { while (*s) XUartPs_SendByte(base, (u8)*s++); }

int main(void)
{
    XGpio gpio;
    XUartPs uart;
    XUartPs_Config *uc;
    u32 ack = 0, v, req, tick = 0, ub;

    // ---- UART1 FIRST, so we can talk no matter what ----
    uc = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    XUartPs_CfgInitialize(&uart, uc, uc->BaseAddress);
    XUartPs_SetBaudRate(&uart, 115200);
    ub = uc->BaseAddress;
    uputs(ub, "\r\nARM START\r\n");           // <-- if you see this, ELF+UART1 are alive

    // ---- AXI GPIO mailbox ----
    XGpio_Initialize(&gpio, XPAR_GPIO_0_DEVICE_ID);
    XGpio_SetDataDirection(&gpio, 1, 0xFFFFFFFF);   // ch1 input (from PL)
    XGpio_SetDataDirection(&gpio, 2, 0x0);          // ch2 output (ack to PL)
    XGpio_DiscreteWrite(&gpio, 2, 0);
    uputs(ub, "GPIO OK\r\n");                 // <-- if you see this, GPIO is reachable

    for (;;) {
        if (++tick >= 3000000u) { tick = 0; XUartPs_SendByte(ub, '.'); }  // loop heartbeat

        v   = XGpio_DiscreteRead(&gpio, 1);
        req = (v >> 8) & 1u;
        if (req != ack) {
            XUartPs_SendByte(ub, (u8)(v & 0xFFu));
            ack = req;
            XGpio_DiscreteWrite(&gpio, 2, ack);
        }
    }
    return 0;
}
