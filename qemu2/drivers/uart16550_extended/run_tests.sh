#!/bin/sh

set -eu

DEVICE="/dev/uart16550_demo"
BASE_ADDR="0xff210000"
DEBUG_LEVEL="2"
LOOPBACK="1"

info() {
    echo "[INFO] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

info "Building kernel module and userspace tests"
make all

if lsmod | grep -q '^uart16550_demo'; then
    info "Removing old uart16550_demo module"
    sudo rmmod uart16550_demo || fail "failed to remove old module"
fi

info "Loading module"
sudo insmod uart16550_demo.ko base_addr=${BASE_ADDR} loopback=${LOOPBACK} debug_level=${DEBUG_LEVEL} || fail "insmod failed"

info "Checking device node"
ls -l ${DEVICE} || fail "device node was not created"

info "Running test suite"
sudo ./test_uart16550_demo --verbose || fail "test suite failed"

info "Recent kernel log"
dmesg | tail -n 40

info "Unloading module"
sudo rmmod uart16550_demo || fail "rmmod failed"

info "All tests finished"
