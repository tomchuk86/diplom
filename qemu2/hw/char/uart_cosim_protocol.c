#include "hw/char/uart_cosim_protocol.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

static int fmt_line(char *buf, size_t buflen, const char *fmt, ...)
{
    va_list ap;
    int n;

    va_start(ap, fmt);
    n = vsnprintf(buf, buflen, fmt, ap);
    va_end(ap);

    return (n >= 0 && (size_t)n < buflen) ? n : -1;
}

const char *uart_cosim_op_name(UartCosimOp op)
{
    switch (op) {
    case UART_COSIM_OP_WRITE:
        return "W";
    case UART_COSIM_OP_READ:
        return "R";
    case UART_COSIM_OP_PING:
        return "PING";
    case UART_COSIM_OP_RESET:
        return "RESET";
    default:
        return "INVALID";
    }
}

static UartCosimOp parse_op_name(const char *op)
{
    if (strcmp(op, "W") == 0 || strcmp(op, "WRITE") == 0) {
        return UART_COSIM_OP_WRITE;
    }
    if (strcmp(op, "R") == 0 || strcmp(op, "READ") == 0) {
        return UART_COSIM_OP_READ;
    }
    if (strcmp(op, "PING") == 0) {
        return UART_COSIM_OP_PING;
    }
    if (strcmp(op, "RESET") == 0) {
        return UART_COSIM_OP_RESET;
    }
    return UART_COSIM_OP_INVALID;
}

const char *uart_cosim_status_name(UartCosimStatus status)
{
    switch (status) {
    case UART_COSIM_STATUS_OK:
        return "OK";
    case UART_COSIM_STATUS_ERR:
        return "ERR";
    case UART_COSIM_STATUS_TIMEOUT:
        return "TIMEOUT";
    default:
        return "ERR";
    }
}

static UartCosimStatus parse_status_name(const char *status)
{
    if (strcmp(status, "OK") == 0) {
        return UART_COSIM_STATUS_OK;
    }
    if (strcmp(status, "TIMEOUT") == 0) {
        return UART_COSIM_STATUS_TIMEOUT;
    }
    return UART_COSIM_STATUS_ERR;
}

int uart_cosim_fmt_write_line(char *buf, size_t buflen,
                              uint32_t offset, uint64_t data, uint32_t size)
{
    return fmt_line(buf, buflen, "W 0x%x 0x%llx %u\n",
                    offset, (unsigned long long)data, size);
}

int uart_cosim_fmt_read_req_line(char *buf, size_t buflen,
                                 uint32_t offset, uint32_t size)
{
    return fmt_line(buf, buflen, "R 0x%x %u\n", offset, size);
}

int uart_cosim_fmt_read_resp_line(char *buf, size_t buflen, uint64_t value)
{
    return fmt_line(buf, buflen, "0x%llx\n", (unsigned long long)value);
}

int uart_cosim_fmt_txn_write_line(char *buf, size_t buflen,
                                  uint32_t id, uint32_t offset,
                                  uint64_t data, uint32_t size,
                                  uint32_t timeout_cycles)
{
    return fmt_line(buf, buflen, "TXN %u W 0x%x 0x%llx %u %u\n",
                    id, offset, (unsigned long long)data, size,
                    timeout_cycles);
}

int uart_cosim_fmt_txn_read_line(char *buf, size_t buflen,
                                 uint32_t id, uint32_t offset,
                                 uint32_t size, uint32_t timeout_cycles)
{
    return fmt_line(buf, buflen, "TXN %u R 0x%x %u %u\n",
                    id, offset, size, timeout_cycles);
}

int uart_cosim_fmt_txn_control_line(char *buf, size_t buflen,
                                    uint32_t id, UartCosimOp op,
                                    uint32_t timeout_cycles)
{
    if (op != UART_COSIM_OP_PING && op != UART_COSIM_OP_RESET) {
        return -1;
    }

    return fmt_line(buf, buflen, "TXN %u %s %u\n",
                    id, uart_cosim_op_name(op), timeout_cycles);
}

