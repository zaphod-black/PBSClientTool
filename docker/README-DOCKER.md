# PBS Client Docker - Cross-Platform Backup Solution

Run Proxmox Backup Client on **Windows, macOS, and Linux** using Docker.

## Overview

This Docker container provides a cross-platform way to backup any machine to Proxmox Backup Server, regardless of operating system. The container runs PBS client in a Linux environment while backing up your host filesystem.

## Features

- **Cross-platform:** Works on Windows, macOS, and Linux
- **Two modes:** Daemon (continuous with scheduler) or one-shot backup
- **Automatic encryption:** Client-side encryption with key management
- **Health monitoring:** Built-in healthcheck and status API
- **Flexible scheduling:** Cron-based scheduling for automated backups
- **Easy management:** Docker Compose for simple deployment
- **Retention policies:** Configurable backup retention

## Quick Start

### 1. Prerequisites

- Docker and Docker Compose installed
- Proxmox Backup Server accessible on network
- PBS user credentials or API token

### 2. Choose Your Platform

```bash
# Linux
docker-compose -f docker-compose-linux.yml up -d

# Windows
docker-compose -f docker-compose-windows.yml up -d

# macOS
docker-compose -f docker-compose-macos.yml up -d
```

### 3. Configure

Edit the appropriate `docker-compose-*.yml` file:

```yaml
environment:
  PBS_REPOSITORY: "user@pbs!token@192.168.1.181:8007:backups"
  PBS_PASSWORD: "your-token-secret"
  BACKUP_SCHEDULE: "0 2 * * *"  # Daily at 2 AM
```

### 4. Start

```bash
docker-compose up -d
```

Done! Backups will run automatically on schedule.

## Building the Image

```bash
# Build
docker build -t pbsclient:latest .

# Or use build script
chmod +x build.sh
./build.sh
```

## Usage Modes

### Daemon Mode (Recommended)

Container runs continuously with cron scheduler:

```bash
docker run -d \
  --name pbs-client \
  -v /:/host-data:ro \
  -v pbs-config:/config \
  -v pbs-logs:/logs \
  -e PBS_REPOSITORY="user@pbs!token@192.168.1.181:8007:backups" \
  -e PBS_PASSWORD="secret" \
  -e MODE=daemon \
  -e BACKUP_SCHEDULE="0 2 * * *" \
  pbsclient:latest
```

### One-Shot Mode

Run backup once and exit:

```bash
docker run --rm \
  -v /:/host-data:ro \
  -v pbs-config:/config \
  -e PBS_REPOSITORY="user@pbs!token@192.168.1.181:8007:backups" \
  -e PBS_PASSWORD="secret" \
  pbsclient:latest backup
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PBS_REPOSITORY` | Yes | - | PBS repository URL |
| `PBS_PASSWORD` | Yes | - | PBS password or API token |
| `MODE` | No | `daemon` | Container mode: `daemon`, `backup`, `test` |
| `BACKUP_SCHEDULE` | No | `0 2 * * *` | Cron schedule for backups |
| `BACKUP_PATHS` | No | `/host-data` | Paths to backup (space-separated) |
| `EXCLUDE_PATTERNS` | No | See compose files | Exclusion patterns |
| `CONTAINER_HOSTNAME` | No | container hostname | Hostname for backups |
| `KEEP_LAST` | No | `3` | Keep last N backups |
| `KEEP_DAILY` | No | `7` | Keep daily backups for N days |
| `KEEP_WEEKLY` | No | `4` | Keep weekly backups for N weeks |
| `KEEP_MONTHLY` | No | `6` | Keep monthly backups for N months |
| `ENABLE_API` | No | `false` | Enable REST API server |
| `API_PORT` | No | `8080` | API server port |
| `TIMEZONE` | No | `UTC` | Container timezone |

### Volume Mounts

| Volume | Purpose | Required |
|--------|---------|----------|
| `/host-data` | Host filesystem to backup | Yes |
| `/config` | Persistent config and encryption keys | Yes |
| `/logs` | Backup logs | Recommended |

## Management Commands

### Check Status

```bash
# Via logs
docker-compose logs -f

# Via API (if enabled)
curl http://localhost:8080/status

# Check last backup
docker exec pbs-client cat /logs/status.json | jq
```

### Manual Backup

```bash
# Trigger backup manually
docker exec pbs-client /usr/local/bin/pbs-backup

# Or via API
curl -X POST http://localhost:8080/backup
```

### View Logs

```bash
# Follow live logs
docker-compose logs -f

# Last backup log
docker exec pbs-client cat /logs/last-backup.log

# Via API
curl http://localhost:8080/logs
```

### Test Connection

```bash
docker exec pbs-client proxmox-backup-client snapshot list
```

### Interactive Shell

```bash
docker exec -it pbs-client /bin/bash
```

## Platform-Specific Notes

### Windows

**File System Access:**
- Mounts `C:\` drive by default
- To backup additional drives, add volume mounts:
  ```yaml
  volumes:
    - C:\:/host-data:ro
    - D:\:/host-data-d:ro
  ```

**Exclusions:**
- System files (pagefile.sys, hiberfil.sys)
- Temp directories
- Windows Update cache
- User temp files

**Scheduling:**
- Container must run continuously
- Docker Desktop must start on boot

**Limitations:**
- No block device backups (file-level only)
- Cannot backup files locked by Windows
- Shadow Copy not available

### macOS

**File System Access:**
- Requires Full Disk Access for Docker
- Grant in: System Preferences → Privacy & Security → Full Disk Access
- May need to restart Docker Desktop after granting access

**Recommended Paths:**
- `/Users` - Home directories
- `/Applications` - Installed apps
- `/etc` - System configs
- `/Library/Application Support` - App data

**Exclusions:**
- Caches and logs in `~/Library`
- Xcode (very large)
- Time Machine backups
- Downloads folder

**Limitations:**
- No block device backups
- Some system files require SIP disabled (not recommended)

### Linux

**Full Access:**
- Can backup everything including block devices
- Mount with `:ro` for safety
- Use `--privileged` for block device access (if needed)

**Block Device Backups:**
To enable block device backups on Linux:
```yaml
devices:
  - /dev/sda:/dev/sda:ro
