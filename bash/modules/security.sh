#!/bin/bash

# Security Hardening Module
# Implements comprehensive security hardening for Ubuntu

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting Security Hardening Module" "$BLUE"

# Kernel hardening via sysctl
harden_kernel() {
    log "Hardening kernel parameters..."
    
    backup_file /etc/sysctl.conf
    
    # Create custom sysctl configuration
    cat > /etc/sysctl.d/99-security-hardening.conf << 'EOF'
# Security Hardening - Kernel Parameters
# Added by VPS setup script

# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore Directed pings
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Enable TCP/IP SYN cookies
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Increase system file descriptor limit
fs.file-max = 65535

# Increase number of PTYs
kernel.pty.max = 16384

# Restrict core dumps
kernel.core_uses_pid = 1
fs.suid_dumpable = 0

# Restrict access to kernel logs
kernel.dmesg_restrict = 1

# Restrict ptrace scope
kernel.yama.ptrace_scope = 1

# Harden BPF JIT
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# Restrict loading TTY line disciplines
dev.tty.ldisc_autoload = 0

# Restrict userfaultfd
kernel.unprivileged_userfaultfd = 0

# Increase ASLR randomization
kernel.randomize_va_space = 2

# Restrict performance events
kernel.perf_event_paranoid = 3

# Restrict kexec
kernel.kexec_load_disabled = 1
EOF

    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-security-hardening.conf > /dev/null 2>&1
    
    log "Kernel parameters hardened" "$GREEN"
}

