#!/bin/bash
set -e

# Entrypoint for PBS Client Docker Container
# Handles both daemon mode (continuous with cron) and one-shot backup mode

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /logs/container.log
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a /logs/container.log >&2
}

# Set timezone
if [ -n "$TIMEZONE" ]; then
    ln -snf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    echo $TIMEZONE > /etc/timezone
fi

# Validate required environment variables
validate_config() {
    if [ -z "$PBS_REPOSITORY" ]; then
        error "PBS_REPOSITORY environment variable is required"
        return 1
    fi
    
    if [ -z "$PBS_PASSWORD" ]; then
        error "PBS_PASSWORD environment variable is required"
        return 1
    fi
    
    return 0
}

# Initialize encryption key if not exists
init_encryption() {
    if [ ! -f /config/encryption-key.json ]; then
        log "Generating encryption key..."
        mkdir -p /config
        proxmox-backup-client key create --kdf none 2>/dev/null || true
        
        # Copy to persistent config volume
        if [ -f /root/.config/proxmox-backup/encryption-key.json ]; then
            cp /root/.config/proxmox-backup/encryption-key.json /config/
            log "Encryption key created and saved to /config/"
            
            # Create paper backup
            proxmox-backup-client key paperkey --output-format text > /config/encryption-key-paper.txt
            log "Paper backup created: /config/encryption-key-paper.txt"
        fi
    else
        log "Using existing encryption key from /config/"
        mkdir -p /root/.config/proxmox-backup
        cp /config/encryption-key.json /root/.config/proxmox-backup/
    fi
}

# Setup cron for daemon mode
setup_cron() {
    log "Setting up cron schedule: $BACKUP_SCHEDULE"
    
    # Create cron job
    cat > /etc/cron.d/pbs-backup << EOF
# PBS Backup Schedule
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
PBS_REPOSITORY=$PBS_REPOSITORY
PBS_PASSWORD=$PBS_PASSWORD

$BACKUP_SCHEDULE root /usr/local/bin/pbs-backup >> /logs/cron.log 2>&1
EOF

    chmod 0644 /etc/cron.d/pbs-backup
    
    # Apply cron environment
    printenv | grep -v "no_proxy" >> /etc/environment
    
    log "Cron configured successfully"
}

# Start daemon mode
start_daemon() {
    log "Starting PBS Client in daemon mode"
    log "Backup schedule: $BACKUP_SCHEDULE"
    log "Monitoring logs at /logs/"
    
    validate_config || exit 1
    init_encryption
    setup_cron
    
    # Start API server if enabled
    if [ "$ENABLE_API" = "true" ]; then
        log "Starting API server on port 8080"
        /usr/local/bin/api-server &
    fi
    
    # Start cron in foreground
    log "Starting cron daemon..."
    cron -f
}

# Run one-shot backup
run_backup() {
    log "Running one-shot backup"
    
    validate_config || exit 1
    init_encryption
    
    # Export for PBS client
    export PBS_REPOSITORY
    export PBS_PASSWORD
    
    # Run backup
    /usr/local/bin/pbs-backup
}

# Test connection
test_connection() {
    log "Testing connection to PBS server..."
    
    validate_config || exit 1
    
    export PBS_REPOSITORY
    export PBS_PASSWORD
    
    if proxmox-backup-client snapshot list >/dev/null 2>&1; then
        log "Connection test successful!"
        return 0
    else
        error "Connection test failed"
        return 1
    fi
}

# Show status
show_status() {
    log "PBS Client Container Status"
    echo "=========================="
    echo "Mode: $MODE"
    echo "PBS Repository: $PBS_REPOSITORY"
    echo "Backup Paths: $BACKUP_PATHS"
    echo "Schedule: $BACKUP_SCHEDULE"
    echo "Timezone: $TIMEZONE"
    echo "=========================="
    
    if [ "$MODE" = "daemon" ]; then
        echo "Last backup:"
        if [ -f /logs/last-backup.log ]; then
            tail -5 /logs/last-backup.log
        else
            echo "  No backups run yet"
        fi
    fi
}

# Main logic
case "${1:-$MODE}" in
    daemon)
        start_daemon
        ;;
    backup)
        run_backup
        ;;
    test)
        test_connection
        ;;
    status)
        show_status
        ;;
    shell)
        log "Starting interactive shell"
        exec /bin/bash
        ;;
    *)
        error "Unknown command: $1"
        echo "Usage: $0 {daemon|backup|test|status|shell}"
        exit 1
        ;;
esac
