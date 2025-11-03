# Backup Types and VM Conversion Guide

## Three Backup Strategies

When running the installer, you'll be asked to choose between three backup types:

### 1. File-level Only (.pxar)
**What it does:** Backs up files and directories as archives

**Pros:**
- Very fast backups (uses metadata change detection)
- Excellent deduplication (20-40x typical)
- Small backup size
- Selective file restoration
- Perfect for daily backups

**Cons:**
- Cannot be directly booted as a VM
- Requires manual steps to restore to bare metal
- Need to reinstall bootloader after restore

**Best for:**
- File recovery
- Configuration backups
- User data protection
- Systems where you just need files, not full disaster recovery

**Example use case:** Backing up a development laptop where you mainly care about code and configs

---

### 2. Block Device Only (.img)
**What it does:** Creates full disk/partition images

**Pros:**
- **Directly bootable as a VM** - just restore to VM disk and start
- Bare metal restore with dd
- Complete system snapshot (including bootloader, partitions, etc.)
- No post-restore configuration needed
- Perfect for disaster recovery

**Cons:**
- Much larger backups (backs up entire disk including empty space)
- Slower backup process
- Less deduplication
- More storage required on PBS

**Best for:**
- Disaster recovery
- Converting physical machines to VMs
- Hardware migration
- Systems you want to boot as VMs later

**Example use case:** Production laptop you want to be able to boot as a VM in Proxmox if hardware fails

---

### 3. Both (Hybrid) - RECOMMENDED
**What it does:** Daily file-level backups + Weekly block device backups

**How it works:**
- File-level backup runs on your schedule (e.g., daily at 2 AM)
- Block device backup runs every **Sunday** regardless of your schedule
- Both stored in the same datastore

**Pros:**
- Best of both worlds
- Fast daily backups for file recovery
- Weekly bootable snapshots for disaster recovery
- Reasonable storage usage
- Maximum flexibility

**Cons:**
- More complex
- Requires more storage than file-only
- Block device backups take longer when they run

**Best for:**
- Production systems
- Critical laptops/workstations
- Any system where both file recovery AND disaster recovery matter

**Example use case:** Your main work laptop - daily backups protect recent work, weekly images let you boot as VM if laptop dies

---

## Storage Requirements Comparison

Example: 256GB laptop with 120GB used space

| Backup Type | First Backup | Subsequent Backups | Weekly Storage Growth |
|------------|--------------|-------------------|---------------------|
| File-level | ~120GB | ~1-5GB (changed files only) | ~7-35GB |
| Block device | ~256GB | ~256GB each time | ~256GB |
| Both (Hybrid) | ~376GB | ~1-5GB daily, +256GB Sunday | ~263-291GB |

**Note:** Deduplication dramatically reduces actual storage - PBS typically achieves 10-40x deduplication on file-level backups.

---

## Converting to VMs

### File-level Backups → VM
**NOT RECOMMENDED** - Requires manual work:

1. Create new VM with blank disk
2. Install minimal OS in VM
3. Boot VM into rescue mode
4. Restore .pxar backup over the minimal install
5. Reinstall bootloader (grub-install)
6. Fix /etc/fstab for new disk UUIDs
7. Configure network for VM environment
8. Reboot and troubleshoot

**Complexity:** High  
**Success rate:** ~60-70%  
**Time:** 1-3 hours

---

### Block Device Backups → VM
**RECOMMENDED** - Almost automatic:

```bash
# On Proxmox VE host (must have PBS client installed)

# 1. List available backups
proxmox-backup-client snapshot list

# 2. Create VM shell (via GUI or CLI)
qm create 999 --name "laptop-vm" --memory 4096 --cores 2

# 3. Create disk for VM (size >= original disk)
qm set 999 --scsi0 local-lvm:32

# 4. Find VM disk device
VM_DISK=$(lvdisplay | grep "vm-999-disk-0" | awk '{print $3}')
# Or typically: /dev/pve/vm-999-disk-0

# 5. Restore backup directly to VM disk
# Replace sda.img with your actual backup name (e.g., nvme0n1.img)
proxmox-backup-client restore \
  host/your-laptop/2025-11-01T03:00:00Z \
  sda.img \
  "$VM_DISK"

# 6. Configure VM boot
qm set 999 --boot order=scsi0

# 7. Start VM
qm start 999
```

**Complexity:** Low  
**Success rate:** ~95%+  
**Time:** 10-30 minutes (mostly waiting for restore)

---

### Post-VM-Conversion Tasks

After booting the restored laptop as a VM, you'll likely need to:

```bash
# 1. Fix network (VM uses virtio, laptop had different interface)
# Ubuntu/Debian:
sudo nano /etc/netplan/01-netcfg.yaml
# Change interface name to ens18 or whatever shows in 'ip a'

# Arch:
sudo nano /etc/systemd/network/20-wired.network

# 2. Install QEMU guest agent (highly recommended)
sudo apt install qemu-guest-agent        # Ubuntu/Debian
sudo pacman -S qemu-guest-agent          # Arch
sudo systemctl enable --now qemu-guest-agent

# 3. Remove laptop-specific packages (optional)
sudo apt remove laptop-mode-tools tlp   # Power management
sudo pacman -Rs laptop-mode-tools

# 4. Update fstab if needed (usually not required)
# Only if you see errors about missing disks

# 5. Reboot to ensure everything works
sudo reboot
```

**That's it!** Your laptop is now running as a VM.

---

## Bare Metal Restoration (New Laptop/Hardware)

### Scenario: Laptop died, bought new one with bigger SSD

**Using Block Device Backup:**

1. Boot new laptop from Ubuntu/Arch USB
2. Install PBS client on live system
3. Configure connection to your PBS
4. List backups and find latest
5. Restore directly to new disk:

