// demo_draw.c  -  the RV32IM draws an XOR texture to the HDMI framebuffer
//
// Writes the palette (grayscale) and then a 320x200 image where each pixel is
// (x XOR y) — the classic XOR fractal texture, an unmistakable "the CPU
// computed this" image. The framebuffer persists, so the video pipeline keeps
// showing it. Pure MMIO writes (single-cycle), no .rodata needed.
//
//   framebuffer: byte per pixel at 0xA0000000 + y*320 + x   (sb)
//   palette:     RGB word    at 0xB0000000 + index*4        (sw)

#include <stdint.h>

#define FB   ((volatile uint8_t  *)0xA0000000u)
#define PAL  ((volatile uint32_t *)0xB0000000u)

int main(void)
{
    // grayscale palette: index i -> RGB(i,i,i)
    for (int i = 0; i < 256; i++)
        PAL[i] = ((uint32_t)i << 16) | ((uint32_t)i << 8) | (uint32_t)i;

    // XOR texture
    for (int y = 0; y < 200; y++)
        for (int x = 0; x < 320; x++)
            FB[y * 320 + x] = (uint8_t)(x ^ y);

    for (;;) { }      // image stays on screen; video reads the framebuffer forever
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
