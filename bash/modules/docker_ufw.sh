#!/bin/bash

# Docker-UFW Integration Module
# Fixes Docker's UFW bypass issue using ufw-docker tool

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log "Starting Docker-UFW Integration Module" "$BLUE"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command_exists docker; then
        error_exit "Docker is not installed. Please run the Docker installation module first."
    fi
    
    # Check if Docker daemon is running
    if ! systemctl is-active docker.service > /dev/null 2>&1; then
        log "Docker daemon is not running, attempting to start..." "$YELLOW"
        if systemctl start docker.service; then
            log "Docker daemon started successfully"
            sleep 3  # Give Docker time to fully start
        else
            if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
                log "Auto mode: Docker daemon failed to start, skipping docker-ufw integration" "$YELLOW"
                return 1
            else
                error_exit "Docker daemon failed to start. Cannot proceed with Docker-UFW integration."
            fi
        fi
    fi
    
    # Verify Docker is responsive
    if ! docker info > /dev/null 2>&1; then
        if [[ "${SETUP_AUTO_MODE:-false}" == "true" ]]; then
            log "Auto mode: Docker is not responsive, skipping docker-ufw integration" "$YELLOW"
            return 1
        else
            error_exit "Docker is not responsive. Cannot proceed with Docker-UFW integration."
        fi
    fi
    
    # Check UFW
    if ! command_exists ufw; then
        error_exit "UFW is not installed. Please run the firewall module first."
    fi
    
    # Check UFW status
    if ! ufw status | grep -q "Status: active"; then
        error_exit "UFW is not active. Please enable UFW first."
    fi
    
    # Check iptables in Docker
    if [[ -f /etc/docker/daemon.json ]]; then
        if grep -q '"iptables": false' /etc/docker/daemon.json; then
            log "Docker iptables is disabled. This needs to be enabled for ufw-docker." "$RED"
            if confirm "Enable Docker iptables management?"; then
                # Remove the iptables: false line
                jq 'del(.iptables)' /etc/docker/daemon.json > /tmp/daemon.json
                mv /tmp/daemon.json /etc/docker/daemon.json
                systemctl restart docker
                log "Docker iptables management enabled"
            else
                error_exit "ufw-docker requires Docker iptables management to be enabled"
            fi
        fi
    fi
    
    log "Prerequisites check passed" "$GREEN"
}

# Explain the Docker-UFW problem
explain_problem() {
    log "Understanding the Docker-UFW conflict:" "$BLUE"
    echo
    echo "Docker bypasses UFW rules by default, which means:"
    echo "- Containers exposed with -p flag are accessible from the internet"
    echo "- UFW rules don't apply to Docker containers"
    echo "- This is a security risk for production servers"
    echo
    echo "The ufw-docker tool fixes this by:"
    echo "- Integrating Docker's iptables rules with UFW"
    echo "- Allowing you to control container access with UFW-like commands"
    echo "- Maintaining Docker's networking functionality"
    echo
    
    if ! confirm "Continue with Docker-UFW integration?"; then
        exit 0
    fi
}

# Install ufw-docker
install_ufw_docker() {
    log "Installing ufw-docker tool..."
    
    # Download ufw-docker script
    local ufw_docker_url="https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker"
    local ufw_docker_path="/usr/local/bin/ufw-docker"
    
    if download_file "$ufw_docker_url" "$ufw_docker_path"; then
        chmod +x "$ufw_docker_path"
        log "ufw-docker tool downloaded successfully"
    else
        error_exit "Failed to download ufw-docker tool"
    fi
    
    # Verify installation
    if [[ -x "$ufw_docker_path" ]]; then
        log "ufw-docker installed at $ufw_docker_path" "$GREEN"
    else
        error_exit "ufw-docker installation failed"
    fi
}

