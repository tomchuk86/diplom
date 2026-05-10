#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/delay.h>
#include <linux/mutex.h>
#include <linux/ioctl.h>
#include <linux/poll.h>
#include <linux/types.h>
#include <linux/string.h>

#define DRV_NAME "uart16550_demo"
#define DRV_VERSION "2.0-diploma"

/* ------------------------------------------------------------------------- */
/* Module parameters                                                         */
/* ------------------------------------------------------------------------- */

static unsigned long base_addr = 0xff210000;
module_param(base_addr, ulong, 0644);
MODULE_PARM_DESC(base_addr, "UART MMIO base address");

static unsigned long region_size = 0x1000;
module_param(region_size, ulong, 0644);
MODULE_PARM_DESC(region_size, "UART MMIO region size");

static bool loopback = true;
module_param(loopback, bool, 0644);
MODULE_PARM_DESC(loopback, "Enable UART loopback mode during initialization");

static unsigned int debug_level = 2;
module_param(debug_level, uint, 0644);
MODULE_PARM_DESC(debug_level, "Debug level: 0=errors, 1=info, 2=verbose, 3=MMIO trace");

static unsigned int tx_timeout_us = 100000;
module_param(tx_timeout_us, uint, 0644);
MODULE_PARM_DESC(tx_timeout_us, "TX ready polling timeout in microseconds");

static unsigned int rx_timeout_us = 200000;
module_param(rx_timeout_us, uint, 0644);
MODULE_PARM_DESC(rx_timeout_us, "RX polling timeout in microseconds");

static unsigned int default_divisor = 27;
module_param(default_divisor, uint, 0644);
MODULE_PARM_DESC(default_divisor, "Default UART divisor value");

/* ------------------------------------------------------------------------- */
/* Register map                                                              */
/* ------------------------------------------------------------------------- */

/*
 * The RTL APB wrapper exposes 16550 registers as 32-bit words:
 * register index N is located at byte offset N * 4.
 */
#define UART_RBR        0x00
#define UART_THR        0x00
#define UART_DLL        0x00
#define UART_IER        0x04
#define UART_DLM        0x04
#define UART_IIR        0x08
#define UART_FCR        0x08
#define UART_LCR        0x0C
#define UART_MCR        0x10
#define UART_LSR        0x14
#define UART_MSR        0x18
#define UART_SCR        0x1C

#define UART_TX_COUNT   0x20
#define UART_RX_COUNT   0x24
#define UART_ERR_COUNT  0x28
#define UART_IRQ_COUNT  0x2C

#define UART_LCR_DLAB   0x80
#define UART_MCR_LOOPBACK 0x10
#define UART_LSR_DR     0x01
#define UART_LSR_THRE   0x20
#define UART_LSR_TEMT   0x40

#define UART_IOCTL_MAGIC        'u'
#define UART_IOCTL_INIT_BASIC   _IO(UART_IOCTL_MAGIC, 1)
#define UART_IOCTL_GET_STATS    _IOR(UART_IOCTL_MAGIC, 2, struct uart_stats)
#define UART_IOCTL_GET_REGS     _IOR(UART_IOCTL_MAGIC, 3, struct uart_regs)
#define UART_IOCTL_SET_DIVISOR  _IOW(UART_IOCTL_MAGIC, 4, u32)
#define UART_IOCTL_SET_LOOPBACK _IOW(UART_IOCTL_MAGIC, 5, u32)
#define UART_IOCTL_RESET_STATS  _IO(UART_IOCTL_MAGIC, 6)
#define UART_IOCTL_RESET_FIFO   _IO(UART_IOCTL_MAGIC, 7)
#define UART_IOCTL_GET_CONFIG   _IOR(UART_IOCTL_MAGIC, 8, struct uart_config)
#define UART_IOCTL_SELF_TEST    _IOWR(UART_IOCTL_MAGIC, 9, struct uart_selftest)

/* ------------------------------------------------------------------------- */
/* Public ioctl structures                                                   */
/* ------------------------------------------------------------------------- */

struct uart_stats {
    u32 tx;
    u32 rx;
    u32 err;
    u32 irq;
};

struct uart_regs {
    u8 ier;
    u8 iir;
    u8 lcr;
    u8 mcr;
    u8 lsr;
    u8 msr;
    u8 scr;
    u8 reserved;
};

struct uart_config {
    u32 base_addr_low;
    u32 region_size;
    u32 loopback;
    u32 debug_level;
    u32 tx_timeout_us;
    u32 rx_timeout_us;
    u32 sw_reads;
    u32 sw_writes;
    u32 sw_ioctls;
    u32 sw_polls;
    u32 sw_errors;
    u32 sw_timeouts;
};

