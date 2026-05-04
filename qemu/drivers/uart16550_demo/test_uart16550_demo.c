#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include "uart16550_demo.h"

int main(){
    int fd;
    int i;
    int rc;
    char rx = 0;
    const char *msg = "HELLO\n";
    struct uart_stats st;

    fd = open("/dev/uart16550_demo", O_RDWR);
    if(fd < 0){
        perror("open");
        return 1;
    }

    ioctl(fd, UART_IOCTL_INIT_BASIC);

    write(fd, msg, 6);

    /*
     * Simple RX test:
     * try to read one echoed byte from UART loopback path.
     * Driver returns -EAGAIN when RX FIFO is empty, so retry a bit.
     */
    for (i = 0; i < 200; i++) {
        rc = read(fd, &rx, 1);
        if (rc == 1) {
            break;
        }
        if (rc < 0 && errno != EAGAIN) {
            perror("read");
            break;
        }
        usleep(1000);
    }

    ioctl(fd, UART_IOCTL_GET_STATS, &st);

    if (rc == 1) {
        printf("RX_TEST=PASS byte=0x%02x ('%c') expected=0x%02x ('%c')\n",
               (unsigned char)rx, rx, (unsigned char)msg[0], msg[0]);
    } else {
        printf("RX_TEST=FAIL no byte received (rc=%d, errno=%d)\n", rc, errno);
    }

    printf("TX=%u RX=%u ERR=%u IRQ=%u\n", st.tx, st.rx, st.err, st.irq);

    close(fd);
    return 0;
}
