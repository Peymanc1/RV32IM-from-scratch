# Makefile  -  Verilator + Spike co-sim
#
# Targets:
#   make            -> build & run single-cycle sim with current program.hex
#   make sim-pipe   -> same but pipelined
#   make wave       -> sim, then point at the VCD
#   make verify     -> rebuild test_rv32im.S, run on Spike + RTL, diff regs
#   make verify-pipe-> verify against pipelined RTL
#   make build-spike-> build Spike from source (one-time)
#   make clean

PROJ_ROOT := ..
RTL_DIR   := $(PROJ_ROOT)/rtl
TB_DIR    := $(PROJ_ROOT)/tb
SIM_DIR   := $(PROJ_ROOT)/sim
SW_DIR    := $(PROJ_ROOT)/software

# Package must come first.
SV_SRCS := \
	$(RTL_DIR)/core/rv32im_pkg.sv \
	$(RTL_DIR)/core/pc.sv \
	$(RTL_DIR)/core/decoder.sv \
	$(RTL_DIR)/core/regfile.sv \
	$(RTL_DIR)/core/immgen.sv \
	$(RTL_DIR)/core/alu.sv \
	$(RTL_DIR)/core/mul_div.sv \
	$(RTL_DIR)/core/branch_unit.sv \
	$(RTL_DIR)/core/control_unit.sv \
	$(RTL_DIR)/memory/imem.sv \
	$(RTL_DIR)/memory/dmem.sv \
	$(RTL_DIR)/top/rv32im_core.sv \
	$(TB_DIR)/integration/tb_rv32im_core.sv

SV_SRCS_PIPE := \
	$(RTL_DIR)/core/rv32im_pkg.sv \
	$(RTL_DIR)/core/pc.sv \
	$(RTL_DIR)/core/decoder.sv \
	$(RTL_DIR)/core/regfile.sv \
	$(RTL_DIR)/core/immgen.sv \
	$(RTL_DIR)/core/alu.sv \
	$(RTL_DIR)/core/mul_div.sv \
	$(RTL_DIR)/core/branch_unit.sv \
	$(RTL_DIR)/core/control_unit.sv \
	$(RTL_DIR)/core/hazard_unit.sv \
	$(RTL_DIR)/core/forwarding_unit.sv \
	$(RTL_DIR)/memory/imem.sv \
	$(RTL_DIR)/memory/dmem.sv \
	$(RTL_DIR)/top/rv32im_core_pipelined.sv \
	$(TB_DIR)/integration/tb_rv32im_core_pipelined.sv

# AXI-Lite master unit test (no CPU, no program.hex needed).
SV_SRCS_AXI := \
	$(RTL_DIR)/core/rv32im_pkg.sv \
	$(RTL_DIR)/peripherals/axi_lite_master.sv \
	$(TB_DIR)/integration/tb_axi_lite_master.sv

# Cache + DDR-model unit test (no CPU, no program.hex needed).
SV_SRCS_CACHE := \
	$(RTL_DIR)/core/rv32im_pkg.sv \
	$(RTL_DIR)/memory/cache.sv \
	$(RTL_DIR)/memory/ddr_model.sv \
	$(TB_DIR)/integration/tb_cache.sv

# AXI burst master + AXI DDR slave through the cache (no CPU).
SV_SRCS_BURST := \
	$(RTL_DIR)/core/rv32im_pkg.sv \
	$(RTL_DIR)/memory/cache.sv \
	$(RTL_DIR)/peripherals/axi_burst_master.sv \
	$(RTL_DIR)/memory/axi_slave_ddr.sv \
	$(TB_DIR)/integration/tb_axi_burst.sv

