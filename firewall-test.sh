#!/bin/bash

# Firewall Test Script - Client-side port scanning and firewall verification
# Usage: ./firewall-test.sh <target-ip-or-hostname> [options]
# This script tests firewall configuration by probing common ports from a client

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="firewall-test-$(date +%Y%m%d-%H%M%S).log"
VERBOSE=false
QUICK_SCAN=false
SAVE_LOG=true

# Common ports to test (using arrays for bash 3.x compatibility)
PORTS_LIST="22 21 23 25 53 80 110 143 443 993 995 1194 1433 1521 1723 2375 2376 2377 3000 3001 3306 4000 4200 4243 4500 5000 5173 5432 5984 6000 6379 7000 7777 8000 8001 8002 8003 8080 8081 8086 8088 8090 8096 8443 8888 9000 9001 9090 9200 9999 25565 27015 27017 32400 161 162 389 500 636"

# Function to get service name for port
get_service_name() {
    local port="$1"
    case "$port" in
        22) echo "SSH" ;;
        21) echo "FTP" ;;
        23) echo "Telnet" ;;
        25) echo "SMTP" ;;
        53) echo "DNS" ;;
        80) echo "HTTP" ;;
        110) echo "POP3" ;;
        143) echo "IMAP" ;;
        161) echo "SNMP" ;;
        162) echo "SNMP Trap" ;;
        389) echo "LDAP" ;;
        443) echo "HTTPS" ;;
        500) echo "IKE" ;;
        636) echo "LDAPS" ;;
        993) echo "IMAPS" ;;
        995) echo "POP3S" ;;
        1194) echo "OpenVPN" ;;
        1433) echo "SQL Server" ;;
        1521) echo "Oracle" ;;
        1723) echo "PPTP VPN" ;;
        2375) echo "Docker API" ;;
        2376) echo "Docker API TLS" ;;
        2377) echo "Docker Swarm" ;;
        3000) echo "Node.js/React Dev" ;;
        3001) echo "Node.js Alt" ;;
        3306) echo "MySQL" ;;
        4000) echo "Alt Service" ;;
        4200) echo "Angular Dev" ;;
        4243) echo "Docker Alt" ;;
        4500) echo "IPSec" ;;
        5000) echo "Flask/Python Dev" ;;
        5173) echo "Vite Dev Server" ;;
        5432) echo "PostgreSQL" ;;
        5984) echo "CouchDB" ;;
        6000) echo "X11" ;;
        6379) echo "Redis" ;;
        7000) echo "Alt Service" ;;
        7777) echo "Game Servers" ;;
        8000) echo "Python/Django Dev" ;;
        8001) echo "Alt HTTP" ;;
        8002) echo "Alt HTTP" ;;
        8003) echo "Alt HTTP" ;;
        8080) echo "HTTP Alt/Spring Boot" ;;
        8081) echo "Jenkins Alt" ;;
        8086) echo "InfluxDB" ;;
        8088) echo "Alt HTTP" ;;
        8090) echo "Confluence" ;;
        8096) echo "Emby/Jellyfin" ;;
        8443) echo "HTTPS Alt" ;;
        8888) echo "Jupyter/Alt HTTP" ;;
        9000) echo "Various Apps/Portainer" ;;
        9001) echo "Alt Service" ;;
        9090) echo "Prometheus" ;;
        9200) echo "Elasticsearch" ;;
        9999) echo "Various Dev" ;;
        25565) echo "Minecraft" ;;
        27015) echo "Steam/Source" ;;
        27017) echo "MongoDB" ;;
        32400) echo "Plex" ;;
        *) echo "Unknown Service" ;;
    esac
}

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    [ "$SAVE_LOG" = true ] && echo "✅ $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    [ "$SAVE_LOG" = true ] && echo "❌ $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    [ "$SAVE_LOG" = true ] && echo "⚠️  $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    [ "$SAVE_LOG" = true ] && echo "ℹ️  $1" >> "$LOG_FILE"
}

print_port_open() {
    echo -e "${GREEN}🟢 Port $1 ($2): OPEN${NC}"
    [ "$SAVE_LOG" = true ] && echo "🟢 Port $1 ($2): OPEN" >> "$LOG_FILE"
}

print_port_closed() {
    echo -e "${RED}🔴 Port $1 ($2): CLOSED/FILTERED${NC}"
    [ "$SAVE_LOG" = true ] && echo "🔴 Port $1 ($2): CLOSED/FILTERED" >> "$LOG_FILE"
}

