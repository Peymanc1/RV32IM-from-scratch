# build_vivado_ps.tcl  -  SoC build: single-cable UART via ARM relay
#
# Block design = Zynq PS (M_AXI_GP0 master) + AXI Interconnect + AXI GPIO.
# The RV32IM (PL) pushes characters into the AXI GPIO mailbox over plain MMIO
# (no AXI on the PL side -> never stalls). The ARM reads the GPIO over
# M_AXI_GP0 and relays each byte to the PS UART1, out the single micro-USB.
#
# GPIO mailbox: channel 1 = 9-bit input  (PL->PS, {req, char})
#               channel 2 = 1-bit output (PS->PL, ack toggle)
# AXI GPIO is assigned in the M_AXI_GP0 space (typically 0x41200000 — confirm
# in the assign_bd_address output and match it in the ARM relay).
#
# Usage:
#   mkdir -p vivado_ps && cd vivado_ps
#   vivado -mode batch -source ../scripts/build_vivado_ps.tcl
#
# REQUIREMENTS:
#   * Digilent board files at ~/digilent_board_files (set via board.repoPaths
#     below). Get them from https://github.com/Digilent/vivado-boards
#     (new/board_files). The Zybo Z7-20 preset configures DDR/MIO/clocks and the
#     UART IO-PLL — essential for the PS UART to actually transmit.
#   * Wrapper port names (ps_sys_wrapper.v) must match rv32im_soc_top.sv. If your
#     Vivado adds a "_0" suffix, adjust the instantiation there.

set proj_name  rv32im_soc
set part       xc7z020clg400-1
set bd_name    ps_sys

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize $script_dir/..]

# Point Vivado at the Digilent board files (copied to ~/digilent_board_files)
# so the Zybo Z7-20 PS preset (DDR / MIO / clocks / UART IO-PLL) applies — this
# is what makes the PS UART transmit and the AXI bus respond.
set_param board.repoPaths $env(HOME)/digilent_board_files

create_project $proj_name ./$proj_name -part $part -force

# Resolve the board_part automatically (the file_version, e.g. 1.2, varies
# between board-file releases — don't hardcode it).
set bp [get_board_parts -quiet *zybo-z7-20:part0:*]
if { [llength $bp] == 0 } {
    error "Zybo Z7-20 board_part not found. Is board.repoPaths correct?\
           ($env(HOME)/digilent_board_files) — available: [get_board_parts -quiet]"
}
set board_part [lindex $bp 0]
puts "Using board_part: $board_part"
set_property board_part $board_part [current_project]

