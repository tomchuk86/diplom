obj-m += uart16550_demo.o

KDIR ?= /home/vboxuser/buildroot/output/build/linux-6.18.7
PWD := $(shell pwd)
ARCH ?= arm
CROSS_COMPILE ?= /home/vboxuser/buildroot/output/host/bin/arm-none-linux-gnueabihf-
CC := $(CROSS_COMPILE)gcc

all: module user

module:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) M=$(PWD) modules

user: test_uart16550_demo

test_uart16550_demo: test_uart16550_demo.c uart16550_demo.h
	$(CC) -O2 -Wall test_uart16550_demo.c -o test_uart16550_demo

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f test_uart16550_demo