print_port_filtered() {
    echo -e "${YELLOW}🟡 Port $1 ($2): FILTERED${NC}"
    [ "$SAVE_LOG" = true ] && echo "🟡 Port $1 ($2): FILTERED" >> "$LOG_FILE"
}

# Function to show help
show_help() {
    cat << EOF
Firewall Test Script - Client-side port scanning and firewall verification

Usage: $SCRIPT_NAME <target> [options]

Parameters:
  target          Target IP address or hostname to test

Options:
  -v, --verbose   Enable verbose output
  -q, --quick     Quick scan (reduced timeout)
  --no-log        Don't save results to log file
  -h, --help      Show this help message

Examples:
  $SCRIPT_NAME 192.168.1.100
  $SCRIPT_NAME myserver.com --verbose
  $SCRIPT_NAME 10.0.0.1 --quick --no-log

This script tests common ports to verify firewall configuration.
Results are saved to: $LOG_FILE (unless --no-log is used)

Tested Ports:
  - Web: 80, 443, 3000, 5173, 8000, 8080, etc.
  - System: 22 (SSH), 25 (SMTP), 53 (DNS), etc.
  - Database: 3306 (MySQL), 5432 (PostgreSQL), etc.
  - Development: 4200 (Angular), 8080 (Spring), etc.
  - And many more common service ports...

EOF
}

# Function to check required tools
check_requirements() {
    local missing_tools=()
    
    if ! command -v nmap >/dev/null 2>&1; then
        missing_tools+=("nmap")
    fi
    
    if ! command -v nc >/dev/null 2>&1 && ! command -v netcat >/dev/null 2>&1; then
        missing_tools+=("netcat")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools:"
        echo "  Ubuntu/Debian: sudo apt-get install nmap netcat"
        echo "  CentOS/RHEL: sudo yum install nmap nmap-ncat"
        echo "  macOS: brew install nmap netcat"
        exit 1
    fi
}

# Function to validate target
validate_target() {
    local target="$1"
    
    if [ -z "$target" ]; then
        print_error "No target specified"
        show_help
        exit 1
    fi
    
    # Basic validation - check if it's an IP or hostname
    if [[ "$target" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_info "Target appears to be an IP address: $target"
    else
        print_info "Target appears to be a hostname: $target"
        # Try to resolve hostname
        if ! nslookup "$target" >/dev/null 2>&1 && ! dig "$target" >/dev/null 2>&1; then
            print_warning "Cannot resolve hostname: $target"
            echo -n "Continue anyway? (y/N): "
            read -r confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                exit 1
            fi
        fi
    fi
}

# Function to test port with netcat
test_port_netcat() {
    local target="$1"
    local port="$2"
    local timeout=3
    
    [ "$QUICK_SCAN" = true ] && timeout=1
    
    if command -v nc >/dev/null 2>&1; then
        nc -z -w "$timeout" "$target" "$port" 2>/dev/null
    elif command -v netcat >/dev/null 2>&1; then
        netcat -z -w "$timeout" "$target" "$port" 2>/dev/null
    else
        return 1
    fi
}

# Function to perform nmap scan
perform_nmap_scan() {
    local target="$1"
    local ports_list=""
    
    # Build comma-separated port list
    for port in $PORTS_LIST; do
        if [ -z "$ports_list" ]; then
            ports_list="$port"
        else
            ports_list="$ports_list,$port"
        fi
    done
    
    print_info "Starting nmap scan..."
    
    local nmap_opts="-p $ports_list"
    [ "$QUICK_SCAN" = true ] && nmap_opts="$nmap_opts -T4"
    [ "$VERBOSE" = true ] && nmap_opts="$nmap_opts -v"
    
    # Perform the scan and parse results
    local nmap_output
    nmap_output=$(nmap $nmap_opts "$target" 2>/dev/null)
    
    if [ "$VERBOSE" = true ]; then
        echo "$nmap_output"
        [ "$SAVE_LOG" = true ] && echo "$nmap_output" >> "$LOG_FILE"
    fi
    
    echo "$nmap_output"
}

# Function to attempt service detection
detect_service() {
    local target="$1"
    local port="$2"
    local service_name="$3"
    
    case "$port" in
        22)
            # SSH banner grab
            local ssh_banner
            ssh_banner=$(timeout 3 nc "$target" 22 2>/dev/null | head -1 2>/dev/null || echo "")
            if [ -n "$ssh_banner" ]; then
                print_info "    SSH Banner: $ssh_banner"
            fi
            ;;
        80|8080|3000|5173|8000)
            # HTTP service check
            if command -v curl >/dev/null 2>&1; then
                local http_response
                http_response=$(timeout 3 curl -s -I "http://$target:$port" 2>/dev/null | head -1 || echo "")
                if [ -n "$http_response" ]; then
                    print_info "    HTTP Response: $http_response"
                fi
            fi
            ;;
        443|8443)
            # HTTPS service check
            if command -v curl >/dev/null 2>&1; then
                local https_response
                https_response=$(timeout 3 curl -s -I -k "https://$target:$port" 2>/dev/null | head -1 || echo "")
                if [ -n "$https_response" ]; then
                    print_info "    HTTPS Response: $https_response"
                fi
            fi
            ;;
    esac
}

