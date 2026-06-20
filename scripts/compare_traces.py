#!/usr/bin/env python3
"""
compare_traces.py  -  diff Spike's commit log against the RTL register dump.

Spike line format (with --log-commits):
    core   0: 3 0x80000000 (0x00500093) x 1 0x00000005
                                        ^^ ^^^^^^^^^^^^
                                        reg     value
Multiple writes to the same reg: only the last one matters for final state.

RTL format (printed by the testbench at exit):
    REGDUMP x5 0x0000000f

Usage:
    python3 compare_traces.py <spike.log> <rtl.log>

Exit: 0 = match, 1 = mismatch, 2 = something broke
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


SPIKE_WRITE_RE = re.compile(
    r"core\s+\d+:\s+\d+\s+0x[0-9a-fA-F]+\s+\([^)]+\)\s+x\s*(\d+)\s+0x([0-9a-fA-F]+)"
)
RTL_DUMP_RE = re.compile(r"REGDUMP\s+x(\d+)\s+0x([0-9a-fA-F]+)")


def parse_spike_log(path: Path) -> dict[int, int]:
    """Return final value of each x-register seen in Spike's commit log."""
    state: dict[int, int] = {i: 0 for i in range(32)}
    with path.open() as f:
        for line in f:
            m = SPIKE_WRITE_RE.search(line)
            if not m:
                continue
            reg = int(m.group(1))
            # mask to 32-bit (Spike will print 64-bit values for RV64)
            val = int(m.group(2), 16) & 0xFFFFFFFF
            state[reg] = val
    return state


def parse_rtl_log(path: Path) -> dict[int, int]:
    state: dict[int, int] = {}
    with path.open() as f:
        for line in f:
            m = RTL_DUMP_RE.search(line)
            if not m:
                continue
            reg = int(m.group(1))
            val = int(m.group(2), 16) & 0xFFFFFFFF
            state[reg] = val
    # default zero for any reg that wasn't dumped (shouldn't happen)
    for i in range(32):
        state.setdefault(i, 0)
    return state


def compare(spike: dict[int, int], rtl: dict[int, int]) -> list[tuple[int, int, int]]:
    diffs = []
    for i in range(32):
        s = spike.get(i, 0)
        r = rtl.get(i, 0)
        if s != r:
            diffs.append((i, s, r))
    return diffs


def pretty_print_state(title: str, state: dict[int, int]) -> None:
    print(f"\n--- {title} ---")
    for i in range(32):
        v = state.get(i, 0)
        signed = v if v < 0x80000000 else v - 0x100000000
        print(f"  x{i:<2} = 0x{v:08x}  ({signed:>12d})")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: compare_traces.py <spike.log> <rtl.log>")
        return 2

    spike_path = Path(sys.argv[1])
    rtl_path = Path(sys.argv[2])

    if not spike_path.exists():
        print(f"spike log not found: {spike_path}")
        return 2
    if not rtl_path.exists():
        print(f"rtl log not found: {rtl_path}")
        return 2

    spike_state = parse_spike_log(spike_path)
    rtl_state = parse_rtl_log(rtl_path)

    # Sanity warnings — if either side parsed nothing, dump some of the file
    # so the user can see what went wrong.
    if all(v == 0 for k, v in spike_state.items() if k != 0):
        print("warning: no register writes parsed from Spike log.")
        print("first 20 lines of spike log:")
        with spike_path.open() as f:
            for i, line in enumerate(f):
                if i >= 20:
                    break
                print(f"  | {line.rstrip()}")

    rtl_nonzero = sum(1 for k, v in rtl_state.items() if k != 0 and v != 0)
    if rtl_nonzero == 0:
        print("warning: no REGDUMP lines parsed from RTL log.")
        print("last 30 lines of rtl log:")
        with rtl_path.open() as f:
            lines = f.readlines()
            for line in lines[-30:]:
                print(f"  | {line.rstrip()}")

    diffs = compare(spike_state, rtl_state)

    pretty_print_state("Spike final state", spike_state)
    pretty_print_state("RTL final state", rtl_state)

    print("\n--- diff ---")
    if not diffs:
        print("  32/32 registers match.")
        return 0

    print(f"  {len(diffs)}/32 registers differ:")
    print(f"  {'reg':<5} {'spike':<15} {'rtl':<15}")
    for reg, s, r in diffs:
        print(f"  x{reg:<4} 0x{s:08x}      0x{r:08x}    <-- FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
