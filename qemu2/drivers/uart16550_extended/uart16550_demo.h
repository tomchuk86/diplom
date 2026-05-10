#ifndef UART16550_DEMO_H
#define UART16550_DEMO_H

/*
 * Userspace interface for uart16550_demo Linux kernel module.
 *
 * This header is intentionally verbose because it is used as a public API
 * between test applications and the kernel module. It mirrors the ioctl
 * structures used by the driver and documents the software-visible register
 * model of the project UART controller.
 */

#include <stdint.h>
#include <sys/ioctl.h>

#define UART16550_DEVICE_PATH "/dev/uart16550_demo"
#define UART16550_DEFAULT_BASE 0xff210000UL
#define UART16550_DEFAULT_REGION_SIZE 0x1000UL

/*
 * The RTL APB wrapper exposes 16550 registers as 32-bit words:
 * register index N is located at byte offset N * 4.
 */
#define UART_REG_RBR       0x00
#define UART_REG_THR       0x00
#define UART_REG_DLL       0x00
#define UART_REG_IER       0x04
#define UART_REG_DLM       0x04
#define UART_REG_IIR       0x08
#define UART_REG_FCR       0x08
#define UART_REG_LCR       0x0C
#define UART_REG_MCR       0x10
#define UART_REG_LSR       0x14
#define UART_REG_MSR       0x18
#define UART_REG_SCR       0x1C

/* Project-specific statistic registers. */
#define UART_REG_TX_COUNT  0x20
#define UART_REG_RX_COUNT  0x24
#define UART_REG_ERR_COUNT 0x28
#define UART_REG_IRQ_COUNT 0x2C

/* UART bit definitions used by tests and debug output. */
#define UART_LCR_DLAB      0x80
#define UART_MCR_LOOPBACK  0x10
#define UART_LSR_DR        0x01
#define UART_LSR_THRE      0x20
#define UART_LSR_TEMT      0x40

#define UART_IOCTL_MAGIC        'u'
#define UART_IOCTL_INIT_BASIC   _IO(UART_IOCTL_MAGIC, 1)
#define UART_IOCTL_GET_STATS    _IOR(UART_IOCTL_MAGIC, 2, struct uart_stats)
#define UART_IOCTL_GET_REGS     _IOR(UART_IOCTL_MAGIC, 3, struct uart_regs)
#define UART_IOCTL_SET_DIVISOR  _IOW(UART_IOCTL_MAGIC, 4, uint32_t)
#define UART_IOCTL_SET_LOOPBACK _IOW(UART_IOCTL_MAGIC, 5, uint32_t)
#define UART_IOCTL_RESET_STATS  _IO(UART_IOCTL_MAGIC, 6)
#define UART_IOCTL_RESET_FIFO   _IO(UART_IOCTL_MAGIC, 7)
#define UART_IOCTL_GET_CONFIG   _IOR(UART_IOCTL_MAGIC, 8, struct uart_config)
#define UART_IOCTL_SELF_TEST    _IOWR(UART_IOCTL_MAGIC, 9, struct uart_selftest)

/*
 * Hardware statistics exported by the QEMU/RTL UART model.
 */
struct uart_stats {
    uint32_t tx;
    uint32_t rx;
    uint32_t err;
    uint32_t irq;
};

/*
 * Standard software-visible UART registers.
 */
struct uart_regs {
    uint8_t ier;
    uint8_t iir;
    uint8_t lcr;
    uint8_t mcr;
    uint8_t lsr;
    uint8_t msr;
    uint8_t scr;
    uint8_t reserved;
};

/*
 * Driver runtime configuration and internal software counters.
 */
struct uart_config {
    uint32_t base_addr_low;
    uint32_t region_size;
    uint32_t loopback;
    uint32_t debug_level;
    uint32_t tx_timeout_us;
    uint32_t rx_timeout_us;
    uint32_t sw_reads;
    uint32_t sw_writes;
    uint32_t sw_ioctls;
    uint32_t sw_polls;
    uint32_t sw_errors;
    uint32_t sw_timeouts;
};

/*
 * Built-in self-test result.
 * The driver sends the requested pattern and optionally tries to read it back
 * when loopback is enabled in the UART model.
 */
struct uart_selftest {
    uint32_t pattern_len;
    uint32_t tx_ok;
    uint32_t rx_ok;
    uint32_t expected_rx;
    uint32_t actual_rx;
    uint32_t errors;
    char pattern[128];
};

#endif /* UART16550_DEMO_H */
