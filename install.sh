#!/bin/bash
set -euo pipefail

# =========================
# COLORS
# =========================
RED="\e[31m"; GRN="\e[32m"; YLW="\e[33m"
BLU="\e[34m"; PRP="\e[35m"; CYN="\e[36m"
RST="\e[0m"

# =========================
# HEADER (PRO DASHBOARD)
# =========================
header() {
clear
echo -e "${CYN}"
cat << "EOF"
╔══════════════════════════════════════════════╗
║        🚀 LAPIOGAMER CONTROL PANEL 🚀        ║
║     Advanced VM + Hosting Installer Suite    ║
╚══════════════════════════════════════════════╝
EOF
echo -e "${RST}"
}

# =========================
# DEP INSTALLER
# =========================
base_install() {
  echo -e "${YLW}[SYSTEM] Installing base dependencies...${RST}"
  sudo apt update -y
  sudo apt install -y \
    curl wget git unzip sudo \
    qemu qemu-kvm qemu-utils \
    libvirt-daemon-system libvirt-clients bridge-utils virt-manager \
    cloud-image-utils
}

# =========================
# VM DOCTOR MODE (OPTION 6)
# =========================
vm_doctor() {

echo -e "${BLU}[VM DOCTOR] Checking system...${RST}"

base_install

echo -e "${GRN}[CHECK] CPU Virtualization Support${RST}"
if egrep -c '(vmx|svm)' /proc/cpuinfo >/dev/null; then
  echo -e "${GRN}✔ CPU supports virtualization${RST}"
else
  echo -e "${YLW}⚠ CPU may NOT support virtualization${RST}"
fi

echo -e "${GRN}[CHECK] KVM Device${RST}"
if [ -e /dev/kvm ]; then
  echo -e "${GRN}✔ KVM AVAILABLE${RST}"
  KVM_FLAG="-enable-kvm -cpu host"
else
  echo -e "${RED}✖ KVM NOT AVAILABLE → switching to TCG mode${RST}"
  KVM_FLAG="-cpu max"
fi

echo -e "${GRN}[CHECK] cloud-localds${RST}"
if ! command -v cloud-localds &>/dev/null; then
  echo -e "${YLW}[FIX] Installing cloud-image-utils...${RST}"
  sudo apt install -y cloud-image-utils
fi

echo -e "${GRN}[INFO] Preparing VM workspace${RST}"
mkdir -p /root/vm
cd /root/vm

cat > user-data <<EOF
#cloud-config
password: root
chpasswd: { expire: False }
ssh_pwauth: true
EOF

echo "instance-id: vm-01" > meta-data

cloud-localds seed.iso user-data meta-data

echo -e "${BLU}[INFO] Booting VM...${RST}"

qemu-system-x86_64 \
  $KVM_FLAG \
  -m 2048 \
  -smp 2 \
  -drive file=seed.iso,format=raw,if=virtio \
  -nographic

cd ~/debian-vm 2>/dev/null || true
}

# =========================
# MENU UI (PROFESSIONAL)
# =========================
menu() {
header

echo -e "${PRP}┌────────────────────────────────────────────┐${RST}"
echo -e "${PRP}│              MAIN CONTROL MENU             │${RST}"
echo -e "${PRP}├────────────────────────────────────────────┤${RST}"
echo -e "${CYN}│  [1]  IDX VM Setup                         │${RST}"
echo -e "${CYN}│  [2]  Ubuntu VNC Docker                    │${RST}"
echo -e "${CYN}│  [3]  Pterodactyl Panel Installer          │${RST}"
echo -e "${CYN}│  [4]  Playit Tunnel                        │${RST}"
echo -e "${CYN}│  [5]  ChunkDash Hosting Panel              │${RST}"
echo -e "${GRN}│  [6]  VM DOCTOR (AUTO FIX QEMU/KVM)        │${RST}"
echo -e "${RED}│  [0]  Exit                                 │${RST}"
echo -e "${PRP}└────────────────────────────────────────────┘${RST}"

echo
read -p "➤ Select option: " choice
}

# =========================
# START
# =========================
menu

case "$choice" in

1)
  echo "[INFO] Running IDX setup..."
  bash "$HOME/script.sh"
  ;;

2)
  sudo apt update -y
  command -v docker >/dev/null || sudo apt install -y docker.io
  docker run -d --name ubuntu-vnc -p 6080:6080 lapiogamer/ubuntu-vnc
  ;;

3)
  bash <(curl -s https://pterodactyl-installer.se)
  ;;

4)
  sudo apt update
  sudo apt install -y curl gnupg
  curl -SsL https://playit-cloud.github.io/ppa/key.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/playit.gpg >/dev/null
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" | sudo tee /etc/apt/sources.list.d/playit.list
  sudo apt update
  sudo apt install -y playit
  ;;

5)
  git clone https://github.com/deadlauncherg/Hosting-panel.git || true
  cd Hosting-panel
  npm install
  ;;

6)
  vm_doctor
  ;;

0)
  echo -e "${RED}Exiting... Bye!${RST}"
  exit 0
  ;;

*)
  echo -e "${RED}Invalid option!${RST}"
  ;;
esac
