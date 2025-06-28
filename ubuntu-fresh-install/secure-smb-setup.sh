#!/bin/bash

set -e

# Script: secure-smb-setup.sh
# Description: Configure Samba with SMB3 encryption for secure file sharing
# Usage: ./secure-smb-setup.sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

echo -e "${BLUE}Configuring Samba for encrypted SMB3 connections...${NC}\n"

# Backup current config
if [[ ! -f /etc/samba/smb.conf.secure-backup ]]; then
    sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.secure-backup
    print_success "Backed up original configuration"
fi

# Create secure global configuration
SECURE_CONFIG="
# SMB3 Encryption Configuration
[global]
    # Require SMB3 protocol minimum
    server min protocol = SMB3
    client min protocol = SMB3
    
    # Require encryption for all connections
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
    
    # Performance with encryption
    socket options = TCP_NODELAY IPTOS_LOWDELAY
    
    # Logging for security auditing
    log file = /var/log/samba/log.%m
    max log size = 1000
    log level = 1 auth:3
"

# Apply secure configuration
print_info "Applying SMB3 encryption configuration..."
if sudo grep -q "# SMB3 Encryption Configuration" /etc/samba/smb.conf; then
    print_warning "Encryption config already exists, updating..."
    # Remove old encryption config
    sudo sed -i '/# SMB3 Encryption Configuration/,/^$/d' /etc/samba/smb.conf
fi

# Insert at the beginning of [global] section
sudo sed -i '/\[global\]/a\'"$SECURE_CONFIG" /etc/samba/smb.conf

# Test configuration
if sudo testparm -s > /dev/null 2>&1; then
    print_success "Configuration is valid"
else
    print_error "Configuration test failed"
    sudo cp /etc/samba/smb.conf.secure-backup /etc/samba/smb.conf
    exit 1
fi

# Restart Samba
sudo systemctl restart smbd nmbd
print_success "Samba restarted with encryption enabled"

echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ SMB3 Encryption Configured Successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}What this configuration provides:${NC}"
echo "  • All SMB traffic is encrypted (AES-128-CCM/AES-128-GCM)"
echo "  • Only SMB3 protocol or higher allowed"
echo "  • Message signing enforced"
echo "  • Legacy authentication disabled"
echo "  • Anonymous access blocked"
echo

echo -e "${YELLOW}Client Requirements:${NC}"
echo "  • Windows 8/Server 2012 or newer"
echo "  • macOS 10.10 (Yosemite) or newer"
echo "  • Linux with SMB3 support (kernel 3.11+)"
echo

echo -e "${YELLOW}Testing encryption:${NC}"
echo "  Windows:  Get-SmbConnection | Select ServerName,Encrypted"
echo "  Linux:    smbstatus -b (look for 'encrypted' flag)"
echo "  macOS:    smbutil statshares -a"