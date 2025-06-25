#!/bin/bash

# Docker Installation Module
# Installs Docker Engine and Docker Compose on Ubuntu

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting Docker Installation Module" "$BLUE"

# Check if Docker is already installed
check_docker_installed() {
    if command_exists docker; then
        local version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log "Docker is already installed (version $version)" "$YELLOW"
        
        if confirm "Reinstall/Update Docker?"; then
            remove_old_docker
            return 1
        else
            return 0
        fi
    fi
    return 1
}

# Remove old Docker installations
remove_old_docker() {
    log "Removing old Docker installations..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Clean up old Docker data (optional)
    if [[ -d /var/lib/docker ]] && confirm "Remove existing Docker data in /var/lib/docker?"; then
        systemctl stop docker 2>/dev/null || true
        rm -rf /var/lib/docker
        rm -rf /var/lib/containerd
        log "Old Docker data removed"
    fi
}

# Install Docker prerequisites
install_prerequisites() {
    log "Installing Docker prerequisites..."
    
    local packages=(
        ca-certificates
        curl
        gnupg
        lsb-release
        apt-transport-https
        software-properties-common
    )
    
    # Install all prerequisites efficiently
    install_packages "${packages[@]}"
}

# Add Docker repository
add_docker_repository() {
    log "Adding Docker official repository..."
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    
    # Remove existing key if present to avoid prompts
    rm -f /etc/apt/keyrings/docker.gpg
    
    # Download and add GPG key with better error handling
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
        error_exit "Failed to download Docker GPG key"
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Get OS information once
    local arch=$(dpkg --print-architecture)
    local codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    
    # Add the repository to apt sources
    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index efficiently (this is needed for Docker packages)
    apt-get update -qq -o Dir::Etc::sourcelist="sources.list.d/docker.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
    
    log "Docker repository added"
}

# Install Docker Engine
install_docker_engine() {
    log "Installing Docker Engine..."
    
    # Install Docker packages efficiently
    local packages=(
        docker-ce
        docker-ce-cli
        containerd.io
        docker-buildx-plugin
        docker-compose-plugin
    )
    
    export DEBIAN_FRONTEND=noninteractive
    if apt-get install -y -qq "${packages[@]}" 2>/dev/null; then
        log "Docker packages installed successfully" "$GREEN"
    else
        log "Retrying Docker installation..." "$YELLOW"
        apt-get update -qq
        apt-get install -y "${packages[@]}" || error_exit "Docker Engine installation failed"
    fi
    
    # Quick verification
    if command_exists docker; then
        log "Docker Engine installed successfully" "$GREEN"
        docker --version | head -1
    else
        error_exit "Docker Engine installation failed"
    fi
}

# Configure Docker daemon
configure_docker_daemon() {
    log "Configuring Docker daemon..."
    
    # Create daemon configuration directory
    ensure_dir /etc/docker
    
    # Create minimal daemon.json to avoid startup issues
    cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    log "Docker daemon configured"
}

# Configure Docker for non-root user
configure_docker_user() {
    log "Configuring Docker for non-root users..."
    
    # Create docker group if it doesn't exist
    if ! getent group docker > /dev/null 2>&1; then
        groupadd docker
        log "Docker group created"
    fi
    
    # Auto mode: add setup user to docker group
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        local setup_user="${SETUP_USER_USERNAME:-${SETUP_USERNAME:-admin}}"
        if id "$setup_user" &>/dev/null; then
            usermod -aG docker "$setup_user"
            log "Auto mode: Added $setup_user to docker group" "$BLUE"
        else
            log "Auto mode: Setup user $setup_user not found, skipping docker group" "$YELLOW"
        fi
    else
        # Interactive mode
        echo "Users with sudo access:"
        if grep -E '^sudo:' /etc/group 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -v '^$'; then
            echo
        else
            echo "No sudo users found"
        fi
        
        if confirm "Add users to docker group for non-root Docker access?"; then
            read -p "Enter usernames to add (space-separated): " users
            
            for user in $users; do
                if id "$user" &>/dev/null; then
                    usermod -aG docker "$user"
                    log "User $user added to docker group"
                else
                    log "User $user does not exist" "$RED"
                fi
            done
            
            log "Users need to log out and back in for group changes to take effect" "$YELLOW"
        fi
    fi
}

