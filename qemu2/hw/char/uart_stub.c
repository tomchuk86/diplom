#include "qemu/osdep.h"
#include "hw/core/sysbus.h"
#include "qom/object.h"
#include "system/memory.h"
#include "qapi/error.h"
#include "hw/char/uart_cosim_socket.h"

#define TYPE_UART_STUB "uart-stub"
OBJECT_DECLARE_SIMPLE_TYPE(UARTStubState, UART_STUB)

/* =========================
 * UART 16550A register map
 * ========================= */
#define UART_REG_RBR_THR_DLL  0x00
#define UART_REG_IER_DLM      0x01
#define UART_REG_IIR_FCR      0x02
#define UART_REG_LCR          0x03
#define UART_REG_MCR          0x04
#define UART_REG_LSR          0x05
#define UART_REG_MSR          0x06
#define UART_REG_SCR          0x07

/* Custom diagnostic/statistic registers */
#define UART_REG_TX_COUNT     0x20
#define UART_REG_RX_COUNT     0x24
#define UART_REG_ERR_COUNT    0x28
#define UART_REG_IRQ_COUNT    0x2C

/* =========================
 * Bit definitions
 * ========================= */
#define UART_LCR_DLAB         0x80

#define UART_LSR_DR           0x01
#define UART_LSR_THRE         0x20
#define UART_LSR_TEMT         0x40

#define UART_IER_RDA          0x01
#define UART_IER_THRE         0x02

#define UART_IIR_NO_INT       0x01
#define UART_IIR_THRE_SRC     0x02
#define UART_IIR_RDA_SRC      0x04

/* =========================
 * Build-time switches
 * ========================= */
#define UART_STUB_SELFTEST    1
#define UART_STUB_COSIM       1

#define UART_FIFO_SIZE        16

typedef struct UARTStubState {
    SysBusDevice parent_obj;
    MemoryRegion mmio;

    /* Standard UART 16550A visible registers */
    uint8_t ier;
    uint8_t iir;
    uint8_t fcr;
    uint8_t lcr;
    uint8_t mcr;
    uint8_t lsr;
    uint8_t msr;
    uint8_t scr;
    uint8_t dll;
    uint8_t dlm;

    /* Simplified FIFOs */
    uint8_t rx_fifo[UART_FIFO_SIZE];
    uint8_t tx_fifo[UART_FIFO_SIZE];
    uint32_t rx_head;
    uint32_t rx_tail;
    uint32_t rx_count_fifo;
    uint32_t tx_head;
    uint32_t tx_tail;
    uint32_t tx_count_fifo;

    /* Last transferred bytes, useful for debug */
    uint8_t last_rbr;
    uint8_t last_thr;

    /* Diagnostic/statistic registers */
    uint32_t tx_count;
    uint32_t rx_count;
    uint32_t err_count;
    uint32_t irq_count;
    bool cosim_connected;
} UARTStubState;

/* =========================================================
 * Helper functions
 * ========================================================= */

static void uart_update_interrupt(UARTStubState *s)
{
    uint8_t old_iir = s->iir;
    uint8_t new_iir = UART_IIR_NO_INT;

    /*
     * Simplified priority:
     * 1) RX data available
     * 2) THR empty
     */
    if ((s->ier & UART_IER_RDA) && (s->rx_count_fifo > 0)) {
        new_iir = UART_IIR_RDA_SRC;
    } else if ((s->ier & UART_IER_THRE) && (s->lsr & UART_LSR_THRE)) {
        new_iir = UART_IIR_THRE_SRC;
    }

    s->iir = new_iir;

    /*
     * Count newly appeared pending interrupts.
     * old: no interrupt, new: interrupt pending
     */
    if ((old_iir & UART_IIR_NO_INT) && !(new_iir & UART_IIR_NO_INT)) {
        s->irq_count++;
        printf("UART16550: interrupt pending, IIR=0x%02x, IRQ_COUNT=%u\n",
               s->iir, s->irq_count);
    }
}

static void uart_update_lsr(UARTStubState *s)
{
    /* Data ready */
    if (s->rx_count_fifo > 0) {
        s->lsr |= UART_LSR_DR;
    } else {
        s->lsr &= ~UART_LSR_DR;
    }

    /* TX holding register empty / transmitter empty */
    if (s->tx_count_fifo == 0) {
        s->lsr |= UART_LSR_THRE;
        s->lsr |= UART_LSR_TEMT;
    } else {
        s->lsr &= ~UART_LSR_THRE;
        s->lsr &= ~UART_LSR_TEMT;
    }

    uart_update_interrupt(s);
}

