#!/usr/bin/env bash
# build_libc.sh  -  build a C program LINKED AGAINST newlib, to run from DDR.
#
# Unlike build_demo.sh (freestanding, -nostdlib, hand-rolled), this links the
# real C library: crt0.S (our startup) + syscalls.c (_sbrk/_write/...) + the
# program + newlib (-lc -lm -lgcc), placed in DDR by linker_unified.ld. This is
# the build the DOOM port will grow out of.
#
# Usage:  ./build_libc.sh libc_test [extra1.c extra2.c ...]
# Output: software/program.hex (+ .bin for DDR load, .elf, .dump)

set -euo pipefail
PROG="${1:-libc_test}"; shift || true
EXTRA_SRCS=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SW_DIR="$PROJ_ROOT/software"

GCC=""; for pfx in riscv64-unknown-elf riscv32-unknown-elf riscv-none-elf; do
    command -v "${pfx}-gcc" >/dev/null 2>&1 && { GCC="${pfx}-gcc"; OC="${pfx}-objcopy"; OD="${pfx}-objdump"; SZ="${pfx}-size"; break; }
done
[ -z "$GCC" ] && { echo "no RISC-V gcc on PATH"; exit 1; }
echo "      toolchain: $GCC"

ELF="$SW_DIR/${PROG}.elf"; BIN="$SW_DIR/${PROG}.bin"; HEX="$SW_DIR/program.hex"; DUMP="$SW_DIR/${PROG}.dump"

echo "[1/3] compile+link (newlib): $PROG"
"$GCC" -march=rv32im -mabi=ilp32 -Os -ffreestanding \
       -ffunction-sections -fdata-sections \
       -nostartfiles -Wl,--gc-sections \
       -T "$SW_DIR/linker_unified.ld" \
       -o "$ELF" \
       "$SW_DIR/crt0.S" "$SW_DIR/syscalls.c" "$SW_DIR/malloc_simple.c" "$SW_DIR/printf_simple.c" "$SW_DIR/${PROG}.c" "${EXTRA_SRCS[@]}" \
       -lc -lm -lgcc
"$SZ" "$ELF"
"$OD" -d -M no-aliases,numeric "$ELF" > "$DUMP"

echo "[2/3] objcopy -> binary (.text+.rodata+.data, loaded into DDR @0x10000000)"
"$OC" -O binary -j .text -j .rodata -j .data "$ELF" "$BIN"

echo "[3/3] binary -> program.hex"
python3 -c "
d=open('$BIN','rb').read(); d+=b'\x00'*((-len(d))%4)
open('$HEX','w').write(''.join('%08x\n'%int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)))
print(f'      {len(d)//4} words -> $HEX')
"
echo "done."
