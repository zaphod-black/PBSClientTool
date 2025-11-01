#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_VERSION="1.0.0"
CONFIG_DIR="/etc/proxmox-backup-client"
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
    echo
    echo "$user_input"
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
    PBS_SERVER=$(prompt "Enter PBS server IP/hostname" "192.168.1.181")
    PBS_PORT=$(prompt "Enter PBS server port" "8007")
    PBS_DATASTORE=$(prompt "Enter datastore name" "backups")

    echo
    info "Authentication Method:"
    echo "  1) Username + Password"
    echo "  2) API Token (recommended for automation)"
    AUTH_METHOD=$(prompt "Select authentication method [1/2]" "2")

    if [ "$AUTH_METHOD" = "1" ]; then
        PBS_USERNAME=$(prompt "Enter username" "root")
        PBS_REALM=$(prompt "Enter realm" "pam")
        PBS_PASSWORD=$(prompt_password "Enter password")
        PBS_REPOSITORY="${PBS_USERNAME}@${PBS_REALM}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
    else
        PBS_USERNAME=$(prompt "Enter username" "backup")
        PBS_REALM=$(prompt "Enter realm" "pbs")
        PBS_TOKEN_NAME=$(prompt "Enter token name" "backup-token")
        PBS_TOKEN_SECRET=$(prompt_password "Enter token secret")
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
    cat > "$CONFIG_DIR/config" <<EOF
# PBS Client Configuration
PBS_REPOSITORY="${PBS_REPOSITORY}"
PBS_PASSWORD="${PBS_PASSWORD}"
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

# Interactive configuration
interactive_config() {
    log "Starting interactive configuration..."
    echo
    echo "======================================"
    echo "  PBS Client Configuration"
    echo "======================================"
    echo

    # PBS Server details
    PBS_SERVER=$(prompt "Enter PBS server IP/hostname" "192.168.1.181")
    PBS_PORT=$(prompt "Enter PBS server port" "8007")
    PBS_DATASTORE=$(prompt "Enter datastore name" "backups")
    
    echo
    info "Authentication Method:"
    echo "  1) Username + Password"
    echo "  2) API Token (recommended for automation)"
    AUTH_METHOD=$(prompt "Select authentication method [1/2]" "2")
    
    if [ "$AUTH_METHOD" = "1" ]; then
        PBS_USERNAME=$(prompt "Enter username" "root")
        PBS_REALM=$(prompt "Enter realm" "pam")
        PBS_PASSWORD=$(prompt_password "Enter password")
        PBS_REPOSITORY="${PBS_USERNAME}@${PBS_REALM}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
    else
        PBS_USERNAME=$(prompt "Enter username" "backup")
        PBS_REALM=$(prompt "Enter realm" "pbs")
        PBS_TOKEN_NAME=$(prompt "Enter token name" "backup-token")
        PBS_TOKEN_SECRET=$(prompt_password "Enter token secret")
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
        ROOT_DEVICE=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's/p$//' 2>/dev/null || echo "")
        
        if [ -n "$ROOT_DEVICE" ]; then
            info "Auto-detected root device: $ROOT_DEVICE"
            BLOCK_DEVICE=$(prompt "Enter block device to backup" "$ROOT_DEVICE")
        else
            info "Common devices: /dev/sda, /dev/nvme0n1, /dev/vda"
            BLOCK_DEVICE=$(prompt "Enter block device to backup" "/dev/sda")
        fi
        
        # Verify it's a block device
        if [ ! -b "$BLOCK_DEVICE" ]; then
            warn "Warning: $BLOCK_DEVICE does not exist or is not a block device"
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
    
    echo
    # Retention policy
    info "Retention Policy:"
    KEEP_LAST=$(prompt "Keep last N backups" "3")
    KEEP_DAILY=$(prompt "Keep daily backups for N days" "7")
    KEEP_WEEKLY=$(prompt "Keep weekly backups for N weeks" "4")
    KEEP_MONTHLY=$(prompt "Keep monthly backups for N months" "6")
    
    # Encryption
    echo
    ENABLE_ENCRYPTION=$(prompt "Enable encryption? (yes/no)" "yes")
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
    
    if proxmox-backup-client snapshot list &>/dev/null; then
        log "Connection test successful!"
        return 0
    else
        error "Connection test failed"
        error "Please verify your server details and credentials"
        return 1
    fi
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service and timer..."
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    # Save configuration
    cat > "$CONFIG_DIR/config" <<EOF
