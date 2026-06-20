# build_video.tcl  -  RV32IM + HDMI framebuffer bitstream (rv32im_video_top)
#
# The CPU (running software/demo_draw.c, baked into BRAM) draws an XOR texture
# into the framebuffer, which comes out HDMI. Pure PL — no PS, no Vitis, no
# program loader. Just build + program the bitstream.
#
# Usage:
#   cd scripts && ./build_demo.sh demo_draw      # -> software/program.hex
#   mkdir -p ../vivado_video && cd ../vivado_video
#   vivado -mode batch -source ../scripts/build_video.tcl
#
# REQUIREMENTS: Digilent vivado-library at ~/vivado-library (rgb2dvi IP).

set proj_name rv32im_video
set part      xc7z020clg400-1

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize $script_dir/..]

set_param board.repoPaths $env(HOME)/digilent_board_files
create_project $proj_name ./$proj_name -part $part -force

# RTL: CPU core + memory + video + tops
add_files -norecurse [glob $root_dir/rtl/core/*.sv]
add_files -norecurse [glob $root_dir/rtl/memory/*.sv]
add_files -norecurse [glob $root_dir/rtl/peripherals/*.sv]
add_files -norecurse [glob $root_dir/rtl/video/video_timing.sv]
add_files -norecurse [glob $root_dir/rtl/video/framebuffer.sv]
add_files -norecurse [glob $root_dir/rtl/video/palette.sv]
add_files -norecurse [glob $root_dir/rtl/video/video_fb.sv]
add_files -norecurse $root_dir/rtl/top/rv32im_core_pipelined.sv
add_files -norecurse $root_dir/rtl/top/rv32im_fpga_top.sv
add_files -norecurse $root_dir/rtl/top/rv32im_video_top.sv

# sim-only single-cycle top
add_files -norecurse $root_dir/rtl/top/rv32im_core.sv
set_property used_in_synthesis false [get_files rv32im_core.sv]

# program.hex (the drawing program) -> BRAM init
add_files -norecurse $root_dir/software/program.hex
set_property file_type "Memory Initialization Files" [get_files program.hex]

add_files -fileset constrs_1 -norecurse $root_dir/constraints/zybo_video.xdc

# ---- clk_wiz: 125 MHz -> 25 MHz pixel + 125 MHz serial ----
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {false} \
] [get_ips clk_wiz_0]
generate_target {instantiation_template synthesis} [get_ips clk_wiz_0]

# ---- rgb2dvi (Digilent) ----
set_property ip_repo_paths $env(HOME)/vivado-library/ip [current_project]
update_ip_catalog -rebuild
create_ip -name rgb2dvi -vendor digilentinc.com -library ip -module_name rgb2dvi_0
set_property -dict [list \
    CONFIG.kGenerateSerialClk {false} \
    CONFIG.kRstActiveHigh {true} \
] [get_ips rgb2dvi_0]
generate_target all [get_ips rgb2dvi_0]

set_property top rv32im_video_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] != "100%" } { error "Synthesis failed." }

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } { error "Implementation failed." }

puts "DONE. Bitstream: ./$proj_name.runs/impl_1/rv32im_video_top.bit"
