# ARM UART relay — Vitis bring-up

The single-cable UART path needs a tiny program on the Zynq ARM that reads the
AXI GPIO mailbox (pushed by the RV32IM) and writes each byte to the PS UART1.
This is built with Vitis from the hardware handoff (XSA) that the Vivado build
exports. Running the app in Vitis also programs the PL bitstream and runs
ps7_init for you — so there's no separate ps7_init step.

## 0. Build the bitstream + export the XSA (Vivado side)

```bash
source /tools/Xilinx/Vivado/2022.2/settings64.sh
cd <repo>/vivado_ps
vivado -mode batch -source ../scripts/build_vivado_ps.tcl   # new BD + program.hex
vivado -mode batch -source ../scripts/export_xsa.tcl        # -> vivado_ps/rv32im_soc.xsa
```

Note the AXI GPIO base address printed by `assign_bd_address` in the build log
(usually `0x4120_0000`). The XGpio driver finds it via XPAR_*, so you normally
don't need it by hand.

## 1. Vitis: platform + application

GUI (`vitis &`):

1. **Create Platform Project** → from XSA `vivado_ps/rv32im_soc.xsa`,
   OS = `standalone`, CPU = `ps7_cortexa9_0`. Build it.
2. **Create Application Project** → on that platform → template **Empty
   Application (C)**. Name it `arm_relay`.
3. Replace `arm_relay/src/` contents with `software/arm_relay/main.c`
   (delete any default `helloworld.c`).
4. **Build** the application.

## 2. Run on the board

- micro-USB to **PROG/UART** (J12), **JP5 = JTAG**, power on.
- Right-click `arm_relay` → **Run As → Launch Hardware**. Vitis will:
  program the PL bitstream, run ps7_init, download the ELF, and start it.
- Open a serial terminal: `minicom -D /dev/ttyUSB1 -b 115200`.

Expected: `[ARM relay up - waiting for RV32IM]`, then `Hello from RV32IM!`
streaming, with the four LEDs toggling each line.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Relay banner prints, but no "Hello..." | RV32IM not pushing — check LEDs toggle; check GPIO mailbox wiring / req-ack bits |
| Nothing at all on serial | wrong COM port, or UART device id — verify `XPAR_XUARTPS_0` maps to UART1 in `xparameters.h` (we enabled only UART1) |
| Garbage characters | baud mismatch — confirm 115200 and the PS UART ref clock in the BSP |
| `XPAR_AXI_GPIO_0_DEVICE_ID` undefined | check the GPIO instance name in `xparameters.h`, fix the id in `main.c` |
| LEDs blink 6× then freeze | RV32IM stuck waiting for ack — relay not running or GPIO ack channel mis-wired |
