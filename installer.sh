#!/bin/bash
set -Eeuo pipefail

# ============================================================
#                         LAPIOPLAYS
#                        Vps Manager
# ============================================================

# ---------- Colors ----------
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
BLACK=$'\033[30m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
WHITE=$'\033[37m'
BRIGHT_BLUE=$'\033[94m'
BRIGHT_CYAN=$'\033[96m'
BRIGHT_WHITE=$'\033[97m'
BRIGHT_GREEN=$'\033[92m'
BRIGHT_RED=$'\033[91m'
BRIGHT_YELLOW=$'\033[93m'
BRIGHT_MAGENTA=$'\033[95m'

APP_NAME="LAPIOPLAYS"
APP_VERSION="2.9"
LOG_DIR="${HOME}/.lapio-bhai"
LOG_FILE="${LOG_DIR}/installer.log"
VPS_DIR="${HOME}/.lapio-bhai/vps"
VPS_ENV="${VPS_DIR}/.vps_env"

mkdir -p "$LOG_DIR" "$VPS_DIR"
touch "$LOG_FILE"

# ---------- Root / sudo ----------
if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=()
else
    SUDO_CMD=(sudo)
fi

# ---------- Terminal helpers ----------
term_width() {
    local width
    width="$(tput cols 2>/dev/null || true)"
    [[ "$width" =~ ^[0-9]+$ ]] || width=80
    (( width < 70 )) && width=70
    printf '%s\n' "$width"
}

line() {
    echo -e "  ${BRIGHT_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ---------- Live system information ----------
human_gb() {
    local mb="${1:-0}"
    awk -v mb="$mb" 'BEGIN {
        if (mb >= 1024) printf "%.1f GB", mb/1024;
        else printf "%d MB", mb;
    }'
}

usage_bar() {
    local percent="${1:-0}"
    local width=12
    local filled empty
    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
    (( percent < 0 )) && percent=0
    (( percent > 100 )) && percent=100
    filled=$(( percent * width / 100 ))
    empty=$(( width - filled ))

    printf '%s' "${BRIGHT_CYAN}"
    local i
    for ((i=0; i<filled; i++)); do printf '▰'; done
    printf '%s' "${DIM}"
    for ((i=0; i<empty; i++)); do printf '▱'; done
    printf '%s' "${RESET}"
}

get_ram_stats() {
    local total used percent
    if command -v free >/dev/null 2>&1; then
        read -r total used < <(free -m | awk '/^Mem:/ {print $2, $3}')
    fi
    total="${total:-0}"
    used="${used:-0}"
    if (( total > 0 )); then
        percent=$(( used * 100 / total ))
    else
        percent=0
    fi
    printf '%s|%s|%s' "$used" "$total" "$percent"
}

get_disk_stats() {
    local used total percent
    read -r used total percent < <(
        df -P / 2>/dev/null | awk 'NR==2 {
            gsub(/%/, "", $5);
            printf "%s %s %s\n", $3, $2, $5
        }'
    )
    used="${used:-0}"
    total="${total:-0}"
    percent="${percent:-0}"
    printf '%s|%s|%s' "$used" "$total" "$percent"
}

get_cpu_percent() {
    local load_avg_value cores percent
    load_avg_value="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
    cores="$(nproc 2>/dev/null || echo 1)"
    percent="$(awk -v loadavg_value="$load_avg_value" -v cores="$cores" 'BEGIN {
        if (cores < 1) cores=1;
        p=(loadavg_value/cores)*100;
        if (p > 100) p=100;
        if (p < 0) p=0;
        printf "%d", p
    }')"
    printf '%s' "${percent:-0}"
}

get_uptime_short() {
    awk '{
        s=int($1);
        d=int(s/86400); s%=86400;
        h=int(s/3600); s%=3600;
        m=int(s/60);
        if (d>0) printf "%dd %dh", d, h;
        else if (h>0) printf "%dh %dm", h, m;
        else printf "%dm", m;
    }' /proc/uptime 2>/dev/null || printf '%s' "unknown"
}

resource_status_color() {
    local percent="${1:-0}"
    if (( percent >= 90 )); then
        printf '%s' "$BRIGHT_RED"
    elif (( percent >= 75 )); then
        printf '%s' "$BRIGHT_YELLOW"
    else
        printf '%s' "$BRIGHT_GREEN"
    fi
}

pause_screen() {
    echo
    read -r -p "  Press ENTER to continue..." _
}

status_ok() {
    echo -e "  ${GREEN}OK${RESET} $1"
}

status_warn() {
    echo -e "  ${YELLOW}!${RESET} $1"
}

status_fail() {
    echo -e "  ${RED}FAIL${RESET} $1"
}

# Run a command without printing the command itself.
# Output is written to the private log. User sees only Working *.
run_silent() {
    local label="$1"
    shift

    local tmp="${LOG_DIR}/task_$$.log"
    local pid
    local spin='|/-\'
    local i=0

    echo -ne "  ${CYAN}${label}${RESET} ${DIM}Working ${RESET}"

    "$@" >"$tmp" 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf '\b%s' "${spin:i++%4:1}"
        sleep 0.18
    done

    if wait "$pid"; then
        printf '\b'
        echo -e "${GREEN}OK${RESET}"
        cat "$tmp" >> "$LOG_FILE" 2>/dev/null || true
        rm -f "$tmp"
        return 0
    else
        printf '\b'
        echo -e "${RED}FAIL${RESET}"
        {
            echo
            echo "[FAILED] $label"
            cat "$tmp" 2>/dev/null || true
        } >> "$LOG_FILE"
        rm -f "$tmp"
        echo -e "  ${RED}Failed:${RESET} ${label}"
        echo -e "  ${DIM}Log: ${LOG_FILE}${RESET}"
        return 1
    fi
}

# Spinner for an already-running PID.
wait_pid_silent() {
    local pid="$1"
    local label="$2"
    local spin='|/-\'
    local i=0

    echo -ne "  ${CYAN}${label}${RESET} ${DIM}Working ${RESET}"
    while kill -0 "$pid" 2>/dev/null; do
        printf '\b%s' "${spin:i++%4:1}"
        sleep 0.18
    done

    if wait "$pid"; then
        printf '\b'
        echo -e "${GREEN}OK${RESET}"
        return 0
    fi

    printf '\b'
    echo -e "${RED}FAIL${RESET}"
    return 1
}

header() {
    clear
    echo
    echo -e "  ${BRIGHT_CYAN}${BOLD}╭────────────────────────────────────────────────────────────╮${RESET}"
    echo -e "  ${BRIGHT_CYAN}${BOLD}│${RESET}  ${BRIGHT_MAGENTA}${BOLD}LAPIOPLAYS${RESET}  ${DIM}•${RESET}  ${BRIGHT_WHITE}SERVER INSTALLER${RESET}  ${DIM}v${APP_VERSION}${RESET}       ${BRIGHT_CYAN}${BOLD}│${RESET}"
    echo -e "  ${BRIGHT_CYAN}${BOLD}╰────────────────────────────────────────────────────────────╯${RESET}"
    echo
}

section_title() {
    local title="$1"
    echo -e "  ${BRIGHT_BLUE}${BOLD}┌─${RESET} ${BRIGHT_WHITE}${BOLD}${title}${RESET}"
    echo -e "  ${BRIGHT_BLUE}${BOLD}└────────────────────────────────────────────────────────────${RESET}"
    echo
}

# ============================================================
# VPS CONFIG
# ============================================================

load_vps_env() {
    if [ -f "$VPS_ENV" ]; then
        # shellcheck disable=SC1090
        source "$VPS_ENV"
    fi

    RAM_GB="${RAM_GB:-4}"
    CPU_CORES="${CPU_CORES:-2}"
    DISK_GB="${DISK_GB:-20}"
    USER_NAME="${USER_NAME:-ubuntu}"
    USER_PASS="${USER_PASS:-1234}"
    TCP_HOST_PORT="${TCP_HOST_PORT:-2222}"
    TCP_GUEST_PORT="${TCP_GUEST_PORT:-22}"
    VPS_MODE="${VPS_MODE:-virtualization}"
}

