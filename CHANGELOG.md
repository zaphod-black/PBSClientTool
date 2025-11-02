# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Multi-target backup support (IN PROGRESS - v1.1.0)**
  - Support for multiple backup destinations (different PBS servers for redundancy)
  - Named backup targets (e.g., "offsite", "local", "backup1")
  - Target management functions:
    - List all configured targets with status
    - Add new backup targets
    - Edit existing targets (connection, settings, or full reconfig)
    - Delete targets with confirmation
    - View detailed target information
  - Automatic migration from legacy single-target configuration to "default" target
  - Independent systemd services per target (pbs-backup-TARGET.service)
  - Configuration stored in /etc/proxmox-backup-client/targets/TARGET.conf
  - Schedule coordination options (planned):
    - All targets run at same time
    - Alternating schedule across targets
    - Individual schedules per target
- Intelligent reconfiguration options when PBS client is already installed
  - Quick connection-only reconfiguration (server/credentials only)
  - Full reconfiguration of all settings
  - Reinstall option with reconfiguration
  - Exit without changes option
- 3-step connection verification process:
  - Step 1: Server reachability test (5s timeout with curl)
  - Step 2: Authentication test with automatic SSL fingerprint acceptance
  - Step 3: Datastore access verification
- Display available block devices when invalid device is entered
- Step-by-step progress indicators during connection testing
- `test-connection.sh` - Diagnostic script for testing PBS connections manually
  - Parameterized for security (no hardcoded credentials)
  - Tests server reachability, authentication, and datastore access
  - Handles SSL fingerprint acceptance interactively
- Comprehensive documentation in README:
  - Step-by-step walkthrough of complete installation (14 steps)
  - PBS server setup guide (API token creation and permissions)
  - Common permission error troubleshooting
  - Explanation of backup types, schedules, and retention policies
- **Live backup progress monitoring**
  - Real-time log following when running backups
  - Automatic completion detection
  - Shows PBS client's built-in progress bars and statistics
  - Can exit with Ctrl+C (backup continues in background)
  - Applied to both "Run backup now" menu option and post-install backup

### Changed
- Installation instructions now use `git clone` instead of `wget`
- Connection test provides better user feedback during testing
- Script now detects existing configurations and offers appropriate options
- Block device detection now strips btrfs subvolume notation (e.g., `[/@]`)
- Connection test succeeds if authentication works, even if no backups exist yet
- More specific error messages based on which step of connection test fails
- SSL certificate fingerprints are now automatically accepted during setup
- Reduced authentication timeout from 30s to 15s
- README now includes comprehensive step-by-step walkthrough
- Prerequisites section expanded with detailed PBS server setup instructions
- README updated with live backup progress examples in Step 13
- Reconfiguration section now documents "Run backup now" option (option 4)
- Manual Backup section updated to recommend easy method via installer
- **Default realm changed from "pbs" to "pam"** (more common for root authentication)
- **Default encryption setting changed from "yes" to "no"** (user can opt-in if needed)
- Main menu now includes "Run backup now" option for immediate backup testing
- Main menu now includes "Modify backup schedule/type" option (option 5)
- Repository renamed from PBSClientInstaller to PBSClientTool
- **Manual backups now force full backup (files + block device) regardless of day**
  - Created separate pbs-backup-manual.service for manual runs
  - Scheduled backups still follow daily/weekly pattern
  - Manual backups always include block device even on non-Sunday
- Script version bumped to 1.1.0 for multi-target support

### Fixed
- **CRITICAL**: SSL fingerprint prompt no longer causes authentication timeout
  - Script now automatically accepts SSL fingerprints by piping 'y' to login
  - This was the root cause of "authentication hanging" issues
- **CRITICAL**: Password/token capture no longer includes newline character
  - `prompt_password()` function now outputs formatting to stderr
  - Added defensive newline stripping when writing config file
  - Filters `\n` and `\r` characters from passwords using `tr -d '\n\r'`
  - Fixes "authentication failed - invalid credentials" in backup service
  - Config file now has properly formatted single-line passwords
  - Applied to both `reconfigure_connection()` and `create_systemd_service()`
- Script no longer hangs indefinitely when PBS server is unreachable
- Block device auto-detection now correctly handles btrfs subvolumes
- Invalid device paths like `/dev/mapper/root[/@]` are now properly cleaned
- Connection test now differentiates between network issues and authentication failures
- Shows actual PBS client error messages when authentication fails
- Authentication test now uses correct `login` command instead of non-existent `status` command
- Connection test no longer times out due to using wrong PBS client commands
- **Backup progress logs now display properly during manual backup runs**
  - Fixed journalctl following wrong service (was following pbs-backup.service instead of pbs-backup-manual.service)
  - Removed stderr suppression (2>/dev/null) that was hiding output
  - Added --since flag to capture logs from service start, not just new entries
  - Now shows verbose progress: "processed 65.6 GiB in 18m, uploaded 64.4 GiB"
- Backup logs now close automatically when backup completes (no more blank screen)

## [1.0.0] - 2025-11-01

### Added
- Initial release
- Auto-detection of Linux distribution (Ubuntu, Debian, Arch)
- Interactive configuration via console prompts
- Automatic encryption key generation with paper backup
- Systemd service and timer for automated backups
- Configurable retention policies
- Connection testing before finalization
- Immediate backup option after installation
- Support for file-level (.pxar) backups
- Support for block device (.img) backups
- Hybrid backup mode (daily files + weekly block device)
- Comprehensive error handling and logging
- Uninstaller script
