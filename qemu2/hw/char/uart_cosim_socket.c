#include "qemu/osdep.h"
#include "uart_cosim_socket.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

static int g_cosim_sock = -1;

int cosim_uart_init(void)
{
    struct sockaddr_in serv_addr;

    if (g_cosim_sock >= 0) {
        return 0;
    }

    g_cosim_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (g_cosim_sock < 0) {
        printf("[COSIM] socket create failed\n");
        return -1;
    }

    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(1234);

    if (inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr) <= 0) {
        printf("[COSIM] invalid address\n");
        close(g_cosim_sock);
        g_cosim_sock = -1;
        return -1;
    }

    if (connect(g_cosim_sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        printf("[COSIM] connect failed\n");
        close(g_cosim_sock);
        g_cosim_sock = -1;
        return -1;
    }

    printf("[COSIM] connected to bridge\n");
    return 0;
}

void cosim_uart_close(void)
{
    if (g_cosim_sock >= 0) {
        close(g_cosim_sock);
        g_cosim_sock = -1;
    }
}

void cosim_uart_write(uint32_t offset, uint64_t data, uint32_t size)
{
    char buf[128];
    int len;

    if (g_cosim_sock < 0) {
        printf("[COSIM] write skipped: not connected\n");
        return;
    }

    len = snprintf(buf, sizeof(buf),
                   "W 0x%x 0x%llx %u\n",
                   offset,
                   (unsigned long long)data,
                   size);

    send(g_cosim_sock, buf, len, 0);

    printf("[COSIM] WRITE offset=0x%x data=0x%llx size=%u\n",
           offset, (unsigned long long)data, size);
}

uint64_t cosim_uart_read(uint32_t offset, uint32_t size)
{
    char buf[128];
    char resp[128];
    int len;

    if (g_cosim_sock < 0) {
        printf("[COSIM] read skipped: not connected\n");
        return 0;
    }

    len = snprintf(buf, sizeof(buf),
                   "R 0x%x %u\n",
                   offset,
                   size);

    send(g_cosim_sock, buf, len, 0);

    len = recv(g_cosim_sock, resp, sizeof(resp) - 1, 0);
    if (len <= 0) {
        printf("[COSIM] read response failed\n");
        return 0;
    }

    resp[len] = '\0';

    uint64_t val = strtoull(resp, NULL, 0);

    printf("[COSIM] READ offset=0x%x size=%u -> 0x%llx\n",
           offset, size, (unsigned long long)val);

    return val;
}