# run_doom.tcl  -  load DOOM into DDR and start the RV32IM
#
#   1. ps7_init                          -> PS clocks + DDR controller up
#   2. dow doom.bin   -> 0x10000000      -> the DOOM program
#   3. dow doom1.wad  -> 0x18000000      -> the game data (read by doom_syscalls.c)
#   4. fpga <bitstream>                  -> RV32IM boots, runs DOOM, HDMI output
#
# Usage:
#   source /tools/Xilinx/Vitis/2022.2/settings64.sh
#   xsct /home/dev-emru/Desktop/RV32IM-from-scratch/scripts/run_doom.tcl
#
# Plug HDMI into a monitor. Switches: SW0/1 turn, SW2 walk, SW3 fire.

set here [file normalize [file dirname [info script]]]
set root [file normalize $here/..]
set proj $root/rv32im_doom    ;# user's working DOOM project (Jun 16 23:51 — actually boots DOOM)

# Hard-coded paths (the previous glob silently picked the wrong .bit
# whenever Vivado produced more than one — user reported manual paths fixed it).
set bit  "$proj/rv32im_doom.runs/impl_1/doom_sys_wrapper.bit"
set init "$proj/rv32im_doom.gen/sources_1/bd/doom_sys/ip/doom_sys_ps7_0/ps7_init.tcl"
set prog $root/software/doom.bin
set wad  $root/doom/doom1.wad

puts "bitstream : $bit"
puts "ps7_init  : $init"
foreach f [list $prog $wad] { if {![file exists $f]} { error "missing $f — run build_doom.sh" } }
if {$bit eq "" || $init eq ""} { error "missing .bit / ps7_init.tcl — build the DOOM SoC bitstream first" }

connect
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
rst -processor
source $init
ps7_init
ps7_post_config

puts "Loading DOOM program -> DDR 0x10000000 ..."
dow -data $prog 0x10000000
puts "Loading DOOM1.WAD -> DDR 0x18000000 (4 MB, takes a moment) ..."
dow -data $wad 0x18000000

puts "Programming PL — RV32IM boots DOOM ..."
fpga -file $bit

puts "==============================================="
puts " DOOM is running. Plug HDMI into a monitor."
puts " SW0/SW1 = turn, SW2 = walk forward, SW3 = fire."
puts "==============================================="
