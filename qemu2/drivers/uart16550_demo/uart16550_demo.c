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

#define DRV_NAME "uart16550_demo"

/* MMIO */
static unsigned long base_addr = 0x10013000;
module_param(base_addr, ulong, 0644);

static unsigned long region_size = 0x1000;
module_param(region_size, ulong, 0644);

/* Registers */
/*
 * The RTL APB wrapper exposes 16550 registers as 32-bit words:
 * register index N is located at byte offset N * 4.
 */
#define UART_RBR 0x00
#define UART_THR 0x00
#define UART_DLL 0x00
#define UART_IER 0x04
#define UART_DLM 0x04
#define UART_IIR 0x08
#define UART_FCR 0x08
#define UART_LCR 0x0C
#define UART_MCR 0x10
#define UART_LSR 0x14
#define UART_MSR 0x18
#define UART_SCR 0x1C

#define UART_TX_COUNT 0x20
#define UART_RX_COUNT 0x24
#define UART_ERR_COUNT 0x28
#define UART_IRQ_COUNT 0x2C

#define UART_LCR_DLAB 0x80
#define UART_LSR_DR   0x01
#define UART_LSR_THRE 0x20

#define UART_IOCTL_MAGIC 'u'
#define UART_IOCTL_INIT_BASIC _IO(UART_IOCTL_MAGIC, 1)
#define UART_IOCTL_GET_STATS  _IOR(UART_IOCTL_MAGIC, 2, struct uart_stats)

struct uart_stats {
    u32 tx;
    u32 rx;
    u32 err;
    u32 irq;
};

struct dev_tiny {
    void __iomem *base;
    struct mutex lock;
};

static struct dev_tiny dev;

/* MMIO */
static inline u8 r8(u32 off){ return readb(dev.base + off); }
static inline void w8(u32 off, u8 v){ writeb(v, dev.base + off); }
static inline u32 r32(u32 off){ return readl(dev.base + off); }

static int wait_thr(void){
    int i;
    for(i=0;i<100000;i++){
        if(r8(UART_LSR) & UART_LSR_THRE) return 0;
        udelay(1);
    }
    return -1;
}

static void init_uart(void){
    w8(UART_LCR, 0x03);
    w8(UART_FCR, 0x07);
    w8(UART_LCR, 0x83);
    w8(UART_DLL, 1);
    w8(UART_DLM, 0);
    w8(UART_LCR, 0x03);
}

static ssize_t my_write(struct file *f, const char __user *buf, size_t len, loff_t *o){
    char c;
    size_t i;
    mutex_lock(&dev.lock);

    for(i=0;i<len;i++){
        if(copy_from_user(&c, buf+i, 1)){
            mutex_unlock(&dev.lock);
            return -EFAULT;
        }
        if(wait_thr()){
            mutex_unlock(&dev.lock);
            return -EIO;
        }
        w8(UART_THR, c);
    }

    mutex_unlock(&dev.lock);
    return len;
}

static ssize_t my_read(struct file *f, char __user *buf, size_t len, loff_t *o){
    char c;
    if(!(r8(UART_LSR) & UART_LSR_DR))
        return -EAGAIN;

    c = r8(UART_RBR);
    if(copy_to_user(buf, &c, 1))
        return -EFAULT;
    return 1;
}

static long my_ioctl(struct file *f, unsigned int cmd, unsigned long arg){
    struct uart_stats st;

    switch(cmd){
        case UART_IOCTL_INIT_BASIC:
            init_uart();
            return 0;

        case UART_IOCTL_GET_STATS:
            st.tx = r32(UART_TX_COUNT);
            st.rx = r32(UART_RX_COUNT);
            st.err = r32(UART_ERR_COUNT);
            st.irq = r32(UART_IRQ_COUNT);

            if(copy_to_user((void __user*)arg, &st, sizeof(st)))
                return -EFAULT;
            return 0;
    }
    return -ENOTTY;
}

static unsigned int my_poll(struct file *f, poll_table *p){
    unsigned int m = 0;
    u8 lsr = r8(UART_LSR);

    if(lsr & UART_LSR_DR)   m |= POLLIN;
    if(lsr & UART_LSR_THRE) m |= POLLOUT;

    return m;
}

static const struct file_operations fops = {
    .owner = THIS_MODULE,
    .read = my_read,
    .write = my_write,
    .unlocked_ioctl = my_ioctl,
    .poll = my_poll,
};

static struct miscdevice misc = {
    .minor = MISC_DYNAMIC_MINOR,
    .name = "uart16550_demo",
    .fops = &fops,
    .mode = 0666,
};

static int __init mod_init(void){
    mutex_init(&dev.lock);
    dev.base = ioremap(base_addr, region_size);
    if(!dev.base) return -ENOMEM;

    init_uart();
    misc_register(&misc);
    pr_info("uart driver loaded\n");
    return 0;
}

static void __exit mod_exit(void){
    misc_deregister(&misc);
    iounmap(dev.base);
    pr_info("uart driver unloaded\n");
}

module_init(mod_init);
module_exit(mod_exit);

MODULE_LICENSE("GPL");
