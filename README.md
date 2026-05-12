# diplom

Интеграция **QEMU vexpress-a9** (`hw/char/uart_*` cosim) ↔ **RTL UART 16550** (ModelSim bridge) ↔ **драйвер** `qemu2/drivers/uart16550_extended`: см. [qemu2/README_COSIM_UART.md](qemu2/README_COSIM_UART.md).

Быстрая сборка артефактов: `bash qemu2/scripts/build_uart16550_stack.sh`.