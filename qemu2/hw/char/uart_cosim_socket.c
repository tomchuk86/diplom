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

static int g_cosim_sock = -1;

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
        ssize_t n = recv(fd, &c, 1, 0);

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

    if (g_cosim_sock < 0) {
        printf("[COSIM socket] write skipped: not connected\n");
        return;
    }

    if (uart_cosim_fmt_write_line(buf, sizeof(buf), offset, data, size) < 0) {
        printf("[COSIM socket] write line overflow\n");
        return;
    }

    if (send_all(g_cosim_sock, buf, strlen(buf)) < 0) {
        printf("[COSIM socket] send failed\n");
        return;
    }

    uart_cosim_trace_write(offset, data, size);
}

uint64_t uart_cosim_socket_read(uint32_t offset, uint32_t size)
{
    char req[128];
    char resp[256];
    uint64_t val = 0;

    if (g_cosim_sock < 0) {
        printf("[COSIM socket] read skipped: not connected\n");
        return 0;
    }

    if (uart_cosim_fmt_read_req_line(req, sizeof(req), offset, size) < 0) {
        printf("[COSIM socket] read req overflow\n");
        return 0;
    }

    if (send_all(g_cosim_sock, req, strlen(req)) < 0) {
        printf("[COSIM socket] send read req failed\n");
        return 0;
    }

    if (recv_response_line(g_cosim_sock, resp, sizeof(resp)) < 0) {
        printf("[COSIM socket] read response failed\n");
        return 0;
    }

    if (!uart_cosim_parse_read_resp_line(resp, &val)) {
        printf("[COSIM socket] bad read response: %s\n", resp);
        return 0;
    }

    uart_cosim_trace_read(offset, size, val);
    return val;
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
