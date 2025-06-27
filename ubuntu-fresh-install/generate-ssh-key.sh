#!/bin/bash

set -e

# SSH Key Generation Script
# This script generates an SSH key pair for secure server access
# Usage: ./generate-ssh-key.sh [server-ip] [username]
# Or with curl: curl -fsSL <raw-github-url>/generate-ssh-key.sh | bash
#
# ⚠️  DISCLAIMER: USE AT YOUR OWN RISK
# This script is provided "as is" without warranty. Review and understand
# all code before execution. Use entirely at your own risk.

echo "======================================"
echo "SSH Key Generation Script"
echo "======================================"
echo "This script will generate an SSH key pair"
echo "for secure server authentication."
echo "======================================"
echo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to show help
show_help() {
    echo "SSH Key Generation Script"
    echo
    echo "Usage:"
    echo "  $0 [server-ip] [username]"
    echo
    echo "Parameters (optional):"
    echo "  server-ip   - IP address of the server (for key naming)"
    echo "  username    - Username for the server connection"
    echo
    echo "Examples:"
    echo "  $0                           # Interactive mode"
    echo "  $0 192.168.1.100 myuser     # Generate key for specific server"
    echo
    echo "Or download and run directly:"
    echo "  curl -fsSL <github-raw-url>/generate-ssh-key.sh | bash"
    exit 0
}

# Check for help flags
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "help" ]; then
    show_help
fi

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Get parameters or prompt for them
SERVER_IP="$1"
USERNAME="$2"

# If server IP not provided, prompt for it
if [ -z "$SERVER_IP" ]; then
    echo -n "Enter server IP address (or press Enter to use generic key name): "
    read -r SERVER_IP
fi

# If username not provided, prompt for it
if [ -z "$USERNAME" ]; then
    echo -n "Enter username for the server (or press Enter to use 'user'): "
    read -r USERNAME
    USERNAME=${USERNAME:-user}
fi

# Validate IP if provided
if [ -n "$SERVER_IP" ] && ! validate_ip "$SERVER_IP"; then
    print_warning "Invalid IP address format, using generic key name"
    SERVER_IP=""
fi

# Generate key name
if [ -n "$SERVER_IP" ]; then
    KEY_NAME="vps_${SERVER_IP}_$(date +%Y%m%d)"
    KEY_COMMENT="${USERNAME}@${SERVER_IP}"
else
    KEY_NAME="vps_key_$(date +%Y%m%d)"
    KEY_COMMENT="${USERNAME}@server"
fi

echo
echo "Configuration:"
echo "=============="
echo "Key name: $KEY_NAME"
echo "Comment: $KEY_COMMENT"
echo "Key type: ED25519 (recommended)"
echo

# Check if key already exists
if [ -f "$KEY_NAME" ] || [ -f "${KEY_NAME}.pub" ]; then
    print_warning "SSH key files already exist:"
    [ -f "$KEY_NAME" ] && echo "  - Private key: $KEY_NAME"
    [ -f "${KEY_NAME}.pub" ] && echo "  - Public key: ${KEY_NAME}.pub"
    echo
    echo -n "Overwrite existing keys? (y/N): "
    read -r OVERWRITE
    
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        echo "Key generation cancelled."
        exit 0
    fi
    
    echo "Removing existing keys..."
    rm -f "$KEY_NAME" "${KEY_NAME}.pub"
fi

echo
echo "Generating SSH key pair..."
echo

# Generate SSH key pair
if ssh-keygen -t ed25519 -f "$KEY_NAME" -C "$KEY_COMMENT" -q -N ""; then
    print_success "SSH key pair generated successfully!"
else
    print_error "Failed to generate SSH key pair"
    exit 1
fi

# Set proper permissions
chmod 600 "$KEY_NAME"
chmod 644 "${KEY_NAME}.pub"

echo
echo "📁 Key Files Created:"
echo "===================="
echo "Private key: $(pwd)/$KEY_NAME"
echo "Public key:  $(pwd)/${KEY_NAME}.pub"
echo

