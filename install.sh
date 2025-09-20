#!/bin/bash
# Clean, user-friendly IDX installer

echo "===================================="
echo "       IDX VPS Setup Script"
echo "===================================="
echo
echo "Choose an option:"
echo "1) Run script.sh with dev.nix setup"
echo "2) Run Ubuntu VNC Docker container"
echo

read -p "Enter option (1 or 2): " choice

# ------------------------------
# Option 1: Setup .idx and run script.sh
# ------------------------------
if [[ "$choice" == "1" ]]; then
    echo
    echo "🔄 Setting up .idx folder and downloading files..."

    IDX_FOLDER="$HOME/.idx"
    mkdir -p "$IDX_FOLDER"

    # Download dev.nix
    if curl -sL https://raw.githubusercontent.com/deadlauncherg/debian-vm/refs/heads/main/dev.nix -o "$IDX_FOLDER/dev.nix"; then
        echo "✅ dev.nix placed in $IDX_FOLDER"
    else
        echo "❌ Failed to download dev.nix"
        exit 1
    fi

    # Download script.sh
    if curl -sL https://raw.githubusercontent.com/deadlauncherg/debian-vm/refs/heads/main/script.sh -o "$HOME/script.sh"; then
        chmod +x "$HOME/script.sh"
        echo "✅ script.sh downloaded to $HOME and made executable"
    else
        echo "❌ Failed to download script.sh"
        exit 1
    fi

    # Run script.sh
    echo
    echo "🚀 Running script.sh..."
    bash "$HOME/script.sh"

# ------------------------------
# Option 2: Docker Ubuntu VNC
# ------------------------------
elif [[ "$choice" == "2" ]]; then
    echo
    echo "📦 Pulling and running Ubuntu VNC container..."
    docker run -d \
      --name myubuntu \
      -p 6080:6080 \
      -p 5901:5901 \
      -v ubuntu_data:/root \
      lapiogamer/ubuntu-vnc
    echo "✅ Docker container started!"
    echo "   Access VNC on ports 6080 (web) / 5901 (VNC client)"

# ------------------------------
# Invalid option
# ------------------------------
else
    echo
    echo "❌ Invalid option! Please enter 1 or 2."
    exit 1
fi

echo
echo "===================================="
echo "      Script execution finished"
echo "===================================="
