#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_VERSION="1.1.0"
SCRIPT_NAME="PBSClientTool"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
CONFIG_DIR="/etc/proxmox-backup-client"
TARGETS_DIR="$CONFIG_DIR/targets"
LOG_FILE="/var/log/pbs-client-installer.log"

# Helper functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[ERROR] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

prompt() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input
    
    if [ -n "$default_value" ]; then
        read -p "$(echo -e ${BLUE}${prompt_text}${NC} [${default_value}]: )" user_input
        echo "${user_input:-$default_value}"
    else
        read -p "$(echo -e ${BLUE}${prompt_text}${NC}: )" user_input
        echo "$user_input"
    fi
}

prompt_password() {
    local prompt_text="$1"
    local user_input
    read -sp "$(echo -e ${BLUE}${prompt_text}${NC}: )" user_input
    echo >&2  # Output newline to stderr so it doesn't get captured
    echo "$user_input"
}

# Multi-target helper functions
list_targets() {
    if [ ! -d "$TARGETS_DIR" ]; then
        return 1
    fi

    local targets=()
    for config in "$TARGETS_DIR"/*.conf; do
        if [ -f "$config" ]; then
            targets+=("$(basename "$config" .conf)")
        fi
    done

    if [ ${#targets[@]} -eq 0 ]; then
        return 1
    fi

    printf '%s\n' "${targets[@]}"
}

validate_target_name() {
    local name="$1"

    # Check if name is empty
    if [ -z "$name" ]; then
        error "Target name cannot be empty"
        return 1
    fi

    # Check if name contains only alphanumeric, dash, underscore
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Target name can only contain letters, numbers, dash, and underscore"
        return 1
    fi

    return 0
}

target_exists() {
    local name="$1"
    [ -f "$TARGETS_DIR/$name.conf" ]
}

get_target_config_path() {
    local name="$1"
    echo "$TARGETS_DIR/$name.conf"
}

# Convert user input (number or name) to target name
resolve_target_input() {
    local input="$1"

    # If input is a number, get the Nth target
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        local target_name=$(list_targets | sed -n "${input}p")
        if [ -n "$target_name" ]; then
            echo "$target_name"
            return 0
        fi
        return 1
    fi

    # Otherwise treat as target name
    echo "$input"
    return 0
}

# Quick authentication test for a single target (minimal output)
quick_test_target() {
    local target_name="$1"
    local config_file="$(get_target_config_path "$target_name")"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    # Source config in subshell to avoid polluting environment
    (
        source "$config_file"
        export PBS_REPOSITORY
        export PBS_PASSWORD

        # Quick auth test - just try to login
        echo "y" | timeout 5 proxmox-backup-client login >/dev/null 2>&1
    )
    return $?
}

# Test all configured targets and display status
test_all_targets() {
    if ! list_targets >/dev/null 2>&1; then
        return 0
    fi

    echo
    echo "════════════════════════════════════════"
    echo "  Testing Backup Target Connections"
    echo "════════════════════════════════════════"
    echo

    local all_ok=true
    while IFS= read -r target; do
        printf "  %-20s " "$target:"

        if quick_test_target "$target"; then
            echo "✓ Connected"
        else
            echo "✗ Failed"
            all_ok=false
        fi
    done < <(list_targets)

    echo
    if [ "$all_ok" = false ]; then
        warn "Some targets failed connection test"
        info "Use option 3 (Edit target) to fix connection issues"
    fi
}

migrate_legacy_config() {
    # Check if old single-target config exists
    if [ -f "$CONFIG_DIR/config" ] && [ ! -d "$TARGETS_DIR" ]; then
        log "Migrating legacy configuration to multi-target system..."

        mkdir -p "$TARGETS_DIR"
        mv "$CONFIG_DIR/config" "$TARGETS_DIR/default.conf"

        # Rename old backup script if it exists
        if [ -f "$CONFIG_DIR/backup.sh" ]; then
            mv "$CONFIG_DIR/backup.sh" "$CONFIG_DIR/backup-default.sh"
        fi

        # Rename old services if they exist
        if [ -f "/etc/systemd/system/pbs-backup.service" ]; then
            systemctl stop pbs-backup.service pbs-backup.timer 2>/dev/null || true
            systemctl disable pbs-backup.service pbs-backup.timer 2>/dev/null || true

            mv /etc/systemd/system/pbs-backup.service /etc/systemd/system/pbs-backup-default.service
            mv /etc/systemd/system/pbs-backup-manual.service /etc/systemd/system/pbs-backup-default-manual.service 2>/dev/null || true
            mv /etc/systemd/system/pbs-backup.timer /etc/systemd/system/pbs-backup-default.timer

            # Update service files to point to new backup script
            sed -i 's|/etc/proxmox-backup-client/backup.sh|/etc/proxmox-backup-client/backup-default.sh|g' \
                /etc/systemd/system/pbs-backup-default.service \
                /etc/systemd/system/pbs-backup-default-manual.service 2>/dev/null || true

            systemctl daemon-reload
            systemctl enable pbs-backup-default.timer
            systemctl start pbs-backup-default.timer

            log "Legacy configuration migrated to 'default' target"
        fi
    fi
}

show_targets_list() {
    echo
    echo "════════════════════════════════════════"
    echo "  Configured Backup Targets"
    echo "════════════════════════════════════════"
    echo

    if ! list_targets >/dev/null 2>&1; then
        warn "No backup targets configured"
        return 1
    fi

    # Use process substitution to avoid subshell issues
    while IFS= read -r target; do
        local config_file="$(get_target_config_path "$target")"

        # Clear any previous variables
        unset PBS_SERVER PBS_PORT PBS_DATASTORE PBS_REPOSITORY PBS_PASSWORD
        unset BACKUP_TYPE BACKUP_PATHS EXCLUDE_PATTERNS BLOCK_DEVICE
        unset TIMER_SCHEDULE TIMER_ONCALENDAR KEEP_LAST KEEP_DAILY KEEP_WEEKLY KEEP_MONTHLY
        unset BLOCK_DEVICE_FREQUENCY BLOCK_DEVICE_DAY

        if [ -f "$config_file" ]; then
            source "$config_file"

            echo "Target: $target"

            # Check if config seems incomplete
            if [ -z "$PBS_SERVER" ] || [ -z "$PBS_DATASTORE" ] || \
               [ "$PBS_SERVER" = "unknown" ] || [ "$PBS_DATASTORE" = "unknown" ]; then
                echo "  Status: ⚠ Incomplete configuration"
                echo "  Action: Use option 3 (Edit target) to reconfigure"
            else
                echo "  Server: ${PBS_SERVER}:${PBS_PORT:-8007}"
                echo "  Datastore: ${PBS_DATASTORE}"
                echo "  Type: ${BACKUP_TYPE:-unknown}"
                echo "  Schedule: ${TIMER_SCHEDULE:-unknown}"

                # Check if timer is active
                if systemctl is-enabled "pbs-backup-${target}.timer" &>/dev/null; then
                    if systemctl is-active "pbs-backup-${target}.timer" &>/dev/null; then
                        echo "  Status: ✓ Active"
                    else
                        echo "  Status: ✗ Inactive"
                    fi
                else
                    echo "  Status: ✗ Disabled"
                fi
            fi
            echo
        fi
    done < <(list_targets)
}

add_target() {
    echo
    log "Adding new backup target..."
    echo

    # Get target name
    while true; do
        TARGET_NAME=$(prompt "Enter target name (e.g., 'offsite', 'local', 'backup1')" "")

        if ! validate_target_name "$TARGET_NAME"; then
            continue
        fi

        if target_exists "$TARGET_NAME"; then
            error "Target '$TARGET_NAME' already exists"
            continue
        fi

        break
    done

    # Run interactive config for this target
    interactive_config_for_target "$TARGET_NAME"
}

edit_target() {
    echo
    if ! list_targets >/dev/null 2>&1; then
        error "No targets configured"
        return 1
    fi

    echo "Available targets:"
    list_targets | nl
    echo

    USER_INPUT=$(prompt "Enter target number or name" "")

    if [ -z "$USER_INPUT" ]; then
        error "No target specified"
        return 1
    fi

    TARGET_NAME=$(resolve_target_input "$USER_INPUT")
    if [ -z "$TARGET_NAME" ]; then
        error "Invalid target number: $USER_INPUT"
        return 1
    fi

    if ! validate_target_name "$TARGET_NAME"; then
        return 1
    fi

    if ! target_exists "$TARGET_NAME"; then
        error "Target '$TARGET_NAME' does not exist"
        return 1
    fi

    log "Editing target: $TARGET_NAME"
    echo
    echo "What would you like to edit?"
    echo "  1) Connection only (server/credentials)"
    echo "  2) Backup settings (type/schedule/retention)"
    echo "  3) Full reconfiguration"
    echo "  4) Cancel"

    local EDIT_CHOICE=$(prompt "Select option [1/2/3/4]" "1")

    case "$EDIT_CHOICE" in
        1)
            reconfigure_connection_for_target "$TARGET_NAME"
            ;;
        2)
            reconfigure_backup_settings_for_target "$TARGET_NAME"
            ;;
        3)
            interactive_config_for_target "$TARGET_NAME"
            ;;
        4)
            info "Cancelled"
            return 0
            ;;
        *)
            error "Invalid option"
            return 1
            ;;
    esac
}

delete_target() {
    echo
    if ! list_targets >/dev/null 2>&1; then
        error "No targets configured"
        return 1
    fi

    echo "Available targets:"
    list_targets | nl
    echo

    USER_INPUT=$(prompt "Enter target number or name to delete" "")

    if [ -z "$USER_INPUT" ]; then
        error "No target specified"
        return 1
    fi

    TARGET_NAME=$(resolve_target_input "$USER_INPUT")
    if [ -z "$TARGET_NAME" ]; then
        error "Invalid target number: $USER_INPUT"
        return 1
    fi

    if ! validate_target_name "$TARGET_NAME"; then
        return 1
    fi

    if ! target_exists "$TARGET_NAME"; then
        error "Target '$TARGET_NAME' does not exist"
        return 1
    fi

    warn "This will delete target '$TARGET_NAME' and stop all associated backups"
    local CONFIRM=$(prompt "Are you sure? Type 'yes' to confirm" "no")

    if [ "$CONFIRM" != "yes" ]; then
        info "Cancelled"
        return 0
    fi

    log "Deleting target: $TARGET_NAME"

    # Stop and disable services
    systemctl stop "pbs-backup-${TARGET_NAME}.service" "pbs-backup-${TARGET_NAME}.timer" 2>/dev/null || true
    systemctl disable "pbs-backup-${TARGET_NAME}.service" "pbs-backup-${TARGET_NAME}.timer" 2>/dev/null || true

    # Remove files
    rm -f "/etc/systemd/system/pbs-backup-${TARGET_NAME}.service"
    rm -f "/etc/systemd/system/pbs-backup-${TARGET_NAME}-manual.service"
    rm -f "/etc/systemd/system/pbs-backup-${TARGET_NAME}.timer"
    rm -f "$CONFIG_DIR/backup-${TARGET_NAME}.sh"
    rm -f "$(get_target_config_path "$TARGET_NAME")"

    systemctl daemon-reload

    log "Target '$TARGET_NAME' deleted successfully"
}

show_target_detail() {
    local target="$1"

    if ! target_exists "$target"; then
        error "Target '$target' does not exist"
        return 1
    fi

    local config_file="$(get_target_config_path "$target")"
    source "$config_file"

    echo
    echo "════════════════════════════════════════"
    echo "  Target: $target"
    echo "════════════════════════════════════════"
    echo
    echo "Connection:"
    echo "  Server: ${PBS_SERVER}:${PBS_PORT}"
    echo "  Datastore: ${PBS_DATASTORE}"
    echo "  Repository: ${PBS_REPOSITORY}"
    echo
    echo "Backup Configuration:"
    echo "  Type: ${BACKUP_TYPE}"

    if [[ "$BACKUP_TYPE" == "files" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Paths: ${BACKUP_PATHS}"
        echo "  Exclusions: ${EXCLUDE_PATTERNS}"
    fi

    if [[ "$BACKUP_TYPE" == "block" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Block Device: ${BLOCK_DEVICE}"
    fi

    echo
    echo "Schedule:"
    if [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Files: ${TIMER_SCHEDULE} (${TIMER_ONCALENDAR})"
        echo "  Block: Weekly on Sunday"
    else
        echo "  ${TIMER_SCHEDULE} (${TIMER_ONCALENDAR})"
    fi

    echo
    echo "Retention:"
    echo "  Last: ${KEEP_LAST}"
    echo "  Daily: ${KEEP_DAILY}"
    echo "  Weekly: ${KEEP_WEEKLY}"
    echo "  Monthly: ${KEEP_MONTHLY}"
    echo

    # Show timer status
    if systemctl is-enabled "pbs-backup-${target}.timer" &>/dev/null; then
        echo "Next scheduled backup:"
        systemctl list-timers "pbs-backup-${target}.timer" --no-pager 2>/dev/null || true
    else
        warn "Timer not enabled for this target"
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect Linux distribution
detect_distro() {
    log "Detecting Linux distribution..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_PRETTY=$PRETTY_NAME
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        OS_VERSION=$DISTRIB_RELEASE
        OS_PRETTY=$DISTRIB_DESCRIPTION
    else
        error "Cannot detect Linux distribution"
        exit 1
    fi
    
    info "Detected: $OS_PRETTY"
    
    # Normalize OS names
    OS=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
}

# Install PBS client on Ubuntu
install_ubuntu() {
    log "Installing Proxmox Backup Client on Ubuntu $OS_VERSION..."
    
    # Determine which repository to use
    if [[ "$OS_VERSION" == "24.04" ]] || [[ "$OS_VERSION" > "24" ]]; then
        REPO="bookworm"
        GPG_FILE="proxmox-release-bookworm.gpg"
    elif [[ "$OS_VERSION" == "22.04" ]]; then
        REPO="bullseye"
        GPG_FILE="proxmox-release-bullseye.gpg"
        # Need to add Focal security repo for libssl1.1
        NEED_FOCAL=true
    elif [[ "$OS_VERSION" == "20.04" ]]; then
        REPO="bullseye"
        GPG_FILE="proxmox-release-bullseye.gpg"
    else
        error "Unsupported Ubuntu version: $OS_VERSION"
        exit 1
    fi
    
    # Download and install GPG key
    log "Downloading GPG key..."
    wget -q "https://enterprise.proxmox.com/debian/${GPG_FILE}" \
        -O "/etc/apt/trusted.gpg.d/${GPG_FILE}"
    
    # Add PBS client repository
    log "Adding PBS client repository..."
    echo "deb [arch=amd64] http://download.proxmox.com/debian/pbs-client ${REPO} main" > \
        /etc/apt/sources.list.d/pbs-client.list
    
    # Add Focal security repo if needed (Ubuntu 22.04)
    if [ "$NEED_FOCAL" = true ]; then
        log "Adding Ubuntu Focal security repository for libssl1.1..."
        echo "deb [arch=amd64] http://security.ubuntu.com/ubuntu focal-security main" > \
            /etc/apt/sources.list.d/focal-security.list
    fi
    
    # Update and install
    log "Updating package lists..."
    apt-get update -qq
    
    log "Installing proxmox-backup-client..."
    apt-get install -y proxmox-backup-client
    
    log "PBS client installed successfully"
}

# Install PBS client on Debian
install_debian() {
    log "Installing Proxmox Backup Client on Debian $OS_VERSION..."
    
    # Determine repository based on Debian version
    case "$OS_VERSION" in
        12*)
            REPO="bookworm"
            GPG_FILE="proxmox-release-bookworm.gpg"
            ;;
        11*)
            REPO="bullseye"
            GPG_FILE="proxmox-release-bullseye.gpg"
            ;;
        10*)
            REPO="buster"
            GPG_FILE="proxmox-release-buster.gpg"
            ;;
        *)
            error "Unsupported Debian version: $OS_VERSION"
            exit 1
            ;;
    esac
    
    # Download and install GPG key
    log "Downloading GPG key..."
    wget -q "https://enterprise.proxmox.com/debian/${GPG_FILE}" \
        -O "/etc/apt/trusted.gpg.d/${GPG_FILE}"
    
    # Add PBS client repository
    log "Adding PBS client repository..."
    echo "deb [arch=amd64] http://download.proxmox.com/debian/pbs-client ${REPO} main" > \
        /etc/apt/sources.list.d/pbs-client.list
    
    # Update and install
    log "Updating package lists..."
    apt-get update -qq
    
    log "Installing proxmox-backup-client..."
    apt-get install -y proxmox-backup-client
    
    log "PBS client installed successfully"
}

# Install PBS client on Arch Linux
install_arch() {
    log "Installing Proxmox Backup Client on Arch Linux..."
    
    # Check if yay is installed
    if ! command -v yay &> /dev/null; then
        error "yay AUR helper is required but not installed"
        info "Install yay first: https://github.com/Jguer/yay"
        exit 1
    fi
    
    # Get the user who invoked sudo
    if [ -n "$SUDO_USER" ]; then
        REAL_USER="$SUDO_USER"
    else
        error "Cannot determine original user. Run with sudo."
        exit 1
    fi
    
    log "Installing proxmox-backup-client-bin from AUR..."
    sudo -u "$REAL_USER" yay -S --noconfirm proxmox-backup-client-bin
    
    log "PBS client installed successfully"
}

# Main installation function
install_pbs_client() {
    case "$OS" in
        ubuntu)
            install_ubuntu
            ;;
        debian)
            install_debian
            ;;
        arch|archlinux)
            install_arch
            ;;
        *)
            error "Unsupported distribution: $OS"
            info "Supported distributions: Ubuntu, Debian, Arch Linux"
            exit 1
            ;;
    esac
    
    # Verify installation
    if command -v proxmox-backup-client &> /dev/null; then
        local version=$(proxmox-backup-client version 2>/dev/null | head -n1)
        log "Installation verified: $version"
        return 0
    else
        error "Installation verification failed"
        return 1
    fi
}

# Reconfigure connection only (PBS server and credentials)
reconfigure_connection() {
    log "Reconfiguring PBS server connection..."
    echo
    echo "======================================"
    echo "  PBS Server Connection Setup"
    echo "======================================"
    echo

    # PBS Server details
    PBS_SERVER=$(prompt "Enter PBS server IP/hostname" "192.168.1.181" | xargs)
    PBS_PORT=$(prompt "Enter PBS server port" "8007" | xargs)
    PBS_DATASTORE=$(prompt "Enter datastore name" "backups" | xargs)

    echo
    info "Authentication Method:"
    echo "  1) Username + Password"
    echo "  2) API Token (recommended for automation)"
    AUTH_METHOD=$(prompt "Select authentication method [1/2]" "2")

    if [ "$AUTH_METHOD" = "1" ]; then
        PBS_USERNAME=$(prompt "Enter username" "root" | xargs)
        PBS_REALM=$(prompt "Enter realm" "pam" | xargs)
        PBS_PASSWORD=$(prompt_password "Enter password" | xargs)
        PBS_REPOSITORY="${PBS_USERNAME}@${PBS_REALM}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
    else
        PBS_USERNAME=$(prompt "Enter username" "backup" | xargs)
        PBS_REALM=$(prompt "Enter realm" "pam" | xargs)
        PBS_TOKEN_NAME=$(prompt "Enter token name" "backup-token" | xargs)
        PBS_TOKEN_SECRET=$(prompt_password "Enter token secret" | xargs)
        PBS_REPOSITORY="${PBS_USERNAME}@${PBS_REALM}!${PBS_TOKEN_NAME}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
        PBS_PASSWORD="$PBS_TOKEN_SECRET"
    fi

    # Test the new connection
    if ! test_connection; then
        error "Connection test failed with new credentials"
        RETRY=$(prompt "Try again? (yes/no)" "yes")
        if [[ "$RETRY" == "yes" ]]; then
            reconfigure_connection
            return
        else
            error "Cannot proceed without successful connection"
            exit 1
        fi
    fi

    # Load existing configuration and update only connection details
    if [ -f "$CONFIG_DIR/config" ]; then
        log "Loading existing backup configuration..."
        source "$CONFIG_DIR/config"
    else
        error "No existing configuration found. Please run full configuration."
        exit 1
    fi

    # Update config file with new connection details
    log "Updating configuration file..."

    # Strip any trailing newlines from password (defensive fix)
    PBS_PASSWORD_CLEAN=$(echo -n "$PBS_PASSWORD" | tr -d '\n\r')

    cat > "$CONFIG_DIR/config" <<EOF
# PBS Client Configuration
PBS_REPOSITORY="${PBS_REPOSITORY}"
PBS_PASSWORD="${PBS_PASSWORD_CLEAN}"
BACKUP_TYPE="${BACKUP_TYPE}"
BACKUP_PATHS="${BACKUP_PATHS}"
EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS}"
BLOCK_DEVICE="${BLOCK_DEVICE}"
KEEP_LAST=${KEEP_LAST}
KEEP_DAILY=${KEEP_DAILY}
KEEP_WEEKLY=${KEEP_WEEKLY}
KEEP_MONTHLY=${KEEP_MONTHLY}
EOF

    chmod 600 "$CONFIG_DIR/config"

    log "Connection configuration updated successfully!"
    echo
    info "Updated Connection:"
    echo "  PBS Server: ${PBS_SERVER}:${PBS_PORT}"
    echo "  Datastore: ${PBS_DATASTORE}"
    echo "  Repository: ${PBS_REPOSITORY}"
    echo
    info "All other backup settings remain unchanged."
}

# Reconfigure backup settings only (type, schedule, retention)
reconfigure_backup_settings() {
    log "Reconfiguring backup settings..."
    echo

    # Load existing configuration to preserve connection details
    if [ -f "$CONFIG_DIR/config" ]; then
        source "$CONFIG_DIR/config"
    else
        error "No existing configuration found. Please run full configuration."
        exit 1
    fi

    # Preserve connection details
    local SAVED_PBS_REPOSITORY="$PBS_REPOSITORY"
    local SAVED_PBS_PASSWORD="$PBS_PASSWORD"

    # Backup type selection
    info "Backup Type:"
    echo "  1) File-level only (.pxar) - Fast, efficient, selective restore"
    echo "  2) Block device only (.img) - Full disk image, bootable as VM"
    echo "  3) Both (Hybrid) - Daily files + Weekly block device (recommended)"

    local CURRENT_BACKUP_TYPE_NUM=""
    case "$BACKUP_TYPE" in
        files) CURRENT_BACKUP_TYPE_NUM="1" ;;
        block) CURRENT_BACKUP_TYPE_NUM="2" ;;
        both) CURRENT_BACKUP_TYPE_NUM="3" ;;
    esac

    BACKUP_TYPE_CHOICE=$(prompt "Select backup type [1/2/3]" "$CURRENT_BACKUP_TYPE_NUM")

    case "$BACKUP_TYPE_CHOICE" in
        1)
            BACKUP_TYPE="files"
            ;;
        2)
            BACKUP_TYPE="block"
            ;;
        3)
            BACKUP_TYPE="both"
            ;;
        *)
            warn "Invalid choice, keeping current setting: $BACKUP_TYPE"
            ;;
    esac

    echo
    # Backup configuration
    info "Backup Configuration:"

    if [[ "$BACKUP_TYPE" == "files" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        BACKUP_PATHS=$(prompt "Enter paths to backup (space-separated)" "$BACKUP_PATHS")
        EXCLUDE_PATTERNS=$(prompt "Enter exclusion patterns (space-separated)" "$EXCLUDE_PATTERNS")
    fi

    if [[ "$BACKUP_TYPE" == "block" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        echo
        info "Block Device Configuration:"
        info "Current device: ${BLOCK_DEVICE:-none}"

        # Try to auto-detect root device if none set
        if [ -z "$BLOCK_DEVICE" ]; then
            ROOT_DEVICE=$(findmnt -n -o SOURCE / | sed 's/\[.*\]$//' | sed 's/[0-9]*$//' | sed 's/p$//' 2>/dev/null || echo "")
            if [ -n "$ROOT_DEVICE" ] && [ -b "$ROOT_DEVICE" ]; then
                BLOCK_DEVICE="$ROOT_DEVICE"
            fi
        fi

        BLOCK_DEVICE=$(prompt "Enter block device to backup" "$BLOCK_DEVICE")

        # Verify it's a block device
        if [ ! -b "$BLOCK_DEVICE" ]; then
            warn "Warning: $BLOCK_DEVICE does not exist or is not a block device"
            info "Available block devices:"
            lsblk -d -n -o NAME,SIZE,TYPE | grep disk | awk '{print "  /dev/"$1" ("$2")"}'
            echo
            CONTINUE=$(prompt "Continue anyway? (yes/no)" "no")
            if [[ "$CONTINUE" != "yes" ]]; then
                error "Configuration cancelled"
                return 1
            fi
        fi
    fi

    echo
    info "Backup Schedule:"
    echo "  1) Hourly"
    echo "  2) Daily (recommended)"
    echo "  3) Weekly"
    echo "  4) Custom"
    SCHEDULE_TYPE=$(prompt "Select schedule type [1/2/3/4]" "2")

    case "$SCHEDULE_TYPE" in
        1)
            TIMER_SCHEDULE="hourly"
            TIMER_ONCALENDAR="hourly"
            ;;
        2)
            BACKUP_HOUR=$(prompt "Enter hour for daily backup (0-23)" "2")
            TIMER_SCHEDULE="daily"
            TIMER_ONCALENDAR="*-*-* ${BACKUP_HOUR}:00:00"
            ;;
        3)
            BACKUP_DOW=$(prompt "Enter day of week (Mon-Sun)" "Sun")
            BACKUP_HOUR=$(prompt "Enter hour (0-23)" "2")
            TIMER_SCHEDULE="weekly"
            TIMER_ONCALENDAR="${BACKUP_DOW} *-*-* ${BACKUP_HOUR}:00:00"
            ;;
        4)
            TIMER_ONCALENDAR=$(prompt "Enter systemd OnCalendar format" "*-*-* 02:00:00")
            TIMER_SCHEDULE="custom"
            ;;
    esac

    echo
    # Retention policy
    info "Retention Policy:"
    KEEP_LAST=$(prompt "Keep last N backups" "${KEEP_LAST:-3}")
    KEEP_DAILY=$(prompt "Keep daily backups for N days" "${KEEP_DAILY:-7}")
    KEEP_WEEKLY=$(prompt "Keep weekly backups for N weeks" "${KEEP_WEEKLY:-4}")
    KEEP_MONTHLY=$(prompt "Keep monthly backups for N months" "${KEEP_MONTHLY:-6}")

    # Restore connection details
    PBS_REPOSITORY="$SAVED_PBS_REPOSITORY"
    PBS_PASSWORD="$SAVED_PBS_PASSWORD"

    # Regenerate systemd service with new settings
    echo
    log "Updating systemd service configuration..."
    create_systemd_service

    # Restart services
    log "Restarting backup timer..."
    systemctl daemon-reload
    systemctl restart pbs-backup.timer

    echo
    log "Backup settings updated successfully!"
    echo
    info "New Configuration:"
    echo "  Backup Type: ${BACKUP_TYPE}"

    if [[ "$BACKUP_TYPE" == "files" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Backup Paths: ${BACKUP_PATHS}"
    fi

    if [[ "$BACKUP_TYPE" == "block" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Block Device: ${BLOCK_DEVICE}"
    fi

    if [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Schedule: Files ${TIMER_SCHEDULE} (${TIMER_ONCALENDAR}), Block device weekly (Sunday)"
    else
        echo "  Schedule: ${TIMER_SCHEDULE} (${TIMER_ONCALENDAR})"
    fi

    echo "  Retention: Last=${KEEP_LAST} Daily=${KEEP_DAILY} Weekly=${KEEP_WEEKLY} Monthly=${KEEP_MONTHLY}"
    echo

    # Show service status
    info "Backup Service Status:"
    echo "────────────────────────────────────────────────────────────"
    systemctl status pbs-backup.timer --no-pager -l || true
    echo "────────────────────────────────────────────────────────────"
    echo
    info "Next scheduled backup:"
    systemctl list-timers pbs-backup.timer --no-pager || true
}

# Per-target wrapper functions
interactive_config_for_target() {
    local target_name="$1"
    TARGET_NAME="$target_name"

    log "Configuring backup target: $target_name"

    # Run standard interactive config
    interactive_config

    # Create systemd service for this target
    create_systemd_service_for_target "$target_name"

    # Test connection
    if ! test_connection; then
        error "Connection test failed"
        return 1
    fi

    log "Target '$target_name' configured successfully!"
}

reconfigure_connection_for_target() {
    local target_name="$1"
    TARGET_NAME="$target_name"

    # Load existing config
    if [ ! -f "$(get_target_config_path "$target_name")" ]; then
        error "Target '$target_name' not found"
        return 1
    fi

    source "$(get_target_config_path "$target_name")"

    # Run standard reconfigure_connection
    reconfigure_connection

    # Update systemd service
    create_systemd_service_for_target "$target_name"

    # Restart timer
    systemctl daemon-reload
    systemctl restart "pbs-backup-${target_name}.timer"

    log "Connection reconfigured for target '$target_name'"
}

reconfigure_backup_settings_for_target() {
    local target_name="$1"
    TARGET_NAME="$target_name"

    # Load existing config
    if [ ! -f "$(get_target_config_path "$target_name")" ]; then
        error "Target '$target_name' not found"
        return 1
    fi

    source "$(get_target_config_path "$target_name")"

    # Run standard reconfigure_backup_settings
    reconfigure_backup_settings
}

run_backup_for_target() {
    local target_name="$1"

    if ! target_exists "$target_name"; then
        error "Target '$target_name' does not exist"
        return 1
    fi

    # Load target config to check backup type
    local config_file="$(get_target_config_path "$target_name")"
    source "$config_file"

    # If hybrid mode, ask what to backup
    local BACKUP_MODE="yes"  # Default: full backup
    if [[ "$BACKUP_TYPE" == "both" ]]; then
        echo
        info "This target is configured for hybrid backups (files + block device)"
        echo
        echo "What would you like to backup?"
        echo "  1) Files only (fast ~2-3 minutes)"
        echo "  2) Block device only (slow ~20-30 minutes, enables VM conversion)"
        echo "  3) Both files and block device (full backup)"
        BACKUP_CHOICE=$(prompt "Select option [1/2/3]" "3")

        case "$BACKUP_CHOICE" in
            1)
                BACKUP_MODE="files"
                info "Running files-only backup for target: $target_name"
                ;;
            2)
                BACKUP_MODE="block"
                info "Running block device backup for target: $target_name"
                ;;
            3)
                BACKUP_MODE="yes"
                info "Running FULL backup (files + block device) for target: $target_name"
                ;;
            *)
                warn "Invalid choice, defaulting to full backup"
                BACKUP_MODE="yes"
                info "Running FULL backup for target: $target_name"
                ;;
        esac
    else
        info "Running backup for target: $target_name"
    fi

    echo

    # Show real-time progress
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Backup Progress (Live) - Target: $target_name"
    if [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "║  Mode: $BACKUP_MODE"
    fi
    echo "║  Press Ctrl+C to stop viewing (backup continues)          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo

    # Run backup script directly with the chosen mode
    if "$CONFIG_DIR/backup-${target_name}.sh" "$BACKUP_MODE"; then
        echo
        log "Backup completed successfully!"
    else
        echo
        error "Backup failed!"
        echo
        info "Check logs above for details"
        return 1
    fi
}

# Interactive configuration
interactive_config() {
    log "Starting interactive configuration..."
    echo
    echo "======================================"
    echo "  PBS Client Configuration"
    echo "======================================"
    echo

    # PBS Server details
    PBS_SERVER=$(prompt "Enter PBS server IP/hostname" "192.168.1.181" | xargs)
    PBS_PORT=$(prompt "Enter PBS server port" "8007" | xargs)
    PBS_DATASTORE=$(prompt "Enter datastore name" "backups" | xargs)

    echo
    info "Authentication Method:"
    echo "  1) Username + Password"
    echo "  2) API Token (recommended for automation)"
    AUTH_METHOD=$(prompt "Select authentication method [1/2]" "2")

    if [ "$AUTH_METHOD" = "1" ]; then
        PBS_USERNAME=$(prompt "Enter username" "root" | xargs)
        PBS_REALM=$(prompt "Enter realm" "pam" | xargs)
        PBS_PASSWORD=$(prompt_password "Enter password" | xargs)
        PBS_REPOSITORY="${PBS_USERNAME}@${PBS_REALM}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
    else
        PBS_USERNAME=$(prompt "Enter username" "backup" | xargs)
        PBS_REALM=$(prompt "Enter realm" "pam" | xargs)
        PBS_TOKEN_NAME=$(prompt "Enter token name" "backup-token" | xargs)
        PBS_TOKEN_SECRET=$(prompt_password "Enter token secret" | xargs)
        PBS_REPOSITORY="${PBS_USERNAME}@${PBS_REALM}!${PBS_TOKEN_NAME}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
        PBS_PASSWORD="$PBS_TOKEN_SECRET"
    fi
    
    echo
    # Backup type selection
    info "Backup Type:"
    echo "  1) File-level only (.pxar) - Fast, efficient, selective restore"
    echo "  2) Block device only (.img) - Full disk image, bootable as VM"
    echo "  3) Both (Hybrid) - Daily files + Weekly block device (recommended)"
    BACKUP_TYPE_CHOICE=$(prompt "Select backup type [1/2/3]" "3")
    
    case "$BACKUP_TYPE_CHOICE" in
        1)
            BACKUP_TYPE="files"
            ;;
        2)
            BACKUP_TYPE="block"
            ;;
        3)
            BACKUP_TYPE="both"
            ;;
        *)
            warn "Invalid choice, defaulting to hybrid (both)"
            BACKUP_TYPE="both"
            ;;
    esac
    
    echo
    # Backup configuration
    info "Backup Configuration:"
    
    if [[ "$BACKUP_TYPE" == "files" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        BACKUP_PATHS=$(prompt "Enter paths to backup (space-separated)" "/")
        EXCLUDE_PATTERNS=$(prompt "Enter exclusion patterns (space-separated)" "/tmp /var/tmp /var/cache /proc /sys /dev /run")
    fi
    
    if [[ "$BACKUP_TYPE" == "block" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        echo
        info "Block Device Configuration:"

        # Try to auto-detect root device
        # Strip subvolume notation [/@], partition numbers, and trailing 'p'
        ROOT_DEVICE=$(findmnt -n -o SOURCE / | sed 's/\[.*\]$//' | sed 's/[0-9]*$//' | sed 's/p$//' 2>/dev/null || echo "")

        if [ -n "$ROOT_DEVICE" ] && [ -b "$ROOT_DEVICE" ]; then
            info "Auto-detected root device: $ROOT_DEVICE"
            BLOCK_DEVICE=$(prompt "Enter block device to backup" "$ROOT_DEVICE")
        else
            if [ -n "$ROOT_DEVICE" ]; then
                warn "Detected device $ROOT_DEVICE is not a valid block device"
            fi
            info "Common devices: /dev/sda, /dev/nvme0n1, /dev/vda"
            BLOCK_DEVICE=$(prompt "Enter block device to backup" "/dev/sda")
        fi

        # Verify it's a block device
        if [ ! -b "$BLOCK_DEVICE" ]; then
            warn "Warning: $BLOCK_DEVICE does not exist or is not a block device"
            info "Available block devices:"
            lsblk -d -n -o NAME,SIZE,TYPE | grep disk | awk '{print "  /dev/"$1" ("$2")"}'
            echo
            CONTINUE=$(prompt "Continue anyway? (yes/no)" "no")
            if [[ "$CONTINUE" != "yes" ]]; then
                error "Installation cancelled"
                exit 1
            fi
        fi
    fi
    
    echo
    info "Backup Schedule:"
    echo "  1) Hourly"
    echo "  2) Daily (recommended)"
    echo "  3) Weekly"
    echo "  4) Custom"
    SCHEDULE_TYPE=$(prompt "Select schedule type [1/2/3/4]" "2")
    
    case "$SCHEDULE_TYPE" in
        1)
            TIMER_SCHEDULE="hourly"
            TIMER_ONCALENDAR="hourly"
            ;;
        2)
            BACKUP_HOUR=$(prompt "Enter hour for daily backup (0-23)" "2")
            TIMER_SCHEDULE="daily"
            TIMER_ONCALENDAR="*-*-* ${BACKUP_HOUR}:00:00"
            ;;
        3)
            BACKUP_DOW=$(prompt "Enter day of week (Mon-Sun)" "Sun")
            BACKUP_HOUR=$(prompt "Enter hour (0-23)" "2")
            TIMER_SCHEDULE="weekly"
            TIMER_ONCALENDAR="${BACKUP_DOW} *-*-* ${BACKUP_HOUR}:00:00"
            ;;
        4)
            TIMER_ONCALENDAR=$(prompt "Enter systemd OnCalendar format" "*-*-* 02:00:00")
            TIMER_SCHEDULE="custom"
            ;;
    esac

    # If hybrid mode, ask for block device schedule separately
    if [[ "$BACKUP_TYPE" == "both" ]]; then
        echo
        info "Block Device Backup Schedule:"
        echo "  Block device backups are slower (20-30 min) but enable VM conversion."
        echo "  File backups will run on the schedule above."
        echo
        echo "  1) Weekly (recommended - every Sunday)"
        echo "  2) Biweekly (every other Sunday)"
        echo "  3) Monthly (1st of each month)"
        echo "  4) Custom day of week"
        echo "  5) Custom day of month"
        BLOCK_SCHEDULE_TYPE=$(prompt "Select block device schedule [1/2/3/4/5]" "1")

        case "$BLOCK_SCHEDULE_TYPE" in
            1)
                BLOCK_DEVICE_FREQUENCY="weekly"
                BLOCK_DEVICE_DAY="7"  # Sunday
                ;;
            2)
                BLOCK_DEVICE_FREQUENCY="biweekly"
                BLOCK_DEVICE_DAY="7"  # Sunday
                ;;
            3)
                BLOCK_DEVICE_FREQUENCY="monthly"
                BLOCK_DEVICE_DAY="1"  # 1st of month
                ;;
            4)
                BLOCK_BACKUP_DOW=$(prompt "Enter day of week for block device (Mon-Sun)" "Sun")
                BLOCK_DEVICE_FREQUENCY="weekly"
                # Convert day name to number (1=Mon, 7=Sun)
                case "$BLOCK_BACKUP_DOW" in
                    Mon|mon|MON|Monday|1) BLOCK_DEVICE_DAY="1" ;;
                    Tue|tue|TUE|Tuesday|2) BLOCK_DEVICE_DAY="2" ;;
                    Wed|wed|WED|Wednesday|3) BLOCK_DEVICE_DAY="3" ;;
                    Thu|thu|THU|Thursday|4) BLOCK_DEVICE_DAY="4" ;;
                    Fri|fri|FRI|Friday|5) BLOCK_DEVICE_DAY="5" ;;
                    Sat|sat|SAT|Saturday|6) BLOCK_DEVICE_DAY="6" ;;
                    Sun|sun|SUN|Sunday|7) BLOCK_DEVICE_DAY="7" ;;
                    *) BLOCK_DEVICE_DAY="7" ;;
                esac
                ;;
            5)
                BLOCK_BACKUP_DOM=$(prompt "Enter day of month (1-31)" "1")
                BLOCK_DEVICE_FREQUENCY="monthly"
                BLOCK_DEVICE_DAY="$BLOCK_BACKUP_DOM"
                ;;
            *)
                warn "Invalid choice, defaulting to weekly (Sunday)"
                BLOCK_DEVICE_FREQUENCY="weekly"
                BLOCK_DEVICE_DAY="7"
                ;;
        esac
    else
        # Not hybrid mode, set defaults (won't be used)
        BLOCK_DEVICE_FREQUENCY="weekly"
        BLOCK_DEVICE_DAY="7"
    fi

    echo
    # Retention policy
    info "Retention Policy:"
    KEEP_LAST=$(prompt "Keep last N backups" "3")
    KEEP_DAILY=$(prompt "Keep daily backups for N days" "7")
    KEEP_WEEKLY=$(prompt "Keep weekly backups for N weeks" "4")
    KEEP_MONTHLY=$(prompt "Keep monthly backups for N months" "6")
    
    # Encryption
    echo
    ENABLE_ENCRYPTION=$(prompt "Enable encryption? (yes/no)" "no")
}

# Create encryption key
create_encryption_key() {
    if [[ "$ENABLE_ENCRYPTION" == "yes" ]]; then
        log "Creating encryption key..."
        
        # Create config directory for root
        mkdir -p /root/.config/proxmox-backup
        
        # Generate key without password (for automated backups)
        if proxmox-backup-client key create --kdf none 2>/dev/null; then
            log "Encryption key created successfully"
            
            # Create paper backup
            local paper_key="/root/pbs-encryption-key-$(date +%Y%m%d).txt"
            proxmox-backup-client key paperkey --output-format text > "$paper_key"
            
            warn "IMPORTANT: Encryption key paper backup saved to: $paper_key"
            warn "Print this file and store it securely. Lost keys = permanent data loss!"
            
            # Copy to config dir for service
            cp /root/.config/proxmox-backup/encryption-key.json "$CONFIG_DIR/"
        else
            error "Failed to create encryption key"
            return 1
        fi
    fi
}

# Test connection to PBS
test_connection() {
    log "Testing connection to PBS server..."

    export PBS_REPOSITORY="$PBS_REPOSITORY"
    export PBS_PASSWORD="$PBS_PASSWORD"

    # Step 1: Verify server is reachable
    info "Step 1/3: Checking if server is reachable..."
    if ! timeout 5 bash -c "curl -sk --max-time 5 https://${PBS_SERVER}:${PBS_PORT} >/dev/null 2>&1"; then
        echo
        error "Server is not reachable at https://${PBS_SERVER}:${PBS_PORT}"
        error "Possible issues:"
        error "  - PBS server is down or unreachable"
        error "  - Wrong IP/hostname"
        error "  - Firewall blocking port ${PBS_PORT}"
        error "  - Network connectivity issues"
        echo
        info "Troubleshooting:"
        echo "  1. Verify server is reachable: ping ${PBS_SERVER}"
        echo "  2. Test HTTPS connection: curl -k https://${PBS_SERVER}:${PBS_PORT}"
        echo "  3. Check if PBS web interface is accessible in browser"
        return 1
    fi
    log "Server is reachable"

    # Step 2: Test authentication and handle SSL fingerprint
    info "Step 2/3: Testing authentication..."

    # Use the 'login' command which tests authentication and stores a ticket
    # Automatically accept SSL fingerprint by piping 'y'
    local test_output
    if test_output=$(echo "y" | timeout 15 proxmox-backup-client login 2>&1); then
        # Check if fingerprint was accepted
        if echo "$test_output" | grep -q "fingerprint:"; then
            local fingerprint=$(echo "$test_output" | grep "fingerprint:" | head -1 | awk '{print $2}')
            info "SSL fingerprint accepted: ${fingerprint}"
        fi
        log "Authentication successful"
    else
        local exit_code=$?
        echo

        if [ $exit_code -eq 124 ]; then
            error "Authentication test timed out"
            error "This might indicate a network issue or server problem"
        else
            error "Authentication failed"
            # Show the actual error from PBS client
            if echo "$test_output" | grep -q "error\|Error"; then
                echo
                echo "$test_output" | grep -i "error" | head -5
                echo
            fi
        fi

        error "Possible issues:"
        error "  - Invalid credentials (username/password/token)"
        error "  - Datastore '${PBS_DATASTORE}' does not exist"
        error "  - User lacks permissions for the datastore"
        error "  - API token is not properly formatted"
        error "  - SSL certificate issues"
        echo
        info "Troubleshooting:"
        echo "  1. Verify credentials in PBS web interface"
        echo "  2. Check datastore name: ${PBS_DATASTORE}"
        echo "  3. Verify user has backup permissions"
        echo "  4. For API tokens, format is: username@realm!tokenname"
        echo "  5. Try the test-connection.sh script for detailed diagnostics"
        echo
        info "Debug info:"
        echo "  Repository: ${PBS_REPOSITORY}"
        return 1
    fi

    # Step 3: Verify datastore access by listing backup groups
    info "Step 3/3: Verifying datastore access..."
    if timeout 15 proxmox-backup-client list 2>/dev/null; then
        log "Datastore access verified"
        log "Connection test successful!"
        return 0
    else
        warn "Could not list backup groups (this is normal if no backups exist yet)"
        log "Connection test successful!"
        return 0
    fi
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service and timer..."
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"

    # Strip any trailing newlines from password (defensive fix)
    PBS_PASSWORD_CLEAN=$(echo -n "$PBS_PASSWORD" | tr -d '\n\r')

    # Save configuration
    cat > "$CONFIG_DIR/config" <<EOF
# PBS Client Configuration
PBS_REPOSITORY="${PBS_REPOSITORY}"
PBS_PASSWORD="${PBS_PASSWORD_CLEAN}"
BACKUP_TYPE="${BACKUP_TYPE}"
BACKUP_PATHS="${BACKUP_PATHS}"
EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS}"
BLOCK_DEVICE="${BLOCK_DEVICE}"
KEEP_LAST=${KEEP_LAST}
KEEP_DAILY=${KEEP_DAILY}
KEEP_WEEKLY=${KEEP_WEEKLY}
KEEP_MONTHLY=${KEEP_MONTHLY}
EOF
    
    chmod 600 "$CONFIG_DIR/config"
    
    # Create backup script
    cat > "$CONFIG_DIR/backup.sh" <<'EOFSCRIPT'
#!/bin/bash
set -e

# Check if forcing full backup (for manual runs)
FORCE_FULL="${1:-no}"

# Load configuration
source /etc/proxmox-backup-client/config

# Export for PBS client
export PBS_REPOSITORY
export PBS_PASSWORD

HOSTNAME=$(hostname)
BACKUP_SUCCESS=true

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to create file-level backup
backup_files() {
    log "Starting file-level backup (.pxar)..."
    
    BACKUP_CMD="proxmox-backup-client backup"
    
    # Add each path as separate archive
    for path in $BACKUP_PATHS; do
        # Sanitize path for archive name
        archive_name=$(echo "$path" | sed 's/^\///' | sed 's/\//-/g')
        [ -z "$archive_name" ] && archive_name="root"
        
        BACKUP_CMD="$BACKUP_CMD ${archive_name}.pxar:${path}"
        
        # Add --include-dev for mount points
        if mountpoint -q "$path" 2>/dev/null; then
            BACKUP_CMD="$BACKUP_CMD --include-dev ${path}"
        fi
    done
    
    # Add exclusions
    for pattern in $EXCLUDE_PATTERNS; do
        BACKUP_CMD="$BACKUP_CMD --exclude=${pattern}"
    done
    
    # Add other options
    BACKUP_CMD="$BACKUP_CMD --skip-lost-and-found --change-detection-mode=metadata"
    
    # Execute backup
    if eval $BACKUP_CMD; then
        log "File-level backup completed successfully"
        return 0
    else
        log "File-level backup FAILED" >&2
        return 1
    fi
}

# Function to create block device backup
backup_block_device() {
    log "Starting block device backup (.img)..."
    
    if [ -z "$BLOCK_DEVICE" ]; then
        log "ERROR: BLOCK_DEVICE not configured" >&2
        return 1
    fi
    
    if [ ! -b "$BLOCK_DEVICE" ]; then
        log "ERROR: $BLOCK_DEVICE is not a block device" >&2
        return 1
    fi
    
    # Get device size
    DEVICE_SIZE=$(blockdev --getsize64 "$BLOCK_DEVICE" 2>/dev/null || echo "0")
    DEVICE_SIZE_GB=$((DEVICE_SIZE / 1024 / 1024 / 1024))
    
    log "Backing up device: $BLOCK_DEVICE (${DEVICE_SIZE_GB}GB)"
    log "This may take a while..."
    
    # Sanitize device name for archive
    DEVICE_NAME=$(basename "$BLOCK_DEVICE")
    
    # Create block device backup
    if proxmox-backup-client backup "${DEVICE_NAME}.img:${BLOCK_DEVICE}"; then
        log "Block device backup completed successfully"
        return 0
    else
        log "Block device backup FAILED" >&2
        return 1
    fi
}

# Main backup execution
log "Starting backup for ${HOSTNAME}"
log "Backup type: ${BACKUP_TYPE}"

case "$BACKUP_TYPE" in
    files)
        backup_files || BACKUP_SUCCESS=false
        ;;
    block)
        backup_block_device || BACKUP_SUCCESS=false
        ;;
    both)
        # Do file backup first (faster, more frequent)
        backup_files || BACKUP_SUCCESS=false

        # Do block device backup on Sunday OR if manually forced
        if [ "$FORCE_FULL" = "yes" ]; then
            log "Manual full backup - including block device"
            backup_block_device || BACKUP_SUCCESS=false
        elif [ "$(date +%u)" -eq 7 ]; then
            log "Weekly block device backup day (Sunday)"
            backup_block_device || BACKUP_SUCCESS=false
        else
            log "Skipping block device backup (runs weekly on Sunday, or use 'Run backup now' for immediate full backup)"
        fi
        ;;
    *)
        log "ERROR: Invalid BACKUP_TYPE: ${BACKUP_TYPE}" >&2
        exit 1
        ;;
esac

# Prune old backups
if [ "$BACKUP_SUCCESS" = true ]; then
    log "Pruning old backups..."
    proxmox-backup-client prune "host/${HOSTNAME}" \
        --keep-last $KEEP_LAST \
        --keep-daily $KEEP_DAILY \
        --keep-weekly $KEEP_WEEKLY \
        --keep-monthly $KEEP_MONTHLY
    
    log "Backup and prune completed successfully"
else
    log "Backup FAILED" >&2
    exit 1
fi
EOFSCRIPT
    
    chmod 700 "$CONFIG_DIR/backup.sh"
    
    # Create systemd service file (for scheduled backups)
    cat > /etc/systemd/system/pbs-backup.service <<EOF
[Unit]
Description=Proxmox Backup Client Backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CONFIG_DIR/backup.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pbs-backup

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd service file for manual full backups
    cat > /etc/systemd/system/pbs-backup-manual.service <<EOF
[Unit]
Description=Proxmox Backup Client Manual Full Backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CONFIG_DIR/backup.sh yes
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pbs-backup

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer file
    cat > /etc/systemd/system/pbs-backup.timer <<EOF
[Unit]
Description=Proxmox Backup Client Backup Timer
Requires=pbs-backup.service

[Timer]
OnCalendar=${TIMER_ONCALENDAR}
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Reload systemd and enable timer
    systemctl daemon-reload
    systemctl enable pbs-backup.timer
    systemctl start pbs-backup.timer
    
    log "Systemd service and timer created successfully"
    
    # Show timer status
    info "Timer status:"
    systemctl status pbs-backup.timer --no-pager || true
}

# Create systemd service for a named target
create_systemd_service_for_target() {
    local target_name="$1"

    log "Creating systemd service and timer for target: $target_name"

    # Create targets directory
    mkdir -p "$TARGETS_DIR"

    # Strip any trailing newlines from password (defensive fix)
    PBS_PASSWORD_CLEAN=$(echo -n "$PBS_PASSWORD" | tr -d '\n\r')

    # Save configuration for this target
    cat > "$(get_target_config_path "$target_name")" <<EOF
# PBS Client Configuration - Target: $target_name
PBS_SERVER="${PBS_SERVER}"
PBS_PORT="${PBS_PORT}"
PBS_DATASTORE="${PBS_DATASTORE}"
PBS_REPOSITORY="${PBS_REPOSITORY}"
PBS_PASSWORD="${PBS_PASSWORD_CLEAN}"
BACKUP_TYPE="${BACKUP_TYPE}"
BACKUP_PATHS="${BACKUP_PATHS}"
EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS}"
BLOCK_DEVICE="${BLOCK_DEVICE}"
BLOCK_DEVICE_FREQUENCY="${BLOCK_DEVICE_FREQUENCY}"
BLOCK_DEVICE_DAY="${BLOCK_DEVICE_DAY}"
TIMER_SCHEDULE="${TIMER_SCHEDULE}"
TIMER_ONCALENDAR="${TIMER_ONCALENDAR}"
KEEP_LAST=${KEEP_LAST}
KEEP_DAILY=${KEEP_DAILY}
KEEP_WEEKLY=${KEEP_WEEKLY}
KEEP_MONTHLY=${KEEP_MONTHLY}
EOF

    chmod 600 "$(get_target_config_path "$target_name")"

    # Create backup script for this target
    cat > "$CONFIG_DIR/backup-${target_name}.sh" <<EOFSCRIPT
#!/bin/bash
set -e

# Check if forcing full backup (for manual runs)
FORCE_FULL="\${1:-no}"

# Load configuration for target: $target_name
source $(get_target_config_path "$target_name")

# Export for PBS client
export PBS_REPOSITORY
export PBS_PASSWORD

HOSTNAME=\$(hostname)
BACKUP_SUCCESS=true

log() {
    echo "[\$(date +'%Y-%m-%d %H:%M:%S')] \$1"
}

# Function to create file-level backup
backup_files() {
    log "Starting file-level backup (.pxar) for target: $target_name"

    BACKUP_CMD="proxmox-backup-client backup"

    # Add each path as separate archive
    for path in \$BACKUP_PATHS; do
        # Sanitize path for archive name
        archive_name=\$(echo "\$path" | sed 's/^\///' | sed 's/\//-/g')
        [ -z "\$archive_name" ] && archive_name="root"

        BACKUP_CMD="\$BACKUP_CMD \${archive_name}.pxar:\${path}"

        # Add --include-dev for mount points
        if mountpoint -q "\$path" 2>/dev/null; then
            BACKUP_CMD="\$BACKUP_CMD --include-dev \${path}"
        fi
    done

    # Add exclusions
    for pattern in \$EXCLUDE_PATTERNS; do
        BACKUP_CMD="\$BACKUP_CMD --exclude=\${pattern}"
    done

    # Add other options
    BACKUP_CMD="\$BACKUP_CMD --skip-lost-and-found --change-detection-mode=metadata"

    # Execute backup
    if eval \$BACKUP_CMD; then
        log "File-level backup completed successfully"
        return 0
    else
        log "File-level backup FAILED" >&2
        return 1
    fi
}

# Function to create block device backup
backup_block_device() {
    log "Starting block device backup (.img) for target: $target_name"

    if [ -z "\$BLOCK_DEVICE" ]; then
        log "ERROR: BLOCK_DEVICE not configured" >&2
        return 1
    fi

    if [ ! -b "\$BLOCK_DEVICE" ]; then
        log "ERROR: \$BLOCK_DEVICE is not a block device" >&2
        return 1
    fi

    # Get device size
    DEVICE_SIZE=\$(blockdev --getsize64 "\$BLOCK_DEVICE" 2>/dev/null || echo "0")
    DEVICE_SIZE_GB=\$((DEVICE_SIZE / 1024 / 1024 / 1024))

    log "Backing up device: \$BLOCK_DEVICE (\${DEVICE_SIZE_GB}GB)"
    log "This may take a while..."

    # Sanitize device name for archive
    DEVICE_NAME=\$(basename "\$BLOCK_DEVICE")

    # Create block device backup
    if proxmox-backup-client backup "\${DEVICE_NAME}.img:\${BLOCK_DEVICE}"; then
        log "Block device backup completed successfully"
        return 0
    else
        log "Block device backup FAILED" >&2
        return 1
    fi
}

# Main backup execution
log "Starting backup for \${HOSTNAME} - Target: $target_name"
log "Backup type: \${BACKUP_TYPE}"

case "\$BACKUP_TYPE" in
    files)
        backup_files || BACKUP_SUCCESS=false
        ;;
    block)
        backup_block_device || BACKUP_SUCCESS=false
        ;;
    both)
        # Determine what to backup
        SHOULD_RUN_FILES=true
        SHOULD_RUN_BLOCK=false

        if [ "\$FORCE_FULL" = "yes" ]; then
            log "Manual full backup - running both files and block device"
            SHOULD_RUN_FILES=true
            SHOULD_RUN_BLOCK=true
        elif [ "\$FORCE_FULL" = "files" ]; then
            log "Manual files-only backup"
            SHOULD_RUN_FILES=true
            SHOULD_RUN_BLOCK=false
        elif [ "\$FORCE_FULL" = "block" ]; then
            log "Manual block-only backup"
            SHOULD_RUN_FILES=false
            SHOULD_RUN_BLOCK=true
        else
            # Scheduled backup - check if it's time based on frequency
            CURRENT_DOW=\$(date +%u)  # 1=Mon, 7=Sun
            CURRENT_DOM=\$(date +%d | sed 's/^0//')  # Remove leading zero

            case "\$BLOCK_DEVICE_FREQUENCY" in
                weekly)
                    if [ "\$CURRENT_DOW" -eq "\$BLOCK_DEVICE_DAY" ]; then
                        log "Weekly block device backup day (day \$BLOCK_DEVICE_DAY)"
                        SHOULD_RUN_BLOCK=true
                    fi
                    ;;
                biweekly)
                    WEEK_OF_YEAR=\$(date +%V)
                    if [ "\$CURRENT_DOW" -eq "\$BLOCK_DEVICE_DAY" ] && [ \$((WEEK_OF_YEAR % 2)) -eq 0 ]; then
                        log "Biweekly block device backup day (even week, day \$BLOCK_DEVICE_DAY)"
                        SHOULD_RUN_BLOCK=true
                    fi
                    ;;
                monthly)
                    if [ "\$CURRENT_DOM" -eq "\$BLOCK_DEVICE_DAY" ]; then
                        log "Monthly block device backup day (\$BLOCK_DEVICE_DAY of month)"
                        SHOULD_RUN_BLOCK=true
                    fi
                    ;;
                *)
                    log "Unknown BLOCK_DEVICE_FREQUENCY: \$BLOCK_DEVICE_FREQUENCY, defaulting to weekly Sunday"
                    if [ "\$CURRENT_DOW" -eq 7 ]; then
                        SHOULD_RUN_BLOCK=true
                    fi
                    ;;
            esac
        fi

        # Execute backups based on decisions
        if [ "\$SHOULD_RUN_FILES" = true ]; then
            backup_files || BACKUP_SUCCESS=false
        else
            log "Skipping file backup (block-only mode)"
        fi

        if [ "\$SHOULD_RUN_BLOCK" = true ]; then
            backup_block_device || BACKUP_SUCCESS=false
        else
            log "Skipping block device backup (next: \${BLOCK_DEVICE_FREQUENCY} on day \${BLOCK_DEVICE_DAY})"
        fi
        ;;
    *)
        log "ERROR: Invalid BACKUP_TYPE: \${BACKUP_TYPE}" >&2
        exit 1
        ;;
esac

# Prune old backups
if [ "\$BACKUP_SUCCESS" = true ]; then
    log "Pruning old backups..."
    proxmox-backup-client prune "host/\${HOSTNAME}" \\
        --keep-last \$KEEP_LAST \\
        --keep-daily \$KEEP_DAILY \\
        --keep-weekly \$KEEP_WEEKLY \\
        --keep-monthly \$KEEP_MONTHLY

    log "Backup and prune completed successfully"
else
    log "Backup FAILED" >&2
    exit 1
fi
EOFSCRIPT

    chmod 700 "$CONFIG_DIR/backup-${target_name}.sh"

    # Create systemd service file (for scheduled backups)
    cat > "/etc/systemd/system/pbs-backup-${target_name}.service" <<EOF
[Unit]
Description=Proxmox Backup Client Backup - Target: $target_name
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CONFIG_DIR/backup-${target_name}.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pbs-backup

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd service file for manual full backups
    cat > "/etc/systemd/system/pbs-backup-${target_name}-manual.service" <<EOF
[Unit]
Description=Proxmox Backup Client Manual Full Backup - Target: $target_name
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CONFIG_DIR/backup-${target_name}.sh yes
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pbs-backup

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer file
    cat > "/etc/systemd/system/pbs-backup-${target_name}.timer" <<EOF
[Unit]
Description=Proxmox Backup Client Backup Timer - Target: $target_name
Requires=pbs-backup-${target_name}.service

[Timer]
OnCalendar=${TIMER_ONCALENDAR}
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable timer
    systemctl daemon-reload
    systemctl enable "pbs-backup-${target_name}.timer"
    systemctl start "pbs-backup-${target_name}.timer"

    log "Systemd service and timer created successfully for target: $target_name"
    info "Timer status:"
    systemctl status "pbs-backup-${target_name}.timer" --no-pager -l || true
}

# Run backup immediately
run_backup_now() {
    echo
    RUN_NOW=$(prompt "Do you want to run a backup now? (yes/no)" "no")

    if [[ "$RUN_NOW" == "yes" ]]; then
        log "Starting immediate FULL backup (files + block device)..."
        echo

        # Show real-time progress
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  Backup Progress (Live)                                    ║"
        echo "║  Press Ctrl+C to exit (backup continues in background)    ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo

        # Start the manual backup (forces full backup)
        systemctl start pbs-backup-manual.service &

        # Wait a brief moment for service to register
        sleep 0.5

        # Monitor backup in background and kill journalctl when done
        (
            while systemctl is-active --quiet pbs-backup-manual.service; do
                sleep 2
            done
            # Service finished, kill the journal follow
            pkill -P $$ journalctl 2>/dev/null
        ) &
        MONITOR_PID=$!

        # Follow logs in foreground from the start (will be killed by monitor when backup completes)
        journalctl -u pbs-backup-manual.service -f --since "2 seconds ago" || true

        # Wait for monitor to finish
        wait $MONITOR_PID 2>/dev/null

        # Clear any leftover output
        echo
        echo "════════════════════════════════════════════════════════════"

        # Check final status
        if systemctl status pbs-backup-manual.service | grep -q "Active: failed"; then
            echo
            error "Backup failed!"
        else
            echo
            log "Backup completed successfully!"
        fi
    fi
}

# Show summary and next steps
show_summary() {
    echo
    echo "======================================"
    echo "  Installation Complete!"
    echo "======================================"
    echo
    info "Configuration Summary:"
    echo "  PBS Server: ${PBS_SERVER}:${PBS_PORT}"
    echo "  Datastore: ${PBS_DATASTORE}"
    echo "  Repository: ${PBS_REPOSITORY}"
    echo "  Backup Type: ${BACKUP_TYPE}"
    
    if [[ "$BACKUP_TYPE" == "files" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Backup Paths: ${BACKUP_PATHS}"
    fi
    
    if [[ "$BACKUP_TYPE" == "block" ]] || [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Block Device: ${BLOCK_DEVICE}"
    fi
    
    if [[ "$BACKUP_TYPE" == "both" ]]; then
        echo "  Schedule: Files ${TIMER_SCHEDULE} (${TIMER_ONCALENDAR}), Block device weekly (Sunday)"
    else
        echo "  Schedule: ${TIMER_SCHEDULE} (${TIMER_ONCALENDAR})"
    fi
    echo
    info "Useful Commands:"
    echo "  Check timer status:  sudo systemctl status pbs-backup.timer"
    echo "  Check service logs:  sudo journalctl -u pbs-backup.service"
    echo "  Run backup now:      sudo systemctl start pbs-backup.service"
    echo "  List backups:        sudo -E proxmox-backup-client snapshot list"
    echo "  Disable backups:     sudo systemctl disable pbs-backup.timer"
    echo
    info "Configuration Files:"
    echo "  Config:              $CONFIG_DIR/config"
    echo "  Backup script:       $CONFIG_DIR/backup.sh"
    echo "  Service:             /etc/systemd/system/pbs-backup.service"
    echo "  Timer:               /etc/systemd/system/pbs-backup.timer"
    
    if [[ "$ENABLE_ENCRYPTION" == "yes" ]]; then
        echo
        warn "IMPORTANT: Backup your encryption key!"
        echo "  Key location: /root/.config/proxmox-backup/encryption-key.json"
        echo "  Paper backup: /root/pbs-encryption-key-*.txt"
    fi
    
    echo
    log "Setup completed successfully!"
}

# Install script to system PATH
install_script() {
    check_root

    echo
    echo "╔════════════════════════════════════════╗"
    echo "║  Install PBSClientTool                 ║"
    echo "╚════════════════════════════════════════╝"
    echo

    # Get the absolute path of this script
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

    if [ -f "$INSTALL_PATH" ]; then
        warn "PBSClientTool is already installed at $INSTALL_PATH"
        OVERWRITE=$(prompt "Do you want to overwrite it? (yes/no)" "no")
        if [ "$OVERWRITE" != "yes" ]; then
            info "Installation cancelled"
            return 0
        fi
    fi

    log "Installing PBSClientTool to $INSTALL_PATH..."

    # Copy script to /usr/local/bin/
    cp "$SCRIPT_PATH" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"

    log "Installation complete!"
    echo
    info "You can now run the tool from anywhere using:"
    echo "  sudo $SCRIPT_NAME"
    echo
    info "Available commands:"
    echo "  sudo $SCRIPT_NAME          - Run interactive menu"
    echo "  sudo $SCRIPT_NAME --help   - Show help message"
    echo "  sudo $SCRIPT_NAME --version - Show version"
    echo
}

# Uninstall script from system PATH
uninstall_script() {
    check_root

    echo
    echo "╔════════════════════════════════════════╗"
    echo "║  Uninstall PBSClientTool               ║"
    echo "╚════════════════════════════════════════╝"
    echo

    if [ ! -f "$INSTALL_PATH" ]; then
        error "PBSClientTool is not installed at $INSTALL_PATH"
        return 1
    fi

    warn "This will remove the PBSClientTool command from your system"
    warn "Your backup targets and configurations will NOT be removed"
    echo
    CONFIRM=$(prompt "Do you want to continue? (yes/no)" "no")

    if [ "$CONFIRM" != "yes" ]; then
        info "Uninstall cancelled"
        return 0
    fi

    log "Removing $INSTALL_PATH..."
    rm -f "$INSTALL_PATH"

    log "Uninstall complete!"
    echo
    info "To completely remove all backup configurations, use the uninstaller:"
    echo "  sudo ./uninstaller.sh"
    echo
}

# Show help message
show_help() {
    cat << EOF

Proxmox Backup Client Tool v${SCRIPT_VERSION}

A tool for managing Proxmox Backup Server client installations and multi-target backups.

USAGE:
    sudo $SCRIPT_NAME [OPTIONS]

OPTIONS:
    --install       Install PBSClientTool to /usr/local/bin (makes it available system-wide)
    --uninstall     Uninstall PBSClientTool from system
    --help, -h      Show this help message
    --version, -v   Show version information

INTERACTIVE MODE (default):
    Run without arguments to launch the interactive menu for managing backup targets.

EXAMPLES:
    # Install to system PATH
    sudo ./pbs-client-installer.sh --install

    # Run from anywhere after installation
    sudo $SCRIPT_NAME

    # Show version
    sudo $SCRIPT_NAME --version

    # Uninstall from system
    sudo $SCRIPT_NAME --uninstall

FEATURES:
    - Multi-target backup support (backup to multiple PBS servers)
    - File-level and block device backups
    - Automated backup scheduling with systemd timers
    - Connection testing and validation
    - Easy target management (add, edit, delete, view)

DOCUMENTATION:
    https://github.com/zaphod-black/PBSClientTool

EOF
}

# Show version
show_version() {
    echo "PBSClientTool version $SCRIPT_VERSION"
}

# Main script execution
main() {
    echo
    echo "╔════════════════════════════════════════╗"
    echo "║  Proxmox Backup Client Installer      ║"
    echo "║  Version: ${SCRIPT_VERSION}                     ║"
    echo "╚════════════════════════════════════════╝"
    echo
    
    # Create log file
    touch "$LOG_FILE"
    
    # Check root
    check_root

    # Detect distribution
    detect_distro

    # Migrate legacy configuration if needed
    migrate_legacy_config

    # Check if script is installed as system command
    SCRIPT_INSTALLED=false
    if [ -f "$INSTALL_PATH" ]; then
        SCRIPT_INSTALLED=true
    fi

    # Check if PBS client is already installed
    if command -v proxmox-backup-client &> /dev/null; then
        warn "Proxmox Backup Client is already installed"

        # Check if any targets exist
        if list_targets >/dev/null 2>&1; then
            show_targets_list
            test_all_targets

            # Main menu loop
            while true; do
                echo
                echo "════════════════════════════════════════"
                echo "  Multi-Target Backup Management"
                echo "════════════════════════════════════════"
                echo
                echo "What would you like to do?"
                echo "  1) List all backup targets"
                echo "  2) Add new backup target"
                echo "  3) Edit existing target"
                echo "  4) Delete target"
                echo "  5) Run backup now (select target)"
                echo "  6) Reinstall PBS client"

                # Only show install option if not already installed
                if [ "$SCRIPT_INSTALLED" = false ]; then
                    echo "  7) Install as system command"
                    echo "  8) Exit"
                    ACTION=$(prompt "Select option [1-8]" "8")
                else
                    echo "  7) Exit"
                    ACTION=$(prompt "Select option [1-7]" "7")
                fi

                case "$ACTION" in
                    1)
                        show_targets_list
                        echo
                        echo "Options:"
                        echo "  1) View target details"
                        echo "  2) Back to main menu"
                        SUBACTION=$(prompt "Select option [1/2]" "2")

                        case "$SUBACTION" in
                            1)
                                echo
                                echo "Available targets:"
                                list_targets | nl
                                echo
                                USER_INPUT=$(prompt "Enter target number or name to view" "")

                                if [ -n "$USER_INPUT" ]; then
                                    TARGET_NAME=$(resolve_target_input "$USER_INPUT")
                                    if [ -n "$TARGET_NAME" ] && validate_target_name "$TARGET_NAME"; then
                                        show_target_detail "$TARGET_NAME"
                                    fi
                                fi
                                ;;
                            2)
                                # Just continue to main menu
                                ;;
                            *)
                                warn "Invalid option, returning to main menu"
                                ;;
                        esac
                        ;;
                    2)
                        add_target
                        ;;
                    3)
                        edit_target
                        ;;
                    4)
                        delete_target
                        ;;
                    5)
                        echo
                        echo "Available targets:"
                        list_targets | nl
                        echo
                        USER_INPUT=$(prompt "Enter target number or name to backup" "")

                        if [ -z "$USER_INPUT" ]; then
                            error "No target specified"
                            continue
                        fi

                        TARGET_NAME=$(resolve_target_input "$USER_INPUT")
                        if [ -z "$TARGET_NAME" ]; then
                            error "Invalid target number: $USER_INPUT"
                            continue
                        fi

                        if ! validate_target_name "$TARGET_NAME"; then
                            continue
                        fi

                        if ! target_exists "$TARGET_NAME"; then
                            error "Target '$TARGET_NAME' does not exist"
                            continue
                        fi

                        run_backup_for_target "$TARGET_NAME"
                        ;;
                    6)
                        info "Reinstalling PBS client..."
                        install_pbs_client
                        log "PBS client reinstalled successfully"
                        ;;
                    7)
                        # Option 7 is either "Install" or "Exit" depending on install status
                        if [ "$SCRIPT_INSTALLED" = false ]; then
                            install_script
                            # Update status if installation succeeded
                            if [ -f "$INSTALL_PATH" ]; then
                                SCRIPT_INSTALLED=true
                            fi
                        else
                            info "Exiting"
                            exit 0
                        fi
                        ;;
                    8)
                        # Option 8 only exists when not installed (it's Exit)
                        if [ "$SCRIPT_INSTALLED" = false ]; then
                            info "Exiting"
                            exit 0
                        else
                            error "Invalid option"
                        fi
                        ;;
                    *)
                        error "Invalid option"
                        ;;
                esac
            done
        else
            # PBS client installed but no targets configured
            info "No backup targets configured"
            echo
            info "Let's create your first backup target!"
            echo

            TARGET_NAME=$(prompt "Enter name for first target (e.g., 'primary', 'local', 'offsite')" "default")

            if ! validate_target_name "$TARGET_NAME"; then
                error "Invalid target name"
                exit 1
            fi

            if target_exists "$TARGET_NAME"; then
                error "Target '$TARGET_NAME' already exists"
                exit 1
            fi

            interactive_config_for_target "$TARGET_NAME"

            echo
            log "First target '$TARGET_NAME' created successfully!"
            echo

            # Offer to install as system command
            if [ ! -f "$INSTALL_PATH" ]; then
                echo
                info "Would you like to install PBSClientTool as a system command?"
                echo "This will allow you to run 'sudo PBSClientTool' from anywhere."
                echo
                INSTALL_CHOICE=$(prompt "Install as system command? (yes/no)" "yes")

                if [ "$INSTALL_CHOICE" = "yes" ]; then
                    echo
                    install_script
                fi
            fi

            echo
            info "You can add more targets by running this script again."
            exit 0
        fi
    else
        # PBS client not installed
        info "Proxmox Backup Client is not installed on this system"
        echo
        echo "This script will:"
        echo "  1. Install Proxmox Backup Client"
        echo "  2. Configure your first backup target"
        echo "  3. Set up automated backups"
        echo

        PROCEED=$(prompt "Do you want to proceed with installation? (yes/no)" "yes")

        if [ "$PROCEED" != "yes" ]; then
            info "Installation cancelled"
            exit 0
        fi

        echo
        info "Installing Proxmox Backup Client..."
        install_pbs_client

        echo
        info "Installation complete! Now let's create your first backup target!"
        echo

        TARGET_NAME=$(prompt "Enter name for first target (e.g., 'primary', 'local', 'offsite')" "default")

        if ! validate_target_name "$TARGET_NAME"; then
            error "Invalid target name"
            exit 1
        fi

        interactive_config_for_target "$TARGET_NAME"

        echo
        log "First target '$TARGET_NAME' created successfully!"
        echo

        # Offer to install as system command
        if [ ! -f "$INSTALL_PATH" ]; then
            echo
            info "Would you like to install PBSClientTool as a system command?"
            echo "This will allow you to run 'sudo PBSClientTool' from anywhere."
            echo
            INSTALL_CHOICE=$(prompt "Install as system command? (yes/no)" "yes")

            if [ "$INSTALL_CHOICE" = "yes" ]; then
                echo
                install_script
            fi
        fi

        echo
        info "You can add more targets by running this script again."
        exit 0
    fi

    # All paths should exit above, this should never be reached
    error "Unexpected code path - please report this bug"
    exit 1
}

# Parse command-line arguments
case "${1:-}" in
    --install)
        install_script
        ;;
    --uninstall)
        uninstall_script
        ;;
    --help|-h)
        show_help
        ;;
    --version|-v)
        show_version
        ;;
    "")
        # No arguments - run interactive mode
        main
        ;;
    *)
        error "Unknown option: $1"
        echo
        echo "Run with --help for usage information"
        exit 1
        ;;
esac
