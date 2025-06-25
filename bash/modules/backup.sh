#!/bin/bash

# Backup Configuration Module
# Sets up automated backup solutions for system and data

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting Backup Configuration Module" "$BLUE"

# Global variables
BACKUP_ROOT="/opt/backups"
BACKUP_USER="backup"

# Install backup tools
install_backup_tools() {
    log "Installing backup tools..."
    
    local tools=(
        rsync           # File synchronization
        duplicity       # Encrypted backup
        rdiff-backup    # Incremental backup
        borgbackup      # Deduplicating backup
        rclone          # Cloud storage sync
        restic          # Modern backup tool
        tar             # Archive utility
        gzip            # Compression
        pigz            # Parallel gzip
        pv              # Progress viewer
        tree            # Directory listing
        curl            # For upload/download
        sqlite3         # For backup databases
    )
    
    for tool in "${tools[@]}"; do
        install_package "$tool"
    done
    
    log "Backup tools installed" "$GREEN"
}

# Create backup directory structure
create_backup_structure() {
    log "Creating backup directory structure..."
    
    # Create main backup directories
    local dirs=(
        "$BACKUP_ROOT"
        "$BACKUP_ROOT/system"
        "$BACKUP_ROOT/configs"
        "$BACKUP_ROOT/data"
        "$BACKUP_ROOT/databases"
        "$BACKUP_ROOT/docker"
        "$BACKUP_ROOT/logs"
        "$BACKUP_ROOT/scripts"
        "$BACKUP_ROOT/tmp"
    )
    
    for dir in "${dirs[@]}"; do
        ensure_dir "$dir"
        chmod 750 "$dir"
    done
    
    # Create backup user if not exists
    if ! id "$BACKUP_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$BACKUP_ROOT" -c "Backup User" "$BACKUP_USER"
        log "Created backup user: $BACKUP_USER"
    fi
    
    # Set ownership
    chown -R "$BACKUP_USER:$BACKUP_USER" "$BACKUP_ROOT"
    
    log "Backup structure created in $BACKUP_ROOT"
}

