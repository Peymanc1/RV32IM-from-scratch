# RV32IM — a RISC-V CPU built from scratch, running DOOM

> A from-scratch RISC-V (RV32IM) CPU in SystemVerilog, the SoC built around it, and the bare-metal software that runs DOOM on it. It explains how each part is built and how to reproduce the whole thing end to end — module by module, with the real signal names from the RTL. No prior FPGA or RISC-V background is assumed.

> **Diagrams (colored, in browser):** for processor internal datapath `docs/datapath.html`; for on-chip/SoC datapath (cache / AXI / DDR / framebuffer, with address labels) `docs/system_datapath.html`.

---

## Table of Contents

* [0. How to read this document](#0-how-to-read-this-document)

**PART I — SYSTEM OVERVIEW AND FUNDAMENTALS**

* [1. The big picture — system architecture](#1-the-big-picture--system-architecture)
* [2. How the project was built, in order](#2-how-the-project-was-built-in-order)
* [3. RISC-V and RV32IM fundamentals](#3-riscv-and-rv32im-fundamentals)
* [4. Pipeline overview (5 stages)](#4-pipeline-overview-5-stages)
* [5. Datapath — signal flow (with diagrams)](#5-datapath--signal-flow-with-diagrams)

**PART II — MODULES (each module individually)**

* [6. Core files — file by file](#6-core-files--file-by-file)
* [7. Memory system — cache, AXI, DDR](#7-memory-system--cache-axi-ddr)
* [8. Video pipeline (framebuffer → HDMI)](#8-video-pipeline-framebuffer--hdmi)
* [9. Software side — toolchain, linker, libc](#9-software-side--toolchain-linker-libc)

**PART III — HOW EVERYTHING CONNECTS TOGETHER**

* [10. End-to-end — how everything connects together](#10-end-to-end--how-everything-connects-together)
* [11. Assembling the pipeline (rv32im\_core\_pipelined.sv)](#11-assembling- the-pipeline-rv32im_core_pipelinedsv)
* [12. Forwarding and hazard — cycle by cycle](#12-forwarding-and-hazard--cycle-by-cycle)
* [13. Address map, MMIO, bitstream vs program](#13-address-map-mmio-bitstream-vs-program)
* [14. SoC top modules (top)](#14-soc-top-modules-top)
* [15. DOOM port — file by file and call chain](#15-doom-port--file-by-file-and-call-chain)

**PART IV — SETUP, VERIFICATION, PORTABILITY**

* [16. Build and run from scratch](#16-build-and-run-from-scratch)
* [17. Verification (Spike, cache TB, DOOM sim)](#17-verification-spike-cache-tb-doom-sim)
* [18. Portability (Basys 3, Tang Nano, USB, bootloader)](#18-portability-basys-3-tang-nano-usb-bootloader)

**APPENDICES**

* [19. Hazards, constraints, and design choices](#19-hazards-constraints-and-design-choices)
* [20. Glossary](#20-glossary)
* [21. Instruction summary (cheat sheet)](#21-instruction-summary-cheat-sheet)

---

## 0\. How to read this document

There are two "worlds", and you will learn both:

* **Hardware (RTL):** SystemVerilog under `rtl/`. The circuit synthesized onto the FPGA — meaning the processor **itself**. Chapters 1–10.
* **Software (C/asm):** `software/` + `doom/`. The program executed by the processor. Chapters 9–12.

The bridge: the **compiler** translates software into machine code → a binary file → loaded into memory → the processor fetches and executes the instructions.

Recommended reading order: Chapter 1 (big picture) → 2 (RISC-V basics) → 3–6 (processor) → 7–9 (memory+IO+video) → 11–12 (software+DOOM) → 13 (run). If you are in a hurry: Chapters 1 + 13 are enough; dive deeper later.

Notation: `file.sv:42` = the 42nd line of that file. Code snippets are exact quotes from the source.

---

# PART I — SYSTEM OVERVIEW AND FUNDAMENTALS

## 1\. The big picture — system architecture

Goal: To run DOOM on a Zybo Z7-20 FPGA board, on an RV32IM processor we **wrote from scratch**.

**RV32IM** = 32-bit RISC-V, **I** (base integer instructions) + **M** (multiply/divide). The processor is a **5-stage pipeline** (assembly line): instructions pass through 5 stages, 5 instructions are processed simultaneously.

We placed this processor inside an **SoC** (System-on-Chip):

![On-chip SoC datapath: CPU -> I/D-cache -> AXI burst -> SmartConnect -> S_AXI_HP -> DDR; MMIO -> framebuffer/palette/LED -> HDMI (AXI/MMIO addresses labeled)](system_datapath.svg)

*Colored SVG; the same visual is in `docs/system_datapath.html` with the address-map table.*

**Important concept — Zynq has two parts:**

* **PS (Processing System):** ARM Cortex-A9 + hard peripherals (USB, DDR controller, UART…). In our DOOM SoC, the PS only **turns on the clocks and the DDR controller**; it does not run our code or move data.
* **PL (Programmable Logic):** the actual FPGA fabric — **the RV32IM core and all peripherals are here**.

**Where is the data:** The program (`doom.bin`), heap, stack, and WAD data are in **DDR** (1 GB external memory chip connected to PS). The processor accesses DDR via **its own caches + AXI burst master**. The framebuffer and LED are not in DDR, but **inside PL** (behind the mmio\_bridge).

**How the project was built, in order:**

```
single-cycle → 5-stage pipeline → FPGA bring-up (LED/UART) → raycaster (HDMI) → DDR+cache → DOOM
```

---

## 2\. How the project was built, in order

The project was built in steps, each one working before the next was started. Each step proves one concept and sets up the next. This section goes through what each step proved, the idea behind it, and the files involved.

### M0 — Processor: single-cycle → pipeline (validation by reference)

First, a single-cycle RV32IM (conceptual foundation) was written, followed by a 5-stage pipeline.  
**Concept — ISA compliance:** For a processor to be "correct", it must run the same program as a **golden reference** (here, the [Spike](https://github.com/riscv-software-src/riscv-isa-sim) ISA simulator) with a **bit-exact** identical result. The same `program.hex` runs on both Spike and Verilator; the final states of the 32 registers are compared (`make verify`, `make verify-pipe`).  
**Proof:** The processor executes RISC-V correctly (no I/O yet, pure computation).  
**Files:** `rtl/top/rv32im_core.sv`, `rv32im_core_pipelined.sv`, `tb/integration/*`, `scripts/compare_traces.py`.

### M1 — LED blink: first hardware output (MMIO concept)

**Goal:** To see the processor do something in the external world — a blinking LED on the board.  
**Concept — MMIO (Memory-Mapped I/O):** You represent a hardware unit (LED) like a **memory address**; when software writes to that address, the hardware reacts. The line `*(volatile uint32_t*)0x90000000 = x;` looks like an ordinary memory write, but the `mmio_bridge` redirects that address to the LED register.  
**How:** `mmio_bridge` decodes the address (0x90000000 → LED); the software changes the value in a loop, reading from the free-running cycle counter (0x90000004).  
**Proof:** Datapath + clock + reset + an MMIO output are actually working on the board — the smallest "sign of life" for bring-up.  
**Files:** `rv32im_fpga_top.sv`, `mmio_bridge.sv`, `software/demo_blink.S`.

### M2 — UART: text from software (serial communication)

**Goal:** To get `printf` output from the processor — invaluable for development/debugging.  
**Concept — UART:** A simple asynchronous serial protocol that sends data bit by bit over a single wire; it appears in a terminal on the computer. On Zybo, the PS's USB-UART bridge carries this with a single cable.  
**How:** Software writes each character to an MMIO mailbox (0x90000020); `printf → _write → mailbox`.  
**Proof:** Software ↔ human communication established; now "what is happening" can be seen (printing values, monitoring status). The foundation for all subsequent debugging.  
**Files:** `software/demo_uart.c`, `doom_syscalls.c` (`_write`).

### M3 — Raycaster: first "screen" (framebuffer + fixed-point)

**Goal:** To draw a real image on the screen — a Wolfenstein-like raycaster.  
**Concept — framebuffer:** Every pixel on the screen is a memory cell; software writes a color **index** to that memory, and hardware constantly scans it and outputs it to HDMI (320×200, 8-bit index + 256 color palette).  
**Concept — fixed-point math:** There is no floating-point unit (FPU) in hardware; angle/distance calculations are done using **integer fractional** (Q-format) math.  
**Constraint (instructive) — 64-bit division:** libc's 64-bit division (`__divdi3`) accesses a `.rodata` table (`__clz_tab`); since it could not be read from the data port in Harvard memory, the raycaster initially kept drawing "walls". Solution: A `recip()` using 32-bit hardware DIVU. Recognizing such platform constraints is an important engineering lesson.  
**Proof:** The video pipeline (framebuffer → palette → timing → rgb2dvi → HDMI) and intense computation are working together as a real-time graphics program.  
**Files:** `software/raycaster.c`, `rtl/video/*`, `rv32im_video_top.sv`.

### M4 — Access to DDR: why cache + AXI were needed

**Problem:** DOOM requires ~37 MB; on-chip BRAM is only a few hundred KB. Program + data cannot fit in BRAM → external DDR is mandatory.  
**Concept — why cache:** DDR is slow and requires bulk (burst) access; the processor, however, expects fast access on every instruction. A **cache** is placed in between: it keeps frequently used data locally and fetches a line from DDR on a miss.  
**Concept — AXI burst:** It reads/writes a cache line (32 bytes) with a single address in consecutive beats. `axi_burst_master` does this; the path: `cache → burst → SmartConnect → PS S_AXI_HP → DDR controller`.  
**Proof:** The processor directly accesses the PS's DDR from the PL (cache → burst → HP) — megabytes of data are now possible.  
**Files:** `cache.sv`, `axi_burst_master.sv`, `rv32im_ddr_core.sv`.

### M5 — Running CODE from DDR (I-cache + back-pressure)

**Goal:** To fetch and run the program **itself** from DDR, not just the data (the program is also large).  
**Concept:** A read-only **I-cache** fills instructions from DDR. Since fetching can take multiple cycles, `imem_ready` back-pressure was added to the processor: if not ready, a NOP bubble is injected into IF/ID, and the PC is frozen with branch-protection. Additionally, the cache fill address needs to be latched (Section 7.1/15).  
**Proof:** The reset vector is 0x10000000 (DDR); the CPU boots directly from there.  
**Files:** `rv32im_iddr_core.sv`, `cache.sv` (req\_addr latch), `pc.sv` (RESET\_VEC).

### M6 — Unified memory (I and D in the same DDR)

**Goal:** Code and data are in a single DDR address space; two separate AXI masters (one for I, one for D).  
**Proof:** The full SoC memory map required by DOOM is ready.  
**Files:** `rv32im_unified_core.sv`.

### M7 — Bare-metal C library (newlib + crt0 + linker + syscalls)

**Goal:** To run a large C program like DOOM **without an operating system**.  
**Concept — bare-metal:** There is no OS; libc's "system calls" (`_open/_read/_write/_sbrk/_fstat`) descend into our small layer. `crt0` sets up sp/gp, clears `.bss`, and jumps to `main`; the linker script determines the layout.  
**Concept — presenting the WAD like a file:** newlib's `fopen/fread` descends to a layer that performs a `memcpy` from the WAD in DDR (`w_file_stdc.c`).  
**Proof:** newlib + our libc parts are working correctly (verified in sim). Situations thought to be "newlib crashing" were actually a workflow pitfall where the sim hex file was overwritten with an old copy.  
**Files:** `crt0_doom.S`, `linker_doom.ld`, `doom_syscalls.c`, `malloc_simple.c`, `printf_simple.c`.

### M8 — DOOM

**Goal:** To combine everything and run DOOM.  
**Concept:** The `doomgeneric` platform layer — `DG_DrawFrame` copies the screen to the framebuffer, `DG_GetKey` maps switches to keys, and `DG_GetTicksMs` generates time from the cycle counter. DOOM's 320×200 8-bit palette format is **identical** to the hardware, so the platform layer is mostly just a copy.  
**Design-handled hazard:** Preserving write-back forwarding during multi-cycle stalls (Section 12.4) — complex compiled code triggers this pattern.  
**Proof:** DOOM boots and renders both on the board and in the Verilator simulation of the actual RTL.

### Bootloader requirement — why it wasn't needed on Zybo, when it is needed

Separate three distinct concepts: **bitstream** (hardware) / **bootloader** (small loader) / **application** (`.bin`).  
`.bin` = application (DOOM), not boot; bootloader = the first to run, a small program that brings the large application from external memory.

* **There is NO bootloader on Zybo.** The job of putting the program into DDR is handled by the **external JTAG loader** (XSCT `dow`); the CPU runs the program **already waiting** at 0x10000000 at reset. `crt0` is not a bootloader (it doesn't load; it only sets up the C environment).
* **When is it needed:** On a pure FPGA board without a PS/JTAG-loader (Basys 3, Tang Nano). Then the program is either **embedded inside the bitstream in BRAM** (if small), or a small **bootloader** is embedded in BRAM, which copies the large application from SD/flash to SDRAM and jumps to it.
* **Our solution:** Thanks to Zynq + XSCT, progress was made without writing a bootloader. This is also the answer to the question "why Zynq was chosen": ready-made DDR + DDR controller + JTAG loader provides memory and loading on the scale of DOOM for free. (Portability and writing a bootloader: Section 18.)

---

## 3\. RISC-V and RV32IM fundamentals

To understand the processor, one must first understand the instruction set (ISA). Source: `rtl/core/rv32im_pkg.sv` — the common types/constants imported by all modules are here.

### 3.1 Registers

32 32-bit registers: `x0`–`x31`. `**x0**` **is always 0** (writes are ignored, reads return 0 — short-circuited in `regfile.sv`). ABI names: `zero(x0), ra(x1 return address), sp(x2 stack), gp(x3 global), a0–a7(arguments/return), s0–s11(saved), t0–t6(temporary)`.

### 3.2 Instruction formats (32-bit)

There are 6 formats in RISC-V; immediate bits are gathered from different places depending on the format (`immgen.sv` handles this):

| Format | Usage | Immediate |
| --- | --- | --- |
| **R** | ADD, SUB, AND, MUL… (register-register) | none |
| **I** | ADDI, LW, JALR (register-immediate) | `[31:20]` sign-extended |
| **S** | SW (store) | `[31:25]`+`[11:7]` |
| **B** | BEQ, BNE… (branch) | scattered, bit0=0 (2-byte aligned target) |
| **U** | LUI, AUIPC (upper 20 bits) | `[31:12]`\<\<12 |
| **J** | JAL | scattered, bit0=0 |

|

### 3.3 Opcodes (`inst[6:0]`)

`opcode_e` in `rv32im_pkg.sv`:

```
OP_LUI 0110111   OP_AUIPC 0010111   OP_JAL 1101111   OP_JALR 1100111
OP_BRANCH 1100011  OP_LOAD 0000011  OP_STORE 0100011
OP_ITYPE 0010011 (ADDI etc.)   OP_RTYPE 0110011 (ADD/SUB + M-ext)
OP_FENCE 0001111 (NOP for now)   OP_SYSTEM 1110011 (ECALL/CSR — placeholder)
```

What an instruction does is determined by the triplet: **opcode + funct3 + funct7**. E.g., `OP_RTYPE` + `funct3=000` → if the 5th bit of funct7 is 0, it's ADD; if 1, it's SUB. **M-extension** = `OP_RTYPE` + `funct7=0000001` (multiply/divide).

### 3.4 Addressing and reset

`RESET_VECTOR = 0x80000000` (Spike + GNU toolchain default). In the BRAM-based core, only the lower bits of the address are used (wraps around). In the DOOM SoC, the reset vector is overridden to **0x10000000** (the start of the program in DDR).

---

## 4\. Pipeline overview (5 stages)

An instruction passes through these 5 stations sequentially; it advances one station per clock cycle:

| Stage | Full Name | What it does | Main file(s) |
| --- | --- | --- | --- |
| **IF** | Instruction Fetch | Reads the instruction from the address pointed to by PC | `pc.sv`, I-cache/imem |
| **ID** | Instruction Decode | Splits the instruction, reads registers, control signals | `decoder.sv`, `control_unit.sv`, `immgen.sv`, `regfile.sv` |
| **EX** | Execute | ALU / multiply-divide / branch decision | `alu.sv`, `mul_div.sv`, `branch_unit.sv` |
| **MEM** | Memory | load/store, D-cache/MMIO | `cache.sv`, `mmio_bridge.sv` |
| **WB** | Write-Back | Writes the result back to the register | `regfile.sv` |

**Pipeline registers** between stages (buckets): `idex_*` (ID/EX), `exmem_*` (EX/MEM), `memwb_*` (MEM/WB) in the code. They carry the output of one stage to the next on the next clock edge.

**Why pipeline?** 5 instructions at the same time → ~5x speedup. The cost: **hazards** (the result of an instruction is needed by the next one before it is written to WB). Solutions: **forwarding** and the **hazard unit** (Chapter 12).

The file assembling everything: `**rtl/top/rv32im_core_pipelined.sv**` (Chapter 11).

---

## 5\. Datapath — signal flow (with diagrams)

This section shows the datapath module by module and MUX by MUX. First, the single-cycle version (conceptually clearest) is given, followed by the version split into a pipeline.

### 5.1 Single-cycle datapath

In the single-cycle design, five logical stages occur in a single clock period as a combinational chain. There are only two sequential elements (updated on the clock edge): the **PC** and the **register file**. The clock period must be long enough to cover the longest path `PC→IMEM→decode→regread→ALU→DMEM→WB`; this is the reason for transitioning to a pipeline.

**Four critical MUXes** (the "decision points" of the datapath; all driven by the `control_unit`):

| MUX | Options | Driven by | When |
| --- | --- | --- | --- |
| **PC\_sel** | pc+4 / branch\_target / jalr\_target | `pc_sel_i` | when branch taken / JAL / JALR |
| **ALU\_A** | rs1 / PC | `alu_a_sel` | AUIPC, BRANCH, JAL → PC; rest → rs1 |
| **ALU\_B** | rs2 / immediate | `alu_b_sel` | I-type/load/store/LUI/AUIPC → imm; R-type → rs2 |
| **WB** | alu\_result / mem\_rdata / pc+4 | `wb_sel` | load → mem; JAL/JALR → pc+4; rest → alu |

The branch target and JALR target are also calculated via the ALU (`alu_a=PC, alu_b=imm` → PC+imm; in JALR `rs1+imm`, the LSB is masked).

### 5.2 Pipeline datapath (5 stages + 4 registers + forwarding)

The pipeline slices the same combinational datapath with four **pipeline registers**. On each clock cycle, each instruction advances one stage; five instructions are in different stages at the same time.

![RV32IM core module-connectivity diagram: every .sv module inside rv32im_core_pipelined.sv (pc, decoder, control_unit, immgen, regfile, alu, branch_unit, mul_div, forwarding_unit, hazard_unit) drawn as a box, with the real RTL signals between them (if_pc, ifid_inst, idex_rs1_data, ex_alu_result, exmem_alu_result, mem_wb_data, fwd_a/b, stall_*/bubble_*, wb_rd_data) as arrows; the four pipeline registers and the PC / forwarding / hazard / flush feedback paths](datapath.svg)

*Colored, module-by-module SVG; browser large version and deep analysis in `docs/datapath.html`. Pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB) stand between stages; stall/flush logic with forwarding is explained cycle by cycle in Chapter 12.*

**How to read the diagram.** Read it left to right: an instruction enters at **IF** and advances one stage per clock, so at any moment five instructions occupy the five bands. Each box is one `.sv` module (its instance name and file are printed under the role) and every arrow is a real RTL net whose label is the exact signal name in `rv32im_core_pipelined.sv`. The four dark vertical bars are the pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB); a value only crosses a bar on a clock edge — that is how each stage hands work to the next.

Following one instruction through the boxes: in **IF**, `u_pc` drives `imem_addr_o`; the external I-cache returns the word as `if_inst`, and `if_pc` / `if_pc_plus4` are latched into IF/ID. In **ID**, `u_decoder` splits the instruction, `u_ctrl` turns the opcode into the control bundle (`alu_a_sel`, `alu_b_sel`, `alu_op`, `wb_sel`, `mem_we/re`, `reg_we`, `is_branch/jal/jalr/mdiv`, `br_type`), `u_immgen` builds `id_imm`, and `u_regfile` reads the two source registers (the WB→ID bypass produces `id_rs1_eff` / `id_rs2_eff`); all of this is latched into ID/EX. In **EX**, the two `fwd` muxes pick each operand's true source — the ID/EX value or a forwarded `mem_wb_data` / `wb_rd_data` — yielding `ex_rs1_fwd` / `ex_rs2_fwd`; the ALU-operand muxes then choose PC vs rs1 and imm vs rs2; `u_alu`, `u_branch` and `u_mul_div` all consume these operands, and the result mux selects ALU vs Mul/Div into `ex_result_final`. In **MEM**, `exmem_alu_result` becomes `dmem_addr_o` to the external D-cache / MMIO, the store value rides `exmem_rs2_data`, and the `wb_sel` mux chooses ALU result / `dmem_rdata_i` / pc+4 into `mem_wb_data`. In **WB**, that value is `wb_rd_data`, written back into `u_regfile`.

The three feedback systems are drawn in their own colors. **Green** carries the EX-resolved branch (`ex_branch_taken` / `ex_branch_target`) back to `u_pc` and triggers `flush_ifid` / `flush_idex`. **Purple** is forwarding: `u_fwd` drives the `fwd_a` / `fwd_b` selects, while `mem_wb_data` (FWD_FROM_M) and `wb_rd_data` (FWD_FROM_W) are the candidate values routed back to the EX muxes. **Orange** is the hazard unit's stall/bubble lines into PC, IF/ID, ID/EX and EX/MEM. The **navy** rail along the bottom is the write-back bus returning to the register file. Together, these feedback paths are why five instructions can overlap in the pipeline yet still produce the same result as if each had run to completion alone.

**Forwarding paths** (cycle by cycle in Chapter 12): The operand of an instruction in the EX stage may come from a previous instruction that hasn't been written to the register file yet. The `forwarding_unit` selects the source:

* **FWD\_FROM\_M:** previous instruction is in the MEM stage → its result (`mem_wb_data`) is forwarded.
* **FWD\_FROM\_W:** two instructions ahead in the WB stage → its result (`wb_rd_data`) is forwarded.
* **FWD\_NONE:** no conflict → the value read from the register file is used.

**Stall/flush points:** load-use dependency causes a 1-cycle stall (Section 12.3); if a branch is resolved and taken in EX, the two instructions in IF/ID and ID are flushed (predict-not-taken); if memory access is not serviced (`dmem_ready=0`), the entire pipeline freezes (`mem_stall`).

---

# PART II — MODULES (each module individually)

## 6\. Core files — file by file

Each module under `rtl/core/`: what it does, its inputs/outputs, how it works, and where it is used. All of them import `rv32im_pkg`.

### 6.1 `rv32im_pkg.sv` — common vocabulary (103 lines)

**What:** All enums and constants. ISA opcodes, ALU operation codes (`alu_op_e`), branch types (`branch_e`), immediate format selector (`imm_type_e`), PC selector (`pc_sel_e`), write-back selector (`wb_sel_e`), ALU operand selectors, and pipeline-specific **forwarding selector** (`fwd_sel_e`: FWD\_NONE / FWD\_FROM\_W / FWD\_FROM\_M).  
**Where:** Every module does `import rv32im_pkg::*;`. Types are centrally defined here → consistency.  
**Why it matters:** Control signals are named enums, not "strings" → readable and error-free.

### 6.2 `pc.sv` — Program Counter (45 lines)

**What:** A register holding the address of the next instruction. It can be frozen with `stall_i` (hazard).  
**Operation:** Depending on `pc_sel_i`, the next PC is `pc+4` (PC\_PLUS4), `branch_target` (PC\_BRANCH), or `jalr_target` (PC\_JALR). If `stall_i` is high, the PC is not updated (the instruction waits in place).  
**Detail:** Goes to `RESET_VEC` on reset — in the DOOM core this is overridden to **0x10000000** (the start of the program in DDR). `pc_plus4_o` is also output externally because the JAL/JALR return address (ra = pc+4) needs it.  
**Where:** IF stage.

### 6.3 `decoder.sv` — bit slicer (25 lines)

**What:** Pure bit extraction, no logic. Extracts fields from the 32-bit instruction: `opcode=inst[6:0]`, `rd=inst[11:7]`, `funct3=inst[14:12]`, `rs1=inst[19:15]`, `rs2=inst[24:20]`, `funct7=inst[31:25]`.  
**Where:** ID stage; its outputs are consumed by the `control_unit` and `regfile`.

### 6.4 `immgen.sv` — immediate generator (47 lines)

**What:** Collects the constant (immediate) from the relevant bits for each format and sign-extends it to 32 bits.  
**Operation:** Separate assembly for I/S/B/U/J formats; selected by `imm_type_i`. In **B and J** formats, the immediate bits are distributed throughout the instruction to share signals with the R/I/S formats; immgen reassembles and sign-extends these bits. E.g., I-type: `{{20{inst[31]}}, inst[31:20]}` (sign-extension).  
**Where:** ID stage; the B operand of the ALU (`alu_b_sel=ALU_B_IMM`), branch/jump targets.

### 6.5 `regfile.sv` — register file (38 lines)

**What:** 32×32-bit registers. **Two combinational read ports** (rs1, rs2), **one synchronous write port** (rd).  
**Operation:** Writing occurs on the clock edge (`we_i && rd!=0`). Reading is instantaneous. `x0` is always 0 (short-circuited on read).  
**Fine point:** Writing happens in the WB stage; an instruction reading at the same time sees the old value → forwarding is required (Chapter 12). (In our design, regfile write is in WB, read is in ID; the pipeline manages this with forwarding.)  
**Where:** ID (read), WB (write).

### 6.6 `alu.sv` — Arithmetic-Logic Unit (37 lines)

**What:** Purely combinational. According to `alu_op_i`: ADD, SUB, SLL (shift), SLT/SLTU (compare), XOR, SRL/SRA (shift), OR, AND, PASSB (pass B straight through — for LUI).  
**Detail:** RV32 shifts use the **lower 5 bits** of operand\_b (`shamt`). `SLT` is signed, `SLTU` is unsigned comparison. The `zero_o` output (is the result 0) is useful in some places.  
**Where:** EX stage. Its operands come from the forwarding mux (`ex_alu_a`, `ex_alu_b`).

### 6.7 `branch_unit.sv` — branch decision (31 lines)

**What:** Three comparators (equal, signed-less-than, unsigned-less-than) cover six branch types: BEQ/BNE/BLT/BGE/BLTU/BGEU. The output is simply "taken?".  
**Where:** EX stage; the PC mux takes the branch based on this decision. (Prediction = not taken; if taken, the pipe is cleared — Chapter 11.)

### 6.8 `control_unit.sv` — brain (146 lines)

**What:** Purely combinational. opcode+funct3+funct7 → all datapath selectors (reg\_we, alu\_a/b\_sel, alu\_op, imm\_type, mem\_we/re, wb\_sel, is\_branch/jal/jalr, br\_type, is\_mdiv).  
**Operation:** Safe defaults = NOP (no side effects). Then a `case` based on opcode:

* R-type → reg\_we=1, alu\_op from funct3/funct7; if M-ext, then is\_mdiv=1.
* I-type → imm=I, alu\_b=IMM, alu\_op from funct3.
* LOAD → mem\_re=1, wb\_sel=WB\_MEM. STORE → mem\_we=1, imm=S.
* BRANCH → is\_branch=1, alu\_a=PC, imm=B. JAL → wb\_sel=WB\_PC4, is\_jal. JALR → wb\_sel=WB\_PC4, is\_jalr.
* LUI → alu\_op=PASSB, imm=U. AUIPC → alu\_a=PC, imm=U.
* FENCE/SYSTEM → NOP (CSR/trap later).

**Why it matters:** The single decision point for "what an instruction does". If there is an error here, that instruction class will behave completely incorrectly.

### 6.9 `mul_div.sv` — M extension (138 lines)

**What:** Multiplication (combinational) + division (multi-cycle FSM).

* **MUL family:** combinational; mapped to **DSP48** blocks in synthesis. MUL (lower 32), MULH/MULHSU/MULHU (upper 32, sign combinations).
* **DIV/REM:** 32-cycle restoring (subtraction with remainder) division FSM. The pipeline stalls while running (`busy_o`). In signed operations, the absolute values of the operands are taken, and the result sign is corrected with `neg_quot/neg_rem`.

**Fine point (also written in the comments):** In the 33-bit trial-subtraction, the zero is added **from the left (high bit)** (adding it to the LSB doubles the value, which is wrong). `busy_o` must also be high in the START cycle, otherwise the PC advances before the FSM leaves IDLE.  
**Where:** EX. If `is_mdiv`, the result comes to `ex_result_final` from mul\_div; hazard\_unit holds the pipeline during division.  
**Warning (software):** 64-bit integer division (`__divdi3`) requires a `.rodata` table (`__clz_tab`) in libc; since it could not be read from the data port in our Harvard memory, it broke the raycaster → **avoid 64-bit division**, use 32-bit hardware DIVU (Chapter 19).

### 6.10 `forwarding_unit.sv` — forwarding decision (43 lines)

**What:** Do the source registers (rs1/rs2) of the instruction in EX conflict with the destination (rd) of an instruction in later stages (MEM, WB)? If they conflict, **forward** from that stage (do not wait for the register file).  
**Output:** `fwd_a`/`fwd_b` ∈ {FWD\_NONE, FWD\_FROM\_M (from MEM), FWD\_FROM\_W (from WB)}. MEM has priority (fresher). Cycle by cycle in Chapter 12.  
**Where:** EX operand muxes (`rv32im_core_pipelined.sv`).

### 6.11 `hazard_unit.sv` — stall decision (68 lines)

**What:** Stalls the pipeline in two situations where forwarding is not enough:

1.  **Load-use:** There is a LOAD in EX, and the instruction in ID wants its rd → the load value is not ready until the end of MEM → **1-cycle stall** (freeze PC+IF/ID, inject NOP bubble to ID/EX). In the next round, the load is in WB/MEM, and forwarding handles it.
2.  **MDIV (multi-cycle division):** While division is stalled in EX, PC+IF/ID **and** ID/EX **are held** (MDIV must stay in EX, otherwise its result is lost); EX/MEM is bubbled (so it doesn't overwrite a partial result).

**Where:** Its outputs are connected to the stall/bubble signals in `rv32im_core_pipelined.sv`.

---

## 7\. Memory system — cache, AXI, DDR

Processor is 50 MHz; DDR is slow and requires "bursts". There is a cache in between.

### 7.1 cache.sv — D-cache and I-cache

#### Why a cache is needed
The processor wants to access memory in every clock cycle and get the result in the same cycle; this is possible in single-cycle BRAM because BRAM is small and fast. DOOM, however, does not fit in BRAM, so the program and data are in DDR. DDR is challenging in two ways. First, it is high-latency: after a read command is issued, it can take dozens of cycles for the first data to arrive (row activation + CAS latency). Second, it is efficient in bulk (burst) access, not individual accesses. The processor's expectation of "instant data every cycle" conflicts with DDR's "slow and bulk" nature. The cache is the intermediate layer that closes this gap: it keeps frequently accessed data right next to the processor in a small local memory that can be read in a single cycle, and fetches data it doesn't have from DDR in bulk.

#### Why it works: locality
The reason caches work is that programs access memory in predictable ways rather than randomly. There are two types of locality. Temporal locality: a recently accessed address is highly likely to be accessed again soon (loop variables, frequently called functions). Spatial locality: when an address is accessed, its neighbors are highly likely to be accessed soon as well (consecutive instructions, array elements). The cache utilizes both: when fetching a piece of data, it fetches not just that word but the entire block (line) containing it, so subsequent accesses to neighbors become free; and it stores the fetched line for a while, making repeated accesses fast.

#### Basic concepts
**Line:** the smallest unit of exchange between cache and DDR; 32 bytes = 8 words in this design. The cache never fetches just a single byte or a single word, always a line. **Hit:** the requested address is in the cache, data is provided in a single cycle, DDR is not accessed. **Miss:** address not present, the line must be fetched from DDR, during which the processor stalls. **Write-back:** writes are initially committed only to the cache line and the line is marked "dirty"; it is written to DDR only when the line is evicted — producing far less DDR traffic than a write-through policy, which writes every single write to DDR instantly. **Write-allocate:** if a write miss occurs, the line is first fetched from DDR, and then the write is performed in the cache. **Valid:** whether the line contains meaningful data; all lines are invalid at reset. **Tag:** upper address bits that distinguish different addresses that map to the same cache location.

#### Geometry and address decomposition
The default structure is 256 lines × 32 bytes = 8 KB. A 32-bit address is split into four fields for the cache. The lowest 2 bits select the byte within a word. The next 3 bits select which of the 8 words in the line it is. The next 8 bits determine which of the 256 lines it maps to (index). The remaining upper 19 bits are the tag. The lowest 5 bits together give the "offset within the line". Code correspondence: byte_off = address[1:0], word_sel = address[4:2], index = address[12:5], tag = address[31:13].

Concrete example: Address 0x10000044. The lower 5 bits are 0x04, which is the start of the second word of the line. The index field (8 bits from the 5th bit) is 2 for this address, meaning it maps to line number 2 out of 256. The remaining upper bits are the tag. When another address mapping to the same index (2) arrives, say an address exactly 8 KB away, only the tag distinguishes the two.

#### Direct-mapped placement
 This cache is direct-mapped: each address can map to only a single line based on its index; there is no choice. This keeps the hardware simple and fast (a single comparison is enough) but has a cost: two frequently used addresses mapping to the same index can constantly evict each other (conflict miss). Multi-way (set-associative) caches mitigate this; direct-mapped was chosen here for simplicity.

#### Storage
The cache consists of four arrays, each 256 lines long. `data_arr` holds the data of the lines (each line is 256 bits = 8 words). `tag_arr` holds the tag of each line, `valid_arr` holds whether it is valid, and `dirty_arr` holds whether it is dirty (modified, waiting to be written back).

#### Hit decision and read
A hit occurs if the line selected by the address index is valid and its tag matches the address tag. On a hit, the word selected by `word_sel` is taken from the line (`sel_word`). It is then processed according to the load type (funct3): if it's a full word (LW), the whole word; if it's a byte (LB/LBU), the byte selected by `byte_off`, sign- or zero-extended; if it's a half-word (LH/LHU), the relevant 16 bits. That is, the job of selecting the requested piece out of the wide line coming from DDR is done here, in the read derivation of the cache.

#### Write on hit
On a write hit, the new data is committed directly to the line, but the write might not cover the entire word: a byte write (SB) changes 1 byte, a half-word (SH) changes 2 bytes. A byte-mask (strobe) is generated for this, and only the masked bytes are updated, while the rest keep their old values (`merge_word`). The written line is marked dirty because the content in the cache is now different from that in DDR and must be written back someday.

#### Miss: finite state machine (FSM)
On a miss, the cache enters a multi-cycle operation and stalls the processor during this time. A four-state machine manages this: S_IDLE, S_WB, S_FILL_GAP, S_FILL. Normally, the cache is in S_IDLE and services hits in a single cycle. On a miss, the requested address is first latched. Then there are two paths: if the current line at that index is dirty, that dirty victim line must be written back to DDR before being overwritten, so the machine switches to S_WB and writes the line; if the victim is clean (or once writing is done), the machine switches to S_FILL to fetch the new line. The intermediate S_FILL_GAP state drops the memory request for one cycle between a write-back and a subsequent fetch; this is required for the memory side to distinguish a write from a read. In S_FILL, the requested line comes from DDR, is written to `data_arr`, its tag and valid bit are set, and its dirty bit is cleared. The machine returns to S_IDLE. In the next cycle, the same address is now a hit.

#### Why req_addr is latched
Fetching takes multiple cycles; during this time, the processor's live address line can change — a branch or jump can shift the subsequent address. If fetching used the live address, the address shifting mid-operation would cause the wrong line to be filled; this leads to instruction corruption, especially in the I-cache. Therefore, the address is frozen at the moment of the miss (`req_addr`), and fetching/write-back uses only this frozen address (`fill_index`, `fill_tag`).

#### Interface with DDR and processor stall
The cache communicates with DDR via a simple line-granular interface: a request flag, write/read direction, line-aligned address, outgoing line, incoming line, and a "transfer done" signal. What connects this interface to actual DDR is the burst master (7.2) and its translation to AXI (7.6). The critical point for the processor: on hits, the ready signal (`c_ready`) is high, and the processor never stalls; throughout a miss, `c_ready` is low, which connects to the processor's memory-ready input and freezes the entire pipeline (`mem_stall`). Thus, a cache miss is the primary cause of multi-cycle pipeline stalls.

#### Cycle-by-cycle story of a miss
The processor wants to read the word at 0x10000040, and that line is not in the cache. In the first cycle, the cache calculates the index, compares the tag, and finds no match; no hit, `c_ready` drops, the processor stalls, and the request address is latched. If the current line at that index is clean, the machine goes directly to fetching. That line is requested from the burst master; the burst master sends the address out via the AR channel, DDR opens the row and streams the eight words (0x10000040–0x1000005F) consecutively. The first word arrives dozens of cycles later (row activation + CAS latency), the remaining seven stream quickly. All eight are gathered and written to the cache line, and the tag and valid bits are set. The machine returns to idle; in the next cycle, 0x10000040 is now a hit, the word is provided in a single cycle, and the processor continues. Important result: once this expensive work is done, subsequent accesses to 0x10000044, 0x10000048, and other addresses in the same line become free hits — this is the payoff of locality.

#### I-cache vs D-cache: same module, two instances
This module is instantiated twice in the DOOM SoC. One is used as a read-only I-cache for instructions (write paths are never triggered). The other is used as a read-write D-cache for data. They are separate physical copies; each has its own data/tag/valid/dirty arrays and is independent of the other. That is, "I-cache and D-cache" are not two separate blocks inside a single file, but two separate instances of a single generic cache module.

### 7.2 `axi_burst_master.sv` — line ↔ AXI burst (157 lines)

**What:** Translates a cache line (8 words) into an **AXI4 INCR burst**. Fill = read burst; write-back = write burst. 32-bit data, 1 word per beat.  
**Robustness:** Beat capture in the Read FSM is gated with `rvalid`, and in the Write FSM with `wready` → resilient to stalls on the actual bus. `wstrb=4'b1111` (full word, line write-back). `m_done` pulses on the last beat of the line; the cache waits for it.

### 7.3 `axi_slave_ddr.sv` — sim DDR (163 lines)

**What:** Non-synthesizable. Mimics the actual PS DDR in **simulation**: services AXI INCR bursts into a memory array (`mem[]`) with a few cycles of read latency. Can be preloaded with `$readmemh`.  
**Where:** `tb_doom_sim.sv`, `tb_ddr_core.sv` etc. — boardless DOOM uses this (Sections 16–14).  
**Addressing:** Word index = `addr[ADDR_W+1:2]` (masks the address to MEM\_WORDS). In the DOOM sim, `MEM_WORDS=1<<26` (256 MB) is chosen so that WAD@0x18000000 (word 0x2000000), program@0, and stack@16M **do not conflict** (if chosen too small, aliasing occurs — Section 16).

### 7.4 `ddr_model.sv` — simple line-granular model (86 lines)

**What:** A simpler, AXI-less, line-granular memory model for the `cache.sv` unit test (`tb_cache.sv`).

### 7.5 `imem.sv` / `dmem.sv` — BRAM memories

**What:** Single-cycle, on-chip BRAM memories. `imem` is read-only (instruction), `dmem` is byte-strobed (LB/LH/LW/SB/SH/SW). Early demos (blink, UART, raycaster) worked with these — no AXI/DDR. This is the basis for porting to a pure FPGA board (Basys/Tang) (Section 18). Small programs fit in BRAM; DOOM does not.

### 7.6 AXI bus — where it goes, what it does

**What is AXI:** The standard bus protocol by ARM/Xilinx. It connects our "masters" (the two burst masters — one for I-cache, one for D-cache) to the "slave" (PS DDR). Everything is based on a **valid/ready handshake**: the sender asserts "valid", the receiver asserts "ready/received"; when both are high in the same cycle, the transfer occurs. This allows a slow side to make the other wait.

**Where it goes (path):** Visible with purple arrows in `system_datapath.svg`. Each burst master exposes a full AXI master interface → **SmartConnect** (merges two masters into a single stream) → the PS's **S_AXI_HP0** port (where the PL/PS boundary is crossed) → path inside the PS → **DDR controller** → DDR chip. Thus, the AXI bus starts inside our PL, crosses from the FPGA fabric to the PS at S_AXI_HP, and goes all the way to the DDR controller inside the PS. **Where it does not go:** The HP port only accesses memory (DDR/OCM); it does not access the PS's peripheral registers (USB, UART…). This is the reason why the USB can only be used via an ARM bridge.

**Five channels (the heart of AXI):** AXI divides a transaction into five independent channels; each is a separate valid/ready handshake:

| Channel | Direction | What it carries | Job |
|---|---|---|---|
| **AR** (read address) | master→slave | address, beat count, beat size, burst type | "read this much from this address" |
| **R** (read data) | slave→master | data, last-beat flag | read data flows back beat by beat |
| **AW** (write address) | master→slave | address, beat count, beat size | "write this much to this address" |
| **W** (write data) | master→slave | data, byte-mask, last beat | data to be written goes beat by beat |
| **B** (write response) | slave→master | response | "write completed" confirmation |

Read and write are independent; address and data are also on separate channels, allowing a subsequent address to be sent while the previous data is still flowing (pipelining).

**Read flow (a cache fill):** The burst master puts the line address on the AR channel, specifies the beat count as 8 and the beat size as 4 bytes (32 bits), and raises the "valid" flag. SmartConnect routes this to the HP port; the DDR controller fetches the data; data comes back beat by beat on the R channel, and on the eighth beat, the "last" flag lights up; the burst master gathers the eight words and fills the cache line.

**Write flow (returning a dirty line):** The line address goes out on the AW channel; data beats flow on the W channel, each with a byte-mask indicating which bytes are valid, and a "last" flag on the final beat; once done, the slave returns a "completed" response via the B channel.

**In our design:** The burst master drives AR/R channels for a fill, and AW/W/B channels for a write-back. The cache simply tells it "read a line" or "write a line"; the burst master translates this into the channel traffic described above. The program, heap, stack, and WAD are all in the 0x1xxxxxxx DDR range and go to DDR via AXI. MMIO addresses (LED/framebuffer/palette, 0x9/0xA/0xB) do not use AXI — the `mmio_bridge` inside the PL services them directly; they never go out to AXI/DDR. In terms of width, our master is 32-bit, while S_AXI_HP is 64-bit; the SmartConnect in between handles the conversion. The burst type is incrementing address (INCR).

---

## 8\. Video pipeline (framebuffer → HDMI)

DOOM's internal screen is **320×200, 8-bit palette index + 256 color palette** — **exactly identical** to our hardware. Therefore, `DG_DrawFrame` is mostly just a copy + palette load.

### 8.1 `video_fb.sv` (78 lines) and its parts

**What:** Dual-clock 320×200 8-bit framebuffer + 256-entry palette + scan timing. The processor side (50 MHz) writes; the video side (25 MHz pixel clock) reads. Inside:

* `framebuffer.sv` — pixel memory (BRAM), write port (from `mmio_bridge`) + read port (scanning).
* `palette.sv` — 256×24-bit color table; pixel index → RGB.
* `video_timing.sv` — VGA/HDMI timing (hsync/vsync/de, visible area counters).

**Output:** RGB + sync → `rgb2dvi` (Digilent IP, TMDS serializer) → **HDMI**.  
**Note:** `video_fb_wrap.v` — Verilog wrapper since Vivado BD module reference does not accept SystemVerilog.

### 8.2 Why dual-clock (CDC)?

The CPU writes the framebuffer at 50 MHz, but the screen must be scanned at a constant 25 MHz pixel rate (HDMI timing). Two separate clocks → framebuffer BRAM is dual-port (one port per clock). The palette and sync are also arranged accordingly.

---

## 9\. Software side — toolchain, linker, libc

### 9.1 Build chain (`scripts/build_doom.sh`)

1.  **Compile:** each `.c` → `.o` with `riscv-none-elf-gcc -march=rv32im -mabi=ilp32 -Os`.
2.  **Link:** all `.o` + libc + our libc parts → a single `.elf`, where the **linker script** (`linker_doom.ld`) determines the placement.
3.  **objcopy:** `.elf` → pure binary `software/doom.bin` (loaded into DDR at 0x10000000). The toolchain PATH must be configured BEFORE building: `export PATH=$HOME/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$PATH`.

### 9.2 `software/linker_doom.ld` — memory map

Answers the question "Where are the program parts in memory?":

```
0x10000000  .text (code) .rodata (constants) .data (initialized) .bss (zero-initialized)
_end        start of heap (malloc grows upward)
0x14000000  __stack_top (stack grows downward) — ~64 MB heap in between
0x18000000  DOOM1.WAD (loaded separately)
```

`ENTRY(_start)`; symbols like `__stack_top`, `__global_pointer$`, `__bss_start/end`, `_end` are here.

### 9.3 `software/crt0_doom.S` — startup code

The processor starts from `_start` at 0x10000000 upon reset: (1) `sp = __stack_top`, (2) `gp = __global_pointer$`, (3) clear `.bss`, (4) `call main`. **It is not a bootloader** — it loads nothing; the program is already waiting in DDR (XSCT put it there). It only sets up the C environment.

### 9.4 libc (C library)

* **newlib** — standard C (string, memcpy, malloc infrastructure). The right choice for bare-metal RISC-V; verified (sprintf worked in sim). Crashes thought to be "broken newlib" were actually a stale-hex pitfall.
* `**software/doom_syscalls.c**` — bare-metal "OS" layer. newlib's `fopen/fread` calls descend to `_open/_read/_lseek/_fstat` here. Only the **.WAD** file is considered to "exist" (others return -1); WAD is read from DDR (0x18000000, size 4196020) via `memcpy`. `_sbrk` expands the heap; `_write` → mailbox.
* `**software/malloc_simple.c**` — simple "bump" allocator (malloc/calloc/free). DOOM manages its own zone allocator on top of a single large malloc block → this is sufficient. (free is a no-op.)
* `**software/printf_simple.c**` — compact printf/sprintf. `**%.3d**` **(precision) was added** — it was missing; since the `HU_Init` font lump name produces `STCFN%.3d`, without precision it was outputting "STCFN%.3d not found" and throwing an `I_Error` (Chapter 19).
* `**software/dbg_hex.c**` — debug tool: a tiny font that prints a u32 onto the HDMI framebuffer with hex digits (`dbg_show_hex`). Added because JTAG was unreliable, so we read by writing to the screen. (Can be stripped for presentation.)

---

# PART III — HOW EVERYTHING CONNECTS TOGETHER

## 10\. End-to-end — how everything connects together

So far we have seen the modules individually; we know what each does on its own. This section connects them together. Instead of abstract box descriptions, we will trace exactly what circulates in the system — a command, a load, a store, a pixel write — from start to finish, and see which module passes the baton to which module by name at each step. For the full on-chip picture, see `system_datapath.svg`; for the processor's internal datapath, see `datapath.svg`.

### 10.1 From power-on to first instruction
When the board is powered on, the PS (ARM side) wakes up first: it initializes the clock sources and the DDR controller, then releases the reset on the PL (FPGA fabric). When reset is lifted, the Program Counter (Section 6.2) is cleared and sets up at the boot vector; in the DOOM configuration, this is 0x10000000 (Section 3.4). This is the very first step the system takes: the PC provides this address to the `imem` port, which is connected to the I-cache (Section 7). Since the first instruction is not yet in the cache, this first fetch is a miss; the cache fetches the line from DDR (the flow is identical to 10.3), and after that, instructions begin to flow.

### 10.2 Lifecycle of an instruction and handoff of stages
An instruction passes through five stages, and each stage hands off what it produces to the next stage via a pipeline register; "connection" is precisely these handoffs. In the IF stage, the PC gives the address to the I-cache, the cache returns the instruction, and the instruction is written to the IF/ID register. In the ID stage, the decoder (Section 6.3) splits the instruction into its fields, the `regfile` (Section 6.5) reads the two source registers, and the `immgen` (Section 6.4) generates the constant; all of these are placed into the ID/EX register. In the EX stage, the ALU (Section 6.6) does the math, the `branch_unit` (Section 6.7) makes the decision in branches, and `mul_div` (Section 6.9) steps in during multiply/divide; the result moves to the EX/MEM register. The critical connection here is forwarding: the result of a previous instruction that has not yet been written to the `regfile` is routed directly to the ALU input instead of the stale value in ID/EX (Chapter 12). In the MEM stage, if the instruction is a load/store, the D-cache (Section 7) is touched; otherwise, the ALU result is carried over as is; the output is written to the MEM/WB register. In the WB stage, the result is written back to the `regfile`, and the lifecycle of the instruction ends. That is, the "connection" inside the processor consists of four pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB) and the forwarding paths stretched between them; how they are wired in code is in Chapter 11.

### 10.3 A load, end to end, through the memory hierarchy
Now let us track a single `lw` instruction sequentially through every module it touches, assuming it is a miss. In the EX stage, the ALU adds the base register and the offset to calculate the data address. In the MEM stage, this address is given to the D-cache. If the address is not in the cache, the cache drops the ready signal (`c_ready`); since this signal is connected to the processor's memory-ready input, the entire pipeline stalls (`mem_stall`, Section 11.1). The cache latches the request address (Section 7) and tells the burst master (Section 7.2) to "bring this line". The burst master puts the address on AXI's AR channel and raises the valid flag (Section 7.6); the request reaches the PS's S_AXI_HP port via SmartConnect, and from there to the DDR controller; the controller translates the address into row/column/bank and opens the DDR. Data flows back beat by beat on the R channel — the first word dozens of cycles later, the rest quickly — and the burst master gathers the eight words to fill the cache line. Once the line is filled, the same address is now a hit: the requested word is selected, processed according to the load type (LB/LH/LW), and placed in the MEM/WB register. `c_ready` rises again, the stall lifts, the pipeline continues flowing, and the value is written to the `regfile` in WB. For a single load, the chain goes: ALU → D-cache → burst master → AXI (AR/R) → SmartConnect → S_AXI_HP → DDR controller → DDR and back.

### 10.4 A store and return of a dirty line to DDR
A `sw` hit is much quieter: data is written directly to the cache line (using a byte-strobe in partial writes, Section 7), the line is marked dirty, and the job is done — DDR is not accessed at that moment. Writing to DDR happens only in the future when that line's slot is required for another address. When that moment comes, the cache must write back the dirty victim before fetching the new line: the FSM first switches to S_WB, the burst master writes the line to DDR via AXI's AW/W channels and waits for a "completed" response from the B channel; then it switches to S_FILL and fetches the new line. Thus, a store reaching DDR depends on the moment that line is evicted, not the moment the store executes — this is the essence of the write-back policy, and it is precisely this delay that reduces DDR traffic.

### 10.5 A framebuffer write reaching the screen
When DOOM draws a frame, every pixel is actually a store to memory — but this store goes to the framebuffer, not DDR. The difference emerges in address decoding. The processor's data port is split into two based on address bits in SoC top (Section 14): addresses starting with 0x1 go to the D-cache/DDR path, while those starting with 0x9/0xA/0xB go to the `mmio_bridge` (Section 13.3). The framebuffer is in the 0xA range, so the pixel write never goes out to AXI/DDR; the `mmio_bridge` writes it to the framebuffer memory inside `video_fb` (Section 8). Independently, the scan side reads from this memory at a constant 25 MHz pixel rate, translates each pixel index to an actual color via the palette memory (written from 0xB), the timing generator adds synchronization signals, and the result is given to `rgb2dvi` to exit from HDMI as TMDS. The processor writing at 50 MHz while the screen reads at 25 MHz means two separate clocks; the safe crossing between these two clocks (CDC) is handled inside the video block (Section 8). The chain: store → address decode → mmio_bridge → framebuffer → (scanning) → palette → timing → rgb2dvi → HDMI.

### 10.6 SoC top: where the physical connection is established
The three paths above (instruction, data, pixel) are wired together in a single place in code, the SoC top module (`rv32im_doom_core.sv`, Section 14). This module instantiates the core and connects its `imem/dmem` ports to the modules: the `imem` port connects to the I-cache instance, and the `dmem` port goes first to an address-bit decoder, and from there either to the D-cache (0x1 → DDR) or to the `mmio_bridge` (0x9/0xA/0xB). The two burst masters behind the two caches expose two AXI master interfaces outwardly; these merge at the top level in SmartConnect and connect to the PS's S_AXI_HP port. That is, the abstract paths we described in 10.2-10.5 turn into concrete signal connections here — which wire goes where is seen in this file.

### 10.7 Module-to-module baton pass — at a glance
Placing the four chains side by side reveals the entire system. Instruction fetch chain: PC → I-cache → (on miss burst master → AXI → DDR) → IF/ID → decoder/regfile/immgen → ID/EX → ALU → EX/MEM → MEM/WB → regfile. Data load chain: ALU (address) → D-cache → (on miss burst master → AXI AR/R → DDR) → MEM/WB → regfile. Store/write-back chain: ALU (address) → D-cache (mark dirty) → (on eviction burst master → AXI AW/W/B → DDR). Video chain: store → address decode → mmio_bridge → framebuffer → palette → timing → rgb2dvi → HDMI. These four chains are the complete map of how the modules we explained individually form a system altogether.

---

## 11 Assembling the pipeline (rv32im\_core\_pipelined.sv)

`rtl/top/rv32im_core_pipelined.sv` (505 lines) is the **main director** of the processor: it connects all core modules, holds pipeline registers, and manages stalls/flushes/forwarding. Data path:

```
IF:   pc → imem_addr → imem_data (instruction)        [pc.sv + I-cache/imem]
ID:   decoder + control_unit + immgen + regfile       → to idex_* register
EX:   forwarding mux → alu / mul_div / branch_unit    → to exmem_* register
MEM:  exmem_alu_result → D-cache / mmio_bridge        → to memwb_* register
WB:   mem_wb_data → regfile write
```

### 11.1 Back-pressure: `imem_ready` / `dmem_ready`

Memory is always ready in single-cycle BRAM. But data is delayed on a **miss** in cache+DDR. Therefore, the core accepts two "ready" signals:

* `dmem_ready_i` low → **mem\_stall**: **the entire pipeline freezes** until the load/store in MEM is serviced (`mem_stall = exmem_valid && (mem_re||mem_we) && !dmem_ready_i`). PC, IF/ID, ID/EX, EX/MEM are held.
* `imem_ready_i` low → **if\_stall**: instruction could not be fetched → a NOP bubble is injected into IF/ID (if branch not taken). PC is frozen with `(if_stall && !ex_branch_taken)`.

Thanks to this, the **same core** works behind both single-cycle BRAM and multi-cycle cache+DDR — only the ready signals are driven differently. (An early attempt to "freeze the entire pipe on if\_stall" broke M2b; correctness: NOP bubble up front + branch protection.)

### 11.2 Branch resolution and flush

Prediction = **not taken** (predict-not-taken). The branch is resolved in EX (`branch_unit`). If taken, the 2 wrong instructions coming from behind (in IF/ID and ID stages) are **flushed** (`flush_ifid = flush_idex = ex_branch_taken`). JAL/JALR also steer in EX. 2-cycle penalty (on a taken branch).

### 11.3 Write-back mux (`mem_wb_data`)

Selects what will be written to rd in WB (`exmem_wb_sel`):

```
WB_ALU → exmem_alu_result   (normal operation; mdiv result from here too)
WB_MEM → dmem_rdata_i       (load: data read from memory)
WB_PC4 → exmem_pc_plus4     (JAL/JALR return address)
WB_IMM → exmem_alu_result   (LUI; already passed via PASSB)
```

**This mux is critical:** This is the *actual* result of the instruction in the MEM stage. Forwarding must use this (not the address) — Chapter 12.

### 11.4 Important fixes (in this file)

* **FWD\_FROM\_M →** `**mem_wb_data**` (it used to be `exmem_alu_result`). **Data** instead of address is forwarded for a load, and **pc+4** instead of the jump target is forwarded for JAL/JALR.
* **MEM/WB is HELD during mem\_stall** (it used to be bubbled). Details in Sections 12.4 and 15 — this was the main bug breaking DOOM.

---

## 12\. Forwarding and hazard — cycle cycle

The most critical and most frequently asked part of the pipeline. With clock-cycle tables.

### 12.1 Without forwarding (incorrect result)

```
            cyc1   cyc2   cyc3   cyc4   cyc5
add x5,..   IF     ID     EX     MEM    WB
sub x8,x5,..       IF     ID     EX     MEM
```

`add` writes x5 in **cyc5 (WB)**; `sub` wants x5 in **cyc4 (EX)** → register file still has old x5 → incorrect. Forwarding is mandatory.

### 12.2 With forwarding (correct, no stall)

The result of `add` is ready at the **end of cyc3** (in the EX/MEM register). In cyc4, `sub` is in EX, and `add` is in MEM → `forwarding_unit` sees "sub.rs1 == MEM.rd" → **FWD\_FROM\_M**: `mem_wb_data` is fed to the ALU input (the register file is not awaited). If the distance were 2 (add in WB at cyc) → **FWD\_FROM\_W**.

### 12.3 Load-use: forwarding is not enough, stall 1 cycle

```
            cyc1   cyc2   cyc3   cyc4   cyc5   cyc6
lw  x5,0(x6) IF     ID     EX     MEM* WB
add x8,x5,..        IF     ID     ----   EX     MEM
```

`lw` result is ready at the end of MEM (cyc4); if `add` came to EX in cyc4, there was no data. `hazard_unit` makes it wait 1 cycle → in cyc5, add is in EX, lw is in WB → correct with FWD\_FROM\_W. The compiler usually avoids this loss by putting independent instructions in between.

### 12.4 Preserving write-back forwarding during multi-cycle stalls

In a multi-cycle memory access like a cache miss, the entire pipeline freezes (`mem_stall`). This freeze introduces a subtle requirement for forwarding. Consider this pattern: a producer instruction (e.g., a load), a memory operation in between that hits a cache miss (and thus causes a stall), and a consumer instruction using the producer's result.

```
            cycA           cycA+1 ... (throughout stall)
producer    WB             (about to exit WB)
mid op      MEM* (miss)    MEM* (waiting for DDR)
consumer    EX (frozen)    EX (frozen, source is producer's rd)
```

* In cycA, the consumer forwards the producer from WB (FWD\_FROM\_W) — correct value.
* If the MEM/WB register is **bubbled** (cleared) during the stall, the producer drops out of WB one cycle later; it is no longer in the MEM or WB stage. The frozen consumer loses its forwarding source and reverts to the **stale operand** it captured in ID → incorrect result.

**Design rule:** The MEM/WB register is **held, not bubbled** during `mem_stall`. Thus, the producer remains in WB, and FWD\_FROM\_W remains valid throughout the stall. Holding is safe because rewriting the same value to the register file is idempotent (harmless); as soon as the stall ends, the operation in MEM moves to WB normally. The MEM/WB `always_ff` block in `rv32im_core_pipelined.sv` implements this rule.

This is a timing/placement-sensitive hazard: it only appears with the "producer → cache-missing intermediate operation → consumer" pattern, with exact cycle alignment. Since a cache miss depends on the memory layout of the program, it is typically triggered under a sufficiently complex load (e.g., DOOM); simple test programs usually do not produce this pattern.

---

## 13\. Address map, MMIO, bitstream vs program

### 13.1 What is an address? A NUMBER over wires; the DECODER gives its meaning

When the CPU executes a load/store, it puts a 32-bit number on the address wires. That number alone is not a physical thing; the **address decoder** gives it meaning: "which device is this range?". In `rv32im_doom_core.sv`:

```
is_ddr = (d_addr[31:28] == 4'h1)   // 0x1xxxxxxx → DDR (cache→AXI→HP)
else   → mmio_bridge                // 0x9/0xA/0xB → LED/cycle/switch/framebuffer/palette
```

* **DDR window** (0x1…): **Fixed** by the Zynq PS (DDR = 0x00000000–0x3FFFFFFF). We settled inside it (program 0x10000000, stack 0x14000000, WAD 0x18000000). This is what "conforming" means.
* **MMIO addresses** (0x9/A/B): **Completely ours** — decoded by the decoder inside the PL, they never see the DDR.

### 13.2 "DDR address" is actually the AXI slave address of the DDR controller

General rule: **every address = (which slave) + (offset within that slave)**. The decoder/address-map selects "which slave"; that slave's controller translates the offset into physical hardware (DDR row/column/bank, or register). "DDR is at this address" = "the decoder sends this range to the slave port of the DDR controller". On Zynq, the PS made this assignment; on your own board, **you** give it with the MIG (DDR controller IP).

### 13.3 `mmio_bridge.sv` (152 lines)

**What:** Connects non-DDR addresses to PL peripherals:

```
0x90000000  LED (4 bits)         0x90000004  cycle counter
0x90000008  switches             0x90000020  UART/mailbox (printf)
0xA0000000  framebuffer write    0xB0000000  palette write (256 colors RGB)
```

The framebuffer is **not in DDR** — it is a separate BRAM (`video_fb`) inside the PL. When DOOM writes to `0xA0000000`, the decoder says "not DDR" → `mmio_bridge` → framebuffer BRAM. This is **memory-mapped I/O**: peripherals appear in the same address space as if they were memory, but they are separate hardware; the decoder distributes the traffic.

### 13.4 "We embed two codes" — actually 3 separate things, in different places

| Loaded Item | What | WHERE | Command | When power is lost |
| --- | --- | --- | --- | --- |
| `doom_sys_wrapper.bit` | **HARDWARE** (CPU+peripheral circuit) | **FPGA fabric (PL)** | `fpga -file` (JTAG) | erased |
| `software/doom.bin` | **SOFTWARE** (machine code) | **DDR** @0x10000000 | `dow -data` (JTAG) | erased |
| `doom/doom1.wad` | game **data** | **DDR** @0x18000000 | `dow -data` (JTAG) | erased |

* The bitstream goes **inside** the FPGA fabric; the CPU **comes into existence** with it.
* `doom.bin` + WAD are in **DDR** (external memory); the CPU accesses them via the PS's HP port. **They are not inside the FPGA fabric.**
* **Durations:** RTL changed → recompile bitstream (~25 mins). C code changed → only `doom.bin` (~10 secs); the bitstream remains the same.
* The PS (ARM) **does not execute** the code; `ps7_init` only turns on the clocks + DDR controller.

### 13.5 Why USB cannot be directly accessed (summary)

The USB OTG port is connected to the **PS (ARM)** (USB controller 0xE0002000), **not the PL**. Our PL master connects to the PS via S\_AXI\_HP, which **only goes to memory** (DDR/OCM) — not peripheral registers. (S\_AXI\_GP accesses more broadly, but running USB requires a massive USB host stack in RV32IM.) Result: Bridging the ARM for USB (ARM reads USB → shares in DDR → RV32IM reads) is heavy. Board buttons (bitstream, ~10 mins) or UART from PC (medium effort) are much easier for immediate gameplay (Chapter 18).

---

## 14\. SoC top modules (top)

Modules under `rtl/top/` that wrap the core with different memory/IO arrangements. The evolutionary steps of the project are visible here too.

* `**rv32im_core.sv**` — single-cycle core (educational foundation). One instruction per clock; long combinational path.
* `**rv32im_core_pipelined.sv**` — 5-stage pipeline (Chapter 11). The actual processor.
* `**rv32im_fpga_top.sv**` — pipelined core + BRAM imem/dmem + MMIO (LED, cycle counter) + Zybo pins. First FPGA bring-up (LED demo). No PS/DDR.
* `**rv32im_ddr_core.sv**` — core + D-cache + `axi_burst_master` → AXI DDR (the DDR-access step).
* `**rv32im_iddr_core.sv**` — code is also fetched from DDR (I-cache fetch). "Run code from DDR" (M2b).
* `**rv32im_unified_core.sv**` — separate I and D AXI masters, both DDR. "Unified memory" (M3).
* `**rv32im_doom_core.sv**` — DOOM SoC core (149 lines): CPU(RESET\_VEC=0x10000000) + I-cache + D-cache + 2 burst masters + `mmio_bridge` (LED/cycle/switch/framebuffer/palette). DOOM uses this.
* `**rv32im_soc_top.sv**` **/** `**rv32im_video_top.sv**` **/** `**hdmi_test_top.sv**` — SoC/video bring-up tops.
* `***_wrap.v**` (doom, ddr, iddr, video\_fb) — **Verilog** wrappers. Mandatory because Vivado Block Design (BD) module reference rejects SystemVerilog.

The TCL building the bitstream: `**scripts/build_doom_soc.tcl**` — BD: PS7 (S\_AXI\_HP, FCLK0=50, FCLK1=125) + `clk_wiz` (25+125 MHz) + `rgb2dvi` + doom core + `video_fb` + SmartConnect + `xlconcat`. (At one point, a D→HP0, I→HP1 separation was added; harmless but wasn't necessary — the bug was forwarding, not the shared bus.)

---

## 15\. DOOM port — file by file and call chain

DOOM source: `doom/doomgeneric/doomgeneric/`. "doomgeneric" is a platform-independent DOOM port; we wrote the **platform layer** + adapted a few init parts for bare-metal.

### 15.1 Files we wrote/modified

* `**doom_main.c**` — `main()`. First gray palette + test pattern + LED=1 (bring-up proof), then `doomgeneric_Create("doom","-iwad","DOOM1.WAD")`, then `for(;;) doomgeneric_Tick()`.
* `**doomgeneric_rv32im.c**` — platform layer (where it connects to hardware):
    * `DG_DrawFrame()` — copies the 320×200 screen to the framebuffer (0xA); loads to 0xB if palette changed; LED heartbeat on every frame.
    * `DG_GetKey()` — 4 switches → LEFT/RIGHT/UP/FIRE (edge-triggered).
    * `DG_GetTicksMs()` — time from the cycle counter (0x90000004) (CPU 50 MHz).
* `**d_main.c**` — `D_DoomMain()` init sequence. Omitted what doesn't exist in bare-metal (file scanning, network). LED stage markers: **8**\=M\_Init **9**\=R\_Init **A**\=P\_Init **B**\=S\_Init **C**\=Net **D**\=HU\_Init **E**\=ST\_Init **F**\=game loop.
* `**w_file_stdc.c**` — WAD file layer: `memcpy` from DDR (0x18000000) instead of `fopen`.
* `**i_system.c**` — zone size (`DEFAULT_RAM`); `I_Error` capture (writes the error message to DDR).
* `**z_zone.c**`**,** `**w_wad.c**`**,** `**r_data.c**` — debug probes (bug hunting; temporary).

### 15.2 Call chain (while DOOM is running)

```
crt0_doom.S (_start)
 └─ main()                         [doom_main.c]   palette+pattern+LED=1
     └─ doomgeneric_Create()        [doomgeneric.c]
         └─ D_DoomMain()            [d_main.c]   init: V_Init, W_Init, R_Init, P_Init,
              │                                   S_Init, HU_Init, ST_Init
              │   lump read: W_CacheLumpName → W_ReadLump → W_StdC_Read  [w_wad.c, w_file_stdc.c]
              │                → memcpy from WAD in DDR (0x18000000)
              │   memory: Z_Malloc  [z_zone.c] → malloc_simple.c (single large block)
              └─ D_DoomLoop()
     └─ for(;;) doomgeneric_Tick()  [doomgeneric.c]
         └─ D_Display() → DG_DrawFrame()  [doomgeneric_rv32im.c]
              └─ framebuffer(0xA) + palette(0xB) → video_fb → HDMI
```

### 15.3 Demo mode vs live gameplay

At startup, DOOM plays its own **demo** (attract mode) — looks like gameplay but the user does not control it. To enter live gameplay: `autostart=true` + `startepisode=1; startmap=1` in `d_main.c` → menu/demo are skipped, directly entering **E1M1**; switches control the player. (4 switches = turn-left/turn-right/walk/fire; no "use/open door" — comes if board buttons are added, Chapter 18.)

---

# PART IV — SETUP, VERIFICATION, PORTABILITY

## 16\. Build and run from scratch

### 16.1 Environment (in every terminal)

```
export PATH=$HOME/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$PATH   # RISC-V compiler
source $HOME/oss-cad-suite/environment                          # Verilator
source /tools/Xilinx/Vivado/2022.2/settings64.sh                # for bitstream
source /tools/Xilinx/Vitis/2022.2/settings64.sh                 # for board loading
```

### 16.2 Compile software

```
cd ~/Desktop/RV32IM-from-scratch
bash scripts/build_doom.sh        # → software/doom.bin
```

### 16.3 Run BOARDLESS (Verilator — simulates actual RTL on PC)

```
# 1) generate sim memory image (doom.bin + WAD → hex; WAD word offset 0x2000000):
python3 - <<'EOF'
def words(p):
    d=open(p,'rb').read()
    if len(d)%4: d+=b'\x00'*(4-len(d)%4)
    return [int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)]
prog=words('software/doom.bin'); wad=words('doom/doom1.wad')
open('sim/sim_doom_d.hex','w').write('@0\n'+'\n'.join('%08x'%w for w in prog)+'\n@2000000\n'+'\n'.join('%08x'%w for w in wad)+'\n')
open('sim/sim_doom_i.hex','w').write('@0\n'+'\n'.join('%08x'%w for w in prog)+'\n')
EOF
# 2) compile (Verilator):
verilator --binary --top-module tb_doom_sim -o Vtb_doom_sim --Mdir sim/obj_dir_doomsim --Wno-fatal -O3 \
  -Irtl/core -Irtl/memory -Irtl/peripherals -Irtl/top \
  rtl/core/rv32im_pkg.sv rtl/core/alu.sv rtl/core/branch_unit.sv rtl/core/control_unit.sv \
  rtl/core/decoder.sv rtl/core/forwarding_unit.sv rtl/core/hazard_unit.sv rtl/core/immgen.sv \
  rtl/core/mul_div.sv rtl/core/pc.sv rtl/core/regfile.sv \
  rtl/memory/cache.sv rtl/memory/mmio_bridge.sv rtl/peripherals/axi_burst_master.sv rtl/memory/axi_slave_ddr.sv \
  rtl/top/rv32im_core_pipelined.sv rtl/top/rv32im_doom_core.sv tb/integration/tb_doom_sim.sv
# 3) run → sim/doom_frame.ppm + LED stage output (LED F = game loop):
./sim/obj_dir_doomsim/Vtb_doom_sim
# 4) convert PPM to PNG: (ImageMagick) convert sim/doom_frame.ppm sim/doom_frame.png
```

This path is deterministic, ~20 secs/run, full visibility. The bug was found with this (Section 17–15).

### 16.4 Run ON BOARD (Zybo Z7-20)

```
# If RTL changed, rebuild the bitstream (~25 mins):
cd vivado_doom && vivado -mode batch -source ../scripts/build_doom_soc.tcl && cd ..
# load doom.bin + WAD to DDR + boot:
xsct scripts/run_doom.tcl
```

`run_doom.tcl`: connect → ARM target → `ps7_init` (open DDR) → `dow doom.bin 0x10000000` → `dow doom1.wad 0x18000000` → `fpga -file <bit>` (program PL, boot). Plug in HDMI; switches are input. **Important:** To see RTL changes on the board, **bitstream is mandatory** (the old bitstream on the board contains the old CPU). If JTAG clogs up after many reloads, **power-cycle** the board.

---

## 17\. Verification (Spike, cache TB, DOOM sim)

Catch hardware errors with a **reference**, not by "guessing". This was the project's most powerful tool.

### 17.1 Spike co-simulation (CPU accuracy)

The same `program.hex` runs on both **Spike** (golden reference ISA simulator) and RTL (Verilator); `scripts/compare_traces.py` compares the final 32-register states. Single-cycle and pipelined cores were verified **bit-exact** (`make verify`, `make verify-pipe`).

### 17.2 Unit testbenches (`tb/integration/`)

* `tb_rv32im_core.sv`, `tb_rv32im_core_pipelined.sv` — core.
* `tb_cache.sv` — cache hit/miss/eviction/write-back; write-miss + evict-rewrite tests were added (proved the cache logic was correct → bug was not in cache).
* `tb_axi_burst.sv`, `tb_ddr_core.sv`, `tb_iddr_core.sv`, `tb_unified_core.sv` — memory path.
* `tb_video_*.sv` — video.

### 17.3 `tb_doom_sim.sv` — full DOOM, boardless (key tool)

Actual `rv32im_doom_core` + two `axi_slave_ddr` (I=4 MB code, D=256 MB so WAD@word 0x2000000, program@0, stack@16M do not conflict). Preload with `sim/sim_doom_{i,d}.hex` (regenerate on every `doom.bin` recompile). Captures FB(0xA)/palette(0xB) writes → PPM; prints LED stages. Contains a **golden-memory checker**: records every store to a mirror model, and compares what the cache returns on every load with the mirror → first mismatch = **address + instruction PC** of the corruption. This definitively separated "is memory broken or forwarding" (memory was clean → forwarding). ~20 secs/run, ~2M cycles/s; DOOM reaches the game loop (LED F) at ~31M cycles.

**Methodology lesson:** A TB simulating actual RTL + a golden reference (Spike or mirror memory model) = the most powerful way to find bugs deterministically at the instruction level. The board is a blind flight beside it (unreliable JTAG, power-cycle, slow).

---

## 18\. Portability (Basys 3, Tang Nano, USB, bootloader)

**The core is board-agnostic.** Board-specific parts are **memory + I/O**. Modular design:

| Component | Zybo/SoC (DOOM) | Pure FPGA (Basys/Tang) |
| --- | --- | --- |
| CPU | rv32im\_core\_pipelined | **same** |
| Memory | cache → AXI → PS HP → DDR | direct **BRAM** (small) or **your own SDRAM controller** |
| I/O | mmio\_bridge | mmio\_bridge (pins adapted to that board) |
| PS/ARM | ps7\_init | **none, not required** |
| Loading | XSCT `dow` (to DDR) | embed in BRAM (bitstream) or UART/SD bootloader |

### 18.1 Basys 3 (Artix-7, no PS, no DDR)

* VGA is **easier** than HDMI (no TMDS; wire RGB+sync from `video_timing.sv` to VGA pins).
* BRAM ~225 KB → small programs (raycaster) fit; **DOOM does not fit** (requires ~37 MB). External memory is mandatory.

### 18.2 Tang Nano 20K (Gowin, 8 MB SDRAM/PSRAM, SD slot)

* DOOM **is possible** but tight: **64 Mbit = 8 MB**. Keep the zone at ~6 MB + **stream the WAD from the SD card** (do not load into RAM) → 0.5(program)+6(zone) \< 8 MB fits.
* Required: **SDRAM controller** (counterpart to DDR controller; you select the address) + **SD reader** (turn `w_file_stdc` into SD reading) + **Gowin TMDS HDMI** + loading path. Xilinx IPs (PS7, SmartConnect, rgb2dvi, clk\_wiz) **cannot be ported** — replaced by Gowin/open-source counterparts.
* Toolchain: Gowin EDA or open source (Yosys + nextpnr-apicula). SV mostly synthesizes.

### 18.3 What is a bootloader (concept)

Three separate things: **bitstream** (hardware) / **bootloader** (small loader) / **application** (.bin). `.bin` = application (DOOM), NOT boot. Bootloader = the first small program to run; it copies the large application from external memory (SD/flash) to RAM and jumps to it. There is **no** bootloader on Zybo (XSCT loads it); on a pure FPGA (if no PS), a small program is embedded in BRAM or a bootloader is written.

### 18.4 USB keyboard/mouse

USB OTG is connected to the **PS** (controller 0xE0002000), not the PL. Our PL master only reaches **memory** via HP. An ARM bridge for USB (ARM USB host stack → share in DDR → RV32IM reads) is required — takes days. **Board buttons** (bitstream, ~10 mins) or **UART from PC** (medium effort) are much easier to play immediately.

---

# APPENDICES

## 19\. Hazards, constraints, and design choices

This section gathers the hazards and architectural constraints that must be explicitly addressed in the design, along with their solutions, in a single place. All are mentioned in their respective module sections; they are summarized here with their rationales.

**Preserving write-back forwarding during a stall.** Throughout a multi-cycle memory stall, the MEM/WB register is held (not bubbled); otherwise, the producer in the WB stage drops out one cycle later and a frozen consumer loses its forwarding source. Details and cycle diagram: Section 12.4.

**Correct selection of the forwarding source.** The value forwarded to EX from the MEM stage must be the **actual** result of that instruction: data read from memory for a load (not the address), `pc+4` for JAL/JALR (not the jump target), and the ALU result for others. The single signal providing this is `mem_wb_data` (Section 11.3); the forwarding mux uses this.

**Load-use dependency.** Since the result of a load is ready at the end of MEM, forwarding is not enough for the immediately following dependent instruction; the `hazard_unit` injects a 1-cycle stall (Section 12.3).

**Multi-cycle division.** DIV/REM takes 32 cycles; throughout this duration, PC, IF/ID, and ID/EX are held, and EX/MEM is bubbled (Section 6.11).

**Instruction-fetch back-pressure.** Instead of freezing the entire pipe when the instruction memory is not ready (`imem_ready=0`), a NOP bubble is injected into IF/ID and the PC is managed with branch protection (`if_stall && !ex_branch_taken`); thus, the fetch stall does not collide with branch steering (Section 11.1).

**Latch of the cache fill address.** Upon a miss, the request address (`req_addr`) is latched, and the fill is performed from this latched address. If live `c_addr` were used, a JAL/branch steering while the fill is ongoing could shift the address and fill the wrong line (instruction corruption, especially in the I-cache). Therefore, the address is latched (Section 7.1).

**Harvard memory and 64-bit division.** Instruction and data ports are separate in the BRAM-based core; libc's 64-bit integer division (`__divdi3`) accesses a `.rodata` table (`__clz_tab`), which may not be readable from the data port. For this reason, 64-bit division is avoided in software; 32-bit hardware DIV/DIVU is used (Section 6.9).

**printf precision requirement.** DOOM generates font lump names with format strings containing precision, such as `STCFN%.3d`; therefore, `printf_simple.c` supports minimum-digit/zero-padding for integers and maximum-length precision for `%s` (Section 9.4).

**Verification principle.** Hazards in this class typically emerge in core+cache+pipeline interactions in a timing/placement-sensitive manner; meeting static timing (WNS>0) does not preclude a logical race. Therefore, verification relies on simulating the actual RTL deterministically and comparing it at the instruction level with a golden reference (Spike or mirror memory model) (Chapter 17).

---

## 20\. Glossary

* **RTL:** Register-Transfer Level — code describing the hardware (SystemVerilog). Synthesized onto the FPGA.
* **FPGA:** Field-Programmable Gate Array — reprogrammable logic fabric. A bitstream converts it into a circuit.
* **PS / PL:** Processing System (ARM+hard peripherals) / Programmable Logic (synthesized circuit) of Zynq.
* **Bitstream:** The binary that configures the FPGA (the circuit itself).
* **Pipeline:** Dividing instructions into stages like an assembly line (IF/ID/EX/MEM/WB).
* **Hazard:** A situation where the result of an instruction is needed early in the pipeline (data) or control ambiguity (branch).
* **Forwarding (bypass):** Routing a result directly within the pipe before it is written to the register.
* **Stall / bubble:** Freezing the pipeline for a round / inserting an empty operation (NOP).
* **Cache / hit / miss / write-back:** Fast local memory / data exists / does not exist / writing a dirty line back to DDR.
* **AXI:** ARM/Xilinx bus protocol (address + data channels, burst).
* **Burst:** Successive multi-beat data with a single address (for cache lines).
* **MMIO:** Memory-Mapped I/O — peripherals appear as memory addresses.
* **DDR / SDRAM / PSRAM:** Types of external dynamic RAM (requires a controller, with refresh).
* **WAD:** DOOM's data file (graphics/audio/maps).
* **Zone allocator:** DOOM's own memory manager (on top of a single large block).
* **newlib / crt0 / linker script:** Bare-metal C library / startup code / layout definition.

---

## 21\. Instruction summary (cheat sheet)

```
# --- environment ---
export PATH=$HOME/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$PATH
source $HOME/oss-cad-suite/environment
source /tools/Xilinx/Vivado/2022.2/settings64.sh
source /tools/Xilinx/Vitis/2022.2/settings64.sh

# --- verify CPU (Spike) ---
cd scripts && make verify && make verify-pipe

# --- compile software ---
bash scripts/build_doom.sh                       # → software/doom.bin

# --- boardless DOOM (sim) ---  (The 4 steps in Section 16.3: hex → verilator → run → PNG)
./sim/obj_dir_doomsim/Vtb_doom_sim               # → sim/doom_frame.ppm, LED stages

# --- DOOM on board (Zybo) ---
cd vivado_doom && vivado -mode batch -source ../scripts/build_doom_soc.tcl && cd ..   # bitstream (~25 mins)
xsct scripts/run_doom.tcl                         # load to DDR + boot

# --- DOOM screen frame ---
#   sim/doom_frame.png
```

**LED stage map:** 8=M\_Init 9=R\_Init A=P\_Init B=S\_Init C=Net D=HU\_Init E=ST\_Init **F=game loop**.

---

*For the colored, browsable datapath diagrams, see `docs/datapath.html` (processor internals) and `docs/system_datapath.html` (the SoC).*
