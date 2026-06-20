// raycaster.c  -  Wolfenstein-style first-person 3D maze on the RV32IM
//
// Casts one ray per screen column through a grid map, draws a vertical wall
// slice (height ~ 1/distance), in colour (red X-walls, green Y-walls, blue
// ceiling, brown floor; brightness = closeness). Pure fixed-point (no FPU),
// draws to the framebuffer at 0xA0000000. PLAYABLE via the slide switches:
//   SW0 turn left   SW1 turn right   SW2 walk forward   SW3 walk back
// (hold a switch to keep turning/walking). Verified in sim (make sim-raycast).
//
// Distances use recip() (a 32-bit hardware divide), NOT a 64-bit divide: the
// 64-bit __divdi3 reads __clz_tab from .rodata, which isn't loaded into this
// Harvard SoC's DMEM, so it returned wrong results for off-axis rays and the
// rotated view collapsed to all-wall. The 32-bit recip fixed it.

#include <stdint.h>

#define W     320
#define H     200
#define MAPW  16
#define MAPH  16
#define ONE   65536

#define FB   ((volatile uint8_t  *)0xA0000000u)
#define PAL  ((volatile uint32_t *)0xB0000000u)
#define SW   (*(volatile uint32_t *)0x90000008u)
#define SPEED   4000        // walk step (~0.06 cell) in 16.16
#define ROT_COS 64736       // cos(~9 deg) in 16.16  (one turn step)
#define ROT_SIN 10252       // sin(~9 deg)

typedef int32_t fx;
// fmul: fixed-point multiply (NOT float) — uses the M-extension 32x32->64
// multiply (mul/mulh), no F extension needed.
static inline fx fmul(fx a, fx b) { return (fx)(((int64_t)a * b) >> 16); }
static fx fabsx(fx a)             { return a < 0 ? -a : a; }

// recip: |1.0 / x| in 16.16, using a 32-bit unsigned divide (hardware DIVU).
// Deliberately avoids the 64-bit divide (__divdi3), which pulls __clz_tab into
// .rodata — unreadable in this Harvard SoC, so 64-bit divide was unreliable.
static fx recip(fx x)
{
    uint32_t ax = (uint32_t)(x < 0 ? -x : x);
    if (ax <= 2) return 0x3fffffff;          // ~infinite (near-parallel ray)
    return (fx)((0x80000000u / ax) << 1);    // (2^31/|x|) << 1  ==  2^32/|x|
}

static int is_wall(int cx, int cy)
{
    if (cx <= 0 || cy <= 0 || cx >= MAPW - 1 || cy >= MAPH - 1) return 1;
    if (cx == 8  && cy >= 2 && cy <= 6)  return 1;   // wall straight ahead
    if (cy == 4  && cx >= 10 && cx <= 13) return 1;
    if (cx == 4  && cy >= 9 && cy <= 13) return 1;
    if (cy == 11 && cx >= 6 && cx <= 12) return 1;
    if (cx == 11 && cy == 8)             return 1;   // a pillar
    if (cx == 6  && cy == 8)             return 1;
    return 0;
}

static uint32_t clamp255(int v) { return (uint32_t)(v > 255 ? 255 : (v < 0 ? 0 : v)); }

__attribute__((noinline))
static void render(fx posX, fx posY, fx dirX, fx dirY, fx planeX, fx planeY)
{
    for (int x = 0; x < W; x++) {
        fx cameraX = (fx)(((2 * x) << 16) / W) - ONE;   // 32-bit (no 64-bit div)
        fx rayX = dirX + fmul(planeX, cameraX);
        fx rayY = dirY + fmul(planeY, cameraX);

        int mapX = posX >> 16, mapY = posY >> 16;
        fx deltaX = recip(rayX);
        fx deltaY = recip(rayY);

        int stepX, stepY;
        fx sideDistX, sideDistY;
        if (rayX < 0) { stepX = -1; sideDistX = fmul(posX - (mapX << 16), deltaX); }
        else          { stepX =  1; sideDistX = fmul(((mapX + 1) << 16) - posX, deltaX); }
        if (rayY < 0) { stepY = -1; sideDistY = fmul(posY - (mapY << 16), deltaY); }
        else          { stepY =  1; sideDistY = fmul(((mapY + 1) << 16) - posY, deltaY); }

        int side = 0;
        for (int guard = 0; guard < 64; guard++) {
            if (sideDistX < sideDistY) { sideDistX += deltaX; mapX += stepX; side = 0; }
            else                       { sideDistY += deltaY; mapY += stepY; side = 1; }
            if (is_wall(mapX, mapY)) break;
        }

        fx perp = (side == 0) ? (sideDistX - deltaX) : (sideDistY - deltaY);
        int dist4 = perp >> 14; if (dist4 < 1) dist4 = 1;
        int lineH = (H * 4) / dist4;
        int start = H / 2 - lineH / 2; if (start < 0)     start = 0;
        int end   = H / 2 + lineH / 2; if (end   > H - 1) end   = H - 1;

        int dist   = perp >> 16;
        int bright = 95 - dist * 6; if (bright < 20) bright = 20; if (bright > 95) bright = 95;
        uint8_t wall = side ? (uint8_t)(100 + bright) : (uint8_t)bright;

        for (int y = 0;       y < start; y++) FB[y * W + x] = 250;   // ceiling
        for (int y = start;   y <= end;  y++) FB[y * W + x] = wall;   // wall
        for (int y = end + 1; y < H;     y++) FB[y * W + x] = 251;   // floor
    }
}

int main(void)
{
    for (int i = 0; i < 256; i++) PAL[i] = 0;
    for (int i = 1; i < 100; i++)
        PAL[i] = (clamp255(i * 2) << 16) | (clamp255(i / 2) << 8);
    for (int i = 0; i < 100; i++)
        PAL[100 + i] = (clamp255(i / 3) << 16) | (clamp255(i * 2) << 8) | clamp255(i / 2);
    PAL[250] = (0x10u << 16) | (0x18u << 8) | 0x38u;   // ceiling
    PAL[251] = (0x30u << 16) | (0x28u << 8) | 0x10u;   // floor

    fx posX = 3 * ONE + ONE / 2, posY = 3 * ONE + ONE / 2;
    fx dirX = ONE, dirY = 0, planeX = 0, planeY = 43253;

    // game loop: SW0 turn left, SW1 turn right (hold to keep turning),
    // SW2 walk forward, SW3 walk back (hold to keep walking).
    for (;;) {
        uint32_t s = SW & 0xF;

        if (s & 3) {                                   // smooth rotation (fmul)
            fx cs = ROT_COS, sn = (s & 1) ? ROT_SIN : -ROT_SIN;
            fx ndx = fmul(dirX,   cs) - fmul(dirY,   sn);
            fx ndy = fmul(dirX,   sn) + fmul(dirY,   cs);
            fx npx = fmul(planeX, cs) - fmul(planeY, sn);
            fx npy = fmul(planeX, sn) + fmul(planeY, cs);
            dirX = ndx; dirY = ndy; planeX = npx; planeY = npy;
        }
        if (s & 12) {                                  // walk along facing
            fx mvX = fmul(dirX, SPEED), mvY = fmul(dirY, SPEED);
            if (s & 8) { mvX = -mvX; mvY = -mvY; }
            if (!is_wall((posX + mvX) >> 16, posY >> 16)) posX += mvX;
            if (!is_wall(posX >> 16, (posY + mvY) >> 16)) posY += mvY;
        }

        render(posX, posY, dirX, dirY, planeX, planeY);
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