# Full-stack core + cache + DDR integration (needs program.hex).
SV_SRCS_DDR := \
	$(RTL_DIR)/core/rv32im_pkg.sv \
	$(RTL_DIR)/core/pc.sv \
	$(RTL_DIR)/core/decoder.sv \
	$(RTL_DIR)/core/regfile.sv \
	$(RTL_DIR)/core/immgen.sv \
	$(RTL_DIR)/core/alu.sv \
	$(RTL_DIR)/core/mul_div.sv \
	$(RTL_DIR)/core/branch_unit.sv \
	$(RTL_DIR)/core/control_unit.sv \
	$(RTL_DIR)/core/hazard_unit.sv \
	$(RTL_DIR)/core/forwarding_unit.sv \
	$(RTL_DIR)/memory/imem.sv \
	$(RTL_DIR)/memory/dmem.sv \
	$(RTL_DIR)/memory/cache.sv \
	$(RTL_DIR)/peripherals/axi_burst_master.sv \
	$(RTL_DIR)/memory/axi_slave_ddr.sv \
	$(RTL_DIR)/top/rv32im_core_pipelined.sv \
	$(TB_DIR)/integration/tb_core_ddr.sv

SV_SRCS_DDRCORE := \
	$(RTL_DIR)/core/rv32im_pkg.sv $(RTL_DIR)/core/pc.sv $(RTL_DIR)/core/decoder.sv \
	$(RTL_DIR)/core/regfile.sv $(RTL_DIR)/core/immgen.sv $(RTL_DIR)/core/alu.sv \
	$(RTL_DIR)/core/mul_div.sv $(RTL_DIR)/core/branch_unit.sv $(RTL_DIR)/core/control_unit.sv \
	$(RTL_DIR)/core/hazard_unit.sv $(RTL_DIR)/core/forwarding_unit.sv \
	$(RTL_DIR)/memory/imem.sv $(RTL_DIR)/memory/dmem.sv $(RTL_DIR)/memory/cache.sv \
	$(RTL_DIR)/memory/mmio_bridge.sv $(RTL_DIR)/peripherals/axi_burst_master.sv \
	$(RTL_DIR)/memory/axi_slave_ddr.sv \
	$(RTL_DIR)/top/rv32im_core_pipelined.sv $(RTL_DIR)/top/rv32im_ddr_core.sv \
	$(TB_DIR)/integration/tb_ddr_core.sv

SV_SRCS_IDDR := \
	$(RTL_DIR)/core/rv32im_pkg.sv $(RTL_DIR)/core/pc.sv $(RTL_DIR)/core/decoder.sv \
	$(RTL_DIR)/core/regfile.sv $(RTL_DIR)/core/immgen.sv $(RTL_DIR)/core/alu.sv \
	$(RTL_DIR)/core/mul_div.sv $(RTL_DIR)/core/branch_unit.sv $(RTL_DIR)/core/control_unit.sv \
	$(RTL_DIR)/core/hazard_unit.sv $(RTL_DIR)/core/forwarding_unit.sv \
	$(RTL_DIR)/memory/imem.sv $(RTL_DIR)/memory/dmem.sv $(RTL_DIR)/memory/cache.sv \
	$(RTL_DIR)/memory/mmio_bridge.sv $(RTL_DIR)/peripherals/axi_burst_master.sv \
	$(RTL_DIR)/memory/axi_slave_ddr.sv \
	$(RTL_DIR)/top/rv32im_core_pipelined.sv $(RTL_DIR)/top/rv32im_iddr_core.sv \
	$(TB_DIR)/integration/tb_iddr_core.sv

SV_SRCS_UNIFIED := \
	$(RTL_DIR)/core/rv32im_pkg.sv $(RTL_DIR)/core/pc.sv $(RTL_DIR)/core/decoder.sv \
	$(RTL_DIR)/core/regfile.sv $(RTL_DIR)/core/immgen.sv $(RTL_DIR)/core/alu.sv \
	$(RTL_DIR)/core/mul_div.sv $(RTL_DIR)/core/branch_unit.sv $(RTL_DIR)/core/control_unit.sv \
	$(RTL_DIR)/core/hazard_unit.sv $(RTL_DIR)/core/forwarding_unit.sv \
	$(RTL_DIR)/memory/cache.sv $(RTL_DIR)/peripherals/axi_burst_master.sv \
	$(RTL_DIR)/memory/axi_slave_ddr.sv \
	$(RTL_DIR)/top/rv32im_core_pipelined.sv $(RTL_DIR)/top/rv32im_unified_core.sv \
	$(TB_DIR)/integration/tb_unified_core.sv

