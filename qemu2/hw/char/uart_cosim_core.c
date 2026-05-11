#include "qemu/osdep.h"
#include "hw/char/uart_cosim.h"
#include "hw/char/uart_cosim_backend.h"

#include <stdio.h>

typedef enum {
    COSIM_BACKEND_NONE = 0,
    COSIM_BACKEND_SOCKET,
    COSIM_BACKEND_DPI,
} CosimBackend;

static CosimBackend backend;

int cosim_uart_init(void)
{
    const char *e = g_getenv("UART16550_COSIM");

    backend = COSIM_BACKEND_NONE;

    if (!e || g_strcmp0(e, "0") == 0) {
        return -1;
    }

    if (g_strcmp0(e, "dpi") == 0) {
        if (uart_cosim_dpi_init() != 0) {
            return -1;
        }
        backend = COSIM_BACKEND_DPI;
        return 0;
    }

    /* UART16550_COSIM=1, socket, или любое другое ненулевое значение — TCP к bridge */
    if (uart_cosim_socket_init() != 0) {
        return -1;
    }
    backend = COSIM_BACKEND_SOCKET;
    return 0;
}

void cosim_uart_close(void)
{
    switch (backend) {
    case COSIM_BACKEND_SOCKET:
        uart_cosim_socket_close();
        break;
    case COSIM_BACKEND_DPI:
        uart_cosim_dpi_close();
        break;
    default:
        break;
    }
    backend = COSIM_BACKEND_NONE;
}

uint64_t cosim_uart_read(uint32_t offset, uint32_t size)
{
    switch (backend) {
    case COSIM_BACKEND_SOCKET:
        return uart_cosim_socket_read(offset, size);
    case COSIM_BACKEND_DPI:
        return uart_cosim_dpi_read(offset, size);
    default:
        return 0;
    }
}

void cosim_uart_write(uint32_t offset, uint64_t data, uint32_t size)
{
    switch (backend) {
    case COSIM_BACKEND_SOCKET:
        uart_cosim_socket_write(offset, data, size);
        break;
    case COSIM_BACKEND_DPI:
        uart_cosim_dpi_write(offset, data, size);
        break;
    default:
        break;
    }
}
