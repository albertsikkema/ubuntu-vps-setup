#!/bin/bash

# Main VPS Setup Script
# This is the core script that orchestrates all setup modules

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
CONFIGS_DIR="$SCRIPT_DIR/configs"
LOG_FILE="/var/log/vps-setup.log"

# Import utilities
source "$MODULES_DIR/utils.sh" 2>/dev/null || {
    echo "Error: Cannot load utilities module"
    exit 1
}

# Configuration
declare -A MODULE_STATUS
SELECTED_MODULES=()
DRY_RUN=false
QUICK_MODE=false
AUTO_MODE=false

# Load environment variables if they exist
if [[ -f "$SCRIPT_DIR/.setup_env" ]]; then
    source "$SCRIPT_DIR/.setup_env"
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        AUTO_MODE=true
        export SETUP_AUTO_MODE=true
        # Export key variables for modules
        export SETUP_USERNAME="${SETUP_USERNAME:-admin}"
        export SETUP_SSH_PORT="${SETUP_SSH_PORT:-2222}"
    fi
fi

# Available modules with descriptions
declare -A MODULES=(
    ["system_update"]="System Update & Basic Setup"
    ["user_management"]="User Management & Sudo Configuration"
    ["ssh_hardening"]="SSH Security Hardening"
    ["firewall"]="UFW Firewall Configuration"
    ["docker"]="Docker & Docker Compose Installation"
    ["docker_ufw"]="Docker-UFW Integration Fix"
)

# Module dependencies
declare -A MODULE_DEPS=(
    ["docker_ufw"]="docker firewall"
)

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick|-q)
                QUICK_MODE=true
                shift
                ;;
            --auto|-a)
                AUTO_MODE=true
                QUICK_MODE=true
                export SETUP_AUTO_MODE=true
                shift
                ;;
            --dry-run|-d)
                DRY_RUN=true
                shift
                ;;
            --modules|-m)
                IFS=',' read -ra SELECTED_MODULES <<< "$2"
                shift 2
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

# Show help message
show_help() {
    cat << EOF
Ubuntu VPS Setup Tool

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -q, --quick             Quick setup with recommended defaults
    -d, --dry-run           Show what would be done without making changes
    -m, --modules <list>    Run specific modules (comma-separated)

Available modules:
    system_update        System Update & Basic Setup
    user_management      User Management & Sudo Configuration
    ssh_hardening        SSH Security Hardening
    firewall             UFW Firewall Configuration
    docker               Docker & Docker Compose Installation
    docker_ufw           Docker-UFW Integration Fix

Example: $0 --modules system_update,ssh_hardening,firewall
}

