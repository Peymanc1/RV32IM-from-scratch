# export_xsa.tcl  -  export the hardware handoff (.xsa) from the built project
#
# The .xsa bundles the bitstream + the PS init files (ps7_init.tcl), which XSCT
# needs to bring the PS up. No re-synthesis — just opens the project and writes
# the handoff.
#
# Usage (from vivado_ps/):
#   vivado -mode batch -source ../scripts/export_xsa.tcl

set here [file normalize [file dirname [info script]]]
set root [file normalize $here/..]
set xpr  $root/vivado_ps/rv32im_soc/rv32im_soc.xpr

open_project $xpr
write_hw_platform -fixed -include_bit -force $root/vivado_ps/rv32im_soc.xsa
puts "DONE. XSA: $root/vivado_ps/rv32im_soc.xsa"
