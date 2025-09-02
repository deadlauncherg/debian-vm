FROM debian:12

LABEL maintainer="lapiogamer"
LABEL description="Debian VM inside Docker (lapiogaming edition)"

RUN apt-get update && apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    curl \
    wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /vmdata
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
