#!/bin/bash

# System Update Module
# Updates system packages and performs basic setup

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting System Update & Basic Setup Module" "$BLUE"

# Update package lists (centralized)
update_packages() {
    log "Updating package lists..."
    
    # Clear any lock files first
    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null || true
    
    # Update with better error handling
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if apt-get update -qq 2>/dev/null; then
            log "Package lists updated successfully"
            return 0
        fi
        
        log "Package list update attempt $attempt failed, retrying..." "$YELLOW"
        sleep 2
        ((attempt++))
    done
    
    error_exit "Failed to update package lists after $max_attempts attempts"
}

# Upgrade installed packages
upgrade_packages() {
    log "Upgrading installed packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get upgrade -y -qq || error_exit "Failed to upgrade packages"
    
    log "Performing distribution upgrade..."
    apt-get dist-upgrade -y -qq || error_exit "Failed to perform dist-upgrade"
    
    log "Removing unnecessary packages..."
    apt-get autoremove -y -qq
    apt-get autoclean -y -qq
}

# Install essential packages efficiently
install_essentials() {
    log "Installing essential packages..."
    
    # Core essentials (always needed)
    local core_packages=(
        curl
        wget
        git
        vim
        nano
        htop
        net-tools
        ufw
        fail2ban
        unattended-upgrades
        software-properties-common
        apt-transport-https
        ca-certificates
        gnupg
        lsb-release
    )
    
    # Additional tools (useful but not critical)
    local additional_packages=(
        build-essential
        python3-pip
        unzip
        zip
        tree
        ncdu
        iotop
        sysstat
        mtr-tiny
        dnsutils
        rsync
        screen
        tmux
    )
    
    # Install core packages first (critical for other modules)
    log "Installing core packages..."
    install_packages "${core_packages[@]}"
    
    # Install additional packages (continue on failure in auto mode)
    log "Installing additional tools..."
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        # In auto mode, don't fail if additional packages can't be installed
        install_packages "${additional_packages[@]}" || log "Some additional packages failed to install" "$YELLOW"
    else
        install_packages "${additional_packages[@]}"
    fi
}

# Configure timezone
configure_timezone() {
    log "Configuring timezone..."
    
    # Always use UTC as requested
    timedatectl set-timezone UTC
    log "Timezone set to UTC"
    
    # Enable NTP
    timedatectl set-ntp true
    log "NTP synchronization enabled"
    
    # Note: Locale configuration is handled in the main setup script
    # to avoid conflicts and ensure proper order
}

# Configure hostname
configure_hostname() {
    log "Current hostname: $(hostname)"
    
    # Check if automated mode or explicitly disabled
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]] || [[ "${SETUP_CHANGE_HOSTNAME:-no}" == "no" ]]; then
        log "Keeping current hostname: $(hostname)" "$BLUE"
        return
    fi
    
    if confirm "Would you like to change the hostname?"; then
        read -p "Enter new hostname: " new_hostname
        
        if [[ -n "$new_hostname" ]]; then
            hostnamectl set-hostname "$new_hostname"
            
            # Update /etc/hosts
            backup_file /etc/hosts
            sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/" /etc/hosts
            
            log "Hostname changed to: $new_hostname"
        fi
    fi
}

# Configure swap
configure_swap() {
    log "Checking swap configuration..."
    
    local swap_size=$(free -m | awk '/^Swap:/ {print $2}')
    
    if [[ $swap_size -eq 0 ]]; then
        log "No swap detected, creating swap file..."
        
        # Calculate swap size efficiently (1x RAM, max 4GB for VPS)
        local ram_size=$(free -m | awk '/^Mem:/ {print $2}')
        local swap_size_mb=$ram_size
        
        # Cap at 4GB for VPS efficiency
        if [[ $swap_size_mb -gt 4096 ]]; then
            swap_size_mb=4096
        fi
        
        # Minimum 512MB
        if [[ $swap_size_mb -lt 512 ]]; then
            swap_size_mb=512
        fi
        
        log "Creating ${swap_size_mb}MB swap file..."
        
        # Create swap file efficiently
        if command_exists fallocate; then
            fallocate -l "${swap_size_mb}M" /swapfile
        else
            dd if=/dev/zero of=/swapfile bs=1M count=$swap_size_mb status=none
        fi
        
        chmod 600 /swapfile
        mkswap /swapfile > /dev/null
        swapon /swapfile
        
        # Make permanent
        add_line_if_not_exists /etc/fstab "/swapfile none swap sw 0 0"
        
        # Configure swappiness (lower for VPS)
        update_config_line /etc/sysctl.conf "vm.swappiness" "vm.swappiness=10"
        sysctl vm.swappiness=10 > /dev/null
        
        log "Swap file created and activated" "$GREEN"
    else
        log "Swap already configured: ${swap_size}MB" "$BLUE"
    fi
}

# Configure system limits
configure_limits() {
    log "Configuring system limits..."
    
    # Increase file descriptor limits
    backup_file /etc/security/limits.conf
    
    cat >> /etc/security/limits.conf << EOF

# Added by VPS setup script
* soft nofile 65535
* hard nofile 65535
* soft nproc 32768
* hard nproc 32768
root soft nofile 65535
root hard nofile 65535
root soft nproc 32768
root hard nproc 32768
EOF

    # Configure sysctl for better performance
    backup_file /etc/sysctl.conf
    
    cat >> /etc/sysctl.conf << EOF

# Added by VPS setup script
# Increase system IP port limits
net.ipv4.ip_local_port_range = 1024 65535

# Increase TCP buffer sizes
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# Enable TCP fast open
net.ipv4.tcp_fastopen = 3

# Increase the maximum number of connections
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# Reuse TIME_WAIT sockets
net.ipv4.tcp_tw_reuse = 1

# Increase the number of outstanding syn requests allowed
net.ipv4.tcp_syncookies = 1
EOF

    sysctl -p > /dev/null 2>&1
    log "System limits configured"
}

# Configure automatic updates
configure_auto_updates() {
    log "Configuring automatic security updates..."
    
    # Configure unattended-upgrades
    backup_file /etc/apt/apt.conf.d/50unattended-upgrades
    
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}";
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

    # Enable automatic updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    log "Automatic security updates configured"
}

# Main execution
main() {
    check_disk_space 500  # Require at least 500MB free
    
    update_packages
    upgrade_packages
    install_essentials
    configure_timezone
    configure_hostname
    configure_swap
    configure_limits
    configure_auto_updates
    
    log "System Update & Basic Setup completed successfully!" "$GREEN"
}

# Run main
main