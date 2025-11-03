#!/bin/bash
# Healthcheck script for Docker container

# Check if cron is running (daemon mode)
if [ "$MODE" = "daemon" ]; then
    if ! pgrep -x "cron" > /dev/null; then
        echo "Cron is not running"
        exit 1
    fi
fi

# Check if last backup was successful (if any backups have run)
if [ -f /logs/status.json ]; then
    SUCCESS=$(jq -r '.success' /logs/status.json 2>/dev/null || echo "null")
    if [ "$SUCCESS" = "false" ]; then
        echo "Last backup failed"
        exit 1
    fi
    
    # Check if backup is too old (more than 48 hours)
    LAST_BACKUP=$(jq -r '.last_backup' /logs/status.json 2>/dev/null || echo "")
    if [ -n "$LAST_BACKUP" ]; then
        LAST_TIMESTAMP=$(date -d "$LAST_BACKUP" +%s 2>/dev/null || echo "0")
        CURRENT_TIMESTAMP=$(date +%s)
        AGE=$((CURRENT_TIMESTAMP - LAST_TIMESTAMP))
        
        # 48 hours = 172800 seconds
        if [ $AGE -gt 172800 ]; then
            echo "Last backup is too old (>48 hours)"
            exit 1
        fi
    fi
fi

# Check if PBS connection is working (quick test)
export PBS_REPOSITORY
export PBS_PASSWORD
if ! timeout 5 proxmox-backup-client snapshot list >/dev/null 2>&1; then
    echo "Cannot connect to PBS server"
    exit 1
fi

echo "Healthy"
exit 0
