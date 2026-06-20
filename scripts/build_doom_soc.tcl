# build_doom_soc.tcl  -  the DOOM SoC bitstream
#
# BD = Zynq PS (S_AXI_HP0 -> DDR) + SmartConnect(2 SI) + rv32im_doom_core
# (CPU + I-cache + D-cache + framebuffer/palette/switch MMIO) + the video
# pipeline (clk_wiz -> 25 MHz pixel + 125 MHz serial; video_fb; rgb2dvi -> HDMI).
# NO program is baked in — DOOM lives in DDR (loaded by run_doom.tcl).
#
# Usage:
#   mkdir -p vivado_doom && cd vivado_doom
#   vivado -mode batch -source ../scripts/build_doom_soc.tcl
# Then:  xsct ../scripts/run_doom.tcl
#
# REQUIREMENTS: Digilent board files at ~/digilent_board_files and the Digilent
# vivado-library (rgb2dvi) at ~/vivado-library.

set proj_name rv32im_doom
set part      xc7z020clg400-1
set bd_name   doom_sys

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize $script_dir/..]

set home_dir ""
if { [info exists env(USERPROFILE)] } { set home_dir [file normalize $env(USERPROFILE)] }
if { $home_dir eq "" && [info exists env(HOME)] } { set home_dir [file normalize $env(HOME)] }
foreach candidate [list \
        "$home_dir/vivado-boards/new/board_files" \
        "$home_dir/digilent_board_files/new/board_files" \
        "$home_dir/digilent_board_files"] {
    if { [file isdirectory $candidate] } {
        set_param board.repoPaths $candidate
        puts "INFO: board.repoPaths = $candidate"; break
    }
}
create_project $proj_name ./$proj_name -part $part -force
set bp [get_board_parts -quiet *zybo-z7-20:part0:*]
if { [llength $bp] == 0 } { error "Zybo Z7-20 board_part not found." }
set_property board_part [lindex $bp 0] [current_project]

