#include "hw/char/uart_cosim_protocol.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int uart_cosim_fmt_write_line(char *buf, size_t buflen,
                              uint32_t offset, uint64_t data, uint32_t size)
{
    int n;

    n = snprintf(buf, buflen, "W 0x%x 0x%llx %u\n",
                 offset, (unsigned long long)data, size);
    return (n >= 0 && (size_t)n < buflen) ? n : -1;
}

int uart_cosim_fmt_read_req_line(char *buf, size_t buflen,
                                 uint32_t offset, uint32_t size)
{
    int n;

    n = snprintf(buf, buflen, "R 0x%x %u\n", offset, size);
    return (n >= 0 && (size_t)n < buflen) ? n : -1;
}

int uart_cosim_fmt_read_resp_line(char *buf, size_t buflen, uint64_t value)
{
    int n;

    n = snprintf(buf, buflen, "0x%llx\n", (unsigned long long)value);
    return (n >= 0 && (size_t)n < buflen) ? n : -1;
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
