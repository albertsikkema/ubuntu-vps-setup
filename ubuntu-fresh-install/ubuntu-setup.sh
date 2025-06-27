#!/bin/bash

set -e

# Ubuntu 24.04 Server Setup Script
# This script performs initial setup and hardening of an Ubuntu 24.04 server
# Usage: ./ubuntu-setup.sh <username> "<ssh-public-key>"
# Or with curl: curl -fsSL <raw-github-url>/ubuntu-setup.sh | bash -s -- <username> "<ssh-public-key>"
#
# ⚠️  DISCLAIMER: USE AT YOUR OWN RISK
# This script is provided "as is" without warranty. NOT intended for production
# environments without thorough testing. Authors are NOT responsible for any
# damage, data loss, or security breaches. Always test on non-production servers first.

echo "======================================"
echo "Ubuntu 24.04 Server Setup Script"
echo "======================================"
echo "This script will:"
echo "- Update and upgrade the system"
echo "- Setup SSH keys for secure access"
echo "- Harden SSH configuration"
echo "- Install Docker and Docker Compose"
echo "- Setup UFW firewall with Docker integration"
echo "======================================"
echo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to show help
show_help() {
    echo "Ubuntu 24.04 Server Setup Script"
    echo
    echo "Usage:"
    echo "  $0 <username> \"<ssh-public-key>\""
    echo
    echo "Parameters:"
    echo "  username        - The existing user account to configure"
    echo "  ssh-public-key  - Your SSH public key for authentication"
    echo
    echo "Examples:"
    echo "  $0 myuser \"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@example.com\""
    echo
    echo "Or download and run directly:"
    echo "  curl -fsSL <github-raw-url>/ubuntu-setup.sh | bash -s -- myuser \"ssh-ed25519 AAAAC3...\""
    exit 0
}

# Check for help flags
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "help" ]; then
    show_help
fi

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "This script should not be run as root!"
    print_warning "Please run as a regular user with sudo privileges"
    exit 1
fi

# Get parameters
USERNAME=${1:-$USER}
SSH_PUBLIC_KEY="$2"

# Validate username
if [ -z "$USERNAME" ]; then
    print_error "Username not provided"
    echo "Usage: $0 <username> \"<ssh-public-key>\""
    echo "Run '$0 --help' for more information"
    exit 1
fi

# Check if user exists
if ! id "$USERNAME" &>/dev/null; then
    print_error "User '$USERNAME' does not exist"
    exit 1
fi

# If no SSH key provided, prompt for it
if [ -z "$SSH_PUBLIC_KEY" ]; then
    echo "No SSH public key provided as parameter."
    echo "Please paste your SSH public key (it should start with 'ssh-' or 'ecdsa-' or 'ed25519-'):"
    read -r SSH_PUBLIC_KEY
    
    if [ -z "$SSH_PUBLIC_KEY" ]; then
        print_error "No SSH public key provided"
        exit 1
    fi
fi

# Validate SSH key format
if ! echo "$SSH_PUBLIC_KEY" | grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) '; then
    print_error "Invalid SSH public key format"
    exit 1
fi

echo
echo "Configuration Summary:"
echo "====================="
echo "Username: $USERNAME"
echo "SSH Key: ${SSH_PUBLIC_KEY:0:50}..."
echo
echo -n "Proceed with setup? (y/N): "
read -r CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Setup cancelled."
    exit 0
fi

echo
echo "Starting server setup..."
echo

# ========================================
# Step 1: System Update and Upgrade
# ========================================
echo "========================================="
echo "Step 1: System Update and Upgrade"
echo "========================================="

echo "Updating package lists..."
sudo apt-get update -y

echo "Upgrading system packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "Installing essential packages..."
sudo apt-get install -y \
    curl \
    wget \
    unzip \
    net-tools \
    htop \
    vim \
    git \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    ufw

# Clean up
echo "Cleaning up package cache..."
sudo apt-get autoremove -y
sudo apt-get autoclean

print_success "System update completed successfully!"
echo

# ========================================
# Step 2: SSH Key Setup
# ========================================
echo "========================================="
echo "Step 2: SSH Key Setup"
echo "========================================="

USER_HOME=$(eval echo ~$USERNAME)
SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

echo "Setting up SSH key for user: $USERNAME"

# Create .ssh directory if it doesn't exist
if [ ! -d "$SSH_DIR" ]; then
    echo "Creating .ssh directory..."
    mkdir -p "$SSH_DIR"
fi

# Create authorized_keys file if it doesn't exist
if [ ! -f "$AUTHORIZED_KEYS" ]; then
    touch "$AUTHORIZED_KEYS"
fi