# Configure Docker to start on boot
configure_docker_startup() {
    log "Configuring Docker to start on boot..."
    
    # Validate daemon.json before starting
    if [[ -f /etc/docker/daemon.json ]]; then
        if ! python3 -m json.tool /etc/docker/daemon.json > /dev/null 2>&1; then
            log "Invalid Docker daemon configuration, removing..." "$YELLOW"
            rm -f /etc/docker/daemon.json
        fi
    fi
    
    # Enable Docker service
    systemctl enable docker.service
    systemctl enable containerd.service
    
    # Start Docker with fast error handling
    if systemctl start docker.service; then
        log "Docker service started successfully"
    else
        log "Docker service failed to start, trying quick recovery..." "$YELLOW"
        
        # Quick recovery: Remove config and retry once
        if [[ -f /etc/docker/daemon.json ]]; then
            log "Removing daemon.json and retrying..." "$YELLOW"
            mv /etc/docker/daemon.json /etc/docker/daemon.json.failed
            systemctl daemon-reload
            
            if systemctl start docker.service; then
                log "Docker started after removing config" "$GREEN"
            else
                if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
                    log "Auto mode: Docker failed to start, continuing without Docker" "$YELLOW"
                    return 0
                else
                    log "Docker startup failed. Check: systemctl status docker" "$RED"
                    error_exit "Docker service failed to start"
                fi
            fi
        else
            if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
                log "Auto mode: Docker failed to start, continuing without Docker" "$YELLOW"
                return 0
            else
                error_exit "Docker service failed to start"
            fi
        fi
    fi
    
    log "Docker configured to start on boot"
}