int uart_cosim_fmt_txn_resp_line(char *buf, size_t buflen,
                                 uint32_t id, UartCosimStatus status,
                                 uint64_t value)
{
    return fmt_line(buf, buflen, "RSP %u %s 0x%llx\n",
                    id, uart_cosim_status_name(status),
                    (unsigned long long)value);
}

bool uart_cosim_parse_write_line(const char *line,
                                 uint32_t *offset, uint64_t *data, uint32_t *size)
{
    unsigned o = 0;
    unsigned long long d = 0;
    unsigned sz = 0;

    if (!line || sscanf(line, "W 0x%x 0x%llx %u", &o, &d, &sz) != 3) {
        return false;
    }
    *offset = o;
    *data = d;
    *size = sz;
    return true;
}

bool uart_cosim_parse_read_req_line(const char *line,
                                    uint32_t *offset, uint32_t *size)
{
    unsigned o = 0;
    unsigned sz = 0;

    if (!line || sscanf(line, "R 0x%x %u", &o, &sz) != 2) {
        return false;
    }
    *offset = o;
    *size = sz;
    return true;
}

bool uart_cosim_parse_read_resp_line(const char *line, uint64_t *value)
{
    char *end = NULL;
    unsigned long long v;

    if (!line || !value) {
        return false;
    }
    v = strtoull(line, &end, 0);
    if (end == line) {
        return false;
    }
    *value = v;
    return true;
}

bool uart_cosim_parse_txn_line(const char *line, UartCosimTxn *txn)
{
    char op_name[16];
    unsigned id = 0;
    unsigned offset = 0;
    unsigned size = 0;
    unsigned timeout = UART_COSIM_DEFAULT_TIMEOUT_CYCLES;
    unsigned long long data = 0;
    UartCosimOp op;

    if (!line || !txn ||
        sscanf(line, "TXN %u %15s", &id, op_name) != 2) {
        return false;
    }

    op = parse_op_name(op_name);
    memset(txn, 0, sizeof(*txn));
    txn->id = id;
    txn->op = op;
    txn->timeout_cycles = UART_COSIM_DEFAULT_TIMEOUT_CYCLES;

    switch (op) {
    case UART_COSIM_OP_WRITE:
        if (sscanf(line, "TXN %u %15s 0x%x 0x%llx %u %u",
                   &id, op_name, &offset, &data, &size, &timeout) != 6) {
            return false;
        }
        txn->offset = offset;
        txn->data = data;
        txn->size = size;
        txn->timeout_cycles = timeout;
        return true;

    case UART_COSIM_OP_READ:
        if (sscanf(line, "TXN %u %15s 0x%x %u %u",
                   &id, op_name, &offset, &size, &timeout) != 5) {
            return false;
        }
        txn->offset = offset;
        txn->size = size;
        txn->timeout_cycles = timeout;
        return true;

    case UART_COSIM_OP_PING:
    case UART_COSIM_OP_RESET:
        if (sscanf(line, "TXN %u %15s %u", &id, op_name, &timeout) < 2) {
            return false;
        }
        txn->timeout_cycles = timeout;
        return true;

    default:
        return false;
    }
}

bool uart_cosim_parse_txn_resp_line(const char *line, UartCosimResp *resp)
{
    char status_name[16];
    unsigned id = 0;
    unsigned long long value = 0;
    int fields;

    if (!line || !resp) {
        return false;
    }

    fields = sscanf(line, "RSP %u %15s 0x%llx",
                    &id, status_name, &value);
    if (fields < 2) {
        return false;
    }

    memset(resp, 0, sizeof(*resp));
    resp->id = id;
    resp->status = parse_status_name(status_name);
    resp->value = (fields == 3) ? value : 0;
    return true;
}
