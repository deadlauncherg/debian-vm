#!/bin/bash
set -Eeuo pipefail

# ============================================================
#                         LAPIO BHAI
#              Professional Server Installer
# ============================================================

# ---------- Colors ----------
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
BLACK='\033[30m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
WHITE='\033[37m'
BRIGHT_BLUE='\033[94m'
BRIGHT_CYAN='\033[96m'
BRIGHT_WHITE='\033[97m'

APP_NAME="LAPIO BHAI"
APP_VERSION="2.0"
LOG_DIR="${HOME}/.lapio-bhai"
LOG_FILE="${LOG_DIR}/installer.log"
VPS_DIR="${HOME}/.lapio-bhai/vps"
VPS_ENV="${VPS_DIR}/.vps_env"

mkdir -p "$LOG_DIR" "$VPS_DIR"
touch "$LOG_FILE"

# ---------- Root / sudo ----------
if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# ---------- Terminal helpers ----------
term_width() {
    tput cols 2>/dev/null || echo 80
}

line() {
    local width
    width=$(term_width)
    printf '%*s\n' "$width" '' | tr ' ' '─'
}

pause_screen() {
    echo
    read -r -p "  Press ENTER to continue..." _
}

status_ok() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

status_warn() {
    echo -e "  ${YELLOW}!${RESET} $1"
}

status_fail() {
    echo -e "  ${RED}✗${RESET} $1"
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
        echo -e "${GREEN}✓${RESET}"
        cat "$tmp" >> "$LOG_FILE" 2>/dev/null || true
        rm -f "$tmp"
        return 0
    else
        printf '\b'
        echo -e "${RED}✗${RESET}"
        {
            echo
            echo "========== FAILED TASK: $label =========="
            cat "$tmp" 2>/dev/null || true
        } >> "$LOG_FILE"
        rm -f "$tmp"
        status_warn "Task failed. Details: $LOG_FILE"
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
        echo -e "${GREEN}✓${RESET}"
        return 0
    fi

    printf '\b'
    echo -e "${RED}✗${RESET}"
    return 1
}

header() {
    clear
    echo
    echo -e "  ${BRIGHT_CYAN}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${BRIGHT_CYAN}${BOLD}║${RESET}                ${BRIGHT_WHITE}${BOLD}LAPIO BHAI${RESET}                         ${BRIGHT_CYAN}${BOLD}║${RESET}"
    echo -e "  ${BRIGHT_CYAN}${BOLD}║${RESET}          ${DIM}SERVER INSTALLER • v${APP_VERSION}${RESET}              ${BRIGHT_CYAN}${BOLD}║${RESET}"
    echo -e "  ${BRIGHT_CYAN}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
    echo
}

