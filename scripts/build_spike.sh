#!/usr/bin/env bash
# build_spike.sh  -  build the RISC-V ISA simulator (Spike) from source
#
# Prereqs:
#   git, gcc/g++, make, autoconf, device-tree-compiler (dtc)
#   ~500 MB disk, 5-10 min build time
#
# Installs to:  /usr/local/bin/spike

set -euo pipefail

SPIKE_SRC_DIR="${HOME}/.local/src/riscv-isa-sim"
SPIKE_BUILD_DIR="${SPIKE_SRC_DIR}/build"

echo "[1] checking dependencies"
for cmd in git autoconf gcc g++ make dtc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing: $cmd"
        echo "install with: sudo apt install -y git autoconf gcc g++ make device-tree-compiler"
        exit 1
    fi
done

echo "[2] fetch / update source"
mkdir -p "$(dirname "$SPIKE_SRC_DIR")"
if [ ! -d "$SPIKE_SRC_DIR" ]; then
    git clone https://github.com/riscv-software-src/riscv-isa-sim.git "$SPIKE_SRC_DIR"
else
    (cd "$SPIKE_SRC_DIR" && git pull --ff-only || true)
fi

echo "[3] configure & build"
mkdir -p "$SPIKE_BUILD_DIR"
cd "$SPIKE_BUILD_DIR"
../configure --prefix=/usr/local
make -j"$(nproc)"

echo "[4] install (sudo)"
sudo make install

echo ""
echo "spike installed:"
which spike
spike --help 2>&1 | head -5 || true