# Check if key already exists
if grep -Fq "$SSH_PUBLIC_KEY" "$AUTHORIZED_KEYS" 2>/dev/null; then
    print_warning "SSH key already exists in authorized_keys"
else
    echo "Adding SSH key to authorized_keys..."
    echo "$SSH_PUBLIC_KEY" >> "$AUTHORIZED_KEYS"
    print_success "SSH key added successfully"
fi

# Set proper permissions
chmod 700 "$SSH_DIR"
chmod 600 "$AUTHORIZED_KEYS"

# Set ownership if we're running with sudo
if [ "$USER" != "$USERNAME" ]; then
    sudo chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
fi

print_success "SSH key setup completed!"
echo

# ========================================
# Step 3: SSH Hardening
# ========================================
echo "========================================="
echo "Step 3: SSH Hardening"
echo "========================================="

echo "🔒 Hardening SSH configuration..."

# Backup SSH config
if [ ! -f /etc/ssh/sshd_config.backup ]; then
    echo "Creating backup of SSH configuration..."
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
fi

# Also create an "original" backup for emergency recovery
if [ ! -f /etc/ssh/sshd_config.original ]; then
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.original
fi

# Create hardened SSH configuration
echo "Creating hardened SSH configuration..."
sudo tee /etc/ssh/sshd_config > /dev/null << EOF
# SSH Hardened Configuration
# Generated by Ubuntu Setup Script

# Network Settings
Port 22
AddressFamily inet
ListenAddress 0.0.0.0

# Protocol and Encryption
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Security Settings
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Login Settings
LoginGraceTime 30
MaxAuthTries 3
MaxSessions 3
MaxStartups 10:30:60

# User Access Control
AllowUsers $USERNAME
DenyUsers root

# Session Settings
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive yes

# Disable Dangerous Features
PermitEmptyPasswords no
PermitUserEnvironment no
AllowAgentForwarding yes
AllowTcpForwarding yes
GatewayPorts no
X11Forwarding no
PrintMotd no
PrintLastLog yes

# Logging
SyslogFacility AUTHPRIV
LogLevel VERBOSE

# SFTP Settings
Subsystem sftp /usr/lib/openssh/sftp-server -l INFO

# Banner
Banner /etc/ssh/banner

EOF

# Create SSH banner with hostname and IP
echo "Creating SSH banner..."
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
sudo tee /etc/ssh/banner > /dev/null << EOF
================================================================================
                        🏠 Welcome to $HOSTNAME! 🏠
================================================================================

Hello! You've successfully connected to server $HOSTNAME ($IP_ADDRESS).

Enjoy your stay!

================================================================================
EOF

# Test SSH configuration
echo "Testing SSH configuration..."
if sudo sshd -t; then
    print_success "SSH configuration test passed"
else
    print_error "SSH configuration test failed, restoring original"
    sudo cp /etc/ssh/sshd_config.original /etc/ssh/sshd_config
    exit 1
fi

# Restart SSH service
echo "Restarting SSH service..."
sudo systemctl restart ssh

# Verify SSH service is running
if systemctl is-active --quiet ssh; then
    print_success "SSH service restarted successfully"
else
    print_error "SSH service failed to start, restoring original configuration"
    sudo cp /etc/ssh/sshd_config.original /etc/ssh/sshd_config
    sudo systemctl restart ssh
    exit 1
fi

print_success "SSH hardening completed!"

echo
echo "🔐 SSH Security Summary:"
echo "========================"
print_success "Root login disabled"
print_success "Password authentication disabled"
print_success "Key-based authentication only"
print_success "User access restricted to: $USERNAME"
print_success "Connection limits configured"
print_success "Session timeouts configured"
print_success "Verbose logging enabled"
echo

# ========================================
# Step 4: Docker Installation
# ========================================
echo "========================================="
echo "Step 4: Docker Installation"
echo "========================================="

# Check if Docker is already installed
if command -v docker >/dev/null 2>&1; then
    echo "Docker is already installed:"
    docker --version
    print_warning "Skipping Docker installation"
else
    echo "Installing Docker..."
    
    # Install prerequisite packages
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    echo "Adding Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index
    sudo apt-get update -y
    
    # Install Docker Engine, CLI, and plugins
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    print_success "Docker installed successfully"
fi

# Verify Docker installation
echo "Verifying Docker installation..."
docker --version
docker compose version

# Add user to docker group
echo "Adding user $USERNAME to docker group..."
sudo usermod -aG docker "$USERNAME"

# Enable Docker service
echo "Enabling Docker service..."
sudo systemctl enable docker.service
sudo systemctl enable containerd.service

# Start Docker service
echo "Starting Docker service..."
sudo systemctl start docker

