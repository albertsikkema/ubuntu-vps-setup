#!/bin/bash

# Configuration Parser Module
# Handles loading and parsing configuration files

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Global configuration variables
declare -A CONFIG

# Load configuration from file
load_config() {
    local config_file="${1:-}"
    
    if [[ -z "$config_file" ]]; then
        log "No configuration file specified" "$YELLOW"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log "Configuration file not found: $config_file" "$RED"
        return 1
    fi
    
    log "Loading configuration from: $config_file" "$BLUE"
    
    local section=""
    local line_num=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Handle sections
        if [[ "$line" =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Handle key=value pairs
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Clean up whitespace
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # Store with section prefix
            if [[ -n "$section" ]]; then
                CONFIG["${section}.${key}"]="$value"
            else
                CONFIG["$key"]="$value"
            fi
        else
            log "Invalid configuration line $line_num: $line" "$YELLOW"
        fi
    done < "$config_file"
    
    log "Configuration loaded: ${#CONFIG[@]} settings" "$GREEN"
    return 0
}

# Get configuration value
get_config() {
    local key="$1"
    local default="${2:-}"
    
    if [[ -n "${CONFIG[$key]:-}" ]]; then
        echo "${CONFIG[$key]}"
    else
        echo "$default"
    fi
}

# Get boolean configuration value
get_config_bool() {
    local key="$1"
    local default="${2:-false}"
    
    local value=$(get_config "$key" "$default")
    
    case "${value,,}" in
        true|yes|1|on|enabled)
            echo "true"
            ;;
        false|no|0|off|disabled)
            echo "false"
            ;;
        *)
            log "Invalid boolean value for $key: $value, using default: $default" "$YELLOW"
            echo "$default"
            ;;
    esac
}

# Set up environment variables from config
setup_config_env() {
    log "Setting up environment from configuration..." "$BLUE"
    
    # General settings
    export SETUP_TIMEZONE=$(get_config "general.timezone" "UTC")
    export SETUP_LOCALE=$(get_config "general.locale" "en_US.UTF-8")
    export SETUP_COUNTRY=$(get_config "general.country" "NL")
    
    # User settings
    export SETUP_USERNAME=$(get_config "user.username" "admin")
    export SETUP_CREATE_USER=$(get_config_bool "user.create_user" "true")
    export SETUP_PASSWORDLESS_SUDO=$(get_config_bool "user.passwordless_sudo" "true")
    export SETUP_DISABLE_ROOT_SSH=$(get_config_bool "user.disable_root_ssh" "true")
    export SETUP_LOCK_ROOT_PASSWORD=$(get_config_bool "user.lock_root_password" "true")
    
    # SSH settings
    export SETUP_SSH_PORT_CHANGE=$(get_config_bool "ssh.change_port" "true")
    export SETUP_SSH_PORT=$(get_config "ssh.ssh_port" "2222")
    export SETUP_ENABLE_2FA=$(get_config_bool "ssh.enable_2fa" "false")
    export SETUP_REGENERATE_HOST_KEYS=$(get_config_bool "ssh.regenerate_host_keys" "true")
    export SETUP_ADD_LOGIN_BANNER=$(get_config_bool "ssh.add_login_banner" "true")
    
    # Firewall settings
    export SETUP_ALLOW_HTTP=$(get_config_bool "firewall.allow_http" "true")
    export SETUP_ALLOW_HTTPS=$(get_config_bool "firewall.allow_https" "true")
    
    # Security settings
    export SETUP_INSTALL_AIDE=$(get_config_bool "security.install_aide" "false")
    
    # Docker settings
    export SETUP_REMOVE_OLD_DOCKER=$(get_config_bool "docker.install_docker" "true")
    export SETUP_ENABLE_USER_NAMESPACE=$(get_config_bool "docker.enable_user_namespace" "false")
    export SETUP_ENABLE_CONTENT_TRUST=$(get_config_bool "docker.enable_content_trust" "false")
    export SETUP_RUN_DOCKER_TEST=$(get_config_bool "docker.run_test" "false")
    
    # Monitoring settings
    export SETUP_INSTALL_NETDATA=$(get_config_bool "monitoring.install_netdata" "true")
    export SETUP_INSTALL_MONIT=$(get_config_bool "monitoring.install_monit" "true")
    export SETUP_DAILY_REPORTS=$(get_config_bool "monitoring.daily_reports" "true")
    
    # Backup settings
    export SETUP_ENABLE_BACKUPS=$(get_config_bool "backup.enable_backups" "true")
    export SETUP_DAILY_BACKUP=$(get_config_bool "backup.daily_backup" "true")
    export SETUP_BACKUP_MONITORING=$(get_config_bool "backup.backup_monitoring" "true")
    
    # Hostname setting (special handling)
    if [[ "$(get_config_bool "general.hostname_change" "false")" == "false" ]]; then
        export SETUP_CHANGE_HOSTNAME="no"
    else
        export SETUP_CHANGE_HOSTNAME="yes"
    fi
    
    log "Environment configured from settings file" "$GREEN"
}

