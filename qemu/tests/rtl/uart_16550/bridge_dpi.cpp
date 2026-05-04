#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

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
static int initialized = 0;

static void process_line(const char *line)
{
    if (line[0] == 'W') {
        unsigned offset = 0;
        unsigned long long data = 0;
        unsigned size = 0;

        if (sscanf(line, "W 0x%x 0x%llx %u", &offset, &data, &size) == 3) {
            printf("[BRIDGE] WRITE offset=0x%x data=0x%llx size=%u\n",
                   offset, data, size);
            fflush(stdout);
            sv_uart_write((int)offset, (uint64_t)data, (int)size);
        }
    } else if (line[0] == 'R') {
        unsigned offset = 0;
        unsigned size = 0;

        if (sscanf(line, "R 0x%x %u", &offset, &size) == 2) {
            unsigned long long val = 0;
            sv_uart_read((int)offset, (int)size, &val);

            char resp[64];
            snprintf(resp, sizeof(resp), "0x%llx\n",
                     val);

            printf("[BRIDGE] READ offset=0x%x size=%u -> 0x%llx\n",
                   offset, size, val);
            fflush(stdout);

            send(conn, resp, strlen(resp), 0);
        }
    }
}

extern "C" void bridge_init(void)
{
    if (initialized) {
        return;
    }

    setvbuf(stdout, NULL, _IONBF, 0);

    struct sockaddr_in addr;
    int opt = 1;

    srv = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(1234);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    bind(srv, (struct sockaddr *)&addr, sizeof(addr));
    listen(srv, 1);

    printf("[BRIDGE] waiting for connection...\n");
    fflush(stdout);
    conn = accept(srv, NULL, NULL);
    printf("[BRIDGE] connected\n");
    fflush(stdout);

    initialized = 1;
}

extern "C" void bridge_poll_once(void)
{
    char rxbuf[1024];
    static char linebuf[2048];
    static int line_len = 0;

    if (!initialized || conn < 0) {
        return;
    }

    int n = recv(conn, rxbuf, sizeof(rxbuf), MSG_DONTWAIT);
    if (n <= 0) {
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
}
