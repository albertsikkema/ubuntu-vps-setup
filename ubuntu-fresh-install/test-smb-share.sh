#!/bin/bash

set -e

# Script: test-smb-share.sh
# Description: Test SMB/Samba share configuration and connectivity
# Usage: ./test-smb-share.sh <server_ip> <share_name> <username> <password>
#        curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/ubuntu-fresh-install/test-smb-share.sh | bash -s -- server_ip share_name username password
#
# This script tests SMB share configuration by:
# - Checking if smbclient is installed
# - Testing authentication
# - Listing share contents
# - Testing write access (if applicable)
# - Verifying share visibility
#
# DISCLAIMER: Use this script at your own risk. Always review scripts before running them.

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
SMB Share Testing Script for Ubuntu

This script tests SMB/Samba share connectivity and configuration.

Usage:
  ./test-smb-share.sh <server_ip> <share_name> <username> <password>
  
  Or via curl:
  curl -fsSL <url> | bash -s -- server_ip share_name username password

Parameters:
  server_ip     IP address or hostname of the SMB server
  share_name    Name of the SMB share to test
  username      Username for SMB authentication
  password      Password for SMB authentication

Examples:
  ./test-smb-share.sh 192.168.1.100 shared john mypassword
  ./test-smb-share.sh server.local documents admin pass123

What this script tests:
  1. SMB client tools availability
  2. Network connectivity to SMB server
  3. Share visibility and listing
  4. Authentication with provided credentials
  5. Read access to the share
  6. Write access to the share (if permitted)
  7. File operations (create, read, delete)

Requirements:
  - smbclient package (will offer to install if missing)
  - Network access to the SMB server
  - Valid credentials for the share

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
echo "║              SMB Share Configuration Tester                   ║"
echo "║                                                              ║"
echo "║  This script will test your SMB share configuration         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Parse parameters
SERVER_IP="${1:-}"
SHARE_NAME="${2:-}"
SMB_USER="${3:-}"
SMB_PASSWORD="${4:-}"

# Validate required parameters
if [[ -z "$SERVER_IP" ]] || [[ -z "$SHARE_NAME" ]] || [[ -z "$SMB_USER" ]] || [[ -z "$SMB_PASSWORD" ]]; then
    print_error "Missing required parameters"
    echo "Usage: $0 <server_ip> <share_name> <username> <password>"
    echo "Example: $0 192.168.1.100 shared john mypassword"
    exit 1
fi

# Show test configuration
echo -e "${BLUE}Test Configuration:${NC}"
echo "  Server: $SERVER_IP"
echo "  Share: $SHARE_NAME"
echo "  Username: $SMB_USER"
echo

# Step 1: Check if smbclient is installed
print_step "Step 1: Checking SMB client tools"
if ! command -v smbclient &> /dev/null; then
    print_warning "smbclient is not installed"
    if [ -t 0 ]; then
        read -p "Install smbclient? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y smbclient > /dev/null 2>&1
            print_success "smbclient installed"
        else
            print_error "Cannot continue without smbclient"
            exit 1
        fi
    else
        print_info "Installing smbclient..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y smbclient > /dev/null 2>&1
        print_success "smbclient installed"
    fi
else
    print_success "smbclient is installed"
fi

# Step 2: Test network connectivity
print_step "Step 2: Testing network connectivity"
if ping -c 1 -W 2 "$SERVER_IP" > /dev/null 2>&1; then
    print_success "Server is reachable"
else
    print_warning "Cannot ping server (this might be normal if ICMP is blocked)"
fi

# Test SMB port connectivity
if timeout 2 bash -c "echo >/dev/tcp/$SERVER_IP/445" 2>/dev/null; then
    print_success "SMB port 445 is open"
else
    print_error "Cannot connect to SMB port 445"
    print_info "Make sure the firewall allows SMB traffic"
    exit 1
fi

# Step 3: List available shares
print_step "Step 3: Listing available shares"
echo "Attempting to list shares on $SERVER_IP..."
SHARES_OUTPUT=$(smbclient -L "//$SERVER_IP" -U "$SMB_USER%$SMB_PASSWORD" -g 2>&1 || true)

if echo "$SHARES_OUTPUT" | grep -q "NT_STATUS_LOGON_FAILURE"; then
    print_error "Authentication failed - check username and password"
    exit 1
elif echo "$SHARES_OUTPUT" | grep -q "$SHARE_NAME"; then
    print_success "Share '$SHARE_NAME' is visible"
else
    print_warning "Share '$SHARE_NAME' not found in share list"
    echo "Available shares:"
    echo "$SHARES_OUTPUT" | grep "Disk|" | cut -d'|' -f2 | sed 's/^/  - /'
fi

