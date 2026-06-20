# program_video.tcl  -  program the PURE-PL video bitstream over JTAG
#
# rv32im_video_top is pure PL (no PS / no ps7_init): the raycaster is baked into
# BRAM and the framebuffer comes out HDMI. So programming is just loading the
# .bit into the FPGA over the micro-USB JTAG. No Vitis / xsct needed.
#
# Usage (after the bitstream is built by build_video.tcl):
#   source /tools/Xilinx/Vivado/2022.2/settings64.sh
#   vivado -mode batch -source scripts/program_video.tcl

set here [file normalize [file dirname [info script]]]
set root [file normalize $here/..]
set bit  [lindex [concat \
             [glob -nocomplain $root/vivado_video/*/rv32im_video.runs/impl_1/rv32im_video_top.bit] \
             [glob -nocomplain $root/vivado_video/rv32im_video.runs/impl_1/rv32im_video_top.bit]] 0]

if {$bit eq ""} {
    error "rv32im_video_top.bit not found — build it first:\n  cd vivado_video && vivado -mode batch -source ../scripts/build_video.tcl"
}
puts "bitstream : $bit"

open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices -quiet *xc7z020*] 0]
set_property PROGRAM.FILE $bit [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

puts "==============================================="
puts " PL programmed. RV32IM is running the raycaster."
puts " Plug HDMI (J11) into a monitor -> 3D maze."
puts "==============================================="
close_hw_manager
