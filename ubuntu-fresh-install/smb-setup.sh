#!/bin/bash

set -e

# Script: smb-setup.sh
# Description: Setup and configure Samba (SMB) file sharing on Ubuntu 24.04
# Usage: ./smb-setup.sh <share_name> <share_path> <username> <password> [--read-only]
#        curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/smb-setup.sh | bash -s -- share_name share_path username password [--read-only]
# 
# This script automates the setup of Samba file sharing on Ubuntu servers including:
# - Installing Samba packages
# - Creating and configuring shares
# - Setting up Samba users
# - Configuring firewall rules
# - Installing management tools
#
# DISCLAIMER: Use this script at your own risk. Always review scripts before running them on your server.

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    echo -e "\n${BLUE}=>${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Samba (SMB) Setup Script for Ubuntu 24.04

This script automates the setup of Samba file sharing on Ubuntu servers.

Usage:
  ./smb-setup.sh <share_name> <share_path> <username> <password> [--read-only]
  
  Or via curl:
  curl -fsSL <url> | bash -s -- share_name share_path username password [--read-only]

Parameters:
  share_name    Name of the SMB share (e.g., "shared", "documents")
  share_path    Path to share (e.g., "/srv/samba/shared")
  username      User for Samba access
  password      Password for Samba access
  --read-only   Make share read-only (optional)

Examples:
  ./smb-setup.sh shared /srv/samba/shared john mypassword
  ./smb-setup.sh documents /home/user/Documents user pass123 --read-only
  ./smb-setup.sh media /media/storage mediauser mediapass

What this script does:
  1. Installs Samba packages
  2. Creates share directory with proper permissions
  3. Configures SMB3 encryption and security settings
  4. Configures Samba share in smb.conf
  5. Sets up Samba user with password
  6. Configures UFW firewall rules for SMB
  7. Installs helper management scripts
  8. Starts and enables Samba services

Security Features:
  - SMB3 encryption enabled (AES-128) for all traffic
  - Legacy protocols (SMB1/SMB2) disabled
  - Message signing enforced
  - Anonymous access blocked
  - Authenticated access only
  - Security logging enabled

After setup, connect to the share:
  - Windows: \\\\server-ip\\share-name
  - macOS: smb://server-ip/share-name
  - Linux: smb://server-ip/share-name or mount via cifs

EOF
}

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "help" ]]; then
    show_help
    exit 0
fi

# Banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Ubuntu Samba (SMB) File Sharing Setup              ║"
echo "║                                                              ║"
echo "║  This script will setup Samba file sharing on your server   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root!"
   echo "Please run as a regular user with sudo privileges."
   exit 1
fi

# Check Ubuntu version
if ! grep -q "Ubuntu 24.04" /etc/os-release && ! grep -q "Ubuntu 22.04" /etc/os-release; then
    print_warning "This script is designed for Ubuntu 24.04/22.04"
    print_warning "Continuing anyway..."
fi

# Parse parameters
SHARE_NAME="${1:-}"
SHARE_PATH="${2:-}"
SMB_USER="${3:-}"
SMB_PASSWORD="${4:-}"
READ_ONLY=false

# Check for read-only flag
if [[ "$5" == "--read-only" ]]; then
    READ_ONLY=true
fi

# Validate required parameters
if [[ -z "$SHARE_NAME" ]] || [[ -z "$SHARE_PATH" ]] || [[ -z "$SMB_USER" ]] || [[ -z "$SMB_PASSWORD" ]]; then
    print_error "Missing required parameters"
    echo "Usage: $0 <share_name> <share_path> <username> <password> [--read-only]"
    echo "Example: $0 shared /srv/samba/shared john mypassword"
    exit 1
fi