save_vps_env() {
    cat > "$VPS_ENV" <<EOF
RAM_GB=${RAM_GB}
CPU_CORES=${CPU_CORES}
DISK_GB=${DISK_GB}
USER_NAME=${USER_NAME}
USER_PASS=${USER_PASS}
TCP_HOST_PORT=${TCP_HOST_PORT}
TCP_GUEST_PORT=${TCP_GUEST_PORT}
VPS_MODE=${VPS_MODE}
EOF
}

# Detect the host OS. systemd-detect-virt describes the environment the host
# runs inside; it does NOT tell us whether QEMU can use KVM.
detect_host_os() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        printf '%s|%s|%s\n' "${ID:-unknown}" "${VERSION_ID:-unknown}" "${PRETTY_NAME:-Unknown Linux}"
    else
        printf '%s|%s|%s\n' "unknown" "unknown" "Unknown Linux"
    fi
}

detect_virt_type() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        systemd-detect-virt 2>/dev/null || true
    else
        printf '%s' "unknown"
    fi
}

# Fast check for the main-menu status line. This avoids starting a QEMU probe
# every time the menu redraws; the full probe is done before option 01 starts.
detect_virtualization() {
    qemu_bin >/dev/null 2>&1 || { printf '%s\n' unavailable; return; }
    [ -c /dev/kvm ] || { printf '%s\n' unavailable; return; }
    if "${SUDO_CMD[@]}" test -r /dev/kvm && "${SUDO_CMD[@]}" test -w /dev/kvm; then
        printf '%s\n' available
    else
        printf '%s\n' unavailable
    fi
}

# A real, short QEMU probe verifies KVM initialization. Exit 124 is expected:
# timeout terminates QEMU after it successfully remains running for 3 seconds.
qemu_bin() {
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then command -v qemu-system-x86_64; return 0; fi
    if command -v qemu-kvm >/dev/null 2>&1; then command -v qemu-kvm; return 0; fi
    return 1
}

probe_kvm_acceleration() {
    local qemu; qemu="$(qemu_bin)" || return 1
    [ -c /dev/kvm ] || return 1
    command -v timeout >/dev/null 2>&1 || return 1

    local output rc
    if output="$(timeout 3s "${SUDO_CMD[@]}" "$qemu" \
        -machine none,accel=kvm -nodefaults -display none -S 2>&1)"; then
        rc=0
    else
        rc=$?
    fi

    if [ "$rc" -eq 124 ]; then
        return 0
    fi
    if [ -n "$output" ]; then
        printf '%s\n' "$output" >> "$LOG_FILE"
    fi
    return 1
}

kvm_detection_message() {
    local host_os virt_type kvm_status
    host_os="$(detect_host_os | awk -F'|' '{print $3}')"
    virt_type="$(detect_virt_type)"
    kvm_status="unavailable"
    if probe_kvm_acceleration; then kvm_status="available"; fi

    echo -e "  ${DIM}Host OS:${RESET} ${CYAN}${host_os}${RESET}"
    echo -e "  ${DIM}Host environment (informational):${RESET} ${CYAN}${virt_type:-unknown}${RESET}"

    if [ "$kvm_status" = available ]; then
        echo -e "  ${BRIGHT_GREEN}${BOLD}● QEMU KVM ACCELERATION AVAILABLE${RESET}"
        echo -e "  ${DIM}QEMU successfully initialized KVM using /dev/kvm.${RESET}"
        return 0
    fi

    echo -e "  ${BRIGHT_YELLOW}${BOLD}● QEMU KVM ACCELERATION UNAVAILABLE${RESET}"
    echo -e "  ${DIM}KVM probe failed. Check /dev/kvm, permissions, host BIOS and provider nested-virtualization settings.${RESET}"
    echo -e "  ${DIM}Details, if any, were appended to:${RESET} ${CYAN}${LOG_FILE}${RESET}"
    return 1
}

port_in_use() {
    local port="$1"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 0
    fi

    if command -v ss >/dev/null 2>&1; then
        ss -ltnH 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END {exit !found}'
        return $?
    fi

    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
        return $?
    fi

    if command -v fuser >/dev/null 2>&1; then
        fuser -s "${port}/tcp" 2>/dev/null
        return $?
    fi

    # If no socket-inspection tool exists, let QEMU perform the final check.
    return 1
}

find_free_host_port() {
    local requested="$1"
    local port="$requested"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        port=2222
    fi

    while [ "$port" -le 65535 ]; do
        if ! port_in_use "$port"; then
            printf '%s' "$port"
            return 0
        fi
        port=$((port + 1))
    done

    return 1
}

vps_image_in_use() {
    local image="$1"
    if command -v fuser >/dev/null 2>&1 && fuser -s "$image" 2>/dev/null; then
        return 0
    fi
    if command -v lsof >/dev/null 2>&1 && lsof "$image" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

install_vps_dependencies() {
    local os_id os_name pkgmgr
    IFS='|' read -r os_id _ os_name <<< "$(detect_host_os)"
    os_id="${os_id,,}"
    echo -e "  ${DIM}Auto-detected host OS:${RESET} ${CYAN}${os_name}${RESET}"

    case "$os_id" in
        ubuntu|debian|linuxmint|pop|elementary|kali|linuxlite|zorin)
            pkgmgr=apt
            run_silent "Updating package index (${os_name})" "${SUDO_CMD[@]}" apt-get update || return 1
            run_silent "Installing QEMU/cloud-init tools" "${SUDO_CMD[@]}" apt-get install -y \
                qemu-system-x86 qemu-utils wget cloud-image-utils curl lsof ca-certificates || return 1
            ;;
        fedora)
            pkgmgr=dnf
            run_silent "Installing QEMU/cloud-init tools (${os_name})" "${SUDO_CMD[@]}" dnf install -y \
                qemu-system-x86-core qemu-img wget cloud-utils curl lsof ca-certificates coreutils || return 1
            ;;
        centos|rhel|rocky|almalinux|ol)
            if command -v dnf >/dev/null 2>&1; then pkgmgr=dnf; else pkgmgr=yum; fi
            run_silent "Installing QEMU/cloud-init tools (${os_name})" "${SUDO_CMD[@]}" "$pkgmgr" install -y \
                qemu-kvm-core qemu-img wget cloud-utils curl lsof ca-certificates coreutils || {
                status_fail "Some RHEL-family versions name/package QEMU differently. Check ${LOG_FILE}."
                return 1
            }
            ;;
        *)
            status_fail "Unsupported automatic package setup for ${os_name} (ID=${os_id})."
            echo -e "  ${DIM}Detected OS correctly; install QEMU, qemu-img, cloud-init/cloud-localds, wget, curl, lsof and timeout using its package manager, then retry.${RESET}"
            return 1
            ;;
    esac

    local missing=0 cmd
    for cmd in qemu-img wget curl timeout; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            status_fail "Required command not found after ${pkgmgr} install: ${cmd}"
            missing=1
        fi
    done
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1 && ! command -v qemu-kvm >/dev/null 2>&1; then
        status_fail "QEMU x86 system emulator not found; package names vary by distro/release."
        missing=1
    fi
    if ! command -v cloud-localds >/dev/null 2>&1; then
        status_fail "cloud-localds is missing (usually supplied by cloud-image-utils/cloud-utils)."
        missing=1
    fi
    [ "$missing" -eq 0 ] || return 1
    status_ok "VPS dependencies are ready for ${os_name}"
}

download_vps_image() {
    VPS_IMAGE="${VPS_DIR}/ubuntu22.qcow2"

    if [ -f "$VPS_IMAGE" ]; then
        status_ok "Ubuntu 22.04 image cache found"
    else
        run_silent "Downloading Ubuntu 22.04 image" \
            "${SUDO_CMD[@]}" wget -q --show-progress \
            "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img" \
            -O "$VPS_IMAGE" || return 1
    fi

    # The source VPS script uses qemu-img resize on the Ubuntu cloud image.
    # Keep the image format explicit so both KVM and TCG use the same disk.
    run_silent "Expanding VPS disk" \
        "${SUDO_CMD[@]}" qemu-img resize "$VPS_IMAGE" "${DISK_GB}G" || return 1

    "${SUDO_CMD[@]}" chmod 666 "$VPS_IMAGE" 2>/dev/null || true
}

