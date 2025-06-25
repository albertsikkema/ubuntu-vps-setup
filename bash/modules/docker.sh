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
    
    apt-get update -qq
    
    for package in "${packages[@]}"; do
        install_package "$package"
    done
}

# Add Docker repository
add_docker_repository() {
    log "Adding Docker official repository..."
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add the repository to apt sources
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index
    apt-get update -qq
    
    log "Docker repository added"
}

# Install Docker Engine
install_docker_engine() {
    log "Installing Docker Engine..."
    
    # Install Docker packages
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Verify installation
    if docker --version > /dev/null 2>&1; then
        log "Docker Engine installed successfully" "$GREEN"
        docker --version
    else
        error_exit "Docker Engine installation failed"
    fi
}

# Configure Docker daemon
configure_docker_daemon() {
    log "Configuring Docker daemon..."
    
    # Create daemon configuration directory
    ensure_dir /etc/docker
    
    # Create daemon.json with optimized settings
    cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "dns": ["8.8.8.8", "8.8.4.4"],
  "ipv6": false,
  "userland-proxy": false,
  "live-restore": true,
  "experimental": false,
  "features": {
    "buildkit": true
  },
  "metrics-addr": "127.0.0.1:9323"
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
    
    # Add users to docker group
    echo "Users with sudo access:"
    grep -E '^sudo:' /etc/group | cut -d: -f4 | tr ',' '\n' | grep -v '^$'
    
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
}

# Configure Docker to start on boot
configure_docker_startup() {
    log "Configuring Docker to start on boot..."
    
    # Enable Docker service
    systemctl enable docker.service
    systemctl enable containerd.service
    
    # Start Docker
    systemctl start docker.service
    
    log "Docker configured to start on boot"
}

# Install Docker Compose standalone (optional)
install_docker_compose_standalone() {
    if confirm "Install Docker Compose standalone binary (in addition to plugin)?"; then
        log "Installing Docker Compose standalone..."
        
        local compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K[^"]+')
        
        if [[ -n "$compose_version" ]]; then
            curl -SL "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            
            # Create symbolic link for compatibility
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
            
            log "Docker Compose standalone installed (version $compose_version)"
        else
            log "Could not determine latest Docker Compose version" "$YELLOW"
        fi
    fi
}

# Configure Docker security
configure_docker_security() {
    log "Configuring Docker security settings..."
    
    # Enable user namespace remapping (optional)
    if confirm "Enable user namespace remapping for better security?"; then
        echo '{"userns-remap": "default"}' | jq -s '.[0] * .[1]' /etc/docker/daemon.json - > /tmp/daemon.json
        mv /tmp/daemon.json /etc/docker/daemon.json
        
        log "User namespace remapping enabled"
        log "Note: This may cause issues with some containers" "$YELLOW"
    fi
    
    # Set up Docker content trust
    if confirm "Enable Docker Content Trust (image signature verification)?"; then
        echo "export DOCKER_CONTENT_TRUST=1" >> /etc/profile.d/docker.sh
        log "Docker Content Trust enabled"
    fi
}

# Test Docker installation
test_docker_installation() {
    log "Testing Docker installation..."
    
    # Test Docker
    if docker run --rm hello-world > /dev/null 2>&1; then
        log "Docker is working correctly!" "$GREEN"
    else
        log "Docker test failed" "$RED"
        return 1
    fi
    
    # Test Docker Compose
    if docker compose version > /dev/null 2>&1; then
        log "Docker Compose plugin is working correctly!" "$GREEN"
        docker compose version
    else
        log "Docker Compose plugin test failed" "$YELLOW"
    fi
    
    # Show Docker info
    log "Docker system information:" "$BLUE"
    docker info | grep -E "Server Version:|Storage Driver:|Cgroup Driver:" || true
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
    
    # Restart Docker with new configuration
    systemctl restart docker
    
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