# Display interactive menu
show_menu() {
    clear
    echo "================================================"
    echo "     Ubuntu VPS Production Setup Tool"
    echo "================================================"
    echo
    echo "Select modules to install (space to select, enter to confirm):"
    echo
    
    local modules_array=("${!MODULES[@]}")
    IFS=$'\n' modules_array=($(sort <<<"${modules_array[*]}"))
    
    local selected=()
    for module in "${modules_array[@]}"; do
        selected+=("off")
    done
    
    # If quick mode, pre-select recommended modules
    if [[ "$QUICK_MODE" == "true" ]]; then
        for i in "${!modules_array[@]}"; do
            case "${modules_array[$i]}" in
                system_update|user_management|ssh_hardening|firewall|security)
                    selected[$i]="on"
                    ;;
            esac
        done
    fi
    
    local current=0
    while true; do
        clear
        echo "================================================"
        echo "     Ubuntu VPS Production Setup Tool"
        echo "================================================"
        echo
        echo "Select modules to install (space to select, enter to confirm):"
        echo
        
        for i in "${!modules_array[@]}"; do
            if [[ $i -eq $current ]]; then
                echo -n "> "
            else
                echo -n "  "
            fi
            
            if [[ "${selected[$i]}" == "on" ]]; then
                echo -n "[X] "
            else
                echo -n "[ ] "
            fi
            
            printf "%-20s %s\n" "${modules_array[$i]}" "${MODULES[${modules_array[$i]}]}"
        done
        
        echo
        echo "Navigation: ↑/↓ to move, SPACE to select/deselect, ENTER to confirm, Q to quit"
        
        # Read single character
        read -rsn1 key
        
        case "$key" in
            $'\x1b')  # Arrow keys
                read -rsn2 key
                case "$key" in
                    '[A')  # Up arrow
                        ((current--))
                        if [[ $current -lt 0 ]]; then
                            current=$((${#modules_array[@]} - 1))
                        fi
                        ;;
                    '[B')  # Down arrow
                        ((current++))
                        if [[ $current -ge ${#modules_array[@]} ]]; then
                            current=0
                        fi
                        ;;
                esac
                ;;
            ' ')  # Space
                if [[ "${selected[$current]}" == "on" ]]; then
                    selected[$current]="off"
                else
                    selected[$current]="on"
                fi
                ;;
            'q'|'Q')  # Quit
                log "Setup cancelled by user" "$YELLOW"
                exit 0
                ;;
            '')  # Enter
                break
                ;;
        esac
    done
    
    # Build selected modules list
    SELECTED_MODULES=()
    for i in "${!modules_array[@]}"; do
        if [[ "${selected[$i]}" == "on" ]]; then
            SELECTED_MODULES+=("${modules_array[$i]}")
        fi
    done
    
    if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
        log "No modules selected. Exiting." "$YELLOW"
        exit 0
    fi
}

# Check and add module dependencies
resolve_dependencies() {
    local resolved=()
    local to_process=("$@")
    
    while [[ ${#to_process[@]} -gt 0 ]]; do
        local module="${to_process[0]}"
        to_process=("${to_process[@]:1}")
        
        # Skip if already resolved
        if [[ " ${resolved[@]} " =~ " ${module} " ]]; then
            continue
        fi
        
        # Add dependencies first
        if [[ -n "${MODULE_DEPS[$module]:-}" ]]; then
            IFS=' ' read -ra deps <<< "${MODULE_DEPS[$module]}"
            for dep in "${deps[@]}"; do
                if [[ ! " ${resolved[@]} " =~ " ${dep} " ]]; then
                    to_process=("$dep" "${to_process[@]}")
                fi
            done
        fi
        
        resolved+=("$module")
    done
    
    SELECTED_MODULES=("${resolved[@]}")
}

# Run a module
run_module() {
    local module=$1
    local module_script="$MODULES_DIR/${module}.sh"
    
    if [[ ! -f "$module_script" ]]; then
        log "Module script not found: $module" "$RED"
        return 1
    fi
    
    log "Running module: ${MODULES[$module]}" "$BLUE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [DRY RUN] Would execute: $module_script" "$YELLOW"
        MODULE_STATUS[$module]="skipped"
    else
        if bash "$module_script"; then
            MODULE_STATUS[$module]="success"
            log "  Module completed successfully" "$GREEN"
        else
            MODULE_STATUS[$module]="failed"
            log "  Module failed" "$RED"
            return 1
        fi
    fi
}

# Show summary
show_summary() {
    echo
    echo "================================================"
    echo "           Setup Summary"
    echo "================================================"
    echo
    
    for module in "${SELECTED_MODULES[@]}"; do
        local status="${MODULE_STATUS[$module]:-pending}"
        case "$status" in
            success)
                echo -e "${GREEN}✓${NC} ${MODULES[$module]}"
                ;;
            failed)
                echo -e "${RED}✗${NC} ${MODULES[$module]}"
                ;;
            skipped)
                echo -e "${YELLOW}○${NC} ${MODULES[$module]} (dry run)"
                ;;
            *)
                echo -e "${YELLOW}?${NC} ${MODULES[$module]}"
                ;;
        esac
    done
    
    echo
    echo "Log file: $LOG_FILE"
}

# Main execution
main() {
    # Parse arguments
    parse_args "$@"
    
    # If no modules specified, show menu or use defaults
    if [[ ${#SELECTED_MODULES[@]} -eq 0 ]] && [[ "$AUTO_MODE" == "false" ]] && [[ "$QUICK_MODE" == "false" ]]; then
        show_menu
    elif [[ "$AUTO_MODE" == "true" ]] && [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
        # Auto mode: select full suite including Docker
        SELECTED_MODULES=(system_update user_management ssh_hardening firewall security docker docker_ufw)
    elif [[ "$QUICK_MODE" == "true" ]] && [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
        # Quick mode: select recommended modules
        SELECTED_MODULES=(system_update user_management ssh_hardening firewall security)
    fi
    
    # Resolve dependencies
    resolve_dependencies "${SELECTED_MODULES[@]}"
    
    # Confirm selection
    echo
    echo "The following modules will be installed:"
    for module in "${SELECTED_MODULES[@]}"; do
        echo "  - ${MODULES[$module]}"
    done
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Running in DRY RUN mode - no changes will be made" "$YELLOW"
    elif [[ "$AUTO_MODE" == "true" ]]; then
        log "Auto mode: Proceeding automatically..." "$BLUE"
    else
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Setup cancelled" "$YELLOW"
            exit 0
        fi
    fi
    
    # Run modules
    for module in "${SELECTED_MODULES[@]}"; do
        if ! run_module "$module"; then
            log "Setup stopped due to module failure" "$RED"
            show_summary
            exit 1
        fi
    done
    
    # Show summary
    show_summary
}

# Run main
main "$@"