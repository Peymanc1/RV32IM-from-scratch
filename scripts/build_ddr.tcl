# build_ddr.tcl  -  M1: RV32IM reaches real PS DDR over AXI bursts
#
# Block design = Zynq PS (S_AXI_HP0 slave -> DDR) + SmartConnect + the RV32IM
# DDR core (rv32im_ddr_core: CPU + D-cache + axi_burst_master). The CPU runs
# ddr_hw_test (baked into BRAM IMEM): it writes/reads the cached DDR region
# (0x10000000) through real AXI4 bursts into the PS DDR controller, sums it, and
# shows the verdict on the LEDs (0b0101 = PASS, 0b1010 = FAIL, 0000 = hung).
#
# Everything runs on one clock: PS FCLK_CLK0 (50 MHz). No PL clock pin, no CDC.
# The BD wrapper is the synthesis top; only the LEDs are real PL pins.
#
# Usage:
#   mkdir -p vivado_ddr && cd vivado_ddr
#   vivado -mode batch -source ../scripts/build_ddr.tcl
#
# Then bring up the PS DDR controller + program the bitstream over JTAG:
#   xsct ../scripts/run_ddr.tcl
#
# REQUIREMENTS: Digilent board files at ~/digilent_board_files (Zybo Z7-20 PS
# preset configures the DDR controller — essential for S_AXI_HP to reach DRAM).

set proj_name rv32im_ddr
set part      xc7z020clg400-1
set bd_name   ddr_sys

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize $script_dir/..]

set_param board.repoPaths $env(HOME)/digilent_board_files
create_project $proj_name ./$proj_name -part $part -force

set bp [get_board_parts -quiet *zybo-z7-20:part0:*]
if { [llength $bp] == 0 } {
    error "Zybo Z7-20 board_part not found — check board.repoPaths ($env(HOME)/digilent_board_files)"
}
set_property board_part [lindex $bp 0] [current_project]
puts "Using board_part: [lindex $bp 0]"

# ---------------------------------------------------------------------------
# RTL sources (CPU + cache + burst master + the DDR core)
# ---------------------------------------------------------------------------
add_files -norecurse [glob $root_dir/rtl/core/*.sv]
add_files -norecurse $root_dir/rtl/memory/imem.sv
add_files -norecurse $root_dir/rtl/memory/dmem.sv
add_files -norecurse $root_dir/rtl/memory/cache.sv
add_files -norecurse $root_dir/rtl/memory/mmio_bridge.sv
add_files -norecurse $root_dir/rtl/peripherals/axi_burst_master.sv
add_files -norecurse $root_dir/rtl/top/rv32im_core_pipelined.sv
add_files -norecurse $root_dir/rtl/top/rv32im_ddr_core.sv
add_files -norecurse $root_dir/rtl/top/rv32im_ddr_wrap.v

# program.hex (ddr_hw_test) -> BRAM IMEM init
add_files -norecurse $root_dir/software/program.hex
set_property file_type "Memory Initialization Files" [get_files program.hex]

add_files -fileset constrs_1 -norecurse $root_dir/constraints/zybo_ddr.xdc

# ---------------------------------------------------------------------------
# Block design
# ---------------------------------------------------------------------------
create_bd_design $bd_name

# Zynq PS: board preset (brings up DDR controller), S_AXI_HP0 enabled, one clock.
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config { make_external "FIXED_IO, DDR" apply_board_preset "1" \
              Master "Disable" Slave "Disable" } [get_bd_cells ps7]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
] [get_bd_cells ps7]

# The RV32IM DDR core as a BD module cell (Vivado bundles m_axi_* into an AXI4
# master interface "m_axi" from the port names).
create_bd_cell -type module -reference rv32im_ddr_wrap ddrcore

# SmartConnect: 32-bit master -> 64-bit S_AXI_HP0 (it inserts the width converter)
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells smc]

# Reset
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst0
connect_bd_net [get_bd_pins ps7/FCLK_CLK0]     [get_bd_pins rst0/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst0/ext_reset_in]

# AXI: ddrcore.m_axi -> SmartConnect -> PS S_AXI_HP0
connect_bd_intf_net [get_bd_intf_pins ddrcore/m_axi] [get_bd_intf_pins smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smc/M00_AXI]   [get_bd_intf_pins ps7/S_AXI_HP0]

# One clock everywhere
foreach c { ddrcore/clk smc/aclk ps7/S_AXI_HP0_ACLK } {
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $c]
}
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_pins ddrcore/rst_n]
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_pins smc/aresetn]

# LEDs out to PL pins
make_bd_pins_external [get_bd_pins ddrcore/led]
set_property name led [get_bd_ports led_0]

# Map the master into the PS DDR address space (0x10000000 must land in DDR).
assign_bd_address

validate_bd_design
save_bd_design

# Wrapper = synthesis top
make_wrapper -files [get_files $bd_name.bd] -top
set pdir [get_property DIRECTORY [current_project]]
set wrap_files [glob -nocomplain \
    $pdir/${proj_name}.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.* \
    $pdir/${proj_name}.srcs/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.*]
if { [llength $wrap_files] == 0 } { error "BD wrapper not found after make_wrapper" }
add_files -norecurse $wrap_files
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
# Synthesis + implementation + bitstream
# ---------------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] != "100%" } { error "Synthesis failed." }

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } { error "Implementation failed." }

puts "DONE. Bitstream: ./$proj_name.runs/impl_1/${bd_name}_wrapper.bit"