section_title() {
    local title="$1"
    echo -e "  ${BRIGHT_BLUE}${BOLD}┌─ ${title}${RESET}"
    echo -e "  ${BRIGHT_BLUE}${BOLD}└──────────────────────────────────────────────────────${RESET}"
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

detect_virtualization() {
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo "available"
    else
        echo "unavailable"
    fi
}

install_vps_dependencies() {
    run_silent "Updating package index" "$SUDO_CMD" apt-get update -y || return 1

    run_silent "Installing VPS dependencies" "$SUDO_CMD" apt-get install -y \
        qemu-system-x86 qemu-utils wget cloud-image-utils curl lsof ca-certificates
}

download_vps_image() {
    VPS_IMAGE="$VPS_DIR/ubuntu22.qcow2"

    if [ -f "$VPS_IMAGE" ]; then
        status_ok "Ubuntu 22.04 image cache found"
        return 0
    fi

    local raw="${VPS_DIR}/ubuntu22.img"

    run_silent "Downloading Ubuntu 22.04 image" \
        "$SUDO_CMD" wget -q \
        "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img" \
        -O "$raw" || return 1

    run_silent "Preparing VPS disk image" \
        "$SUDO_CMD" qemu-img convert -O qcow2 "$raw" "$VPS_IMAGE" || return 1

    rm -f "$raw"
    run_silent "Expanding VPS disk" \
        "$SUDO_CMD" qemu-img resize "$VPS_IMAGE" "${DISK_GB}G" || return 1

    "$SUDO_CMD" chmod 666 "$VPS_IMAGE" 2>/dev/null || true
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
        status_fail "VPS files are missing. Create a VPS first."
        pause_screen
        return
    fi

    header
    section_title "VPS STATUS"

    local kvm_args=()
    if [ "$VPS_MODE" = "virtualization" ] && [ "$(detect_virtualization)" = "available" ]; then
        kvm_args=(-enable-kvm -cpu host)
        status_ok "Hardware virtualization: ENABLED"
    else
        kvm_args=(-cpu max)
        status_warn "Hardware virtualization: OFF — using software emulation"
    fi

    echo
    echo -e "  ${WHITE}Resources${RESET}"
    echo -e "  ${DIM}RAM       ${RESET}${CYAN}${RAM_GB} GB${RESET}"
    echo -e "  ${DIM}CPU       ${RESET}${CYAN}${CPU_CORES} cores${RESET}"
    echo -e "  ${DIM}Disk      ${RESET}${CYAN}${DISK_GB} GB${RESET}"
    echo -e "  ${DIM}SSH       ${RESET}${CYAN}${TCP_HOST_PORT} → ${TCP_GUEST_PORT}${RESET}"
    echo

    echo -e "  ${YELLOW}Starting VPS...${RESET}"
    echo -e "  ${DIM}Press Ctrl+C to stop the VPS.${RESET}"
    echo

    qemu-system-x86_64 \
        "${kvm_args[@]}" \
        -m "${RAM_GB}G" \
        -smp "$CPU_CORES" \
        -drive "file=${image},format=qcow2,if=virtio" \
        -drive "file=${seed},format=raw,if=virtio" \
        -boot order=c \
        -nographic \
        -netdev "user,id=net0,hostfwd=tcp::${TCP_HOST_PORT}-:${TCP_GUEST_PORT}" \
        -device virtio-net-pci,netdev=net0
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

    if [ "$(detect_virtualization)" != "available" ]; then
        status_warn "/dev/kvm is not available on this host."
        echo -e "  ${DIM}The installer will still prepare the VPS, but QEMU will fall back to emulation.${RESET}"
        echo
    else
        status_ok "KVM virtualization detected"
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

vps_menu() {
    while true; do
        header
        section_title ".VPS INSTALLER"

        echo -e "  ${CYAN}01${RESET}  ${WHITE}VPS with Virtualisation${RESET}"
        echo -e "      ${DIM}QEMU + KVM hardware acceleration when available${RESET}"
        echo
        echo -e "  ${CYAN}02${RESET}  ${WHITE}VPS without Virtualisation${RESET}"
        echo -e "      ${DIM}QEMU software emulation / TCG mode${RESET}"
        echo
        echo -e "  ${CYAN}03${RESET}  ${WHITE}Start Existing VPS${RESET}"
        echo -e "      ${DIM}Boot the saved VPS configuration${RESET}"
        echo
        echo -e "  ${CYAN}04${RESET}  ${WHITE}Network Settings${RESET}"
        echo
        echo -e "  ${CYAN}05${RESET}  ${WHITE}Clean VPS${RESET}"
        echo
        echo -e "  ${CYAN}00${RESET}  ${WHITE}Back${RESET}"
        echo

        read -r -p "  Select › " choice

        case "$choice" in
            1) vps_virtualization ;;
            2) vps_no_virtualization ;;
            3) start_vps ;;
            4) vps_network ;;
            5) clean_vps ;;
            0|00) return ;;
            *) status_fail "Invalid selection"; sleep 1 ;;
        esac
    done
}

