## =============================================================================
## Zybo Z7-20 — standalone HDMI colour-bar test (hdmi_test_top)
## Pins from the Digilent Zybo-Z7-Master.xdc.
## =============================================================================

## 125 MHz board oscillator
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

## HDMI TX (source) — TMDS differential pairs
set_property -dict { PACKAGE_PIN H16 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_p }];
set_property -dict { PACKAGE_PIN H17 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_n }];
set_property -dict { PACKAGE_PIN D19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[0] }];
set_property -dict { PACKAGE_PIN D20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[0] }];
set_property -dict { PACKAGE_PIN C20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[1] }];
set_property -dict { PACKAGE_PIN B20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[1] }];
set_property -dict { PACKAGE_PIN B19 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_p[2] }];
set_property -dict { PACKAGE_PIN A20 IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_n[2] }];