# Configure system backup
configure_system_backup() {
    log "Configuring system backup..."
    
    cat > "$BACKUP_ROOT/scripts/system-backup.sh" << 'EOF'
#!/bin/bash
# System Backup Script

set -euo pipefail

BACKUP_ROOT="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$BACKUP_ROOT/logs/system-backup-$DATE.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting system backup..."

# Create backup directories
mkdir -p "$BACKUP_ROOT/system/$DATE"
cd "$BACKUP_ROOT/system/$DATE"

# System configuration files
log "Backing up system configurations..."
tar -czf configs.tar.gz \
    /etc/passwd \
    /etc/group \
    /etc/shadow \
    /etc/gshadow \
    /etc/hosts \
    /etc/hostname \
    /etc/fstab \
    /etc/crontab \
    /etc/ssh/ \
    /etc/sudoers* \
    /etc/systemd/system/ \
    /etc/ufw/ \
    /etc/fail2ban/ \
    /etc/logrotate.d/ \
    /etc/apt/sources.list* \
    /etc/default/ \
    /etc/sysctl.d/ \
    /etc/security/ \
    /etc/docker/ \
    2>/dev/null || true

# Installed packages list
log "Backing up package information..."
dpkg --get-selections > packages.list
apt-mark showmanual > packages-manual.list

# System information
log "Collecting system information..."
{
    echo "Hostname: $(hostname)"
    echo "Date: $(date)"
    echo "Kernel: $(uname -a)"
    echo "Distribution: $(lsb_release -a 2>/dev/null)"
    echo "Memory: $(free -h)"
    echo "Disk: $(df -h)"
    echo "Network: $(ip addr show)"
    echo "Services: $(systemctl list-unit-files --state=enabled)"
} > system-info.txt

# User home directories (excluding large files)
log "Backing up user configurations..."
tar -czf user-configs.tar.gz \
    --exclude="*.log" \
    --exclude="*.cache" \
    --exclude="*.tmp" \
    --exclude="node_modules" \
    --exclude=".git" \
    /home/ /root/ \
    2>/dev/null || true

# Docker data (if Docker is installed)
if command -v docker >/dev/null 2>&1; then
    log "Backing up Docker data..."
    
    # Docker images list
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" > docker-images.list
    
    # Docker containers list
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" > docker-containers.list
    
    # Docker compose files
    find /opt/docker -name "docker-compose.yml" -o -name "docker-compose.yaml" | \
        tar -czf docker-compose-files.tar.gz -T - 2>/dev/null || true
fi

# Cron jobs
log "Backing up cron jobs..."
{
    echo "=== Root Crontab ==="
    crontab -l 2>/dev/null || echo "No root crontab"
    echo
    echo "=== System Crontab ==="
    cat /etc/crontab
    echo
    echo "=== Cron.d Files ==="
    find /etc/cron.d -type f -exec echo "=== {} ===" \; -exec cat {} \; 2>/dev/null || true
} > cron-jobs.txt

# UFW rules
log "Backing up firewall rules..."
ufw status verbose > ufw-rules.txt 2>/dev/null || true
iptables-save > iptables-rules.txt 2>/dev/null || true

# Generate checksums
log "Generating checksums..."
find . -type f -exec sha256sum {} \; > checksums.sha256

# Cleanup old backups (keep last 30 days)
log "Cleaning up old backups..."
find "$BACKUP_ROOT/system" -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null || true

log "System backup completed: $BACKUP_ROOT/system/$DATE"

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_ROOT/system/$DATE" | cut -f1)
log "Backup size: $BACKUP_SIZE"

# Optional: Send notification
# echo "System backup completed on $(hostname). Size: $BACKUP_SIZE" | \
#     mail -s "Backup Report - $(hostname)" admin@example.com
EOF

    chmod +x "$BACKUP_ROOT/scripts/system-backup.sh"
    chown "$BACKUP_USER:$BACKUP_USER" "$BACKUP_ROOT/scripts/system-backup.sh"
    
    log "System backup script created"
}

