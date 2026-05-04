#ifndef UART_DEMO_H
#define UART_DEMO_H

#include <stdint.h>
#include <sys/ioctl.h>

#define UART_IOCTL_MAGIC 'u'
#define UART_IOCTL_INIT_BASIC _IO(UART_IOCTL_MAGIC, 1)
#define UART_IOCTL_GET_STATS  _IOR(UART_IOCTL_MAGIC, 2, struct uart_stats)

struct uart_stats {
    uint32_t tx;
    uint32_t rx;
    uint32_t err;
    uint32_t irq;
};

#endif
