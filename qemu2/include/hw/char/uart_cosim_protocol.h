/*
 * UART 16550 QEMU <-> RTL cosimulation line protocol (shared by socket bridge
 * and tests).
 *
 * Legacy lines are kept for compatibility:
 *   W 0x<offset> 0x<data> <size>
 *   R 0x<offset> <size>
 *   0x<value>
 *
 * Transaction lines add ids, status and control operations:
 *   TXN <id> W 0x<offset> 0x<data> <size> <timeout_cycles>
 *   TXN <id> R 0x<offset> <size> <timeout_cycles>
 *   TXN <id> PING <timeout_cycles>
 *   TXN <id> RESET <timeout_cycles>
 *   RSP <id> OK|ERR|TIMEOUT 0x<value>
 */
#ifndef HW_CHAR_UART_COSIM_PROTOCOL_H
#define HW_CHAR_UART_COSIM_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define UART_COSIM_LSR_OFFSET 0x14
#define UART_COSIM_DEFAULT_TIMEOUT_CYCLES 100000u

typedef enum UartCosimOp {
    UART_COSIM_OP_INVALID = 0,
    UART_COSIM_OP_WRITE,
    UART_COSIM_OP_READ,
    UART_COSIM_OP_PING,
    UART_COSIM_OP_RESET,
} UartCosimOp;

typedef enum UartCosimStatus {
    UART_COSIM_STATUS_OK = 0,
    UART_COSIM_STATUS_ERR,
    UART_COSIM_STATUS_TIMEOUT,
} UartCosimStatus;

typedef struct UartCosimTxn {
    uint32_t id;
    UartCosimOp op;
    uint32_t offset;
    uint64_t data;
    uint32_t size;
    uint32_t timeout_cycles;
} UartCosimTxn;

typedef struct UartCosimResp {
    uint32_t id;
    UartCosimStatus status;
    uint64_t value;
} UartCosimResp;

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

int uart_cosim_fmt_txn_write_line(char *buf, size_t buflen,
                                  uint32_t id, uint32_t offset,
                                  uint64_t data, uint32_t size,
                                  uint32_t timeout_cycles);
int uart_cosim_fmt_txn_read_line(char *buf, size_t buflen,
                                 uint32_t id, uint32_t offset,
                                 uint32_t size, uint32_t timeout_cycles);
int uart_cosim_fmt_txn_control_line(char *buf, size_t buflen,
                                    uint32_t id, UartCosimOp op,
                                    uint32_t timeout_cycles);
int uart_cosim_fmt_txn_resp_line(char *buf, size_t buflen,
                                 uint32_t id, UartCosimStatus status,
                                 uint64_t value);

const char *uart_cosim_op_name(UartCosimOp op);
const char *uart_cosim_status_name(UartCosimStatus status);

/*
 * Parse lines (may include trailing \r). Returns true on success.
 */
bool uart_cosim_parse_write_line(const char *line,
                                 uint32_t *offset, uint64_t *data, uint32_t *size);
bool uart_cosim_parse_read_req_line(const char *line,
                                    uint32_t *offset, uint32_t *size);
bool uart_cosim_parse_read_resp_line(const char *line, uint64_t *value);
bool uart_cosim_parse_txn_line(const char *line, UartCosimTxn *txn);
bool uart_cosim_parse_txn_resp_line(const char *line, UartCosimResp *resp);

#endif
