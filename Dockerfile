FROM debian:12

LABEL maintainer="lapiogamer"
LABEL description="Debian VM inside Docker (lapiogaming edition)"

# Install QEMU and required tools
RUN apt-get update && apt-get install -y \
    qemu-system-x86 \
    qemu-kvm \
    qemu-utils \
    libvirt-daemon-system \
    libvirt-clients \
    virt-manager \
    sudo \
    curl \
    wget \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Working directory for VM files
WORKDIR /vmdata

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
