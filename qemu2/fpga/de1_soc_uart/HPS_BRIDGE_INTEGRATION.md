# HPS-to-FPGA UART16550 integration

This project currently has two FPGA/HPS usage modes:

- standalone FPGA UART demo (`de1_soc_uart_top.v`) for GPIO/PuTTY testing;
- HPS Linux driver access through the lightweight HPS-to-FPGA bridge.

The HPS/Linux mode requires adding the UART IP to a Platform Designer system.
The software DPI bridge used by QEMU/ModelSim cosimulation is not used on the
physical board.

## Hardware block

Use this wrapper as the custom Platform Designer component top:

```text
rtl/uart_16550/avalon_apb_uart_16550.v
```

It exposes:

- Avalon-MM slave: `avs_*`
- clock/reset: `clk`, `reset_n`
- interrupt: `irq`
- UART pins: `uart_txd`, `uart_rxd`

It wraps the APB UART core:

```text
avalon_apb_uart_16550 -> apb_uart_16550 -> uart_16550_core
```

## Platform Designer steps

1. Create a new Platform Designer system, for example `hps_uart_system`.
2. Add `Cyclone V Hard Processor System`.
3. Enable the lightweight HPS-to-FPGA master interface.
4. Create a custom component using these files:

   ```text
   rtl/uart_16550/avalon_apb_uart_16550.v
   rtl/uart_16550/apb_uart_16550.v
   rtl/uart_16550/uart_16550_core.v
   rtl/uart_16550/uart_baud.v
   rtl/uart_16550/uart_fifo.v
   rtl/uart_16550/uart_tx.v
   rtl/uart_16550/uart_rx.v
   ```

5. Set custom component top module to `avalon_apb_uart_16550`.
6. Mark `avs_*` as an Avalon-MM slave interface.
7. Connect:

   ```text
   HPS h2f_lw_axi_master -> avalon_apb_uart_16550 Avalon-MM slave
   clock/reset           -> avalon_apb_uart_16550 clk/reset_n
   uart_txd/rxd          -> external conduit or board pins
   ```

8. Assign an address offset in the lightweight bridge map, for example:

   ```text
   UART offset: 0x00010000
   Linux physical address: 0xFF200000 + 0x00010000 = 0xFF210000
   ```

9. Generate HDL and include the generated system in the Quartus project.

## Linux driver test on DE1-SoC

Build the driver on the board if kernel headers are available:

```sh
cd /root/uart16550_demo
make clean
make
```

Load with the physical address assigned in Platform Designer:

```sh
insmod ./uart16550_demo.ko base_addr=0xff210000 region_size=0x1000
ls -l /dev/uart16550_demo
./test_uart16550_demo
```

If the driver loads with `0xff200000` but the test shows no RX/TX activity,
that only proves the lightweight bridge region can be mapped. The UART IP must
be instantiated at the selected offset for the driver to talk to the RTL.
