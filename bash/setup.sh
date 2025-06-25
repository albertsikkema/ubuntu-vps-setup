#!/bin/bash

# Ubuntu VPS Setup Script
# Automated production-ready configuration for Ubuntu 24.10 VPS
# Set-and-forget script with sensible defaults

set -euo pipefail

# Configuration
REPO_URL="https://github.com/albertsikkema/ubuntu-vps-setup"
REPO_BRANCH="main"
TEMP_DIR="/tmp/vps-setup-$$"
LOG_FILE="/var/log/vps-setup.log"

# Automated setup defaults
AUTO_MODE=false
INTERACTIVE_MODE=true
DEFAULT_MODULES="system_update,user_management,ssh_hardening,firewall,security,docker,docker_ufw,monitoring,backup"
CONFIG_FILE=""

# Default configuration values
DEFAULT_USERNAME="admin"
DEFAULT_SSH_PORT="2222"
DEFAULT_TIMEZONE="UTC"
DEFAULT_LOCALE="en_US.UTF-8"
DEFAULT_COUNTRY="NL"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                AUTO_MODE=true
                INTERACTIVE_MODE=false
                shift
                ;;
            --username=*)
                DEFAULT_USERNAME="${1#*=}"
                shift
                ;;
            --ssh-port=*)
                DEFAULT_SSH_PORT="${1#*=}"
                shift
                ;;
            --modules=*)
                DEFAULT_MODULES="${1#*=}"
                shift
                ;;
            --config=*)
                CONFIG_FILE="${1#*=}"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "Unknown option: $1" "$RED"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF
Ubuntu VPS Setup Tool - Automated Configuration

Usage: $0 [OPTIONS]

Options:
    --auto                  Run in fully automated mode (no prompts)
    --username=NAME         Set username for sudo user (default: $DEFAULT_USERNAME)
    --ssh-port=PORT         Set SSH port (default: $DEFAULT_SSH_PORT)
    --modules=LIST          Comma-separated modules to install
    --config=FILE           Use configuration file for settings
    -h, --help              Show this help

Automated Mode:
    Runs with these defaults:
    - Timezone: UTC
    - Locale: en_US.UTF-8 (with nl-NL formatting)
    - Username: $DEFAULT_USERNAME
    - SSH Port: $DEFAULT_SSH_PORT
    - All security modules enabled
    - Docker with UFW integration

Examples:
    $0 --auto                           # Full automated setup
    $0 --auto --username=myuser         # Custom username
    $0 --modules=docker,docker_ufw      # Only Docker modules

Modules available:
    system_update, user_management, ssh_hardening, firewall,
    security, docker, docker_ufw, monitoring, backup
EOF
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
}

