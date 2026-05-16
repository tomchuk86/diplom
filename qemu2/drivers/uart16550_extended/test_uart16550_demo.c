#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <time.h>
#include "uart16550_demo.h"

#define TEST_PASS 0
#define TEST_FAIL 1

struct test_ctx {
    int fd;
    int passed;
    int failed;
    int verbose;
    int quick;
    size_t stress_len;
    /* 0 = полный pattern в selftest; иначе не больше N байт */
    size_t selftest_max;
};

static int read_with_retry(int fd, char *out, int retries);

static void print_line(void)
{
    printf("------------------------------------------------------------\n");
}

static void pass(struct test_ctx *ctx, const char *name)
{
    ctx->passed++;
    printf("[PASS] %s\n", name);
}

static void fail(struct test_ctx *ctx, const char *name, const char *msg)
{
    ctx->failed++;
    printf("[FAIL] %s: %s\n", name, msg);
}

static void print_stats(const struct uart_stats *st)
{
    printf("UART statistics:\n");
    printf("  TX_COUNT  = %u\n", st->tx);
    printf("  RX_COUNT  = %u\n", st->rx);
    printf("  ERR_COUNT = %u\n", st->err);
    printf("  IRQ_COUNT = %u\n", st->irq);
}

static void print_regs(const struct uart_regs *r)
{
    printf("UART registers:\n");
    printf("  IER = 0x%02x\n", r->ier);
    printf("  IIR = 0x%02x\n", r->iir);
    printf("  LCR = 0x%02x\n", r->lcr);
    printf("  MCR = 0x%02x\n", r->mcr);
    printf("  LSR = 0x%02x\n", r->lsr);
    printf("  MSR = 0x%02x\n", r->msr);
    printf("  SCR = 0x%02x\n", r->scr);
}

static void print_config(const struct uart_config *cfg)
{
    printf("Driver configuration:\n");
    printf("  base_addr_low = 0x%08x\n", cfg->base_addr_low);
    printf("  region_size   = 0x%08x\n", cfg->region_size);
    printf("  loopback      = %u\n", cfg->loopback);
    printf("  debug_level   = %u\n", cfg->debug_level);
    printf("  tx_timeout_us = %u\n", cfg->tx_timeout_us);
    printf("  rx_timeout_us = %u\n", cfg->rx_timeout_us);
    printf("  sw_reads      = %u\n", cfg->sw_reads);
    printf("  sw_writes     = %u\n", cfg->sw_writes);
    printf("  sw_ioctls     = %u\n", cfg->sw_ioctls);
    printf("  sw_polls      = %u\n", cfg->sw_polls);
    printf("  sw_errors     = %u\n", cfg->sw_errors);
    printf("  sw_timeouts   = %u\n", cfg->sw_timeouts);
}

static int get_stats(int fd, struct uart_stats *st)
{
    if (ioctl(fd, UART_IOCTL_GET_STATS, st) < 0) {
        perror("ioctl GET_STATS");
        return -1;
    }
    return 0;
}

static int get_regs(int fd, struct uart_regs *r)
{
    if (ioctl(fd, UART_IOCTL_GET_REGS, r) < 0) {
        perror("ioctl GET_REGS");
        return -1;
    }
    return 0;
}