# Create example configuration
create_example_config() {
    local example_file="$1"
    
    cat > "$example_file" << 'EOF'
# Ubuntu VPS Setup Configuration File
# Copy this file and modify as needed

[general]
timezone=UTC
locale=en_US.UTF-8
country=NL
hostname_change=false

[user]
username=myuser
create_user=true
passwordless_sudo=true
disable_root_ssh=true
lock_root_password=true

[ssh]
change_port=true
ssh_port=2222
enable_2fa=false
regenerate_host_keys=true
add_login_banner=true

[firewall]
allow_http=true
allow_https=true

[security]
install_aide=false

[docker]
install_docker=true
enable_user_namespace=false
enable_content_trust=false

[monitoring]
install_netdata=true
install_monit=true
daily_reports=true

[backup]
enable_backups=true
daily_backup=true
backup_monitoring=true

[advanced]
email_notifications=false
admin_email=admin@example.com
EOF
    
    log "Example configuration created: $example_file"
}

# Validate configuration
validate_config() {
    log "Validating configuration..." "$BLUE"
    
    local errors=0
    
    # Check username format
    local username=$(get_config "user.username" "admin")
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log "ERROR: Invalid username format: $username" "$RED"
        ((errors++))
    fi
    
    # Check SSH port range
    local ssh_port=$(get_config "ssh.ssh_port" "2222")
    if [[ ! "$ssh_port" =~ ^[0-9]+$ ]] || [[ "$ssh_port" -lt 1024 ]] || [[ "$ssh_port" -gt 65535 ]]; then
        log "ERROR: Invalid SSH port: $ssh_port (must be 1024-65535)" "$RED"
        ((errors++))
    fi
    
    # Check timezone
    local timezone=$(get_config "general.timezone" "UTC")
    if [[ ! -f "/usr/share/zoneinfo/$timezone" ]]; then
        log "WARNING: Timezone may not exist: $timezone" "$YELLOW"
    fi
    
    # Check email format if notifications enabled
    if [[ "$(get_config_bool "advanced.email_notifications" "false")" == "true" ]]; then
        local email=$(get_config "advanced.admin_email" "")
        if [[ ! "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            log "ERROR: Invalid email format: $email" "$RED"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Configuration validation passed" "$GREEN"
        return 0
    else
        log "Configuration validation failed with $errors errors" "$RED"
        return 1
    fi
}

# Show current configuration
show_config() {
    log "Current Configuration:" "$BLUE"
    echo
    
    local sections=("general" "user" "ssh" "firewall" "security" "docker" "monitoring" "backup" "advanced")
    
    for section in "${sections[@]}"; do
        echo "[$section]"
        
        # Find all keys for this section
        for key in "${!CONFIG[@]}"; do
            if [[ "$key" =~ ^${section}\. ]]; then
                local display_key="${key#${section}.}"
                echo "  $display_key = ${CONFIG[$key]}"
            fi
        done
        echo
    done
}

# Override configuration with command line arguments
override_with_args() {
    local username="${1:-}"
    local ssh_port="${2:-}"
    
    if [[ -n "$username" ]]; then
        CONFIG["user.username"]="$username"
        log "Overridden username: $username" "$BLUE"
    fi
    
    if [[ -n "$ssh_port" ]]; then
        CONFIG["ssh.ssh_port"]="$ssh_port"
        log "Overridden SSH port: $ssh_port" "$BLUE"
    fi
}

# Export functions for use by other modules
export -f load_config get_config get_config_bool setup_config_env
export -f validate_config show_config override_with_args create_example_config