# Install Docker Compose standalone (optional)
install_docker_compose_standalone() {
    # Skip in auto mode to save time
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        log "Auto mode: Skipping Docker Compose standalone (plugin is sufficient)" "$BLUE"
        return 0
    fi
    
    if confirm "Install Docker Compose standalone binary (in addition to plugin)?"; then
        log "Installing Docker Compose standalone..."
        
        # Get version with timeout and fallback
        local compose_version
        if compose_version=$(timeout 10 curl -s https://api.github.com/repos/docker/compose/releases/latest 2>/dev/null | grep -oP '"tag_name": "\K[^"]+'); then
            log "Latest version: $compose_version"
            
            # Download with progress and error handling
            if curl -fsSL "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose; then
                chmod +x /usr/local/bin/docker-compose
                
                # Create symbolic link for compatibility
                ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
                
                log "Docker Compose standalone installed (version $compose_version)" "$GREEN"
            else
                log "Failed to download Docker Compose standalone" "$YELLOW"
            fi
        else
            log "Could not determine latest Docker Compose version (timeout/network issue)" "$YELLOW"
        fi
    fi
}

# Configure Docker security
configure_docker_security() {
    # Skip advanced security in auto mode for reliability
    if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
        log "Auto mode: Skipping advanced Docker security (basic security applied)" "$BLUE"
        return 0
    fi
    
    log "Configuring Docker security settings..."
    
    # Enable user namespace remapping (optional)
    if confirm "Enable user namespace remapping for better security?"; then
        # Merge configuration without jq dependency
        if [[ -f /etc/docker/daemon.json ]] && [[ -s /etc/docker/daemon.json ]]; then
            # Backup and modify existing config
            cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
            if python3 -c "import json; d=json.load(open('/etc/docker/daemon.json')); d['userns-remap']='default'; json.dump(d, open('/tmp/daemon.json', 'w'), indent=2)" 2>/dev/null; then
                mv /tmp/daemon.json /etc/docker/daemon.json
                log "User namespace remapping enabled"
                log "Note: This may cause issues with some containers" "$YELLOW"
            else
                log "Failed to configure user namespace remapping" "$YELLOW"
            fi
        else
            # Create new config
            echo '{"userns-remap": "default"}' > /etc/docker/daemon.json
            log "User namespace remapping enabled"
        fi
    fi
    
    # Set up Docker content trust
    if confirm "Enable Docker Content Trust (image signature verification)?"; then
        ensure_dir /etc/profile.d
        echo "export DOCKER_CONTENT_TRUST=1" >> /etc/profile.d/docker.sh
        log "Docker Content Trust enabled"
    fi
}

# Test Docker installation
test_docker_installation() {
    log "Testing Docker installation..."
    
    # Quick version check first
    if ! command_exists docker; then
        log "Docker command not found" "$RED"
        return 1
    fi
    
    # Test Docker daemon connectivity (faster than running containers)
    if docker info > /dev/null 2>&1; then
        log "Docker daemon is running" "$GREEN"
    else
        log "Docker daemon is not responding" "$RED"
        if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
            log "Auto mode: Continuing despite Docker daemon test failure" "$YELLOW"
            return 0
        else
            return 1
        fi
    fi
    
    # Quick hello-world test (only in interactive mode)
    if [[ "${SETUP_AUTO_MODE:-false}" != "true" ]]; then
        log "Running hello-world test..."
        if timeout 30 docker run --rm hello-world > /dev/null 2>&1; then
            log "Docker is working correctly!" "$GREEN"
        else
            log "Docker hello-world test failed (timeout or error)" "$YELLOW"
        fi
    else
        log "Auto mode: Skipping hello-world test (saving time)" "$BLUE"
    fi
    
    # Test Docker Compose (quick version check)
    if docker compose version > /dev/null 2>&1; then
        log "Docker Compose plugin is working!" "$GREEN"
        docker compose version | head -1
    else
        log "Docker Compose plugin test failed" "$YELLOW"
    fi
    
    # Show essential Docker info
    log "Docker system information:" "$BLUE"
    docker info 2>/dev/null | grep -E "Server Version:|Storage Driver:|Cgroup Driver:" | head -3 || true
}

# Create Docker directories
create_docker_directories() {
    log "Creating Docker working directories..."
    
    # Create common Docker directories
    local dirs=(
        "/opt/docker/compose"
        "/opt/docker/data"
        "/opt/docker/config"
    )
    
    for dir in "${dirs[@]}"; do
        ensure_dir "$dir"
        chmod 755 "$dir"
    done
    
    # Create example docker-compose.yml
    cat > /opt/docker/compose/docker-compose.example.yml << 'EOF'
version: '3.8'

services:
  # Example service configuration
  app:
    image: nginx:alpine
    container_name: example_app
    ports:
      - "8080:80"
    volumes:
      - /opt/docker/data/nginx:/usr/share/nginx/html:ro
    restart: unless-stopped
    networks:
      - app_network

networks:
  app_network:
    driver: bridge

volumes:
  app_data:
EOF

    log "Docker directories created in /opt/docker/"
}

# Main execution
main() {
    # Check if already installed
    if check_docker_installed; then
        test_docker_installation
        return 0
    fi
    
    # Install Docker
    install_prerequisites
    add_docker_repository
    install_docker_engine
    
    # Configure Docker
    configure_docker_daemon
    configure_docker_user
    configure_docker_startup
    configure_docker_security
    
    # Install extras
    install_docker_compose_standalone
    
    # Restart Docker with new configuration if running
    if systemctl is-active docker.service > /dev/null; then
        log "Restarting Docker with new configuration..."
        systemctl restart docker || log "Docker restart failed, but continuing..." "$YELLOW"
    fi
    
    # Test installation
    test_docker_installation
    
    # Create directories
    create_docker_directories
    
    log "Docker Installation Module completed successfully!" "$GREEN"
    log "Docker and Docker Compose are ready to use" "$BLUE"
    
    # Show important notes
    log "Important notes:" "$YELLOW"
    log "- Users added to docker group need to log out and back in" "$YELLOW"
    log "- Docker data directory: /var/lib/docker" "$YELLOW"
    log "- Docker compose files: /opt/docker/compose" "$YELLOW"
    log "- Remember to configure UFW for Docker if using firewall" "$YELLOW"
}

# Run main
main