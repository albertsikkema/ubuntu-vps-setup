# Ubuntu VPS Production Setup Tool

A comprehensive CLI tool for setting up a production-ready Ubuntu 24.10 VPS with security hardening, Docker support, and proper firewall configuration.

## Quick Start

### 🚀 Fully Automated Setup (Recommended)

Run this one-liner for a complete set-and-forget setup:

```bash
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/bash/setup.sh | sudo bash -s -- --auto
```

Or download first:

```bash
wget https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/bash/setup.sh
chmod +x setup.sh
sudo ./setup.sh --auto
```

### 🎯 What Auto Mode Does:
- **Timezone**: Always UTC
- **Locale**: English language with Dutch (nl-NL) formatting
- **Username**: `admin` (customizable with `--username=myuser`)
- **SSH Port**: `2222` (customizable with `--ssh-port=3333`)
- **All Security**: Full hardening enabled
- **Docker**: With UFW integration
- **Zero Prompts**: Completely automated

### ⚙️ Custom Automated Setup

```bash
# Custom username and SSH port
sudo ./setup.sh --auto --username=myuser --ssh-port=3333

# Only specific modules
sudo ./setup.sh --auto --modules=docker,docker_ufw,firewall
```

### 📱 Interactive Mode

For manual control:

```bash
wget https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/bash/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

## Features

### Core Modules

1. **System Update & Basic Setup**
   - Updates all packages
   - Configures timezone and hostname
   - Sets up swap space
   - Configures system limits
   - Enables automatic security updates

2. **User Management**
   - Creates secure sudo user
   - Configures SSH key authentication
   - Sets up password policies
   - Implements account lockout policies

3. **SSH Hardening**
   - Changes default SSH port
   - Disables root login
   - Configures key-only authentication
   - Sets up fail2ban protection
   - Optional 2FA setup

4. **Firewall Configuration**
   - UFW setup with secure defaults
   - Rate limiting for SSH
   - Custom port management
   - IP-based access control

5. **Security Hardening**
   - Kernel parameter hardening
   - AppArmor configuration
   - File integrity monitoring (AIDE)
   - Audit logging (auditd)
   - Rootkit detection tools

6. **Docker Installation**
   - Docker Engine from official repository
   - Docker Compose plugin
   - Optimized daemon configuration
   - User permissions setup

7. **Docker-UFW Integration**
   - Fixes Docker's UFW bypass issue
   - Installs ufw-docker tool
   - Provides secure container access management

## Usage

### Interactive Mode (Recommended)

Simply run the script without arguments:

```bash
sudo ./setup.sh
```

This will show an interactive menu where you can select which modules to install.

### Quick Mode

For a standard setup with recommended modules:

```bash
sudo ./setup.sh --quick
```

This installs: system updates, user management, SSH hardening, firewall, and security modules.

### Specific Modules

To run only specific modules:

```bash
sudo ./setup.sh --modules system_update,docker,docker_ufw
```

### Dry Run

To see what would be done without making changes:

```bash
sudo ./setup.sh --dry-run
```

## Module Details

### System Requirements

- Ubuntu 24.10 (also works with 24.04 and 23.10)
- Root or sudo access
- At least 1GB RAM
- At least 10GB disk space
- Active internet connection

### What Each Module Does

#### System Update
- Updates package lists and upgrades all packages
- Installs essential tools (curl, wget, git, etc.)
- Configures swap (2x RAM up to 4GB, then 1x RAM up to 8GB max)
- Sets timezone based on IP geolocation
- Configures automatic security updates

#### User Management
- Creates a new sudo user with secure password
- Optional SSH key setup (paste key or provide URL)
- Optional passwordless sudo configuration
- Disables root SSH access
- Configures password complexity requirements
- Sets up account lockout after 5 failed attempts

#### SSH Hardening
- Optional port change (default: 22)
- Disables password authentication
- Restricts to SSH protocol 2
- Configures secure ciphers and algorithms
- Sets up login banner
- Implements connection limits
- Optional 2FA with Google Authenticator

#### Firewall (UFW)
- Default: deny incoming, allow outgoing
- Automatic SSH port detection and protection
- Rate limiting on SSH (6 connections per 30 seconds)
- Optional HTTP/HTTPS ports
- Custom port configuration
- IP-based allow/deny rules

#### Security Hardening
- Kernel parameters for network security
- Disables IPv6 (if not needed)
- AppArmor enforcement
- AIDE file integrity monitoring
- Audit logging for security events
- Disables unnecessary services
- Installs security scanning tools

#### Docker Installation
- Adds official Docker repository
- Installs Docker CE, CLI, and Compose plugin
- Configures logging rotation
- Sets up Docker user permissions
- Creates organized directory structure in /opt/docker
- Optional standalone docker-compose binary

#### Docker-UFW Integration
- Installs ufw-docker tool
- Fixes Docker's iptables bypass issue
- Provides commands to manage container access:
  ```bash
  # Allow access to container
  sudo ufw-docker allow nginx 80
  
  # Allow from specific IP
  sudo ufw-docker allow nginx 80 from 192.168.1.0/24
  
  # Remove access
  sudo ufw-docker delete allow nginx 80
  ```

## Security Best Practices

1. **Always run system_update first** - Ensures latest security patches
2. **Create a non-root user** - Never use root for daily operations
3. **Use SSH keys** - More secure than passwords
4. **Change SSH port** - Reduces automated attacks
5. **Enable firewall before Docker** - Ensures proper integration
6. **Regular updates** - Run system updates weekly
7. **Monitor logs** - Check /var/log/auth.log and /var/log/ufw.log

## Post-Installation

### Important Commands

```bash
# Check firewall status
sudo ufw status verbose

