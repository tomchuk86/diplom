#!/usr/bin/env bash
set -euo pipefail

# Run the UART16550 Buildroot/QEMU target with the guest serial console
# attached directly to this terminal. Exit QEMU with Ctrl-A, then X.

QEMU_BIN="${QEMU_BIN:-/home/vboxuser/diplom/qemu2/build/qemu-system-arm}"
BUILDROOT_IMAGES="${BUILDROOT_IMAGES:-/home/vboxuser/buildroot/output/images}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$BUILDROOT_IMAGES/zImage}"
DTB_IMAGE="${DTB_IMAGE:-$BUILDROOT_IMAGES/vexpress-v2p-ca9.dtb}"
ROOTFS_IMAGE="${ROOTFS_IMAGE:-$BUILDROOT_IMAGES/rootfs.ext2}"
HOSTSHARE_DIR="${HOSTSHARE_DIR:-/home/vboxuser/diplom/qemu2/drivers/uart16550_demo}"
for path in "$QEMU_BIN" "$KERNEL_IMAGE" "$DTB_IMAGE" "$ROOTFS_IMAGE" "$HOSTSHARE_DIR"; do
  if [ ! -e "$path" ]; then
    echo "ERROR: missing path: $path" >&2
    echo "Set QEMU_BIN, BUILDROOT_IMAGES, KERNEL_IMAGE, DTB_IMAGE, ROOTFS_IMAGE or HOSTSHARE_DIR if needed." >&2
    exit 1
  fi
done

echo "Starting QEMU. Guest serial console is attached to this terminal."
echo "Exit QEMU with Ctrl-A, then X."
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
