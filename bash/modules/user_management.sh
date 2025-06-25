#!/bin/bash

# User Management Module
# Creates secure user accounts and configures sudo access

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting User Management Module" "$BLUE"

# Global variables
NEW_USER=""
SSH_KEY=""

# Create new sudo user
create_sudo_user() {
    log "Creating new sudo user..."
    
    # Get username with automated support
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        NEW_USER="${SETUP_USERNAME:-admin}"
        log "Auto mode: Using username '$NEW_USER'" "$BLUE"
    else
        while true; do
            NEW_USER=$(auto_input "Enter username for new sudo user" "${SETUP_USERNAME:-admin}")
            
            if [[ -z "$NEW_USER" ]]; then
                log "Username cannot be empty" "$RED"
                continue
            fi
        
            if [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                break
            else
                log "Invalid username. Use lowercase letters, numbers, underscore, and hyphen only" "$RED"
                if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
                    NEW_USER="admin"  # Fallback to safe default
                    break
                fi
            fi
        done
    fi
    
    # Validate username format
    if [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log "Invalid username format, using 'admin'" "$YELLOW"
        NEW_USER="admin"
    fi
    
    # Check if user already exists
    if id "$NEW_USER" &>/dev/null; then
        log "User $NEW_USER already exists" "$YELLOW"
        if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
            log "Auto mode: Continuing with existing user $NEW_USER" "$BLUE"
        else
            if ! confirm "Continue with existing user?"; then
                return 1
            fi
        fi
    else
        # Create user
        log "Creating user $NEW_USER..."
        useradd -m -s /bin/bash "$NEW_USER"
        
        # Set password
        log "Setting password for $NEW_USER..."
        if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
            # Generate random password for automated mode
            local temp_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)
            echo "$NEW_USER:$temp_password" | chpasswd
            log "Auto-generated temporary password for $NEW_USER (change after setup)" "$YELLOW"
            log "Temporary password: $temp_password" "$YELLOW"
            echo "IMPORTANT: Temporary password for $NEW_USER: $temp_password" >> /var/log/vps-setup.log
        else
            echo "Please set a strong password for the new user:"
            passwd "$NEW_USER" || error_exit "Failed to set password"
        fi
    fi
    
    # Add to sudo group
    usermod -aG sudo "$NEW_USER"
    log "User $NEW_USER added to sudo group"
}

# Configure SSH key authentication
setup_ssh_key() {
    log "Setting up SSH key authentication for $NEW_USER..."
    
    local ssh_dir="/home/$NEW_USER/.ssh"
    ensure_dir "$ssh_dir"
    
    # Get SSH public key
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        log "Auto mode: Skipping SSH key setup (configure manually after installation)" "$BLUE"
        option=3
    else
        echo "Please provide SSH public key for $NEW_USER"
        echo "You can:"
        echo "1) Paste the key directly"
        echo "2) Provide a URL to download the key"
        echo "3) Skip SSH key setup"
        
        read -p "Choose option (1-3): " option
    fi
    
    case $option in
        1)
            echo "Paste your SSH public key (usually starts with ssh-rsa, ssh-ed25519, etc.):"
            read -r SSH_KEY
            
            if [[ -n "$SSH_KEY" ]]; then
                echo "$SSH_KEY" >> "$ssh_dir/authorized_keys"
                log "SSH key added"
            else
                log "No SSH key provided" "$YELLOW"
                return
            fi
            ;;
        2)
            read -p "Enter URL to SSH public key: " key_url
            
            if [[ -n "$key_url" ]]; then
                if download_file "$key_url" "$ssh_dir/authorized_keys"; then
                    log "SSH key downloaded and added"
                else
                    log "Failed to download SSH key" "$RED"
                    return
                fi
            fi
            ;;
        3)
            log "Skipping SSH key setup" "$YELLOW"
            return
            ;;
        *)
            log "Invalid option" "$RED"
            return
            ;;
    esac
    
    # Set proper permissions
    chown -R "$NEW_USER:$NEW_USER" "$ssh_dir"
    chmod 700 "$ssh_dir"
    chmod 600 "$ssh_dir/authorized_keys"
    
    log "SSH key authentication configured"
}

