#!/bin/bash

# Firewall Configuration Module
# Sets up UFW (Uncomplicated Firewall) with secure defaults

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting Firewall Configuration Module" "$BLUE"

# Global variables
SSH_PORT=22
CUSTOM_PORTS=()

# Check current firewall status
check_firewall_status() {
    if command_exists ufw; then
        local status=$(ufw status | grep -o "Status: .*" | cut -d' ' -f2)
        log "Current UFW status: $status" "$BLUE"
    else
        error_exit "UFW is not installed"
    fi
}

# Reset firewall to defaults
reset_firewall() {
    if confirm "Reset firewall to default settings?"; then
        log "Resetting firewall..."
        ufw --force reset
        log "Firewall reset to defaults"
    fi
}

# Configure default policies
configure_defaults() {
    log "Configuring default firewall policies..."
    
    # Default policies: deny incoming, allow outgoing
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow established connections
    ufw default allow routed
    
    log "Default policies configured: Deny incoming, Allow outgoing"
}

# Get SSH port from config
get_ssh_port() {
    # Check sshd_config for custom port
    if [[ -f /etc/ssh/sshd_config ]]; then
        local port=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "")
        if [[ -n "$port" ]]; then
            SSH_PORT=$port
        fi
    fi
    
    # Check sshd_config.d for custom port
    if [[ -d /etc/ssh/sshd_config.d ]]; then
        local port=$(grep -h -E "^Port" /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | tail -1 || echo "")
        if [[ -n "$port" ]]; then
            SSH_PORT=$port
        fi
    fi
    
    log "Detected SSH port: $SSH_PORT"
}

# Configure essential services
configure_essential_services() {
    log "Configuring firewall rules for essential services..."
    
    # SSH (with rate limiting)
    log "Adding SSH rule (port $SSH_PORT) with rate limiting..."
    ufw limit $SSH_PORT/tcp comment 'SSH rate limit'
    
    # HTTP and HTTPS (optional)
    if confirm "Allow HTTP (port 80)?"; then
        ufw allow 80/tcp comment 'HTTP'
        CUSTOM_PORTS+=(80)
    fi
    
    if confirm "Allow HTTPS (port 443)?"; then
        ufw allow 443/tcp comment 'HTTPS'
        CUSTOM_PORTS+=(443)
    fi
    
    # Common services
    local services=(
        "DNS:53:udp:Outgoing DNS queries"
        "NTP:123:udp:Time synchronization"
    )
    
    for service in "${services[@]}"; do
        IFS=':' read -r name port proto desc <<< "$service"
        ufw allow out $port/$proto comment "$desc"
    done
}

# Configure custom ports
configure_custom_ports() {
    log "Configure additional ports..."
    
    while true; do
        read -p "Enter port to open (or 'done' to finish): " port
        
        if [[ "$port" == "done" ]] || [[ -z "$port" ]]; then
            break
        fi
        
        if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
            read -p "Protocol (tcp/udp/both) [tcp]: " proto
            proto=${proto:-tcp}
            
            read -p "Description: " desc
            desc=${desc:-"Custom port"}
            
            case $proto in
                tcp|udp)
                    ufw allow $port/$proto comment "$desc"
                    ;;
                both)
                    ufw allow $port comment "$desc"
                    ;;
                *)
                    log "Invalid protocol" "$RED"
                    continue
                    ;;
            esac
            
            CUSTOM_PORTS+=($port)
            log "Added rule for port $port/$proto"
        else
            log "Invalid port number" "$RED"
        fi
    done
}

