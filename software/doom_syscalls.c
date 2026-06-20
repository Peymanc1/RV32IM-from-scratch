// doom_syscalls.c  -  bare-metal syscalls + WAD-from-DDR file layer.
// _open/_read/_lseek serve DOOM1.WAD straight out of DDR (loaded at
// WAD_BASE by xsdb). Other paths get a no-op fd. _sbrk grows heap up
// toward stack. _write goes to the UART mailbox.

#include <sys/stat.h>
#include <sys/types.h>
#include <stdint.h>
#include <errno.h>

#define WAD_BASE 0x18000000u            // where XSCT loads DOOM1.WAD into DDR
#define WAD_SIZE 4196020u               // shareware DOOM1.WAD size in bytes

#define MBOX (*(volatile uint32_t *)0x90000020u)

extern char _end;
static char *heap_ptr = 0;
void *_sbrk(ptrdiff_t incr)
{
    if (!heap_ptr) heap_ptr = &_end;
    char *prev = heap_ptr; heap_ptr += incr; return prev;
}

// ---- minimal file descriptors ----
static struct { uint8_t used, iswad; uint32_t off; } fds[16];

static int is_wad(const char *name)
{
    const char *b = name, *p;
    for (p = name; *p; p++) if (*p == '/' || *p == '\\') b = p + 1;
    int n = 0; while (b[n]) n++;
    if (n < 4) return 0;
    const char *e = b + n - 4;
    return (e[0]=='.') && (e[1]=='w'||e[1]=='W') && (e[2]=='a'||e[2]=='A') && (e[3]=='d'||e[3]=='D');
}

int _open(const char *name, int flags, int mode)
{
    (void)flags; (void)mode;
    if (!is_wad(name)) return -1;          // only the WAD "exists"; others fail
    for (int fd = 3; fd < 16; fd++) if (!fds[fd].used) {
        fds[fd].used = 1; fds[fd].off = 0; fds[fd].iswad = 1;
        return fd;
    }
    return -1;
}

int _read(int fd, char *buf, int len)
{
    if (fd < 3 || fd >= 16 || !fds[fd].used) return 0;
    if (!fds[fd].iswad) return 0;                  // non-WAD files read empty
    uint32_t off = fds[fd].off;
    if (off >= WAD_SIZE) return 0;
    uint32_t n = (uint32_t)len;
    if (off + n > WAD_SIZE) n = WAD_SIZE - off;
    const volatile uint8_t *w = (const volatile uint8_t *)(WAD_BASE + off);
    for (uint32_t i = 0; i < n; i++) buf[i] = w[i];
    fds[fd].off = off + n;
    return (int)n;
}

off_t _lseek(int fd, off_t off, int whence)
{
    if (fd < 3 || fd >= 16 || !fds[fd].used) return 0;
    uint32_t base = (whence == 0) ? 0 : (whence == 2) ? WAD_SIZE : fds[fd].off;
    fds[fd].off = base + (uint32_t)off;
    return (off_t)fds[fd].off;
}

int _fstat(int fd, struct stat *st)
{
    if (fd >= 3 && fd < 16 && fds[fd].used && fds[fd].iswad) {
        st->st_mode = S_IFREG; st->st_size = WAD_SIZE; return 0;
    }
    st->st_mode = S_IFCHR; return 0;
}

int _close(int fd) { if (fd >= 3 && fd < 16) fds[fd].used = 0; return 0; }

int _write(int fd, const char *buf, int len)
{
    (void)fd;
    static uint32_t req = 0;
    for (int i = 0; i < len; i++) { req ^= 0x100u; MBOX = req | (uint8_t)buf[i]; }
    return len;
}

int  _isatty(int fd)            { return fd < 3; }
int  _getpid(void)              { return 1; }
int  _kill(int p, int s)        { (void)p;(void)s; errno = EINVAL; return -1; }
void _exit(int c)               { (void)c; for (;;) {} }
int  mkdir(const char *p, mode_t m){ (void)p;(void)m; return 0; }   // no FS, fake ok
