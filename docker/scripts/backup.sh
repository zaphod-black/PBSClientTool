#!/bin/bash
set -e

# PBS Backup Script - Runs inside Docker container
# Backs up mounted host filesystem

HOSTNAME=${CONTAINER_HOSTNAME:-$(hostname)}
LOG_FILE="/logs/last-backup.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Parse backup paths into array
IFS=' ' read -ra PATHS <<< "$BACKUP_PATHS"
IFS=' ' read -ra EXCLUDES <<< "$EXCLUDE_PATTERNS"

# Validate backup paths exist
for path in "${PATHS[@]}"; do
    if [ ! -e "$path" ]; then
        error "Backup path does not exist: $path"
        exit 1
    fi
done

log "========================================="
log "Starting backup for $HOSTNAME"
log "========================================="
log "Paths: ${PATHS[*]}"
log "Excludes: ${EXCLUDES[*]}"

# Build backup command
BACKUP_CMD="proxmox-backup-client backup"

# Add each path as separate archive
for path in "${PATHS[@]}"; do
    # Sanitize path for archive name
    # /host-data/home -> home.pxar
    # /host-data -> root.pxar
    archive_name=$(echo "$path" | sed 's/^\/host-data\///' | sed 's/\//-/g')
    [ -z "$archive_name" ] && archive_name="root"
    [ "$archive_name" = "host-data" ] && archive_name="root"
    
    BACKUP_CMD="$BACKUP_CMD ${archive_name}.pxar:${path}"
done

# Add exclusions
for pattern in "${EXCLUDES[@]}"; do
    BACKUP_CMD="$BACKUP_CMD --exclude=${pattern}"
done

# Add options
BACKUP_CMD="$BACKUP_CMD --skip-lost-and-found"

# Use metadata change detection if not first backup
if proxmox-backup-client snapshot list 2>/dev/null | grep -q "$HOSTNAME"; then
    BACKUP_CMD="$BACKUP_CMD --change-detection-mode=metadata"
    log "Using metadata change detection (incremental)"
else
    log "First backup - reading all files"
fi

# Execute backup
log "Executing backup command..."
if eval $BACKUP_CMD 2>&1 | tee -a "$LOG_FILE"; then
    log "Backup completed successfully"
    BACKUP_SUCCESS=true
else
    error "Backup FAILED"
    BACKUP_SUCCESS=false
fi

# Prune old backups
if [ "$BACKUP_SUCCESS" = true ] && [ "${ENABLE_PRUNE:-true}" = "true" ]; then
    log "Pruning old backups..."
    
    # Use environment variables or defaults
    KEEP_LAST=${KEEP_LAST:-3}
    KEEP_DAILY=${KEEP_DAILY:-7}
    KEEP_WEEKLY=${KEEP_WEEKLY:-4}
    KEEP_MONTHLY=${KEEP_MONTHLY:-6}
    
    if proxmox-backup-client prune "host/${HOSTNAME}" \
        --keep-last "$KEEP_LAST" \
        --keep-daily "$KEEP_DAILY" \
        --keep-weekly "$KEEP_WEEKLY" \
        --keep-monthly "$KEEP_MONTHLY" 2>&1 | tee -a "$LOG_FILE"; then
        log "Prune completed successfully"
    else
        error "Prune failed"
    fi
fi

# Save stats
log "========================================="
log "Backup session completed"
log "========================================="

# Update status file
cat > /logs/status.json << EOF
{
  "last_backup": "$(date -Iseconds)",
  "hostname": "$HOSTNAME",
  "success": $BACKUP_SUCCESS,
  "paths": ${PATHS[@]@json}
}
EOF

if [ "$BACKUP_SUCCESS" = true ]; then
    exit 0
else
    exit 1
fi
