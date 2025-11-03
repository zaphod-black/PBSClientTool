# PBS Client Docker Solution - Complete Package

This is a **cross-platform Proxmox Backup Client** running in Docker, enabling backups from **Windows, macOS, and Linux** to your Proxmox Backup Server.

## What's Included

### Core Docker Components
- **Dockerfile** - Multi-stage build with PBS client
- **docker-compose-linux.yml** - Linux deployment config
- **docker-compose-windows.yml** - Windows deployment config
- **docker-compose-macos.yml** - macOS deployment config

### Scripts (in `scripts/` directory)
- **entrypoint.sh** - Main container entrypoint, handles modes
- **backup.sh** - Actual backup logic that runs inside container
- **healthcheck.sh** - Container health monitoring
- **api-server.sh** - Optional REST API for management

### Deployment Tools
- **build.sh** - Builds the Docker image
- **deploy.sh** - Interactive deployment script (auto-detects platform)

### Documentation
- **README-DOCKER.md** - Complete documentation (500+ lines)
- **QUICKSTART-DOCKER.md** - Quick start guide

### Original Native Installers (Bonus)
- **pbs-client-installer.sh** - Interactive native installer
- **pbs-client-uninstaller.sh** - Clean removal script
- **README.md** - Native installer documentation
- **BACKUP-TYPES-GUIDE.md** - Guide for file vs block backups

## How It Works

```
┌─────────────────────────────────────────┐
│         Host System                     │
│    (Windows/Mac/Linux)                  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │  Docker Container (Debian)       │  │
│  │                                  │  │
│  │  ┌────────────────────────────┐ │  │
│  │  │ PBS Client (Linux binary)  │ │  │
│  │  │                            │ │  │
│  │  │ - Connects to PBS Server   │ │  │
│  │  │ - Reads host filesystem    │ │  │
│  │  │ - Encrypts & uploads       │ │  │
│  │  └────────────────────────────┘ │  │
│  │                                  │  │
│  │  Host FS mounted at /host-data   │  │
│  │  ↓                               │  │
│  │  C:\ or / or /Users             │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
           │
           │ TLS encrypted
           ↓
┌─────────────────────────────────────────┐
│    Proxmox Backup Server                │
│    192.168.1.181:8007                   │
│                                         │
│  - Receives encrypted chunks            │
│  - Deduplicates data                    │
│  - Stores backups                       │
└─────────────────────────────────────────┘
```

## Two Operating Modes

### 1. Daemon Mode (Recommended)
Container runs continuously with internal cron scheduler:
- Automatic scheduled backups
- Health monitoring
- Optional REST API
- Persistent logging

**Use case:** Laptops and workstations that need regular automated backups

### 2. One-Shot Mode
Container runs backup once and exits:
- Triggered manually or by host scheduler
- Minimal resource usage when not running
- Good for CI/CD or manual backups

**Use case:** Servers with existing orchestration, testing, manual backups

## Key Features

### Cross-Platform
- **Linux:** Full support including block devices
- **Windows:** File-level backups of C:\ (or other drives)
- **macOS:** File-level backups with proper permission handling

### Docker Benefits
1. **Consistent environment** - PBS client runs in same Linux environment everywhere
2. **Easy updates** - Pull new image, restart container
3. **Isolation** - Container can't affect host system
4. **Portability** - Same container on all platforms

### Smart Defaults
- Auto-detects and excludes temp directories
- Platform-specific exclusion patterns
- Automatic encryption key generation
- Metadata change detection for fast incrementals

### Management
- REST API for remote control (optional)
- Health checks for monitoring
- Structured JSON logs
- docker-compose for easy deployment

## Quick Start Examples

### Linux Laptop
```bash
# Build
./build.sh

# Deploy (interactive)
./deploy.sh

# Or manually
docker-compose -f docker-compose-linux.yml up -d
```

### Windows Developer Machine
```bash
# Ensure Docker Desktop is running
# Share C:\ drive in Docker settings

./deploy.sh
# Or
docker-compose -f docker-compose-windows.yml up -d
```

### macOS Laptop
```bash
# Grant Full Disk Access to Docker first
./deploy.sh
# Or
docker-compose -f docker-compose-macos.yml up -d
```

## Integration with PBSClientTool

This Docker solution is **perfect for PBSClientTool** because:

1. **Uniform interface** - Same API/commands across all platforms
2. **Remote management** - REST API enables central control
3. **Easy deployment** - Single image works everywhere
4. **Standardized monitoring** - Same health checks on all systems

### Suggested Integration

```bash
# PBSClientTool could deploy Docker containers
pbsclienttool deploy laptop1 --platform windows --docker

# Monitor via API
pbsclienttool status laptop1
# Queries: http://laptop1:8080/status

# Trigger backup remotely
pbsclienttool backup laptop1 --now
# POSTs to: http://laptop1:8080/backup
```

## Limitations

### What Works
✅ File-level backups on all platforms
✅ Automatic encryption
✅ Incremental backups with deduplication
✅ Scheduled backups via cron
✅ Retention policies
✅ Remote management via API

### What Doesn't Work
❌ Block device backups on Windows/Mac (Docker limitation)
❌ Windows Shadow Copy / VSS
❌ macOS APFS snapshots
❌ Backing up files currently locked/open on Windows
❌ Accessing system files requiring SIP disabled on Mac

### Workarounds
- **Block devices:** Boot from Linux USB, run PBS client natively
- **Locked files:** Close applications before backup, or schedule during off-hours
- **Large files:** Use exclusions for `node_modules`, `.git`, etc.

## Storage Requirements

Example: 500GB laptop with 200GB used

**Docker overhead:**
- Image size: ~500MB
- Container overhead: ~50MB
- Logs: ~100MB/month