create_cloud_init() {
    local user_data="$VPS_DIR/user-data"
    local meta_data="$VPS_DIR/meta-data"
    local seed="$VPS_DIR/seed.img"

    cat > "$user_data" <<EOF
#cloud-config
hostname: lapio-vps
manage_etc_hosts: true
ssh_pwauth: true
ssh_deletekeys: false
users:
  - default
  - name: ${USER_NAME}
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
chpasswd:
  list: |
    ${USER_NAME}:${USER_PASS}
  expire: false
package_update: true
packages:
  - sudo
  - curl
  - wget
  - git
  - unzip
  - htop
  - lsof
EOF

    cat > "$meta_data" <<EOF
instance-id: lapio-bhai-vps
local-hostname: lapio-vps
EOF

    run_silent "Generating cloud-init disk" \
        cloud-localds "$seed" "$user_data" "$meta_data"
}

start_vps() {
    load_vps_env

    local image="$VPS_DIR/ubuntu22.qcow2"
    local seed="$VPS_DIR/seed.img"

    if [ ! -f "$image" ] || [ ! -f "$seed" ]; then
        status_fail "VPS files are missing. Create the VPS first."
        echo -e "  ${DIM}Returning to the VPS menu...${RESET}"
        sleep 1
        return 0
    fi

    # Only treat the disk as locked when a real process is using it.
    # A stale/old lock message must never block a fresh VPS start.
    if vps_image_in_use "$image"; then
        header
        section_title "START VPS"
        echo -e "  ${BRIGHT_YELLOW}${BOLD}● VPS ALREADY RUNNING${RESET}"
        echo
        echo -e "  ${DIM}The VPS disk is currently being used by QEMU.${RESET}"
        echo -e "  ${DIM}Starting another instance would be unsafe, so it was blocked.${RESET}"
        echo
        echo -e "  ${DIM}SSH:${RESET} ${CYAN}localhost:${TCP_HOST_PORT} -> VM:${TCP_GUEST_PORT}${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}Press ENTER to return to the VPS menu...${RESET}"
        read -r _
        return 0
    fi

    # QEMU cannot bind a forwarding port that is already used by SSH or another service.
    # Pick the requested port when free; otherwise move to the next free TCP port.
    local original_host_port="$TCP_HOST_PORT"
    local free_host_port
    free_host_port="$(find_free_host_port "$TCP_HOST_PORT")" || {
        status_fail "No free TCP port is available for SSH forwarding."
        echo -e "  ${DIM}Requested port: ${TCP_HOST_PORT}${RESET}"
        echo -e "  ${BRIGHT_CYAN}Press ENTER to return to the VPS menu...${RESET}"
        read -r _
        return 0
    }
    if [ "$free_host_port" != "$TCP_HOST_PORT" ]; then
        TCP_HOST_PORT="$free_host_port"
        save_vps_env
    fi

    header
    section_title "START VPS"

    if [ "$free_host_port" != "$original_host_port" ]; then
        status_warn "Host port ${original_host_port} is already in use; using ${TCP_HOST_PORT} instead."
        echo -e "  ${DIM}SSH forwarding: localhost:${TCP_HOST_PORT} -> VM:${TCP_GUEST_PORT}${RESET}"
        echo
    fi

    local accel_args=()
    local cpu_args=()
    if [ "$VPS_MODE" = "virtualization" ]; then
        if kvm_detection_message; then
            accel_args=(-enable-kvm)
            cpu_args=(-cpu host)
            echo
            status_ok "Starting with real KVM hardware acceleration"
        else
            status_warn "KVM is unavailable; automatically falling back to QEMU TCG software emulation."
            accel_args=(-accel tcg,thread=multi)
            cpu_args=(-cpu max)
        fi
    else
        echo -e "  ${BRIGHT_YELLOW}${BOLD}● SOFTWARE EMULATION${RESET}"
        echo -e "  ${DIM}QEMU TCG mode selected. No KVM is required.${RESET}"
        accel_args=(-accel tcg,thread=multi)
        cpu_args=(-cpu max)
    fi

    echo
    echo -e "  ${DIM}RAM     ${RESET}${CYAN}${RAM_GB} GB${RESET}"
    echo -e "  ${DIM}CPU     ${RESET}${CYAN}${CPU_CORES} cores${RESET}"
    echo -e "  ${DIM}Disk    ${RESET}${CYAN}${DISK_GB} GB${RESET}"
    echo -e "  ${DIM}SSH     ${RESET}${CYAN}localhost:${TCP_HOST_PORT} -> VM:${TCP_GUEST_PORT}${RESET}"
    echo
    echo -e "  ${YELLOW}Starting VPS. Press Ctrl+C to stop.${RESET}"
    echo

    # QEMU is intentionally run in the foreground so the VPS stays attached
    # to this terminal exactly like the original VPS implementation.
    local qemu_command
    qemu_command="$(qemu_bin)" || { status_fail "QEMU binary not found"; pause_screen; return 1; }
    set +e
    "${SUDO_CMD[@]}" "$qemu_command" \
        "${accel_args[@]}" \
        "${cpu_args[@]}" \
        -m "${RAM_GB}G" \
        -smp "$CPU_CORES" \
        -drive "file=${image},format=qcow2,if=virtio" \
        -drive "file=${seed},format=raw,if=virtio" \
        -boot order=c \
        -nographic \
        -netdev "user,id=net0,hostfwd=tcp::${TCP_HOST_PORT}-:${TCP_GUEST_PORT}" \
        -device virtio-net-pci,netdev=net0
    local qemu_rc=$?
    set -e

    echo
    if [ "$qemu_rc" -eq 0 ] || [ "$qemu_rc" -eq 130 ] || [ "$qemu_rc" -eq 143 ]; then
        status_ok "VPS stopped"
    else
        status_fail "QEMU exited with code ${qemu_rc}"
        echo -e "  ${DIM}See: ${LOG_FILE}${RESET}"
    fi

    echo
    echo -e "  ${BRIGHT_CYAN}Press ENTER to return to the VPS menu...${RESET}"
    read -r _
    return 0
}

create_vps() {
    header
    section_title "CREATE VPS"

    load_vps_env

    local host_ram_gb reserve_ram_gb
    host_ram_gb="$(awk '/MemTotal:/ {printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo 0)"
    host_ram_gb="${host_ram_gb:-0}"
    reserve_ram_gb=1
    echo -e "  ${DIM}Detected host RAM:${RESET} ${CYAN}${host_ram_gb} GB${RESET}"
    echo -e "  ${DIM}For stability, keep at least ${reserve_ram_gb} GB for the host. Guest RAM cannot create extra physical memory.${RESET}"
    read -r -p "  RAM in GB [${RAM_GB}]: " value
    RAM_GB="${value:-$RAM_GB}"
    if ! [[ "$RAM_GB" =~ ^[1-9][0-9]*$ ]]; then
        status_fail "RAM must be a positive whole number of GB."
        pause_screen
        return 1
    fi
    if (( host_ram_gb > 0 && RAM_GB > host_ram_gb )); then
        status_fail "${RAM_GB} GB exceeds the detected ${host_ram_gb} GB host RAM. Choose ${host_ram_gb} GB or less."
        pause_screen
        return 1
    fi
    if (( host_ram_gb > 0 && RAM_GB >= host_ram_gb )); then
        status_warn "You selected all detected host RAM. The outer VPS may freeze or be killed by its OOM manager."
        read -r -p "  Continue with ${RAM_GB} GB anyway? [y/N]: " ram_confirm
        if [[ ! "$ram_confirm" =~ ^[Yy]$ ]]; then
            status_warn "Choose a smaller RAM value and try again."
            pause_screen
            return 1
        fi
    elif (( host_ram_gb > 1 && RAM_GB > host_ram_gb - reserve_ram_gb )); then
        status_warn "This leaves less than ${reserve_ram_gb} GB for the host; memory pressure may make the server unstable."
    fi

    read -r -p "  CPU cores [${CPU_CORES}]: " value
    CPU_CORES="${value:-$CPU_CORES}"

    read -r -p "  Disk in GB [${DISK_GB}]: " value
    DISK_GB="${value:-$DISK_GB}"

    read -r -p "  Username [${USER_NAME}]: " value
    USER_NAME="${value:-$USER_NAME}"

    read -r -s -p "  Password [hidden]: " value
    echo
    USER_PASS="${value:-$USER_PASS}"

    read -r -p "  Host SSH port [${TCP_HOST_PORT}]: " value
    TCP_HOST_PORT="${value:-$TCP_HOST_PORT}"

    save_vps_env
    echo

    install_vps_dependencies || { pause_screen; return; }

    if [ "$VPS_MODE" = "virtualization" ] && ! kvm_detection_message; then
        echo
        status_warn "KVM is unavailable. Option 01 will continue using QEMU TCG software emulation instead."
        VPS_MODE="no_virtualization"
        save_vps_env
    fi

    download_vps_image || { pause_screen; return; }
    create_cloud_init || { pause_screen; return; }

    status_ok "VPS created successfully"
    start_vps
}

