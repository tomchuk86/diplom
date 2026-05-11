#!/usr/bin/env bash
set -euo pipefail

# Run the UART16550 Buildroot/QEMU target with the guest serial console
# attached directly to this terminal. Exit QEMU with Ctrl-A, then X.
#
# UART16550_COSIM=1|socket — QEMU MMIO по TCP к ModelSim bridge (полная цепочка RTL).
# UART16550_COSIM=dpi — только колбэки в процессе QEMU (без ModelSim по TCP).
# Example:
#   cd /path/to/repo && UART16550_COSIM=1 UART_COSIM_LOG=1 bash qemu2/scripts/run_uart16550_qemu_telnet.sh
# Use && before env vars — not "cd ...UART16550_COSIM=..." (that breaks cd).
# Details: qemu2/README_COSIM_UART.md

QEMU_BIN="${QEMU_BIN:-/home/vboxuser/diplom/qemu2/build/qemu-system-arm}"
BUILDROOT_IMAGES="${BUILDROOT_IMAGES:-/home/vboxuser/buildroot/output/images}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$BUILDROOT_IMAGES/zImage}"
DTB_IMAGE="${DTB_IMAGE:-$BUILDROOT_IMAGES/vexpress-v2p-ca9.dtb}"
ROOTFS_IMAGE="${ROOTFS_IMAGE:-$BUILDROOT_IMAGES/rootfs.ext2}"
HOSTSHARE_DIR="${HOSTSHARE_DIR:-/home/vboxuser/diplom/qemu2/drivers/uart16550_extended}"
for path in "$QEMU_BIN" "$KERNEL_IMAGE" "$DTB_IMAGE" "$ROOTFS_IMAGE" "$HOSTSHARE_DIR"; do
  if [ ! -e "$path" ]; then
    echo "ERROR: missing path: $path" >&2
    echo "Set QEMU_BIN, BUILDROOT_IMAGES, KERNEL_IMAGE, DTB_IMAGE, ROOTFS_IMAGE or HOSTSHARE_DIR if needed." >&2
    exit 1
  fi
done

if [ ! -f "$HOSTSHARE_DIR/uart16550_demo.ko" ] || [ ! -f "$HOSTSHARE_DIR/test_uart16550_demo" ]; then
  echo "WARNING: в $HOSTSHARE_DIR нет uart16550_demo.ko или test_uart16550_demo" >&2
  echo "  Соберите под гостя: make -C $HOSTSHARE_DIR guest" >&2
fi

echo "Starting QEMU. Guest serial console is attached to this terminal."
echo "Exit QEMU with Ctrl-A, then X."
echo
echo "9p share на хосте: $HOSTSHARE_DIR (mount_tag=hostshare)"
echo "В госте выполните подряд (remount без первого mount ничего не даст):"
echo "  mkdir -p /mnt/host && mount -t 9p -o trans=virtio hostshare /mnt/host && ls -la /mnt/host"
echo "  insmod /mnt/host/uart16550_demo.ko base_addr=0xff210000 loopback=1 debug_level=2"
echo "  /mnt/host/test_uart16550_demo --verbose --cosim"
echo "(insmod — одной строкой, без переноса перед =2.)"
echo

exec "$QEMU_BIN" \
  -M vexpress-a9 \
  -m 256M \
  -kernel "$KERNEL_IMAGE" \
  -dtb "$DTB_IMAGE" \
  -drive "if=sd,file=$ROOTFS_IMAGE,format=raw" \
  -append "console=ttyAMA0,115200 root=/dev/mmcblk0 rootwait rootfstype=ext4 rw" \
  -fsdev "local,id=fsdev0,path=$HOSTSHARE_DIR,security_model=none" \
  -device virtio-9p-device,fsdev=fsdev0,mount_tag=hostshare \
  -nographic
