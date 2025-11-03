# PBSClientTool

Interactive tool for installing and managing Proxmox Backup Client on **all platforms**: Linux (native), Windows, and macOS (Docker).

<img width="346" height="714" alt="screenshot-2025-11-02_18-48-02" src="https://github.com/user-attachments/assets/6796f247-ef4f-488c-8443-d232dc70b356" />

## Features

- **Cross-platform support** - Native Linux + Docker for Windows/Mac
- **Multi-target backups** - Backup to multiple PBS servers for redundancy
- **Auto-detection** - Automatically detects your Linux distribution
- **File & block device backups** - Supports .pxar (files) and .img (full disk) backups
- **Interactive setup** - Guided configuration with connection testing
- **Flexible scheduling** - Separate schedules for file and disk backups
- **System-wide install** - Run from anywhere with `PBSClientTool` command

## Quick Start

```bash
# Clone and install
git clone https://github.com/zaphod-black/PBSClientTool.git
cd PBSClientTool
sudo ./pbs-client-installer.sh --install

# Run from anywhere
sudo PBSClientTool
```

## Prerequisites

### On Your System
- Root/sudo access
- Internet connection
- Supported OS: Ubuntu 20.04+, Debian 10+, Arch Linux
- **Arch only:** Install `yay` first ([instructions](https://github.com/Jguer/yay))

### On Proxmox Backup Server

Before running the installer, set up an API token with backup permissions:

**1. Create API Token:**
1. Login to PBS web interface (e.g., `https://192.168.1.181:8007`)
2. Go to **Configuration → Access Control → API Tokens**
3. Click **Add**
4. Configure:
   - User: `root@pam`
   - Token ID: `backupAutomations` (or any name)
   - **Privilege Separation:** Leave unchecked
5. **Copy the secret immediately** (shown only once!)

**2. Grant Permissions:**
1. Go to **Configuration → Access Control → Permissions**
2. Click **Add → User Permission**
3. Configure:
   - Path: `/datastore/YOUR-DATASTORE-NAME`
   - User: `root@pam!backupAutomations`
   - Role: `DatastoreBackup`
4. Click **Add**

## Usage

### Installation Wizard

Run the tool and follow the prompts:

```bash
sudo PBSClientTool
```

You'll be asked for:
1. **PBS Server:** IP/hostname and port
2. **Authentication:** API token (recommended) or password
3. **Backup Type:**
   - File-level only (fast, selective restore)
   - Block device only (full disk image, bootable as VM)
   - **Both (recommended)** - Files daily + disk weekly
4. **Schedule:** When to run backups
5. **Retention:** How long to keep backups
6. **Encryption:** Optional (recommended for sensitive data)

The installer will test your connection and create automated backup services.

### Multi-Target Management

After installation, you can manage multiple backup targets:

**Main Menu Options:**
1. **List all backup targets** - View all configured servers
2. **Add new backup target** - Configure additional PBS server
3. **Edit existing target** - Update connection/settings
4. **Delete target** - Remove a backup destination
5. **Run backup now** - Test or run immediate backup
6. **Reinstall PBS client** - Reinstall the backup software
7. **Exit**

### Running Backups

**Scheduled (automatic):**
```bash
# Check timer status
sudo systemctl status pbs-backup-default.timer

# View next scheduled run
sudo systemctl list-timers pbs-backup-*
```

**Manual (on-demand):**
```bash
# Via menu (recommended - shows live progress)
sudo PBSClientTool
# Select option 5 (Run backup now)

# Via systemd
sudo systemctl start pbs-backup-default-manual.service

# Direct script execution
sudo /etc/proxmox-backup-client/backup-default.sh
```

### Viewing Logs

```bash
# View recent backup logs
sudo journalctl -u pbs-backup-default.service -n 50

# Follow logs in real-time
sudo journalctl -fu pbs-backup-default.service

# List all backups on server
sudo -E proxmox-backup-client snapshot list
```

## Command-Line Options

```bash
sudo PBSClientTool              # Interactive menu
sudo PBSClientTool --help       # Show help
sudo PBSClientTool --version    # Show version
sudo PBSClientTool --install    # Install to system
sudo PBSClientTool --uninstall  # Remove from system
```

## Configuration Files

**Multi-target setup:**
- `/etc/proxmox-backup-client/targets/TARGET.conf` - Target configurations
- `/etc/proxmox-backup-client/backup-TARGET.sh` - Backup scripts
- `/etc/systemd/system/pbs-backup-TARGET.{service,timer}` - Systemd units

**Encryption key:**
- `/root/.config/proxmox-backup/encryption-key.json` - Main key
- `/root/pbs-encryption-key-*.txt` - Paper backup (print and secure!)

## Backup Types Explained

### File-Level (.pxar)
- **Fast** - Usually completes in 2-5 minutes
- **Selective** - Restore individual files/folders
- **Efficient** - Deduplication and compression
- **Best for:** Daily backups, quick recovery

### Block Device (.img)
- **Slow** - Can take 20-30+ minutes
- **Complete** - Entire disk image
- **Bootable** - Can restore as VM on Proxmox
- **Best for:** Weekly backups, disaster recovery

### Hybrid (Both)
- **Recommended** - Best of both worlds
- Files backup daily (fast, efficient)
- Disk image weekly (complete system backup)
- Configure separate schedules for each

## Encryption Key - Important!

⚠️ **Your encryption key is the ONLY way to restore encrypted backups!**

**If you lose the key, your backups are permanently unrecoverable.**

**Best practices:**
1. Print the paper backup immediately (`/root/pbs-encryption-key-*.txt`)
2. Store printed copy in safe location (fireproof safe, safety deposit box)
3. Copy `encryption-key.json` to password manager
4. NEVER store key on the same system being backed up
5. Test key restoration regularly

## Updating PBSClientTool

```bash
cd ~/dev/PBSClientTool
git pull
sudo ./pbs-client-installer.sh --install
# Confirm overwrite: yes
```

Your backup targets and configurations are preserved during updates.

## Uninstallation

**Remove command only (keeps backups and configs):**
```bash
sudo PBSClientTool --uninstall
```

**Complete removal (removes everything):**
```bash
cd ~/dev/PBSClientTool
sudo ./uninstaller.sh
```

## Docker Solution (Windows/Mac) - 🚧 IN DEVELOPMENT

> ⚠️ **Note:** The Docker solution is currently in active development. The native Linux installer above is the **stable, production-ready version**. Use Docker for cross-platform testing or if you need Windows/Mac support.

Want to backup Windows or macOS systems? Use the Docker-based solution:

### Quick Start

**1. Build the image:**
```bash
cd docker
./build.sh
```

**2. Run the container:**
```bash
docker run -d \
  --name pbs-backup \
  -p 8080:8080 \
  -v /path/to/backup:/host-data:ro \
  -v pbs-config:/config \
  -v pbs-logs:/logs \
  -e MODE=daemon \
  -e ENABLE_API=true \
  pbsclient:latest
```

Replace `/path/to/backup` with your data directory:
- **Home directory**: `-v /home/username:/host-data:ro`
- **Entire system**: `-v /:/host-data:ro`
- **Specific folder**: `-v /data:/host-data:ro`

**3. Configure via web UI:**
- Open http://localhost:8080
- Click **⚙ Settings**
- Enter your PBS server details
- Click **💾 Save Configuration**
- Click **▶ Run Backup Now** to test

### What It Provides

- **Cross-platform** - Works on Windows, macOS, and Linux
- **Web Dashboard** - Real-time monitoring with retro terminal UI
- **Configuration UI** - Set up PBS backups from your browser
- **REST API** - Remote management and monitoring
- **File-level backups** - Daily automated backups
- **Easy deployment** - Single container, simple configuration

**Web Dashboard Features:**
- Settings page for PBS configuration
- Live backup status and progress
- System health monitoring
- Backup history and logs
- Manual backup trigger
- Retro blue/purple neon aesthetic

See [docker/README-DOCKER.md](docker/README-DOCKER.md) for complete documentation.

**Platform Support Matrix:**

| Feature | Native Linux | Docker (Win/Mac) |
|---------|-------------|------------------|
| File backups | ✅ Yes | ✅ Yes |
| Block device backups | ✅ Yes | ❌ No |
| Performance | ✅ Best | ⚠️ Good |
| Setup complexity | Medium | Easy |

## Troubleshooting

Having issues? See the [Troubleshooting Guide](TROUBLESHOOTING.md) for:
- Connection test failures
- Permission errors
- Installation issues
- Backup problems
- Configuration issues
- And more...

## Supported Distributions

| OS | Versions | Notes |
|----|----------|-------|
| Ubuntu | 20.04, 22.04, 24.04 | LTS only |
| Debian | 10, 11, 12 | Stable |
| Arch Linux | Rolling | Requires `yay` |

## Getting Help

- **Script issues:** [GitHub Issues](https://github.com/zaphod-black/PBSClientTool/issues)
- **PBS questions:** [Proxmox Forum](https://forum.proxmox.com)
- **PBS docs:** [Official Documentation](https://pbs.proxmox.com/docs/)

## Contributing

Issues and pull requests welcome!

## License

MIT License

## Credits

Created by Cade - Built on Proxmox Backup Client