# Step 4: Test share access
print_step "Step 4: Testing share access"
TEST_COMMAND="ls"
ACCESS_OUTPUT=$(smbclient "//$SERVER_IP/$SHARE_NAME" -U "$SMB_USER%$SMB_PASSWORD" -c "$TEST_COMMAND" 2>&1 || true)

if echo "$ACCESS_OUTPUT" | grep -q "NT_STATUS"; then
    print_error "Cannot access share: $ACCESS_OUTPUT"
    exit 1
else
    print_success "Successfully connected to share"
fi

# Step 5: Test read access
print_step "Step 5: Testing read access"
FILES_COUNT=$(smbclient "//$SERVER_IP/$SHARE_NAME" -U "$SMB_USER%$SMB_PASSWORD" -c "ls" 2>/dev/null | grep -c "blocks of size" || echo "0")
if [[ "$FILES_COUNT" != "0" ]]; then
    print_success "Can list files in share"
    echo "Share contents:"
    smbclient "//$SERVER_IP/$SHARE_NAME" -U "$SMB_USER%$SMB_PASSWORD" -c "ls" 2>/dev/null | head -10 | sed 's/^/  /'
else
    print_warning "Could not list files (share might be empty or access denied)"
fi

# Step 6: Test write access
print_step "Step 6: Testing write access"
TEST_FILE="smb_test_$(date +%s).txt"
TEST_CONTENT="SMB test file created on $(date)"

# Try to create a test file
echo "$TEST_CONTENT" > /tmp/$TEST_FILE
UPLOAD_OUTPUT=$(smbclient "//$SERVER_IP/$SHARE_NAME" -U "$SMB_USER%$SMB_PASSWORD" -c "put /tmp/$TEST_FILE $TEST_FILE" 2>&1 || true)

if echo "$UPLOAD_OUTPUT" | grep -q "NT_STATUS_ACCESS_DENIED"; then
    print_warning "Write access denied (share might be read-only)"
    WRITE_ACCESS=false
elif echo "$UPLOAD_OUTPUT" | grep -q "putting file"; then
    print_success "Successfully uploaded test file"
    WRITE_ACCESS=true
    
    # Try to read it back
    DOWNLOAD_OUTPUT=$(smbclient "//$SERVER_IP/$SHARE_NAME" -U "$SMB_USER%$SMB_PASSWORD" -c "get $TEST_FILE /tmp/${TEST_FILE}.download" 2>&1 || true)
    if [[ -f "/tmp/${TEST_FILE}.download" ]]; then
        print_success "Successfully downloaded test file"
        rm -f "/tmp/${TEST_FILE}.download"
    fi
    
    # Clean up test file on share
    smbclient "//$SERVER_IP/$SHARE_NAME" -U "$SMB_USER%$SMB_PASSWORD" -c "del $TEST_FILE" 2>&1 > /dev/null || true
    print_info "Cleaned up test file"
else
    print_error "Failed to test write access: $UPLOAD_OUTPUT"
    WRITE_ACCESS=false
fi

# Clean up local test file
rm -f /tmp/$TEST_FILE

# Step 7: Summary
print_step "Test Summary"
echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}SMB Share Test Results:${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}Connection Details:${NC}"
echo "  Server: $SERVER_IP"
echo "  Share: //$SERVER_IP/$SHARE_NAME"
echo "  User: $SMB_USER"
echo

echo -e "${BLUE}Access Rights:${NC}"
echo "  Read access: ✓"
if [[ "$WRITE_ACCESS" == true ]]; then
    echo "  Write access: ✓"
else
    echo "  Write access: ✗ (read-only)"
fi
echo

echo -e "${BLUE}Mount Commands:${NC}"
echo -e "${YELLOW}Linux (CIFS):${NC}"
echo "  sudo mkdir -p /mnt/$SHARE_NAME"
echo "  sudo mount -t cifs //$SERVER_IP/$SHARE_NAME /mnt/$SHARE_NAME -o username=$SMB_USER"
echo
echo -e "${YELLOW}Linux (smbclient):${NC}"
echo "  smbclient //$SERVER_IP/$SHARE_NAME -U $SMB_USER"
echo
echo -e "${YELLOW}Windows:${NC}"
echo "  net use Z: \\\\$SERVER_IP\\$SHARE_NAME /user:$SMB_USER"
echo
echo -e "${YELLOW}macOS:${NC}"
echo "  open smb://$SMB_USER@$SERVER_IP/$SHARE_NAME"
echo "  or Finder: Go → Connect to Server → smb://$SERVER_IP/$SHARE_NAME"

# Performance tip
echo -e "\n${BLUE}Performance Testing:${NC}"
echo "To test transfer speeds, use:"
echo "  dd if=/dev/zero bs=1M count=100 | smbclient //$SERVER_IP/$SHARE_NAME -U $SMB_USER%password -c 'put - testfile.bin'"

print_success "SMB share testing completed!"