## =============================================================================
## Zybo Z7-10 / Z7-20 Constraints
## Top module: rv32im_fpga_top
##
## Pin atamasi: Digilent Zybo Z7 master XDC referansindan alindi.
## https://digilent.com/reference/programmable-logic/zybo-z7/reference-manual
## =============================================================================

## --- Clock signal: 125 MHz Ethernet PHY tarafindan saglanan SYSCLK ---
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

## --- Reset butonu (BTN0, active-HIGH — Zybo butonlari pull-down'lu) ---
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { btn_rst }];

## --- LED'ler (LD0..LD3) ---
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## --- CDC false path: 125 MHz domain'den cpu_clk domain'ine giden reset
##     synchronizer'a static-timing analysis disinda tut. ---
set_false_path -from [get_ports btn_rst] -to [get_clocks *cpu_clk*]

## --- Konfigurasyon notu: Bitstream'i SD karta (boot mode SW6=11) yazmak
##     icin asagidaki ayar gerek. JTAG-only icin bunu yorum yapabilirsin. ---
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO     [current_design]
