#!/bin/bash

# Monitoring & Logging Setup Module
# Installs and configures monitoring tools and centralized logging

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting Monitoring & Logging Setup Module" "$BLUE"

# Install basic monitoring tools
install_monitoring_tools() {
    log "Installing monitoring tools..."
    
    local tools=(
        htop            # Enhanced top
        iotop           # I/O monitoring
        nethogs         # Network monitoring per process
        ncdu            # Disk usage analyzer
        lsof            # List open files
        strace          # System call tracer
        tcpdump         # Network packet analyzer
        sysstat         # System statistics (iostat, sar, etc.)
        vnstat          # Network statistics
        glances         # All-in-one monitoring
        nmon            # Performance monitoring
        dstat           # System statistics
        atop            # Advanced system monitor
        monit           # Process monitoring and restart
        logwatch        # Log analysis and reporting
        logrotate       # Log rotation
        rsyslog         # Enhanced syslog
    )
    
    for tool in "${tools[@]}"; do
        install_package "$tool"
    done
    
    log "Basic monitoring tools installed" "$GREEN"
}

# Configure logrotate for better log management
configure_logrotate() {
    log "Configuring log rotation..."
    
    # Create custom logrotate configuration
    cat > /etc/logrotate.d/vps-monitoring << 'EOF'
# VPS Monitoring Log Rotation
# Rotate logs more frequently to prevent disk issues

/var/log/auth.log {
    weekly
    missingok
    rotate 8
    compress
    delaycompress
    notifempty
    create 0640 root adm
}

/var/log/kern.log {
    weekly
    missingok
    rotate 8
    compress
    delaycompress
    notifempty
    create 0640 root adm
}

/var/log/syslog {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 root adm
}

/var/log/ufw.log {
    weekly
    missingok
    rotate 8
    compress
    delaycompress
    notifempty
    create 0640 root adm
}

/var/log/fail2ban.log {
    weekly
    missingok
    rotate 8
    compress
    delaycompress
    notifempty
    create 0640 root adm
}

# Docker logs if Docker is installed
/var/lib/docker/containers/*/*-json.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    copytruncate
    maxsize 100M
}
EOF

    # Test logrotate configuration
    logrotate -d /etc/logrotate.d/vps-monitoring > /dev/null 2>&1 || {
        log "Logrotate configuration test failed" "$YELLOW"
    }
    
    log "Log rotation configured"
}

# Install and configure netdata for real-time monitoring
install_netdata() {
    if confirm "Install Netdata for real-time monitoring?"; then
        log "Installing Netdata..."
        
        # Download and install netdata
        bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait --disable-telemetry
        
        # Configure netdata
        backup_file /etc/netdata/netdata.conf
        
        cat > /etc/netdata/netdata.conf << 'EOF'
[global]
    # NetData Configuration
    run as user = netdata
    web files owner = root
    web files group = netdata
    bind socket to IP = 127.0.0.1
    default port = 19999
    disconnect idle clients after seconds = 60
    enable web responses gzip compression = yes
    
[web]
    web files owner = root
    web files group = netdata
    respect do not track policy = yes
    allow connections from = localhost 127.0.0.1 ::1
    allow dashboard from = localhost 127.0.0.1 ::1
    
[plugins]
    # Enable/disable plugins
    apps = yes
    cgroups = yes
    diskspace = yes
    proc = yes
    tc = no
    idlejitter = no
    
[health]
    enabled = yes
    default repeat warning = never
    default repeat critical = never
EOF

        # Create systemd override for security
        mkdir -p /etc/systemd/system/netdata.service.d
        cat > /etc/systemd/system/netdata.service.d/override.conf << 'EOF'
[Service]
# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/cache/netdata /var/lib/netdata /var/log/netdata
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictRealtime=true
EOF

        systemctl daemon-reload
        systemctl restart netdata
        systemctl enable netdata
        
        log "Netdata installed and configured"
        log "Access via: http://localhost:19999 (local only)" "$BLUE"
    fi
}

# Configure vnstat for network monitoring
configure_vnstat() {
    log "Configuring network statistics..."
    
    # Get primary network interface
    local interface=$(get_primary_interface)
    
    # Initialize vnstat database
    if vnstat -i "$interface" --create 2>/dev/null; then
        log "vnstat database created for interface $interface"
    elif vnstat -u -i "$interface" 2>/dev/null; then
        log "vnstat database initialized for interface $interface"
    else
        log "vnstat database initialization may have failed, but continuing..." "$YELLOW"
    fi
    
    # Configure vnstat
    backup_file /etc/vnstat.conf
    
    cat > /etc/vnstat.conf << EOF
# vnStat configuration

# Interface to monitor
Interface "$interface"

# Database directory
DatabaseDir "/var/lib/vnstat"

# Update interval in seconds (300 = 5 minutes)
UpdateInterval 300

# Log file
LogFile "/var/log/vnstat.log"

# Create directories if missing
CreateDirs yes

# Use UTC
UseUTC yes

# Monthly rotation day
MonthRotate 1

# Units (0=bytes, 1=bits)
RateUnit 1

# Default interface for queries
QueryMode 0
EOF

    # Enable and start vnstat
    systemctl enable vnstat
    systemctl start vnstat
    
    log "Network statistics configured for interface: $interface"
}

# Install and configure monit for process monitoring
configure_monit() {
    if confirm "Install Monit for process monitoring and auto-restart?"; then
        log "Configuring Monit..."
        
        backup_file /etc/monit/monitrc
        
        cat > /etc/monit/monitrc << 'EOF'
# Monit Configuration
# Check services and restart if needed

# Global settings
set daemon 120           # Check every 2 minutes
set log syslog

# HTTP interface (local only)
set httpd port 2812 and
    use address localhost
    allow localhost
    allow admin:monit

# System monitoring
check system $HOST
    if loadavg (1min) > 4 then alert
    if loadavg (5min) > 2 then alert
    if cpu usage > 95% for 10 cycles then alert
    if memory usage > 90% then alert
    if swap usage > 50% then alert

# Root filesystem
check filesystem rootfs with path /
    if space usage > 90% then alert
    if space usage > 95% then exec "/usr/local/bin/cleanup-logs.sh"
    if inode usage > 90% then alert

# SSH monitoring
check process sshd with pidfile /var/run/sshd.pid
    start program "/bin/systemctl start ssh"
    stop program "/bin/systemctl stop ssh"
    if failed host localhost port 22 protocol ssh then restart
    if 5 restarts within 5 cycles then timeout

# UFW firewall
check process ufw with matching "ufw"
    start program "/bin/systemctl start ufw"
    stop program "/bin/systemctl stop ufw"

# Fail2ban
check process fail2ban with pidfile /var/run/fail2ban/fail2ban.pid
    start program "/bin/systemctl start fail2ban"
    stop program "/bin/systemctl stop fail2ban"
    if 5 restarts within 5 cycles then timeout

# Docker (if installed)
check process docker with pidfile /var/run/docker.pid
    start program "/bin/systemctl start docker"
    stop program "/bin/systemctl stop docker"
    if failed unixsocket /var/run/docker.sock then restart
    if 5 restarts within 5 cycles then timeout

# Log file size monitoring
check file auth.log with path /var/log/auth.log
    if size > 100 MB then exec "/usr/sbin/logrotate -f /etc/logrotate.conf"

check file syslog with path /var/log/syslog
    if size > 100 MB then exec "/usr/sbin/logrotate -f /etc/logrotate.conf"
EOF

        # Create log cleanup script
        cat > /usr/local/bin/cleanup-logs.sh << 'EOF'
#!/bin/bash
# Emergency log cleanup when disk space is critical

echo "$(date): Emergency log cleanup triggered" >> /var/log/emergency-cleanup.log

# Clean old logs
find /var/log -name "*.log" -mtime +7 -delete
find /var/log -name "*.gz" -mtime +14 -delete

# Clean old journal logs
journalctl --vacuum-time=7d

# Clean package cache
apt-get clean

# Clean Docker logs if Docker is installed
if command -v docker >/dev/null 2>&1; then
    docker system prune -f --volumes --filter "until=168h"
fi

echo "$(date): Emergency cleanup completed" >> /var/log/emergency-cleanup.log
EOF

        chmod +x /usr/local/bin/cleanup-logs.sh
        chmod 600 /etc/monit/monitrc
        
        # Test monit configuration
        monit -t
        
        systemctl enable monit
        systemctl start monit
        
        log "Monit configured and started"
        log "Monit web interface: http://localhost:2812 (admin/monit)" "$BLUE"
    fi
}

# Configure systemd journal limits
configure_systemd_journal() {
    log "Configuring systemd journal limits..."
    
    backup_file /etc/systemd/journald.conf
    
    cat > /etc/systemd/journald.conf << 'EOF'
# Journald Configuration
[Journal]

# Limit journal size
SystemMaxUse=500M
SystemMaxFileSize=50M
SystemMaxFiles=10

# Retention time
MaxRetentionSec=2weeks

# Compression
Compress=yes

# Forward to syslog
ForwardToSyslog=yes

# Sync interval
SyncIntervalSec=60

# Rate limiting
RateLimitInterval=30s
RateLimitBurst=10000

# Storage
Storage=persistent
EOF

    # Restart journald
    systemctl restart systemd-journald
    
    log "Systemd journal configured with size limits"
}

# Install log analysis tools
install_log_analysis() {
    log "Installing log analysis tools..."
    
    # Install goaccess for web log analysis
    install_package goaccess
    
    # Create log analysis script
    cat > /usr/local/bin/analyze-logs.sh << 'EOF'
#!/bin/bash
# Log analysis script

echo "Log Analysis Report - $(date)"
echo "================================="
echo

echo "Failed SSH Login Attempts (last 24h):"
grep "Failed password" /var/log/auth.log | grep "$(date +'%b %d')" | wc -l

echo
echo "Top Failed SSH IPs:"
grep "Failed password" /var/log/auth.log | grep "$(date +'%b %d')" | \
    awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head -10

echo
echo "UFW Blocked Connections (last 24h):"
grep "UFW BLOCK" /var/log/ufw.log | grep "$(date +'%b %d')" | wc -l

echo
echo "Disk Usage:"
df -h / | tail -n 1

echo
echo "Memory Usage:"
free -h

echo
echo "System Load:"
uptime

echo
echo "Recent Errors in Syslog:"
grep -i error /var/log/syslog | tail -10

echo
echo "Fail2ban Status:"
fail2ban-client status 2>/dev/null || echo "Fail2ban not running"
EOF

    chmod +x /usr/local/bin/analyze-logs.sh
    
    log "Log analysis tools installed"
}

# Set up automated reporting
setup_automated_reporting() {
    if confirm "Set up daily system reports?"; then
        log "Setting up automated reporting..."
        
        # Create daily report script
        cat > /usr/local/bin/daily-report.sh << 'EOF'
#!/bin/bash
# Daily system report

REPORT_FILE="/var/log/daily-report-$(date +%Y%m%d).log"

{
    echo "Daily System Report - $(date)"
    echo "======================================"
    echo
    
    echo "SYSTEM INFORMATION:"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo
    
    echo "DISK USAGE:"
    df -h / /var /tmp 2>/dev/null
    echo
    
    echo "MEMORY USAGE:"
    free -h
    echo
    
    echo "TOP PROCESSES BY CPU:"
    ps aux --sort=-%cpu | head -6
    echo
    
    echo "TOP PROCESSES BY MEMORY:"
    ps aux --sort=-%mem | head -6
    echo
    
    echo "NETWORK STATISTICS:"
    vnstat -i $(ip route | grep default | awk '{print $5}' | head -1) -d | tail -8
    echo
    
    echo "SECURITY EVENTS:"
    echo "Failed SSH attempts today: $(grep "Failed password" /var/log/auth.log | grep "$(date +'%b %d')" | wc -l)"
    echo "UFW blocks today: $(grep "UFW BLOCK" /var/log/ufw.log | grep "$(date +'%b %d')" | wc -l)"
    echo "Fail2ban bans: $(fail2ban-client status | grep "Currently banned" | awk '{print $4}' || echo "0")"
    echo
    
    echo "DOCKER STATUS:" 
    if command -v docker >/dev/null 2>&1; then
        echo "Running containers: $(docker ps -q | wc -l)"
        echo "Total containers: $(docker ps -aq | wc -l)"
        echo "Images: $(docker images -q | wc -l)"
        docker system df
    else
        echo "Docker not installed"
    fi
    echo
    
    echo "RECENT ERRORS:"
    echo "System errors (last 24h):"
    journalctl --since "24 hours ago" --priority=err --no-pager -q | tail -5
    echo
    
    echo "SERVICE STATUS:"
    systemctl is-active ssh ufw fail2ban docker 2>/dev/null | paste <(echo -e "SSH\nUFW\nFail2ban\nDocker") -
    echo
    
} > "$REPORT_FILE"

# Keep only last 30 days of reports
find /var/log -name "daily-report-*.log" -mtime +30 -delete

# Optional: Email report (requires mail setup)
# mail -s "Daily Report - $(hostname)" admin@example.com < "$REPORT_FILE"
EOF

        chmod +x /usr/local/bin/daily-report.sh
        
        # Add to cron
        echo "0 6 * * * root /usr/local/bin/daily-report.sh" >> /etc/crontab
        
        log "Daily reporting configured (runs at 6 AM)"
        log "Reports saved to: /var/log/daily-report-YYYYMMDD.log" "$BLUE"
    fi
}

# Create monitoring dashboard script
create_monitoring_dashboard() {
    log "Creating monitoring dashboard..."
    
    cat > /usr/local/bin/dashboard.sh << 'EOF'
#!/bin/bash
# Simple monitoring dashboard

clear
echo "=========================================="
echo "          VPS Monitoring Dashboard"
echo "=========================================="
echo

# System info
echo "System: $(hostname) | $(date)"
echo "Uptime: $(uptime -p)"
echo "Load: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo

# Memory and disk
echo "Memory Usage:"
free -h | grep -E "Mem|Swap"
echo

echo "Disk Usage:"
df -h / | tail -1
echo

# Network
echo "Network ($(get_primary_interface)):"
vnstat -i $(get_primary_interface) | grep "today" || echo "No data yet"
echo

# Security
echo "Security Status:"
echo "  SSH failures today: $(grep "Failed password" /var/log/auth.log | grep "$(date +'%b %d')" | wc -l)"
echo "  UFW blocks today: $(grep "UFW BLOCK" /var/log/ufw.log | grep "$(date +'%b %d')" | wc -l 2>/dev/null || echo "0")"
echo "  Fail2ban active: $(systemctl is-active fail2ban)"
echo

# Docker
if command -v docker >/dev/null 2>&1; then
    echo "Docker Status:"
    echo "  Running containers: $(docker ps -q | wc -l)"
    echo "  Service status: $(systemctl is-active docker)"
    echo
fi

# Top processes
echo "Top Processes (CPU):"
ps aux --sort=-%cpu | head -4 | tail -3 | awk '{print "  " $11 " (" $3 "%)"}'
echo

echo "=========================================="
echo "Commands:"
echo "  htop          - Process monitor"
echo "  glances       - All-in-one monitor"
echo "  analyze-logs  - Log analysis"
echo "  vnstat        - Network statistics"
if systemctl is-active netdata >/dev/null 2>&1; then
    echo "  Netdata       - http://localhost:19999"
fi
if systemctl is-active monit >/dev/null 2>&1; then
    echo "  Monit         - http://localhost:2812"
fi
echo "=========================================="
EOF

    chmod +x /usr/local/bin/dashboard.sh
    
    # Add alias to bashrc
    echo "alias dashboard='/usr/local/bin/dashboard.sh'" >> /etc/bash.bashrc
    
    log "Monitoring dashboard created"
    log "Run 'dashboard' command to view system status" "$BLUE"
}

# Main execution
main() {
    install_monitoring_tools
    configure_logrotate
    configure_vnstat
    configure_systemd_journal
    install_log_analysis
    
    # Optional components
    install_netdata
    configure_monit
    setup_automated_reporting
    
    # Always create dashboard
    create_monitoring_dashboard
    
    log "Monitoring & Logging Setup completed successfully!" "$GREEN"
    
    echo
    log "Monitoring tools installed:" "$BLUE"
    log "- Basic tools: htop, iotop, glances, vnstat" "$BLUE"
    log "- Log analysis: analyze-logs command" "$BLUE"
    log "- Dashboard: dashboard command" "$BLUE"
    
    if systemctl is-active netdata >/dev/null 2>&1; then
        log "- Netdata: http://localhost:19999" "$BLUE"
    fi
    
    if systemctl is-active monit >/dev/null 2>&1; then
        log "- Monit: http://localhost:2812 (admin/monit)" "$BLUE"
    fi
    
    log "Daily reports: /var/log/daily-report-YYYYMMDD.log" "$BLUE"
}

# Run main
main