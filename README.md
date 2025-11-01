# PBSClientInstaller

Interactive bash script that automatically installs and configures Proxmox Backup Client on Ubuntu, Debian, and Arch Linux systems.

## Features

- **Auto-detects Linux distribution** (Ubuntu 20.04/22.04/24.04, Debian 10/11/12, Arch Linux)
- **Installs correct PBS client version** for your system
- **Interactive configuration** via console prompts
- **Automatic encryption key generation** with paper backup
- **Systemd service and timer** for automated backups
- **Configurable retention policies** (daily, weekly, monthly)
- **Connection testing** before finalizing setup
- **Immediate backup option** after installation

## Prerequisites

### All Systems
- Root/sudo access
- Active internet connection
- Proxmox Backup Server accessible on network

### Arch Linux Specifically
- `yay` AUR helper must be installed
- Install yay first: https://github.com/Jguer/yay

### Before Running
- Have your PBS server details ready:
  - Server IP/hostname (e.g., 192.168.1.181)
  - Port (default: 8007)
  - Datastore name
  - Authentication credentials (username/password or API token)

## Installation

### Clone the repository

```bash
git clone https://github.com/zaphod-black/PBSClientInstaller
cd PBSClientInstaller
chmod +x pbs-client-installer.sh
```

### Run with sudo

```bash
sudo ./pbs-client-installer.sh
```

### Reconfiguration

If PBS client is already installed, the script will detect this and offer you options:

**With existing configuration:**
- **Reconfigure connection only** - Quick update of PBS server IP/credentials only
- **Full reconfiguration** - Redo all settings (paths, schedules, retention, etc.)
- **Reinstall PBS client and reconfigure** - Complete reinstall
- **Exit without changes**

**Without existing configuration:**
- **Configure PBS client** - Set up for the first time
- **Reinstall and configure** - Fresh installation
- **Exit without changes**

The connection-only reconfiguration is perfect for:
- Switching to a different backup server
- Updating expired API tokens
- Changing authentication methods
- Updating datastore names

All backup settings (paths, schedules, retention policies) are preserved.

## Usage Example

The script will interactively prompt you for:

1. **PBS Server Configuration**
   - Server IP/hostname
   - Port (default: 8007)
   - Datastore name

2. **Authentication**
   - Username + Password OR
   - API Token (recommended for automation)

3. **Backup Configuration**
   - Paths to backup (e.g., `/`, `/home`)
   - Exclusion patterns (e.g., `/tmp`, `/var/cache`)

4. **Schedule**
   - Hourly, Daily, Weekly, or Custom schedule
   - Specific time for backups

5. **Retention Policy**
   - Number of last backups to keep
   - Daily/weekly/monthly retention

6. **Encryption**
   - Enable/disable client-side encryption

## Example Session

```
╔════════════════════════════════════════╗
║  Proxmox Backup Client Installer      ║
║  Version: 1.0.0                        ║
╚════════════════════════════════════════╝

[INFO] Detected: Ubuntu 24.04 LTS
[INFO] Installing Proxmox Backup Client on Ubuntu 24.04...
[INFO] PBS client installed successfully

======================================
  PBS Client Configuration
======================================

Enter PBS server IP/hostname [192.168.1.181]: 
Enter PBS server port [8007]: 
Enter datastore name [backups]: 

Authentication Method:
  1) Username + Password
  2) API Token (recommended for automation)
Select authentication method [1/2] [2]: 

Enter username [backup]: 
Enter realm [pbs]: 
Enter token name [backup-token]: 
Enter token secret: 

Backup Configuration:
Enter paths to backup (space-separated) [/]: /
Enter exclusion patterns (space-separated) [/tmp /var/tmp /var/cache /proc /sys /dev /run]: 

Backup Schedule:
  1) Hourly
  2) Daily (recommended)
  3) Weekly
  4) Custom
Select schedule type [1/2/3/4] [2]: 2
Enter hour for daily backup (0-23) [2]: 3

Retention Policy:
Keep last N backups [3]: 3
Keep daily backups for N days [7]: 7
Keep weekly backups for N weeks [4]: 4
Keep monthly backups for N months [6]: 12

Enable encryption? (yes/no) [yes]: yes

[INFO] Encryption key created successfully
[WARN] IMPORTANT: Encryption key paper backup saved to: /root/pbs-encryption-key-20251101.txt
[WARN] Print this file and store it securely. Lost keys = permanent data loss!

[INFO] Testing connection to PBS server...
[INFO] Connection test successful!

[INFO] Creating systemd service and timer...
[INFO] Systemd service and timer created successfully

Do you want to run a backup now? (yes/no) [no]: yes
[INFO] Starting immediate backup...
```

## Post-Installation

### Check Status

```bash
# Check timer status
sudo systemctl status pbs-backup.timer

# Check last backup run
sudo systemctl status pbs-backup.service

# View backup logs
sudo journalctl -u pbs-backup.service

# Follow logs in real-time
sudo journalctl -fu pbs-backup.service
```

### Manual Backup

```bash
# Run backup immediately
sudo systemctl start pbs-backup.service

# List all backups
sudo -E proxmox-backup-client snapshot list
```

### Configuration Files

- `/etc/proxmox-backup-client/config` - Main configuration
- `/etc/proxmox-backup-client/backup.sh` - Backup script
- `/root/.config/proxmox-backup/encryption-key.json` - Encryption key
- `/etc/systemd/system/pbs-backup.service` - Systemd service
- `/etc/systemd/system/pbs-backup.timer` - Systemd timer

