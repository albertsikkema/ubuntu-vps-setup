# Automated VPS Setup - Step by Step Guide

## 🎯 Overview

This guide shows you how to use the automated VPS setup tool that requires minimal user interaction and uses sensible defaults optimized for Netherlands (nl-NL) with UTC timezone.

## 🚀 One-Liner Installation

### Full Automated Setup
```bash
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/bash/setup.sh | sudo bash -s -- --auto
```

This command will:
1. Download the setup script
2. Run it in fully automated mode  
3. Configure everything with sensible defaults
4. Complete in ~10-15 minutes with zero interaction

## 📋 Default Configuration

### System Settings
- **Timezone**: UTC (always)
- **Locale**: English language with Dutch (nl-NL) number/date formatting
- **Hostname**: Unchanged (keeps VPS provider default)
- **Swap**: Auto-configured based on RAM

### Security Settings
- **Username**: `admin` (with sudo access)
- **SSH Port**: `2222` (changed from default 22)
- **SSH**: Key-only authentication, root login disabled
- **Password Policy**: Strong passwords required
- **Firewall**: UFW enabled, only SSH + HTTP/HTTPS allowed
- **Fail2ban**: Enabled for SSH protection
- **Security Hardening**: Full kernel and system hardening

### Docker Configuration
- **Docker CE**: Latest from official repository
- **Docker Compose**: Plugin version installed
- **UFW Integration**: ufw-docker tool configured
- **Containers**: NOT exposed to internet by default

## ⚙️ Customization Options

### Custom Username and SSH Port
```bash
sudo ./setup.sh --auto --username=myuser --ssh-port=3333
```

### Specific Modules Only
```bash
# Only Docker and security
sudo ./setup.sh --auto --modules=system_update,docker,docker_ufw,firewall

# Only basic hardening (no Docker)
sudo ./setup.sh --auto --modules=system_update,user_management,ssh_hardening,firewall,security
```

### Available Modules
- `system_update` - System updates and basic setup
- `user_management` - Create sudo user and security policies  
- `ssh_hardening` - Secure SSH configuration
- `firewall` - UFW firewall setup
- `security` - Advanced security hardening
- `docker` - Docker and Docker Compose installation
- `docker_ufw` - Docker-UFW integration fix
- `monitoring` - Basic monitoring tools
- `backup` - Backup configuration

## 🔐 Security Features

### What Gets Secured
1. **SSH Hardening**
   - Port changed to 2222
   - Root login disabled
   - Password authentication disabled
   - Strong ciphers only
   - Connection rate limiting

2. **User Security**
   - New sudo user created
   - Strong password policies
   - Account lockout after 5 failed attempts
   - Root account locked

3. **Firewall Protection**
   - UFW enabled with deny-all default
   - Only SSH (2222), HTTP (80), HTTPS (443) allowed
   - Rate limiting on SSH
   - Docker containers protected

4. **System Hardening**
   - Kernel parameter hardening
   - AppArmor enabled
   - File integrity monitoring (optional)
   - Audit logging
   - Unnecessary services disabled

## 🐳 Docker Integration

### What Gets Installed
- Docker CE (latest stable)
- Docker Compose plugin
- Optimized daemon configuration
- User permissions for non-root access

### UFW-Docker Integration
- Fixes Docker's firewall bypass issue
- Containers NOT exposed to internet by default
- Use `ufw-docker` commands to manage access:

```bash
# Allow external access to container
sudo ufw-docker allow nginx 80

# Allow from specific IP
sudo ufw-docker allow nginx 80 from 192.168.1.0/24

# Remove access
sudo ufw-docker delete allow nginx 80
```

## 📁 File Locations

### Important Files Created
- **Setup Log**: `/var/log/vps-setup.log`
- **Firewall Config**: `/root/firewall-config.txt`
- **Security Report**: `/root/security-report.txt`
- **Docker Files**: `/opt/docker/`
- **UFW-Docker Help**: `/root/ufw-docker-examples.txt`

### Configuration Backups
All original config files are backed up with timestamps:
- `/etc/ssh/sshd_config.backup.YYYYMMDD_HHMMSS`
- `/etc/sysctl.conf.backup.YYYYMMDD_HHMMSS`
- `/etc/ufw/after.rules.backup.YYYYMMDD_HHMMSS`

## 🛠️ Post-Installation

### Immediate Steps
1. **Test SSH Connection** (use new port!)
   ```bash
   ssh admin@YOUR_SERVER_IP -p 2222
   ```

2. **Check Service Status**
   ```bash
   sudo systemctl status docker ufw fail2ban
   ```

3. **Review Security Report**
   ```bash
   sudo cat /root/security-report.txt
   ```

### Verify Docker-UFW Integration
```bash
# Check firewall status
sudo ufw status verbose

# List Docker containers and ports
docker-ports

# Run security check
docker-secure
```

### Optional: Security Audit
```bash
# Run comprehensive security audit
sudo lynis audit system

# Check for rootkits
sudo rkhunter --check
```

## 🔧 Troubleshooting

### SSH Connection Issues
- **Port**: Make sure you're using port 2222 (or your custom port)
- **Keys**: Ensure your SSH key is properly configured
- **Firewall**: Check `sudo ufw status` shows SSH port allowed

### Docker Access Issues
- **Container Not Accessible**: Use `sudo ufw-docker allow container_name port`
- **Check Rules**: Run `sudo ufw-docker status`
- **View Ports**: Use `docker-ports` command

### Reset Firewall (Emergency)
```bash
sudo ufw disable
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp  # Your SSH port
sudo ufw enable
```

## 📊 Expected Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| Download & Prep | 1-2 min | Download repository and setup |
| System Updates | 3-5 min | Package updates and installs |
| Security Config | 2-3 min | SSH, firewall, hardening |
| Docker Install | 2-4 min | Docker and integration |
| Final Setup | 1-2 min | Configuration and testing |
| **Total** | **9-16 min** | Complete automated setup |

## 🎉 Success Indicators

After completion, you should see:
- ✅ SSH accessible on new port with keys only
- ✅ Docker installed and secured with UFW
- ✅ Firewall active with minimal ports open
- ✅ New sudo user created and working
- ✅ All security services running
- ✅ No containers exposed to internet by default

## 🆘 Support

If you encounter issues:
1. Check the log file: `/var/log/vps-setup.log`
2. Verify system requirements (Ubuntu 24.10 recommended)
3. Ensure root/sudo access
4. Check network connectivity

The automated setup is designed to be robust and handle most common scenarios without intervention.