// demo_uart.c  -  RV32IM prints "Hello" out the single cable via the ARM relay
//
// The RV32IM can't drive the PS UART directly, so it pushes each character into
// the MMIO mailbox (pure PL, single-cycle — never stalls). A tiny ARM program
// (see scripts/arm_relay) reads the mailbox over AXI GPIO and writes the byte
// to the PS UART1, which comes out the single PROG/UART micro-USB.
//
// Flow control: a 1-bit req/ack toggle. We flip req and write {req,char}; the
// ARM, when it sees req != ack, consumes the byte and sets ack = req. We wait
// for that before sending the next char -> lossless, no FIFO needed.
//
// No string literals (.text-only program.hex), so characters are immediates.

#include <stdint.h>

#define LED       (*(volatile uint32_t *)0x90000000u)
#define MBOX_PUSH (*(volatile uint32_t *)0x90000020u)   // [7:0]=char, [8]=req
#define MBOX_ACK  (*(volatile uint32_t *)0x90000024u)   // [0]=ARM ack toggle

static uint32_t req;

static void delay(uint32_t n) { for (volatile uint32_t i = 0; i < n; i++) { } }

static void putc_mbox(int c)
{
    req ^= 1u;
    MBOX_PUSH = (req << 8) | (uint32_t)(uint8_t)c;     // hand the byte to the PS
    while ((MBOX_ACK & 1u) != req) { /* wait for the ARM relay to consume it */ }
}

static void greet(void)
{
    putc_mbox('H'); putc_mbox('e'); putc_mbox('l'); putc_mbox('l'); putc_mbox('o');
    putc_mbox(' '); putc_mbox('f'); putc_mbox('r'); putc_mbox('o'); putc_mbox('m');
    putc_mbox(' '); putc_mbox('R'); putc_mbox('V'); putc_mbox('3'); putc_mbox('2');
    putc_mbox('I'); putc_mbox('M'); putc_mbox('!'); putc_mbox('\r'); putc_mbox('\n');
}

int main(void)
{
    req = 0;

    // startup heartbeat: proves the CPU is alive before we depend on the relay.
    LED = 0x1u;
    for (int b = 0; b < 6; b++) { LED ^= 0xFu; delay(0x80000u); }

    uint32_t led = 0x1u;
    for (;;) {
        LED = led;
        greet();                 // stalls here only if the ARM relay isn't running
        led ^= 0xF;
        delay(0x40000u);
    }
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