# ---- RTL ----
add_files -norecurse [glob $root_dir/rtl/core/*.sv]
add_files -norecurse $root_dir/rtl/memory/imem.sv
add_files -norecurse $root_dir/rtl/memory/dmem.sv
add_files -norecurse $root_dir/rtl/memory/cache.sv
add_files -norecurse $root_dir/rtl/memory/mmio_bridge.sv
add_files -norecurse $root_dir/rtl/peripherals/axi_burst_master.sv
add_files -norecurse $root_dir/rtl/video/video_timing.sv
add_files -norecurse $root_dir/rtl/video/framebuffer.sv
add_files -norecurse $root_dir/rtl/video/palette.sv
add_files -norecurse $root_dir/rtl/video/video_fb.sv
add_files -norecurse $root_dir/rtl/video/video_fb_wrap.v
add_files -norecurse $root_dir/rtl/top/rv32im_core_pipelined.sv
add_files -norecurse $root_dir/rtl/top/rv32im_doom_core.sv
add_files -norecurse $root_dir/rtl/top/rv32im_doom_wrap.v
add_files -fileset constrs_1 -norecurse $root_dir/constraints/zybo_doom.xdc

# rgb2dvi IP repo
set ip_repo ""
foreach candidate [list "$home_dir/vivado-library/ip" "$home_dir/vivado-library" "$home_dir/Documents/vivado-library/ip"] {
    if { [file isdirectory $candidate] } { set ip_repo $candidate; break }
}
if { $ip_repo eq "" } { error "vivado-library not found under $home_dir" }
set_property ip_repo_paths $ip_repo [current_project]
update_ip_catalog
puts "INFO: ip_repo_paths = $ip_repo"
update_ip_catalog -rebuild

# ---------------------------------------------------------------------------
create_bd_design $bd_name

# Zynq PS: S_AXI_HP0, FCLK_CLK0=50 (CPU/AXI), FCLK_CLK1=125 (video clk_wiz in)
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config { make_external "FIXED_IO, DDR" apply_board_preset "1" \
              Master "Disable" Slave "Disable" } [get_bd_cells ps7]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {125} \
    CONFIG.PCW_EN_RST0_PORT {1} \
] [get_bd_cells ps7]

# clk_wiz: 125 -> 25 MHz pixel + 125 MHz serial
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clkw
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {false} \
] [get_bd_cells clkw]

# rgb2dvi (Digilent): active-low reset so we can tie aRst = locked
create_bd_cell -type ip -vlnv digilentinc.com:ip:rgb2dvi rgb2dvi
set_property -dict [list CONFIG.kGenerateSerialClk {false} CONFIG.kRstActiveHigh {false} ] [get_bd_cells rgb2dvi]

# our cores (module references via Verilog wrappers)
create_bd_cell -type module -reference rv32im_doom_wrap doom
create_bd_cell -type module -reference video_fb_wrap    vfb

# SEPARATE DDR paths to avoid I/D shared-bus contention (a timing race that
# corrupted stores when both went through one SmartConnect->HP0). D -> HP0,
# I -> HP1, each via its own 1-SI SmartConnect (32->64 bit width conversion).
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smc_d
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells smc_d]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smc_i
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells smc_i]

# {r,g,b} -> 24-bit vid_pData
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat cat
set_property -dict [list CONFIG.NUM_PORTS {3} CONFIG.IN0_WIDTH {8} CONFIG.IN1_WIDTH {8} CONFIG.IN2_WIDTH {8}] [get_bd_cells cat]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst0
connect_bd_net [get_bd_pins ps7/FCLK_CLK0]     [get_bd_pins rst0/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst0/ext_reset_in]

# ---- clocks ----
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins clkw/clk_in1]
foreach c { doom/clk vfb/clk_w smc_d/aclk smc_i/aclk ps7/S_AXI_HP0_ACLK ps7/S_AXI_HP1_ACLK } {
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $c]
}
connect_bd_net [get_bd_pins clkw/clk_out1] [get_bd_pins vfb/pclk]
connect_bd_net [get_bd_pins clkw/clk_out1] [get_bd_pins rgb2dvi/PixelClk]
connect_bd_net [get_bd_pins clkw/clk_out2] [get_bd_pins rgb2dvi/SerialClk]
connect_bd_net [get_bd_pins clkw/locked]   [get_bd_pins vfb/rst_n]
connect_bd_net [get_bd_pins clkw/locked]   [get_bd_pins rgb2dvi/aRst_n]

# ---- resets ----
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_pins doom/rst_n]
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_pins smc_d/aresetn]
connect_bd_net [get_bd_pins rst0/peripheral_aresetn] [get_bd_pins smc_i/aresetn]

# ---- AXI: D -> smc_d -> HP0 ; I -> smc_i -> HP1  (fully separate paths) ----
connect_bd_intf_net [get_bd_intf_pins doom/m_axi_d] [get_bd_intf_pins smc_d/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smc_d/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
connect_bd_intf_net [get_bd_intf_pins doom/m_axi_i] [get_bd_intf_pins smc_i/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smc_i/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP1]

# ---- framebuffer / palette wires doom -> video_fb ----
foreach s { fb_we fb_waddr fb_wdata pal_we pal_waddr pal_wdata } {
    connect_bd_net [get_bd_pins doom/$s] [get_bd_pins vfb/$s]
}

# ---- video_fb RGB+sync -> rgb2dvi ----
connect_bd_net [get_bd_pins vfb/b] [get_bd_pins cat/In0]
connect_bd_net [get_bd_pins vfb/g] [get_bd_pins cat/In1]
connect_bd_net [get_bd_pins vfb/r] [get_bd_pins cat/In2]
connect_bd_net [get_bd_pins cat/dout]  [get_bd_pins rgb2dvi/vid_pData]
connect_bd_net [get_bd_pins vfb/de]    [get_bd_pins rgb2dvi/vid_pVDE]
connect_bd_net [get_bd_pins vfb/hsync] [get_bd_pins rgb2dvi/vid_pHSync]
connect_bd_net [get_bd_pins vfb/vsync] [get_bd_pins rgb2dvi/vid_pVSync]

# ---- external ports: switches, LEDs, HDMI ----
make_bd_pins_external  [get_bd_pins doom/sw];  set_property name sw  [get_bd_ports sw_0]
make_bd_pins_external  [get_bd_pins doom/led]; set_property name led [get_bd_ports led_0]
make_bd_pins_external  [get_bd_pins rgb2dvi/TMDS_Clk_p];  set_property name hdmi_tx_clk_p [get_bd_ports TMDS_Clk_p_0]
make_bd_pins_external  [get_bd_pins rgb2dvi/TMDS_Clk_n];  set_property name hdmi_tx_clk_n [get_bd_ports TMDS_Clk_n_0]
make_bd_pins_external  [get_bd_pins rgb2dvi/TMDS_Data_p]; set_property name hdmi_tx_p     [get_bd_ports TMDS_Data_p_0]
make_bd_pins_external  [get_bd_pins rgb2dvi/TMDS_Data_n]; set_property name hdmi_tx_n     [get_bd_ports TMDS_Data_n_0]

assign_bd_address
validate_bd_design
save_bd_design

make_wrapper -files [get_files $bd_name.bd] -top
set pdir [get_property DIRECTORY [current_project]]
set wrap_files [glob -nocomplain \
    $pdir/${proj_name}.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.* \
    $pdir/${proj_name}.srcs/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.*]
if { [llength $wrap_files] == 0 } { error "BD wrapper not found" }
add_files -norecurse $wrap_files
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] != "100%" } { error "Synthesis failed." }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } { error "Implementation failed." }
puts "DONE. Bitstream: ./$proj_name.runs/impl_1/${bd_name}_wrapper.bit"
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         