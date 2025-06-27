# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ubuntu VPS setup automation toolkit. The focus is on transforming fresh Ubuntu 24.04 installations into secure, Docker-ready environments with minimal user interaction.

## Architecture Evolution

The project underwent a major architectural shift (visible in git history):
- **Original**: Complex bash module system with 11+ specialized modules
- **Current**: Streamlined `ubuntu-fresh-install/` directory with 2 main scripts
- **Philosophy**: Moved from enterprise-grade modularity to accessible simplicity

## Main Scripts and Usage

### Current Active Scripts

**ubuntu-fresh-install/ubuntu-setup.sh** (Server-side):
- Complete server hardening and Docker setup in 5 sequential steps
- Runs on target Ubuntu 24.04 server with existing user account
- Handles: system updates, SSH hardening, Docker installation, UFW+Docker firewall

**ubuntu-fresh-install/generate-ssh-key.sh** (Client-side):
- SSH key pair generation with smart naming conventions
- Supports both interactive and command-line modes
- Generates ED25519 keys with usage instructions

### Execution Patterns

**Direct GitHub execution** (primary workflow):
```bash
# Generate SSH keys (client)
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/generate-ssh-key.sh | bash

# Setup server (server)
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/ubuntu-setup.sh | bash -s -- <username> "<ssh-public-key>"
```

**Local execution** (development/testing):
```bash
# Download and test locally
curl -o ubuntu-setup.sh https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/ubuntu-setup.sh
chmod +x ubuntu-setup.sh
./ubuntu-setup.sh username "ssh-key"
```

## Development Commands

### Script Validation
```bash
# Syntax check
bash -n ubuntu-fresh-install/ubuntu-setup.sh
bash -n ubuntu-fresh-install/generate-ssh-key.sh

# Make executable
chmod +x ubuntu-fresh-install/*.sh
```

### Testing Workflow
```bash
# Test on fresh Ubuntu 24.04 server
./ubuntu-setup.sh testuser "$(cat ~/.ssh/id_rsa.pub)"

# Verify setup completion
docker --version
ufw status
ssh-test.sh  # if available
```

### Git Workflow
```bash
# Standard commit pattern
git commit -m "Description
```

## Key Technical Details

### Script Architecture
- **Error Handling**: All scripts use `set -e` for fail-fast behavior
- **User Validation**: Comprehensive input validation before execution
- **Progress Feedback**: Color-coded output with success/error indicators
- **Idempotency**: Scripts check existing state before making changes

### Security Configuration
- **SSH Hardening**: Disables root login, password auth, enables key-only access
- **UFW Integration**: Firewall with Docker container isolation via ufw-docker tool
- **Docker Security**: Daemon configured with security settings and log rotation
- **System Backups**: SSH configs backed up before modifications

### Management Tools Created
Scripts install these tools in `/usr/local/bin/`:
- `docker-status.sh` - Docker system status and container overview
- `ufw-status.sh` - Firewall status with Docker integration info
- `docker-firewall.sh` - Easy Docker container port management

## Important Implementation Notes

### UFW-Docker Integration Sequence
The script enables UFW **before** installing ufw-docker integration (fixed in commit aacaa87). This order is critical:
1. Configure UFW rules
2. Enable UFW firewall
3. Install ufw-docker tool
4. Configure Docker integration

### SSH Banner Customization
The SSH banner dynamically includes hostname and IP address:
```bash
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
```

### Parameter Handling
Scripts support both command-line arguments and interactive prompts:
- Command-line: `./script.sh username "ssh-key"`
- Interactive: Prompts when parameters missing
- GitHub execution: Must provide parameters via `bash -s --`

## Legacy Architecture (Available in Git History)

For reference, the original modular system included:
- `bash/modules/`: 11 specialized modules (backup, monitoring, security, etc.)
- `bash/configs/`: Configuration file system
- `server-scripts/`: Multi-script server-side deployment
- Comprehensive testing framework and documentation

This system was simplified to focus on core Docker+SSH setup functionality while maintaining security and reliability.