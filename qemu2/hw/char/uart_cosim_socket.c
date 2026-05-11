#include "qemu/osdep.h"
#include "hw/char/uart_cosim_backend.h"
#include "hw/char/uart_cosim_protocol.h"
#include "hw/char/uart_cosim_log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef CONFIG_POSIX

#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/select.h>

static int g_cosim_sock = -1;
static uint32_t g_next_txn_id = 1;

static uint32_t cosim_next_txn_id(void)
{
    uint32_t id = g_next_txn_id++;

    if (g_next_txn_id == 0) {
        g_next_txn_id = 1;
    }
    return id;
}

static int cosim_socket_timeout_ms(void)
{
    static int timeout_ms = -1;
    const char *e;

    if (timeout_ms >= 0) {
        return timeout_ms;
    }

    e = g_getenv("UART_COSIM_TIMEOUT_MS");
    timeout_ms = e ? atoi(e) : 5000;
    if (timeout_ms < 100) {
        timeout_ms = 100;
    }
    return timeout_ms;
}

static uint32_t cosim_rtl_timeout_cycles(void)
{
    static uint32_t timeout_cycles;
    const char *e;

    if (timeout_cycles) {
        return timeout_cycles;
    }

    e = g_getenv("UART_COSIM_RTL_TIMEOUT_CYCLES");
    timeout_cycles = e ? (uint32_t)strtoul(e, NULL, 0)
                       : UART_COSIM_DEFAULT_TIMEOUT_CYCLES;
    if (!timeout_cycles) {
        timeout_cycles = UART_COSIM_DEFAULT_TIMEOUT_CYCLES;
    }
    return timeout_cycles;
}

static ssize_t send_all(int fd, const void *buf, size_t len)
{
    const char *p = buf;
    size_t left = len;

    while (left > 0) {
        ssize_t n = send(fd, p, left, 0);

        if (n <= 0) {
            return -1;
        }
        p += n;
        left -= (size_t)n;
    }
    return (ssize_t)len;
}

/*
 * Read until '\n' (handles split TCP segments).
 */
static int recv_response_line(int fd, char *buf, size_t maxlen)
{
    size_t pos = 0;

    while (pos < maxlen - 1) {
        char c;
        ssize_t n;
        fd_set rfds;
        struct timeval tv;
        int ready;

        FD_ZERO(&rfds);
        FD_SET(fd, &rfds);
        tv.tv_sec = cosim_socket_timeout_ms() / 1000;
        tv.tv_usec = (cosim_socket_timeout_ms() % 1000) * 1000;

        ready = select(fd + 1, &rfds, NULL, NULL, &tv);
        if (ready <= 0) {
            return -1;
        }

        n = recv(fd, &c, 1, 0);

        if (n <= 0) {
            return -1;
        }
        if (c == '\r') {
            continue;
        }
        if (c == '\n') {
            buf[pos] = '\0';
            return 0;
        }
        buf[pos++] = c;
    }
    return -1;
}

static bool send_txn_and_wait(uint32_t id, const char *line, UartCosimResp *resp)
{
    char resp_line[256];

    if (send_all(g_cosim_sock, line, strlen(line)) < 0) {
        printf("[COSIM socket] send failed for txn %u\n", id);
        return false;
    }

    if (recv_response_line(g_cosim_sock, resp_line, sizeof(resp_line)) < 0) {
        printf("[COSIM socket] timeout/no response for txn %u\n", id);
        return false;
    }

    if (!uart_cosim_parse_txn_resp_line(resp_line, resp)) {
        printf("[COSIM socket] bad txn response: %s\n", resp_line);
        return false;
    }

    if (resp->id != id) {
        printf("[COSIM socket] mismatched response id: got %u expected %u\n",
               resp->id, id);
        return false;
    }

    if (resp->status != UART_COSIM_STATUS_OK) {
        printf("[COSIM socket] txn %u failed: %s value=0x%llx\n",
               id, uart_cosim_status_name(resp->status),
               (unsigned long long)resp->value);
        return false;
    }

    return true;
}

static bool send_control_txn(UartCosimOp op)
{
    char req[128];
    UartCosimResp resp;
    uint32_t id = cosim_next_txn_id();

    if (uart_cosim_fmt_txn_control_line(req, sizeof(req), id, op,
                                        cosim_rtl_timeout_cycles()) < 0) {
        return false;
    }

    return send_txn_and_wait(id, req, &resp);
}

int uart_cosim_socket_init(void)
{
    struct sockaddr_in serv_addr;

    if (g_cosim_sock >= 0) {
        return 0;
    }

    g_cosim_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (g_cosim_sock < 0) {
        printf("[COSIM socket] socket create failed\n");
        return -1;
    }

    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(1234);

    if (inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr) <= 0) {
        printf("[COSIM socket] invalid address\n");
        close(g_cosim_sock);
        g_cosim_sock = -1;
        return -1;
    }

    if (connect(g_cosim_sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        printf("[COSIM socket] connect failed (start ModelSim run_cosim.do first)\n");
        close(g_cosim_sock);
        g_cosim_sock = -1;
        return -1;
    }

    printf("[COSIM socket] connected to 127.0.0.1:1234\n");
    if (!send_control_txn(UART_COSIM_OP_PING)) {
        printf("[COSIM socket] bridge protocol handshake failed\n");
        close(g_cosim_sock);
        g_cosim_sock = -1;
        return -1;
    }
    printf("[COSIM socket] enhanced transaction protocol active\n");
    return 0;
}

void uart_cosim_socket_close(void)
{
    if (g_cosim_sock >= 0) {
        close(g_cosim_sock);
        g_cosim_sock = -1;
    }
}

void uart_cosim_socket_write(uint32_t offset, uint64_t data, uint32_t size)
{
    char buf[128];
    UartCosimResp resp;
    uint32_t id;

    if (g_cosim_sock < 0) {
        printf("[COSIM socket] write skipped: not connected\n");
        return;
    }

    id = cosim_next_txn_id();
    if (uart_cosim_fmt_txn_write_line(buf, sizeof(buf), id, offset, data, size,
                                      cosim_rtl_timeout_cycles()) < 0) {
        printf("[COSIM socket] write line overflow\n");
        return;
    }

    if (!send_txn_and_wait(id, buf, &resp)) {
        return;
    }

    uart_cosim_trace_write(offset, data, size);
}

uint64_t uart_cosim_socket_read(uint32_t offset, uint32_t size)
{
    char req[128];
    UartCosimResp resp;
    uint32_t id;

    if (g_cosim_sock < 0) {
        printf("[COSIM socket] read skipped: not connected\n");
        return 0;
    }

    id = cosim_next_txn_id();
    if (uart_cosim_fmt_txn_read_line(req, sizeof(req), id, offset, size,
                                    cosim_rtl_timeout_cycles()) < 0) {
        printf("[COSIM socket] read req overflow\n");
        return 0;
    }

    if (!send_txn_and_wait(id, req, &resp)) {
        return 0;
    }

    uart_cosim_trace_read(offset, size, resp.value);
    return resp.value;
}

#else /* !CONFIG_POSIX */

int uart_cosim_socket_init(void)
{
    printf("[COSIM socket] unsupported on this host (POSIX sockets required)\n");
    return -1;
}

void uart_cosim_socket_close(void)
{
}

void uart_cosim_socket_write(uint32_t offset, uint64_t data, uint32_t size)
{
    (void)offset;
    (void)data;
    (void)size;
}

uint64_t uart_cosim_socket_read(uint32_t offset, uint32_t size)
{
    (void)offset;
    (void)size;
    return 0;
}

#endif /* CONFIG_POSIX */
