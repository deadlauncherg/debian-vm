#!/bin/bash
set -Eeuo pipefail

# ============================================================
#                         LAPIO BHAI
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

APP_NAME="LAPIO BHAI"
APP_VERSION="2.5"
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
    local load cores percent
    load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
    cores="$(nproc 2>/dev/null || echo 1)"
    percent="$(awk -v load="$load" -v cores="$cores" 'BEGIN {
        if (cores < 1) cores=1;
        p=(load/cores)*100;
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
    echo -e "  ${BRIGHT_CYAN}${BOLD}│${RESET}  ${BRIGHT_MAGENTA}${BOLD}LAPIO BHAI${RESET}  ${DIM}•${RESET}  ${BRIGHT_WHITE}SERVER INSTALLER${RESET}  ${DIM}v${APP_VERSION}${RESET}       ${BRIGHT_CYAN}${BOLD}│${RESET}"
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

# Detect the host virtualization environment.
# For the "WITH VIRTUALISATION" option we require systemd-detect-virt
# to report KVM AND /dev/kvm to be usable. Option 02 is always the TCG fallback.
detect_virt_type() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        systemd-detect-virt 2>/dev/null || true
    else
        printf '%s' "unknown"
    fi
}

detect_virtualization() {
    local virt_type
    virt_type="$(detect_virt_type)"

    if [ "$virt_type" = "kvm" ] && [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo "available"
    else
        echo "unavailable"
    fi
}

kvm_detection_message() {
    local virt_type
    virt_type="$(detect_virt_type)"

    if [ "$virt_type" = "kvm" ] && [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo -e "  ${BRIGHT_GREEN}${BOLD}● KVM VIRTUALISATION AVAILABLE${RESET}"
        echo -e "  ${DIM}systemd-detect-virt:${RESET} ${GREEN}${virt_type}${RESET}"
        echo -e "  ${DIM}/dev/kvm:${RESET} ${GREEN}ready${RESET}"
        return 0
    fi

    echo -e "  ${BRIGHT_YELLOW}${BOLD}● KVM VIRTUALISATION UNAVAILABLE${RESET}"
    echo -e "  ${DIM}systemd-detect-virt:${RESET} ${YELLOW}${virt_type:-unknown}${RESET}"
    if [ -e /dev/kvm ]; then
        echo -e "  ${DIM}/dev/kvm:${RESET} ${YELLOW}not usable for this mode${RESET}"
    else
        echo -e "  ${DIM}/dev/kvm:${RESET} ${YELLOW}not available${RESET}"
    fi
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
    run_silent "Updating package index" "${SUDO_CMD[@]}" apt-get update || return 1
    run_silent "Installing VPS packages" "${SUDO_CMD[@]}" apt-get install -y \
        qemu-system-x86 qemu-utils wget cloud-image-utils curl lsof ca-certificates \
        || return 1
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
        if ! kvm_detection_message; then
            echo
            status_warn "Real KVM is not available for this VPS."
            echo -e "  ${DIM}Use option 02 (.VPS without Virtualisation) to run with QEMU TCG.${RESET}"
            echo
            echo -e "  ${BRIGHT_CYAN}Press ENTER to return to the VPS menu...${RESET}"
            read -r _
            return 0
        fi
        accel_args=(-enable-kvm)
        cpu_args=(-cpu host)
        echo
        status_ok "Starting with real KVM hardware acceleration"
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
    set +e
    "${SUDO_CMD[@]}" qemu-system-x86_64 \
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

    read -r -p "  RAM in GB [${RAM_GB}]: " value
    RAM_GB="${value:-$RAM_GB}"

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

    echo -e "  ${DIM}Checking host virtualisation with:${RESET} ${CYAN}systemd-detect-virt${RESET}"
    echo

    if ! kvm_detection_message; then
        echo
        status_warn "Option 01 requires real KVM."
        echo -e "  ${DIM}No VPS will be created in KVM mode.${RESET}"
        echo -e "  ${DIM}Choose option 02 to use QEMU TCG without KVM.${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}Press ENTER to return to the VPS menu...${RESET}"
        read -r _
        return 0
    fi

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
    echo -e "  ${DIM}No /dev/kvm requirement. QEMU will use TCG emulation.${RESET}"
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

        echo -e "  ${BRIGHT_CYAN}${BOLD}01${RESET}  ${WHITE}VPS with Virtualisation${RESET}"
        echo -e "      ${DIM}Real KVM VPS when systemd-detect-virt reports kvm${RESET}"
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

tools_menu() {
    while true; do
        header
        section_title ".TOOLS"

        echo -e "  ${CYAN}01${RESET}  ${WHITE}Playit${RESET}"
        echo -e "      ${DIM}Install Playit tunnel service${RESET}"
        echo
        echo -e "  ${CYAN}00${RESET}  ${WHITE}Back${RESET}"
        echo

        read -r -p "  Select › " choice

        case "$choice" in
            1) install_playit ;;
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
        echo -e "  ${DIM}LAPIO BHAI${RESET} ${BRIGHT_CYAN}›${RESET} ${DIM}Ready for command${RESET}"
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
                echo -e "  ${BRIGHT_CYAN}${BOLD}LAPIO BHAI${RESET} ${DIM}installer closed.${RESET}"
                echo
                exit 0
                ;;
            *) status_fail "Invalid option"; sleep 1 ;;
        esac
    done
}

# ---------- Error trap ----------
trap 'echo; status_fail "Unexpected error. See: $LOG_FILE"; pause_screen' ERR

main_menu