static void uart_reset_rx_fifo(UARTStubState *s)
{
    s->rx_head = 0;
    s->rx_tail = 0;
    s->rx_count_fifo = 0;
    uart_update_lsr(s);
}

static void uart_reset_tx_fifo(UARTStubState *s)
{
    s->tx_head = 0;
    s->tx_tail = 0;
    s->tx_count_fifo = 0;
    uart_update_lsr(s);
}

static void uart_push_rx(UARTStubState *s, uint8_t value)
{
    if (s->rx_count_fifo >= UART_FIFO_SIZE) {
        s->err_count++;
        printf("UART16550: RX FIFO overflow\n");
        return;
    }
    s->rx_fifo[s->rx_tail] = value;
    s->rx_tail = (s->rx_tail + 1) % UART_FIFO_SIZE;
    s->rx_count_fifo++;
    s->rx_count++;
    s->last_rbr = value;

    uart_update_lsr(s);

    printf("UART16550: receive byte 0x%02x ('%c'), RX FIFO count=%u\n",
           value, (char)value, s->rx_count_fifo);
}

static uint8_t uart_pop_rx(UARTStubState *s)
{
    uint8_t value;

    if (s->rx_count_fifo == 0) {
        printf("UART16550: RX FIFO empty\n");
        uart_update_lsr(s);
        return 0x00;
    }

    value = s->rx_fifo[s->rx_head];
    s->rx_head = (s->rx_head + 1) % UART_FIFO_SIZE;
    s->rx_count_fifo--;

    uart_update_lsr(s);
    return value;
}

static void uart_push_tx(UARTStubState *s, uint8_t value)
{
    if (s->tx_count_fifo >= UART_FIFO_SIZE) {
        s->err_count++;
        printf("UART16550: TX FIFO overflow\n");
        return;
    }

    s->tx_fifo[s->tx_tail] = value;
    s->tx_tail = (s->tx_tail + 1) % UART_FIFO_SIZE;
    s->tx_count_fifo++;
    s->tx_count++;
    s->last_thr = value;

    uart_update_lsr(s);

    printf("UART16550: write THR = 0x%02x ('%c'), TX FIFO count=%u\n",
           value, (char)value, s->tx_count_fifo);
}

/*
 * Simplified behavior:
 * as soon as data is written, we assume TX FIFO is flushed immediately.
 */
static void uart_flush_tx(UARTStubState *s)
{
    if (s->tx_count_fifo > 0) {
        printf("UART16550: flush TX FIFO (%u bytes)\n", s->tx_count_fifo);
    }

    s->tx_head = 0;
    s->tx_tail = 0;
    s->tx_count_fifo = 0;
    uart_update_lsr(s);
}

/* =========================================================
 * Local behavioral model
 * ========================================================= */

static uint64_t uart_local_read(UARTStubState *s, hwaddr addr, unsigned size)
{
    switch (addr) {
    case UART_REG_RBR_THR_DLL:
        if (s->lcr & UART_LCR_DLAB) {
            printf("UART16550: read DLL = 0x%02x\n", s->dll);
            return s->dll;
        } else {
            uint8_t val = uart_pop_rx(s);
            printf("UART16550: read RBR = 0x%02x\n", val);
            return val;
        }

    case UART_REG_IER_DLM:
        if (s->lcr & UART_LCR_DLAB) {
            printf("UART16550: read DLM = 0x%02x\n", s->dlm);
            return s->dlm;
        } else {
            printf("UART16550: read IER = 0x%02x\n", s->ier);
            return s->ier;
        }

    case UART_REG_IIR_FCR:
        printf("UART16550: read IIR = 0x%02x\n", s->iir);
        return s->iir;

    case UART_REG_LCR:
        printf("UART16550: read LCR = 0x%02x\n", s->lcr);
        return s->lcr;

    case UART_REG_MCR:
        printf("UART16550: read MCR = 0x%02x\n", s->mcr);
        return s->mcr;

    case UART_REG_LSR:
        uart_update_lsr(s);
        printf("UART16550: read LSR = 0x%02x\n", s->lsr);
        return s->lsr;

    case UART_REG_MSR:
        printf("UART16550: read MSR = 0x%02x\n", s->msr);
        return s->msr;

    case UART_REG_SCR:
        printf("UART16550: read SCR = 0x%02x\n", s->scr);
        return s->scr;

    case UART_REG_TX_COUNT:
        printf("UART16550: read TX_COUNT = %u\n", s->tx_count);
        return s->tx_count;

    case UART_REG_RX_COUNT:
        printf("UART16550: read RX_COUNT = %u\n", s->rx_count);
        return s->rx_count;

    case UART_REG_ERR_COUNT:
        printf("UART16550: read ERR_COUNT = %u\n", s->err_count);
        return s->err_count;

    case UART_REG_IRQ_COUNT:
        printf("UART16550: read IRQ_COUNT = %u\n", s->irq_count);
        return s->irq_count;

    default:
        printf("UART16550: read unknown offset 0x%llx\n",
               (unsigned long long)addr);
        return 0;
    }
}

