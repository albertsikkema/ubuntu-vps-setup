#!/bin/bash

# Script to prepare the VPS setup tool for GitHub

echo "Preparing Ubuntu VPS Setup Tool for GitHub..."

# Create .gitignore
cat > .gitignore << 'EOF'
# Logs
*.log
/logs/

# Temporary files
*.tmp
*.swp
*.bak
*~

# OS files
.DS_Store
Thumbs.db

# IDE files
.vscode/
.idea/

# Test files
test/
*.test

# Local configurations
config.local.yml
*.local

# Sensitive files
*.key
*.pem
secrets/
EOF

# Create LICENSE file (MIT)
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2024 [Your Name]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# Update setup.sh with your actual GitHub repository URL
echo "IMPORTANT: Update the following in setup.sh:"
echo "1. Replace 'albertsikkema' with your GitHub username"
echo "2. Replace 'ubuntu-vps-setup' with your repository name"
echo ""
echo "Example:"
echo "  REPO_URL=\"https://github.com/johndoe/ubuntu-vps-setup\""
echo ""

# Create a simple install script for the repository
cat > install.sh << 'EOF'
#!/bin/bash
# Quick installer for Ubuntu VPS Setup Tool

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "Ubuntu VPS Setup Tool Installer"
echo "==============================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Download and run setup
echo "Downloading setup script..."
if command -v wget >/dev/null 2>&1; then
    wget -O setup.sh https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/setup.sh
elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o setup.sh https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/setup.sh
else
    echo -e "${RED}Neither wget nor curl found. Please install one.${NC}"
    exit 1
fi

chmod +x setup.sh
echo -e "${GREEN}Setup script downloaded successfully!${NC}"
echo
echo "Run ./setup.sh to start the VPS configuration"
EOF

chmod +x install.sh

# Show directory structure
echo ""
echo "Directory structure:"
tree -a -I '.git' || {
    echo "ubuntu-vps-setup/"
    echo "├── .gitignore"
    echo "├── LICENSE"
    echo "├── README.md"
    echo "├── install.sh"
    echo "├── setup.sh"
    echo "├── setup-github.sh"
    echo "├── vps-setup-main.sh"
    echo "├── modules/"
    echo "│   ├── utils.sh"
    echo "│   ├── system_update.sh"
    echo "│   ├── user_management.sh"
    echo "│   ├── ssh_hardening.sh"
    echo "│   ├── firewall.sh"
    echo "│   ├── security.sh"
    echo "│   ├── docker.sh"
    echo "│   └── docker_ufw.sh"
    echo "└── configs/"
}

echo ""
echo "Next steps:"
echo "1. Update REPO_URL in setup.sh with your GitHub details"
echo "2. Initialize git repository: git init"
echo "3. Add files: git add ."
echo "4. Commit: git commit -m 'Initial commit'"
echo "5. Add remote: git remote add origin https://github.com/albertsikkema/ubuntu-vps-setup.git"
echo "6. Push: git push -u origin main"
echo ""
echo "Remember to update the README.md with your repository URL!"