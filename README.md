# Ubuntu VPS Production Setup Tool

> **⚠️ DISCLAIMER - WORK IN PROGRESS**
> 
> This project is currently under active development and should be considered **EXPERIMENTAL**. 
>
> - **NOT PRODUCTION READY** - Use at your own risk
> - **NO WARRANTY** - I am not responsible for any damage, data loss, or security issues
> - **TEST FIRST** - Always test on non-critical systems before production use
> - **BACKUP DATA** - Ensure you have backups before running this script
> - **SECURITY RISK** - This script makes significant system changes that could affect security
>
> By using this tool, you acknowledge that you understand these risks and accept full responsibility.

🚀 **Fast, focused setup for Ubuntu 24.10 VPS with Docker, SSH security, and firewall configuration.**

## ⚡ Quick Start

### Option 1: One-Liner (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/albertsikkema/ubuntu-vps-setup/main/bash/setup.sh | sudo bash -s -- --auto
```

### Option 2: Download and Run Locally
```bash
wget "https://github.com/albertsikkema/ubuntu-vps-setup/archive/refs/heads/main.tar.gz"
tar -xzf main.tar.gz
cd ubuntu-vps-setup-main/bash
sudo ./setup.sh --auto
```

Both commands will:
- ✅ Update and secure your Ubuntu 24.10 VPS
- ✅ Install Docker with UFW integration
- ✅ Set up SSH hardening and firewall protection
- ✅ Configure everything for Netherlands (nl-NL) with UTC timezone
- ✅ Complete in 5-10 minutes with **minimal user interaction**

## 🎯 What You Get

### Security
- SSH hardening (port 2222, key-only auth)
- UFW firewall with minimal attack surface
- Docker containers protected by default
- Essential security configurations

### Docker Integration
- Docker CE + Compose from official repository
- **Fixes Docker's UFW bypass security hole**
- Use `ufw-docker` commands to manage container access
- Containers NOT exposed to internet by default

## 📦 Modules Installed

The setup includes these 6 essential modules:

| Module | Description | Purpose |
|--------|-------------|---------|
| **system_update** | System Update & Basic Setup | Updates packages, configures timezone/locale, installs essential tools |
| **user_management** | User Management & Sudo Configuration | Creates secure sudo user with your credentials |
| **ssh_hardening** | SSH Security Hardening | Secures SSH (port 2222, key-only auth, disable root) |
| **firewall** | UFW Firewall Configuration | Sets up UFW firewall with HTTP/HTTPS access |
| **docker** | Docker & Docker Compose Installation | Installs Docker CE + Compose from official repository |
| **docker_ufw** | Docker-UFW Integration Fix | Fixes Docker's UFW bypass security issue |

## 📁 Repository Structure

```
bash/                           # Main tool directory
├── setup.sh                   # Bootstrap script
├── modules/                    # Individual setup modules
├── configs/                    # Configuration templates
├── AUTOMATED_SETUP_GUIDE.md   # Complete usage guide
└── README.md                   # Full documentation
```

## 🔧 Usage Options

### Full Automation (Recommended)
```bash
sudo ./setup.sh --auto
```

### Custom Settings
```bash
sudo ./setup.sh --auto --username=myuser --ssh-port=3333
```

### Configuration File
```bash
sudo ./setup.sh --config=/path/to/config.conf
```

### Interactive Mode
```bash
sudo ./setup.sh
```

## 📚 Documentation

- **[Quick Start Guide](bash/AUTOMATED_SETUP_GUIDE.md)** - Step-by-step automation guide
- **[Full Documentation](bash/README.md)** - Complete feature documentation
- **[Completion Summary](bash/COMPLETION_SUMMARY.md)** - Feature overview

## ⚙️ Default Configuration

| Setting | Value | Customizable |
|---------|-------|--------------|
| **Timezone** | UTC | ❌ (always UTC) |
| **Locale** | English + Dutch formatting | ❌ |
| **Username** | `admin` | ✅ `--username=` |
| **SSH Port** | `2222` | ✅ `--ssh-port=` |
| **Firewall** | UFW enabled | ❌ |
| **Docker** | With UFW integration | ❌ |

## 🛡️ Security Features

- **SSH**: Port 2222, key-only auth, root disabled
- **Firewall**: UFW with rate limiting
- **Docker**: Containers protected by UFW
- **System**: Essential hardening, fail2ban
- **User Management**: Secure sudo user creation

## 🔗 Quick Links

- **🚀 [One-Liner Setup](bash/AUTOMATED_SETUP_GUIDE.md#-one-liner-installation)**
- **📖 [Full Documentation](bash/README.md)**
- **⚙️ [Configuration Options](bash/configs/default.conf)**
- **🐛 [Issues](https://github.com/albertsikkema/ubuntu-vps-setup/issues)**

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

**Perfect for:** Developers needing a quick Docker-ready VPS, system administrators, simple production deployments.

**Tested on:** Ubuntu 24.10, Ubuntu 24.04

**Features:** Fast setup (5-10 minutes), user-controlled credentials, essential security, Docker + UFW integration.