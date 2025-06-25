#!/bin/bash

# Utility functions for VPS setup scripts

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export NC='\033[0m' # No Color

# Log file
export LOG_FILE="${LOG_FILE:-/var/log/vps-setup.log}"

# Logging function
log() {
    local message="$1"
    local color="${2:-$GREEN}"
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] $message${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if package is installed
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Install package if not already installed
install_package() {
    local package="$1"
    if ! package_installed "$package"; then
        log "Installing $package..."
        apt-get update -qq
        apt-get install -y -qq "$package" || error_exit "Failed to install $package"
    else
        log "$package is already installed" "$BLUE"
    fi
}

# Backup file before modification
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log "Backed up $file to $backup" "$BLUE"
    fi
}

# Replace or append line in file
update_config_line() {
    local file="$1"
    local search="$2"
    local replace="$3"
    
    backup_file "$file"
    
    if grep -q "^${search}" "$file"; then
        sed -i "s|^${search}.*|${replace}|" "$file"
        log "Updated: $replace in $file" "$BLUE"
    else
        echo "$replace" >> "$file"
        log "Added: $replace to $file" "$BLUE"
    fi
}

# Comment out line in file
comment_line() {
    local file="$1"
    local pattern="$2"
    
    backup_file "$file"
    sed -i "s|^${pattern}|#${pattern}|g" "$file"
}

# Generate random password
generate_password() {
    local length="${1:-16}"
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-"$length"
}

# Create user if not exists
create_user_if_not_exists() {
    local username="$1"
    local home_dir="${2:-/home/$username}"
    
    if ! id "$username" &>/dev/null; then
        log "Creating user: $username"
        useradd -m -d "$home_dir" -s /bin/bash "$username"
        return 0
    else
        log "User $username already exists" "$BLUE"
        return 1
    fi
}

# Check if service is running
service_running() {
    systemctl is-active --quiet "$1"
}

# Enable and start service
enable_service() {
    local service="$1"
    log "Enabling and starting $service..."
    systemctl enable "$service"
    systemctl start "$service"
}

# Restart service
restart_service() {
    local service="$1"
    log "Restarting $service..."
    systemctl restart "$service"
}

# Check if port is open
port_open() {
    local port="$1"
    netstat -tuln | grep -q ":${port}"
}

# Get primary network interface
get_primary_interface() {
    ip route | grep default | awk '{print $5}' | head -n1
}

# Get primary IP address
get_primary_ip() {
    local interface=$(get_primary_interface)
    ip addr show "$interface" | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1
}

# Prompt for confirmation with automated response support
confirm() {
    local prompt="${1:-Continue?}"
    
    # Check for specific automated responses first
    local prompt_key=""
    case "$prompt" in
        *"change the hostname"*) prompt_key="SETUP_CHANGE_HOSTNAME" ;;
        *"Change SSH port"*) prompt_key="SETUP_SSH_PORT_CHANGE" ;;
        *"Disable root SSH login"*) prompt_key="SETUP_DISABLE_ROOT_SSH" ;;
        *"Lock root account"*) prompt_key="SETUP_LOCK_ROOT_PASSWORD" ;;
        *"sudo without password"*) prompt_key="SETUP_PASSWORDLESS_SUDO" ;;
        *"Allow HTTP"*) prompt_key="SETUP_ALLOW_HTTP" ;;
        *"Allow HTTPS"*) prompt_key="SETUP_ALLOW_HTTPS" ;;
        *"Two-Factor Authentication"*) prompt_key="SETUP_ENABLE_2FA" ;;
        *"Regenerate SSH host keys"*) prompt_key="SETUP_REGENERATE_HOST_KEYS" ;;
        *"login banner"*) prompt_key="SETUP_ADD_LOGIN_BANNER" ;;
        *"Install AIDE"*) prompt_key="SETUP_INSTALL_AIDE" ;;
        *"old Docker"*) prompt_key="SETUP_REMOVE_OLD_DOCKER" ;;
        *"user namespace"*) prompt_key="SETUP_ENABLE_USER_NAMESPACE" ;;
        *"Content Trust"*) prompt_key="SETUP_ENABLE_CONTENT_TRUST" ;;
        *"test container"*) prompt_key="SETUP_RUN_DOCKER_TEST" ;;
    esac
    
    if [[ -n "$prompt_key" ]] && [[ -n "${!prompt_key:-}" ]]; then
        local response="${!prompt_key}"
        log "Auto response for '$prompt': $response" "$BLUE"
        [[ "$response" =~ ^[Yy]|yes$ ]]
        return $?
    fi
    
    # Check for general automated mode (fallback to YES for unmapped prompts)
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        log "Auto mode: Answering YES to: $prompt" "$BLUE"
        return 0
    fi
    
    # Interactive prompt
    read -p "$prompt (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Automated input handling for prompts