```bash
# On live USB system
sudo apt install proxmox-backup-client  # or yay -S on Arch

# Configure (temporary)
export PBS_REPOSITORY='user@pbs!token@192.168.1.181:8007:backups'
export PBS_PASSWORD='your-token-secret'

# List backups
proxmox-backup-client snapshot list

# Restore to new disk (replace /dev/nvme0n1 with your new disk)
proxmox-backup-client restore \
  host/old-laptop/2025-11-01T03:00:00Z \
  sda.img \
  /dev/nvme0n1

# Reboot
sudo reboot
```

6. Remove USB, boot from restored disk
7. System should boot normally with all your data

**If new disk is larger:** The restored partition will be original size. Expand it:

```bash
# After first boot from restored disk

# For ext4 filesystem
sudo growpart /dev/nvme0n1 1  # Expand partition
sudo resize2fs /dev/nvme0n1p1  # Expand filesystem

# For btrfs
sudo btrfs filesystem resize max /
```

---

## Which Should You Choose?

**Choose File-level only if:**
- Storage on PBS is very limited
- You only care about recovering files, not full system
- You're comfortable reinstalling OS if hardware fails
- Backup speed is critical

**Choose Block device only if:**
- You specifically want VM conversion capability
- Storage space is not a concern
- You rarely backup (weekly/monthly)
- System rarely changes

**Choose Both (Hybrid) if:**
- You want maximum protection
- PBS has decent storage (500GB+ free)
- System is important/production
- You want both fast recovery AND disaster recovery options
- **This is the recommended default**

---

## Storage Planning

### For Hybrid Backups

Calculate required PBS storage:

```
Initial: (Disk Size) + (Used Space)
Weekly: + (Disk Size)
Monthly: 4 × (Disk Size) + ~(Used Space × 2)
```

**Example:** 512GB laptop with 200GB used

```
Initial: 512GB + 200GB = 712GB
After 1 month: 512 + 200 + (4 × 512) + 400 = 2860GB ≈ 3TB
With dedup: ~1TB actual storage (typical 3:1 compression)
```

**Recommendation:** PBS datastore with at least **3x your total disk size** for comfortable monthly retention with hybrid backups.

---

## Testing Your Backups

**CRITICAL:** Always test restores before you need them!

### Test File-level Restore
```bash
# Restore single file to verify
proxmox-backup-client restore \
  host/laptop/2025-11-01T03:00:00Z \
  root.pxar /tmp/test-restore \
  --pattern 'etc/hostname'

cat /tmp/test-restore/etc/hostname
```

### Test Block Device Restore
```bash
# On Proxmox VE, create test VM quarterly
# Follow VM conversion steps above
# Verify VM boots successfully
# Delete test VM after verification
```

---

## Troubleshooting

### Block device backup fails: "cannot open device"

**Problem:** Device is busy/mounted

**Solution:**
```bash
# Option 1: Backup while system is running (works, but not ideal)
# Current script does this - it's safe but may have minor inconsistencies

# Option 2: Boot from USB and backup unmounted disk (best)
# Boot from Live USB
# Install PBS client
# Backup the unmounted disk
```

### VM won't boot after restore

**Common causes:**
1. Secure Boot enabled in VM (disable in VM settings)
2. Wrong boot order (set boot to scsi0)
3. EFI partition not restored (ensure you backed up entire disk, not just a partition)

**Fix:**
```bash
# In Proxmox VM settings:
# Options → Boot Order → Enable scsi0, move to top
# Options → BIOS → SeaBIOS (or OVMF if original was UEFI)
```

### "Not enough space" error during block device backup

**Problem:** Disk is large, PBS datastore is full

**Solutions:**
1. Clean old backups: `proxmox-backup-client prune`
2. Run garbage collection on PBS
3. Add more storage to PBS
4. Switch to file-level only or increase prune frequency

---

## FAQ

**Q: Can I backup just one partition instead of entire disk?**  
A: Yes! During setup, specify `/dev/sda1` instead of `/dev/sda`. However, you won't be able to directly boot this as a VM without manual partition table recreation.

**Q: Will hybrid backup run two backups simultaneously?**  
A: No. On Sundays, it runs file backup first, then block backup. They're sequential.

**Q: Can I change the weekly block backup day from Sunday?**  
A: Yes! Edit `/etc/proxmox-backup-client/backup.sh` and change `[ "$(date +%u)" -eq 7 ]` to different day (1=Monday, 7=Sunday).

**Q: Does block device backup require downtime?**  
A: No, but it's a "hot backup" of a running system, so minor inconsistencies possible. For critical systems, consider backing up while system is idle or from Live USB.

**Q: Can I restore a block backup to smaller disk?**  
A: No, target must be >= original size. You CAN restore file-level backups to any size disk.

**Q: Do I need encryption for block device backups?**  
A: YES! Block device backups contain everything including swap (which may have passwords/keys). Always enable encryption.

---

## Quick Command Reference

```bash
# List all backups
proxmox-backup-client snapshot list

# Restore file-level backup
proxmox-backup-client restore host/laptop/DATE root.pxar /restore/path

# Restore block device to disk
proxmox-backup-client restore host/laptop/DATE sda.img /dev/sdX

# Restore block device to VM disk
proxmox-backup-client restore host/laptop/DATE sda.img /dev/pve/vm-ID-disk-0

# Mount backup for browsing (file-level only)
proxmox-backup-client mount host/laptop/DATE root.pxar /mnt

# Check backup size
proxmox-backup-client snapshot list --output-format json | jq

# Manual block device backup
proxmox-backup-client backup sda.img:/dev/sda
```