# Check Ubuntu version with auto-continue in auto mode
check_ubuntu_version() {
    if ! grep -q "Ubuntu 24" /etc/os-release; then
        log "WARNING: This script is designed for Ubuntu 24.10. Your version:" "$YELLOW"
        cat /etc/os-release | grep VERSION
        
        if [[ "$AUTO_MODE" == "true" ]]; then
            log "Auto mode: Continuing anyway..." "$YELLOW"
        else
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Set locale and timezone
configure_locale_timezone() {
    log "Configuring locale and timezone..."
    
    # Set timezone to UTC
    timedatectl set-timezone UTC
    log "Timezone set to UTC"
    
    # Install locales package if not present
    apt-get install -y locales
    
    # Configure locales - use simpler approach
    log "Generating required locales..."
    
    # Backup locale.gen
    cp /etc/locale.gen /etc/locale.gen.backup 2>/dev/null || true
    
    # Ensure both locales are uncommented in locale.gen
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sed -i 's/# nl_NL.UTF-8 UTF-8/nl_NL.UTF-8 UTF-8/' /etc/locale.gen
    
    # Add them if they don't exist at all
    grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    grep -q "^nl_NL.UTF-8 UTF-8" /etc/locale.gen || echo "nl_NL.UTF-8 UTF-8" >> /etc/locale.gen
    
    # Generate locales
    locale-gen
    
    # Verify Dutch locale was generated
    if locale -a | grep -q "nl_NL.utf8"; then
        log "Dutch locale successfully generated"
        
        # Set primary language to English, but use Dutch formatting
        cat > /etc/default/locale << EOF
LANG=en_US.UTF-8
LANGUAGE=en_US:en
LC_TIME=nl_NL.UTF-8
LC_NUMERIC=nl_NL.UTF-8
LC_MONETARY=nl_NL.UTF-8
LC_PAPER=nl_NL.UTF-8
LC_MEASUREMENT=nl_NL.UTF-8
LC_CTYPE=en_US.UTF-8
LC_COLLATE=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
EOF
        
        # Apply the locale settings immediately
        source /etc/default/locale 2>/dev/null || true
        
        log "Locale configured: English language with Dutch formatting"
    else
        log "Dutch locale generation failed, using English only" "$YELLOW"
        
        # Fallback to English only
        cat > /etc/default/locale << EOF
LANG=en_US.UTF-8
LANGUAGE=en_US:en
LC_ALL=en_US.UTF-8
EOF
        
        source /etc/default/locale 2>/dev/null || true
        log "Fallback: Using English locale only"
    fi
}

# Load and process configuration file
process_config_file() {
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            log "Loading configuration from: $CONFIG_FILE" "$BLUE"
            
            # Source the config parser and load the file
            source "$TEMP_DIR/bash/modules/config_parser.sh"
            
            if load_config "$CONFIG_FILE"; then
                # Validate configuration
                if validate_config; then
                    # Set up environment from config
                    setup_config_env
                    log "Configuration loaded and applied" "$GREEN"
                else
                    error_exit "Configuration validation failed"
                fi
            else
                error_exit "Failed to load configuration file"
            fi
        else
            error_exit "Configuration file not found: $CONFIG_FILE"
        fi
    fi
}

# Create environment file for automated setup
create_environment_file() {
    cat > "$TEMP_DIR/.setup_env" << EOF
# Automated setup environment variables
export SETUP_AUTO_MODE="$AUTO_MODE"
export SETUP_USERNAME="$DEFAULT_USERNAME"
export SETUP_SSH_PORT="$DEFAULT_SSH_PORT"
export SETUP_TIMEZONE="$DEFAULT_TIMEZONE"
export SETUP_LOCALE="$DEFAULT_LOCALE"
export SETUP_COUNTRY="$DEFAULT_COUNTRY"
export SETUP_MODULES="$DEFAULT_MODULES"
export SETUP_INTERACTIVE="$INTERACTIVE_MODE"

# Default responses for interactive prompts
export SETUP_CHANGE_HOSTNAME="no"
export SETUP_SSH_PORT_CHANGE="yes"
export SETUP_DISABLE_ROOT_SSH="yes"
export SETUP_LOCK_ROOT_PASSWORD="yes"
export SETUP_PASSWORDLESS_SUDO="yes"
export SETUP_ALLOW_HTTP="yes"
export SETUP_ALLOW_HTTPS="yes"
export SETUP_ENABLE_2FA="no"
export SETUP_REGENERATE_HOST_KEYS="yes"
export SETUP_ADD_LOGIN_BANNER="yes"
export SETUP_INSTALL_AIDE="no"
export SETUP_REMOVE_OLD_DOCKER="yes"
export SETUP_ENABLE_USER_NAMESPACE="no"
export SETUP_ENABLE_CONTENT_TRUST="no"
export SETUP_RUN_DOCKER_TEST="no"
EOF
    
    log "Environment file created for automated setup"
}

# Download repository
download_repo() {
    log "Downloading VPS setup repository..."
    
    # Install required tools
    apt-get update -qq
    apt-get install -y -qq git curl wget locales > /dev/null 2>&1
    
    # Configure locale and timezone first
    configure_locale_timezone
    
    # Clone repository
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    if git clone -b "$REPO_BRANCH" "$REPO_URL" "$TEMP_DIR" > /dev/null 2>&1; then
        log "Repository cloned successfully"
    else
        # Fallback to wget if git fails
        log "Git clone failed, trying wget..." "$YELLOW"
        mkdir -p "$TEMP_DIR"
        
        local archive_url="$REPO_URL/archive/refs/heads/$REPO_BRANCH.tar.gz"
        log "Downloading from: $archive_url"
        
        if wget -q "$archive_url" -O "$TEMP_DIR/repo.tar.gz"; then
            cd "$TEMP_DIR"
            tar -xzf repo.tar.gz --strip-components=1
            rm repo.tar.gz
            cd - > /dev/null
            log "Repository downloaded via wget"
        else
            error_exit "Failed to download repository from $archive_url"
        fi
    fi
    
    # Verify files were downloaded (they should be in bash/ subdirectory)
    if [[ ! -f "$TEMP_DIR/bash/vps-setup-main.sh" ]]; then
        error_exit "Main setup script not found at $TEMP_DIR/bash/vps-setup-main.sh. Check repository structure."
    fi
    
    # Make scripts executable
    find "$TEMP_DIR/bash" -name "*.sh" -type f -exec chmod +x {} \;
    log "Scripts made executable"
    
    # Process configuration file if provided
    process_config_file
    
    # Create environment file for modules
    create_environment_file
}

# Run main setup
run_setup() {
    log "Starting VPS setup..."
    
    # Check if main script exists in bash subdirectory
    if [[ -f "$TEMP_DIR/bash/vps-setup-main.sh" ]]; then
        cd "$TEMP_DIR/bash"
        
        if [[ "$AUTO_MODE" == "true" ]]; then
            # Run in automated mode
            ./vps-setup-main.sh --auto --modules "$DEFAULT_MODULES"
        else
            # Run in interactive mode
            ./vps-setup-main.sh "$@"
        fi
    else
        error_exit "Main setup script not found in repository"
    fi
}

# Cleanup
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Show automated setup summary
show_auto_summary() {
    if [[ "$AUTO_MODE" == "true" ]]; then
        log "AUTOMATED SETUP SUMMARY:" "$BLUE"
        log "- Timezone: UTC" "$BLUE"
        log "- Locale: English with Dutch formatting" "$BLUE"
        log "- Username: $DEFAULT_USERNAME" "$BLUE"
        log "- SSH Port: $DEFAULT_SSH_PORT" "$BLUE"
        log "- Modules: $DEFAULT_MODULES" "$BLUE"
        log "- Docker with UFW integration: YES" "$BLUE"
        log "- Security hardening: FULL" "$BLUE"
        echo
        
        if [[ "$INTERACTIVE_MODE" == "false" ]]; then
            log "Running fully automated - no user input required!" "$GREEN"
        else
            log "Press CTRL+C within 10 seconds to cancel..." "$YELLOW"
            sleep 10
        fi
    fi
}

# Main execution
main() {
    # Parse arguments first
    parse_args "$@"
    
    clear
    echo "================================================"
    echo "     Ubuntu VPS Production Setup Tool"
    echo "     Automated Configuration for nl-NL"
    echo "================================================"
    echo
    
    # Create log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # Show automated setup summary
    show_auto_summary
    
    # Run checks
    check_root
    check_ubuntu_version
    
    # Download and run
    download_repo
    run_setup "$@"
    
    log "Setup completed successfully!" "$GREEN"
    log "Check the log file for details: $LOG_FILE" "$BLUE"
    log "Server is configured for Netherlands (nl-NL) with UTC timezone" "$BLUE"
}

# Run main function with all arguments
main "$@"