# ---------------------------------------------------------------------------
# RTL sources
# ---------------------------------------------------------------------------
add_files -norecurse [glob $root_dir/rtl/core/*.sv]
add_files -norecurse [glob $root_dir/rtl/memory/*.sv]
add_files -norecurse [glob $root_dir/rtl/peripherals/*.sv]
add_files -norecurse $root_dir/rtl/top/rv32im_core_pipelined.sv
add_files -norecurse $root_dir/rtl/top/rv32im_fpga_top.sv
add_files -norecurse $root_dir/rtl/top/rv32im_soc_top.sv

# single-cycle top is sim-only; keep it out of synthesis
add_files -norecurse $root_dir/rtl/top/rv32im_core.sv
set_property used_in_synthesis false [get_files rv32im_core.sv]

# program.hex -> BRAM init (the $readmemh in imem.sv resolves at synth time)
add_files -norecurse $root_dir/software/program.hex
set_property file_type "Memory Initialization Files" [get_files program.hex]

# constraints (button + LEDs only; clock comes from PS)
add_files -fileset constrs_1 -norecurse $root_dir/constraints/zybo_z7_ps.xdc

# ---------------------------------------------------------------------------
# Block design: Zynq PS (M_AXI_GP0) + AXI Interconnect + AXI GPIO mailbox
# ---------------------------------------------------------------------------
create_bd_design $bd_name

# Zynq PS
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config { make_external "FIXED_IO, DDR" apply_board_preset "1" \
              Master "Disable" Slave "Disable" } [get_bd_cells ps7]

# Enable M_AXI_GP0 (PS master -> PL), UART1 on MIO 48/49, a clock + reset.
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_GP0 {0} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
] [get_bd_cells ps7]

# AXI GPIO mailbox: ch1 = 9-bit all-input (PL->PS), ch2 = 1-bit all-output (PS->PL)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio gpio
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {9} \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_GPIO2_WIDTH {1} \
    CONFIG.C_ALL_OUTPUTS_2 {1} \
] [get_bd_cells gpio]

# AXI Interconnect: PS M_AXI_GP0 (AXI3 master) -> AXI GPIO (AXI4-Lite slave).
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_ic
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_ic]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0]  [get_bd_intf_pins axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M00_AXI] [get_bd_intf_pins gpio/S_AXI]

# Clock the whole AXI domain (M_AXI_GP0 + interconnect + GPIO) from the PS
# FCLK_CLK0 — a real PS clock. (We previously drove it from a PL-divided clock,
# which left the PS AXI port unresponsive and hung the ARM: "cannot halt core".)
# The PL core keeps its own board-oscillator clock; only the GPIO *wires* cross
# between the two domains, and the slow req/ack handshake tolerates that.
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst0
connect_bd_net [get_bd_pins ps7/FCLK_CLK0]     [get_bd_pins rst0/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst0/ext_reset_in]

foreach c { ps7/M_AXI_GP0_ACLK axi_ic/ACLK axi_ic/S00_ACLK axi_ic/M00_ACLK gpio/s_axi_aclk } {
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $c]
}
connect_bd_net [get_bd_pins rst0/interconnect_aresetn] [get_bd_pins axi_ic/ARESETN]
connect_bd_net [get_bd_pins rst0/peripheral_aresetn]   [get_bd_pins axi_ic/S00_ARESETN]
connect_bd_net [get_bd_pins rst0/peripheral_aresetn]   [get_bd_pins axi_ic/M00_ARESETN]
connect_bd_net [get_bd_pins rst0/peripheral_aresetn]   [get_bd_pins gpio/s_axi_aresetn]

# Expose the GPIO channels as external ports (-> ps_sys_wrapper ports
# mbox_in_tri_i[8:0] and mbox_ack_tri_o[0:0]).
make_bd_intf_pins_external [get_bd_intf_pins gpio/GPIO]
set_property name mbox_in  [get_bd_intf_ports GPIO_0]
make_bd_intf_pins_external [get_bd_intf_pins gpio/GPIO2]
set_property name mbox_ack [get_bd_intf_ports GPIO2_0]

# Assign the AXI GPIO into the M_AXI_GP0 address space (watch the log for the
# resulting base — used by the ARM relay).
assign_bd_address

validate_bd_design
save_bd_design

# Generate the HDL wrapper (module ps_sys_wrapper) for the RTL top to use.
# Vivado 2022.x writes generated BD output under <proj>.gen/; older versions
# used <proj>.srcs/ — glob both so this is version-robust.
make_wrapper -files [get_files $bd_name.bd] -top
set pdir [get_property DIRECTORY [current_project]]
set wrap_files [glob -nocomplain \
    $pdir/${proj_name}.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.* \
    $pdir/${proj_name}.srcs/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.*]
if { [llength $wrap_files] == 0 } { error "BD wrapper not found after make_wrapper" }
add_files -norecurse $wrap_files

# Our hand-written SoC top is the synthesis top (it instantiates the wrapper).
set_property top rv32im_soc_top [current_fileset]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
# Synthesis + implementation + bitstream
# ---------------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] != "100%" } {
    error "Synthesis failed — see synth_1 log."
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    error "Implementation failed — see impl_1 log."
}

puts "DONE. Bitstream:"
puts "  ./$proj_name.runs/impl_1/rv32im_soc_top.bit"
