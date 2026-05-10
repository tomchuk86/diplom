obj-m += uart16550_demo.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)
ARCH ?= $(shell uname -m | sed 's/armv7l/arm/')
CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc

USER_CFLAGS := -O2 -Wall -Wextra -std=gnu99

.PHONY: all module user clean install unload reload test lines

all: module user

module:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) M=$(PWD) modules

user: test_uart16550_demo

test_uart16550_demo: test_uart16550_demo.c uart16550_demo.h
	$(CC) $(USER_CFLAGS) test_uart16550_demo.c -o test_uart16550_demo

install: module
	-sudo rmmod uart16550_demo
	sudo insmod uart16550_demo.ko base_addr=0xff210000 loopback=1 debug_level=2
	dmesg | tail -n 20

unload:
	-sudo rmmod uart16550_demo
	dmesg | tail -n 20

reload: unload install

test: user
	sudo ./test_uart16550_demo --verbose

lines:
	wc -l uart16550_demo.c uart16550_demo.h test_uart16550_demo.c Makefile run_tests.sh README.md

clean:
	$(MAKE) -C $(KDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) M=$(PWD) clean
	rm -f test_uart16550_demo
