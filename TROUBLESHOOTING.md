# Troubleshooting Guide

Common issues and solutions for PBSClientTool.

## Connection Issues

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

### Connection Test Failures

The installer tests connections with a 3-step process:

**Step 1 - Server Reachability (5s timeout):**
- PBS server is unreachable (check IP/hostname)
- Firewall blocking port (default: 8007)
- Network connectivity issues

**Quick checks:**
```bash
# Test server reachability
ping 192.168.1.181
curl -k https://192.168.1.181:8007
```

**Step 2 - Authentication (15s timeout):**
- Invalid credentials (username/password/token)
- SSL certificate fingerprint issues (automatically handled)
- API token format errors

**Quick checks:**
- Verify credentials in PBS web interface
- Ensure API token includes both username and token name: `root@pam!backupAutomations`
- Check for trailing spaces in input fields (script now trims automatically)

**Step 3 - Datastore Access:**
- Datastore does not exist on server
- User lacks permissions for the datastore

**Quick checks:**
- Verify datastore name matches exactly (case-sensitive)
- Check permissions in PBS: Configuration → Access Control → Permissions

### SSL Certificate Fingerprints

The installer automatically accepts SSL fingerprints during setup. If you need to manually accept:

```bash
export PBS_REPOSITORY="root@pam@192.168.1.181:8007:DEAD-BACKUP"
export PBS_PASSWORD="your-password"
proxmox-backup-client login
# Answer 'y' when prompted to accept the fingerprint
```

## Permission Errors

### Missing Datastore.Backup Permission

**Error:**
```
Error: permission check failed - missing Datastore.Audit|Datastore.Backup
Error: while creating locked backup group
```

**Solution:**

Your API token needs backup permissions on the datastore.

**Via PBS Web Interface:**
1. Go to **Configuration → Access Control → Permissions**
2. Click **Add → User Permission**
3. Configure:
   - **Path:** `/datastore/YOUR-DATASTORE-NAME`
   - **User:** `root@pam!backupAutomations` (your token)
   - **Role:** `DatastoreBackup` (or `DatastoreAdmin` for full access)
4. Click **Add**

**Via PBS CLI:**
```bash
pveum acl modify /datastore/DEAD-BACKUP -token 'root@pam!backupAutomations' -role DatastoreBackup
```

### Required Permissions

The API token needs at least:
- **Datastore.Backup** - Create new backups
- **Datastore.Verify** - Verify backup integrity (optional)
- **Datastore.Prune** - Remove old backups based on retention policy

The `DatastoreBackup` or `DatastoreAdmin` role includes all of these.

## Installation Issues

### Ubuntu 22.04: libssl1.1 Missing

**Error:**
```
libssl1.1: not found
```

**Solution:**
```bash
wget http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb
```

### Arch Linux: libfuse3.so.3 Not Found

**Error:**
```
error while loading shared libraries: libfuse3.so.3: cannot open shared object file
```

**Solution:**

Rebuild the package after fuse3 updates:
```bash
yay -S proxmox-backup-client-bin --rebuild
```

### Arch Linux: yay Not Installed

**Error:**
```
yay: command not found
```

**Solution:**

Install yay AUR helper first:
```bash
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

See: https://github.com/Jguer/yay

## Backup Issues

### Backups Not Running

Check timer and service status:

```bash
# Check if timer is enabled and active
sudo systemctl list-timers pbs-backup-default.timer

# Check service status
sudo systemctl status pbs-backup-default.service

# View recent logs
sudo journalctl -u pbs-backup-default.service -n 50

# Follow logs in real-time
sudo journalctl -fu pbs-backup-default.service
```

### "Skip mount point" Messages

**Message:**
```
Skip mount point: /boot/efi
```

**This is normal behavior.** The script excludes separate mount points by default to avoid issues with mounted filesystems.

**To include specific mount points:**

Edit `/etc/proxmox-backup-client/backup-default.sh` and add `--include-dev` flags:

```bash
proxmox-backup-client backup \
  root.pxar:/ \
  --include-dev /boot/efi \
  --repository $PBS_REPOSITORY