# Configure Docker daemon with security settings
echo "Configuring Docker daemon..."
sudo mkdir -p /etc/docker

sudo tee /etc/docker/daemon.json > /dev/null << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "storage-driver": "overlay2"
}
EOF

# Restart Docker to apply configuration
echo "Restarting Docker with new configuration..."
sudo systemctl restart docker

# Wait for Docker to be ready
sleep 5

# Test Docker installation
echo "Testing Docker installation..."
sudo docker run --rm hello-world

print_success "Docker installation completed!"
echo

# ========================================
# Step 5: UFW Firewall + Docker Integration
# ========================================
echo "========================================="
echo "Step 5: UFW Firewall + Docker Integration"
echo "========================================="

echo "Setting up UFW firewall with Docker integration..."

# Reset UFW to default state
echo "Resetting UFW to defaults..."
sudo ufw --force reset

# Set default policies
echo "Setting default UFW policies..."
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow essential services
echo "Configuring UFW rules..."

# Allow SSH (port 22)
sudo ufw allow 22/tcp comment 'SSH'

# Allow HTTP (port 80)
sudo ufw allow 80/tcp comment 'HTTP'

# Allow HTTPS (port 443)
sudo ufw allow 443/tcp comment 'HTTPS'

# Enable UFW first (required for ufw-docker integration)
echo "Enabling UFW firewall..."
sudo ufw --force enable

# Download and install ufw-docker script
echo "Installing ufw-docker integration..."
sudo wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
sudo chmod +x /usr/local/bin/ufw-docker

# Install ufw-docker configuration (now that UFW is enabled)
echo "Configuring ufw-docker integration..."
sudo /usr/local/bin/ufw-docker install

# Create backup of UFW rules
echo "Creating backup of UFW configuration..."
sudo cp /etc/ufw/after.rules /etc/ufw/after.rules.backup

# Verify UFW status
echo "Checking UFW status..."
sudo ufw status verbose

# Create UFW management script
echo "Creating UFW management script..."
sudo tee /usr/local/bin/ufw-status.sh > /dev/null << 'EOF'
#!/bin/bash
echo "=== UFW Firewall Status Report ==="
echo "Date: $(date)"
echo
echo "UFW Status:"
ufw status verbose
echo
echo "UFW Application Profiles:"
ufw app list 2>/dev/null || echo "No application profiles available"
echo
echo "Docker Integration:"
if [ -x "/usr/local/bin/ufw-docker" ]; then
    echo "✅ ufw-docker tool is installed"
    echo "Available commands:"
    echo "  - ufw-docker allow <container> <port>"
    echo "  - ufw-docker delete allow <container>"
    echo "  - ufw-docker list"
else
    echo "❌ ufw-docker tool is not installed"
fi
echo
echo "Active Docker Containers:"
if command -v docker >/dev/null 2>&1; then
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" 2>/dev/null || echo "Docker not running or no containers"
else
    echo "Docker not installed"
fi
echo
echo "UFW Rules:"
iptables -L -n | grep -E "(Chain|ACCEPT|DROP|REJECT)" | head -20
EOF

sudo chmod +x /usr/local/bin/ufw-status.sh

# Create Docker container firewall helper script
echo "Creating Docker firewall management script..."
sudo tee /usr/local/bin/docker-firewall.sh > /dev/null << 'EOF'
#!/bin/bash

# Docker UFW Firewall Management Script

show_help() {
    echo "Docker UFW Firewall Management"
    echo "Usage: $0 [command] [options]"
    echo
    echo "Commands:"
    echo "  allow <container> <port>     - Allow access to container port"
    echo "  deny <container> <port>      - Deny access to container port"
    echo "  delete <container>           - Remove all rules for container"
    echo "  list                         - List all docker firewall rules"
    echo "  status                       - Show firewall and docker status"
    echo "  help                         - Show this help message"
    echo
    echo "Examples:"
    echo "  $0 allow nginx 80            - Allow HTTP access to nginx container"
    echo "  $0 allow mysql 3306          - Allow MySQL access"
    echo "  $0 delete nginx              - Remove all nginx firewall rules"
    echo "  $0 list                      - Show all current rules"
}