# Configure AppArmor
configure_apparmor() {
    log "Configuring AppArmor..."
    
    # Install AppArmor utilities
    install_package apparmor-utils
    install_package apparmor-profiles
    install_package apparmor-profiles-extra
    
    # Enable AppArmor
    systemctl enable apparmor
    systemctl start apparmor
    
    # Put all profiles in enforce mode
    log "Enforcing AppArmor profiles..."
    aa-enforce /etc/apparmor.d/* 2>/dev/null || true
    
    # Show status
    log "AppArmor status:" "$BLUE"
    aa-status --summary 2>/dev/null || true
    
    log "AppArmor configured and enabled" "$GREEN"
}

# Install and configure AIDE
configure_aide() {
    if confirm "Install AIDE (Advanced Intrusion Detection Environment)?"; then
        log "Installing and configuring AIDE..."
        
        # Install AIDE
        install_package aide aide-common
        
        # Initialize AIDE database
        log "Initializing AIDE database (this may take a while)..."
        aideinit
        
        # Copy the database
        cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
        
        # Create daily check script
        cat > /etc/cron.daily/aide-check << 'EOF'
#!/bin/bash
# Daily AIDE check

AIDE_LOG="/var/log/aide/aide-check-$(date +%Y%m%d).log"
mkdir -p /var/log/aide

/usr/bin/aide --check > "$AIDE_LOG" 2>&1

if [ $? -ne 0 ]; then
    echo "AIDE detected changes. Check $AIDE_LOG for details."
    # Optional: Send alert email
    # mail -s "AIDE Alert on $(hostname)" admin@example.com < "$AIDE_LOG"
fi

# Rotate old logs
find /var/log/aide -name "aide-check-*.log" -mtime +30 -delete
EOF
        
        chmod +x /etc/cron.daily/aide-check
        
        log "AIDE configured with daily checks" "$GREEN"
    fi
}

# Configure auditd
configure_auditd() {
    log "Configuring system auditing..."
    
    # Install auditd
    install_package auditd audispd-plugins
    
    # Configure audit rules
    cat > /etc/audit/rules.d/hardening.rules << 'EOF'
# Security Hardening Audit Rules

# Delete all rules
-D

# Buffer size
-b 8192

# Failure mode
-f 1

# Monitor authentication
-w /etc/passwd -p wa -k passwd_changes
-w /etc/group -p wa -k group_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitor SSH
-w /etc/ssh/sshd_config -p wa -k ssh_config

# Monitor system calls
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time_change
-a always,exit -F arch=b64 -S clock_settime -k time_change
-a always,exit -F arch=b32 -S clock_settime -k time_change

# Monitor file operations
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete

# Monitor privilege escalation
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation
-a always,exit -F arch=b32 -S setuid -S setgid -S setreuid32 -S setregid32 -k privilege_escalation

# Monitor unauthorized access
-a always,exit -F arch=b64 -S open -F dir=/etc -F success=0 -k unauthorized_access
-a always,exit -F arch=b64 -S open -F dir=/bin -F success=0 -k unauthorized_access
-a always,exit -F arch=b64 -S open -F dir=/usr/bin -F success=0 -k unauthorized_access

# Make configuration immutable
-e 2
EOF

    # Reload audit rules
    augenrules --load
    systemctl restart auditd
    
    log "Audit daemon configured" "$GREEN"
}

# Disable unnecessary services
disable_unnecessary_services() {
    log "Disabling unnecessary services..."
    
    local services=(
        "avahi-daemon"
        "cups"
        "rpcbind"
        "rsync"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" 2>/dev/null | grep -q "enabled"; then
            if confirm "Disable $service service?"; then
                systemctl stop "$service" 2>/dev/null || true
                systemctl disable "$service" 2>/dev/null || true
                log "Disabled $service"
            fi
        fi
    done
}

# Secure shared memory
secure_shared_memory() {
    log "Securing shared memory..."
    
    if ! grep -q "/run/shm" /etc/fstab; then
        echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
        mount -o remount /run/shm
        log "Shared memory secured"
    else
        log "Shared memory already configured" "$BLUE"
    fi
}

# Configure file permissions
secure_file_permissions() {
    log "Securing file permissions..."
    
    # Secure sensitive files
    local files=(
        "/etc/passwd:644"
        "/etc/shadow:640"
        "/etc/group:644"
        "/etc/gshadow:640"
        "/etc/ssh/sshd_config:600"
        "/boot/grub/grub.cfg:600"
        "/etc/crontab:600"
        "/etc/cron.hourly:700"
        "/etc/cron.daily:700"
        "/etc/cron.weekly:700"
        "/etc/cron.monthly:700"
        "/etc/cron.d:700"
    )
    
    for file_perm in "${files[@]}"; do
        IFS=':' read -r file perm <<< "$file_perm"
        if [[ -e "$file" ]]; then
            chmod "$perm" "$file"
            log "Set permissions for $file to $perm"
        fi
    done
    
    # Find and fix world-writable files
    log "Checking for world-writable files..."
    local writable_files=$(find / -xdev -type f -perm -0002 2>/dev/null | head -20)
    
    if [[ -n "$writable_files" ]]; then
        log "Found world-writable files:" "$YELLOW"
        echo "$writable_files"
        
        if confirm "Fix permissions on world-writable files?"; then
            find / -xdev -type f -perm -0002 -exec chmod o-w {} \; 2>/dev/null
            log "World-writable file permissions fixed"
        fi
    fi
}

# Install security tools
install_security_tools() {
    log "Installing additional security tools..."
    
    local tools=(
        "rkhunter"          # Rootkit scanner
        "chkrootkit"        # Another rootkit scanner
        "lynis"             # Security auditing tool
        "debsums"           # Verify installed packages
        "libpam-tmpdir"     # Temporary directory isolation
        "apt-listbugs"      # Check for bugs before installing
        "apt-listchanges"   # Show changelogs
        "needrestart"       # Check for services needing restart
    )
    
    for tool in "${tools[@]}"; do
        install_package "$tool"
    done
    
    # Configure rkhunter
    if command_exists rkhunter; then
        log "Updating rkhunter database..."
        rkhunter --update 2>/dev/null || true
        rkhunter --propupd 2>/dev/null || true
    fi
}

# Configure fail2ban additional jails
configure_fail2ban_extras() {
    log "Configuring additional fail2ban jails..."
    
    # Create custom jail for repeated auth failures
    cat > /etc/fail2ban/jail.d/auth.conf << EOF
[pam-generic]
enabled = true
filter = pam-generic
logpath = /var/log/auth.log
maxretry = 5
bantime = 1800
findtime = 600

[postfix]
enabled = false
filter = postfix
logpath = /var/log/mail.log
maxretry = 3
bantime = 3600
EOF

    # Restart fail2ban
    systemctl restart fail2ban
    
    log "Additional fail2ban jails configured"
}

# Create security report
create_security_report() {
    local report_file="/root/security-report.txt"
    
    log "Creating security report..."
    
    {
        echo "Security Hardening Report"
        echo "Generated on: $(date)"
        echo "========================"
        echo
        
        echo "System Information:"
        echo "- Hostname: $(hostname)"
        echo "- IP Address: $(get_primary_ip)"
        echo "- Kernel: $(uname -r)"
        echo
        
        echo "Security Status:"
        echo "- UFW Status: $(ufw status | grep Status | cut -d: -f2)"
        echo "- AppArmor: $(systemctl is-active apparmor)"
        echo "- Auditd: $(systemctl is-active auditd)"
        echo "- Fail2ban: $(systemctl is-active fail2ban)"
        echo
        
        echo "Open Ports:"
        ss -tuln | grep LISTEN
        echo
        
        echo "Failed Login Attempts (last 10):"
        grep "Failed password" /var/log/auth.log | tail -10 || echo "None found"
        echo
        
        echo "Recommendations:"
        echo "- Run 'lynis audit system' for detailed security audit"
        echo "- Run 'rkhunter --check' for rootkit scan"
        echo "- Review audit logs in /var/log/audit/"
        echo "- Check fail2ban status with 'fail2ban-client status'"
    } > "$report_file"
    
    chmod 600 "$report_file"
    log "Security report saved to $report_file" "$GREEN"
}

# Main execution
main() {
    # Kernel hardening
    harden_kernel
    
    # Security frameworks
    configure_apparmor
    configure_aide
    configure_auditd
    
    # System hardening
    disable_unnecessary_services
    secure_shared_memory
    secure_file_permissions
    
    # Additional security
    install_security_tools
    configure_fail2ban_extras
    
    # Generate report
    create_security_report
    
    log "Security Hardening Module completed successfully!" "$GREEN"
    
    # Show next steps
    echo
    log "Recommended next steps:" "$YELLOW"
    log "1. Run 'lynis audit system' for a comprehensive security audit" "$YELLOW"
    log "2. Review the security report at /root/security-report.txt" "$YELLOW"
    log "3. Configure AIDE alerts if needed" "$YELLOW"
    log "4. Set up log monitoring and alerting" "$YELLOW"
}

# Run main
main