SV_SRCS_VIDEO := \
	$(RTL_DIR)/video/video_timing.sv \
	$(TB_DIR)/integration/tb_video_timing.sv

SV_SRCS_PATTERN := \
	$(RTL_DIR)/video/video_timing.sv \
	$(RTL_DIR)/video/test_pattern.sv \
	$(TB_DIR)/integration/tb_video_pattern.sv

SV_SRCS_FB := \
	$(RTL_DIR)/video/video_timing.sv \
	$(RTL_DIR)/video/framebuffer.sv \
	$(RTL_DIR)/video/palette.sv \
	$(RTL_DIR)/video/video_fb.sv \
	$(TB_DIR)/integration/tb_video_fb.sv

SV_SRCS_RAYCAST := \
	$(RTL_DIR)/core/rv32im_pkg.sv $(RTL_DIR)/core/pc.sv $(RTL_DIR)/core/decoder.sv \
	$(RTL_DIR)/core/regfile.sv $(RTL_DIR)/core/immgen.sv $(RTL_DIR)/core/alu.sv \
	$(RTL_DIR)/core/mul_div.sv $(RTL_DIR)/core/branch_unit.sv $(RTL_DIR)/core/control_unit.sv \
	$(RTL_DIR)/core/hazard_unit.sv $(RTL_DIR)/core/forwarding_unit.sv \
	$(RTL_DIR)/memory/imem.sv $(RTL_DIR)/memory/dmem.sv $(RTL_DIR)/memory/mmio_bridge.sv \
	$(RTL_DIR)/peripherals/axi_lite_master.sv \
	$(RTL_DIR)/top/rv32im_core_pipelined.sv $(RTL_DIR)/top/rv32im_fpga_top.sv \
	$(TB_DIR)/integration/tb_raycast.sv

TOP        := tb_rv32im_core
TOP_PIPE   := tb_rv32im_core_pipelined
TOP_AXI    := tb_axi_lite_master
TOP_CACHE  := tb_cache
TOP_BURST  := tb_axi_burst
TOP_DDR    := tb_core_ddr
TOP_DDRCORE := tb_ddr_core
TOP_IDDR   := tb_iddr_core
TOP_UNI    := tb_unified_core
TOP_VIDEO  := tb_video_timing
TOP_PAT    := tb_video_pattern
TOP_RAY    := tb_raycast
TOP_FB     := tb_video_fb
OBJDIR     := $(SIM_DIR)/obj_dir
OBJDIR_P   := $(SIM_DIR)/obj_dir_pipe
OBJDIR_A   := $(SIM_DIR)/obj_dir_axi
OBJDIR_C   := $(SIM_DIR)/obj_dir_cache
OBJDIR_B   := $(SIM_DIR)/obj_dir_burst
OBJDIR_D   := $(SIM_DIR)/obj_dir_ddr
OBJDIR_DC  := $(SIM_DIR)/obj_dir_ddrcore
OBJDIR_ID  := $(SIM_DIR)/obj_dir_iddr
OBJDIR_UNI := $(SIM_DIR)/obj_dir_unified
OBJDIR_V   := $(SIM_DIR)/obj_dir_video
OBJDIR_PAT := $(SIM_DIR)/obj_dir_pattern
OBJDIR_RAY := $(SIM_DIR)/obj_dir_raycast
OBJDIR_FB  := $(SIM_DIR)/obj_dir_fb
BIN        := $(OBJDIR)/V$(TOP)
BIN_PIPE   := $(OBJDIR_P)/V$(TOP_PIPE)
BIN_AXI    := $(OBJDIR_A)/V$(TOP_AXI)
BIN_CACHE  := $(OBJDIR_C)/V$(TOP_CACHE)
BIN_BURST  := $(OBJDIR_B)/V$(TOP_BURST)
BIN_DDR    := $(OBJDIR_D)/V$(TOP_DDR)
BIN_DDRCORE := $(OBJDIR_DC)/V$(TOP_DDRCORE)
BIN_IDDR   := $(OBJDIR_ID)/V$(TOP_IDDR)
BIN_UNI    := $(OBJDIR_UNI)/V$(TOP_UNI)
BIN_VIDEO  := $(OBJDIR_V)/V$(TOP_VIDEO)
BIN_PAT    := $(OBJDIR_PAT)/V$(TOP_PAT)
BIN_RAY    := $(OBJDIR_RAY)/V$(TOP_RAY)
BIN_FB     := $(OBJDIR_FB)/V$(TOP_FB)

