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

# Enhanced error handling
error_exit() {
    local error_msg="$1"
    local exit_code="${2:-1}"
    
    log "ERROR: $error_msg" "$RED"
    
    # Log additional context if available
    if [[ -n "${BASH_LINENO:-}" ]] && [[ -n "${BASH_SOURCE:-}" ]]; then
        log "Error occurred at line ${BASH_LINENO[1]} in ${BASH_SOURCE[1]}" "$RED"
    fi
    
    # In auto mode, try to continue with non-critical errors
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]] && [[ "${SETUP_CONTINUE_ON_ERROR:-false}" == "true" ]]; then
        log "Auto mode: Continuing despite error (exit code would be $exit_code)" "$YELLOW"
        return $exit_code
    fi
    
    exit $exit_code
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if package is installed
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Install package if not already installed (assumes apt is updated)
install_package() {
    local package="$1"
    if ! package_installed "$package"; then
        log "Installing $package..."
        apt-get install -y -qq "$package" || error_exit "Failed to install $package"
    else
        log "$package is already installed" "$BLUE"
    fi
}

# Install multiple packages efficiently in one command
install_packages() {
    local packages=("$@")
    local to_install=()
    
    # Validate input
    if [[ ${#packages[@]} -eq 0 ]]; then
        log "No packages specified for installation" "$YELLOW"
        return 0
    fi
    
    # Check which packages need installation
    for package in "${packages[@]}"; do
        if [[ -z "$package" ]]; then
            continue  # Skip empty package names
        fi
        
        if ! package_installed "$package"; then
            to_install+=("$package")
        else
            log "$package is already installed" "$BLUE"
        fi
    done
    
    # Install all needed packages in one command
    if [[ ${#to_install[@]} -gt 0 ]]; then
        log "Installing packages: ${to_install[*]}"
        
        # Set non-interactive mode
        export DEBIAN_FRONTEND=noninteractive
        
        # Try installation with retry logic
        local max_attempts=2
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if apt-get install -y -qq "${to_install[@]}" 2>/dev/null; then
                log "Successfully installed ${#to_install[@]} packages" "$GREEN"
                return 0
            fi
            
            log "Package installation attempt $attempt failed" "$YELLOW"
            
            if [[ $attempt -eq 1 ]]; then
                # First failure: update package lists and retry
                log "Updating package lists and retrying..."
                apt-get update -qq 2>/dev/null || true
            fi
            
            ((attempt++))
        done
        
        # All attempts failed
        if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
            log "Auto mode: Some packages failed to install, continuing" "$YELLOW"
            return 0
        else
            error_exit "Failed to install packages: ${to_install[*]}"
        fi
    else
        log "All packages already installed" "$BLUE"
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
        *"IP-based firewall rules"*) prompt_key="SETUP_ADD_IP_RULES" ;;
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

# Check disk space with better error handling
check_disk_space() {
    local required_mb="${1:-1000}"
    
    # Get available space with error handling
    local available_mb
    if ! available_mb=$(df / 2>/dev/null | awk 'NR==2 {print int($4/1024)}'); then
        log "Warning: Could not check disk space" "$YELLOW"
        return 0
    fi
    
    if [[ -z "$available_mb" ]] || [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        log "Warning: Could not determine available disk space" "$YELLOW"
        return 0
    fi
    
    if [[ $available_mb -lt $required_mb ]]; then
        log "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB" "$RED"
        
        if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
            log "Auto mode: Continuing with low disk space warning" "$YELLOW"
            return 0
        else
            error_exit "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        fi
    else
        log "Disk space check passed: ${available_mb}MB available" "$BLUE"
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

# Validate network connectivity
check_network() {
    local test_hosts=("8.8.8.8" "1.1.1.1")
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 5 "$host" > /dev/null 2>&1; then
            return 0
        fi
    done
    
    log "Warning: Network connectivity check failed" "$YELLOW"
    return 1
}

# Cleanup function for failed installations
cleanup_failed_install() {
    local package="$1"
    log "Cleaning up failed installation of $package..." "$YELLOW"
    
    # Remove partially installed packages
    apt-get remove --purge -y "$package" 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    
    # Clear any held locks
    rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock 2>/dev/null || true
}

# Validate username
validate_username() {
    local username="$1"
    
    # Check if username is empty
    if [[ -z "$username" ]]; then
        return 1
    fi
    
    # Check length (1-32 characters)
    if [[ ${#username} -gt 32 ]] || [[ ${#username} -lt 1 ]]; then
        return 1
    fi
    
    # Check valid characters (alphanumeric, underscore, hyphen)
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 1
    fi
    
    # Check doesn't start with number or special char
    if [[ "$username" =~ ^[0-9_-] ]]; then
        return 1
    fi
    
    # Check against reserved names
    local reserved=("root" "daemon" "bin" "sys" "sync" "games" "man" "lp" "mail" "news" "uucp" "proxy" "www-data" "backup" "list" "irc" "gnats" "nobody" "systemd" "admin" "administrator")
    for reserved_name in "${reserved[@]}"; do
        if [[ "$username" == "$reserved_name" ]]; then
            return 1
        fi
    done
    
    return 0
}

# Validate password strength
validate_password() {
    local password="$1"
    
    # Check minimum length
    if [[ ${#password} -lt 8 ]]; then
        return 1
    fi
    
    # Check maximum length (reasonable limit)
    if [[ ${#password} -gt 128 ]]; then
        return 1
    fi
    
    # Check contains at least one letter and one number
    if [[ ! "$password" =~ [a-zA-Z] ]] || [[ ! "$password" =~ [0-9] ]]; then
        return 1
    fi
    
    return 0
}

# Validate SSH port
validate_ssh_port() {
    local port="$1"
    
    # Check if it's a number
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Check range (1024-65535, avoiding system ports)
    if [[ $port -lt 1024 ]] || [[ $port -gt 65535 ]]; then
        return 1
    fi
    
    # Check if port is already in use
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    
    return 0
}

# Sanitize file path
sanitize_path() {
    local path="$1"
    
    # Remove potentially dangerous characters
    path="${path//[^a-zA-Z0-9._/-]/}"
    
    # Remove double slashes
    path="${path//\/\//\/}"
    
    # Remove trailing slash unless it's root
    if [[ "$path" != "/" ]]; then
        path="${path%/}"
    fi
    
    echo "$path"
}

# Export all functions
export -f log error_exit command_exists package_installed install_package install_packages
export -f backup_file update_config_line comment_line generate_password
export -f create_user_if_not_exists service_running enable_service restart_service
export -f port_open get_primary_interface get_primary_ip confirm auto_input
export -f check_ubuntu_version ensure_dir download_file check_disk_space
export -f add_line_if_not_exists check_network cleanup_failed_install
export -f validate_username validate_password validate_ssh_port sanitize_path