# Configure sudo without password (optional)
configure_sudo_nopass() {
    if confirm "Allow $NEW_USER to use sudo without password?"; then
        echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USER"
        chmod 440 "/etc/sudoers.d/$NEW_USER"
        log "Passwordless sudo configured for $NEW_USER"
    else
        # Ensure timeout is reasonable
        backup_file /etc/sudoers
        if ! grep -q "Defaults timestamp_timeout" /etc/sudoers; then
            echo "Defaults timestamp_timeout=15" >> /etc/sudoers
            log "Sudo timeout set to 15 minutes"
        fi
    fi
}

# Disable root login
disable_root_login() {
    log "Configuring root account security..."
    
    if confirm "Disable root SSH login?"; then
        update_config_line /etc/ssh/sshd_config "PermitRootLogin" "PermitRootLogin no"
        log "Root SSH login disabled"
    fi
    
    if confirm "Lock root account password?"; then
        passwd -l root
        log "Root account password locked"
    fi
}

# Configure password policies
configure_password_policies() {
    log "Configuring password policies..."
    
    # Install password quality checking library
    install_package "libpam-pwquality"
    
    # Configure password complexity
    backup_file /etc/security/pwquality.conf
    
    cat > /etc/security/pwquality.conf << EOF
# Password quality configuration
# Added by VPS setup script

# Minimum password length
minlen = 12

# Require at least one digit
dcredit = -1

# Require at least one uppercase letter
ucredit = -1

# Require at least one lowercase letter
lcredit = -1

# Require at least one special character
ocredit = -1

# Reject passwords with 3 or more repeated characters
maxrepeat = 3

# Reject passwords with 3 or more characters in sequence
maxsequence = 3

# Reject passwords containing username
usercheck = 1

# Enforce policy for root
enforce_for_root
EOF

    # Configure password aging
    backup_file /etc/login.defs
    
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs
    
    log "Password policies configured"
}

# Configure account lockout policies
configure_account_lockout() {
    log "Configuring account lockout policies..."
    
    # Configure PAM for account lockout
    backup_file /etc/pam.d/common-auth
    
    # Add pam_tally2 for account lockout after failed attempts
    if ! grep -q "pam_tally2" /etc/pam.d/common-auth; then
        sed -i '1i auth required pam_tally2.so deny=5 unlock_time=900 onerr=fail' /etc/pam.d/common-auth
        log "Account lockout configured: 5 failed attempts, 15 minute lockout"
    fi
    
    # Configure for SSH as well
    backup_file /etc/pam.d/sshd
    if ! grep -q "pam_tally2" /etc/pam.d/sshd; then
        sed -i '1i auth required pam_tally2.so deny=5 unlock_time=900 onerr=fail' /etc/pam.d/sshd
    fi
}

# Remove unnecessary users
cleanup_users() {
    log "Checking for unnecessary system users..."
    
    # List of users that might be removed (depending on system)
    local unnecessary_users=(
        "games"
        "gnats"
        "irc"
        "list"
        "news"
        "uucp"
    )
    
    for user in "${unnecessary_users[@]}"; do
        if id "$user" &>/dev/null; then
            if confirm "Remove unnecessary user '$user'?"; then
                userdel -r "$user" 2>/dev/null || true
                log "Removed user: $user"
            fi
        fi
    done
}

# Main execution
main() {
    # Create new sudo user
    create_sudo_user
    
    if [[ -n "$NEW_USER" ]]; then
        setup_ssh_key
        configure_sudo_nopass
    fi
    
    # Security configurations
    disable_root_login
    configure_password_policies
    configure_account_lockout
    cleanup_users
    
    # Restart SSH if config changed
    if [[ -f /etc/ssh/sshd_config.backup.* ]]; then
        restart_service ssh
    fi
    
    log "User Management Module completed successfully!" "$GREEN"
    
    if [[ -n "$NEW_USER" ]]; then
        log "You can now login as: ssh $NEW_USER@$(get_primary_ip)" "$BLUE"
    fi
}

# Run main
main