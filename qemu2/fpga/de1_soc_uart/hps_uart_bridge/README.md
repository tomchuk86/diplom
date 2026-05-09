# DE1-SoC HPS UART16550 Bridge Bitstream

This project builds an FPGA bitstream where Linux on the HPS accesses the
UART16550 RTL through the lightweight HPS-to-FPGA bridge:

```text
HPS Linux -> lightweight HPS-to-FPGA bridge -> Avalon-MM -> APB UART16550
```

The UART IP is mapped at lightweight bridge offset `0x00010000`, so the Linux
physical address is:

```text
0xff200000 + 0x00010000 = 0xff210000
```

The first version uses polling/MMIO only. The UART IRQ signal is intentionally
left unconnected because the current demo driver can test the block without GIC
integration.

## Build

From this directory:

```bash
cd /home/vboxuser/diplom/qemu2/fpga/de1_soc_uart/hps_uart_bridge

/opt/altera_lite/25.1std/quartus/sopc_builder/bin/qsys-script \
  --package-version=13.1 \
  --search-path='ip/uart16550_avalon,$' \
  --script=soc_system.tcl

/opt/altera_lite/25.1std/quartus/sopc_builder/bin/qsys-generate \
  soc_system.qsys \
  --synthesis=VERILOG \
  --search-path='ip/uart16550_avalon,$'

python3 patch_soc_system_qip.py

/opt/altera_lite/25.1std/quartus/bin/quartus_sh --flow compile hps_uart_bridge
```

The output bitstream is:

```text
output_files/hps_uart_bridge.sof
```

Note: `patch_soc_system_qip.py` removes a stale generated `hps_sdram_p0.sdc`
reference. Without this patch Quartus can stop in Fitter with an auto-constraint
error when the design only needs the lightweight bridge and does not export HPS
DDR pins at the FPGA top level.

## Program FPGA

Check the JTAG chain:

```bash
/opt/altera_lite/25.1std/quartus/bin/jtagconfig --enum
```

Program the FPGA device in the DE1-SoC chain. On this setup the FPGA was device
`@2`; if your `jtagconfig --enum` shows a different chain, adjust the cable name:

```bash
sudo /opt/altera_lite/25.1std/quartus/bin/quartus_pgm \
  -c "DE-SoC [2-1]" \
  -m jtag \
  -o "p;output_files/hps_uart_bridge.sof@2"
```

## Test From HPS Linux

Boot Linux on the board, then enable the lightweight bridge if sysfs exposes it:

```sh
ls /sys/class/fpga-bridge
echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable 2>/dev/null || true
```

Load the demo driver with the bridge address:

```sh
cd /root/uart16550_demo
rmmod uart16550_demo 2>/dev/null
insmod ./uart16550_demo.ko base_addr=0xff210000 region_size=0x1000
./test_uart16550_demo
```

For external UART traffic, connect:

```text
GPIO_0[0] FPGA TX -> USB-UART RX
GPIO_0[1] FPGA RX <- USB-UART TX
GND board        -> USB-UART GND
```
