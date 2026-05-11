/*
 * Example: wiring QEMU UART cosim "dpi" backend to RTL without TCP.
 *
 * ModelSim/Questa DPI tasks (sv_uart_read/write) live inside the simulator
 * process; stock qemu-system-arm cannot call them from another binary.
 *
 * Typical approaches:
 *   - Link a custom QEMU entrypoint with your simulator vendor API (non-portable), or
 *   - Run RTL via Verilator C++ model and implement mmio_read/mmio_write below
 *     against the generated eval API, or
 *   - Полная цепочка **QEMU + гостевой драйвер + RTL**: `UART16550_COSIM=1`, ModelSim `run_cosim.do`,
 *     TCP `127.0.0.1:1234` (см. README_COSIM_UART.md), или
 *
 * This file is documentation-only unless you link it into a custom executable
 * that calls uart_cosim_register_dpi_ops() before qemu_main().
 */

#if 0

#include "hw/char/uart_cosim.h"
#include <stdint.h>

static uint8_t stub_regs[256];

static uint64_t glue_mmio_read(void *opaque, uint32_t offset, uint32_t size)
{
    (void)opaque;
    if (size != 1 || offset >= sizeof(stub_regs)) {
        return 0;
    }
    return stub_regs[offset];
}

static void glue_mmio_write(void *opaque, uint32_t offset, uint64_t data,
                            uint32_t size)
{
    (void)opaque;
    if (size != 1 || offset >= sizeof(stub_regs)) {
        return;
    }
    stub_regs[offset] = (uint8_t)data;
}

void dpi_cosim_register_stub_ops(void)
{
    static const UartCosimDpiOps ops = {
        .mmio_read = glue_mmio_read,
        .mmio_write = glue_mmio_write,
        .opaque = NULL,
    };

    uart_cosim_register_dpi_ops(&ops);
}

#endif
