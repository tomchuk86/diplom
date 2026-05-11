/*
 * UART 16550 QEMU <-> RTL cosimulation line protocol (shared by socket bridge and tests).
 */
#ifndef HW_CHAR_UART_COSIM_PROTOCOL_H
#define HW_CHAR_UART_COSIM_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define UART_COSIM_LSR_OFFSET 0x14

static inline bool uart_cosim_offset_verbose(unsigned offset)
{
    return offset != UART_COSIM_LSR_OFFSET;
}

/*
 * Format one-line requests/responses (newline-terminated over socket).
 * Returns characters written (excluding '\0') or -1 on truncation.
 */
int uart_cosim_fmt_write_line(char *buf, size_t buflen,
                              uint32_t offset, uint64_t data, uint32_t size);
int uart_cosim_fmt_read_req_line(char *buf, size_t buflen,
                                 uint32_t offset, uint32_t size);
int uart_cosim_fmt_read_resp_line(char *buf, size_t buflen, uint64_t value);

/*
 * Parse lines (may include trailing \r). Returns true on success.
 */
bool uart_cosim_parse_write_line(const char *line,
                                 uint32_t *offset, uint64_t *data, uint32_t *size);
bool uart_cosim_parse_read_req_line(const char *line,
                                    uint32_t *offset, uint32_t *size);
bool uart_cosim_parse_read_resp_line(const char *line, uint64_t *value);

#endif