# Function to analyze and report results
analyze_results() {
    local target="$1"
    local nmap_output="$2"
    
    echo
    print_info "=== Port Scan Results for $target ==="
    echo
    
    local open_ports=0
    local closed_ports=0
    local filtered_ports=0
    
    # Parse nmap output and test each port
    for port in $PORTS_LIST; do
        local service_name=$(get_service_name "$port")
        
        if echo "$nmap_output" | grep -q "^$port/tcp.*open"; then
            print_port_open "$port" "$service_name"
            open_ports=$((open_ports + 1))
            
            # Attempt service detection for open ports
            if [ "$VERBOSE" = true ]; then
                detect_service "$target" "$port" "$service_name"
            fi
            
        elif echo "$nmap_output" | grep -q "^$port/tcp.*filtered"; then
            print_port_filtered "$port" "$service_name"
            filtered_ports=$((filtered_ports + 1))
        else
            print_port_closed "$port" "$service_name"
            closed_ports=$((closed_ports + 1))
        fi
    done
    
    # Summary
    echo
    print_info "=== Scan Summary ==="
    echo "Target: $target"
    local total_ports=$(echo $PORTS_LIST | wc -w)
    echo "Total ports tested: $total_ports"
    print_success "Open ports: $open_ports"
    print_warning "Filtered ports: $filtered_ports"
    print_error "Closed ports: $closed_ports"
    
    # Security recommendations
    echo
    print_info "=== Security Analysis ==="
    
    if [ $open_ports -eq 0 ]; then
        print_success "Excellent! No unnecessary ports are open."
    elif [ $open_ports -le 3 ]; then
        print_success "Good! Only a few essential ports are open."
    elif [ $open_ports -le 10 ]; then
        print_warning "Moderate number of open ports. Review if all are necessary."
    else
        print_error "High number of open ports detected. Security review recommended."
    fi
    
    # Check for common security concerns
    if echo "$nmap_output" | grep -q "^21/tcp.*open"; then
        print_warning "FTP (port 21) is open - consider using SFTP instead"
    fi
    
    if echo "$nmap_output" | grep -q "^23/tcp.*open"; then
        print_error "Telnet (port 23) is open - this is a major security risk!"
    fi
    
    if echo "$nmap_output" | grep -q "^2375/tcp.*open"; then
        print_error "Docker API (port 2375) is open without TLS - security risk!"
    fi
    
    echo
    if [ "$SAVE_LOG" = true ]; then
        print_info "Detailed results saved to: $LOG_FILE"
    fi
    
    echo "Scan completed at: $(date)"
}

# Main function
main() {
    local target=""
    
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quick)
                QUICK_SCAN=true
                shift
                ;;
            --no-log)
                SAVE_LOG=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [ -z "$target" ]; then
                    target="$1"
                else
                    print_error "Too many arguments"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Initialize log file
    if [ "$SAVE_LOG" = true ]; then
        echo "Firewall Test Results - $(date)" > "$LOG_FILE"
        echo "Target: $target" >> "$LOG_FILE"
        echo "========================================" >> "$LOG_FILE"
    fi
    
    echo "🔥 Firewall Test Script"
    echo "======================="
    echo
    
    # Validate inputs and requirements
    validate_target "$target"
    check_requirements
    
    echo
    print_info "Starting firewall test for target: $target"
    [ "$QUICK_SCAN" = true ] && print_info "Quick scan mode enabled"
    [ "$VERBOSE" = true ] && print_info "Verbose mode enabled"
    echo
    
    # Perform the scan
    local nmap_output
    nmap_output=$(perform_nmap_scan "$target")
    
    # Analyze and report results
    analyze_results "$target" "$nmap_output"
}

# Run main function with all arguments
main "$@"