#include "qemu/osdep.h"
#include "hw/char/uart_cosim_backend.h"
#include "hw/char/uart_cosim.h"
#include "hw/char/uart_cosim_log.h"

#include <stdio.h>
#include <string.h>

static UartCosimDpiOps dpi_ops;
static bool dpi_registered;

bool uart_cosim_dpi_has_ops(void)
{
    return dpi_registered;
}

void uart_cosim_register_dpi_ops(const UartCosimDpiOps *ops)
{
    memset(&dpi_ops, 0, sizeof(dpi_ops));
    dpi_registered = false;

    if (!ops || !ops->mmio_read || !ops->mmio_write) {
        return;
    }

    dpi_ops = *ops;
    dpi_registered = true;
}

int uart_cosim_dpi_init(void)
{
    if (!dpi_registered) {
        printf("[COSIM dpi] ops missing — register uart_cosim_register_dpi_ops() "
               "before uart-stub init, or rely on uart-stub fallback MMIO.\n");
        return -1;
    }

    printf("[COSIM dpi] backend active (MMIO via registered callbacks)\n");
    return 0;
}

void uart_cosim_dpi_close(void)
{
    memset(&dpi_ops, 0, sizeof(dpi_ops));
    dpi_registered = false;
}

void uart_cosim_dpi_write(uint32_t offset, uint64_t data, uint32_t size)
{
    if (!dpi_registered) {
        printf("[COSIM dpi] write skipped: not initialized\n");
        return;
    }

    dpi_ops.mmio_write(dpi_ops.opaque, offset, data, size);
    uart_cosim_trace_write(offset, data, size);
}

uint64_t uart_cosim_dpi_read(uint32_t offset, uint32_t size)
{
    uint64_t val;

    if (!dpi_registered) {
        printf("[COSIM dpi] read skipped: not initialized\n");
        return 0;
    }

    val = dpi_ops.mmio_read(dpi_ops.opaque, offset, size);
    uart_cosim_trace_read(offset, size, val);
    return val;
}
