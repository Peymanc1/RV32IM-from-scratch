#!/usr/bin/env bash
# build_demo.sh  -  assemble a .S into program.hex
#
# Usage:
#   ./build_demo.sh                # default: demo_blink
#   ./build_demo.sh demo_blink     # explicit
#   ./build_demo.sh test_rv32im    # the verification test
#
# Output:  software/program.hex  (Vivado / sim IMEM init)

set -euo pipefail

PROG="${1:-demo_blink}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SW_DIR="$PROJ_ROOT/software"

ELF="$SW_DIR/${PROG}.elf"
BIN="$SW_DIR/${PROG}.bin"
HEX="$SW_DIR/program.hex"
DUMP="$SW_DIR/${PROG}.dump"

# Accept either an assembly (.S) or a C (.c) source.
EXTRA_CFLAGS=""
if [ -f "$SW_DIR/${PROG}.S" ]; then
    SRC="$SW_DIR/${PROG}.S"
elif [ -f "$SW_DIR/${PROG}.c" ]; then
    SRC="$SW_DIR/${PROG}.c"
    # freestanding C, size-optimised so it stays in the small IMEM.
    EXTRA_CFLAGS="-ffreestanding -Os -Wall"
    # libgcc for 64-bit fixed-point helpers (__divdi3 etc.); no libc pulled in.
    EXTRA_LIBS="-lgcc"
else
    echo "error: neither $SW_DIR/${PROG}.S nor ${PROG}.c found"
    exit 1
fi

# Pick whichever bare-metal RISC-V GCC prefix is on PATH. Order: the common
# Linux-distro names, then the xpack "riscv-none-elf-" prefix.
GCC=""
for pfx in riscv64-unknown-elf riscv32-unknown-elf riscv-none-elf; do
    if command -v "${pfx}-gcc" >/dev/null 2>&1; then
        GCC="${pfx}-gcc"; OBJCOPY="${pfx}-objcopy"; OBJDUMP="${pfx}-objdump"
        break
    fi
done
if [ -z "$GCC" ]; then
    echo "error: no RISC-V gcc found on PATH (tried riscv64/riscv32-unknown-elf, riscv-none-elf)"
    exit 1
fi
echo "      toolchain: $GCC"

echo "[1/3] compile: $PROG  ($(basename "$SRC"))"
"$GCC" -march=rv32im -mabi=ilp32 \
       $EXTRA_CFLAGS \
       -nostdlib -nostartfiles -static \
       -Wl,--no-relax \
       -T "$SW_DIR/${LD_SCRIPT:-linker.ld}" \
       -o "$ELF" "$SRC" ${EXTRA_LIBS:-}

"$OBJDUMP" -d -M no-aliases,numeric "$ELF" > "$DUMP"
echo "      -> $ELF  (disasm: $DUMP)"

echo "[2/3] objcopy -> binary"
# Copy .text AND .rodata (they're contiguous in ROM). -Os can spill large
# constants / switch tables into .rodata; if we copy only .text those bytes are
# absent from IMEM and the program reads garbage. Both go into program.hex.
"$OBJCOPY" -O binary -j .text -j .rodata -j .srodata "$ELF" "$BIN"

echo "[3/3] binary -> hex (32-bit word per line)"
python3 -c "
with open('$BIN','rb') as f: data = f.read()
while len(data) % 4: data += b'\x00'
with open('$HEX','w') as f:
    for i in range(0, len(data), 4):
        w = int.from_bytes(data[i:i+4], 'little')
        f.write(f'{w:08x}\n')
print(f'      {len(data)//4} words -> $HEX')
"

echo ""
echo "done. program.hex is ready."
echo "  for sim    : will be picked up by 'make sim-pipe' automatically"
echo "  for Vivado : add as a design source with type = Memory Initialization Files"