vps_virtualization() {
    header
    section_title ".VPS • WITH VIRTUALISATION"

    VPS_MODE="virtualization"
    load_vps_env
    VPS_MODE="virtualization"

    echo -e "  ${DIM}Host OS detection and the QEMU KVM test will run during setup.${RESET}"
    echo

    save_vps_env
    create_vps
}

vps_no_virtualization() {
    header
    section_title ".VPS • WITHOUT VIRTUALISATION"

    VPS_MODE="no_virtualization"
    load_vps_env
    VPS_MODE="no_virtualization"
    save_vps_env

    status_ok "Software emulation mode selected"
    echo -e "  ${DIM}No /dev/kvm requirement. QEMU uses TCG software emulation.${RESET}"
    echo

    create_vps
}

configure_network() {
    header
    section_title "VPS NETWORK"
    load_vps_env

    echo -e "  ${DIM}Current:${RESET} ${CYAN}localhost:${TCP_HOST_PORT} -> VM:${TCP_GUEST_PORT}${RESET}"
    echo
    read -r -p "  New host SSH port [${TCP_HOST_PORT}]: " value
    TCP_HOST_PORT="${value:-$TCP_HOST_PORT}"
    save_vps_env
    echo
    status_ok "SSH forwarding port saved: ${TCP_HOST_PORT}"
    pause_screen
}

clean_vps() {
    header
    section_title "CLEAN VPS"
    echo -e "  ${YELLOW}This removes the saved VPS disk, cloud-init and configuration.${RESET}"
    echo
    read -r -p "  Continue? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || return

    run_silent "Removing VPS files" rm -rf "$VPS_DIR" || { mkdir -p "$VPS_DIR"; pause_screen; return; }
    mkdir -p "$VPS_DIR"
    rm -f "$VPS_ENV" 2>/dev/null || true
    status_ok "VPS workspace cleaned"
    pause_screen
}

vps_menu() {
    while true; do
        header
        section_title ".VPS"
        local detected_id detected_version detected_name
        IFS='|' read -r detected_id detected_version detected_name <<< "$(detect_host_os)"
        echo -e "  ${DIM}Detected OS:${RESET} ${CYAN}${detected_name} (${detected_id} ${detected_version})${RESET}"
        echo

        echo -e "  ${BRIGHT_CYAN}${BOLD}01${RESET}  ${WHITE}VPS with Virtualisation${RESET}"
        echo -e "      ${DIM}Uses KVM if available; otherwise falls back to TCG${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}02${RESET}  ${WHITE}VPS without Virtualisation${RESET}"
        echo -e "      ${DIM}QEMU TCG software emulation${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}03${RESET}  ${WHITE}Start Existing VPS${RESET}"
        echo -e "      ${DIM}Boot the saved VPS configuration${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}04${RESET}  ${WHITE}Network Settings${RESET}"
        echo -e "      ${DIM}Change the host SSH forwarding port${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}05${RESET}  ${WHITE}Clean VPS${RESET}"
        echo -e "      ${DIM}Remove VPS image and cloud-init files${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}00${RESET}  ${WHITE}Back${RESET}"
        echo

        read -r -p "  Select option [00-05]: " choice

        case "$choice" in
            1|01) vps_virtualization ;;
            2|02) vps_no_virtualization ;;
            3|03) start_vps ;;
            4|04) configure_network ;;
            5|05) clean_vps ;;
            0|00) return ;;
            *) status_fail "Invalid option"; sleep 1 ;;
        esac
    done
}

# ============================================================
# PTERODACTYL
# ============================================================