auto_input() {
    local prompt="$1"
    local default_value="$2"
    
    # Check for automated mode first
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        # In auto mode, use environment variables or defaults
        case "$prompt" in
            *"username"*) 
                local value="${SETUP_USERNAME:-$default_value}"
                log "Auto mode: Using '$value' for username" "$BLUE"
                echo "$value"
                return
                ;;
            *"SSH port"*) 
                local value="${SETUP_SSH_PORT:-$default_value}"
                log "Auto mode: Using '$value' for SSH port" "$BLUE"
                echo "$value"
                return
                ;;
            *)
                log "Auto mode: Using default '$default_value' for: $prompt" "$BLUE"
                echo "$default_value"
                return
                ;;
        esac
    fi
    
    # Check for specific environment variables in non-auto mode
    case "$prompt" in
        *"username"*) 
            if [[ -n "${SETUP_USERNAME:-}" ]]; then
                echo "${SETUP_USERNAME}"
                return
            fi
            ;;
        *"SSH port"*) 
            if [[ -n "${SETUP_SSH_PORT:-}" ]]; then
                echo "${SETUP_SSH_PORT}"
                return
            fi
            ;;
    esac
    
    # Interactive input
    read -p "$prompt: " input
    echo "${input:-$default_value}"
}

# Check Ubuntu version
check_ubuntu_version() {
    if ! grep -qE "Ubuntu (24\.|23\.10)" /etc/os-release; then
        log "WARNING: This script is optimized for Ubuntu 24.10/24.04" "$YELLOW"
        if ! confirm "Your Ubuntu version may not be fully compatible. Continue anyway?"; then
            exit 1
        fi
    fi
}

# Create directory if not exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log "Created directory: $dir" "$BLUE"
    fi
}

# Download file with retry
download_file() {
    local url="$1"
    local dest="$2"
    local retries=3
    
    for i in $(seq 1 $retries); do
        if wget -q -O "$dest" "$url"; then
            return 0
        fi
        log "Download attempt $i failed, retrying..." "$YELLOW"
        sleep 2
    done
    
    return 1
}

# Check disk space
check_disk_space() {
    local required_mb="${1:-1000}"
    local available_mb=$(df / | awk 'NR==2 {print int($4/1024)}')
    
    if [[ $available_mb -lt $required_mb ]]; then
        error_exit "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
    fi
}

# Add line to file if not exists
add_line_if_not_exists() {
    local file="$1"
    local line="$2"
    
    if ! grep -qF "$line" "$file"; then
        echo "$line" >> "$file"
        log "Added to $file: $line" "$BLUE"
    fi
}

# Export all functions
export -f log error_exit command_exists package_installed install_package
export -f backup_file update_config_line comment_line generate_password
export -f create_user_if_not_exists service_running enable_service restart_service
export -f port_open get_primary_interface get_primary_ip confirm
export -f check_ubuntu_version ensure_dir download_file check_disk_space
export -f add_line_if_not_exists