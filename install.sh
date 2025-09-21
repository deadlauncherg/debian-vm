#!/bin/bash
set -euo pipefail

# =======================================
# Rainbow banner for Lapiogamer
# =======================================
rainbow() {
  text=$1
  colors=(31 33 32 36 34 35)
  i=0
  for (( c=0; c<${#text}; c++ )); do
    printf "\033[1;${colors[i]}m${text:$c:1}\033[0m"
    i=$(( (i+1) % ${#colors[@]} ))
  done
  echo
}

clear
rainbow "================================================"
rainbow "    WELCOME TO Lapiogamer Auto Setup                                                "
rainbow "================================================"
echo

# =======================================
# Menu
# =======================================
echo "Choose an option:"
echo "  1) Setup IDX VM (dev.nix + script.sh)"
echo "  2) Run Ubuntu VNC Docker"
echo "  0) Exit"
echo
read -p "Enter choice: " choice

# =======================================
# Option 1 → create .idx/dev.nix + script.sh
# =======================================
if [ "$choice" = "1" ]; then
  echo "[INFO] Creating .idx folder and dev.nix..."
  mkdir -p "$HOME/.idx"

  cat > "$HOME/.idx/dev.nix" <<'EOF'
{ pkgs, ... }: {
  channel = "stable-24.05";
  packages = [
    pkgs.git
    pkgs.curl
    pkgs.wget
    pkgs.unzip
    pkgs.openssh
    pkgs.sudo
    pkgs.qemu_kvm
    pkgs.cloud-utils
  ];
  env = {
    DEBIAN_FRONTEND = "noninteractive";
  };
  idx = {
    extensions = [
      "ms-vscode.remote-ssh"
      "ms-vscode.cpptools"
      "ms-python.python"
    ];
    workspace = {
      onCreate = {
        setup = ''
          echo "🔄 Preparing lightweight environment..."
          sudo apt-get update -y || true
          echo "✅ Base IDX environment ready"
        '';
      };
      onStart = {
        refresh = ''
          echo "🔁 Refreshing environment..."
          sudo apt-get update -y || true
        '';
      };
    };
    previews = { enable = false; };
  };
}
EOF

  echo "[INFO] Creating script.sh..."
  cat > "$HOME/script.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

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

VM_DIR="$HOME/vm"
IMG_FILE="$VM_DIR/debian-cloud.qcow2"
SEED_FILE="$VM_DIR/seed.iso"
MEMORY=30768
CPUS=6
SSH_PORT=24
DISK_SIZE=100G

mkdir -p "$VM_DIR"
cd "$VM_DIR"

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

    cat > user-data <<CLOUD
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
CLOUD

    cat > meta-data <<CLOUD
instance-id: iid-local01
local-hostname: debian11
CLOUD

    cloud-localds "$SEED_FILE" user-data meta-data
    echo "[INFO] VM setup complete!"
else
    echo "[INFO] VM image found, skipping setup..."
fi

echo "[INFO] Starting VM..."
KVM_OPTS=""
if [ -e /dev/kvm ]; then
    KVM_OPTS="-enable-kvm -cpu host"
else
    echo "[WARN] KVM not available, running in emulation mode."
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
  echo "[INFO] Running script.sh..."
  bash "$HOME/script.sh"

# =======================================
# Option 2 → run Docker Ubuntu VNC
# =======================================
elif [ "$choice" = "2" ]; then
  echo "[INFO] Installing Docker if not present..."
  
  # Update package index
  sudo apt-get update -y

  # Install docker.io if not already installed
  if ! command -v docker &> /dev/null; then
    sudo apt-get install -y docker.io
    echo "[INFO] Docker installed successfully."
  else
    echo "[INFO] Docker already installed."
  fi

  # Run Docker container
  docker run -d \
    --name myubuntu \
    -p 6080:6080 \
    -p 5901:5901 \
    -v ubuntu_data:/root \
    lapiogamer/ubuntu-vnc

# =======================================
# Exit
# =======================================
else
  echo "[INFO] Exiting..."
  exit 0
fi
