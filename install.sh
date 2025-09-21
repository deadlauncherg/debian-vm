#!/bin/bash
set -euo pipefail

echo "===================================="
echo "       IDX VPS Setup Menu"
echo "===================================="
echo
echo "Choose an option:"
echo "1) Create script.sh + dev.nix and run VM"
echo "2) Run Ubuntu VNC Docker container"
echo

read -p "Enter option (1 or 2): " choice

if [[ "$choice" == "1" ]]; then
    echo "🔄 Creating .idx folder and dev.nix..."
    IDX_FOLDER="$HOME/.idx"
    mkdir -p "$IDX_FOLDER"

    # Fetch dev.nix into .idx
    curl -sL https://raw.githubusercontent.com/deadlauncherg/debian-vm/refs/heads/main/dev.nix -o "$IDX_FOLDER/dev.nix"
    echo "✅ dev.nix placed in $IDX_FOLDER"

    echo "📝 Writing script.sh..."
    cat > "$HOME/script.sh" <<"EOF"
#!/bin/bash
set -euo pipefail

# =============================
# Debian 11 VM (Auto-detect Image Format)
# =============================

clear
cat << "BANNER"
================================================
   ____       _     _             
  |  _ \  ___| |__ (_) __ _ _ __  
  | | | |/ _ \ '_ \| |/ _` | '_ \ 
  | |_| |  __/ |_) | | (_| | | | |
  |____/ \___|_.__/|_|\__,_|_| |_|
                                  
   Debian 11 (Image format safe)
================================================
BANNER

# =============================
# Configurable Variables
# =============================
VM_DIR="$HOME/vm"
IMG_FILE="$VM_DIR/debian-cloud.qcow2"
SEED_FILE="$VM_DIR/seed.iso"
MEMORY=2048   # safe for IDX
CPUS=2
SSH_PORT=24
DISK_SIZE=10G

mkdir -p "$VM_DIR"
cd "$VM_DIR"

# =============================
# VM Image Setup
# =============================
if [ ! -f "$IMG_FILE" ]; then
    echo "[INFO] Downloading Debian 11 cloud image..."
    wget -q https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2 -O "$VM_DIR/debian-cloud.raw"

    echo "[INFO] Checking image format..."
    FORMAT=$(qemu-img info "$VM_DIR/debian-cloud.raw" | grep "file format" | awk '{print $3}')

    if [ "$FORMAT" != "qcow2" ]; then
        echo "[WARN] Image is $FORMAT, converting to qcow2..."
        qemu-img convert -f "$FORMAT" -O qcow2 "$VM_DIR/debian-cloud.raw" "$IMG_FILE"
        rm "$VM_DIR/debian-cloud.raw"
    else
        mv "$VM_DIR/debian-cloud.raw" "$IMG_FILE"
    fi

    echo "[INFO] Resizing image to $DISK_SIZE..."
    qemu-img resize "$IMG_FILE" "$DISK_SIZE"

    # Cloud-init config with hostname = debian11
    cat > user-data <<EOF2
#cloud-config
hostname: debian11
manage_etc_hosts: true
disable_root: false
ssh_pwauth: true
chpasswd:
  list: |
    root:root
  expire: false
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false
resize_rootfs: true
package_update: true
package_upgrade: true
runcmd:
 - apt-get update -y
 - apt-get upgrade -y
 - apt-get install -y sudo curl unzip git wget htop lsof
 - sed -ri "s/^#?PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
 - systemctl restart ssh
EOF2

    cat > meta-data <<EOF2
instance-id: iid-local01
local-hostname: debian11
EOF2

    cloud-localds "$SEED_FILE" user-data meta-data
    echo "[INFO] VM setup complete!"
else
    echo "[INFO] VM image found, skipping setup..."
fi

# =============================
# Start VM
# =============================
echo "[INFO] Starting VM..."

KVM_OPTS=""
if [ -e /dev/kvm ]; then
    KVM_OPTS="-enable-kvm -cpu host"
else
    echo "[WARN] KVM not available, running in emulation mode (slower)."
    KVM_OPTS="-cpu max"
fi

exec qemu-system-x86_64 \
    $KVM_OPTS \
    -m "$MEMORY" \
    -smp "$CPUS" \
    -drive file="$IMG_FILE",format=qcow2,if=virtio \
    -drive file="$SEED_FILE",format=raw,if=virtio \
    -boot order=c \
    -device virtio-net-pci,netdev=n0 \
    -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22 \
    -nographic -serial mon:stdio
EOF

    chmod +x "$HOME/script.sh"
    echo "✅ script.sh created at $HOME/script.sh"

    echo "🚀 Running script.sh..."
    bash "$HOME/script.sh"

elif [[ "$choice" == "2" ]]; then
    echo "📦 Pulling and running Ubuntu VNC container..."
    docker run -d \
      --name myubuntu \
      -p 6080:6080 \
      -p 5901:5901 \
      -v ubuntu_data:/root \
      lapiogamer/ubuntu-vnc
    echo "✅ Docker container started!"
    echo "   Access VNC on ports 6080 (web) / 5901 (VNC client)"

else
    echo "❌ Invalid option! Please enter 1 or 2."
    exit 1
fi

echo
echo "===================================="
echo "      Script execution finished"
echo "===================================="
