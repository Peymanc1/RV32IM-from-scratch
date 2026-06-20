// syscalls.c  -  the bare-metal "OS" newlib calls into.
//
// newlib's malloc -> _sbrk (heap in DDR, just below the stack); printf/puts ->
// _write (routed to the UART mailbox so output comes out the single cable). The
// rest are minimal stubs so the libc links. This is the layer that lets DOOM's
// 30k lines of malloc/printf/memcpy actually run on our CPU.

#include <sys/stat.h>
#include <sys/types.h>
#include <stdint.h>
#include <errno.h>

#define MBOX (*(volatile uint32_t *)0x90000020u)   // {req(8), char(7:0)}
#define MACK (*(volatile uint32_t *)0x90000024u)   // [0] = ARM ack toggle

extern char _end;                 // end of .bss (from the linker) = heap base
static char *heap_ptr = 0;

void *_sbrk(ptrdiff_t incr)
{
    if (heap_ptr == 0) heap_ptr = &_end;
    char *prev = heap_ptr;
    heap_ptr += incr;
    return (void *)prev;
}

// one char to the PS via the AXI-GPIO mailbox. Fire-and-forget for now (no
// ack wait) so it never blocks on a top that doesn't implement the mailbox
// (e.g. the unified sim core). TODO: re-enable the req/ack handshake on the
// real DOOM SoC top that wires the mailbox + ARM relay.
static void putc_uart(char c)
{
    static uint32_t req = 0;
    req ^= 0x100u;
    MBOX = req | (uint8_t)c;
    (void)MACK;
}

int _write(int fd, const char *buf, int len)
{
    (void)fd;
    for (int i = 0; i < len; i++) putc_uart(buf[i]);
    return len;
}

int   _read (int fd, char *buf, int len) { (void)fd; (void)buf; (void)len; return 0; }
int   _close(int fd)                     { (void)fd; return -1; }
off_t _lseek(int fd, off_t off, int w)   { (void)fd; (void)off; (void)w; return 0; }
int   _fstat(int fd, struct stat *st)    { (void)fd; st->st_mode = S_IFCHR; return 0; }
int   _isatty(int fd)                    { (void)fd; return 1; }
int   _getpid(void)                      { return 1; }
int   _kill(int pid, int sig)            { (void)pid; (void)sig; errno = EINVAL; return -1; }
void  _exit(int code)                    { (void)code; for (;;) { } }