# Need a modern g++ for the C++20 coroutine bits Verilator emits with --timing.
# Exporting CXX so the sub-make Verilator spawns picks it up too — otherwise
# verilated.mk falls back to whatever 'g++' resolves to on this system.
CXX ?= g++-10
export CXX

# Two-step build instead of --binary, so we keep control of CXX:
#   1) verilator --cc --exe --main  -> C++ + Vtop.mk
#   2) make -C obj_dir -f Vtop.mk CXX=$(CXX)  -> compile with our toolchain
VERILATOR_FLAGS = --cc --exe --main \
                  --trace \
                  --timing \
                  -CFLAGS "-std=c++20 -fcoroutines" \
                  -Wall \
                  -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                  -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                  -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                  --top-module $(TOP) \
                  -Mdir $(OBJDIR) \
                  -o V$(TOP)

VERILATOR_FLAGS_PIPE = --cc --exe --main \
                       --trace \
                       --timing \
                       -CFLAGS "-std=c++20 -fcoroutines" \
                       -Wall \
                       -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                       -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                       -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                       --top-module $(TOP_PIPE) \
                       -Mdir $(OBJDIR_P) \
                       -o V$(TOP_PIPE)

VERILATOR_FLAGS_AXI = --cc --exe --main \
                      --trace \
                      --timing \
                      -CFLAGS "-std=c++20 -fcoroutines" \
                      -Wall \
                      -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                      -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                      -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                      --top-module $(TOP_AXI) \
                      -Mdir $(OBJDIR_A) \
                      -o V$(TOP_AXI)

VERILATOR_FLAGS_CACHE = --cc --exe --main \
                        --trace \
                        --timing \
                        -CFLAGS "-std=c++20 -fcoroutines" \
                        -Wall \
                        -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                        -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                        -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                        --top-module $(TOP_CACHE) \
                        -Mdir $(OBJDIR_C) \
                        -o V$(TOP_CACHE)

VERILATOR_FLAGS_BURST = --cc --exe --main \
                        --trace --timing -CFLAGS "-std=c++20 -fcoroutines" -Wall \
                        -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                        -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                        -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                        --top-module $(TOP_BURST) -Mdir $(OBJDIR_B) -o V$(TOP_BURST)

VERILATOR_FLAGS_DDR = --cc --exe --main \
                      --trace \
                      --timing \
                      -CFLAGS "-std=c++20 -fcoroutines" \
                      -Wall \
                      -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                      -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                      -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                      --top-module $(TOP_DDR) \
                      -Mdir $(OBJDIR_D) \
                      -o V$(TOP_DDR)

