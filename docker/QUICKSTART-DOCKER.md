# Docker PBS Client - Quick Start

## One-Command Deploy (Any Platform)

```bash
chmod +x deploy.sh
./deploy.sh
```

Answer the prompts and you're done!

## Manual Deploy

### 1. Build Image

```bash
chmod +x build.sh
./build.sh
```

### 2. Create `.env` File

```bash
cat > .env << 'EOF'
PBS_REPOSITORY=backup@pbs!token@192.168.1.181:8007:backups
PBS_PASSWORD=your-token-secret-here
BACKUP_SCHEDULE=0 2 * * *
HOSTNAME=my-laptop
EOF
```

### 3. Start Container

```bash
# Linux
docker-compose -f docker-compose-linux.yml up -d

# Windows
docker-compose -f docker-compose-windows.yml up -d

# macOS
docker-compose -f docker-compose-macos.yml up -d
```

## Verify It's Working

```bash
# Check container is running
docker ps

# View logs
docker logs pbs-backup-client

# Check last backup status
docker exec pbs-backup-client cat /logs/status.json | jq

# Trigger manual backup
docker exec pbs-backup-client /usr/local/bin/pbs-backup
```

## Common Commands

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# View logs
docker-compose logs -f

# Restart
docker-compose restart

# Update image
docker-compose pull
docker-compose up -d

# Shell access
docker exec -it pbs-backup-client /bin/bash
```

## Backup Your Encryption Key!

**CRITICAL - Do this immediately:**

```bash
# Copy encryption key
docker cp pbs-backup-client:/config/encryption-key.json ./

# View paper backup
docker exec pbs-backup-client cat /config/encryption-key-paper.txt
```

Store these files securely. Without them, you cannot restore your backups!

## Platform-Specific Setup

### Windows

1. Install Docker Desktop
2. Share C:\ drive with Docker (Settings → Resources → File Sharing)
3. Run: `docker-compose -f docker-compose-windows.yml up -d`

### macOS

1. Install Docker Desktop
2. Grant Full Disk Access:
   - System Preferences → Privacy & Security → Full Disk Access
   - Add Docker.app
3. Run: `docker-compose -f docker-compose-macos.yml up -d`

### Linux

1. Install Docker Engine
2. Run: `docker-compose -f docker-compose-linux.yml up -d`

## Troubleshooting

**Container won't start:**
```bash
docker-compose logs
docker-compose config  # Validate config
```

**Can't connect to PBS:**
```bash
docker exec pbs-backup-client ping 192.168.1.181
docker exec pbs-backup-client proxmox-backup-client snapshot list
```

**Permission denied (Windows/Mac):**
- Windows: Share drive with Docker in settings
- Mac: Grant Full Disk Access to Docker

**Backup fails:**
```bash
# View detailed logs
docker exec pbs-backup-client cat /logs/last-backup.log
```

## What Gets Backed Up?

### Linux
- Default: Entire root filesystem (`/`)
- Excludes: `/tmp`, `/proc`, `/sys`, `/dev`, `/run`

### Windows
- Default: `C:\` drive
- Excludes: Temp folders, system files, cache
- Can add D:\, E:\ by editing docker-compose.yml

### macOS
- Default: `/Users` and `/Applications`
- Excludes: Caches, logs, trash
- Can add other paths by editing docker-compose.yml

## API Access (Optional)

Enable API in docker-compose.yml:
```yaml
environment:
  ENABLE_API: "true"
```

Then access:
```bash
# Status
curl http://localhost:8080/status | jq

# Health check
curl http://localhost:8080/health

# Trigger backup
curl -X POST http://localhost:8080/backup

# View logs
curl http://localhost:8080/logs | jq
```

## Customization

Edit `docker-compose-*.yml` to customize:

```yaml
environment:
  # Change schedule
  BACKUP_SCHEDULE: "0 3 * * *"  # 3 AM daily
  
  # Add more paths (Linux example)
  BACKUP_PATHS: "/host-data /host-data/home"
  
  # Add more exclusions
  EXCLUDE_PATTERNS: "/host-data/tmp /host-data/var/cache /host-data/Downloads"
  
  # Adjust retention
  KEEP_LAST: 5
  KEEP_DAILY: 14
  KEEP_WEEKLY: 8
  KEEP_MONTHLY: 12
```

Restart after changes:
```bash
docker-compose down
docker-compose up -d
```

## Integration with PBSClientTool

The Docker approach complements PBSClientTool perfectly:

**Scenario:** Manage 10 developer laptops (mix of Windows/Mac/Linux)

1. Deploy Docker container on each laptop
2. Use PBSClientTool to monitor all backups centrally
3. API endpoints enable remote management

## Full Documentation

See `README-DOCKER.md` for complete documentation including:
- All configuration options
- Platform-specific details
- Security best practices
- Performance tuning
- Advanced usage

## Need Help?

- Full docs: README-DOCKER.md
- PBS Forums: https://forum.proxmox.com
- Issues: [your-github-repo]/issues
