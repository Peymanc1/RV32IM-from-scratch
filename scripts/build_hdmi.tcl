# build_hdmi.tcl  -  standalone HDMI colour-bar bitstream (no CPU/PS)
#
# Builds hdmi_test_top: board 125 MHz -> clk_wiz (25 MHz) -> video_timing ->
# test_pattern -> rgb2dvi (TMDS) -> HDMI TX. Shows colour bars on a monitor.
# This isolates the HDMI chain from the SoC so it's debuggable on its own.
#
# Usage:
#   mkdir -p vivado_hdmi && cd vivado_hdmi
#   vivado -mode batch -source ../scripts/build_hdmi.tcl
#
# REQUIREMENTS:
#   * Digilent vivado-library at ~/vivado-library (for the rgb2dvi IP):
#       git clone https://github.com/Digilent/vivado-library.git ~/vivado-library
#   * Digilent board files at ~/digilent_board_files (already set up).
#
# CAVEATS (HDMI bring-up is iterative — flagged honestly):
#   * The rgb2dvi IP VLNV / CONFIG names and the clk_wiz CONFIG keys can vary by
#     Vivado version. If create_ip errors, open the IP catalog in the GUI to get
#     the exact vendor/library/version and parameter names.
#   * Monitors are picky about 640x480@60 and exact pixel clock; if no image,
#     try a different monitor / adapter first.

set proj_name rv32im_hdmi
set part      xc7z020clg400-1

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize $script_dir/..]

set_param board.repoPaths $env(HOME)/digilent_board_files
create_project $proj_name ./$proj_name -part $part -force

# RTL
add_files -norecurse $root_dir/rtl/video/video_timing.sv
add_files -norecurse $root_dir/rtl/video/test_pattern.sv
add_files -norecurse $root_dir/rtl/video/hdmi_test_top.sv
add_files -fileset constrs_1 -norecurse $root_dir/constraints/zybo_hdmi.xdc

# ---- clk_wiz: 125 MHz -> 25 MHz pixel clock + 125 MHz serial clock (5x) ----
# rgb2dvi can't generate its own serial clock for a 25 MHz pixel (its packaged
# kClkRange only allows 1/2/3 = >=40 MHz), so we provide both clocks here.
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

set_property top hdmi_test_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] != "100%" } { error "Synthesis failed." }

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } { error "Implementation failed." }

puts "DONE. Bitstream: ./$proj_name.runs/impl_1/hdmi_test_top.bit"
