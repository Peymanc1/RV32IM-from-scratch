#!/usr/bin/env bash
# verify.sh  -  end-to-end: compile test program, run on Spike + RTL, diff regs
#
# Usage:
#   verify.sh             # single-cycle (default)
#   verify.sh single
#   verify.sh pipe        # pipelined
#
# Pipeline:
#   1. test_rv32im.S -> ELF (via riscv64-unknown-elf-gcc)
#   2. ELF -> program.hex  (for IMEM)  + program.elf (for Spike)
#   3. Run on Spike  -> spike_trace.log
#   4. Run on RTL    -> rtl_output.log
#   5. compare_traces.py diffs the final register state
#
# Exit codes: 0 = pass, 1 = mismatch, 2 = build/run error

set -euo pipefail

TARGET="${1:-single}"
case "$TARGET" in
    single)
        MAKE_TARGET="sim"
        RTL_BIN_DIR="obj_dir"
        RTL_BIN_NAME="Vtb_rv32im_core"
        echo "[verify] target: single-cycle (rv32im_core)"
        ;;
    pipe|pipeline|pipelined)
        MAKE_TARGET="sim-pipe"
        RTL_BIN_DIR="obj_dir_pipe"
        RTL_BIN_NAME="Vtb_rv32im_core_pipelined"
        echo "[verify] target: pipelined (rv32im_core_pipelined)"
        ;;
    *)
        echo "unknown target: '$TARGET'  (expected: single | pipe)"
        exit 2
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SW_DIR="$PROJ_ROOT/software"
SIM_DIR="$PROJ_ROOT/sim"

TEST_SRC="$SW_DIR/test_rv32im.S"
LD_SCRIPT="$SW_DIR/linker.ld"
TEST_ELF="$SW_DIR/test_rv32im.elf"
TEST_BIN="$SW_DIR/test_rv32im.bin"
TEST_HEX="$SW_DIR/program.hex"
TEST_DUMP="$SW_DIR/test_rv32im.dump"

SPIKE_LOG="$SIM_DIR/spike_trace.log"
RTL_LOG="$SIM_DIR/rtl_output.log"
COMPARE_SCRIPT="$SCRIPT_DIR/compare_traces.py"

# Ubuntu's gcc-riscv64-unknown-elf package provides these. Some systems only
# ship the 32-bit prefix.
RISCV_GCC="riscv64-unknown-elf-gcc"
RISCV_OBJCOPY="riscv64-unknown-elf-objcopy"
RISCV_OBJDUMP="riscv64-unknown-elf-objdump"
if ! command -v "$RISCV_GCC" >/dev/null 2>&1; then
    RISCV_GCC="riscv32-unknown-elf-gcc"
    RISCV_OBJCOPY="riscv32-unknown-elf-objcopy"
    RISCV_OBJDUMP="riscv32-unknown-elf-objdump"
fi

mkdir -p "$SIM_DIR"

# 1. compile
echo "[1/5] compile test program"
"$RISCV_GCC" \
    -march=rv32im -mabi=ilp32 \
    -nostdlib -nostartfiles -static \
    -Wl,--no-relax \
    -T "$LD_SCRIPT" \
    -o "$TEST_ELF" \
    "$TEST_SRC"

"$RISCV_OBJDUMP" -d -M no-aliases,numeric "$TEST_ELF" > "$TEST_DUMP"
echo "      -> $TEST_ELF  (disasm: $TEST_DUMP)"

# 2. ELF -> hex (one 32-bit word per line for $readmemh)
echo "[2/5] generate program.hex for IMEM"
"$RISCV_OBJCOPY" -O binary --only-section=.text "$TEST_ELF" "$TEST_BIN"
python3 -c "
with open('$TEST_BIN','rb') as f: data = f.read()
while len(data) % 4: data += b'\x00'
with open('$TEST_HEX','w') as f:
    for i in range(0, len(data), 4):
        w = int.from_bytes(data[i:i+4], byteorder='little')
        f.write(f'{w:08x}\n')
print(f'      {len(data)//4} instructions -> $TEST_HEX')
"

# 3. Spike
echo "[3/5] run on Spike"
if ! command -v spike >/dev/null 2>&1; then
    echo "spike not installed. run:"
    echo "  $SCRIPT_DIR/build_spike.sh"
    exit 2
fi

# --log-commits prints one line per retired instruction with the dest reg's
# new value. timeout caps the run if the program ends in a halt-loop.
timeout 5s spike \
    --isa=rv32im \
    -m0x80000000:0x10000 \
    --log-commits \
    "$TEST_ELF" \
    > "$SPIKE_LOG" 2>&1 || true

echo "      -> $SPIKE_LOG ($(wc -l < "$SPIKE_LOG") lines)"

# 4. RTL
echo "[4/5] run on RTL"
cp "$TEST_HEX" "$SIM_DIR/program.hex"
(cd "$SCRIPT_DIR" && make "$MAKE_TARGET") 2>&1 | tail -20
RTL_BIN_PATH="$SIM_DIR/$RTL_BIN_DIR/$RTL_BIN_NAME"
if [ ! -x "$RTL_BIN_PATH" ]; then
    echo "RTL build failed: $RTL_BIN_PATH not found"
    exit 2
fi
(cd "$SIM_DIR" && "./$RTL_BIN_DIR/$RTL_BIN_NAME") > "$RTL_LOG" 2>&1 || true
echo "      -> $RTL_LOG"

# 5. diff
echo "[5/5] compare traces"
python3 "$COMPARE_SCRIPT" "$SPIKE_LOG" "$RTL_LOG"
result=$?

echo ""
if [ $result -eq 0 ]; then
    echo "=========================================="
    echo "  PASS — RTL matches Spike bit-exact."
    echo "=========================================="
else
    echo "=========================================="
    echo "  FAIL — see diff above."
    echo "  RTL log:   $RTL_LOG"
    echo "  Spike log: $SPIKE_LOG"
    echo "=========================================="
fi

exit $result
