#!/bin/bash

# SSH Hardening Module
# Secures SSH configuration for production use

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting SSH Hardening Module" "$BLUE"

# Global variables
SSH_PORT=22
NEW_SSH_PORT=""

# Backup SSH configuration
backup_ssh_config() {
    backup_file /etc/ssh/sshd_config
    
    # Also backup the SSH host keys
    for key in /etc/ssh/ssh_host_*; do
        if [[ -f "$key" ]]; then
            backup_file "$key"
        fi
    done
}

# Change SSH port
change_ssh_port() {
    log "Current SSH port: $SSH_PORT"
    
    if confirm "Change SSH port from default (22)?"; then
        while true; do
            NEW_SSH_PORT=$(auto_input "Enter new SSH port (1024-65535)" "${SETUP_SSH_PORT:-2222}")
            
            if [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] && [[ "$NEW_SSH_PORT" -ge 1024 ]] && [[ "$NEW_SSH_PORT" -le 65535 ]]; then
                if port_open "$NEW_SSH_PORT"; then
                    log "Port $NEW_SSH_PORT is already in use" "$RED"
                    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
                        # Try default + 1 in auto mode
                        NEW_SSH_PORT=$((${SETUP_SSH_PORT:-2222} + 1))
                        log "Auto mode: Trying port $NEW_SSH_PORT instead" "$BLUE"
                        continue
                    fi
                else
                    break
                fi
            else
                log "Invalid port number" "$RED"
                if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
                    NEW_SSH_PORT="2222"  # Safe fallback
                    break
                fi
            fi
        done
        
        update_config_line /etc/ssh/sshd_config "Port" "Port $NEW_SSH_PORT"
        SSH_PORT=$NEW_SSH_PORT
        log "SSH port changed to $NEW_SSH_PORT"
    fi
}

# Configure SSH security settings
configure_ssh_security() {
    log "Configuring SSH security settings..."
    
    # Create custom sshd_config
    cat > /etc/ssh/sshd_config.d/99-hardening.conf << EOF
# SSH Hardening Configuration
# Added by VPS setup script

# Basic Security
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Key Authentication
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Connection Settings
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
MaxStartups 10:30:60

# Disable unsafe features
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
DebianBanner no

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Restrict ciphers and algorithms
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Host key algorithms
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# Login grace time
LoginGraceTime 30s

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    log "SSH security configuration applied"
}

# Configure SSH allow/deny lists
configure_ssh_access() {
    log "Configuring SSH access restrictions..."
    
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        log "Auto mode: Skipping SSH user/group restrictions" "$BLUE"
        return
    fi
    
    if [[ "${SETUP_RESTRICT_SSH_ACCESS:-no}" == "yes" ]] && confirm "Restrict SSH access to specific users/groups?"; then
        echo "" >> /etc/ssh/sshd_config.d/99-hardening.conf
        
        # Allow specific users
        read -p "Enter allowed users (space-separated, leave empty to skip): " allowed_users
        if [[ -n "$allowed_users" ]]; then
            echo "AllowUsers $allowed_users" >> /etc/ssh/sshd_config.d/99-hardening.conf
            log "SSH access restricted to users: $allowed_users"
        fi
        
        # Allow specific groups
        read -p "Enter allowed groups (space-separated, leave empty to skip): " allowed_groups
        if [[ -n "$allowed_groups" ]]; then
            echo "AllowGroups $allowed_groups" >> /etc/ssh/sshd_config.d/99-hardening.conf
            log "SSH access restricted to groups: $allowed_groups"
        fi
    fi
}

# Configure 2FA (optional)
configure_2fa() {
    if confirm "Setup Two-Factor Authentication (2FA) for SSH?"; then
        log "Installing Google Authenticator..."
        install_package "libpam-google-authenticator"
        
        # Configure PAM
        backup_file /etc/pam.d/sshd
        
        # Add Google Authenticator to PAM
        echo "auth required pam_google_authenticator.so nullok" >> /etc/pam.d/sshd
        
        # Update SSH config
        echo "" >> /etc/ssh/sshd_config.d/99-hardening.conf
        echo "# Two-Factor Authentication" >> /etc/ssh/sshd_config.d/99-hardening.conf
        echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config.d/99-hardening.conf
        echo "ChallengeResponseAuthentication yes" >> /etc/ssh/sshd_config.d/99-hardening.conf
        
        log "2FA enabled for SSH"
        log "Users must run 'google-authenticator' to setup their 2FA" "$YELLOW"
    fi
}

# Generate strong host keys
regenerate_host_keys() {
    if confirm "Regenerate SSH host keys for better security?"; then
        log "Regenerating SSH host keys..."
        
        # Remove old keys
        rm -f /etc/ssh/ssh_host_*
        
        # Generate new keys with strong parameters
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" < /dev/null
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" < /dev/null
        
        log "New SSH host keys generated"
    fi
}

# Configure SSH banner
configure_ssh_banner() {
    if confirm "Add login banner for SSH?"; then
        cat > /etc/issue.net << 'EOF'
**************************************************************************
                            AUTHORIZED ACCESS ONLY

This system is for authorized use only. All activity is monitored and 
logged. Unauthorized access is strictly prohibited and will be prosecuted
to the fullest extent of the law.

By accessing this system, you consent to monitoring and recording of all
activities. If you do not consent, disconnect immediately.
**************************************************************************
EOF
        
        echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config.d/99-hardening.conf
        log "SSH login banner configured"
    fi
}

# Setup fail2ban for SSH
setup_ssh_fail2ban() {
    log "Configuring fail2ban for SSH protection..."
    
    # Create fail2ban SSH jail
    cat > /etc/fail2ban/jail.d/ssh.conf << EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
ignoreip = 127.0.0.1/8 ::1
EOF

    # Enable and start fail2ban
    enable_service fail2ban
    
    log "Fail2ban configured for SSH protection"
}

# Validate SSH configuration
validate_ssh_config() {
    log "Validating SSH configuration..."
    
    if sshd -t; then
        log "SSH configuration is valid" "$GREEN"
        return 0
    else
        log "SSH configuration has errors!" "$RED"
        return 1
    fi
}

# Main execution
main() {
    backup_ssh_config
    
    # Get current SSH port
    SSH_PORT=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
    
    change_ssh_port
    configure_ssh_security
    configure_ssh_access
    configure_2fa
    regenerate_host_keys
    configure_ssh_banner
    
    # Validate before applying
    if validate_ssh_config; then
        restart_service ssh
        setup_ssh_fail2ban
        
        log "SSH Hardening Module completed successfully!" "$GREEN"
        
        if [[ -n "$NEW_SSH_PORT" ]]; then
            log "IMPORTANT: SSH port changed to $NEW_SSH_PORT" "$YELLOW"
            log "Update your firewall rules and connection settings!" "$YELLOW"
        fi
    else
        log "SSH configuration validation failed. Check the configuration!" "$RED"
        exit 1
    fi
}

# Run main
main