# Display public key
echo "🔑 Your Public Key:"
echo "=================="
echo
cat "${KEY_NAME}.pub"
echo
echo "📋 Copy the above public key to use with the server setup script."
echo

# Display usage instructions
echo "📖 Usage Instructions:"
echo "======================"
echo
echo "1. Copy the public key shown above"
echo
echo "2. Run the server setup script on your Ubuntu server:"
if [ -n "$SERVER_IP" ]; then
    echo "   # Connect to your server first:"
    echo "   ssh $USERNAME@$SERVER_IP"
    echo
    echo "   # Then run the setup script:"
    echo "   curl -fsSL <github-raw-url>/ubuntu-setup.sh | bash -s -- $USERNAME \"<paste-public-key-here>\""
else
    echo "   # Connect to your server first:"
    echo "   ssh $USERNAME@<your-server-ip>"
    echo
    echo "   # Then run the setup script:"
    echo "   curl -fsSL <github-raw-url>/ubuntu-setup.sh | bash -s -- $USERNAME \"<paste-public-key-here>\""
fi
echo
echo "3. After server setup is complete, connect using:"
if [ -n "$SERVER_IP" ]; then
    echo "   ssh -i $KEY_NAME $USERNAME@$SERVER_IP"
else
    echo "   ssh -i $KEY_NAME $USERNAME@<server-ip>"
fi
echo

# Create SSH config entry suggestion
echo "💡 SSH Config Entry (optional):"
echo "==============================="
echo "Add this to your ~/.ssh/config file for easier connections:"
echo

if [ -n "$SERVER_IP" ]; then
    HOST_NAME="vps-${SERVER_IP//./-}"
    cat << EOF
Host $HOST_NAME
    HostName $SERVER_IP
    User $USERNAME
    IdentityFile $(pwd)/$KEY_NAME
    IdentitiesOnly yes
    StrictHostKeyChecking yes

EOF
    echo "Then connect with: ssh $HOST_NAME"
else
    cat << EOF
Host your-server
    HostName <server-ip>
    User $USERNAME
    IdentityFile $(pwd)/$KEY_NAME
    IdentitiesOnly yes
    StrictHostKeyChecking yes

EOF
    echo "Replace <server-ip> with your actual server IP"
    echo "Then connect with: ssh your-server"
fi

echo

# Security recommendations
echo "🔒 Security Recommendations:"
echo "============================"
echo "✅ Keep your private key secure and never share it"
echo "✅ Use a passphrase for additional security (run: ssh-keygen -p -f $KEY_NAME)"
echo "✅ Backup your keys in a secure location"
echo "✅ Remove old/unused keys from servers"
echo "✅ Use different keys for different servers/purposes"
echo

# Display key fingerprint
echo "🔍 Key Fingerprint:"
echo "==================="
ssh-keygen -lf "${KEY_NAME}.pub"
echo

print_success "SSH key generation completed!"
echo "Key files are saved in the current directory: $(pwd)"

# Final summary
echo
echo "📝 Next Steps:"
echo "=============="
echo "1. Copy the public key (shown above)"
echo "2. Run the ubuntu-setup.sh script on your server"
echo "3. Test the SSH connection"
echo "4. Store the private key securely"
echo

# Check for SSH agent
if [ -n "$SSH_AUTH_SOCK" ]; then
    echo -n "Add key to SSH agent? (y/N): "
    read -r ADD_TO_AGENT
    
    if [ "$ADD_TO_AGENT" = "y" ] || [ "$ADD_TO_AGENT" = "Y" ]; then
        if ssh-add "$KEY_NAME" 2>/dev/null; then
            print_success "Key added to SSH agent"
        else
            print_warning "Failed to add key to SSH agent"
        fi
    fi
else
    print_info "SSH agent not running. Start it with: eval \$(ssh-agent) && ssh-add $KEY_NAME"
fi

echo
echo "Key generation completed at: $(date)"