# PBS Client Configuration
PBS_REPOSITORY="${PBS_REPOSITORY}"
PBS_PASSWORD="${PBS_PASSWORD}"
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
        
        # Only do block device backup on Sunday (weekly)
        if [ "$(date +%u)" -eq 7 ]; then
            log "Weekly block device backup day (Sunday)"
            backup_block_device || BACKUP_SUCCESS=false
        else
            log "Skipping block device backup (runs weekly on Sunday)"
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
    
    # Create systemd service file
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

# Run backup immediately
run_backup_now() {
    echo
    RUN_NOW=$(prompt "Do you want to run a backup now? (yes/no)" "no")
    
    if [[ "$RUN_NOW" == "yes" ]]; then
        log "Starting immediate backup..."
        echo
        
        if systemctl start pbs-backup.service; then
            log "Backup job started"
            echo
            info "View backup progress with:"
            echo "  sudo journalctl -fu pbs-backup.service"
            echo
            
            # Ask if they want to follow logs
            FOLLOW_LOGS=$(prompt "Follow backup logs now? (yes/no)" "yes")
            if [[ "$FOLLOW_LOGS" == "yes" ]]; then
                journalctl -fu pbs-backup.service
            fi
        else
            error "Failed to start backup job"
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

    # Check if PBS client is already installed
    if command -v proxmox-backup-client &> /dev/null; then
        warn "Proxmox Backup Client is already installed"

        # Check if configuration exists
        if [ -f "$CONFIG_DIR/config" ]; then
            info "Existing configuration detected"
            echo
            echo "What would you like to do?"
            echo "  1) Reconfigure connection only (server/credentials)"
            echo "  2) Full reconfiguration (all settings)"
            echo "  3) Reinstall PBS client and reconfigure"
            echo "  4) Exit"
            ACTION=$(prompt "Select option [1/2/3/4]" "1")

            case "$ACTION" in
                1)
                    info "Reconfiguring connection only..."
                    reconfigure_connection
                    # Skip most of the setup, just restart services
                    systemctl daemon-reload
                    systemctl restart pbs-backup.timer
                    log "Configuration updated and services restarted!"
                    echo
                    info "Your backup schedule and settings remain unchanged."
                    exit 0
                    ;;
                2)
                    info "Proceeding with full reconfiguration..."
                    # Continue to interactive_config below
                    ;;
                3)
                    info "Reinstalling PBS client..."
                    install_pbs_client
                    # Continue to interactive_config below
                    ;;
                4)
                    info "Exiting without changes"
                    exit 0
                    ;;
                *)
                    error "Invalid option"
                    exit 1
                    ;;
            esac
        else
            # PBS client installed but no config
            info "No existing configuration found"
            echo
            echo "What would you like to do?"
            echo "  1) Configure PBS client"
            echo "  2) Reinstall and configure"
            echo "  3) Exit"
            ACTION=$(prompt "Select option [1/2/3]" "1")

            case "$ACTION" in
                1)
                    info "Proceeding with configuration..."
                    # Continue to interactive_config below
                    ;;
                2)
                    info "Reinstalling PBS client..."
                    install_pbs_client
                    # Continue to interactive_config below
                    ;;
                3)
                    info "Exiting without changes"
                    exit 0
                    ;;
                *)
                    error "Invalid option"
                    exit 1
                    ;;
            esac
        fi
    else
        # PBS client not installed
        install_pbs_client
    fi

    # Interactive configuration
    interactive_config

    # Create encryption key
    create_encryption_key

    # Test connection
    if ! test_connection; then
        error "Cannot proceed without successful connection to PBS"
        exit 1
    fi

    # Create systemd service
    create_systemd_service

    # Offer to run backup now
    run_backup_now

    # Show summary
    show_summary
}

# Run main function
main "$@"
