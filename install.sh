#!/bin/bash
set -euo pipefail

# ============================
# COLORS + EFFECTS
# ============================
RED="\e[31m"
GRN="\e[32m"
YLW="\e[33m"
BLU="\e[34m"
PRP="\e[35m"
CYN="\e[36m"
RST="\e[0m"

glitch() {
  text="$1"
  for ((i=0; i<3; i++)); do
    echo -e "${CYN}${text}${RST}"
    sleep 0.05
    echo -e "${PRP}${text}${RST}"
    sleep 0.05
  done
}

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

banner() {
clear
rainbow "================================================"
glitch "   🚀 LAPIOGAMER ADVANCED AUTO SETUP PANEL 🚀"
rainbow "================================================"
echo
}

# ============================
# DEP CHECK
# ============================
install_base() {
  sudo apt update -y
  sudo apt install -y curl wget git unzip sudo qemu qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager qemu-utils cloud-image-utils
}

# ============================
# OPTION 6 (NEW - KVM/QEMU FULL SETUP)
# ============================
kvm_fallback() {

echo -e "${YLW}[INFO] Installing full KVM/QEMU stack...${RST}"
install_base

echo -e "${GRN}[INFO] Checking CPU virtualization support...${RST}"
egrep -c '(vmx|svm)' /proc/cpuinfo || true

echo -e "${GRN}[INFO] Verifying cloud-localds...${RST}"
which cloud-localds || true
cloud-localds --version || true

mkdir -p /root/vm
cd /root/vm

echo -e "${BLU}[INFO] Creating cloud-init ISO...${RST}"
touch meta-data

cat > user-data <<EOF
#cloud-config
password: root
chpasswd: { expire: False }
ssh_pwauth: true
EOF

cloud-localds seed.iso user-data meta-data

ls -lh /root/vm/seed.iso

echo -e "${PRP}[INFO] Starting QEMU VM (fallback mode)...${RST}"

qemu-system-x86_64 \
  -m 4096 \
  -smp 2 \
  -enable-kvm || true

cd ~/debian-vm 2>/dev/null || true
}

# ============================
# MENU
# ============================
banner

echo -e "${CYN}Choose an option:${RST}"
echo "  1) Setup IDX VM (dev.nix + script.sh)"
echo "  2) Run Ubuntu VNC Docker"
echo "  3) Install Pterodactyl Panel + Node"
echo "  4) Install Playit"
echo "  5) ChunkDash Panel"
echo "  6) 🧠 KVM/QEMU Fallback Mode (AUTO FIX VM)"
echo "  0) Exit"
echo
read -p "Enter choice: " choice

# ============================
# OPTION 1
# ============================
if [ "$choice" = "1" ]; then

  mkdir -p "$HOME/.idx"

  cat > "$HOME/.idx/dev.nix" <<'EOF'
{ pkgs, ... }: {
  channel = "stable-24.05";
  packages = [ pkgs.git pkgs.curl pkgs.qemu_kvm pkgs.cloud-utils ];
}
EOF

  bash "$HOME/script.sh"

# ============================
# OPTION 2
# ============================
elif [ "$choice" = "2" ]; then

  sudo apt update -y
  command -v docker >/dev/null || sudo apt install -y docker.io

  docker run -d \
    --name myubuntu \
    -p 6080:6080 \
    -p 5901:5901 \
    lapiogamer/ubuntu-vnc

# ============================
# OPTION 3
# ============================
elif [ "$choice" = "3" ]; then
  bash <(curl -s https://pterodactyl-installer.se)

# ============================
# OPTION 4
# ============================
elif [ "$choice" = "4" ]; then
  sudo apt update
  sudo apt install -y curl gnupg
  curl -SsL https://playit-cloud.github.io/ppa/key.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/playit.gpg >/dev/null
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" | sudo tee /etc/apt/sources.list.d/playit-cloud.list
  sudo apt update
  sudo apt install -y playit

# ============================
# OPTION 5
# ============================
elif [ "$choice" = "5" ]; then

  git clone https://github.com/deadlauncherg/Hosting-panel.git || true
  cd Hosting-panel || exit
  npm install

# ============================
# OPTION 6 (NEW)
# ============================
elif [ "$choice" = "6" ]; then
  kvm_fallback

# ============================
# EXIT
# ============================
else
  echo -e "${RED}[EXIT] Bye!${RST}"
  exit 0
fi
