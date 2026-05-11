#ifndef HW_CHAR_UART_COSIM_BACKEND_H
#define HW_CHAR_UART_COSIM_BACKEND_H

#include <stdint.h>

int uart_cosim_socket_init(void);
void uart_cosim_socket_close(void);
uint64_t uart_cosim_socket_read(uint32_t offset, uint32_t size);
void uart_cosim_socket_write(uint32_t offset, uint64_t data, uint32_t size);

int uart_cosim_dpi_init(void);
void uart_cosim_dpi_close(void);
uint64_t uart_cosim_dpi_read(uint32_t offset, uint32_t size);
void uart_cosim_dpi_write(uint32_t offset, uint64_t data, uint32_t size);

#endif