static void uart_local_write(UARTStubState *s, hwaddr addr, uint64_t value, unsigned size)
{
    uint8_t v = (uint8_t)value;

    switch (addr) {
    case UART_REG_RBR_THR_DLL:
        if (s->lcr & UART_LCR_DLAB) {
            s->dll = v;
            printf("UART16550: write DLL = 0x%02x\n", s->dll);
        } else {
            uart_push_tx(s, v);
            uart_flush_tx(s);
        }
        break;
    case UART_REG_IER_DLM:
        if (s->lcr & UART_LCR_DLAB) {
            s->dlm = v;
            printf("UART16550: write DLM = 0x%02x\n", s->dlm);
        } else {
            s->ier = v;
            printf("UART16550: write IER = 0x%02x\n", s->ier);
            uart_update_interrupt(s);
        }
        break;

    case UART_REG_IIR_FCR:
        s->fcr = v;
        printf("UART16550: write FCR = 0x%02x\n", s->fcr);

        if (v & 0x02) {
            uart_reset_rx_fifo(s);
            printf("UART16550: RX FIFO reset via FCR\n");
        }
        if (v & 0x04) {
            uart_reset_tx_fifo(s);
            printf("UART16550: TX FIFO reset via FCR\n");
        }

        uart_update_interrupt(s);
        break;

    case UART_REG_LCR:
        s->lcr = v;
        printf("UART16550: write LCR = 0x%02x\n", s->lcr);
        break;

    case UART_REG_MCR:
        s->mcr = v;
        printf("UART16550: write MCR = 0x%02x\n", s->mcr);
        break;

    case UART_REG_LSR:
        printf("UART16550: write to LSR ignored (0x%02x)\n", v);
        break;

    case UART_REG_MSR:
        printf("UART16550: write to MSR ignored (0x%02x)\n", v);
        break;

    case UART_REG_SCR:
        s->scr = v;
        printf("UART16550: write SCR = 0x%02x\n", s->scr);
        break;

    case UART_REG_TX_COUNT:
        s->tx_count = (uint32_t)value;
        printf("UART16550: write TX_COUNT = %u\n", s->tx_count);
        break;

    case UART_REG_RX_COUNT:
        s->rx_count = (uint32_t)value;
        printf("UART16550: write RX_COUNT = %u\n", s->rx_count);
        break;

    case UART_REG_ERR_COUNT:
        s->err_count = (uint32_t)value;
        printf("UART16550: write ERR_COUNT = %u\n", s->err_count);
        break;

    case UART_REG_IRQ_COUNT:
        s->irq_count = (uint32_t)value;
        printf("UART16550: write IRQ_COUNT = %u\n", s->irq_count);
        break;

    default:
        printf("UART16550: write unknown offset 0x%llx = 0x%llx\n",
               (unsigned long long)addr,
               (unsigned long long)value);
        break;
    }
}

/* =========================================================
 * COSIM hook points
 * ========================================================= */

#if UART_STUB_COSIM
/*
 * QEMU MMIO side uses canonical 16550 byte offsets 0x00..0x07 for
 * register accesses (as many software stacks do for port-style UARTs).
 * Our APB RTL wrapper decodes reg index from paddr[4:2], so the bridge
 * expects APB byte addresses 0x00,0x04,...,0x1C for regs 0..7.
 *
 * Translate only legacy 16550 registers. Keep extended diagnostics
 * offsets (0x20+) unchanged.
 */
