# run_ddr.tcl  -  bring up the PS DDR controller, then program the PL bitstream
#
# S_AXI_HP reaches DRAM only once the PS DDR controller is initialised (clocks /
# DDR PHY), which ps7_init does. Vivado Hardware Manager programs the PL but does
# NOT run ps7_init — this XSCT script does both, in order (PS first so the DDR is
# alive before the RV32IM issues its first burst).
#
# Usage (Vitis/XSCT must be sourced):
#   source /tools/Xilinx/Vitis/2022.2/settings64.sh
#   xsct /home/dev-emru/Desktop/RV32IM-from-scratch/scripts/run_ddr.tcl
#
# Watch the Zybo LEDs:  0b0101 = PASS (CPU reached DDR),  0b1010 = FAIL,
#                       0000 = hung (DDR/AXI never responded).

set here [file normalize [file dirname [info script]]]
set root [file normalize $here/..]
set proj $root/vivado_ddr/rv32im_ddr

set bit  [lindex [glob -nocomplain $proj/rv32im_ddr.runs/impl_1/ddr_sys_wrapper.bit] 0]
set init [lindex [glob -nocomplain \
              $proj/*.gen/sources_1/bd/ddr_sys/ip/*ps7*/ps7_init.tcl \
              $proj/*.srcs/sources_1/bd/ddr_sys/ip/*ps7*/ps7_init.tcl] 0]

puts "bitstream : $bit"
puts "ps7_init  : $init"
if {$bit eq "" || $init eq ""} { error "Could not locate .bit or ps7_init.tcl — build first." }

connect

# 1) PS first: clocks + DDR controller/PHY up before any AXI burst hits S_AXI_HP.
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
rst -processor
source $init
ps7_init
ps7_post_config

# 2) configure the PL — the RV32IM starts with the DDR already alive.
puts "Programming PL ..."
fpga -file $bit

puts "==============================================="
puts " Done. Watch the LEDs:"
puts "   0101 = PASS  (RV32IM reached PS DDR over AXI bursts)"
puts "   1010 = FAIL  (sum mismatch)"
puts "   0000 = hung  (no DDR response)"
puts "==============================================="