VERILATOR_FLAGS_DDRCORE = --cc --exe --main --trace --timing \
                      -CFLAGS "-std=c++20 -fcoroutines" -Wall \
                      -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                      -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                      -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET -Wno-PINMISSING \
                      -Wno-PINCONNECTEMPTY -Wno-IMPLICITSTATIC -Wno-PROCASSINIT \
                      --top-module $(TOP_DDRCORE) -Mdir $(OBJDIR_DC) -o V$(TOP_DDRCORE)

VERILATOR_FLAGS_IDDR = --cc --exe --main --trace --timing \
                      -CFLAGS "-std=c++20 -fcoroutines" -Wall \
                      -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                      -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                      -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET -Wno-PINMISSING \
                      -Wno-PINCONNECTEMPTY -Wno-IMPLICITSTATIC -Wno-PROCASSINIT \
                      --top-module $(TOP_IDDR) -Mdir $(OBJDIR_ID) -o V$(TOP_IDDR)

VERILATOR_FLAGS_UNI = --cc --exe --main --trace --timing \
                      -CFLAGS "-std=c++20 -fcoroutines" -Wall \
                      -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                      -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                      -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET -Wno-PINMISSING \
                      -Wno-PINCONNECTEMPTY -Wno-IMPLICITSTATIC -Wno-PROCASSINIT \
                      --top-module $(TOP_UNI) -Mdir $(OBJDIR_UNI) -o V$(TOP_UNI)

VERILATOR_FLAGS_VIDEO = --cc --exe --main --trace --timing -CFLAGS "-std=c++20 -fcoroutines" -Wall \
                        -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                        -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                        -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                        --top-module $(TOP_VIDEO) -Mdir $(OBJDIR_V) -o V$(TOP_VIDEO)

VERILATOR_FLAGS_PAT = --cc --exe --main --trace --timing -CFLAGS "-std=c++20 -fcoroutines" -Wall \
                      -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                      -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                      -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                      --top-module $(TOP_PAT) -Mdir $(OBJDIR_PAT) -o V$(TOP_PAT)

VERILATOR_FLAGS_RAY = --cc --exe --main --trace --timing -CFLAGS "-std=c++20 -fcoroutines" -Wall \
                      -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                      -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                      -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                      --top-module $(TOP_RAY) -Mdir $(OBJDIR_RAY) -o V$(TOP_RAY)

VERILATOR_FLAGS_FB = --cc --exe --main --trace --timing -CFLAGS "-std=c++20 -fcoroutines" -Wall \
                     -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-WIDTH \
                     -Wno-TIMESCALEMOD -Wno-IMPORTSTAR -Wno-BLKSEQ \
                     -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET \
                     --top-module $(TOP_FB) -Mdir $(OBJDIR_FB) -o V$(TOP_FB)

all: sim

# Single-cycle build.
$(BIN): $(SV_SRCS)
	@mkdir -p $(SIM_DIR)
	@cp $(SW_DIR)/program.hex $(SIM_DIR)/program.hex
	verilator $(VERILATOR_FLAGS) $(SV_SRCS)
	$(MAKE) -C $(OBJDIR) -f V$(TOP).mk CXX=$(CXX) -j

# Run from sim/ so program.hex and waveform end up in the right place.
sim: $(BIN)
	cd $(SIM_DIR) && ./obj_dir/V$(TOP)

# Pipelined build.
$(BIN_PIPE): $(SV_SRCS_PIPE)
	@mkdir -p $(SIM_DIR)
	@cp $(SW_DIR)/program.hex $(SIM_DIR)/program.hex
	verilator $(VERILATOR_FLAGS_PIPE) $(SV_SRCS_PIPE)
	$(MAKE) -C $(OBJDIR_P) -f V$(TOP_PIPE).mk CXX=$(CXX) -j

sim-pipe: $(BIN_PIPE)
	cd $(SIM_DIR) && ./obj_dir_pipe/V$(TOP_PIPE)

