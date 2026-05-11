#ifndef HW_CHAR_UART_COSIM_LOG_H
#define HW_CHAR_UART_COSIM_LOG_H

#include <stdbool.h>
#include <stdint.h>

bool uart_cosim_should_log_mmio(uint32_t offset);
void uart_cosim_trace_write(uint32_t offset, uint64_t data, uint32_t size);
void uart_cosim_trace_read(uint32_t offset, uint32_t size, uint64_t val);

#endif