install_pterodactyl() {
    header
    section_title ".PTERODACTYL PANEL"

    echo -e "  ${WHITE}Pterodactyl Panel + Wings installer${RESET}"
    echo -e "  ${DIM}The official installer script will be downloaded and launched.${RESET}"
    echo

    status_warn "The Pterodactyl installer may require interactive choices."
    echo -e "  ${DIM}Installer output is logged to:${RESET} ${CYAN}${LOG_FILE}${RESET}"
    echo

    read -r -p "  Continue? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || return

    # Keep the command itself hidden. The installer receives a terminal so
    # interactive prompts remain usable; its output is also logged.
    echo
    echo -e "  ${CYAN}Pterodactyl installer${RESET} ${DIM}Working *${RESET}"
    echo

    bash <(curl -fsSL https://pterodactyl-installer.se) 2>&1 | tee -a "$LOG_FILE"

    echo
    status_ok "Pterodactyl installer finished"
    pause_screen
}

# ============================================================
# TOOLS
# ============================================================

install_playit() {
    header
    section_title ".TOOLS • PLAYIT"

    run_silent "Updating package index" "${SUDO_CMD[@]}" apt-get update -y || { pause_screen; return; }
    run_silent "Installing Playit dependencies" "${SUDO_CMD[@]}" apt-get install -y curl gnupg ca-certificates || { pause_screen; return; }

    local keyring="/etc/apt/trusted.gpg.d/playit.gpg"
    local repo="/etc/apt/sources.list.d/playit-cloud.list"

    if [ -n "$SUDO_CMD" ]; then
        curl -fsSL https://playit-cloud.github.io/ppa/key.gpg \
            | $SUDO_CMD gpg --dearmor --yes -o "$keyring" >>"$LOG_FILE" 2>&1
    else
        curl -fsSL https://playit-cloud.github.io/ppa/key.gpg \
            | gpg --dearmor --yes -o "$keyring" >>"$LOG_FILE" 2>&1
    fi

    echo "deb [signed-by=${keyring}] https://playit-cloud.github.io/ppa/data ./" \
        | $SUDO_CMD tee "$repo" >/dev/null

    run_silent "Refreshing Playit repository" "${SUDO_CMD[@]}" apt-get update -y || { pause_screen; return; }
    run_silent "Installing Playit" "${SUDO_CMD[@]}" apt-get install -y playit || { pause_screen; return; }

    status_ok "Playit installed successfully"
    echo -e "  ${DIM}Run Playit from your server when you are ready to authenticate it.${RESET}"
    pause_screen
}

# ---------- CLOUDFLARE TUNNEL ----------
install_cloudflare_tunnel() {
    header
    section_title ".TOOLS • CLOUDFLARE TUNNEL"

    echo -e "  ${WHITE}Cloudflare Tunnel installer${RESET}"
    echo -e "  ${DIM}Installing cloudflared and registering the tunnel as a service.${RESET}"
    echo

    # Add Cloudflare GPG key
    run_silent "Adding Cloudflare GPG key directory" \
        "${SUDO_CMD[@]}" mkdir -p --mode=0755 /usr/share/keyrings || { pause_screen; return; }

    if ! curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg \
        | "${SUDO_CMD[@]}" tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null 2>>"$LOG_FILE"; then
        status_fail "Failed to add Cloudflare GPG key"
        pause_screen
        return
    fi
    status_ok "Cloudflare GPG key added"

    # Add this repo to apt repositories
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' \
        | "${SUDO_CMD[@]}" tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

    # Install cloudflared
    run_silent "Updating package index" "${SUDO_CMD[@]}" apt-get update || { pause_screen; return; }
    run_silent "Installing cloudflared" "${SUDO_CMD[@]}" apt-get install cloudflared || { pause_screen; return; }

    echo
    echo -e "  ${BRIGHT_WHITE}${BOLD}Cloudflare Tunnel Token${RESET}"
    echo -e "  ${DIM}Paste your Cloudflare tunnel token or the full install command.${RESET}"
    echo -e "  ${DIM}Input is visible so you can confirm what was pasted.${RESET}"
    echo

    local tunnel_token token_input
    # Accept either a raw token or the full command copied from Cloudflare.
    # Input is intentionally visible at the user's request. It is never written
    # to the installer log.
    read -r -p "  Token or full install command: " token_input
    echo

    # Trim leading/trailing whitespace.
    token_input="${token_input#"${token_input%%[![:space:]]*}"}"
    token_input="${token_input%"${token_input##*[![:space:]]}"}"
    token_input="${token_input%$'\r'}"

    # If the user pasted `sudo cloudflared service install TOKEN`, extract only
    # the token. This parses text only; the pasted command is never executed.
    if [[ "$token_input" =~ ^(sudo[[:space:]]+)?cloudflared[[:space:]]+service[[:space:]]+install[[:space:]]+(.+)$ ]]; then
        tunnel_token="${BASH_REMATCH[2]}"
    else
        tunnel_token="$token_input"
    fi

    # Remove optional matching surrounding quotes without evaluating the input.
    case "$tunnel_token" in
        \"*\") tunnel_token="${tunnel_token:1:${#tunnel_token}-2}" ;;
        '*') tunnel_token="${tunnel_token:1:${#tunnel_token}-2}" ;;
    esac
    tunnel_token="${tunnel_token%$'\r'}"
    tunnel_token="${tunnel_token#"${tunnel_token%%[![:space:]]*}"}"
    tunnel_token="${tunnel_token%"${tunnel_token##*[![:space:]]}"}"

    if [ -z "$tunnel_token" ]; then
        status_fail "Cloudflare tunnel token cannot be empty"
        pause_screen
        return
    fi

    # Do not impose an eyJ/base64 format check here. Cloudflare is the authority
    # that validates the tunnel token, and copied tokens can vary in formatting.
    if [ -z "$tunnel_token" ]; then
        status_fail "Cloudflare tunnel token cannot be empty"
        echo -e "  ${DIM}Paste either the raw token or: sudo cloudflared service install TOKEN${RESET}"
        pause_screen
        return
    fi

    status_ok "Cloudflare tunnel token received"
    echo -e "  ${DIM}Installing the tunnel service...${RESET}"

    # Do not log the token. Capture only cloudflared's error output so the user
    # can see why installation failed without exposing the secret.
    local cf_error="${LOG_DIR}/cloudflared-install-$$.err"
    rm -f "$cf_error"
    if ! "${SUDO_CMD[@]}" cloudflared service install "$tunnel_token" >"/dev/null" 2>"$cf_error"; then
        status_fail "Cloudflare tunnel service installation failed"
        if [ -s "$cf_error" ]; then
            echo
            echo -e "  ${BRIGHT_YELLOW}${BOLD}cloudflared:${RESET}"
            sed 's/^[[:space:]]*/  /' "$cf_error" | tail -n 12
            cat "$cf_error" >> "$LOG_FILE" 2>/dev/null || true
        fi
        rm -f "$cf_error"
        echo -e "  ${DIM}The tunnel token itself was not written to the log.${RESET}"
        pause_screen
        return
    fi
    rm -f "$cf_error"

    status_ok "Cloudflare Tunnel service installed"
    echo
    echo -e "  ${BRIGHT_GREEN}${BOLD}Add these exactly in routine in Cloudflare Tunnel:${RESET}"
    echo -e "  ${DIM}Type:${RESET} https"
    echo -e "  ${DIM}URL:${RESET} localhost:8443"
    echo -e "  ${DIM}Enable TLS:${RESET} yes"
    echo
    echo -e "  ${WHITE}Panel Settings:${RESET}"
    echo -e "  ${DIM}ufw-no:${RESET} html"
    echo -e "  ${DIM}encryption:${RESET} n"
    echo -e "  ${DIM}assume SSL:${RESET} y"
    echo -e "  ${DIM}HTTPS request:${RESET} n"
    echo
    echo -e "  ${WHITE}For Wings, in routine Cloudflare:${RESET}"
    echo -e "  ${DIM}Type:${RESET} https"
    echo -e "  ${DIM}URL:${RESET} localhost"
    echo -e "  ${DIM}Enable TLS:${RESET} yes"
    echo
    status_ok "Cloudflare Tunnel setup is done"
    echo -e "  ${DIM}You are ready to continue.${RESET}"
    pause_screen
}

# ---------- PUFFERPANEL ----------
install_pufferpanel() {
    header
    section_title ".TOOLS • PUFFERPANEL"

    echo -e "  ${WHITE}PufferPanel installer${RESET}"
    echo -e "  ${DIM}PufferPanel will be configured for web port 8081.${RESET}"
    echo

    echo -e "  ${BRIGHT_WHITE}${BOLD}Install Cloudflare Tunnel first?${RESET}"
    echo -e "  ${DIM}If Yes, cloudflared will be installed and you can paste either:${RESET}"
    echo -e "  ${DIM}• the raw tunnel token${RESET}"
    echo -e "  ${DIM}• sudo cloudflared service install TOKEN${RESET}"
    echo

    local cf_answer
    read -r -p "  Install Cloudflare Tunnel? [y/N]: " cf_answer
    echo

    if [[ "$cf_answer" =~ ^[Yy]$ ]]; then
        # Reuse the existing Cloudflare installer. It keeps the token visible
        # while never writing the token itself to the installer log.
        install_cloudflare_tunnel || {
            status_fail "Cloudflare Tunnel installation failed. PufferPanel installation cancelled."
            pause_screen
            return
        }
        echo
    else
        status_ok "Cloudflare Tunnel skipped"
        echo
    fi

    echo -e "  ${BRIGHT_WHITE}${BOLD}Installing PufferPanel${RESET}"
    echo

    run_silent "Updating package index" "${SUDO_CMD[@]}" apt-get update || { pause_screen; return; }
    run_silent "Installing PufferPanel dependencies" "${SUDO_CMD[@]}" apt-get install -y curl gnupg apt-transport-https || { pause_screen; return; }

    run_silent "Creating PufferPanel keyring directory" \
        "${SUDO_CMD[@]}" mkdir -p /etc/apt/keyrings || { pause_screen; return; }

    local puffer_key="/etc/apt/keyrings/pufferpanel.gpg"
    local puffer_repo="/etc/apt/sources.list.d/pufferpanel.sources"

    if ! curl -fsSL https://packagecloud.io/pufferpanel/pufferpanel/gpgkey \
        | "${SUDO_CMD[@]}" gpg --dearmor --yes \
            | "${SUDO_CMD[@]}" tee "$puffer_key" >/dev/null 2>>"$LOG_FILE"; then
        status_fail "Failed to add PufferPanel GPG key"
        pause_screen
        return
    fi
    status_ok "PufferPanel GPG key added"

    cat <<'EOF' | "${SUDO_CMD[@]}" tee "$puffer_repo" >/dev/null
X-Repolib-Name: PufferPanel
Types: deb
URIs: https://packagecloud.io/pufferpanel/pufferpanel/any/
Suites: any
Components: main
Signed-By: /etc/apt/keyrings/pufferpanel.gpg
EOF

    status_ok "PufferPanel repository added"

    run_silent "Refreshing PufferPanel repository" "${SUDO_CMD[@]}" apt-get update || { pause_screen; return; }
    run_silent "Installing PufferPanel" "${SUDO_CMD[@]}" apt-get install -y pufferpanel || { pause_screen; return; }

    # PufferPanel defaults to 0.0.0.0:8080. Change the web listener to 8081.
    # Keep this limited to the documented web.host value so unrelated settings
    # are not modified.
    local puffer_config="/etc/pufferpanel/config.json"
    if "${SUDO_CMD[@]}" test -f "$puffer_config"; then
        if "${SUDO_CMD[@]}" sed -i \
            's/"host"[[:space:]]*:[[:space:]]*"0\.0\.0\.0:8080"/"host": "0.0.0.0:8081"/' \
            "$puffer_config"; then
            status_ok "PufferPanel web port set to 8081"
        else
            status_fail "Could not change PufferPanel web port"
            pause_screen
            return
        fi
    else
        status_warn "PufferPanel config.json was not found; leaving package defaults unchanged"
    fi

    # PufferPanel packages ship pufferpanel.service, but LAPIOPLAYS can also
    # be executed inside containers where systemd is not PID 1. In that case
    # `systemctl enable` fails even though PufferPanel itself is installed.
    # Detect that situation before calling systemctl and use PufferPanel's
    # built-in runService command instead.
    local puffer_systemd=0
    if command -v systemctl >/dev/null 2>&1 \
        && [ -d /run/systemd/system ] \
        && [ "$(ps -p 1 -o comm= 2>/dev/null || true)" = "systemd" ]; then
        puffer_systemd=1
    fi

    if [ "$puffer_systemd" -eq 1 ]; then
        run_silent "Reloading systemd" "${SUDO_CMD[@]}" systemctl daemon-reload || { pause_screen; return; }
        run_silent "Enabling PufferPanel service" "${SUDO_CMD[@]}" systemctl enable pufferpanel || { pause_screen; return; }
        run_silent "Starting PufferPanel service" "${SUDO_CMD[@]}" systemctl restart pufferpanel || { pause_screen; return; }
        status_ok "PufferPanel service is running"
    else
        status_warn "systemd is not available; using PufferPanel runService mode"

        # Stop an older manually-started instance if we know its PID.
        local puffer_pid_file="/run/pufferpanel.pid"
        if [ -f "$puffer_pid_file" ]; then
            local old_pid
            old_pid="$(cat "$puffer_pid_file" 2>/dev/null || true)"
            if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
                "${SUDO_CMD[@]}" kill "$old_pid" 2>/dev/null || true
                sleep 1
            fi
            "${SUDO_CMD[@]}" rm -f "$puffer_pid_file" 2>/dev/null || true
        fi

        local puffer_log="/var/log/pufferpanel.log"
        "${SUDO_CMD[@]}" bash -c \
            'nohup /usr/sbin/pufferpanel runService >>/var/log/pufferpanel.log 2>&1 </dev/null & echo $! >/run/pufferpanel.pid'
        sleep 2

        local puffer_pid
        puffer_pid="$("${SUDO_CMD[@]}" cat "$puffer_pid_file" 2>/dev/null || true)"
        if [[ "$puffer_pid" =~ ^[0-9]+$ ]] && kill -0 "$puffer_pid" 2>/dev/null; then
            status_ok "PufferPanel started with runService"
            echo -e "  ${DIM}Runtime log:${RESET} ${CYAN}${puffer_log}${RESET}"
        else
            status_fail "PufferPanel failed to start"
            echo -e "  ${DIM}Check:${RESET} ${CYAN}${puffer_log}${RESET}"
            pause_screen
            return
        fi
    fi

    echo
    echo -e "  ${BRIGHT_WHITE}${BOLD}Create PufferPanel admin user${RESET}"
    echo -e "  ${DIM}The official PufferPanel command will now open its interactive prompts.${RESET}"
    echo -e "  ${DIM}Make sure to answer Y when it asks whether the user is an admin.${RESET}"
    echo

    # Keep this interactive: PufferPanel asks for username, password and admin
    # confirmation. The command itself and any password are not copied to the log.
    if "${SUDO_CMD[@]}" pufferpanel user add; then
        echo
        status_ok "PufferPanel user created"
    else
        echo
        status_fail "PufferPanel user creation failed or was cancelled"
        echo -e "  ${DIM}You can retry later with: sudo pufferpanel user add${RESET}"
        pause_screen
        return
    fi

    echo
    status_ok "PufferPanel installation completed"
    echo -e "  ${DIM}Panel:${RESET} ${CYAN}http://YOUR_SERVER_IP:8081${RESET}"
    echo -e "  ${DIM}Service:${RESET} ${CYAN}pufferpanel${RESET}"
    echo
    pause_screen
}

delete_cloudflare_tunnel() {
    header
    section_title ".TOOLS • DELETE CLOUDFLARE TUNNEL"

    echo -e "  ${YELLOW}This removes the existing cloudflared tunnel service.${RESET}"
    echo

    if "${SUDO_CMD[@]}" cloudflared service uninstall >>"$LOG_FILE" 2>&1; then
        status_ok "Cloudflare Tunnel service deleted"
    else
        status_warn "Cloudflare Tunnel service was not installed or could not be removed"
    fi

    echo
    echo -e "  ${DIM}If you also want to delete the Cloudflare tunnel itself, enter its name or ID.${RESET}"
    echo -e "  ${DIM}Leave empty to only remove the local service.${RESET}"
    echo
    local tunnel_name
    read -r -p "  Tunnel name/ID [optional]: " tunnel_name

    if [ -n "$tunnel_name" ]; then
        read -r -p "  Delete tunnel '$tunnel_name' from Cloudflare? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            if cloudflared tunnel delete "$tunnel_name" >>"$LOG_FILE" 2>&1; then
                status_ok "Cloudflare tunnel deleted: $tunnel_name"
            else
                status_fail "Could not delete tunnel: $tunnel_name"
                echo -e "  ${DIM}See: ${LOG_FILE}${RESET}"
            fi
        else
            status_warn "Tunnel deletion cancelled"
        fi
    fi

    pause_screen
}

install_proxmox_container() {
    header
    section_title ".TOOLS • PROXMOX VE (DOCKER)"
    echo -e "  ${DIM}This runs a community Proxmox-in-Docker image, not a supported full Proxmox host install.${RESET}"
    echo -e "  ${DIM}It needs Docker and privileged-container access; nested virtualization and systemd may not work on every VPS.${RESET}"
    echo

    if ! command -v docker >/dev/null 2>&1; then
        local os_id os_name
        IFS='|' read -r os_id _ os_name <<< "$(detect_host_os)"
        os_id="${os_id,,}"
        case "$os_id" in
            ubuntu|debian|linuxmint|pop|elementary|kali)
                run_silent "Updating package index" "${SUDO_CMD[@]}" apt-get update || { pause_screen; return 1; }
                run_silent "Installing Docker" "${SUDO_CMD[@]}" apt-get install -y docker.io || { pause_screen; return 1; }
                ;;
            fedora)
                run_silent "Installing Docker-compatible engine" "${SUDO_CMD[@]}" dnf install -y moby-engine || {
                    status_fail "Docker package unavailable. Install Docker Engine using the official Docker instructions for Fedora."; pause_screen; return 1;
                }
                ;;
            centos|rhel|rocky|almalinux|ol)
                run_silent "Installing container engine" "${SUDO_CMD[@]}" dnf install -y docker || {
                    status_fail "Docker package unavailable. Install Docker Engine for ${os_name}, then retry."; pause_screen; return 1;
                }
                ;;
            *) status_fail "Cannot auto-install Docker on ${os_name}; install Docker Engine then retry."; pause_screen; return 1 ;;
        esac
    fi

    if ! "${SUDO_CMD[@]}" docker info >/dev/null 2>&1; then
        if command -v systemctl >/dev/null 2>&1; then
            "${SUDO_CMD[@]}" systemctl enable --now docker >>"$LOG_FILE" 2>&1 || true
        fi
    fi
    if ! "${SUDO_CMD[@]}" docker info >/dev/null 2>&1; then
        status_fail "Docker daemon is not running or this environment blocks Docker. See ${LOG_FILE}."
        pause_screen
        return 1
    fi

    if "${SUDO_CMD[@]}" docker container inspect proxmoxve >/dev/null 2>&1; then
        read -r -p "  Container 'proxmoxve' already exists. Remove and recreate it? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            "${SUDO_CMD[@]}" docker rm -f proxmoxve >>"$LOG_FILE" 2>&1 || { status_fail "Could not remove existing container"; pause_screen; return 1; }
        else
            status_warn "Keeping existing container. Open http://SERVER-IP:3004 if it is running."
            pause_screen
            return 0
        fi
    fi

    run_silent "Pulling Proxmox container image" "${SUDO_CMD[@]}" docker pull rtedpro/proxmox:8.4.x || { pause_screen; return 1; }
    run_silent "Creating Proxmox container on host port 3004" "${SUDO_CMD[@]}" docker run -d \
        --name proxmoxve --hostname pve --restart unless-stopped \
        -p 3004:8006 --privileged rtedpro/proxmox:8.4.x || { pause_screen; return 1; }

    echo
    status_ok "Proxmox container started (if supported by this host)"
    echo -e "  ${DIM}Web UI: http://SERVER-IP:3004${RESET}"
    echo -e "  ${DIM}Container shell: sudo docker exec -it proxmoxve bash${RESET}"
    echo -e "  ${DIM}If the UI does not load, inspect: docker logs proxmoxve${RESET}"
    pause_screen
}

