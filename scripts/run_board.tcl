# run_board.tcl  -  XSCT: program the PL bitstream AND bring up the PS (ps7_init)
#
# The RV32IM (PL) is clocked by the PS FCLK and prints over the PS UART, so the
# PS must be initialised (clocks/MIO/UART) before anything runs. Vivado Hardware
# Manager only programs the PL — it does NOT run ps7_init. This script does both.
#
# Usage (Vitis must be sourced for xsct):
#   source /tools/Xilinx/Vitis/2022.2/settings64.sh
#   xsct /home/dev-emru/Desktop/RV32IM-from-scratch/scripts/run_board.tcl

set here [file normalize [file dirname [info script]]]
set root [file normalize $here/..]
set proj $root/vivado_ps/rv32im_soc

set bit  [lindex [glob -nocomplain $proj/rv32im_soc.runs/impl_1/rv32im_soc_top.bit] 0]
set init [lindex [glob -nocomplain \
              $root/vivado_ps/hw/ps7_init.tcl \
              $proj/*.gen/sources_1/bd/*/ip/*processing_system7*/ps7_init.tcl \
              $proj/*.srcs/sources_1/bd/*/ip/*processing_system7*/ps7_init.tcl] 0]

puts "bitstream : $bit"
puts "ps7_init  : $init"
if {$bit eq "" || $init eq ""} {
    error "Could not locate .bit or ps7_init.tcl — check the paths above."
}

connect

# 1) bring up the PS FIRST (clocks, MIO mux, UART ref clock). Must happen
#    before the PL/CPU starts, otherwise the RV32IM races ahead to its first
#    UART write and stalls forever on an unresponsive S_AXI_GP0.
puts "Bringing up PS (ps7_init) ..."
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
rst -processor
source $init
ps7_init
ps7_post_config

# 2) now configure the PL fabric — CPU starts with the PS already alive
puts "Programming PL ..."
fpga -file $bit

puts "==============================================="
puts " PL programmed + PS initialised."
puts " RV32IM should now be running demo_uart:"
puts "   - LEDs toggle each line"
puts "   - 'Hello from RV32IM!' streams out the UART"
puts " Open a serial terminal: minicom -D /dev/ttyUSB1 -b 115200"
puts "==============================================="