# Configure IP-based rules
configure_ip_rules() {
    if confirm "Add IP-based firewall rules?"; then
        log "Configure IP-based access rules..."
        
        while true; do
            echo "1) Allow from specific IP"
            echo "2) Deny from specific IP"
            echo "3) Done"
            
            read -p "Choose option: " option
            
            case $option in
                1)
                    read -p "Enter IP address or subnet to allow: " ip
                    read -p "Enter port (or 'any' for all ports): " port
                    
                    if [[ "$port" == "any" ]]; then
                        ufw allow from $ip comment "Allow from $ip"
                    else
                        read -p "Protocol (tcp/udp) [tcp]: " proto
                        proto=${proto:-tcp}
                        ufw allow from $ip to any port $port proto $proto
                    fi
                    log "Added allow rule for $ip"
                    ;;
                2)
                    read -p "Enter IP address or subnet to deny: " ip
                    ufw deny from $ip comment "Deny from $ip"
                    log "Added deny rule for $ip"
                    ;;
                3)
                    break
                    ;;
                *)
                    log "Invalid option" "$RED"
                    ;;
            esac
        done
    fi
}

# Configure logging
configure_logging() {
    log "Configuring firewall logging..."
    
    echo "Select logging level:"
    echo "1) Off"
    echo "2) Low"
    echo "3) Medium (default)"
    echo "4) High"
    echo "5) Full"
    
    read -p "Choose option [3]: " level
    level=${level:-3}
    
    case $level in
        1) ufw logging off ;;
        2) ufw logging low ;;
        3) ufw logging medium ;;
        4) ufw logging high ;;
        5) ufw logging full ;;
        *) ufw logging medium ;;
    esac
    
    log "Firewall logging configured"
}

# Configure advanced settings
configure_advanced() {
    if confirm "Configure advanced firewall settings?"; then
        log "Configuring advanced settings..."
        
        # Enable IPv6 support
        backup_file /etc/default/ufw
        if confirm "Enable IPv6 support?"; then
            sed -i 's/IPV6=.*/IPV6=yes/' /etc/default/ufw
            log "IPv6 support enabled"
        else
            sed -i 's/IPV6=.*/IPV6=no/' /etc/default/ufw
            log "IPv6 support disabled"
        fi
        
        # Configure connection tracking
        cat >> /etc/ufw/sysctl.conf << EOF

# Added by VPS setup script
# Connection tracking
net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
EOF
        
        log "Advanced settings configured"
    fi
}

# Enable firewall
enable_firewall() {
    log "Enabling firewall..."
    
    # Show current rules
    log "Current firewall rules:" "$BLUE"
    ufw show added
    
    echo
    log "WARNING: Enabling firewall will apply these rules immediately!" "$YELLOW"
    log "Make sure SSH access is properly configured!" "$YELLOW"
    
    if confirm "Enable firewall now?"; then
        ufw --force enable
        log "Firewall enabled successfully!" "$GREEN"
        
        # Show status
        ufw status verbose
    else
        log "Firewall NOT enabled. Enable manually with: ufw enable" "$YELLOW"
    fi
}

# Save firewall configuration
save_config() {
    local config_file="/root/firewall-config.txt"
    
    log "Saving firewall configuration to $config_file..."
    
    {
        echo "# UFW Firewall Configuration"
        echo "# Generated on $(date)"
        echo
        echo "# Status"
        ufw status verbose
        echo
        echo "# Rules"
        ufw show added
        echo
        echo "# Raw rules"
        iptables-save
    } > "$config_file"
    
    chmod 600 "$config_file"
    log "Configuration saved to $config_file"
}

# Main execution
main() {
    check_firewall_status
    get_ssh_port
    
    # Configure firewall
    reset_firewall
    configure_defaults
    configure_essential_services
    configure_custom_ports
    configure_ip_rules
    configure_logging
    configure_advanced
    
    # Enable and save
    enable_firewall
    save_config
    
    log "Firewall Configuration Module completed successfully!" "$GREEN"
    
    # Show important ports
    if [[ ${#CUSTOM_PORTS[@]} -gt 0 ]]; then
        log "Open ports: $SSH_PORT (SSH), ${CUSTOM_PORTS[*]}" "$BLUE"
    else
        log "Open ports: $SSH_PORT (SSH)" "$BLUE"
    fi
}

# Run main
main