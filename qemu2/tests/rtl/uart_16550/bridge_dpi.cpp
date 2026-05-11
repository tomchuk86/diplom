#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

extern "C" {
#include "hw/char/uart_cosim_protocol.h"
}

#ifdef __cplusplus
extern "C" {
#endif

void sv_uart_read(int offset, int size, unsigned long long *data);
void sv_uart_write(int offset, uint64_t data, int size);

#ifdef __cplusplus
}
#endif

static int srv = -1;
static int conn = -1;
static int initialized;

static int bridge_log_level(void)
{
    static int lvl = -2;
    const char *e;

    if (lvl != -2) {
        return lvl;
    }
    e = getenv("UART_COSIM_LOG");
    if (!e) {
        lvl = 1;
    } else {
        lvl = atoi(e);
        if (lvl < 0) {
            lvl = 1;
        }
    }
    return lvl;
}

static bool bridge_should_log(unsigned offset)
{
    int l = bridge_log_level();

    if (l <= 0) {
        return false;
    }
    if (l >= 2) {
        return true;
    }
    return uart_cosim_offset_verbose(offset);
}

static void bridge_trace_write(unsigned offset, unsigned long long data,
                               unsigned size)
{
    if (bridge_should_log(offset)) {
        printf("[BRIDGE] WRITE offset=0x%x data=0x%llx size=%u\n",
               offset, data, size);
        fflush(stdout);
    }
}

static void bridge_trace_read(unsigned offset, unsigned size,
                              unsigned long long val)
{
    if (bridge_should_log(offset)) {
        printf("[BRIDGE] READ offset=0x%x size=%u -> 0x%llx\n",
               offset, size, val);
        fflush(stdout);
    }
}

static int bridge_send_all(int fd, const void *buf, size_t len)
{
    const char *p = (const char *)buf;
    size_t left = len;

    while (left > 0) {
        ssize_t n = send(fd, p, left, 0);

        if (n <= 0) {
            return -1;
        }
        p += n;
        left -= (size_t)n;
    }
    return 0;
}

static void process_line(const char *line)
{
    uint32_t offset = 0;
    uint64_t data = 0;
    uint32_t size = 0;

    if (line[0] == 'W') {
        if (!uart_cosim_parse_write_line(line, &offset, &data, &size)) {
            fprintf(stderr, "[BRIDGE] bad WRITE line: %s\n", line);
            return;
        }
        bridge_trace_write(offset, data, size);
        sv_uart_write((int)offset, (uint64_t)data, (int)size);
    } else if (line[0] == 'R') {
        if (!uart_cosim_parse_read_req_line(line, &offset, &size)) {
            fprintf(stderr, "[BRIDGE] bad READ line: %s\n", line);
            return;
        }
        unsigned long long val = 0;

        sv_uart_read((int)offset, (int)size, &val);

        char resp[64];

        uart_cosim_fmt_read_resp_line(resp, sizeof(resp), val);
        bridge_trace_read(offset, size, val);

        if (bridge_send_all(conn, resp, strlen(resp)) < 0) {
            fprintf(stderr, "[BRIDGE] send read response failed\n");
        }
    }
}

extern "C" void bridge_init(void)
{
    int opt = 1;
    struct sockaddr_in addr;

    if (initialized) {
        return;
    }

    setvbuf(stdout, NULL, _IONBF, 0);

    srv = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(1234);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    bind(srv, (struct sockaddr *)&addr, sizeof(addr));
    listen(srv, 1);

    printf("[BRIDGE] waiting for QEMU on 127.0.0.1:1234...\n");
    fflush(stdout);
    conn = accept(srv, NULL, NULL);
    printf("[BRIDGE] QEMU connected\n");
    fflush(stdout);

    initialized = 1;
}

extern "C" void bridge_poll_once(void)
{
    /*
     * tb_apb_uart вызывает bridge_poll_once на каждом posedge pclk, а sv_uart_write/read
     * внутри process_line ждут @(posedge pclk). Пока первый вызов «внутри» DPI не вернулся,
     * симулятор снова дёргает bridge_poll_once → параллельный recv/APB и тупик/обрыв сессии.
     * Удерживаем не более одного активного poll, пока SV-транзакция не завершилась.
     */
    static int in_bridge_poll;
    char rxbuf[1024];
    static char linebuf[2048];
    static int line_len;

    if (!initialized || conn < 0) {
        return;
    }
    if (in_bridge_poll) {
        return;
    }
    in_bridge_poll = 1;

    int n = recv(conn, rxbuf, sizeof(rxbuf), MSG_DONTWAIT);

    if (n <= 0) {
        in_bridge_poll = 0;
        return;
    }

    for (int i = 0; i < n; i++) {
        char c = rxbuf[i];
        if (c == '\n') {
            linebuf[line_len] = '\0';
            if (line_len > 0) {
                process_line(linebuf);
            }
            line_len = 0;
        } else {
            if (line_len < (int)sizeof(linebuf) - 1) {
                linebuf[line_len++] = c;
            }
        }
    }
    in_bridge_poll = 0;
}