# Install ufw-docker rules
install_ufw_rules() {
    log "Installing ufw-docker firewall rules..."
    
    # Backup current UFW rules
    backup_file /etc/ufw/after.rules
    
    # Install the rules
    if ufw-docker install; then
        log "ufw-docker rules installed successfully" "$GREEN"
    else
        error_exit "Failed to install ufw-docker rules"
    fi
    
    # Reload UFW
    log "Reloading UFW..."
    ufw reload
    
    log "UFW reloaded with Docker integration" "$GREEN"
}

# Configure Docker networks
configure_docker_networks() {
    log "Configuring Docker network settings..."
    
    # Get Docker networks
    log "Current Docker networks:" "$BLUE"
    docker network ls
    
    # Explain network isolation
    echo
    log "Docker network recommendations:" "$YELLOW"
    echo "- Use custom bridge networks for better isolation"
    echo "- Avoid using the default bridge network"
    echo "- Use internal networks for services that don't need external access"
    echo
}

# Test Docker-UFW integration
test_integration() {
    log "Testing Docker-UFW integration..."
    
    if confirm "Run integration test with a test container?"; then
        local test_port=8888
        
        log "Starting test container on port $test_port..."
        docker run -d --name ufw-test -p $test_port:80 nginx:alpine > /dev/null 2>&1 || {
            log "Test container may already exist, removing..." "$YELLOW"
            docker rm -f ufw-test > /dev/null 2>&1
            docker run -d --name ufw-test -p $test_port:80 nginx:alpine > /dev/null 2>&1
        }
        
        sleep 2
        
        log "Container started. Port $test_port should NOT be accessible from outside." "$YELLOW"
        log "To test: curl http://YOUR_SERVER_IP:$test_port (should fail)" "$BLUE"
        
        echo
        log "To allow access, use: sudo ufw-docker allow ufw-test 80" "$BLUE"
        log "To remove test container: docker rm -f ufw-test" "$BLUE"
    fi
}

# Show usage examples
show_usage_examples() {
    log "ufw-docker usage examples:" "$BLUE"
    echo
    cat << 'EOF'
# List Docker-related UFW rules
ufw-docker status

# Allow external access to a container port
ufw-docker allow [container_name] [port]
ufw-docker allow nginx 80

# Allow from specific IP/subnet
ufw-docker allow nginx 80 from 192.168.1.0/24

# Delete a rule
ufw-docker delete allow nginx 80

# Allow access to container by IP
ufw route allow proto tcp from any to 172.17.0.2 port 80

# Complex example with Docker Compose
# For a service named 'web' in docker-compose:
docker compose ps  # Get container name
ufw-docker allow projectname_web_1 80

# IMPORTANT: Use container names, not service names!
EOF
    
    # Save examples to file
    local examples_file="/root/ufw-docker-examples.txt"
    cat > "$examples_file" << 'EOF'
UFW-Docker Command Reference
===========================

Basic Commands:
--------------
ufw-docker status                    # Show Docker-related rules
ufw-docker allow [name] [port]       # Allow access to container port
ufw-docker delete allow [name] [port] # Remove access rule

Examples:
---------
# Allow HTTP access to nginx container
ufw-docker allow nginx 80

# Allow HTTPS from specific subnet
ufw-docker allow nginx 443 from 10.0.0.0/8

# Allow access to specific container IP
ufw route allow proto tcp from any to 172.17.0.2 port 3306

Docker Compose:
--------------
# First, get the actual container name
docker compose ps

# Then use the full container name (not service name)
ufw-docker allow myproject_web_1 80

Managing Multiple Containers:
----------------------------
# Create a script to manage multiple containers
for container in web db redis; do
    ufw-docker allow myproject_${container}_1 [port]
done

Security Best Practices:
-----------------------
1. Never expose database ports to 0.0.0.0
2. Use specific source IPs when possible
3. Regularly review open ports with 'ufw-docker status'
4. Use Docker networks for internal communication
5. Bind to localhost for local-only services: -p 127.0.0.1:8080:80
EOF
    
    log "Examples saved to $examples_file" "$GREEN"
}