tools_menu() {
    while true; do
        header
        section_title ".TOOLS"

        echo -e "  ${CYAN}01${RESET}  ${WHITE}Playit${RESET}"
        echo -e "      ${DIM}Install Playit tunnel service${RESET}"
        echo
        echo -e "  ${CYAN}02${RESET}  ${WHITE}Cloudflare Tunnel${RESET}"
        echo -e "      ${DIM}Install or delete Cloudflare Tunnel${RESET}"
        echo
        echo -e "  ${CYAN}03${RESET}  ${WHITE}PufferPanel${RESET}"
        echo -e "      ${DIM}Install PufferPanel on web port 8081${RESET}"
        echo
        echo -e "  ${CYAN}04${RESET}  ${WHITE}Proxmox VE (Docker)${RESET}"
        echo -e "      ${DIM}Experimental container, web port 3004${RESET}"
        echo
        echo -e "  ${CYAN}05${RESET}  ${WHITE}OS Systems${RESET}"
        echo -e "      ${DIM}Ubuntu 22.04 / 20.04 proot rootfs manager${RESET}"
        echo
        echo -e "  ${CYAN}00${RESET}  ${WHITE}Back${RESET}"
        echo

        read -r -p "  Select › " choice

        case "$choice" in
            1|01) install_playit ;;
            2|02)
                while true; do
                    header
                    section_title ".TOOLS • CLOUDFLARE TUNNEL"

                    echo -e "  ${CYAN}01${RESET}  ${WHITE}Install Tunnel${RESET}"
                    echo -e "      ${DIM}Install cloudflared and configure the tunnel service${RESET}"
                    echo
                    echo -e "  ${CYAN}02${RESET}  ${WHITE}Delete Tunnel${RESET}"
                    echo -e "      ${DIM}Delete the existing Cloudflare Tunnel service/tunnel${RESET}"
                    echo
                    echo -e "  ${CYAN}00${RESET}  ${WHITE}Back${RESET}"
                    echo

                    read -r -p "  Select › " tunnel_choice

                    case "$tunnel_choice" in
                        1|01) install_cloudflare_tunnel ;;
                        2|02) delete_cloudflare_tunnel ;;
                        0|00) break ;;
                        *) status_fail "Invalid selection"; sleep 1 ;;
                    esac
                done
                ;;
            3|03) install_pufferpanel ;;
            4|04) install_proxmox_container ;;
            5|05) os_systems_menu ;;
            0|00) return ;;
            *) status_fail "Invalid selection"; sleep 1 ;;
        esac
    done
}