# Check fail2ban status
sudo fail2ban-client status

# Check Docker container ports
docker-ports

# Run security audit
sudo lynis audit system

# Check for rootkits
sudo rkhunter --check

# View security report
sudo cat /root/security-report.txt
```

### Files and Directories

- **Logs**: `/var/log/vps-setup.log`
- **Firewall config**: `/root/firewall-config.txt`
- **Security report**: `/root/security-report.txt`
- **Docker files**: `/opt/docker/`
- **UFW-Docker examples**: `/root/ufw-docker-examples.txt`

### Default Configurations

- **SSH**: Key-only auth, fail2ban protection
- **Firewall**: Deny all incoming except configured ports
- **Docker**: Logging limited to 100MB x 5 files
- **Swap**: Dynamic based on RAM
- **Updates**: Daily security updates

## Troubleshooting

### SSH Connection Issues

If you're locked out after SSH changes:

1. Use VPS provider's console access
2. Check SSH config: `sudo sshd -t`
3. Check firewall: `sudo ufw status`
4. Restart SSH: `sudo systemctl restart ssh`

### Docker-UFW Issues

If containers aren't accessible:

1. Check ufw-docker status: `sudo ufw-docker status`
2. Ensure container is running: `docker ps`
3. Add access rule: `sudo ufw-docker allow container_name port`

### Firewall Issues

To temporarily disable firewall:

```bash
sudo ufw disable
```

To reset firewall rules:

```bash
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp  # Or your SSH port
sudo ufw enable
```

## Advanced Usage

### Custom Module Development

Create new modules in the `modules/` directory:

```bash
#!/bin/bash
# modules/custom.sh

set -euo pipefail
source "$SCRIPT_DIR/utils.sh"

log "Starting Custom Module" "$BLUE"

# Your code here

log "Custom Module completed!" "$GREEN"
```

### Configuration Files

Future versions will support configuration files for automated setups:

```yaml
# config.yml (planned)
modules:
  - system_update
  - user_management:
      username: myuser
      ssh_key_url: https://github.com/myuser.keys
  - ssh_hardening:
      port: 2222
      enable_2fa: true
  - firewall:
      additional_ports:
        - 80/tcp
        - 443/tcp
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on a fresh VPS
5. Submit a pull request

## License

MIT License - See LICENSE file for details

## Support

- Report issues: https://github.com/albertsikkema/ubuntu-vps-setup/issues
- Documentation: https://github.com/albertsikkema/ubuntu-vps-setup/wiki

## Disclaimer

This tool makes significant changes to system configuration. Always:

1. Backup important data before running
2. Test on a non-production server first
3. Keep console access available
4. Document any custom configurations

The authors are not responsible for any damage or data loss resulting from the use of this tool.