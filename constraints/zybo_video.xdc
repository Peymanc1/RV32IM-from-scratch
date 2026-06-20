## =============================================================================
## Zybo Z7-20 — RV32IM + HDMI framebuffer (rv32im_video_top)
## =============================================================================

## 125 MHz board oscillator
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

## Reset button (BTN0, active-high)
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports { btn_rst }];

## Slide switches (game input): SW0=turn L, SW1=turn R, SW2=forward, SW3=back
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];

## LEDs
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## HDMI TX (source) — TMDS differential pairs
set_property -dict { PACKAGE_PIN H16 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_p }];
set_property -dict { PACKAGE_PIN H17 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_n }];
set_property -dict { PACKAGE_PIN D19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[0] }];
set_property -dict { PACKAGE_PIN D20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[0] }];
set_property -dict { PACKAGE_PIN C20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[1] }];
set_property -dict { PACKAGE_PIN B20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[1] }];
set_property -dict { PACKAGE_PIN B19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[2] }];
set_property -dict { PACKAGE_PIN A20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[2] }];