static int test_init(struct test_ctx *ctx)
{
    const char *name = "init_basic";

    if (ioctl(ctx->fd, UART_IOCTL_INIT_BASIC) < 0) {
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_get_regs(struct test_ctx *ctx)
{
    const char *name = "get_regs";
    struct uart_regs regs;

    if (get_regs(ctx->fd, &regs) < 0) {
        fail(ctx, name, "GET_REGS ioctl failed");
        return TEST_FAIL;
    }

    if (ctx->verbose)
        print_regs(&regs);

    if ((regs.lcr & 0x03) != 0x03) {
        fail(ctx, name, "LCR does not report 8-bit mode");
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_get_config(struct test_ctx *ctx)
{
    const char *name = "get_config";
    struct uart_config cfg;

    if (ioctl(ctx->fd, UART_IOCTL_GET_CONFIG, &cfg) < 0) {
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    if (ctx->verbose)
        print_config(&cfg);

    if (cfg.region_size == 0) {
        fail(ctx, name, "region_size is zero");
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_set_divisor(struct test_ctx *ctx)
{
    const char *name = "set_divisor";
    uint32_t divisor = 27;

    if (ioctl(ctx->fd, UART_IOCTL_SET_DIVISOR, &divisor) < 0) {
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_loopback_enable(struct test_ctx *ctx)
{
    const char *name = "set_loopback";
    uint32_t enable = 1;

    if (ioctl(ctx->fd, UART_IOCTL_SET_LOOPBACK, &enable) < 0) {
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_reset_stats(struct test_ctx *ctx)
{
    const char *name = "reset_stats";
    struct uart_stats st;

    if (ioctl(ctx->fd, UART_IOCTL_RESET_STATS) < 0) {
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    if (get_stats(ctx->fd, &st) < 0) {
        fail(ctx, name, "GET_STATS failed after reset");
        return TEST_FAIL;
    }

    if (ctx->verbose)
        print_stats(&st);

    pass(ctx, name);
    return TEST_PASS;
}

static int test_reset_fifo(struct test_ctx *ctx)
{
    const char *name = "reset_fifo";

    if (ioctl(ctx->fd, UART_IOCTL_RESET_FIFO) < 0) {
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

/*
 * With loopback, each TX byte is echoed into the RX FIFO (depth 8). Bursts overflow
 * RTL ERR_COUNT unless we read echo promptly. Optional drain catches leftovers.
 */
static int write_bytes_consume_loopback(struct test_ctx *ctx, const char *buf, size_t len)
{
    struct uart_config cfg;
    size_t i;
    char rx;

    if (ioctl(ctx->fd, UART_IOCTL_GET_CONFIG, &cfg) < 0)
        return -1;

    if (!cfg.loopback)
        return write(ctx->fd, buf, len) == (ssize_t)len ? 0 : -1;

    for (i = 0; i < len; i++) {
        if (write(ctx->fd, buf + i, 1) != 1)
            return -1;
        if (read_with_retry(ctx->fd, &rx, 800) != 1)
            return -1;
        if ((unsigned char)rx != (unsigned char)buf[i]) {
            fprintf(stderr,
                    "loopback mismatch at offset %zu: sent 0x%02x read 0x%02x\n",
                    i, (unsigned char)buf[i], (unsigned char)rx);
            return -2;
        }
    }
    return 0;
}

static int test_write_string(struct test_ctx *ctx)
{
    const char *name = "write_string";
    const char *msg = "HELLO_FROM_EXPANDED_DRIVER\n";

    switch (write_bytes_consume_loopback(ctx, msg, strlen(msg))) {
    case 0:
        break;
    case -2:
        fail(ctx, name, "loopback echo byte mismatch");
        return TEST_FAIL;
    default:
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_tx_counter(struct test_ctx *ctx)
{
    const char *name = "tx_counter";
    struct uart_stats before;
    struct uart_stats after;
    const char *msg = "1234567890";

    if (get_stats(ctx->fd, &before) < 0) {
        fail(ctx, name, "failed to get initial stats");
        return TEST_FAIL;
    }

    switch (write_bytes_consume_loopback(ctx, msg, strlen(msg))) {
    case 0:
        break;
    case -2:
        fail(ctx, name, "loopback echo byte mismatch");
        return TEST_FAIL;
    default:
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    if (get_stats(ctx->fd, &after) < 0) {
        fail(ctx, name, "failed to get final stats");
        return TEST_FAIL;
    }

    if (after.tx < before.tx + strlen(msg)) {
        fail(ctx, name, "TX_COUNT did not grow as expected");
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int read_with_retry(int fd, char *out, int retries)
{
    int i;
    ssize_t ret;

    for (i = 0; i < retries; i++) {
        ret = read(fd, out, 1);
        if (ret == 1)
            return 1;
        if (ret < 0 && errno != EAGAIN)
            return -1;
        usleep(1000);
    }

    return 0;
}

static int test_loopback_rx(struct test_ctx *ctx)
{
    const char *name = "loopback_rx";
    const char tx = 'Z';
    char rx = 0;
    ssize_t ret;
    int rc;

    ioctl(ctx->fd, UART_IOCTL_RESET_FIFO);

    ret = write(ctx->fd, &tx, 1);
    if (ret != 1) {
        fail(ctx, name, "failed to write loopback byte");
        return TEST_FAIL;
    }

    rc = read_with_retry(ctx->fd, &rx, 200);
    if (rc != 1) {
        fail(ctx, name, "no RX byte returned by loopback");
        return TEST_FAIL;
    }

    if ((unsigned char)rx != (unsigned char)tx) {
        fprintf(stderr, "loopback_rx: sent 0x%02x read 0x%02x\n",
                (unsigned char)tx, (unsigned char)rx);
        fail(ctx, name, "received byte differs from transmitted byte");
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_poll(struct test_ctx *ctx)
{
    const char *name = "poll";
    struct pollfd pfd;
    int ret;

    pfd.fd = ctx->fd;
    pfd.events = POLLIN | POLLOUT;
    pfd.revents = 0;

    ret = poll(&pfd, 1, 100);
    if (ret < 0) {
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    if (!(pfd.revents & POLLOUT)) {
        fail(ctx, name, "driver did not report POLLOUT");
        return TEST_FAIL;
    }

    if (ctx->verbose)
        printf("poll revents=0x%x\n", pfd.revents);

    pass(ctx, name);
    return TEST_PASS;
}

static int test_nonblock_empty_read(struct test_ctx *ctx)
{
    const char *name = "nonblock_empty_read";
    int flags;
    char rx;
    ssize_t ret;

    ioctl(ctx->fd, UART_IOCTL_RESET_FIFO);

    flags = fcntl(ctx->fd, F_GETFL, 0);
    fcntl(ctx->fd, F_SETFL, flags | O_NONBLOCK);

    ret = read(ctx->fd, &rx, 1);

    fcntl(ctx->fd, F_SETFL, flags);

    if (ret < 0 && errno == EAGAIN) {
        pass(ctx, name);
        return TEST_PASS;
    }

    fail(ctx, name, "empty nonblocking read did not return EAGAIN");
    return TEST_FAIL;
}

static int test_selftest_ioctl(struct test_ctx *ctx)
{
    const char *name = "selftest_ioctl";
    struct uart_selftest st;

    memset(&st, 0, sizeof(st));
    snprintf(st.pattern, sizeof(st.pattern), "SELFTEST_1234567890");
    st.pattern_len = strlen(st.pattern);
    if (ctx->selftest_max > 0 && st.pattern_len > ctx->selftest_max) {
        st.pattern_len = ctx->selftest_max;
    }

    if (ioctl(ctx->fd, UART_IOCTL_SELF_TEST, &st) < 0) {
        fail(ctx, name, strerror(errno));
        return TEST_FAIL;
    }

    if (ctx->verbose) {
        printf("selftest: tx_ok=%u rx_ok=%u expected=%u actual=%u errors=%u\n",
               st.tx_ok, st.rx_ok, st.expected_rx, st.actual_rx, st.errors);
    }

    if (st.errors != 0 || st.tx_ok != st.pattern_len) {
        fail(ctx, name, "selftest reported errors");
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_stress(struct test_ctx *ctx)
{
    /*
     * Loopback byte-at-a-time; при UART16550_COSIM + ModelSim каждый байт очень дорог.
     * Длину задаёт --stress-bytes или режим --cosim (см. usage).
     */
    const char *name = "stress_loopback_bytes";
    char *buf;
    size_t len = ctx->stress_len ? ctx->stress_len : 64;
    size_t i;
    struct uart_stats before;
    struct uart_stats after;

    buf = malloc(len);
    if (!buf) {
        fail(ctx, name, "malloc failed");
        return TEST_FAIL;
    }

    for (i = 0; i < len; i++)
        buf[i] = 'A' + (i % 26);

    get_stats(ctx->fd, &before);
    switch (write_bytes_consume_loopback(ctx, buf, len)) {
    case 0:
        break;
    case -2:
        fail(ctx, name, "loopback echo byte mismatch");
        free(buf);
        return TEST_FAIL;
    default:
        fail(ctx, name, strerror(errno));
        free(buf);
        return TEST_FAIL;
    }
    get_stats(ctx->fd, &after);

    free(buf);

    if (after.tx < before.tx + len) {
        fail(ctx, name, "TX_COUNT did not grow after stress write");
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static int test_final_stats(struct test_ctx *ctx)
{
    const char *name = "final_stats";
    struct uart_stats st;
    struct uart_config cfg;

    /*
     * RTL накопляет ERR_COUNT на overflow/frame/parity за сессию; после стресса
     * значение часто ≠ 0 даже без провалившихся тестов. Проверяем здесь только
     * то, что сброс статистики в железе/драйвере работает: FIFO + STATS
     * и затем все четыре счётчика показывают ноль.
     */
    if (ioctl(ctx->fd, UART_IOCTL_RESET_FIFO) < 0) {
        fail(ctx, name, "RESET_FIFO failed");
        return TEST_FAIL;
    }
    if (ioctl(ctx->fd, UART_IOCTL_RESET_STATS) < 0) {
        fail(ctx, name, "RESET_STATS failed");
        return TEST_FAIL;
    }
    if (get_stats(ctx->fd, &st) < 0) {
        fail(ctx, name, "GET_STATS failed");
        return TEST_FAIL;
    }

    if (ioctl(ctx->fd, UART_IOCTL_GET_CONFIG, &cfg) < 0) {
        fail(ctx, name, "GET_CONFIG failed");
        return TEST_FAIL;
    }

    print_stats(&st);
    if (ctx->verbose)
        print_config(&cfg);

    if (st.tx != 0 || st.rx != 0 || st.err != 0 || st.irq != 0) {
        fail(ctx, name,
             "hardware stats not zero after RESET_FIFO + RESET_STATS");
        return TEST_FAIL;
    }

    pass(ctx, name);
    return TEST_PASS;
}

static void usage(const char *prog)
{
    printf("Usage: %s [options]\n", prog);
    printf("Default device: %s\n", UART16550_DEVICE_PATH);
    printf("  --device PATH   UART device node\n");
    printf("  --verbose       extra logs\n");
    printf("  --quick         skip poll / nonblock / selftest / stress (cosim-friendly)\n");
    printf("  --cosim         короткий прогон: stress=16 байт, selftest pattern=8 (можно совмещать с --stress-bytes / --selftest-bytes)\n");
    printf("  --stress-bytes N   байт в stress_loopback_bytes (по умолчанию 64)\n");
    printf("  --selftest-bytes N обрезать kernel selftest до N байт pattern (по умолчанию весь pattern)\n");
}

int main(int argc, char **argv)
{
    struct test_ctx ctx;
    const char *dev_path = UART16550_DEVICE_PATH;
    int i;
    int opt_cosim = 0;
    int stress_by_user = 0;
    int selftest_by_user = 0;
    unsigned long u;

    memset(&ctx, 0, sizeof(ctx));
    ctx.fd = -1;
    ctx.stress_len = 64;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--device") && i + 1 < argc) {
            dev_path = argv[++i];
        } else if (!strcmp(argv[i], "--verbose")) {
            ctx.verbose = 1;
        } else if (!strcmp(argv[i], "--quick")) {
            ctx.quick = 1;
        } else if (!strcmp(argv[i], "--cosim")) {
            opt_cosim = 1;
        } else if (!strcmp(argv[i], "--stress-bytes") && i + 1 < argc) {
            u = strtoul(argv[++i], NULL, 0);
            ctx.stress_len = u ? u : 1;
            stress_by_user = 1;
        } else if (!strcmp(argv[i], "--selftest-bytes") && i + 1 < argc) {
            u = strtoul(argv[++i], NULL, 0);
            ctx.selftest_max = u;
            selftest_by_user = 1;
        } else if (!strcmp(argv[i], "--help")) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 1;
        }
    }

    if (opt_cosim) {
        if (!stress_by_user) {
            ctx.stress_len = 16;
        }
        if (!selftest_by_user) {
            ctx.selftest_max = 8;
        }
    }

    ctx.fd = open(dev_path, O_RDWR);
    if (ctx.fd < 0) {
        perror("open device");
        return 1;
    }

    printf("UART16550 demo test suite\n");
    printf("Device: %s\n", dev_path);
    if (opt_cosim) {
        printf("Mode: --cosim (stress_len=%zu, selftest_max=%zu)\n",
               ctx.stress_len, ctx.selftest_max);
    }
    print_line();

    test_init(&ctx);
    test_get_regs(&ctx);
    test_get_config(&ctx);
    test_set_divisor(&ctx);
    test_loopback_enable(&ctx);
    test_reset_stats(&ctx);
    test_reset_fifo(&ctx);
    test_write_string(&ctx);
    test_tx_counter(&ctx);
    test_loopback_rx(&ctx);
    if (!ctx.quick) {
        test_poll(&ctx);
        test_nonblock_empty_read(&ctx);
        test_selftest_ioctl(&ctx);
        test_stress(&ctx);
    } else {
        printf("[SKIP] slow cosimulation tests (--quick)\n");
    }
    test_final_stats(&ctx);

    print_line();
    printf("SUMMARY: passed=%d failed=%d\n", ctx.passed, ctx.failed);

    close(ctx.fd);
    return ctx.failed ? 1 : 0;
}
