## Zybo Z7-20 — RV32IM + DDR bring-up (BD is top; clock comes from PS FCLK_CLK0)
## Only the LEDs are real PL pins. PASS = 0b0101, FAIL = 0b1010, 0000 = hung.

set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];
