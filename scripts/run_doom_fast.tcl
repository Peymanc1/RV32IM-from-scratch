# run_doom_fast.tcl - reload only doom.bin + reprogram PL (WAD stays in DDR).
set root [file normalize [file dirname [info script]]/..]
set proj $root/vivado_doom/rv32im_doom
set bit  [lindex [glob -nocomplain $proj/*.runs/impl_1/*_wrapper.bit] 0]
set init [lindex [glob -nocomplain $proj/*.gen/sources_1/bd/*/ip/*ps7*/ps7_init.tcl] 0]
connect
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
rst -processor
source $init; ps7_init; ps7_post_config
puts "loading doom.bin -> 0x10000000 (WAD assumed already in DDR @0x18000000)"
dow -data $root/software/doom.bin 0x10000000
fpga -file $bit
puts "done — watch LEDs: 0001=reached main, 0010=DOOM init done, 1xxx blinking=frames rendering"