struct uart_selftest {
    u32 pattern_len;
    u32 tx_ok;
    u32 rx_ok;
    u32 expected_rx;
    u32 actual_rx;
    u32 errors;
    char pattern[128];
};

/* ------------------------------------------------------------------------- */
/* Driver state                                                              */
/* ------------------------------------------------------------------------- */

struct uart_sw_counters {
    u32 reads;
    u32 writes;
    u32 ioctls;
    u32 polls;
    u32 errors;
    u32 timeouts;
    u32 bytes_written;
    u32 bytes_read;
};

struct uart_demo_dev {
    void __iomem *base;
    struct mutex lock;
    bool initialized;
    bool loopback_enabled;
    u16 divisor;
    struct uart_sw_counters sw;
};

static struct uart_demo_dev dev;

/* ------------------------------------------------------------------------- */
/* Logging helpers                                                           */
/* ------------------------------------------------------------------------- */

#define uart_err(fmt, ...) \
    pr_err(DRV_NAME ": " fmt, ##__VA_ARGS__)

#define uart_info(fmt, ...) \
    do { if (debug_level >= 1) pr_info(DRV_NAME ": " fmt, ##__VA_ARGS__); } while (0)

#define uart_dbg(fmt, ...) \
    do { if (debug_level >= 2) pr_info(DRV_NAME ": " fmt, ##__VA_ARGS__); } while (0)

#define uart_trace(fmt, ...) \
    do { if (debug_level >= 3) pr_info(DRV_NAME ": " fmt, ##__VA_ARGS__); } while (0)

static const char *uart_reg_name(u32 off)
{
    switch (off) {
    case UART_RBR: return "RBR/THR/DLL";
    case UART_IER: return "IER/DLM";
    case UART_IIR: return "IIR/FCR";
    case UART_LCR: return "LCR";
    case UART_MCR: return "MCR";
    case UART_LSR: return "LSR";
    case UART_MSR: return "MSR";
    case UART_SCR: return "SCR";
    case UART_TX_COUNT: return "TX_COUNT";
    case UART_RX_COUNT: return "RX_COUNT";
    case UART_ERR_COUNT: return "ERR_COUNT";
    case UART_IRQ_COUNT: return "IRQ_COUNT";
    default: return "UNKNOWN";
    }
}

/* ------------------------------------------------------------------------- */
/* Low-level MMIO access                                                     */
/* ------------------------------------------------------------------------- */

static inline u8 uart_read8(u32 off)
{
    u8 v = readb(dev.base + off);
    uart_trace("read8 %-12s off=0x%02x val=0x%02x\n", uart_reg_name(off), off, v);
    return v;
}

static inline void uart_write8(u32 off, u8 v)
{
    uart_trace("write8 %-11s off=0x%02x val=0x%02x\n", uart_reg_name(off), off, v);
    writeb(v, dev.base + off);
}

static inline u32 uart_read32(u32 off)
{
    u32 v = readl(dev.base + off);
    uart_trace("read32 %-11s off=0x%02x val=0x%08x\n", uart_reg_name(off), off, v);
    return v;
}

static inline void uart_write32(u32 off, u32 v)
{
    uart_trace("write32 %-10s off=0x%02x val=0x%08x\n", uart_reg_name(off), off, v);
    writel(v, dev.base + off);
}

/* ------------------------------------------------------------------------- */
/* UART helpers                                                              */
/* ------------------------------------------------------------------------- */

static int uart_wait_lsr(u8 mask, bool set, unsigned int timeout_us)
{
    unsigned int i;
    u8 lsr;

    for (i = 0; i < timeout_us; i++) {
        lsr = uart_read8(UART_LSR);

        if (set) {
            if (lsr & mask)
                return 0;
        } else {
            if (!(lsr & mask))
                return 0;
        }

        udelay(1);
    }

    dev.sw.timeouts++;
    uart_err("timeout waiting LSR mask=0x%02x set=%d last_lsr=0x%02x\n",
             mask, set, lsr);
    return -ETIMEDOUT;
}

static int uart_wait_tx_ready(void)
{
    return uart_wait_lsr(UART_LSR_THRE, true, tx_timeout_us);
}

static int uart_wait_rx_ready(unsigned int timeout_us)
{
    return uart_wait_lsr(UART_LSR_DR, true, timeout_us);
}

static void uart_set_dlab(bool enable)
{
    u8 lcr = uart_read8(UART_LCR);

    if (enable)
        lcr |= UART_LCR_DLAB;
    else
        lcr &= ~UART_LCR_DLAB;

    uart_write8(UART_LCR, lcr);
    uart_dbg("DLAB %s, LCR=0x%02x\n", enable ? "enabled" : "disabled", lcr);
}

static void uart_set_divisor_hw(u16 divisor)
{
    if (divisor == 0)
        divisor = 1;

    uart_set_dlab(true);
    uart_write8(UART_DLL, divisor & 0xff);
    uart_write8(UART_DLM, (divisor >> 8) & 0xff);
    uart_set_dlab(false);

    dev.divisor = divisor;
    uart_info("divisor set to %u\n", divisor);
}

static void uart_reset_fifo_hw(void)
{
    /* FIFO enable + reset RX + reset TX */
    uart_write8(UART_FCR, 0x07);
    uart_dbg("FIFO reset requested through FCR=0x07\n");
}

static void uart_reset_stats_hw(void)
{
    uart_write32(UART_TX_COUNT, 0);
    uart_write32(UART_RX_COUNT, 0);
    uart_write32(UART_ERR_COUNT, 0);
    uart_write32(UART_IRQ_COUNT, 0);
    uart_dbg("hardware statistic counters reset\n");
}

static void uart_set_loopback_hw(bool enable)
{
    u8 mcr = enable ? UART_MCR_LOOPBACK : 0x00;

    uart_write8(UART_MCR, mcr);
    dev.loopback_enabled = enable;
    uart_info("loopback %s\n", enable ? "enabled" : "disabled");
}

static void uart_init_hw(void)
{
    uart_info("basic init started\n");

    /* 8 data bits, no parity, 1 stop bit */
    uart_write8(UART_LCR, 0x03);

    uart_reset_fifo_hw();
    uart_set_divisor_hw((u16)default_divisor);
    uart_write8(UART_LCR, 0x03);
    uart_set_loopback_hw(loopback);
    uart_reset_fifo_hw();
    uart_reset_stats_hw();

    /* Scratch register is used as a quick sanity marker. */
    uart_write8(UART_SCR, 0x5A);

    dev.initialized = true;
    uart_info("basic init finished: divisor=%u loopback=%d\n",
              dev.divisor, dev.loopback_enabled);
}

static void uart_get_stats_hw(struct uart_stats *st)
{
    st->tx = uart_read32(UART_TX_COUNT);
    st->rx = uart_read32(UART_RX_COUNT);
    st->err = uart_read32(UART_ERR_COUNT);
    st->irq = uart_read32(UART_IRQ_COUNT);
}

static void uart_get_regs_hw(struct uart_regs *r)
{
    r->ier = uart_read8(UART_IER);
    r->iir = uart_read8(UART_IIR);
    r->lcr = uart_read8(UART_LCR);
    r->mcr = uart_read8(UART_MCR);
    r->lsr = uart_read8(UART_LSR);
    r->msr = uart_read8(UART_MSR);
    r->scr = uart_read8(UART_SCR);
    r->reserved = 0;
}

static void uart_get_config_sw(struct uart_config *cfg)
{
    cfg->base_addr_low = (u32)base_addr;
    cfg->region_size = (u32)region_size;
    cfg->loopback = dev.loopback_enabled ? 1 : 0;
    cfg->debug_level = debug_level;
    cfg->tx_timeout_us = tx_timeout_us;
    cfg->rx_timeout_us = rx_timeout_us;
    cfg->sw_reads = dev.sw.reads;
    cfg->sw_writes = dev.sw.writes;
    cfg->sw_ioctls = dev.sw.ioctls;
    cfg->sw_polls = dev.sw.polls;
    cfg->sw_errors = dev.sw.errors;
    cfg->sw_timeouts = dev.sw.timeouts;
}

static int uart_put_byte_locked(u8 byte)
{
    int ret = uart_wait_tx_ready();

    if (ret)
        return ret;

    uart_write8(UART_THR, byte);
    dev.sw.bytes_written++;
    return 0;
}

static int uart_get_byte_locked(u8 *byte, bool nonblock)
{
    int ret;

    if (uart_read8(UART_LSR) & UART_LSR_DR) {
        *byte = uart_read8(UART_RBR);
        dev.sw.bytes_read++;
        return 1;
    }

    if (nonblock)
        return -EAGAIN;

    ret = uart_wait_rx_ready(rx_timeout_us);
    if (ret)
        return ret;

    *byte = uart_read8(UART_RBR);
    dev.sw.bytes_read++;
    return 1;
}

static int uart_self_test_locked(struct uart_selftest *t)
{
    u32 i;
    u8 rx;
    int ret;
    u32 len;

    len = t->pattern_len;
    if (len == 0 || len > sizeof(t->pattern)) {
        static const char default_pattern[] = "UART16550_SELFTEST";
        len = sizeof(default_pattern) - 1;
        memcpy(t->pattern, default_pattern, len);
    }

    t->pattern_len = len;
    t->tx_ok = 0;
    t->rx_ok = 0;
    t->expected_rx = len;
    t->actual_rx = 0;
    t->errors = 0;

    uart_reset_fifo_hw();

    for (i = 0; i < len; i++) {
        ret = uart_put_byte_locked(t->pattern[i]);
        if (ret) {
            t->errors++;
            return ret;
        }
        t->tx_ok++;
    }

    if (!dev.loopback_enabled)
        return 0;

    for (i = 0; i < len; i++) {
        ret = uart_get_byte_locked(&rx, false);
        if (ret < 0) {
            t->errors++;
            return ret;
        }

        t->actual_rx++;
        if (rx == (u8)t->pattern[i])
            t->rx_ok++;
        else
            t->errors++;
    }

    return t->errors ? -EIO : 0;
}

/* ------------------------------------------------------------------------- */
/* File operations                                                           */
/* ------------------------------------------------------------------------- */

static ssize_t uart_demo_write(struct file *f, const char __user *buf,
                               size_t len, loff_t *off)
{
    size_t i;
    char c;
    int ret;

    if (len == 0)
        return 0;

    mutex_lock(&dev.lock);
    dev.sw.writes++;

    for (i = 0; i < len; i++) {
        if (copy_from_user(&c, buf + i, 1)) {
            dev.sw.errors++;
            mutex_unlock(&dev.lock);
            return -EFAULT;
        }

        ret = uart_put_byte_locked((u8)c);
        if (ret) {
            dev.sw.errors++;
            mutex_unlock(&dev.lock);
            return i ? (ssize_t)i : ret;
        }
    }

    uart_dbg("write completed: requested=%zu bytes_written_total=%u\n",
             len, dev.sw.bytes_written);

    mutex_unlock(&dev.lock);
    return len;
}

static ssize_t uart_demo_read(struct file *f, char __user *buf,
                              size_t len, loff_t *off)
{
    size_t i;
    u8 c;
    int ret;
    bool nonblock = !!(f->f_flags & O_NONBLOCK);

    if (len == 0)
        return 0;

    mutex_lock(&dev.lock);
    dev.sw.reads++;

    for (i = 0; i < len; i++) {
        ret = uart_get_byte_locked(&c, nonblock || i > 0);
        if (ret < 0) {
            if (ret != -EAGAIN)
                dev.sw.errors++;
            mutex_unlock(&dev.lock);
            return i ? (ssize_t)i : ret;
        }

        if (copy_to_user(buf + i, &c, 1)) {
            dev.sw.errors++;
            mutex_unlock(&dev.lock);
            return -EFAULT;
        }
    }

    uart_dbg("read completed: requested=%zu bytes_read_now=%zu bytes_read_total=%u\n",
             len, i, dev.sw.bytes_read);

    mutex_unlock(&dev.lock);
    return i;
}

static long uart_demo_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
    struct uart_stats st;
    struct uart_regs regs;
    struct uart_config cfg;
    struct uart_selftest selftest;
    u32 value;
    int ret = 0;

    mutex_lock(&dev.lock);
    dev.sw.ioctls++;

    switch (cmd) {
    case UART_IOCTL_INIT_BASIC:
        uart_init_hw();
        break;

    case UART_IOCTL_GET_STATS:
        uart_get_stats_hw(&st);
        mutex_unlock(&dev.lock);
        if (copy_to_user((void __user *)arg, &st, sizeof(st)))
            return -EFAULT;
        return 0;

    case UART_IOCTL_GET_REGS:
        uart_get_regs_hw(&regs);
        mutex_unlock(&dev.lock);
        if (copy_to_user((void __user *)arg, &regs, sizeof(regs)))
            return -EFAULT;
        return 0;

    case UART_IOCTL_SET_DIVISOR:
        mutex_unlock(&dev.lock);
        if (copy_from_user(&value, (void __user *)arg, sizeof(value)))
            return -EFAULT;
        mutex_lock(&dev.lock);
        uart_set_divisor_hw((u16)value);
        break;

    case UART_IOCTL_SET_LOOPBACK:
        mutex_unlock(&dev.lock);
        if (copy_from_user(&value, (void __user *)arg, sizeof(value)))
            return -EFAULT;
        mutex_lock(&dev.lock);
        uart_set_loopback_hw(value ? true : false);
        break;

    case UART_IOCTL_RESET_STATS:
        uart_reset_stats_hw();
        memset(&dev.sw, 0, sizeof(dev.sw));
        break;

    case UART_IOCTL_RESET_FIFO:
        uart_reset_fifo_hw();
        break;

    case UART_IOCTL_GET_CONFIG:
        uart_get_config_sw(&cfg);
        mutex_unlock(&dev.lock);
        if (copy_to_user((void __user *)arg, &cfg, sizeof(cfg)))
            return -EFAULT;
        return 0;

    case UART_IOCTL_SELF_TEST:
        mutex_unlock(&dev.lock);
        if (copy_from_user(&selftest, (void __user *)arg, sizeof(selftest)))
            return -EFAULT;
        mutex_lock(&dev.lock);
        ret = uart_self_test_locked(&selftest);
        mutex_unlock(&dev.lock);
        if (copy_to_user((void __user *)arg, &selftest, sizeof(selftest)))
            return -EFAULT;
        return ret;

    default:
        dev.sw.errors++;
        ret = -ENOTTY;
        break;
    }

    mutex_unlock(&dev.lock);
    return ret;
}

static unsigned int uart_demo_poll(struct file *f, poll_table *p)
{
    unsigned int mask = 0;
    u8 lsr;

    mutex_lock(&dev.lock);
    dev.sw.polls++;

    lsr = uart_read8(UART_LSR);
    if (lsr & UART_LSR_DR)
        mask |= POLLIN | POLLRDNORM;
    if (lsr & UART_LSR_THRE)
        mask |= POLLOUT | POLLWRNORM;

    mutex_unlock(&dev.lock);
    return mask;
}

static int uart_demo_open(struct inode *inode, struct file *file)
{
    uart_dbg("device opened\n");
    return 0;
}

static int uart_demo_release(struct inode *inode, struct file *file)
{
    uart_dbg("device closed\n");
    return 0;
}

static const struct file_operations uart_fops = {
    .owner = THIS_MODULE,
    .open = uart_demo_open,
    .release = uart_demo_release,
    .read = uart_demo_read,
    .write = uart_demo_write,
    .unlocked_ioctl = uart_demo_ioctl,
    .poll = uart_demo_poll,
    .llseek = no_llseek,
};

static struct miscdevice uart_misc = {
    .minor = MISC_DYNAMIC_MINOR,
    .name = "uart16550_demo",
    .fops = &uart_fops,
    .mode = 0666,
};

/* ------------------------------------------------------------------------- */
/* Module init / exit                                                        */
/* ------------------------------------------------------------------------- */

static int __init uart_module_init(void)
{
    int ret;

    memset(&dev, 0, sizeof(dev));
    mutex_init(&dev.lock);
    dev.loopback_enabled = loopback;
    dev.divisor = (u16)default_divisor;

    dev.base = ioremap(base_addr, region_size);
    if (!dev.base) {
        uart_err("ioremap failed: base=0x%lx size=0x%lx\n", base_addr, region_size);
        return -ENOMEM;
    }

    uart_init_hw();

    ret = misc_register(&uart_misc);
    if (ret) {
        uart_err("misc_register failed: %d\n", ret);
        iounmap(dev.base);
        return ret;
    }

    uart_info("loaded version=%s base=0x%lx size=0x%lx loopback=%d debug=%u\n",
              DRV_VERSION, base_addr, region_size, dev.loopback_enabled, debug_level);
    uart_info("device node: /dev/%s\n", uart_misc.name);
    return 0;
}

static void __exit uart_module_exit(void)
{
    uart_info("unloading: sw_reads=%u sw_writes=%u bytes_in=%u bytes_out=%u errors=%u timeouts=%u\n",
              dev.sw.reads, dev.sw.writes, dev.sw.bytes_read,
              dev.sw.bytes_written, dev.sw.errors, dev.sw.timeouts);

    misc_deregister(&uart_misc);

    if (dev.base)
        iounmap(dev.base);

    uart_info("unloaded\n");
}

module_init(uart_module_init);
module_exit(uart_module_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Diploma project, student 4");
MODULE_DESCRIPTION("Expanded MMIO UART16550-compatible driver for QEMU/FPGA SoC");
MODULE_VERSION(DRV_VERSION);