vps_network() {
    header
    section_title "VPS • NETWORK"

    load_vps_env

    echo -e "  Current: ${CYAN}${TCP_HOST_PORT} → ${TCP_GUEST_PORT}${RESET}"
    echo

    read -r -p "  New host port [${TCP_HOST_PORT}]: " value
    TCP_HOST_PORT="${value:-$TCP_HOST_PORT}"

    read -r -p "  Guest port [${TCP_GUEST_PORT}]: " value
    TCP_GUEST_PORT="${value:-$TCP_GUEST_PORT}"

    save_vps_env
    status_ok "Network settings saved"
    pause_screen
}

clean_vps() {
    header
    section_title "CLEAN VPS"

    read -r -p "  Remove the VPS image and configuration? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        run_silent "Removing VPS files" "$SUDO_CMD" rm -rf "$VPS_DIR"
        mkdir -p "$VPS_DIR"
        status_ok "VPS workspace cleaned"
    else
        status_warn "Cleanup cancelled"
    fi
    pause_screen
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

    run_silent "Updating package index" "$SUDO_CMD" apt-get update -y || { pause_screen; return; }
    run_silent "Installing Playit dependencies" "$SUDO_CMD" apt-get install -y curl gnupg ca-certificates || { pause_screen; return; }

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

    run_silent "Refreshing Playit repository" "$SUDO_CMD" apt-get update -y || { pause_screen; return; }
    run_silent "Installing Playit" "$SUDO_CMD" apt-get install -y playit || { pause_screen; return; }

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

        # System status
        local host_arch kvm_status
        host_arch="$(uname -m 2>/dev/null || echo unknown)"
        kvm_status="$(detect_virtualization)"

        echo -e "  ${GREEN}● ONLINE${RESET}    ${DIM}Host:${RESET} ${WHITE}${host_arch}${RESET}    ${DIM}KVM:${RESET} ${WHITE}${kvm_status}${RESET}"
        echo
        line
        echo
        echo -e "  ${BRIGHT_WHITE}${BOLD}INSTALLER MENU${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}01${RESET}  ${WHITE}.VPS${RESET}"
        echo -e "      ${DIM}Virtualisation / No Virtualisation / VPS manager${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}02${RESET}  ${WHITE}.PTERODACTYL${RESET}"
        echo -e "      ${DIM}Install Pterodactyl Panel + Wings${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}03${RESET}  ${WHITE}.TOOLS${RESET}"
        echo -e "      ${DIM}Server and networking tools${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}04${RESET}  ${WHITE}.DASHBOARDS${RESET}"
        echo -e "      ${DIM}ChunkDash / Feastic hosting dashboard${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}05${RESET}  ${WHITE}LOGS${RESET}"
        echo -e "      ${DIM}View installer activity and errors${RESET}"
        echo
        echo -e "  ${BRIGHT_CYAN}${BOLD}00${RESET}  ${WHITE}EXIT${RESET}"
        echo
        line
        echo
        read -r -p "  Select option › " choice

        case "$choice" in
            1|01) vps_menu ;;
            2|02) install_pterodactyl ;;
            3|03) tools_menu ;;
            4|04) dashboards_menu ;;
            5|05)
                header
                section_title "INSTALLER LOG"
                echo -e "  ${DIM}Log file:${RESET} ${CYAN}${LOG_FILE}${RESET}"
                echo
                tail -n 80 "$LOG_FILE" 2>/dev/null || true
                pause_screen
                ;;
            0|00)
                clear
                echo
                echo -e "  ${BRIGHT_CYAN}${BOLD}LAPIO BHAI${RESET} ${DIM}installer closed.${RESET}"
                echo
                exit 0
                ;;
            *)
                status_fail "Invalid selection. Choose a menu number."
                sleep 1
                ;;
        esac
    done
}

# ---------- Error trap ----------
trap 'echo; status_fail "Unexpected error. Check: $LOG_FILE"; pause_screen' ERR

main_menu
