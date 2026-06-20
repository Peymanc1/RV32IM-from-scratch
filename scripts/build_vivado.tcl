# build_vivado.tcl  -  one-shot Vivado batch build
#
# Usage:
#   cd vivado_project
#   vivado -mode batch -source ../scripts/build_vivado.tcl
#
# Steps:
#   1. create new project (Z7-20 by default)
#   2. add the SV sources
#   3. add the XDC
#   4. add program.hex as a Memory Initialization File
#   5. synth + impl + bitstream
#
# Output: vivado_project/rv32im_fpga.runs/impl_1/rv32im_fpga_top.bit

# Project settings — edit `part` for a different board.
set proj_name      "rv32im_fpga"
set proj_dir       "./$proj_name"
set part           "xc7z020clg400-1"   ;# Zybo Z7-20  (Z7-10 = xc7z010clg400-1)
set top_module     "rv32im_fpga_top"

# Paths (assumes script invoked from inside vivado_project/, sibling of scripts/)
set repo_root      [file normalize "[file dirname [info script]]/.."]
set rtl_dir        "$repo_root/rtl"
set constraints    "$repo_root/constraints/zybo_z7.xdc"
set program_hex    "$repo_root/software/program.hex"

puts "[1/6] creating project: $proj_name"
file delete -force $proj_dir
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]

puts "[2/6] adding RTL sources"
add_files -norecurse [glob "$rtl_dir/core/*.sv"]
add_files -norecurse [glob "$rtl_dir/memory/*.sv"]
add_files -norecurse "$rtl_dir/top/rv32im_core_pipelined.sv"
add_files -norecurse "$rtl_dir/top/rv32im_fpga_top.sv"

# Keep the single-cycle top out of synthesis — sim-only.
set_property used_in_synthesis false [get_files "$rtl_dir/top/rv32im_core.sv"] -quiet

set_property top $top_module [current_fileset]
set_property file_type SystemVerilog [get_files "$rtl_dir/core/rv32im_pkg.sv"]

puts "[3/6] adding constraints"
add_files -fileset constrs_1 -norecurse $constraints

puts "[4/6] adding program.hex (Memory Initialization File)"
# imem.sv calls \$readmemh("program.hex"); Vivado looks for it in the project.
add_files -norecurse $program_hex
set_property file_type "Memory Initialization Files" [get_files program.hex]

puts "[5/6] synthesis"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] != "100%" } {
    error "synthesis failed"
}

puts "[6/6] implementation + bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    error "implementation failed"
}

set bitfile "$proj_dir/$proj_name.runs/impl_1/$top_module.bit"
puts ""
puts "==========================================="
puts " bitstream ready:"
puts "   $bitfile"
puts ""
puts " program over JTAG with:"
puts "   open_hw_manager"
puts "   connect_hw_server"
puts "   open_hw_target"
puts "   set_property PROGRAM.FILE $bitfile \[lindex \[get_hw_devices\] 0\]"
puts "   program_hw_devices \[lindex \[get_hw_devices\] 0\]"
puts "==========================================="

# Drop utilization + timing reports next to the project.
open_run impl_1
report_utilization -file "$proj_dir/utilization_post_impl.rpt"
report_timing_summary -file "$proj_dir/timing_summary_post_impl.rpt"
puts "reports: $proj_dir/{utilization,timing_summary}_post_impl.rpt"
