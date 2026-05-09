#!/usr/bin/env bash
set -euo pipefail

# Run the UART16550 Buildroot/QEMU target with the guest serial console
# exported as a telnet server. Connect with:
#   telnet 127.0.0.1 5555
# or from Windows/host PuTTY to <VM-IP>:5555 (or 127.0.0.1:5555 with
# VirtualBox NAT port forwarding Host 5555 -> Guest 5555).

QEMU_BIN="${QEMU_BIN:-/home/vboxuser/qemu/build/qemu-system-arm}"
BUILDROOT_IMAGES="${BUILDROOT_IMAGES:-/home/vboxuser/buildroot/output/images}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$BUILDROOT_IMAGES/zImage}"
DTB_IMAGE="${DTB_IMAGE:-$BUILDROOT_IMAGES/vexpress-v2p-ca9.dtb}"
ROOTFS_IMAGE="${ROOTFS_IMAGE:-$BUILDROOT_IMAGES/rootfs.ext2}"
HOSTSHARE_DIR="${HOSTSHARE_DIR:-/home/vboxuser/qemu/drivers/uart16550_demo}"
TELNET_HOST="${TELNET_HOST:-0.0.0.0}"
TELNET_PORT="${TELNET_PORT:-5555}"

for path in "$QEMU_BIN" "$KERNEL_IMAGE" "$DTB_IMAGE" "$ROOTFS_IMAGE" "$HOSTSHARE_DIR"; do
  if [ ! -e "$path" ]; then
    echo "ERROR: missing path: $path" >&2
    echo "Set QEMU_BIN, BUILDROOT_IMAGES, KERNEL_IMAGE, DTB_IMAGE, ROOTFS_IMAGE or HOSTSHARE_DIR if needed." >&2
    exit 1
  fi
done

echo "Starting QEMU. Guest serial console is available via telnet:"
echo "  telnet ${TELNET_HOST} ${TELNET_PORT}"
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
  -display none \
  -monitor none \
  -serial "telnet:${TELNET_HOST}:${TELNET_PORT},server,nowait"
