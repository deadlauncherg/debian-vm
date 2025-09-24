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
rainbow "    WELCOME TO Lapiogamer Auto Setup"
rainbow "================================================"
echo

# =======================================
# Menu
# =======================================
echo "Choose an option:"
echo "  1) Setup IDX VM (dev.nix + script.sh)"
echo "  2) Run Ubuntu VNC Docker"
echo "  3) Install Pterodactyl Panel + Node"
echo "  4) Install Playit"
echo "  5) Get Root Access in Google Colab + Run VM"
echo "  0) Exit"
echo
read -p "Enter choice: " choice

# =======================================
# Option 5 → Get root in Google Colab and run Option 1
# =======================================
if [ "$choice" = "5" ]; then
    echo "[INFO] Setting up root access in Colab..."
    
    sudo apt update
    sudo apt install -y cloud-image-utils qemu-utils qemu-system-x86

    echo "[INFO] Checking cloud-localds..."
    which cloud-localds
    cloud-localds --version || true

    echo "[INFO] Creating VM directory..."
    sudo mkdir -p /root/vm
    cd /root/vm

    echo "[INFO] Preparing seed.iso..."
    touch user-data meta-data
    sudo cloud-localds seed.iso user-data meta-data

    echo "[INFO] Checking seed.iso..."
    ls -lh /root/vm/seed.iso

    echo "[INFO] Running your Option 1 VM script..."
    # Call your existing script.sh (assumes Option 1 already created it)
    if [ ! -f "$HOME/script.sh" ]; then
        echo "[ERROR] Option 1 script.sh not found. Run Option 1 first!"
        exit 1
    fi
    bash "$HOME/script.sh"
fi

# =======================================
# Option 1 → create .idx/dev.nix + script.sh
# =======================================
if [ "$choice" = "1" ]; then
  # ... your original Option 1 code here ...
  # (untouched)
  echo "[INFO] Running Option 1..."
fi

# =======================================
# Option 2 → Docker Ubuntu VNC
# =======================================
if [ "$choice" = "2" ]; then
  # ... original Option 2 code ...
fi

# =======================================
# Option 3 → Pterodactyl Panel + Node
# =======================================
if [ "$choice" = "3" ]; then
  # ... original Option 3 code ...
fi

# =======================================
# Option 4 → Playit
# =======================================
if [ "$choice" = "4" ]; then
  # ... original Option 4 code ...
fi

# =======================================
# Exit
# =======================================
if [ "$choice" = "0" ]; then
  echo "[INFO] Exiting..."
  exit 0
fi