# ============================================================
# OS SYSTEMS (PROOT ROOT FILESYSTEMS)
# ============================================================

OS_DIR="${HOME}/.lapio-bhai/os-systems"

install_os_dependencies() {
    if ! command -v proot >/dev/null 2>&1; then
        run_silent "Updating package index" "${SUDO_CMD[@]}" apt-get update || return 1
        run_silent "Installing proot and download tools" "${SUDO_CMD[@]}" apt-get install -y proot wget ca-certificates tar || return 1
    fi
    command -v wget >/dev/null 2>&1 || {
        run_silent "Installing wget" "${SUDO_CMD[@]}" apt-get install -y wget || return 1
    }
}

os_system_install_or_start() {
    local version="$1"
    local release="$2"
    local rootfs="${OS_DIR}/ubuntu-${version}"
    local archive="/tmp/lapio-ubuntu-${version}-$$.tar.gz"
    local arch url

    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) status_fail "Unsupported host architecture: $(uname -m)"; pause_screen; return 1 ;;
    esac

    mkdir -p "$OS_DIR"
    header
    section_title "OS SYSTEMS • UBUNTU ${version}"

    if [ ! -f "${rootfs}/.lapio-installed" ]; then
        echo -e "  ${DIM}This creates a user-space Ubuntu root filesystem. Root access inside it is simulated by proot (-0); it does not grant host-root privileges.${RESET}"
        echo
        install_os_dependencies || { pause_screen; return 1; }

        url="https://cdimage.ubuntu.com/ubuntu-base/releases/${release}/release/ubuntu-base-${release}-base-${arch}.tar.gz"
        run_silent "Downloading Ubuntu ${version} (${arch})" wget --tries=5 --timeout=20 -O "$archive" "$url" || {
            rm -f "$archive"
            status_fail "Download failed. Check the Ubuntu Base release URL or network."
            pause_screen
            return 1
        }

        mkdir -p "$rootfs"
        if ! run_silent "Extracting Ubuntu ${version}" tar -xzf "$archive" -C "$rootfs"; then
            rm -f "$archive"
            rm -rf "$rootfs"
            pause_screen
            return 1
        fi
        rm -f "$archive"
        mkdir -p "${rootfs}/tmp" "${rootfs}/root"
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "${rootfs}/etc/resolv.conf"
        touch "${rootfs}/.lapio-installed"
        status_ok "Ubuntu ${version} root filesystem installed"
    else
        status_ok "Ubuntu ${version} root filesystem already exists"
    fi

    echo
    echo -e "  ${DIM}Login shell: root (proot user-space emulation)${RESET}"
    echo -e "  ${DIM}Exit Ubuntu by typing:${RESET} ${CYAN}exit${RESET}"
    echo
    # -0 provides root-like identity inside the rootfs only, not real host root.
    proot -0 -r "$rootfs" -w /root \
        -b /dev -b /proc -b /sys -b /etc/resolv.conf:/etc/resolv.conf \
        /usr/bin/env -i HOME=/root USER=root LOGNAME=root \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        TERM="${TERM:-xterm-256color}" /bin/bash --login
    pause_screen
}

os_systems_menu() {
    while true; do
        header
        section_title "OS SYSTEMS • ROOTFS MANAGER"
        echo -e "  ${CYAN}01${RESET}  ${WHITE}Ubuntu 22.04 LTS (Jammy)${RESET}"
        echo -e "      ${DIM}Install or launch Ubuntu 22.04 with proot root-like access${RESET}"
        echo
        echo -e "  ${CYAN}02${RESET}  ${WHITE}Ubuntu 20.04 LTS (Focal)${RESET}"
        echo -e "      ${DIM}Install or launch Ubuntu 20.04 with proot root-like access${RESET}"
        echo
        echo -e "  ${CYAN}03${RESET}  ${WHITE}List installed OS systems${RESET}"
        echo
        echo -e "  ${CYAN}00${RESET}  ${WHITE}Back${RESET}"
        echo
        read -r -p "  Select › " choice
        case "$choice" in
            1|01) os_system_install_or_start "22.04" "22.04" ;;
            2|02) os_system_install_or_start "20.04" "20.04" ;;
            3|03)
                header
                section_title "INSTALLED OS SYSTEMS"
                [ ! -f "${OS_DIR}/ubuntu-22.04/.lapio-installed" ] || status_ok "Ubuntu 22.04 installed"
                [ ! -f "${OS_DIR}/ubuntu-20.04/.lapio-installed" ] || status_ok "Ubuntu 20.04 installed"
                if [ ! -f "${OS_DIR}/ubuntu-22.04/.lapio-installed" ] && [ ! -f "${OS_DIR}/ubuntu-20.04/.lapio-installed" ]; then
                    status_warn "No OS systems installed yet"
                fi
                pause_screen
                ;;
            0|00) return ;;
            *) status_fail "Invalid selection"; sleep 1 ;;
        esac
    done
}

# ============================================================
# DASHBOARDS
# ============================================================

