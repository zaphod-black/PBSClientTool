# Quick Start Guide

## One-Command Install

```bash
curl -sSL https://raw.githubusercontent.com/YOUR-REPO/pbs-client-installer.sh | sudo bash
```

Or download first:

```bash
wget https://raw.githubusercontent.com/YOUR-REPO/pbs-client-installer.sh
chmod +x pbs-client-installer.sh
sudo ./pbs-client-installer.sh
```

## Before You Start

Have these ready:
- PBS server IP (e.g., 192.168.1.181)
- Datastore name (e.g., backups)
- Authentication: username + password OR API token

### Creating an API Token (Recommended)

On your PBS server web interface:
1. Go to **Configuration → Access Control → API Tokens**
2. Click **Add**
3. Username: `backup@pbs`
4. Token ID: `backup-token`
5. Click **Add** and save the secret shown

## Installation Flow

1. Script detects your Linux distro
2. Installs correct PBS client version
3. You answer prompts for:
   - PBS server details
   - **Backup type:** File-level, Block device, or Both (Hybrid)
   - What to backup
   - When to backup (schedule)
   - How long to keep backups (retention)
4. Script creates encryption key
5. Tests connection
6. Sets up automated backups
7. Optionally runs first backup

**Time required:** 2-5 minutes

## Backup Type Selection

During installation, choose your backup strategy:

**1. File-level only (.pxar):**
- Fast, efficient daily backups
- Great for file recovery
- Cannot directly boot as VM

**2. Block device only (.img):**
- Full disk images
- **Can be booted as VMs** in Proxmox
- Larger backup size, slower

**3. Both (Hybrid) - RECOMMENDED:**
- Daily file-level backups
- Weekly full disk images (Sundays)
- Best for disaster recovery + VM conversion
- See BACKUP-TYPES-GUIDE.md for details

## Example Configuration

### Basic Setup (Root filesystem only)
- Paths: `/`
- Exclusions: `/tmp /var/tmp /var/cache /proc /sys /dev /run`
- Schedule: Daily at 2 AM
- Retention: 3 last, 7 daily, 4 weekly, 6 monthly

### Full System Backup
- Paths: `/ /home`
- Exclusions: `/tmp /var/tmp /var/cache /proc /sys /dev /run`
- Schedule: Daily at 3 AM
- Retention: 3 last, 7 daily, 4 weekly, 12 monthly

## Post-Install Commands

```bash
# Check timer status
sudo systemctl status pbs-backup.timer

# View logs
sudo journalctl -u pbs-backup.service

# Run backup now
sudo systemctl start pbs-backup.service

# List your backups
sudo -E proxmox-backup-client snapshot list

# Disable automatic backups
sudo systemctl disable pbs-backup.timer
```

## Backup Your Encryption Key!

After installation, immediately backup:
```bash
/root/.config/proxmox-backup/encryption-key.json
/root/pbs-encryption-key-*.txt (paper backup with QR code)
```

**Lost key = Lost data forever!**

## Converting Backups to VMs

If you chose block device or hybrid backups, you can boot your laptop as a VM:

```bash
# On Proxmox VE host (install PBS client first)

# Create VM
qm create 999 --name "laptop-vm" --memory 4096 --cores 2 --scsi0 local-lvm:32

# Restore backup to VM disk
proxmox-backup-client restore \
  host/your-laptop/2025-11-01T03:00:00Z \
  sda.img \
  /dev/pve/vm-999-disk-0

# Boot VM
qm set 999 --boot order=scsi0
qm start 999
```

**See BACKUP-TYPES-GUIDE.md for complete instructions**

## Troubleshooting

**Connection fails?**
```bash
ping YOUR_PBS_IP
curl -k https://YOUR_PBS_IP:8007
```

**Check credentials in PBS web interface**

**Arch: Need yay first?**
```bash
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

## Uninstall

```bash
sudo ./pbs-client-uninstaller.sh
```

Keeps your backups on PBS server intact.

## Support

Full docs: See README.md
PBS Forums: https://forum.proxmox.com
Issues: [your-repo]/issues
