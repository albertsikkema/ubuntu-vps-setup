# Ubuntu Fresh Install Scripts

Two scripts for setting up a fresh Ubuntu 24.04 server with security hardening and Docker.

## Quick Start

### 1. Generate SSH Keys (Client Machine)

```bash
# Download and run the key generator
curl -fsSL https://raw.githubusercontent.com/ubuntu-vps-setup/server_install/refs/heads/main/generate-ssh-key.sh | bash

# Or download and run locally
wget https://raw.githubusercontent.com/ubuntu-vps-setup/refs/heads/main/generate-ssh-key.sh
./generate-ssh-key.sh [server-ip] [username]
```

### 2. Setup Server (Ubuntu 24.04 Server)

```bash
# Download and run the server setup script
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/refs/heads/main/ubuntu-fresh-install/ubuntu-setup.sh | bash -s -- <username> "<ssh-public-key>"

# Or download and run locally
wget https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/refs/heads/main/ubuntu-fresh-install/ubuntu-setup.sh
chmod +x ubuntu-setup.sh
./ubuntu-setup.sh <username> "<ssh-public-key>"
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

## Management Scripts (Installed on Server)

- `docker-status.sh` - Docker system status
- `ufw-status.sh` - Firewall status and rules
- `docker-firewall.sh` - Docker container firewall management

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

## License

MIT License - Feel free to modify and distribute.