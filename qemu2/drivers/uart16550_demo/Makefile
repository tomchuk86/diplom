obj-m += uart16550_demo.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)
ARCH ?= $(shell uname -m | sed 's/armv7l/arm/')
CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc

all: module user

module:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) M=$(PWD) modules

user: test_uart16550_demo

test_uart16550_demo: test_uart16550_demo.c uart16550_demo.h
	$(CC) -O2 -Wall test_uart16550_demo.c -o test_uart16550_demo

clean:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) M=$(PWD) clean
	rm -f test_uart16550_demo
