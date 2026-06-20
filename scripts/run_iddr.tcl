# run_iddr.tcl  -  M2c: load the program into DDR, then start the RV32IM from DDR
#
# No ARM code: XSCT itself is the loader. Order matters — DDR must hold the
# program BEFORE the RV32IM (PL) comes out of reset and fetches its first
# instruction from 0x10000000:
#   1. ps7_init           -> PS clocks + DDR controller/PHY up
#   2. dow program -> DDR  -> the .text image lands at 0x10000000
#   3. fpga bitstream      -> PL configured; RV32IM boots from (loaded) DDR
#
# Usage:
#   source /tools/Xilinx/Vitis/2022.2/settings64.sh
#   xsct /home/dev-emru/Desktop/RV32IM-from-scratch/scripts/run_iddr.tcl
#
# Program to load: software/iddr_test.bin (built with linker_ddr.ld, .text @
# 0x10000000). Watch the LEDs: 0101 = PASS (ran from DDR), 1010 = FAIL, 0000 = hung.

set here [file normalize [file dirname [info script]]]
set root [file normalize $here/..]
set proj $root/vivado_iddr/rv32im_iddr

set bit  [lindex [glob -nocomplain $proj/rv32im_iddr.runs/impl_1/iddr_sys_wrapper.bit] 0]
set init [lindex [glob -nocomplain \
              $proj/*.gen/sources_1/bd/iddr_sys/ip/*ps7*/ps7_init.tcl \
              $proj/*.srcs/sources_1/bd/iddr_sys/ip/*ps7*/ps7_init.tcl] 0]
set prog $root/software/iddr_test.bin

puts "bitstream : $bit"
puts "ps7_init  : $init"
puts "program   : $prog"
if {$bit eq "" || $init eq "" || ![file exists $prog]} {
    error "Missing .bit / ps7_init.tcl / program .bin — build first."
}

connect

# 1) PS + DDR controller up
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
rst -processor
source $init
ps7_init
ps7_post_config

# 2) write the program image into DDR at 0x10000000 (raw binary)
puts "Loading program into DDR @0x10000000 ..."
dow -data $prog 0x10000000

# 3) configure the PL — RV32IM boots from DDR (already loaded)
puts "Programming PL ..."
fpga -file $bit

puts "==============================================="
puts " RV32IM now running FROM DDR. LEDs:"
puts "   0101 = PASS   1010 = FAIL   0000 = hung"
puts " To run a different program: rebuild its .bin and re-run this script"
puts " (no bitstream rebuild needed)."
puts "==============================================="
