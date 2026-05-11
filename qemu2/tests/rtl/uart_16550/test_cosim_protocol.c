#include <assert.h>
#include <stdio.h>

#include "hw/char/uart_cosim_protocol.h"

int main(void)
{
    char buf[128];
    uint32_t o, sz;
    uint64_t d, v;

    assert(uart_cosim_fmt_write_line(buf, sizeof(buf), 0x0c, 0x83, 1) > 0);
    assert(uart_cosim_parse_write_line(buf, &o, &d, &sz));
    assert(o == 0x0c && d == 0x83 && sz == 1);

    assert(uart_cosim_fmt_read_req_line(buf, sizeof(buf), 0x14, 1) > 0);
    assert(uart_cosim_parse_read_req_line(buf, &o, &sz));
    assert(o == 0x14 && sz == 1);

    assert(uart_cosim_fmt_read_resp_line(buf, sizeof(buf), 0x3a) > 0);
    assert(uart_cosim_parse_read_resp_line(buf, &v));
    assert(v == 0x3a);

    printf("uart_cosim_protocol: all assertions passed\n");
    return 0;
}