# AXI-Lite master unit test.
$(BIN_AXI): $(SV_SRCS_AXI)
	@mkdir -p $(SIM_DIR)
	verilator $(VERILATOR_FLAGS_AXI) $(SV_SRCS_AXI)
	$(MAKE) -C $(OBJDIR_A) -f V$(TOP_AXI).mk CXX=$(CXX) -j

sim-axi: $(BIN_AXI)
	cd $(SIM_DIR) && ./obj_dir_axi/V$(TOP_AXI)

# Cache + DDR-model unit test.
$(BIN_CACHE): $(SV_SRCS_CACHE)
	@mkdir -p $(SIM_DIR)
	verilator $(VERILATOR_FLAGS_CACHE) $(SV_SRCS_CACHE)
	$(MAKE) -C $(OBJDIR_C) -f V$(TOP_CACHE).mk CXX=$(CXX) -j

sim-cache: $(BIN_CACHE)
	cd $(SIM_DIR) && ./obj_dir_cache/V$(TOP_CACHE)

# Cache over AXI burst master + AXI DDR slave.
$(BIN_BURST): $(SV_SRCS_BURST)
	@mkdir -p $(SIM_DIR)
	verilator $(VERILATOR_FLAGS_BURST) $(SV_SRCS_BURST)
	$(MAKE) -C $(OBJDIR_B) -f V$(TOP_BURST).mk CXX=$(CXX) -j

sim-burst: $(BIN_BURST)
	cd $(SIM_DIR) && ./obj_dir_burst/V$(TOP_BURST)

# Full-stack core + cache + DDR integration.
$(BIN_DDR): $(SV_SRCS_DDR)
	@mkdir -p $(SIM_DIR)
	@cp $(SW_DIR)/program.hex $(SIM_DIR)/program.hex
	verilator $(VERILATOR_FLAGS_DDR) $(SV_SRCS_DDR)
	$(MAKE) -C $(OBJDIR_D) -f V$(TOP_DDR).mk CXX=$(CXX) -j

sim-ddr: $(BIN_DDR)
	cd $(SIM_DIR) && ./obj_dir_ddr/V$(TOP_DDR)

# rv32im_ddr_core (the synthesizable BD cell) on the sim DDR slave.
$(BIN_DDRCORE): $(SV_SRCS_DDRCORE)
	@echo "  [verilate] $(TOP_DDRCORE)"
	verilator $(VERILATOR_FLAGS_DDRCORE) $(SV_SRCS_DDRCORE)
	$(MAKE) -C $(OBJDIR_DC) -f V$(TOP_DDRCORE).mk CXX=$(CXX) -j

sim-ddrcore: $(BIN_DDRCORE)
	cp $(SW_DIR)/program.hex $(SIM_DIR)/program.hex 2>/dev/null || true
	cd $(SIM_DIR) && ./obj_dir_ddrcore/V$(TOP_DDRCORE)

# rv32im_iddr_core: CPU fetches & runs its program from DDR (I-cache). M2b.
$(BIN_IDDR): $(SV_SRCS_IDDR)
	@echo "  [verilate] $(TOP_IDDR)"
	verilator $(VERILATOR_FLAGS_IDDR) $(SV_SRCS_IDDR)
	$(MAKE) -C $(OBJDIR_ID) -f V$(TOP_IDDR).mk CXX=$(CXX) -j

sim-iddr: $(BIN_IDDR)
	cp $(SW_DIR)/program.hex $(SIM_DIR)/program.hex 2>/dev/null || true
	cd $(SIM_DIR) && ./obj_dir_iddr/V$(TOP_IDDR)

# rv32im_unified_core: code AND data from DDR (I-cache + D-cache). M3.
$(BIN_UNI): $(SV_SRCS_UNIFIED)
	@echo "  [verilate] $(TOP_UNI)"
	verilator $(VERILATOR_FLAGS_UNI) $(SV_SRCS_UNIFIED)
	$(MAKE) -C $(OBJDIR_UNI) -f V$(TOP_UNI).mk CXX=$(CXX) -j