# Configure database backup
configure_database_backup() {
    log "Configuring database backup..."
    
    cat > "$BACKUP_ROOT/scripts/database-backup.sh" << 'EOF'
#!/bin/bash
# Database Backup Script

set -euo pipefail

BACKUP_ROOT="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$BACKUP_ROOT/logs/db-backup-$DATE.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting database backup..."

# Create backup directory
mkdir -p "$BACKUP_ROOT/databases/$DATE"
cd "$BACKUP_ROOT/databases/$DATE"

# MySQL/MariaDB backup
if command -v mysqldump >/dev/null 2>&1 && systemctl is-active mysql >/dev/null 2>&1; then
    log "Backing up MySQL databases..."
    
    # Get list of databases
    DATABASES=$(mysql -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")
    
    for db in $DATABASES; do
        log "Backing up database: $db"
        mysqldump --single-transaction --routines --triggers "$db" | gzip > "${db}.sql.gz"
    done
fi

# PostgreSQL backup
if command -v pg_dump >/dev/null 2>&1 && systemctl is-active postgresql >/dev/null 2>&1; then
    log "Backing up PostgreSQL databases..."
    
    # Backup all databases
    sudo -u postgres pg_dumpall | gzip > postgresql-all.sql.gz
    
    # Individual databases
    DATABASES=$(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;")
    for db in $DATABASES; do
        if [[ -n "$db" ]] && [[ "$db" != "postgres" ]]; then
            log "Backing up PostgreSQL database: $db"
            sudo -u postgres pg_dump "$db" | gzip > "${db}-postgresql.sql.gz"
        fi
    done
fi

# MongoDB backup
if command -v mongodump >/dev/null 2>&1 && systemctl is-active mongod >/dev/null 2>&1; then
    log "Backing up MongoDB..."
    mongodump --out mongodb-dump
    tar -czf mongodb-dump.tar.gz mongodb-dump/
    rm -rf mongodb-dump/
fi

# Redis backup
if command -v redis-cli >/dev/null 2>&1 && systemctl is-active redis >/dev/null 2>&1; then
    log "Backing up Redis..."
    redis-cli --rdb redis-dump.rdb
    gzip redis-dump.rdb
fi

# SQLite databases
log "Looking for SQLite databases..."
find /opt /var /home -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" 2>/dev/null | while read db; do
    if [[ -r "$db" ]]; then
        log "Backing up SQLite database: $db"
        cp "$db" "$(basename "$db")-$(date +%H%M%S)"
    fi
done

# Generate checksums
find . -type f -exec sha256sum {} \; > checksums.sha256

# Cleanup old backups (keep last 14 days)
find "$BACKUP_ROOT/databases" -maxdepth 1 -type d -mtime +14 -exec rm -rf {} \; 2>/dev/null || true

log "Database backup completed: $BACKUP_ROOT/databases/$DATE"
EOF

    chmod +x "$BACKUP_ROOT/scripts/database-backup.sh"
    chown "$BACKUP_USER:$BACKUP_USER" "$BACKUP_ROOT/scripts/database-backup.sh"
    
    log "Database backup script created"
}

# Configure Docker backup
configure_docker_backup() {
    if command -v docker >/dev/null 2>&1; then
        log "Configuring Docker backup..."
        
        cat > "$BACKUP_ROOT/scripts/docker-backup.sh" << 'EOF'
#!/bin/bash
# Docker Backup Script

set -euo pipefail

BACKUP_ROOT="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$BACKUP_ROOT/logs/docker-backup-$DATE.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting Docker backup..."

# Create backup directory
mkdir -p "$BACKUP_ROOT/docker/$DATE"
cd "$BACKUP_ROOT/docker/$DATE"

# Backup Docker volumes
log "Backing up Docker volumes..."
docker volume ls -q | while read volume; do
    if [[ -n "$volume" ]]; then
        log "Backing up volume: $volume"
        docker run --rm -v "$volume":/data -v "$(pwd)":/backup alpine \
            tar -czf "/backup/volume-${volume}.tar.gz" -C /data . 2>/dev/null || {
            log "Failed to backup volume: $volume"
        }
    fi
done

# Backup Docker Compose projects
log "Backing up Docker Compose files..."
find /opt/docker -name "docker-compose.yml" -o -name "docker-compose.yaml" | while read compose_file; do
    project_dir=$(dirname "$compose_file")
    project_name=$(basename "$project_dir")
    
    log "Backing up compose project: $project_name"
    
    # Create project backup directory
    mkdir -p "compose-$project_name"
    
    # Copy compose files and configs
    cp -r "$project_dir"/* "compose-$project_name/" 2>/dev/null || true
    
    # Export running containers for this project
    if [[ -f "$compose_file" ]]; then
        cd "$project_dir"
        docker-compose ps --services 2>/dev/null | while read service; do
            container_id=$(docker-compose ps -q "$service" 2>/dev/null)
            if [[ -n "$container_id" ]]; then
                log "Exporting container: $service"
                docker export "$container_id" | gzip > "$BACKUP_ROOT/docker/$DATE/compose-$project_name/${service}-container.tar.gz"
            fi
        done
        cd "$BACKUP_ROOT/docker/$DATE"
    fi
done

# Backup standalone containers
log "Backing up standalone containers..."
docker ps -a --format "{{.Names}}" | while read container; do
    if [[ -n "$container" ]]; then
        # Skip compose containers (they have project prefixes)
        if [[ ! "$container" =~ _.*_[0-9]+$ ]]; then
            log "Backing up container: $container"
            docker export "$container" | gzip > "container-${container}.tar.gz" 2>/dev/null || {
                log "Failed to backup container: $container"
            }
        fi
    fi
done

# Export Docker images list
log "Exporting Docker images list..."
docker images --format "{{.Repository}}:{{.Tag}}" > docker-images.list

# Export container information
log "Exporting container information..."
{
    echo "=== Running Containers ==="
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    echo
    echo "=== All Containers ==="
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    echo
    echo "=== Volumes ==="
    docker volume ls
    echo
    echo "=== Networks ==="
    docker network ls
} > docker-info.txt

# Generate checksums
find . -type f -exec sha256sum {} \; > checksums.sha256

# Cleanup old backups (keep last 7 days)
find "$BACKUP_ROOT/docker" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

log "Docker backup completed: $BACKUP_ROOT/docker/$DATE"
EOF

        chmod +x "$BACKUP_ROOT/scripts/docker-backup.sh"
        chown "$BACKUP_USER:$BACKUP_USER" "$BACKUP_ROOT/scripts/docker-backup.sh"
        
        log "Docker backup script created"
    fi
}

# Setup automated backup scheduling
setup_backup_scheduling() {
    log "Setting up backup scheduling..."
    
    # Create master backup script
    cat > "$BACKUP_ROOT/scripts/run-backups.sh" << 'EOF'
#!/bin/bash
# Master Backup Script

set -euo pipefail

BACKUP_ROOT="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$BACKUP_ROOT/logs/master-backup-$DATE.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting master backup process..."

# Ensure log directory exists
mkdir -p "$BACKUP_ROOT/logs"

# Run system backup
if [[ -x "$BACKUP_ROOT/scripts/system-backup.sh" ]]; then
    log "Running system backup..."
    sudo -u backup "$BACKUP_ROOT/scripts/system-backup.sh"
else
    log "System backup script not found or not executable"
fi

# Run database backup
if [[ -x "$BACKUP_ROOT/scripts/database-backup.sh" ]]; then
    log "Running database backup..."
    sudo -u backup "$BACKUP_ROOT/scripts/database-backup.sh"
else
    log "Database backup script not found or not executable"
fi

# Run Docker backup
if [[ -x "$BACKUP_ROOT/scripts/docker-backup.sh" ]] && command -v docker >/dev/null 2>&1; then
    log "Running Docker backup..."
    sudo -u backup "$BACKUP_ROOT/scripts/docker-backup.sh"
else
    log "Docker backup script not found, not executable, or Docker not installed"
fi

# Cleanup old logs (keep last 30 days)
find "$BACKUP_ROOT/logs" -name "*.log" -mtime +30 -delete 2>/dev/null || true

# Calculate total backup size
TOTAL_SIZE=$(du -sh "$BACKUP_ROOT" | cut -f1)
log "Total backup size: $TOTAL_SIZE"

log "Master backup process completed"

# Optional: Send summary email
# echo "Backup completed on $(hostname) at $(date). Total size: $TOTAL_SIZE" | \
#     mail -s "Backup Summary - $(hostname)" admin@example.com
EOF

    chmod +x "$BACKUP_ROOT/scripts/run-backups.sh"
    
    # Add to cron with automated response handling
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]] || confirm "Set up automated daily backups?"; then
        # Daily backup at 2 AM
        echo "0 2 * * * root $BACKUP_ROOT/scripts/run-backups.sh" >> /etc/crontab
        
        # Weekly full backup on Sunday at 3 AM
        echo "0 3 * * 0 root $BACKUP_ROOT/scripts/system-backup.sh" >> /etc/crontab
        
        log "Backup scheduling configured (daily at 2 AM, weekly full on Sunday at 3 AM)"
    fi
}

# Create backup restoration scripts
create_restore_scripts() {
    log "Creating restoration scripts..."
    
    cat > "$BACKUP_ROOT/scripts/restore-system.sh" << 'EOF'
#!/bin/bash
# System Restoration Script

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <backup_date>"
    echo "Available backups:"
    ls -1 /opt/backups/system/ 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_DATE="$1"
BACKUP_DIR="/opt/backups/system/$BACKUP_DATE"
LOG_FILE="/opt/backups/logs/restore-$BACKUP_DATE-$(date +%H%M%S).log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

log "Starting system restoration from: $BACKUP_DIR"

cd "$BACKUP_DIR"

# Verify checksums
log "Verifying backup integrity..."
if [[ -f checksums.sha256 ]]; then
    if sha256sum -c checksums.sha256 >/dev/null 2>&1; then
        log "Backup integrity verified"
    else
        log "WARNING: Backup integrity check failed!"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

echo "WARNING: This will restore system configurations!"
echo "Current configurations will be backed up to /tmp/restore-backup-$(date +%Y%m%d_%H%M%S)"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Create safety backup
SAFETY_BACKUP="/tmp/restore-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$SAFETY_BACKUP"
tar -czf "$SAFETY_BACKUP/current-configs.tar.gz" /etc/ 2>/dev/null || true

# Restore configurations
if [[ -f configs.tar.gz ]]; then
    log "Restoring system configurations..."
    tar -xzf configs.tar.gz -C / 2>/dev/null || true
fi

# Restore packages
if [[ -f packages.list ]]; then
    log "Restoring packages..."
    dpkg --set-selections < packages.list
    apt-get dselect-upgrade -y
fi

log "System restoration completed"
log "Original configs backed up to: $SAFETY_BACKUP"
log "Please reboot the system to ensure all changes take effect"
EOF

    chmod +x "$BACKUP_ROOT/scripts/restore-system.sh"
    
    # Create Docker restore script
    cat > "$BACKUP_ROOT/scripts/restore-docker.sh" << 'EOF'
#!/bin/bash
# Docker Restoration Script

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <backup_date>"
    echo "Available backups:"
    ls -1 /opt/backups/docker/ 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_DATE="$1"
BACKUP_DIR="/opt/backups/docker/$BACKUP_DATE"
LOG_FILE="/opt/backups/logs/restore-docker-$BACKUP_DATE-$(date +%H%M%S).log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed"
    exit 1
fi

log "Starting Docker restoration from: $BACKUP_DIR"

cd "$BACKUP_DIR"

echo "WARNING: This will restore Docker volumes and containers!"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Restore volumes
log "Restoring Docker volumes..."
find . -name "volume-*.tar.gz" | while read volume_backup; do
    volume_name=$(basename "$volume_backup" .tar.gz | sed 's/^volume-//')
    log "Restoring volume: $volume_name"
    
    # Create volume if it doesn't exist
    docker volume create "$volume_name" >/dev/null 2>&1 || true
    
    # Restore data
    docker run --rm -v "$volume_name":/data -v "$(pwd)":/backup alpine \
        tar -xzf "/backup/$volume_backup" -C /data 2>/dev/null || {
        log "Failed to restore volume: $volume_name"
    }
done

# Restore compose projects
log "Restoring Docker Compose projects..."
find . -type d -name "compose-*" | while read compose_dir; do
    project_name=$(basename "$compose_dir" | sed 's/^compose-//')
    target_dir="/opt/docker/$project_name"
    
    log "Restoring compose project: $project_name to $target_dir"
    mkdir -p "$target_dir"
    cp -r "$compose_dir"/* "$target_dir/"
done

log "Docker restoration completed"
log "Please review restored compose projects in /opt/docker/"
EOF

    chmod +x "$BACKUP_ROOT/scripts/restore-docker.sh"
    
    # Set ownership
    chown "$BACKUP_USER:$BACKUP_USER" "$BACKUP_ROOT/scripts/"*.sh
    
    log "Restoration scripts created"
}

# Create backup monitoring and alerts
setup_backup_monitoring() {
    log "Setting up backup monitoring..."
    
    cat > "$BACKUP_ROOT/scripts/check-backups.sh" << 'EOF'
#!/bin/bash
# Backup Monitoring Script

set -euo pipefail

BACKUP_ROOT="/opt/backups"
LOG_FILE="$BACKUP_ROOT/logs/backup-check-$(date +%Y%m%d).log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup monitoring check..."

# Check if backups are recent
ALERT_DAYS=2
BACKUP_DIRS=("system" "databases" "docker")

for backup_type in "${BACKUP_DIRS[@]}"; do
    backup_dir="$BACKUP_ROOT/$backup_type"
    
    if [[ -d "$backup_dir" ]]; then
        latest_backup=$(find "$backup_dir" -maxdepth 1 -type d -name "20*" | sort | tail -1)
        
        if [[ -n "$latest_backup" ]]; then
            backup_age=$(find "$latest_backup" -maxdepth 0 -mtime +$ALERT_DAYS | wc -l)
            
            if [[ $backup_age -gt 0 ]]; then
                log "WARNING: $backup_type backup is older than $ALERT_DAYS days"
                echo "Backup alert: $backup_type backup on $(hostname) is older than $ALERT_DAYS days" >> /tmp/backup-alerts.txt
            else
                log "OK: $backup_type backup is recent"
            fi
        else
            log "WARNING: No $backup_type backups found"
            echo "Backup alert: No $backup_type backups found on $(hostname)" >> /tmp/backup-alerts.txt
        fi
    fi
done

# Check backup sizes (alert if too small)
MIN_SIZE_KB=1000  # 1MB minimum

for backup_type in "${BACKUP_DIRS[@]}"; do
    backup_dir="$BACKUP_ROOT/$backup_type"
    
    if [[ -d "$backup_dir" ]]; then
        latest_backup=$(find "$backup_dir" -maxdepth 1 -type d -name "20*" | sort | tail -1)
        
        if [[ -n "$latest_backup" ]]; then
            backup_size_kb=$(du -sk "$latest_backup" | cut -f1)
            
            if [[ $backup_size_kb -lt $MIN_SIZE_KB ]]; then
                log "WARNING: $backup_type backup is suspiciously small: ${backup_size_kb}KB"
                echo "Backup alert: $backup_type backup on $(hostname) is only ${backup_size_kb}KB" >> /tmp/backup-alerts.txt
            else
                log "OK: $backup_type backup size: ${backup_size_kb}KB"
            fi
        fi
    fi
done

# Check disk space
BACKUP_USAGE=$(df "$BACKUP_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $BACKUP_USAGE -gt 90 ]]; then
    log "WARNING: Backup disk usage is $BACKUP_USAGE%"
    echo "Backup alert: Backup disk on $(hostname) is $BACKUP_USAGE% full" >> /tmp/backup-alerts.txt
fi

# Send alerts if any exist
if [[ -f /tmp/backup-alerts.txt ]]; then
    log "Backup alerts found, check /tmp/backup-alerts.txt"
    # Optional: Send email alerts
    # mail -s "Backup Alerts - $(hostname)" admin@example.com < /tmp/backup-alerts.txt
    # rm /tmp/backup-alerts.txt
else
    log "All backup checks passed"
fi

log "Backup monitoring check completed"
EOF

    chmod +x "$BACKUP_ROOT/scripts/check-backups.sh"
    chown "$BACKUP_USER:$BACKUP_USER" "$BACKUP_ROOT/scripts/check-backups.sh"
    
    # Add daily backup check to cron
    echo "0 8 * * * root $BACKUP_ROOT/scripts/check-backups.sh" >> /etc/crontab
    
    log "Backup monitoring configured (daily check at 8 AM)"
}

# Create backup management commands
create_backup_commands() {
    log "Creating backup management commands..."
    
    # Create backup command
    cat > /usr/local/bin/backup-now << 'EOF'
#!/bin/bash
# Manual backup trigger

echo "Starting manual backup..."
/opt/backups/scripts/run-backups.sh
echo "Manual backup completed"
EOF

    # Create backup status command
    cat > /usr/local/bin/backup-status << 'EOF'
#!/bin/bash
# Backup status check

echo "Backup Status Report"
echo "==================="
echo

BACKUP_ROOT="/opt/backups"

# Show recent backups
for backup_type in system databases docker; do
    echo "$backup_type backups:"
    if [[ -d "$BACKUP_ROOT/$backup_type" ]]; then
        find "$BACKUP_ROOT/$backup_type" -maxdepth 1 -type d -name "20*" | sort | tail -5 | while read backup; do
            backup_date=$(basename "$backup")
            backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1)
            echo "  $backup_date ($backup_size)"
        done
    else
        echo "  No backups found"
    fi
    echo
done

# Show disk usage
echo "Backup disk usage:"
df -h "$BACKUP_ROOT" | tail -1
echo

# Show last backup times
echo "Last backup times:"
for backup_type in system databases docker; do
    latest=$(find "$BACKUP_ROOT/$backup_type" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort | tail -1)
    if [[ -n "$latest" ]]; then
        echo "  $backup_type: $(stat -c %y "$latest" | cut -d. -f1)"
    else
        echo "  $backup_type: Never"
    fi
done
EOF

    # Create restore command
    cat > /usr/local/bin/backup-restore << 'EOF'
#!/bin/bash
# Backup restoration helper

echo "Backup Restoration Helper"
echo "========================"
echo

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <system|docker> [backup_date]"
    echo
    echo "Available system backups:"
    ls -1 /opt/backups/system/ 2>/dev/null || echo "  None"
    echo
    echo "Available docker backups:"
    ls -1 /opt/backups/docker/ 2>/dev/null || echo "  None"
    exit 1
fi

case "$1" in
    system)
        if [[ $# -eq 2 ]]; then
            /opt/backups/scripts/restore-system.sh "$2"
        else
            echo "Available system backups:"
            ls -1 /opt/backups/system/
        fi
        ;;
    docker)
        if [[ $# -eq 2 ]]; then
            /opt/backups/scripts/restore-docker.sh "$2"
        else
            echo "Available docker backups:"
            ls -1 /opt/backups/docker/
        fi
        ;;
    *)
        echo "Invalid backup type. Use: system or docker"
        exit 1
        ;;
esac
EOF

    # Make commands executable
    chmod +x /usr/local/bin/backup-now
    chmod +x /usr/local/bin/backup-status
    chmod +x /usr/local/bin/backup-restore
    
    log "Backup management commands created:"
    log "- backup-now: Run manual backup" "$BLUE"
    log "- backup-status: Show backup status" "$BLUE"
    log "- backup-restore: Restore from backup" "$BLUE"
}

# Main execution
main() {
    install_backup_tools
    create_backup_structure
    configure_system_backup
    configure_database_backup
    configure_docker_backup
    setup_backup_scheduling
    create_restore_scripts
    setup_backup_monitoring
    create_backup_commands
    
    # Set proper permissions
    chown -R "$BACKUP_USER:$BACKUP_USER" "$BACKUP_ROOT"
    chmod -R 750 "$BACKUP_ROOT"
    
    log "Backup Configuration Module completed successfully!" "$GREEN"
    
    echo
    log "Backup system configured:" "$BLUE"
    log "- Backup location: $BACKUP_ROOT" "$BLUE"
    log "- Backup user: $BACKUP_USER" "$BLUE"
    log "- Daily backups: 2 AM (system, databases, docker)" "$BLUE"
    log "- Weekly full backup: Sunday 3 AM" "$BLUE"
    log "- Monitoring: Daily at 8 AM" "$BLUE"
    echo
    log "Management commands:" "$BLUE"
    log "- backup-now: Run immediate backup" "$BLUE"
    log "- backup-status: Check backup status" "$BLUE"
    log "- backup-restore system|docker <date>: Restore backup" "$BLUE"
    echo
    log "Backup retention:" "$BLUE"
    log "- System: 30 days" "$BLUE"
    log "- Databases: 14 days" "$BLUE"
    log "- Docker: 7 days" "$BLUE"
}

# Run main
main