# Validate share name (alphanumeric, underscore, hyphen only)
if ! [[ "$SHARE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    print_error "Share name must contain only letters, numbers, underscores, and hyphens"
    exit 1
fi

# Show configuration summary
echo -e "\n${BLUE}Configuration Summary:${NC}"
echo "  Share Name: $SHARE_NAME"
echo "  Share Path: $SHARE_PATH"
echo "  Samba User: $SMB_USER"
echo "  Read-only: $READ_ONLY"
echo

print_info "Starting Samba setup..."

# Step 1: Install Samba packages
print_step "Step 1/6: Installing Samba packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y samba samba-common-bin > /dev/null 2>&1; then
    print_success "Samba packages installed"
else
    print_error "Failed to install Samba packages"
    exit 1
fi

# Step 2: Create share directory
print_step "Step 2/6: Creating share directory"
if [[ ! -d "$SHARE_PATH" ]]; then
    sudo mkdir -p "$SHARE_PATH"
    print_success "Created directory: $SHARE_PATH"
else
    print_info "Directory already exists: $SHARE_PATH"
fi

# Set ownership and permissions
sudo chown -R "$SMB_USER:$SMB_USER" "$SHARE_PATH"
if [[ "$READ_ONLY" == true ]]; then
    sudo chmod -R 755 "$SHARE_PATH"
else
    sudo chmod -R 770 "$SHARE_PATH"
fi
print_success "Set permissions on share directory"

# Step 3: Configure Samba
print_step "Step 3/6: Configuring Samba"

# Backup original smb.conf
if [[ ! -f /etc/samba/smb.conf.bak ]]; then
    sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
    print_success "Backed up original smb.conf"
fi

# Configure global security settings for SMB3 encryption
print_info "Configuring SMB3 encryption and security settings..."
GLOBAL_SECURITY_CONFIG="
# SMB3 Security Configuration
   # Require SMB3 protocol minimum for encryption
   server min protocol = SMB3
   client min protocol = SMB3
   
   # Enable encryption for all connections
   smb encrypt = required
   
   # Enhanced security settings
   server signing = mandatory
   client signing = mandatory
   
   # Disable older, insecure protocols
   ntlm auth = no
   lanman auth = no
   
   # Additional security
   restrict anonymous = 2
   map to guest = Never
   
   # Performance optimization with encryption
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   
   # Security logging
   log file = /var/log/samba/log.%m
   max log size = 1000
   log level = 1 auth:3"

# Check if security config already exists
if ! sudo grep -q "# SMB3 Security Configuration" /etc/samba/smb.conf; then
    # Add security settings to [global] section
    sudo sed -i '/\[global\]/a\'"$GLOBAL_SECURITY_CONFIG" /etc/samba/smb.conf
    print_success "Added SMB3 encryption and security settings"
else
    print_info "SMB3 security configuration already present"
fi

# Create share configuration
SHARE_CONFIG="
[$SHARE_NAME]
   comment = Samba Share - $SHARE_NAME
   path = $SHARE_PATH
   browseable = yes
   read only = $(if [[ "$READ_ONLY" == true ]]; then echo "yes"; else echo "no"; fi)
   create mask = 0770
   directory mask = 0770
   valid users = $SMB_USER
   force user = $SMB_USER
   force group = $SMB_USER"

# Check if share already exists
if sudo grep -q "\\[$SHARE_NAME\\]" /etc/samba/smb.conf; then
    print_warning "Share [$SHARE_NAME] already exists in smb.conf"
    if [ -t 0 ]; then
        # Running interactively - ask for confirmation
        read -p "Overwrite existing configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Overwriting existing configuration..."
            # Remove existing share configuration
            sudo sed -i "/\\[$SHARE_NAME\\]/,/^\\[/{ /^\\[/!d }" /etc/samba/smb.conf
            sudo sed -i "/\\[$SHARE_NAME\\]/d" /etc/samba/smb.conf
        else
            print_warning "Skipping share configuration - share already exists"
            exit 0
        fi
    else
        # Running non-interactively (via curl) - automatically overwrite
        print_info "Overwriting existing configuration..."
        # Remove existing share configuration
        sudo sed -i "/\\[$SHARE_NAME\\]/,/^\\[/{ /^\\[/!d }" /etc/samba/smb.conf
        sudo sed -i "/\\[$SHARE_NAME\\]/d" /etc/samba/smb.conf
    fi
fi

# Add share configuration
echo "$SHARE_CONFIG" | sudo tee -a /etc/samba/smb.conf > /dev/null
print_success "Added share configuration to smb.conf"

# Test Samba configuration
if sudo testparm -s > /dev/null 2>&1; then
    print_success "Samba configuration is valid"
else
    print_error "Samba configuration test failed"
    print_info "Restoring backup..."
    sudo cp /etc/samba/smb.conf.bak /etc/samba/smb.conf
    exit 1
fi

# Step 4: Setup Samba user
print_step "Step 4/6: Setting up Samba user"

# Check if system user exists
if ! id "$SMB_USER" &>/dev/null; then
    print_info "System user '$SMB_USER' does not exist, creating..."
    sudo useradd -m -s /bin/bash "$SMB_USER"
    print_success "Created system user: $SMB_USER"
fi

# Setup Samba password
print_info "Setting Samba password for user: $SMB_USER"
if printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | sudo smbpasswd -a -s "$SMB_USER" > /dev/null 2>&1; then
    sudo smbpasswd -e "$SMB_USER" > /dev/null 2>&1
    print_success "Samba user configured"
else
    print_error "Failed to set Samba password"
    exit 1
fi

# Step 5: Configure firewall
print_step "Step 5/6: Configuring UFW firewall rules"

# Check if UFW is active
if sudo ufw status | grep -q "Status: active"; then
    # Add SMB/CIFS rules
    sudo ufw allow 445/tcp comment "Samba" > /dev/null 2>&1
    sudo ufw allow 139/tcp comment "Samba" > /dev/null 2>&1
    sudo ufw allow 137/udp comment "Samba" > /dev/null 2>&1
    sudo ufw allow 138/udp comment "Samba" > /dev/null 2>&1
    print_success "Added UFW rules for Samba"
else
    print_warning "UFW is not active - skipping firewall configuration"
fi

# Step 6: Install management scripts
print_step "Step 6/6: Installing management scripts"

# Create smb-status.sh
cat << 'EOF' | sudo tee /usr/local/bin/smb-status.sh > /dev/null
#!/bin/bash
# Samba status and information script

echo "=== Samba Service Status ==="
systemctl status smbd --no-pager | head -n 10
echo
echo "=== Active Connections ==="
sudo smbstatus -b 2>/dev/null || echo "No active connections"
echo
echo "=== Configured Shares ==="
sudo smbstatus -S 2>/dev/null || testparm -s 2>/dev/null | grep "^\[" | grep -v "^\[global\]" | grep -v "^\[printers\]" | grep -v "^\[print"
echo
echo "=== Samba Users ==="
sudo pdbedit -L -v | grep -E "^Unix|^User" | sed 'N;s/\n/ - /'
EOF

sudo chmod +x /usr/local/bin/smb-status.sh
print_success "Created /usr/local/bin/smb-status.sh"

# Create smb-users.sh
cat << 'EOF' | sudo tee /usr/local/bin/smb-users.sh > /dev/null
#!/bin/bash
# Samba user management script

show_help() {
    echo "Samba User Management"
    echo
    echo "Usage: smb-users.sh [command] [username]"
    echo
    echo "Commands:"
    echo "  list              List all Samba users"
    echo "  add <username>    Add a new Samba user"
    echo "  remove <username> Remove a Samba user"
    echo "  enable <username> Enable a Samba user"
    echo "  disable <username> Disable a Samba user"
    echo "  passwd <username> Change Samba password"
    echo
}

case "$1" in
    list)
        echo "=== Samba Users ==="
        sudo pdbedit -L
        ;;
    add)
        if [[ -z "$2" ]]; then
            echo "Error: Username required"
            show_help
            exit 1
        fi
        if ! id "$2" &>/dev/null; then
            echo "Error: System user '$2' does not exist"
            exit 1
        fi
        sudo smbpasswd -a "$2"
        ;;
    remove)
        if [[ -z "$2" ]]; then
            echo "Error: Username required"
            show_help
            exit 1
        fi
        sudo smbpasswd -x "$2"
        ;;
    enable)
        if [[ -z "$2" ]]; then
            echo "Error: Username required"
            show_help
            exit 1
        fi
        sudo smbpasswd -e "$2"
        ;;
    disable)
        if [[ -z "$2" ]]; then
            echo "Error: Username required"
            show_help
            exit 1
        fi
        sudo smbpasswd -d "$2"
        ;;
    passwd)
        if [[ -z "$2" ]]; then
            echo "Error: Username required"
            show_help
            exit 1
        fi
        sudo smbpasswd "$2"
        ;;
    *)
        show_help
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/smb-users.sh
print_success "Created /usr/local/bin/smb-users.sh"