sim-unified: $(BIN_UNI)
	cp $(SW_DIR)/program.hex $(SIM_DIR)/program.hex 2>/dev/null || true
	cd $(SIM_DIR) && ./obj_dir_unified/V$(TOP_UNI)

# Video timing unit test.
$(BIN_VIDEO): $(SV_SRCS_VIDEO)
	@mkdir -p $(SIM_DIR)
	verilator $(VERILATOR_FLAGS_VIDEO) $(SV_SRCS_VIDEO)
	$(MAKE) -C $(OBJDIR_V) -f V$(TOP_VIDEO).mk CXX=$(CXX) -j

sim-video: $(BIN_VIDEO)
	cd $(SIM_DIR) && ./obj_dir_video/V$(TOP_VIDEO)

$(BIN_PAT): $(SV_SRCS_PATTERN)
	@mkdir -p $(SIM_DIR)
	verilator $(VERILATOR_FLAGS_PAT) $(SV_SRCS_PATTERN)
	$(MAKE) -C $(OBJDIR_PAT) -f V$(TOP_PAT).mk CXX=$(CXX) -j

sim-pattern: $(BIN_PAT)
	cd $(SIM_DIR) && ./obj_dir_pattern/V$(TOP_PAT)

$(BIN_RAY): $(SV_SRCS_RAYCAST)
	@mkdir -p $(SIM_DIR)
	@cp $(SW_DIR)/program.hex $(SIM_DIR)/program.hex
	verilator $(VERILATOR_FLAGS_RAY) $(SV_SRCS_RAYCAST)
	$(MAKE) -C $(OBJDIR_RAY) -f V$(TOP_RAY).mk CXX=$(CXX) -j

sim-raycast: $(BIN_RAY)
	cd $(SIM_DIR) && ./obj_dir_raycast/V$(TOP_RAY)

$(BIN_FB): $(SV_SRCS_FB)
	@mkdir -p $(SIM_DIR)
	verilator $(VERILATOR_FLAGS_FB) $(SV_SRCS_FB)
	$(MAKE) -C $(OBJDIR_FB) -f V$(TOP_FB).mk CXX=$(CXX) -j

sim-fb: $(BIN_FB)
	cd $(SIM_DIR) && ./obj_dir_fb/V$(TOP_FB)

wave: sim
	@echo ""
	@echo "VCD: $(SIM_DIR)/waveform.vcd"
	@echo "Open with: gtkwave $(SIM_DIR)/waveform.vcd &"

wave-pipe: sim-pipe
	@echo ""
	@echo "VCD: $(SIM_DIR)/waveform_pipe.vcd"
	@echo "Open with: gtkwave $(SIM_DIR)/waveform_pipe.vcd &"

verify:
	@chmod +x verify.sh
	./verify.sh single

verify-pipe:
	@chmod +x verify.sh
	./verify.sh pipe

build-spike:
	@chmod +x build_spike.sh
	./build_spike.sh

clean:
	rm -rf $(OBJDIR) $(OBJDIR_P) $(OBJDIR_A) $(OBJDIR_C) $(OBJDIR_B) $(OBJDIR_D) $(OBJDIR_V) $(OBJDIR_PAT) $(OBJDIR_FB) $(SIM_DIR)/*.vcd $(SIM_DIR)/program.hex \
	       $(SIM_DIR)/spike_trace.log $(SIM_DIR)/rtl_output.log \
	       $(SW_DIR)/test_rv32im.elf $(SW_DIR)/test_rv32im.bin \
	       $(SW_DIR)/test_rv32im.dump

.PHONY: all sim sim-pipe sim-axi sim-cache sim-burst sim-ddr sim-ddrcore sim-iddr sim-video sim-pattern sim-fb wave wave-pipe verify verify-pipe build-spike clean
