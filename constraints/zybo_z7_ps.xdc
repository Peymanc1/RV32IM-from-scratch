## =============================================================================
## Zybo Z7-20 constraints for the PS-based SoC build (rv32im_soc_top)
##
## NOTE: unlike the pure-PL build, there is NO external clock pin here — the
## CPU clock source is the PS FCLK_CLK0, generated inside the Zynq block design.
## So this file only constrains the button and the LEDs. DDR / FIXED_IO / UART
## MIO pins are handled automatically by the PS (apply_board_preset).
## =============================================================================

## --- 125 MHz board oscillator (clocks the PL, independent of the PS) ---
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

## --- Reset button (BTN0, active-HIGH) ---
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { btn_rst }];

## --- LEDs (LD0..LD3) ---
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];