# Restart Samba services
print_info "Restarting Samba services..."
sudo systemctl restart smbd nmbd
sudo systemctl enable smbd nmbd > /dev/null 2>&1
print_success "Samba services restarted and enabled"

# Final summary
echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Samba setup completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"

# Get IP address
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo -e "${BLUE}Share Information:${NC}"
echo "  Share Name: $SHARE_NAME"
echo "  Share Path: $SHARE_PATH"
echo "  Username: $SMB_USER"
echo "  Access: $(if [[ "$READ_ONLY" == true ]]; then echo "Read-only"; else echo "Read/Write"; fi)"
echo "  Security: SMB3 with AES encryption enabled"
echo

echo -e "${BLUE}Connect to your share:${NC}"
echo "  Windows:  \\\\$IP_ADDRESS\\$SHARE_NAME"
echo "  macOS:    smb://$IP_ADDRESS/$SHARE_NAME"
echo "  Linux:    smb://$IP_ADDRESS/$SHARE_NAME"
echo

echo -e "${BLUE}Management Commands:${NC}"
echo "  smb-status.sh  - Show Samba status and connections"
echo "  smb-users.sh   - Manage Samba users"
echo

echo -e "${BLUE}Useful Commands:${NC}"
echo "  sudo smbstatus          - Show current connections"
echo "  sudo testparm           - Test Samba configuration"
echo "  sudo systemctl status smbd   - Check Samba service"
echo "  sudo nano /etc/samba/smb.conf - Edit configuration"
echo

echo -e "${BLUE}Client Requirements for SMB3 Encryption:${NC}"
echo "  Windows: Windows 8/Server 2012 or newer"
echo "  macOS: macOS 10.10 (Yosemite) or newer"
echo "  Linux: Kernel 3.11+ with SMB3 support"
echo

echo -e "${BLUE}Verify Encryption is Working:${NC}"
echo "  Windows: Get-SmbConnection | Select ServerName,Encrypted"
echo "  Linux: sudo smbstatus -b (look for 'encrypted' flag)"
echo "  Logs: tail -f /var/log/samba/log.*"
echo

print_warning "Security Notes:"
echo "  ✓ SMB3 encryption is now enabled (AES-128)"
echo "  ✓ Legacy protocols (SMB1/SMB2) are disabled"
echo "  ✓ Message signing is enforced"
echo "  - Consider using VPN for internet access"
echo "  - Regularly check logs: /var/log/samba/"
echo "  - Keep Samba updated: sudo apt update && sudo apt upgrade"