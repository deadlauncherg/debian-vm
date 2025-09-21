#!/bin/bash
set -euo pipefail

# =============================
# Debian 11 VM (Auto-detect Image Format)
# =============================

clear
cat << "EOF"
================================================
   ____       _     _             
  |  _ \  ___| |__ (_) __ _ _ __  
  | | | |/ _ \ '_ \| |/ _` | '_ \ 
  | |_| |  __/ |_) | | (_| | | | |
  |____/ \___|_.__/|_|\__,_|_| |_|
                                  
   Debian 11 (Image format safe)
================================================
EOF

# =============================
# Ensure qemu-img is available
# =============================
if ! command -v qemu-img &> /dev/null; then
    echo "[WARN] qemu-img not found, downloading static binary..."
    mkdir -p "$HOME/bin"
    cd "$HOME/bin"
    curl -L -o qemu-img https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-x86_64-static
    chmod +x qemu-img
    export PATH="$HOME/bin:$PATH"
    cd -
    echo "[INFO] qemu-img ready at $HOME/bin/qemu-img"
fi

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
