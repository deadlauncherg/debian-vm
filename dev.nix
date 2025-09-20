{ pkgs, ... }: {
  # Use stable nixpkgs channel
  channel = "stable-24.05";

  # Minimal packages (only what you need to run vm.sh + QEMU)
  packages = [
    pkgs.git
    pkgs.curl
    pkgs.wget
    pkgs.unzip
    pkgs.openssh
    pkgs.sudo
    pkgs.qemu_kvm   # QEMU with KVM support
    pkgs.cloud-utils  # for cloud-localds
  ];

  # Environment variables
  env = {
    DEBIAN_FRONTEND = "noninteractive";
  };

  # IDX configuration
  idx = {
    extensions = [
      "ms-vscode.remote-ssh"
      "ms-vscode.cpptools"
      "ms-python.python"
    ];

    workspace = {
      # Run once when workspace is created
      onCreate = {
        setup = ''
          echo "🔄 Preparing lightweight environment..."
          sudo apt-get update -y || true
          echo "✅ Base IDX environment ready"
        '';
      };

      # Run each time workspace starts
      onStart = {
        refresh = ''
          echo "🔁 Refreshing environment..."
          sudo apt-get update -y || true
        '';
      };
    };

    # Disable previews (saves resources)
    previews = {
      enable = false;
    };
  };
}
