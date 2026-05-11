#include <assert.h>
#include <stdio.h>

#include "hw/char/uart_cosim_protocol.h"

int main(void)
{
    char buf[128];
    uint32_t o, sz;
    uint64_t d, v;
    UartCosimTxn txn;
    UartCosimResp resp;

    assert(uart_cosim_fmt_write_line(buf, sizeof(buf), 0x0c, 0x83, 1) > 0);
    assert(uart_cosim_parse_write_line(buf, &o, &d, &sz));
    assert(o == 0x0c && d == 0x83 && sz == 1);

    assert(uart_cosim_fmt_read_req_line(buf, sizeof(buf), 0x14, 1) > 0);
    assert(uart_cosim_parse_read_req_line(buf, &o, &sz));
    assert(o == 0x14 && sz == 1);

    assert(uart_cosim_fmt_read_resp_line(buf, sizeof(buf), 0x3a) > 0);
    assert(uart_cosim_parse_read_resp_line(buf, &v));
    assert(v == 0x3a);

    assert(uart_cosim_fmt_txn_write_line(buf, sizeof(buf), 7, 0x0c, 0x83,
                                         1, 1000) > 0);
    assert(uart_cosim_parse_txn_line(buf, &txn));
    assert(txn.id == 7 && txn.op == UART_COSIM_OP_WRITE);
    assert(txn.offset == 0x0c && txn.data == 0x83);
    assert(txn.size == 1 && txn.timeout_cycles == 1000);

    assert(uart_cosim_fmt_txn_read_line(buf, sizeof(buf), 8, 0x14,
                                        1, 1000) > 0);
    assert(uart_cosim_parse_txn_line(buf, &txn));
    assert(txn.id == 8 && txn.op == UART_COSIM_OP_READ);
    assert(txn.offset == 0x14 && txn.size == 1);

    assert(uart_cosim_fmt_txn_control_line(buf, sizeof(buf), 9,
                                           UART_COSIM_OP_PING, 1000) > 0);
    assert(uart_cosim_parse_txn_line(buf, &txn));
    assert(txn.id == 9 && txn.op == UART_COSIM_OP_PING);

    assert(uart_cosim_fmt_txn_control_line(buf, sizeof(buf), 10,
                                           UART_COSIM_OP_RESET, 1000) > 0);
    assert(uart_cosim_parse_txn_line(buf, &txn));
    assert(txn.id == 10 && txn.op == UART_COSIM_OP_RESET);

    assert(uart_cosim_fmt_txn_resp_line(buf, sizeof(buf), 11,
                                        UART_COSIM_STATUS_OK, 0x55) > 0);
    assert(uart_cosim_parse_txn_resp_line(buf, &resp));
    assert(resp.id == 11 && resp.status == UART_COSIM_STATUS_OK);
    assert(resp.value == 0x55);

    printf("uart_cosim_protocol: all assertions passed\n");
    return 0;
}
