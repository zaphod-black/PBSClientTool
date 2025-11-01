#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONFIG_DIR="/etc/proxmox-backup-client"

# Helper functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
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

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error "Cannot detect Linux distribution"
        exit 1
    fi
    
    OS=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
}

# Confirm uninstallation
confirm_uninstall() {
    echo
    echo "╔════════════════════════════════════════╗"
    echo "║  PBS Client Uninstaller                ║"
    echo "╚════════════════════════════════════════╝"
    echo
    
    warn "This will remove:"
    echo "  - Proxmox Backup Client software"
    echo "  - Systemd service and timer"
    echo "  - Configuration files in $CONFIG_DIR"
    echo "  - Repository configuration"
    echo
    info "This will NOT remove:"
    echo "  - Your backups on the PBS server"
    echo "  - Encryption keys in /root/.config/proxmox-backup/"
    echo
    
    CONFIRM=$(prompt "Are you sure you want to uninstall? (yes/no)" "no")
    if [[ "$CONFIRM" != "yes" ]]; then
        info "Uninstallation cancelled"
        exit 0
    fi
    
    KEEP_ENCRYPTION_KEY=$(prompt "Keep encryption key? (yes/no)" "yes")
}

# Stop and disable systemd service
remove_systemd_service() {
    log "Stopping and disabling systemd services..."
    
    if systemctl is-active --quiet pbs-backup.timer; then
        systemctl stop pbs-backup.timer
    fi
    
    if systemctl is-enabled --quiet pbs-backup.timer; then
        systemctl disable pbs-backup.timer
    fi
    
    if systemctl is-active --quiet pbs-backup.service; then
        systemctl stop pbs-backup.service
    fi
    
    # Remove service files
    rm -f /etc/systemd/system/pbs-backup.service
    rm -f /etc/systemd/system/pbs-backup.timer
    
    systemctl daemon-reload
    
    log "Systemd services removed"
}

# Remove configuration
remove_config() {
    log "Removing configuration files..."
    
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        log "Configuration directory removed: $CONFIG_DIR"
    fi
    
    # Remove encryption key if requested
    if [[ "$KEEP_ENCRYPTION_KEY" == "no" ]]; then
        if [ -d /root/.config/proxmox-backup ]; then
            rm -rf /root/.config/proxmox-backup
            log "Encryption keys removed"
        fi
        
        # Remove paper backups
        rm -f /root/pbs-encryption-key-*.txt
    else
        warn "Encryption keys preserved in /root/.config/proxmox-backup/"
        warn "Paper backups preserved: /root/pbs-encryption-key-*.txt"
    fi
}

# Uninstall PBS client on Ubuntu/Debian
uninstall_debian_based() {
    log "Uninstalling PBS client on $OS..."
    
    if dpkg -l | grep -q proxmox-backup-client; then
        apt-get remove -y proxmox-backup-client
        apt-get autoremove -y
        log "PBS client package removed"
    fi
    
    # Remove repository files
    rm -f /etc/apt/sources.list.d/pbs-client.list
    rm -f /etc/apt/sources.list.d/focal-security.list
    
    # Remove GPG keys
    rm -f /etc/apt/trusted.gpg.d/proxmox-release-*.gpg
    
    apt-get update -qq
    
    log "Repository configuration removed"
}

# Uninstall PBS client on Arch
uninstall_arch() {
    log "Uninstalling PBS client on Arch Linux..."
    
    # Get the user who invoked sudo
    if [ -n "$SUDO_USER" ]; then
        REAL_USER="$SUDO_USER"
    else
        warn "Cannot determine original user, attempting removal as root"
        REAL_USER="root"
    fi
    
    if pacman -Q proxmox-backup-client-bin &>/dev/null; then
        if [ "$REAL_USER" != "root" ]; then
            sudo -u "$REAL_USER" yay -R --noconfirm proxmox-backup-client-bin
        else
            pacman -R --noconfirm proxmox-backup-client-bin
        fi
        log "PBS client package removed"
    elif pacman -Q proxmox-backup-client &>/dev/null; then
        if [ "$REAL_USER" != "root" ]; then
            sudo -u "$REAL_USER" yay -R --noconfirm proxmox-backup-client
        else
            pacman -R --noconfirm proxmox-backup-client
        fi
        log "PBS client package removed"
    fi
}

# Main uninstall function
uninstall_pbs_client() {
    case "$OS" in
        ubuntu|debian)
            uninstall_debian_based
            ;;
        arch|archlinux)
            uninstall_arch
            ;;
        *)
            warn "Unknown distribution: $OS"
            warn "Manual package removal may be required"
            ;;
    esac
}

# Show completion message
show_completion() {
    echo
    echo "======================================"
    echo "  Uninstallation Complete"
    echo "======================================"
    echo
    log "PBS client has been uninstalled"
    
    if [[ "$KEEP_ENCRYPTION_KEY" == "yes" ]]; then
        info "Encryption keys preserved:"
        echo "  /root/.config/proxmox-backup/encryption-key.json"
        echo "  /root/pbs-encryption-key-*.txt"
        echo
        warn "Remember to backup these keys before removing the system!"
    fi
    
    info "Your backups on the PBS server remain intact"
    info "You can reinstall the client at any time to access them"
    echo
}

# Main execution
main() {
    check_root
    detect_distro
    confirm_uninstall
    remove_systemd_service
    remove_config
    uninstall_pbs_client
    show_completion
}

main "$@"