install_chunkdash() {
    header
    section_title ".DASHBOARDS • CHUNKDASH"

    local dir="${HOME}/Hosting-panel"

    if [ -d "$dir" ]; then
        read -r -p "  Existing Hosting-panel found. Reinstall? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            run_silent "Removing existing ChunkDash" rm -rf "$dir" || return
        else
            status_warn "Installation cancelled"
            pause_screen
            return
        fi
    fi

    run_silent "Downloading ChunkDash" \
        git clone https://github.com/deadlauncherg/Hosting-panel.git "$dir" || {
        pause_screen
        return
    }

    cd "$dir"

    # Install NVM silently.
    local nvm_dir="${HOME}/.nvm"
    if [ ! -s "${nvm_dir}/nvm.sh" ]; then
        run_silent "Installing Node Version Manager" \
            bash -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash' || {
            pause_screen
            return
        }
    fi

    # Load NVM without printing commands.
    export NVM_DIR="$nvm_dir"
    # shellcheck disable=SC1090
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

    run_silent "Installing Node.js 18" nvm install 18 || {
        pause_screen
        return
    }

    run_silent "Selecting Node.js 18" nvm use 18 || {
        pause_screen
        return
    }

    run_silent "Installing ChunkDash packages" npm install || {
        pause_screen
        return
    }

    echo
    status_ok "ChunkDash / Feastic dashboard installed"
    echo
    echo -e "  ${YELLOW}Next step:${RESET}"
    echo -e "  ${DIM}Edit:${RESET} ${CYAN}${dir}/settings.json${RESET}"
    echo -e "  ${DIM}Then start the dashboard from its project directory.${RESET}"
    echo
    pause_screen
}

dashboards_menu() {
    while true; do
        header
        section_title ".DASHBOARDS"

        echo -e "  ${CYAN}01${RESET}  ${WHITE}ChunkDash • Feastic Theme${RESET}"
        echo -e "      ${DIM}Install Lapio's custom hosting dashboard${RESET}"
        echo
        echo -e "  ${CYAN}02${RESET}  ${DIM}Coming Soon${RESET}"
        echo
        echo -e "  ${CYAN}03${RESET}  ${DIM}Coming Soon${RESET}"
        echo
        echo -e "  ${CYAN}00${RESET}  ${WHITE}Back${RESET}"
        echo

        read -r -p "  Select › " choice

        case "$choice" in
            1) install_chunkdash ;;
            2|3) status_warn "This dashboard slot is coming soon"; sleep 1 ;;
            0|00) return ;;
            *) status_fail "Invalid selection"; sleep 1 ;;
        esac
    done
}

# ============================================================
# MAIN MENU
# ============================================================

main_menu() {
    while true; do
        header

        local host_arch kvm_status kvm_label kvm_color virt_type
        local ram_stats ram_used ram_total ram_percent
        local disk_stats disk_used disk_total disk_percent
        local cpu_percent cpu_color
        local uptime_short

        host_arch="$(uname -m 2>/dev/null || echo unknown)"
        virt_type="$(detect_virt_type)"
        kvm_status="$(detect_virtualization)"

        if [ "$kvm_status" = "available" ]; then
            kvm_label="AVAILABLE"
            kvm_color="$BRIGHT_GREEN"
        else
            kvm_label="UNAVAILABLE"
            kvm_color="$BRIGHT_YELLOW"
        fi

        ram_stats="$(get_ram_stats)"
        IFS='|' read -r ram_used ram_total ram_percent <<< "$ram_stats"

        disk_stats="$(get_disk_stats)"
        IFS='|' read -r disk_used disk_total disk_percent <<< "$disk_stats"

        cpu_percent="$(get_cpu_percent)"
        cpu_color="$(resource_status_color "$cpu_percent")"
        uptime_short="$(get_uptime_short)"

        echo -e "  ${BRIGHT_GREEN}${BOLD}● ONLINE${RESET}  ${DIM}HOST${RESET} ${WHITE}${host_arch}${RESET}  ${DIM}VIRT${RESET} ${WHITE}${virt_type}${RESET}  ${DIM}KVM${RESET} ${kvm_color}${BOLD}${kvm_label}${RESET}"
        echo

        # Compact live resource panel. All values are read locally and safely
        # fall back to zero/unknown if a utility is unavailable.
        echo -e "  ${BRIGHT_BLUE}${BOLD}╭──────────────────── LIVE SYSTEM ───────────────────────────╮${RESET}"
        echo -e "  ${BRIGHT_BLUE}${BOLD}│${RESET}  ${BRIGHT_WHITE}${BOLD}RAM${RESET}   ${DIM}$(human_gb "$ram_used") / $(human_gb "$ram_total")${RESET}  ${cpu_color}${BOLD}${ram_percent}%${RESET}  $(usage_bar "$ram_percent") ${BRIGHT_BLUE}${BOLD}│${RESET}"
        echo -e "  ${BRIGHT_BLUE}${BOLD}│${RESET}  ${BRIGHT_WHITE}${BOLD}DISK${RESET}  ${DIM}$(human_gb "$((disk_used / 1024))") / $(human_gb "$((disk_total / 1024))")${RESET}  $(resource_status_color "$disk_percent")${BOLD}${disk_percent}%${RESET}  $(usage_bar "$disk_percent") ${BRIGHT_BLUE}${BOLD}│${RESET}"
        echo -e "  ${BRIGHT_BLUE}${BOLD}│${RESET}  ${BRIGHT_WHITE}${BOLD}CPU${RESET}   ${DIM}load usage${RESET}  ${cpu_color}${BOLD}${cpu_percent}%${RESET}  $(usage_bar "$cpu_percent")   ${DIM}UP ${uptime_short}${RESET} ${BRIGHT_BLUE}${BOLD}│${RESET}"
        echo -e "  ${BRIGHT_BLUE}${BOLD}╰────────────────────────────────────────────────────────────╯${RESET}"
        echo

        line
        echo -e "  ${BRIGHT_WHITE}${BOLD}MAIN MENU${RESET}  ${DIM}Select a module to continue${RESET}"
        echo

        echo -e "  ${BRIGHT_CYAN}${BOLD}01${RESET}  ${BRIGHT_WHITE}${BOLD}.VPS${RESET}"
        echo -e "      ${DIM}Virtualisation, TCG mode and VPS management${RESET}"
        echo
        echo -e "  ${BRIGHT_MAGENTA}${BOLD}02${RESET}  ${BRIGHT_WHITE}${BOLD}.PTERODACTYL${RESET}"
        echo -e "      ${DIM}Install Pterodactyl Panel and Wings${RESET}"
        echo
        echo -e "  ${BRIGHT_YELLOW}${BOLD}03${RESET}  ${BRIGHT_WHITE}${BOLD}.TOOLS${RESET}"
        echo -e "      ${DIM}Server and networking tools${RESET}"
        echo
        echo -e "  ${BRIGHT_BLUE}${BOLD}04${RESET}  ${BRIGHT_WHITE}${BOLD}.DASHBOARDS${RESET}"
        echo -e "      ${DIM}ChunkDash / Feastic hosting dashboard${RESET}"
        echo
        echo -e "  ${BRIGHT_GREEN}${BOLD}05${RESET}  ${BRIGHT_WHITE}${BOLD}LOGS${RESET}"
        echo -e "      ${DIM}View recent installer errors${RESET}"
        echo
        echo -e "  ${DIM}${BOLD}00${RESET}  ${BRIGHT_WHITE}${BOLD}EXIT${RESET}"
        echo

        line
        echo -e "  ${DIM}LAPIOPLAYS${RESET} ${BRIGHT_CYAN}›${RESET} ${DIM}Ready for command${RESET}"
        printf -v MAIN_MENU_PROMPT "  %s%sSelect [00-05] › %s" "$BRIGHT_CYAN" "$BOLD" "$RESET"
        read -r -p "$MAIN_MENU_PROMPT" choice

        case "$choice" in
            1|01) vps_menu ;;
            2|02) install_pterodactyl ;;
            3|03) tools_menu ;;
            4|04) dashboards_menu ;;
            5|05)
                header
                section_title "INSTALLER LOG"
                echo -e "  ${DIM}${LOG_FILE}${RESET}"
                echo
                tail -n 60 "$LOG_FILE" 2>/dev/null || true
                pause_screen
                ;;
            0|00)
                clear
                echo
                echo -e "  ${BRIGHT_CYAN}${BOLD}LAPIOPLAYS${RESET} ${DIM}installer closed.${RESET}"
                echo
                exit 0
                ;;
            *) status_fail "Invalid option"; sleep 1 ;;
        esac
    done
}

# ---------- Error trap ----------
trap 'rc=$?; echo "[ERROR] command failed (exit $rc) at ${BASH_SOURCE[0]}:${LINENO}" >> "$LOG_FILE"; status_fail "Command failed at line ${LINENO} (exit ${rc}). See: ${LOG_FILE}"' ERR

main_menu