privileged: true
```

Then set:
```yaml
environment:
  BACKUP_TYPE: block
  BLOCK_DEVICE: /dev/sda
```

## API Endpoints

When `ENABLE_API=true`:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/status` | GET | Current backup status |
| `/health` | GET | Health check |
| `/backup` | POST | Trigger manual backup |
| `/logs` | GET | Recent backup logs |

Example:
```bash
# Check status
curl http://localhost:8080/status | jq

# Trigger backup
curl -X POST http://localhost:8080/backup

# Health check
curl http://localhost:8080/health
```

## Encryption Keys

**CRITICAL:** Your encryption key is stored in `/config/encryption-key.json`

### Backup Your Key

```bash
# Copy from volume
docker cp pbs-client:/config/encryption-key.json ./backup/

# View paper backup (QR code)
docker exec pbs-client cat /config/encryption-key-paper.txt
```

### Restore Key

```bash
# Copy key to volume
docker cp ./backup/encryption-key.json pbs-client:/config/

# Restart container
docker-compose restart
```

## Troubleshooting

### Connection Fails

```bash
# Test PBS connectivity
docker exec pbs-client bash -c "export PBS_REPOSITORY='...' PBS_PASSWORD='...' && proxmox-backup-client snapshot list"

# Check network
docker exec pbs-client ping 192.168.1.181

# Check firewall rules
```

### Permission Denied

```bash
# Linux: Ensure volume mounts are readable
# Windows: Grant Docker access to drives
# macOS: Grant Full Disk Access
```

### Container Won't Start

```bash
# Check logs
docker-compose logs

# Validate environment variables
docker-compose config

# Check disk space
docker system df
```

### Backup Fails

```bash
# Check last backup log
docker exec pbs-client cat /logs/last-backup.log

# Verify paths exist
docker exec pbs-client ls -la /host-data

# Check exclusion patterns
```

### High Memory Usage

```bash
# Limit container memory
docker run --memory=4g ...

# Or in docker-compose:
deploy:
  resources:
    limits:
      memory: 4G
```

## Performance Considerations

### Network Bandwidth

For remote backups over WAN:
```yaml
environment:
  RATE_LIMIT: 10485760  # 10 MB/s
```

### Storage Requirements

First backup reads all data. Subsequent backups only transfer changed files.

Example: 500GB system with 200GB used
- First backup: ~200GB transferred
- Daily backups: ~1-5GB transferred (only changes)
- Monthly storage: ~10-30GB (with deduplication)

### Docker Desktop Limitations

Docker Desktop (Windows/Mac) has performance overhead:
- File I/O slower than native
- First backup will be slower
- Consider increasing Docker resources

## Integration with PBSClientTool

This Docker solution complements PBSClientTool:

```bash
# Use PBSClientTool to manage Docker containers
pbsclienttool add-target \
  --name laptop1 \
  --type docker \
  --host laptop1.local \
  --repository "..."
```

## Security Best Practices

1. **Use API Tokens** instead of passwords
2. **Enable encryption** (automatic by default)
3. **Backup encryption keys** to secure location
4. **Mount filesystems read-only** (`:ro`)
5. **Don't expose API port** to internet
6. **Use secrets management** for credentials:

```yaml
secrets:
  pbs_password:
    external: true

environment:
  PBS_PASSWORD_FILE: /run/secrets/pbs_password
```

## Limitations

### What This CANNOT Do

- **Windows/Mac block device backups** - File-level only
- **Shadow Copy/VSS on Windows** - Not available
- **Live database backups** - Stop database first or use dumps
- **Backup locked files** - Some Windows files may be skipped
- **APFS snapshots on Mac** - Not accessible from Docker

### Workarounds

For databases:
```bash
# Pre-backup hook
docker exec pbs-client bash -c '
  mysqldump -u root -p password db > /host-data/backup/db.sql
'
```

For block device backups on Windows/Mac:
- Boot from Linux USB
- Run PBS client natively
- Backup unmounted disk

## Examples

### Backup Windows User Profile Only

```yaml
volumes:
  - C:\Users\YourName:/host-data:ro

environment:
  BACKUP_PATHS: "/host-data"
  EXCLUDE_PATTERNS: "/host-data/AppData/Local/Temp"
```

### Backup Multiple Mac Users

```yaml
volumes:
  - /Users:/host-data:ro

environment:
  BACKUP_PATHS: "/host-data"
  EXCLUDE_PATTERNS: "/host-data/*/Library/Caches /host-data/*/.Trash"
```

### Backup Linux Server with Multiple Mounts

```yaml
volumes:
  - /:/host-data:ro
  - /home:/host-home:ro
  - /var/www:/host-www:ro

environment:
  BACKUP_PATHS: "/host-data /host-home /host-www"
```

## Contributing

Issues and pull requests welcome at [your-repo-url]

## License

MIT License

## Credits

- Proxmox team for PBS
- Docker PBS client by [your-name]
