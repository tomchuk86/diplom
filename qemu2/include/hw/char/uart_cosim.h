#ifndef HW_CHAR_UART_COSIM_H
#define HW_CHAR_UART_COSIM_H

#include <stdbool.h>
#include <stdint.h>

/*
 * UART16550_COSIM:
 *   unset / "0" — только встроенная MMIO-модель uart-stub (cosim выключен).
 *   "dpi" — MMIO через uart_cosim_register_dpi_ops() (один процесс с моделью).
 *           Если ops не зарегистрированы, uart-stub ставит fallback на ту же модель.
 *   "1", "socket" или любое другое ненулевое — TCP-клиент QEMU → 127.0.0.1:1234
 *           (ModelSim bridge_dpi.so + RTL + строковый протокол).
 *
 * UART_COSIM_LOG: 0=silent, 1=default (меньше спама по LSR), 2=all offsets.
 */

typedef struct UartCosimDpiOps {
    uint64_t (*mmio_read)(void *opaque, uint32_t offset, uint32_t size);
    void (*mmio_write)(void *opaque, uint32_t offset, uint64_t data, uint32_t size);
    void *opaque;
} UartCosimDpiOps;

void uart_cosim_register_dpi_ops(const UartCosimDpiOps *ops);

bool uart_cosim_dpi_has_ops(void);

int cosim_uart_init(void);
void cosim_uart_close(void);

uint64_t cosim_uart_read(uint32_t offset, uint32_t size);
void cosim_uart_write(uint32_t offset, uint64_t data, uint32_t size);

#endif