**PBS storage (on server):**
- First backup: ~200GB
- Daily backups: ~1-5GB each (only changes)
- With deduplication: Typically 5-10x reduction
- Monthly: ~50-100GB actual storage (with dedup)

## Performance Considerations

### First Backup
- Reads entire filesystem
- Can take hours for large disks
- Network bandwidth is bottleneck
- Consider running on-site for first backup

### Subsequent Backups
- Metadata change detection (fast)
- Only changed files transferred
- Typically 1-5GB transferred
- Usually completes in 10-30 minutes

### Docker Overhead
- **Linux:** Minimal (<5% performance impact)
- **Windows/Mac:** Docker Desktop adds overhead (~20-30% slower)
- **Network:** No impact, direct connection

## Security

### Built-in Security
1. **Client-side encryption** (AES-256-GCM)
2. **TLS transport** to PBS server
3. **Read-only filesystem mounts** (`:ro`)
4. **Isolated container** environment

### Best Practices
1. Use API tokens instead of passwords
2. Backup encryption keys to secure location
3. Don't expose API port to internet
4. Use Docker secrets for credentials
5. Regular key rotation

### Credentials
Stored in:
- Environment variables (docker-compose)
- `.env` file (chmod 600)
- Or Docker secrets (production)

Never committed to git (in `.dockerignore`).

## Comparison: Docker vs Native Install

| Feature | Docker | Native Install |
|---------|--------|----------------|
| Windows support | ✅ Yes | ❌ No |
| macOS support | ✅ Yes | ❌ No |
| Linux support | ✅ Yes | ✅ Yes |
| Block devices (Linux) | ⚠️ Possible | ✅ Yes |
| Block devices (Win/Mac) | ❌ No | ❌ No |
| Ease of deployment | ✅ Very easy | ⚠️ Moderate |
| Updates | ✅ Pull image | ⚠️ Re-run installer |
| Resource usage | ⚠️ Higher | ✅ Lower |
| Portability | ✅ Excellent | ❌ Platform-specific |
| Performance | ⚠️ Good | ✅ Excellent |

**Recommendation:**
- **Docker:** Windows, macOS, mixed environment, ease of management
- **Native:** Linux servers, block device backups needed, maximum performance

## Use Cases

### Perfect For Docker

1. **Mixed OS Team**
   - 5 Windows laptops
   - 3 MacBooks
   - 2 Linux workstations
   - → Single deployment method for all

2. **Developer Workstations**
   - Already using Docker
   - Need easy setup
   - Want central management

3. **Remote Workers**
   - Various operating systems
   - Need automated backups
   - Central IT management

4. **Testing/Development**
   - Quick setup/teardown
   - Multiple test environments
   - Consistent results

### Better Native

1. **Linux Production Servers**
   - Need maximum performance
   - Block device backups required
   - Direct hardware access needed

2. **Infrastructure Systems**
   - Minimal dependencies preferred
   - Docker not already deployed
   - Tight resource constraints

## Monitoring & Alerts

### Health Checks
Container includes healthcheck that monitors:
- Cron daemon running (daemon mode)
- Last backup success/failure
- Backup age (alerts if >48 hours old)
- PBS server connectivity

### Status API
```bash
# Check status
curl http://localhost:8080/status
{
  "last_backup": "2025-11-03T02:00:00Z",
  "hostname": "laptop1",
  "success": true,
  "paths": ["/host-data"]
}

# Health
curl http://localhost:8080/health
{"status":"healthy"}
```

### Integration Ideas
- Prometheus metrics exporter
- Grafana dashboard
- Email alerts on failure
- Slack/Discord notifications

## Roadmap / Future Ideas

### Possible Enhancements
1. **GUI Management** - Web interface for configuration
2. **Windows VSS Integration** - Shadow copy support
3. **Auto-discovery** - Detect and backup databases automatically
4. **Pre/post hooks** - Custom scripts before/after backup
5. **Bandwidth scheduling** - Different limits by time of day
6. **Multi-destination** - Backup to multiple PBS servers
7. **Backup verification** - Automated restore testing

### Community Contributions Welcome
- Platform testing (various Windows/Mac versions)
- Performance optimization
- Additional features
- Documentation improvements

## Support & Resources

### Documentation
- **README-DOCKER.md** - Complete reference
- **QUICKSTART-DOCKER.md** - Quick start guide
- **BACKUP-TYPES-GUIDE.md** - Backup strategy guide

### Community
- PBS Forums: https://forum.proxmox.com
- Your repo: [github-link]
- Issues/PRs welcome

### Related Projects
- **PBSClientTool** - Your CLI tool for PBS client management
- **proxmox-backup-client** - Official Proxmox client
- **Proxmox Backup Server** - Server component

## Getting Started Checklist

- [ ] Have PBS server running and accessible
- [ ] Create PBS user and API token
- [ ] Install Docker (Desktop on Win/Mac, Engine on Linux)
- [ ] Download/clone this repository
- [ ] Run `./build.sh` to build image
- [ ] Run `./deploy.sh` for guided setup
- [ ] **Backup encryption key immediately**
- [ ] Verify first backup completes
- [ ] Test restore of a few files
- [ ] Set up monitoring (optional)

## Conclusion

This Docker-based PBS client solution provides a **universal backup solution** that works across all major operating systems. Combined with Proxmox Backup Server and your PBSClientTool for management, you have a complete **open-source, self-hosted backup infrastructure** comparable to commercial solutions like CrashPlan or Backblaze, but with:

- Full control over your data
- No recurring costs
- Better deduplication
- Native Proxmox integration
- Support for hybrid environments

Perfect for MSPs, IT teams, homelabs, or anyone managing multiple systems across different platforms.
