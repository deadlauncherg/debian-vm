#!/bin/bash
set -e

# Default values if not set
RAM=${RAM:-2048}
CPU=${CPU:-2}
DISK_SIZE=${DISK_SIZE:-20G}
IMG_FILE="/vmdata/debian.img"

echo "=== Lapiogaming Debian VM ==="
echo "CPU: $CPU | RAM: ${RAM}MB | Disk: $DISK_SIZE"
echo "Image: $IMG_FILE"

# Create VM disk if it doesn't exist
if [ ! -f "$IMG_FILE" ]; then
    echo "[+] Creating disk image: $IMG_FILE ($DISK_SIZE)"
    qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    echo "⚠️ No OS installed yet. You need to boot with a Debian ISO once."
fi

# Run QEMU virtual machine
exec qemu-system-x86_64 \
    -m $RAM \
    -smp $CPU \
    -drive file=$IMG_FILE,format=qcow2 \
    -nographic \
    -enable-kvm
