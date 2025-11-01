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
- Connection test timeout (30 seconds) to prevent indefinite hanging
- Detailed error messages for connection failures
  - Differentiates between timeout and authentication errors
  - Provides specific troubleshooting steps based on error type
  - Displays helpful diagnostic commands

### Changed
- Installation instructions now use `git clone` instead of `wget`
- Connection test provides better user feedback during testing
- Script now detects existing configurations and offers appropriate options

### Fixed
- Script no longer hangs indefinitely when PBS server is unreachable
- Connection test now properly handles timeout scenarios

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