static uint32_t uart_cosim_translate_addr(hwaddr addr)
{
    if (addr <= UART_REG_SCR) {
        return (uint32_t)(addr << 2);
    }
    return (uint32_t)addr;
}

static uint64_t uart_cosim_read(UARTStubState *s, hwaddr addr, unsigned size)
{
    uint64_t value;
    uint32_t cosim_addr;

    if (!s->cosim_connected) {
        return uart_local_read(s, addr, size);
    }

    cosim_addr = uart_cosim_translate_addr(addr);
    value = cosim_uart_read(cosim_addr, (uint32_t)size);

    printf("UART16550 COSIM: read addr=0x%llx (cosim=0x%x) size=%u -> 0x%llx\n",
           (unsigned long long)addr,
           cosim_addr,
           size,
           (unsigned long long)value);

    return value;
}

static void uart_cosim_write(UARTStubState *s, hwaddr addr, uint64_t value, unsigned size)
{
    uint32_t cosim_addr;

    if (!s->cosim_connected) {
        uart_local_write(s, addr, value, size);
        return;
    }

    cosim_addr = uart_cosim_translate_addr(addr);

    printf("UART16550 COSIM: write addr=0x%llx (cosim=0x%x) value=0x%llx size=%u\n",
           (unsigned long long)addr,
           cosim_addr,
           (unsigned long long)value,
           size);

    cosim_uart_write(cosim_addr, value, (uint32_t)size);
}
#endif

/* =========================================================
 * MMIO dispatch layer
 * ========================================================= */

static uint64_t uart_stub_read(void *opaque, hwaddr addr, unsigned size)
{
#if UART_STUB_COSIM
    return uart_cosim_read((UARTStubState *)opaque, addr, size);
#else
    UARTStubState *s = opaque;
    return uart_local_read(s, addr, size);
#endif
}

static void uart_stub_write(void *opaque, hwaddr addr, uint64_t value, unsigned size)
{
#if UART_STUB_COSIM
    uart_cosim_write((UARTStubState *)opaque, addr, value, size);
    return;
#else
    UARTStubState *s = opaque;
    uart_local_write(s, addr, value, size);
#endif
}

static const MemoryRegionOps uart_stub_ops = {
    .read = uart_stub_read,
    .write = uart_stub_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
};

/* =========================================================
 * Device initialization
 * ========================================================= */