```

### Backup Fails with "No space left"

**Error:**
```
Error: No space left on device
```

**Possible causes:**
1. PBS datastore is full
2. Local `/tmp` is full during backup
3. Encryption key storage is full

**Solutions:**
1. Check PBS datastore usage in web interface
2. Prune old backups: `sudo proxmox-backup-client prune`
3. Clean local temp: `sudo rm -rf /tmp/*`

### Encryption Key Issues

**Error:**
```
Error: unable to open encryption key
```

**Solution:**

Ensure encryption key exists and has correct permissions:
```bash
ls -la /root/.config/proxmox-backup/encryption-key.json
# Should show: -rw------- (600) owned by root

# If missing, restore from paper backup
sudo mkdir -p /root/.config/proxmox-backup
sudo cp /path/to/saved/encryption-key.json /root/.config/proxmox-backup/
sudo chmod 600 /root/.config/proxmox-backup/encryption-key.json
```

## Multi-Target Issues

### Target Connection Tests Fail

**Symptom:**
```
  default:             ✗ Failed
```

**Solution:**

Use option 3 (Edit target) from main menu to reconfigure:
1. Test connection first with standalone test-connection.sh script
2. Verify datastore permissions on PBS server
3. Check for typos in server/datastore names
4. Ensure API token is still valid (not revoked/expired)

### Services Not Found

**Error:**
```
Unit pbs-backup-default.timer not found
```

**Solution:**

The target may not have been fully configured. Reconfigure it:
```bash
sudo PBSClientTool
# Select option 3 (Edit existing target)
# Select option 3 (Full reconfiguration)
```

## Configuration Issues

### Whitespace in Configuration

**Error:**
```
Error: invalid repository format
```

**Cause:**

Previous versions could capture trailing spaces in input fields, breaking the repository string.

**Solution:**

Current version (1.1.0+) automatically trims all input. If you have an old config, reconfigure the target:
```bash
sudo PBSClientTool
# Select option 3 (Edit existing target)
# Select option 1 (Connection only)
# Re-enter connection details (will be auto-trimmed)
```

### Target Shows "Incomplete configuration"

**Symptom:**
```
Target: default
  Status: ⚠ Incomplete configuration
  Action: Use option 3 (Edit target) to reconfigure
```

**Cause:**

Essential fields (PBS_SERVER or PBS_DATASTORE) are missing or contain placeholder values.

**Solution:**

Use option 3 from main menu to edit the target and complete the configuration.

## Advanced Troubleshooting

### Enable Verbose Backup Logging

Edit `/etc/proxmox-backup-client/backup-default.sh` and add `--verbose`:

```bash
proxmox-backup-client backup \
  root.pxar:/ \
  --verbose \
  --repository $PBS_REPOSITORY
```

### Test Backup Manually

Run backup script directly to see full output:

```bash
sudo /etc/proxmox-backup-client/backup-default.sh
```

### Check PBS Server Logs

On the PBS server:
```bash
journalctl -u proxmox-backup.service -f
```

### Verify Repository Format

Check that PBS_REPOSITORY is correctly formatted:

```bash
source /etc/proxmox-backup-client/targets/default.conf
echo $PBS_REPOSITORY

# Should look like:
# username@realm!tokenname@server:port:datastore
# OR
# username@realm@server:port:datastore
```

### Network Timeout Issues

If backups are slow or timing out over WAN:

Edit backup script and add rate limiting:
```bash
proxmox-backup-client backup \
  root.pxar:/ \
  --rate-limit 10485760 \
  --repository $PBS_REPOSITORY
```

Rate is in bytes/second (10485760 = 10 MB/s).

## Getting Help

### Collect Debug Information

When reporting issues, include:

```bash
# Script version
sudo PBSClientTool --version

# PBS client version
proxmox-backup-client version

# Target list
sudo PBSClientTool
# Select option 1, screenshot the output

# Service status
sudo systemctl status pbs-backup-default.service

# Recent logs
sudo journalctl -u pbs-backup-default.service -n 100 --no-pager
```

### Where to Get Help

- **PBSClientTool issues:** https://github.com/zaphod-black/PBSClientTool/issues
- **PBS client issues:** https://forum.proxmox.com
- **PBS documentation:** https://pbs.proxmox.com/docs/

## Common Misconfigurations

### Token Format

❌ **Wrong:** `backupAutomations` (token name only)
✅ **Correct:** `root@pam!backupAutomations` (full format in permissions)

### Datastore Name

❌ **Wrong:** `DEAD-Backup` (wrong case)
✅ **Correct:** `DEAD-BACKUP` (exact match from PBS)

### Repository String

❌ **Wrong:** `root@pam !backupAutomations@...` (extra space)
✅ **Correct:** `root@pam!backupAutomations@...` (no spaces)

(Note: Current version auto-trims spaces, but good to know the correct format)

### Permission Path

❌ **Wrong:** `/datastore/DEAD-BACKUP/` (trailing slash)
✅ **Correct:** `/datastore/DEAD-BACKUP` (no trailing slash)
