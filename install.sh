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
echo "  5) Lapio's Custom Dash ChunkDash"
echo "  0) Exit"
echo
read -p "Enter choice: " choice

# =======================================
# Option 1 → create .idx/dev.nix + script.sh
# =======================================
if [ "$choice" = "1" ]; then
  # (keep all of your current Option 1 code as-is)
  echo "[INFO] Creating .idx folder and dev.nix..."
  mkdir -p "$HOME/.idx"
  # ...rest of your Option 1 code remains unchanged

# =======================================
# Option 2 → run Docker Ubuntu VNC
# =======================================
elif [ "$choice" = "2" ]; then
  # (keep all of your current Option 2 code as-is)
  echo "[INFO] Installing Docker if not present..."
  # ...rest of Option 2 code

# =======================================
# Option 3 → Install Pterodactyl Panel + Node
# =======================================
elif [ "$choice" = "3" ]; then
  # (keep all of your current Option 3 code as-is)
  echo "[INFO] Installing Pterodactyl Panel + Node..."
  bash <(curl -s https://pterodactyl-installer.se)

# =======================================
# Option 4 → Install Playit 
# =======================================
elif [ "$choice" = "4" ]; then
  # (keep all of your current Option 4 code as-is)
  echo "[INFO] Installing Playit..."
  # ...rest of Option 4 code

# =======================================
# Option 5 → Lapio's Custom Dash ChunkDash
# =======================================
elif [ "$choice" = "5" ]; then
  echo "Lapio's Custom Dash ChunkDash"
  echo "Choose a theme:"
  echo "  1) Feastic Theme"
  echo "  2) Soon"
  echo "  3) Soon"
  echo "  4) Soon"
  echo "  0) Back"
  read -p "Enter theme choice: " theme_choice

  if [ "$theme_choice" = "1" ]; then
    echo "[INFO] You selected Feastic Theme."
    echo "Make sure to update your settings.json before running."
    sleep 2
    git clone https://github.com/deadlauncherg/Hosting-panel.git
    cd Hosting-panel || exit
    npm install
    nano settings.json

  elif [ "$theme_choice" = "2" ]; then
    echo "[INFO] Option coming soon."
  elif [ "$theme_choice" = "3" ]; then
    echo "[INFO] Option coming soon."
  elif [ "$theme_choice" = "4" ]; then
    echo "[INFO] Option coming soon."
  else
    echo "[INFO] Returning to main menu."
  fi

# =======================================
# Exit
# =======================================
else
  echo "[INFO] Exiting..."
  exit 0
fi
