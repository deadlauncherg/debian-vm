#!/bin/bash
set -euo pipefail

echo "===================================="
echo "  IDX VPS Setup / Ubuntu VNC Script"
echo "===================================="
echo "Choose an option:"
echo "1) Full root access + VM + Playit + Dropbear"
echo "2) Run Ubuntu VNC Docker container"
read -p "Enter option (1 or 2): " choice

if [[ "$choice" == "1" ]]; then
    # Option 1: Root + VM
    echo "🔄 Replacing dev.nix with modded version..."
    mkdir -p ~/.config/nixpkgs
    cp ./modded_dev.nix ~/.config/nixpkgs/dev.nix || { echo "Error: dev.nix missing!"; exit 1; }

    echo "🚀 Running VM setup..."
    bash ./script.sh

    echo "🌐 Installing Playit.gg..."
    curl -SsL https://playit-cloud.github.io/ppa/key.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/playit.gpg >/dev/null
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" | sudo tee /etc/apt/sources.list.d/playit-cloud.list
    sudo apt update -y
    sudo apt install -y playit
    echo "Run Playit.gg and press Ctrl+C when done."
    playit

    echo "🐚 Installing Dropbear..."
    sudo apt install -y dropbear
    sudo dropbear -p 22

    read -p "Enter username to create (default 'done'): " username
    username=${username:-done}
    sudo adduser "$username" --gecos "" --disabled-password
    sudo adduser "$username" sudo

    echo "✅ Option 1 complete!"

elif [[ "$choice" == "2" ]]; then
    # Option 2: Docker Ubuntu VNC
    echo "📦 Pulling and running Ubuntu VNC container..."
    docker run -d \
      --name myubuntu \
      -p 6080:6080 \
      -p 5901:5901 \
      -v ubuntu_data:/root \
      lapiogamer/ubuntu-vnc
    echo "✅ Docker container started! Access VNC on ports 6080/5901"

else
    echo "❌ Invalid option!"
    exit 1
fi
