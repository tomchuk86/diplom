#include "qemu/osdep.h"
#include "hw/char/uart_cosim_protocol.h"
#include "hw/char/uart_cosim_log.h"

#include <stdio.h>
#include <stdlib.h>

static int uart_cosim_log_level(void)
{
    static int lvl = -2;
    const char *e;

    if (lvl != -2) {
        return lvl;
    }
    e = g_getenv("UART_COSIM_LOG");
    if (!e) {
        lvl = 1;
    } else {
        lvl = atoi(e);
        if (lvl < 0) {
            lvl = 1;
        }
    }
    return lvl;
}

bool uart_cosim_should_log_mmio(uint32_t offset)
{
    int l = uart_cosim_log_level();

    if (l <= 0) {
        return false;
    }
    if (l >= 2) {
        return true;
    }
    return uart_cosim_offset_verbose(offset);
}

void uart_cosim_trace_write(uint32_t offset, uint64_t data, uint32_t size)
{
    if (uart_cosim_should_log_mmio(offset)) {
        printf("[COSIM] WRITE offset=0x%x data=0x%llx size=%u\n",
               offset, (unsigned long long)data, size);
    }
}

void uart_cosim_trace_read(uint32_t offset, uint32_t size, uint64_t val)
{
    if (uart_cosim_should_log_mmio(offset)) {
        printf("[COSIM] READ offset=0x%x size=%u -> 0x%llx\n",
               offset, size, (unsigned long long)val);
    }
}
