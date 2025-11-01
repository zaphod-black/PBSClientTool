# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Intelligent reconfiguration options when PBS client is already installed
  - Quick connection-only reconfiguration (server/credentials only)
  - Full reconfiguration of all settings
  - Reinstall option with reconfiguration
  - Exit without changes option
- 3-step connection verification process:
  - Step 1: Server reachability test (5s timeout)
  - Step 2: Authentication test (30s timeout)
  - Step 3: Datastore access verification
- Display available block devices when invalid device is entered
- Step-by-step progress indicators during connection testing

### Changed
- Installation instructions now use `git clone` instead of `wget`
- Connection test provides better user feedback during testing
- Script now detects existing configurations and offers appropriate options
- Block device detection now strips btrfs subvolume notation (e.g., `[/@]`)
- Connection test succeeds if authentication works, even if no backups exist yet
- More specific error messages based on which step of connection test fails

### Fixed
- Script no longer hangs indefinitely when PBS server is unreachable
- Block device auto-detection now correctly handles btrfs subvolumes
- Invalid device paths like `/dev/mapper/root[/@]` are now properly cleaned
- Connection test now differentiates between network issues and authentication failures
- Shows actual PBS client error messages when authentication fails
- Authentication test now uses correct `login` command instead of non-existent `status` command
- Connection test no longer times out due to using wrong PBS client commands

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
