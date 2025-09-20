#!/bin/bash
set -euxo pipefail

echo "===================================="
echo "  IDX VPS Setup / Ubuntu VNC Script"
echo "===================================="

echo "Choose an option:"
echo "1) Prepare files for root access + VM setup"
echo "2) Run Ubuntu VNC Docker container"
read -p "Enter option (1 or 2): " choice

# ------------------------------
# Option 1: Prepare files for root access
# ------------------------------
if [[ "$choice" == "1" ]]; then
    echo "🔄 Setting up .idx folder and downloading files..."

    # Create .idx folder in home
    IDX_FOLDER="$HOME/.idx"
    mkdir -p "$IDX_FOLDER"

    # Download dev.nix into .idx folder
    curl -sL https://raw.githubusercontent.com/deadlauncherg/debian-vm/refs/heads/main/dev.nix -o "$IDX_FOLDER/dev.nix"
    echo "✅ dev.nix placed in $IDX_FOLDER"

    # Download script.sh to home directory (outside .idx)
    curl -sL https://raw.githubusercontent.com/deadlauncherg/debian-vm/refs/heads/main/script.sh -o "$HOME/script.sh"
    chmod +x "$HOME/script.sh"
    echo "✅ script.sh downloaded to $HOME and made executable"

    # Inform user to run script.sh after root access
    echo
    echo "===================================="
    echo "✅ Preparation complete!"
    echo "Next steps:"
    echo "1) Gain root access on your IDX VPS."
    echo "2) Run the VM setup script manually:"
    echo "   bash ~/script.sh"
    echo "===================================="

# ------------------------------
# Option 2: Docker Ubuntu VNC
# ------------------------------
elif [[ "$choice" == "2" ]]; then
    echo "📦 Pulling and running Ubuntu VNC container..."
    docker run -d \
      --name myubuntu \
      -p 6080:6080 \
      -p 5901:5901 \
      -v ubuntu_data:/root \
      lapiogamer/ubuntu-vnc
    echo "✅ Docker container started! Access VNC on ports 6080/5901"

# ------------------------------
# Invalid option
# ------------------------------
else
    echo "❌ Invalid option! Exiting..."
    exit 1
fi