# Create helper scripts
create_helper_scripts() {
    log "Creating helper scripts..."
    
    # Create docker-ports script
    cat > /usr/local/bin/docker-ports << 'EOF'
#!/bin/bash
# Show all exposed Docker ports and their UFW status

echo "Docker Container Ports:"
echo "======================"
echo

# Get all running containers with exposed ports
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -v "PORTS" | while read line; do
    if [[ ! -z "$line" ]]; then
        echo "$line"
    fi
done

echo
echo "UFW Docker Rules:"
echo "================"
ufw-docker status 2>/dev/null || echo "ufw-docker not configured"
EOF
    
    chmod +x /usr/local/bin/docker-ports
    
    # Create docker-secure script
    cat > /usr/local/bin/docker-secure << 'EOF'
#!/bin/bash
# Quick security check for Docker containers

echo "Docker Security Check"
echo "===================="
echo

# Check for containers running as root
echo "Containers running as root:"
docker ps -q | xargs -I {} docker exec {} id -u 2>/dev/null | grep -c "^0$" | xargs echo "Count:"

# Check for privileged containers
echo
echo "Privileged containers:"
docker ps -q | xargs docker inspect -f '{{.Name}}: {{.HostConfig.Privileged}}' | grep true || echo "None found (good!)"

# Check for containers with all capabilities
echo
echo "Containers with dangerous capabilities:"
docker ps -q | xargs docker inspect -f '{{.Name}}: {{.HostConfig.CapAdd}}' | grep -v '\[\]' || echo "None found"

# Check exposed ports
echo
echo "Externally exposed ports (0.0.0.0):"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep "0.0.0.0" || echo "None found"
EOF
    
    chmod +x /usr/local/bin/docker-secure
    
    log "Helper scripts created:" "$GREEN"
    log "- docker-ports: Show all Docker ports and UFW status" "$BLUE"
    log "- docker-secure: Quick Docker security check" "$BLUE"
}

# Configure automatic cleanup
configure_cleanup() {
    if confirm "Configure automatic cleanup of ufw-docker rules for stopped containers?"; then
        cat > /etc/cron.daily/ufw-docker-cleanup << 'EOF'
#!/bin/bash
# Clean up UFW rules for stopped Docker containers

# Get list of running containers
running_containers=$(docker ps --format '{{.Names}}' 2>/dev/null)

# Get UFW rules
ufw_rules=$(ufw status numbered | grep -E "^\[[0-9]+\]" | grep "ufw-docker" || true)

# Check each rule
while IFS= read -r rule; do
    container_name=$(echo "$rule" | grep -oP "ufw-docker-user-.*?(?=\s|$)" | sed 's/ufw-docker-user-//')
    
    if [[ -n "$container_name" ]]; then
        if ! echo "$running_containers" | grep -q "^$container_name$"; then
            echo "Removing UFW rule for stopped container: $container_name"
            # Extract rule number and delete
            rule_num=$(echo "$rule" | grep -oP "^\[\K[0-9]+")
            ufw --force delete $rule_num
        fi
    fi
done <<< "$ufw_rules"
EOF
        
        chmod +x /etc/cron.daily/ufw-docker-cleanup
        log "Automatic cleanup configured (runs daily)"
    fi
}

# Main execution
main() {
    if ! check_prerequisites; then
        log "Docker-UFW integration skipped due to prerequisites" "$YELLOW"
        return 0
    fi
    
    explain_problem
    
    # Install and configure
    install_ufw_docker
    install_ufw_rules
    configure_docker_networks
    
    # Test and document
    test_integration
    show_usage_examples
    create_helper_scripts
    configure_cleanup
    
    log "Docker-UFW Integration Module completed successfully!" "$GREEN"
    
    echo
    log "Important notes:" "$YELLOW"
    log "- Docker containers are now protected by UFW" "$YELLOW"
    log "- Use 'ufw-docker' commands to manage container access" "$YELLOW"
    log "- Existing containers may need rules added manually" "$YELLOW"
    log "- Run 'docker-ports' to see all exposed ports" "$YELLOW"
    log "- Run 'docker-secure' for a security check" "$YELLOW"
}

# Run main
main