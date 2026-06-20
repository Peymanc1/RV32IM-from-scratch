// printf_simple.c  -  compact printf/sprintf/snprintf that override newlib's.
//
// newlib's vfprintf machinery (__ssprint_r) crashed on this CPU; we don't need
// its full feature set. This supports the conversions DOOM uses: %d %i %u %x %X
// %c %s %p %%, optional field width, '0' padding, '.precision' (min digits for
// integers / max chars for %s), and the 'l' length flag (harmless on ilp32
// where int == long == 32-bit). Output goes through _write.

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

extern int _write(int fd, const char *buf, int len);

static void emit(char c, char *buf, size_t *pos, size_t max)
{
    if (buf && *pos < max) buf[*pos] = c;
    (*pos)++;
}

static void emit_num(unsigned long v, int base, int is_signed, int upper,
                     int width, char pad, int prec, char *buf, size_t *pos, size_t max)
{
    char tmp[24]; int n = 0, neg = 0;
    const char *digs = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    if (is_signed && (long)v < 0) { neg = 1; v = (unsigned long)(-(long)v); }
    if (v == 0) tmp[n++] = '0';
    while (v) { tmp[n++] = digs[v % base]; v /= base; }
    while (n < prec && n < (int)sizeof(tmp)) tmp[n++] = '0';   // precision = min digits (zero-padded)
    int len = n + neg;
    if (neg && pad == '0') emit('-', buf, pos, max);   // sign before zero-pad
    for (int i = len; i < width; i++) emit(pad, buf, pos, max);
    if (neg && pad == ' ') emit('-', buf, pos, max);   // sign after space-pad
    while (n) emit(tmp[--n], buf, pos, max);
}

static int core(char *buf, size_t max, const char *fmt, va_list ap)
{
    size_t pos = 0;
    for (; *fmt; fmt++) {
        if (*fmt != '%') { emit(*fmt, buf, &pos, max); continue; }
        fmt++;
        char pad = ' '; int width = 0, prec = -1;
        while (*fmt == '-' || *fmt == '+' || *fmt == ' ' || *fmt == '#') fmt++;  // flags (ignored)
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') { width = width * 10 + (*fmt - '0'); fmt++; }
        if (*fmt == '.') { fmt++; prec = 0; while (*fmt >= '0' && *fmt <= '9') { prec = prec * 10 + (*fmt - '0'); fmt++; } }
        while (*fmt == 'l' || *fmt == 'h' || *fmt == 'z') fmt++;   // length flags (ignored)
        int p = prec < 0 ? 0 : prec;   // integer min-digits (0 if no precision given)
        switch (*fmt) {
            case 'd': case 'i': emit_num((unsigned long)(long)va_arg(ap, long), 10, 1, 0, width, pad, p, buf, &pos, max); break;
            case 'u':           emit_num(va_arg(ap, unsigned long), 10, 0, 0, width, pad, p, buf, &pos, max); break;
            case 'x':           emit_num(va_arg(ap, unsigned long), 16, 0, 0, width, pad, p, buf, &pos, max); break;
            case 'X':           emit_num(va_arg(ap, unsigned long), 16, 0, 1, width, pad, p, buf, &pos, max); break;
            case 'p':           emit('0', buf, &pos, max); emit('x', buf, &pos, max);
                                emit_num(va_arg(ap, unsigned long), 16, 0, 0, width, pad, p, buf, &pos, max); break;
            case 'c':           emit((char)va_arg(ap, int), buf, &pos, max); break;
            case 's': { const char *s = va_arg(ap, const char *); int c = 0; if (!s) s = "(null)";
                        while (*s && (prec < 0 || c < prec)) { emit(*s++, buf, &pos, max); c++; } break; }
            case '%':           emit('%', buf, &pos, max); break;
            default:            emit('%', buf, &pos, max); emit(*fmt, buf, &pos, max); break;
        }
    }
    return (int)pos;
}

int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap)
{
    int r = core(buf, n ? n - 1 : 0, fmt, ap);
    if (n) buf[(size_t)r < n ? (size_t)r : n - 1] = '\0';
    return r;
}
int snprintf(char *buf, size_t n, const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt); int r = vsnprintf(buf, n, fmt, ap); va_end(ap); return r;
}
int sprintf(char *buf, const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    int r = core(buf, (size_t)-1, fmt, ap); va_end(ap);
    buf[r] = '\0';
    return r;
}
int printf(const char *fmt, ...)
{
    char buf[256];
    va_list ap; va_start(ap, fmt);
    int r = core(buf, sizeof(buf), fmt, ap); va_end(ap);
    _write(1, buf, r < (int)sizeof(buf) ? r : (int)sizeof(buf));
    return r;
}
int puts(const char *s)
{
    int n = 0; while (s[n]) n++;
    _write(1, s, n); _write(1, "\n", 1);
    return n + 1;
}
