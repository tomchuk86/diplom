#ifndef UART_COSIM_SOCKET_H
#define UART_COSIM_SOCKET_H

#include <stdint.h>

int cosim_uart_init(void);
void cosim_uart_close(void);

uint64_t cosim_uart_read(uint32_t offset, uint32_t size);
void cosim_uart_write(uint32_t offset, uint64_t data, uint32_t size);

#endif