case "$1" in
    allow)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Error: Missing container name or port"
            echo "Usage: $0 allow <container> <port>"
            exit 1
        fi
        echo "Allowing access to container '$2' on port '$3'"
        ufw-docker allow "$2" "$3"
        ;;
    deny)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Error: Missing container name or port"
            echo "Usage: $0 deny <container> <port>"
            exit 1
        fi
        echo "Denying access to container '$2' on port '$3'"
        ufw-docker deny "$2" "$3"
        ;;
    delete)
        if [ -z "$2" ]; then
            echo "Error: Missing container name"
            echo "Usage: $0 delete <container>"
            exit 1
        fi
        echo "Removing all firewall rules for container '$2'"
        ufw-docker delete allow "$2"
        ;;
    list)
        echo "Current Docker UFW rules:"
        ufw status | grep -i docker || echo "No Docker-specific rules found"
        echo
        echo "All UFW rules:"
        ufw status numbered
        ;;
    status)
        /usr/local/bin/ufw-status.sh
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo
        show_help
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/docker-firewall.sh

# Create Docker status script
echo "Creating Docker status script..."
sudo tee /usr/local/bin/docker-status.sh > /dev/null << 'EOF'
#!/bin/bash
echo "=== Docker Status Report ==="
echo "Date: $(date)"
echo
echo "Docker Version:"
docker --version
docker compose version
echo
echo "Service Status:"
systemctl is-active docker && echo "✅ Docker service is running" || echo "❌ Docker service is not running"
systemctl is-active containerd && echo "✅ Containerd service is running" || echo "❌ Containerd service is not running"
echo
echo "Docker System Information:"
docker system df
echo
echo "Running Containers:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo
echo "Docker Images:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
echo
echo "Docker Networks:"
docker network ls
echo
echo "Docker Volumes:"
docker volume ls
EOF

sudo chmod +x /usr/local/bin/docker-status.sh

# Test the integration
echo "Testing UFW and Docker integration..."

# Check if Docker is running
if systemctl is-active --quiet docker; then
    print_success "Docker service is running"
    
    # Test ufw-docker command
    if sudo /usr/local/bin/ufw-docker list >/dev/null 2>&1; then
        print_success "ufw-docker integration is working"
    else
        print_warning "ufw-docker integration test failed, but installation completed"
    fi
else
    print_warning "Docker service is not running, skipping integration test"
fi

print_success "UFW + Docker integration setup completed!"
echo

# ========================================
# Final Summary
# ========================================
echo "========================================="
echo "🎉 Server Setup Complete!"
echo "========================================="
echo
echo "✅ System updated and upgraded"
echo "✅ SSH key configured for user: $USERNAME"
echo "✅ SSH hardened with security settings"
echo "✅ Docker and Docker Compose installed"
echo "✅ UFW firewall configured with Docker integration"
echo

echo "🔥 Firewall Configuration:"
echo "=========================="
print_success "UFW firewall enabled and configured"
print_success "Default policy: deny incoming, allow outgoing"
print_success "SSH access allowed (port 22)"
print_success "HTTP access allowed (port 80)"
print_success "HTTPS access allowed (port 443)"
print_success "Docker integration installed (ufw-docker)"
print_success "Docker containers isolated by default"
echo

echo "📝 Important Notes:"
echo "==================="
echo "1. SSH Access:"
echo "   - Only user '$USERNAME' can SSH to this server"
echo "   - Password authentication is disabled"
echo "   - Use your SSH key to connect"
echo
echo "2. Docker:"
echo "   - User '$USERNAME' has been added to docker group"
echo "   - Log out and back in for group changes to take effect"
echo "   - Or run: newgrp docker"
echo
echo "3. Firewall:"
echo "   - UFW is enabled with Docker integration"
echo "   - Docker containers are isolated by default"
echo "   - Use 'docker-firewall.sh' to manage container access"
echo "   - Use 'ufw-docker allow <container> <port>' to expose ports"
echo
echo "4. Security:"
echo "   - Root SSH access is completely disabled"
echo "   - Failed login attempts are limited"
echo "   - SSH config backup: /etc/ssh/sshd_config.backup"
echo "   - Emergency restore: /etc/ssh/sshd_config.original"
echo

echo "🛠️  Useful Commands:"
echo "===================="
echo "System status:        systemctl status ssh docker"
echo "Docker status:        docker-status.sh"
echo "Firewall status:      ufw-status.sh"
echo "Docker firewall:      docker-firewall.sh help"
echo "View SSH logs:        sudo journalctl -u ssh"
echo "View UFW logs:        sudo journalctl -u ufw"
echo

echo "🐳 Docker Firewall Examples:"
echo "============================"
echo "Allow HTTP to nginx:  docker-firewall.sh allow nginx 80"
echo "Allow MySQL access:   docker-firewall.sh allow mysql 3306"
echo "Remove nginx rules:   docker-firewall.sh delete nginx"
echo "List all rules:       docker-firewall.sh list"
echo

print_warning "IMPORTANT: Make sure you can connect with your SSH key before closing this session!"
echo
echo "Setup completed at: $(date)"
echo