// malloc_simple.c  -  a tiny allocator that overrides newlib's complex malloc.
//
// newlib's full malloc was hanging on this CPU; we don't need it. DOOM's Z_Malloc
// zone manages its own memory from one big block, so a simple bump allocator
// (with size headers so realloc works, free = no-op) is plenty. Memory comes
// from the DDR heap via _sbrk (grows up toward the stack).

#include <stddef.h>
#include <stdint.h>

extern void *_sbrk(ptrdiff_t incr);

void *malloc(size_t n)
{
    n = (n + 7u) & ~(size_t)7u;                 // 8-byte align
    size_t *h = (size_t *)_sbrk((ptrdiff_t)(n + 8u));   // 8-byte header
    if (h == (void *)-1 || h == 0) return 0;
    h[0] = n;                                   // remember size (for realloc)
    return (void *)(h + 2);                     // payload, 8-byte aligned
}

void free(void *p) { (void)p; }                 // bump allocator: no reclamation

void *calloc(size_t a, size_t b)
{
    size_t n = a * b;
    unsigned char *p = (unsigned char *)malloc(n);
    if (p) for (size_t i = 0; i < n; i++) p[i] = 0;
    return p;
}

void *realloc(void *p, size_t n)
{
    if (!p) return malloc(n);
    size_t old = ((size_t *)p)[-2];
    unsigned char *q = (unsigned char *)malloc(n);
    if (q) {
        size_t c = old < n ? old : n;
        unsigned char *s = (unsigned char *)p;
        for (size_t i = 0; i < c; i++) q[i] = s[i];
    }
    return q;
}
