# Ubuntu Fresh Install Scripts

Three scripts for setting up a fresh Ubuntu 24.04 server with security hardening, Docker, and file sharing capabilities. Make sure a user with sudo access is already setup, which is the default for installing Ubuntu Server from the official source: https://ubuntu.com/download/server.

## Quick Start

### 1. Generate SSH Keys (Client Machine)

```bash
# Download and run the key generator
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/generate-ssh-key.sh | bash

# Or download and run locally
wget https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/generate-ssh-key.sh
./generate-ssh-key.sh [server-ip] [username]
```

### 2. Setup Server (Ubuntu 24.04 Server)

```bash
# Download and run the server setup script
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/ubuntu-setup.sh | bash -s -- <username> "<ssh-public-key>"

# Or download and run locally
wget https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/ubuntu-setup.sh
chmod +x ubuntu-setup.sh
./ubuntu-setup.sh <username> "<ssh-public-key>"
```

### 3. Setup SMB File Sharing (Optional)

```bash
# Download and run the SMB setup script
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/smb-setup.sh | bash -s -- <share_name> <share_path> [username] [--read-only]

# Or download and run locally
wget https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/smb-setup.sh
chmod +x smb-setup.sh
./smb-setup.sh shared /srv/samba/shared
```

## What Gets Configured

### Security
- ✅ SSH hardening (disable root login, password auth)
- ✅ UFW firewall with Docker integration
- ✅ SSH key-only authentication
- ✅ Connection limits and timeouts

### Software
- ✅ System updates and essential packages
- ✅ Docker Engine and Docker Compose
- ✅ UFW-Docker integration for container isolation

### Network
- ✅ UFW firewall (ports 22, 80, 443 open)
- ✅ Docker containers isolated by default
- ✅ Easy container port management
- ✅ SMB/CIFS ports configured when using SMB setup

### File Sharing (Optional)
- ✅ Samba (SMB/CIFS) server installation
- ✅ Authenticated file sharing
- ✅ Read-only and read-write share options
- ✅ SMB user management tools

## Usage Examples

### Generate Keys for Specific Server
```bash
./generate-ssh-key.sh 192.168.1.100 myuser
```

### Setup Server with Generated Key
```bash
# Copy the public key from the output above, then:
./ubuntu-setup.sh myuser "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... myuser@192.168.1.100"
```

### Manage Docker Container Firewall
```bash
# After setup, use these commands on the server:
docker-firewall.sh allow nginx 80        # Allow HTTP to nginx container
docker-firewall.sh allow mysql 3306      # Allow MySQL access
docker-firewall.sh delete nginx          # Remove nginx firewall rules
docker-firewall.sh list                  # Show all rules
```

### Setup SMB File Sharing
```bash
# Create a read-write share
./smb-setup.sh shared /srv/samba/shared

# Create a read-only share for specific user
./smb-setup.sh documents /home/john/Documents john --read-only

# Interactive mode (prompts for parameters)
./smb-setup.sh
```

## UFW-Docker Integration

This setup includes **ufw-docker** - a critical security tool that fixes the Docker and UFW security flaw without disabling iptables.

### The Problem
By default, Docker bypasses UFW firewall rules by directly manipulating iptables. This means:
- Published Docker ports (`-p 8080:80`) are accessible from anywhere, regardless of UFW settings
- UFW rules like `ufw deny 8080` have no effect on Docker containers
- This creates a significant security vulnerability

### The Solution: ufw-docker
The setup automatically installs [ufw-docker](https://github.com/chaifeng/ufw-docker) which:
- ✅ **Integrates UFW with Docker**: Makes Docker respect UFW firewall rules
- ✅ **Container Isolation**: Docker containers are blocked from external access by default
- ✅ **Granular Control**: Allow specific container ports only when needed
- ✅ **Maintains Performance**: No need to disable Docker's iptables feature

### How It Works
```bash
# Without ufw-docker (INSECURE):
docker run -p 8080:80 nginx    # Port 8080 accessible from anywhere!
ufw deny 8080                  # This rule is ignored by Docker

# With ufw-docker (SECURE):
docker run -p 8080:80 nginx               # Port 8080 blocked by default
docker-firewall.sh allow nginx 80         # Explicitly allow access
# or: ufw-docker allow nginx 80           # Direct ufw-docker command
```

### Direct ufw-docker Commands
```bash
# Allow container port access
ufw-docker allow container_name port

# Examples:
ufw-docker allow nginx 80         # Allow HTTP to nginx
ufw-docker allow api-server 3000  # Allow API access
ufw-docker allow database 5432    # Allow PostgreSQL access

# Remove container access
ufw-docker delete allow container_name

# List Docker firewall rules
ufw-docker list
```

## Management Scripts (Installed on Server)

### Docker & Firewall
- `docker-status.sh` - Docker system status
- `ufw-status.sh` - Firewall status and rules
- `docker-firewall.sh` - Docker container firewall management

### SMB/File Sharing (if installed)
- `smb-status.sh` - Samba service status and active connections
- `smb-users.sh` - Manage Samba users (add, remove, enable, disable)

## Requirements

### Client Machine
- Bash shell
- `curl` or `wget`
- SSH client

### Server
- Fresh Ubuntu 24.04 installation
- User account already created
- Sudo privileges for the user
- Internet connection

## Security Features

- 🔒 Root SSH login disabled
- 🔒 Password authentication disabled  
- 🔒 SSH key-only authentication
- 🔒 UFW firewall enabled
- 🔒 Docker containers isolated by default
- 🔒 Connection limits and session timeouts
- 🔒 Comprehensive security logging

## Troubleshooting

### Locked Out of SSH
1. Use your server provider's console/VNC access
2. Restore SSH config: `sudo cp /etc/ssh/sshd_config.original /etc/ssh/sshd_config`
3. Restart SSH: `sudo systemctl restart ssh`

### Docker Permission Issues
```bash
# Add user to docker group (if not done automatically)
sudo usermod -aG docker $USER
newgrp docker
```

### Firewall Issues
```bash
# Check UFW status
sudo ufw status verbose

# Reset UFW if needed
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing  
sudo ufw allow 22/tcp
sudo ufw --force enable
```

### SMB Connection Issues
```bash
# Check Samba status
sudo systemctl status smbd nmbd

# View Samba logs
sudo tail -f /var/log/samba/log.smbd

# Test configuration
sudo testparm

# List active connections
sudo smbstatus
```

### Connect to SMB Shares
```bash
# Windows
\\server-ip\share-name

# macOS
smb://server-ip/share-name

# Linux (command line)
smbclient //server-ip/share-name -U username

# Linux (mount)
sudo mount -t cifs //server-ip/share-name /mnt/point -o username=user
```

## ⚠️ Disclaimer

**IMPORTANT: USE AT YOUR OWN RISK**

- These scripts are provided "as is" without warranty of any kind
- **NOT intended for production environments** without thorough testing
- The authors are **NOT responsible** for any damage, data loss, or security breaches
- These scripts modify critical system security settings
- **Always test on non-production servers first**
- Ensure you have alternative access methods before running
- Review and understand all code before execution
- Use of these scripts is entirely at your own risk

**Production Recommendations:**
- Perform comprehensive testing in staging environments
- Have backup and recovery procedures in place
- Review all security configurations for your specific requirements
- Consider professional security auditing for production deployments

## License

MIT License - Feel free to modify and distribute.