### Modify Configuration

Edit the config file and restart the timer:

```bash
sudo nano /etc/proxmox-backup-client/config
sudo systemctl daemon-reload
sudo systemctl restart pbs-backup.timer
```

### Disable Automatic Backups

```bash
sudo systemctl disable pbs-backup.timer
sudo systemctl stop pbs-backup.timer
```

### Uninstall

Use the provided uninstaller:

```bash
sudo ./pbs-client-uninstaller.sh
```

## Backup Encryption Key

**CRITICAL**: Your encryption key is your only way to restore data. If you lose it, your backups are permanently unrecoverable.

### Key Locations
- Primary: `/root/.config/proxmox-backup/encryption-key.json`
- Paper backup: `/root/pbs-encryption-key-YYYYMMDD.txt`

### Best Practices
1. Print the paper backup immediately
2. Store printed copy in safe location (fireproof safe, safety deposit box)
3. Copy `encryption-key.json` to password manager
4. Never store key on the same system being backed up
5. Test key restoration regularly

### Restore Encryption Key

To restore backups on a new system:

```bash
# Copy your saved encryption-key.json
sudo mkdir -p /root/.config/proxmox-backup
sudo cp /path/to/saved/encryption-key.json /root/.config/proxmox-backup/

# Or recreate from paper backup QR code
# (scan QR code and save to file)
```

## Troubleshooting

### Connection Test Script

If you encounter connection issues, use the included diagnostic script:

```bash
./test-connection.sh <server> <port> <datastore> <username> <realm> <password-or-token>
```

**Examples:**

With username/password:
```bash
./test-connection.sh 192.168.1.181 8007 DEAD-BACKUP root pam mypassword
```

With API token:
```bash
./test-connection.sh 192.168.1.181 8007 DEAD-BACKUP root pam backup-token token-secret-here
```

The script will:
- Test server reachability
- Handle SSL certificate fingerprint acceptance
- Test authentication
- Verify datastore access
- Provide detailed error messages

### Connection Test Fails

The installer tests the connection with a 3-step process:

**Step 1 - Server Reachability (5s timeout):**
- PBS server is unreachable (check IP/hostname)
- Firewall blocking port (default: 8007)
- Network connectivity issues

**Step 2 - Authentication (15s timeout):**
- Invalid credentials (username/password/token)
- SSL certificate fingerprint issues (automatically handled)
- API token format errors

**Step 3 - Datastore Access:**
- Datastore does not exist on server
- User lacks permissions for the datastore

**Quick checks:**
```bash
# Test server reachability
ping 192.168.1.181
curl -k https://192.168.1.181:8007

# Verify credentials in PBS web interface
# Check datastore name matches exactly
```

**SSL Certificate Fingerprints:**

The installer automatically accepts SSL fingerprints during setup. If you need to manually accept a fingerprint:

```bash
export PBS_REPOSITORY="root@pam@192.168.1.181:8007:DEAD-BACKUP"
export PBS_PASSWORD="your-password"
proxmox-backup-client login
# Answer 'y' when prompted to accept the fingerprint
```

### Installation Fails on Ubuntu 22.04

You may need to manually install `libssl1.1`:
```bash
wget http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb
```

### Arch: "libfuse3.so.3 not found"

Rebuild after fuse3 updates:
```bash
yay -S proxmox-backup-client-bin --rebuild
```

### Backups Not Running

Check timer and service status:
```bash
sudo systemctl list-timers pbs-backup.timer
sudo systemctl status pbs-backup.service
sudo journalctl -u pbs-backup.service -n 50
```

### "Skip mount point" Messages

This is normal. The script excludes separate mount points by default. To include specific mount points, edit `/etc/proxmox-backup-client/backup.sh` and add `--include-dev` flags.

## Advanced Usage

### Custom Backup Script

Modify `/etc/proxmox-backup-client/backup.sh` for advanced scenarios:

```bash
# Add specific mount points
--include-dev /boot/efi

# Use data change detection mode
--change-detection-mode=data

# Add rate limiting (10 MB/s)
--rate-limit 10485760

# Verbose output
--verbose
```

### Multiple Backup Jobs

Create additional services for different schedules:

```bash
# Copy and modify service/timer files
sudo cp /etc/systemd/system/pbs-backup.service /etc/systemd/system/pbs-backup-hourly.service
sudo cp /etc/systemd/system/pbs-backup.timer /etc/systemd/system/pbs-backup-hourly.timer

# Edit timer OnCalendar setting
sudo nano /etc/systemd/system/pbs-backup-hourly.timer

sudo systemctl daemon-reload
sudo systemctl enable --now pbs-backup-hourly.timer
```

## Security Considerations

- Configuration file contains credentials - protected with mode 600
- Encryption key is root-only accessible
- No passwords logged or displayed in output
- All communication uses TLS encryption
- Consider using API tokens instead of passwords for automation

## Supported Distributions

| Distribution | Versions | Notes |
|-------------|----------|-------|
| Ubuntu | 20.04, 22.04, 24.04 | LTS versions only |
| Debian | 10 (Buster), 11 (Bullseye), 12 (Bookworm) | Stable releases |
| Arch Linux | Rolling | Requires `yay` AUR helper |

## Contributing

Issues and pull requests welcome at [your-repo-url]

## License

MIT License - see LICENSE file

## Credits

- Proxmox team for PBS client
- Script by Cade

## Support

For PBS client issues: https://forum.proxmox.com
For script issues: [your-repo-url]/issues
