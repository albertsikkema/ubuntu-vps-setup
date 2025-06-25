#!/bin/bash

# Test script to validate the automated setup works correctly
# This is for development/testing purposes only

set -euo pipefail

echo "==================================="
echo "VPS Setup Tool - Validation Test"
echo "==================================="
echo

# Test 1: Check all required files exist
echo "1. Checking file structure..."
required_files=(
    "setup.sh"
    "vps-setup-main.sh"
    "modules/utils.sh"
    "modules/system_update.sh"
    "modules/user_management.sh"
    "modules/ssh_hardening.sh"
    "modules/firewall.sh"
    "modules/security.sh"
    "modules/docker.sh"
    "modules/docker_ufw.sh"
)

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  ✓ $file exists"
    else
        echo "  ✗ $file missing"
        exit 1
    fi
done

# Test 2: Check script permissions
echo
echo "2. Checking script permissions..."
for script in setup.sh vps-setup-main.sh modules/*.sh; do
    if [[ -x "$script" ]]; then
        echo "  ✓ $script is executable"
    else
        echo "  ✗ $script not executable"
        exit 1
    fi
done

# Test 3: Syntax check
echo
echo "3. Checking script syntax..."
for script in setup.sh vps-setup-main.sh modules/*.sh; do
    if bash -n "$script"; then
        echo "  ✓ $script syntax OK"
    else
        echo "  ✗ $script syntax error"
        exit 1
    fi
done

# Test 4: Check environment variables
echo
echo "4. Testing environment variable handling..."
export SETUP_AUTO_MODE="true"
export SETUP_USERNAME="testuser"
export SETUP_SSH_PORT="3333"

# Source utils and test auto_input function
source modules/utils.sh

result=$(auto_input "username test" "default")
if [[ "$result" == "testuser" ]]; then
    echo "  ✓ Auto input works correctly"
else
    echo "  ✗ Auto input failed (got: $result)"
    exit 1
fi

# Test 5: Check automated confirmation
if confirm "test prompt"; then
    echo "  ✓ Auto confirm works correctly"
else
    echo "  ✗ Auto confirm failed"
    exit 1
fi

# Test 6: Validate default configurations
echo
echo "5. Checking default configurations..."

# Check setup.sh has correct defaults
if grep -q 'DEFAULT_USERNAME="admin"' setup.sh; then
    echo "  ✓ Default username is admin"
else
    echo "  ✗ Default username not set correctly"
    exit 1
fi

if grep -q 'DEFAULT_SSH_PORT="2222"' setup.sh; then
    echo "  ✓ Default SSH port is 2222"
else
    echo "  ✗ Default SSH port not set correctly"
    exit 1
fi

if grep -q 'DEFAULT_TIMEZONE="UTC"' setup.sh; then
    echo "  ✓ Default timezone is UTC"
else
    echo "  ✗ Default timezone not set correctly"
    exit 1
fi

# Test 7: Check module dependencies
echo
echo "6. Checking module dependencies..."
source vps-setup-main.sh

if [[ "${MODULE_DEPS[docker_ufw]}" == "docker firewall" ]]; then
    echo "  ✓ Docker UFW dependencies correct"
else
    echo "  ✗ Docker UFW dependencies incorrect"
    exit 1
fi

echo
echo "========================================="
echo "✅ All tests passed! Setup tool is ready"
echo "========================================="
echo
echo "Next steps:"
echo "1. Update REPO_URL in setup.sh"
echo "2. Push to GitHub repository"
echo "3. Test on fresh Ubuntu 24.10 VPS"
echo
echo "One-liner command (after GitHub upload):"
echo "curl -fsSL https://raw.githubusercontent.com/YOURUSERNAME/YOURREPO/main/bash/setup.sh | sudo bash -s -- --auto"