static void uart_stub_init(Object *obj)
{
    UARTStubState *s = UART_STUB(obj);
    uint64_t val;

    /* Reset state */
    s->ier = 0x00;
    s->iir = UART_IIR_NO_INT;
    s->fcr = 0x00;
    s->lcr = 0x00;
    s->mcr = 0x00;
    s->lsr = UART_LSR_THRE | UART_LSR_TEMT;
    s->msr = 0x00;
    s->scr = 0x00;
    s->dll = 0x00;
    s->dlm = 0x00;
    s->rx_head = 0;
    s->rx_tail = 0;
    s->rx_count_fifo = 0;
    s->tx_head = 0;
    s->tx_tail = 0;
    s->tx_count_fifo = 0;

    s->last_rbr = 0x00;
    s->last_thr = 0x00;

    s->tx_count = 0;
    s->rx_count = 0;
    s->err_count = 0;
    s->irq_count = 0;

    uart_update_lsr(s);

    memory_region_init_io(&s->mmio, obj, &uart_stub_ops, s,
                          "uart16550-mmio", 0x1000);
    sysbus_init_mmio(SYS_BUS_DEVICE(obj), &s->mmio);

    printf("uart_stub_init called\n");
#if UART_STUB_COSIM
    s->cosim_connected = (cosim_uart_init() == 0);
#else
    s->cosim_connected = false;
#endif

#if UART_STUB_SELFTEST
    printf("UART16550 self-test begin\n");

    /* DLAB / divisor latch test */
    uart_local_write(s, UART_REG_LCR, UART_LCR_DLAB, 1);
    uart_local_write(s, UART_REG_RBR_THR_DLL, 0x34, 1);
    uart_local_write(s, UART_REG_IER_DLM, 0x12, 1);

    val = uart_local_read(s, UART_REG_RBR_THR_DLL, 1);
    printf("UART16550 self-test DLL = 0x%llx\n", (unsigned long long)val);

    val = uart_local_read(s, UART_REG_IER_DLM, 1);
    printf("UART16550 self-test DLM = 0x%llx\n", (unsigned long long)val);

    /* Back to normal mode */
    uart_local_write(s, UART_REG_LCR, 0x03, 1);
    uart_local_write(s, UART_REG_RBR_THR_DLL, 0x41, 1);
    uart_local_write(s, UART_REG_SCR, 0x5A, 1);

    val = uart_local_read(s, UART_REG_LCR, 1);
    printf("UART16550 self-test LCR = 0x%llx\n", (unsigned long long)val);

    val = uart_local_read(s, UART_REG_SCR, 1);
    printf("UART16550 self-test SCR = 0x%llx\n", (unsigned long long)val);

    val = uart_local_read(s, UART_REG_LSR, 1);
    printf("UART16550 self-test LSR = 0x%llx\n", (unsigned long long)val);

    val = uart_local_read(s, UART_REG_TX_COUNT, 4);
    printf("UART16550 self-test TX_COUNT = 0x%llx\n", (unsigned long long)val);

    /* IER / FCR / MCR / MSR */
    uart_local_write(s, UART_REG_IER_DLM, 0x05, 1);
    val = uart_local_read(s, UART_REG_IER_DLM, 1);
    printf("UART16550 self-test IER = 0x%llx\n", (unsigned long long)val);

    uart_local_write(s, UART_REG_IIR_FCR, 0x06, 1);
    val = uart_local_read(s, UART_REG_IIR_FCR, 1);
    printf("UART16550 self-test IIR = 0x%llx\n", (unsigned long long)val);

    uart_local_write(s, UART_REG_MCR, 0x10, 1);
    val = uart_local_read(s, UART_REG_MCR, 1);
    printf("UART16550 self-test MCR = 0x%llx\n", (unsigned long long)val);

    val = uart_local_read(s, UART_REG_MSR, 1);
    printf("UART16550 self-test MSR = 0x%llx\n", (unsigned long long)val);

    /* RX FIFO test */
    uart_push_rx(s, 0x42);
    uart_push_rx(s, 0x43);

    val = uart_local_read(s, UART_REG_LSR, 1);
    printf("UART16550 self-test LSR after RX = 0x%llx\n",
           (unsigned long long)val);

    val = uart_local_read(s, UART_REG_RBR_THR_DLL, 1);
    printf("UART16550 self-test RBR1 = 0x%llx\n",
           (unsigned long long)val);

    val = uart_local_read(s, UART_REG_RBR_THR_DLL, 1);
    printf("UART16550 self-test RBR2 = 0x%llx\n",
           (unsigned long long)val);

    val = uart_local_read(s, UART_REG_LSR, 1);
    printf("UART16550 self-test LSR after RBR reads = 0x%llx\n",
           (unsigned long long)val);

    val = uart_local_read(s, UART_REG_RX_COUNT, 4);
    printf("UART16550 self-test RX_COUNT = 0x%llx\n",
           (unsigned long long)val);

    /* Simplified interrupt logic test */
    uart_local_write(s, UART_REG_IER_DLM, UART_IER_RDA | UART_IER_THRE, 1);
    uart_push_rx(s, 0x44);

    val = uart_local_read(s, UART_REG_IIR_FCR, 1);
    printf("UART16550 self-test IIR after IRQ = 0x%llx\n",
           (unsigned long long)val);

    val = uart_local_read(s, UART_REG_IRQ_COUNT, 4);
    printf("UART16550 self-test IRQ_COUNT = 0x%llx\n",
           (unsigned long long)val);

    printf("UART16550 self-test end\n");
#endif
}

static void uart_stub_class_init(ObjectClass *klass, const void *data)
{
}

static const TypeInfo uart_stub_info = {
    .name          = TYPE_UART_STUB,
    .parent        = TYPE_SYS_BUS_DEVICE,
    .instance_size = sizeof(UARTStubState),
    .instance_init = uart_stub_init,
    .class_init    = uart_stub_class_init,
};
static void uart_stub_register_types(void)
{
    type_register_static(&uart_stub_info);
}

type_init(uart_stub_register_types)
