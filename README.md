# Ubuntu VPS Production Setup Tool

🚀 **Complete automated setup for production-ready Ubuntu 24.10 VPS with security hardening, Docker support, and proper firewall configuration.**

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
- ✅ Set up comprehensive monitoring and backups
- ✅ Configure everything for Netherlands (nl-NL) with UTC timezone
- ✅ Complete in 10-15 minutes with **zero user interaction**

## 🎯 What You Get

### Security
- SSH hardening (port 2222, key-only auth)
- UFW firewall with minimal attack surface
- Docker containers protected by default
- Full system hardening (kernel, AppArmor, fail2ban)

### Monitoring & Backup
- Real-time monitoring with Netdata
- Process monitoring with Monit
- Automated daily backups (system + Docker)
- Log analysis and rotation

### Docker Integration
- Docker CE + Compose from official repository
- **Fixes Docker's UFW bypass security hole**
- Use `ufw-docker` commands to manage container access
- Containers NOT exposed to internet by default

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
- **System**: Kernel hardening, AppArmor, audit logs
- **Monitoring**: Fail2ban, intrusion detection

## 🔗 Quick Links

- **🚀 [One-Liner Setup](bash/AUTOMATED_SETUP_GUIDE.md#-one-liner-installation)**
- **📖 [Full Documentation](bash/README.md)**
- **⚙️ [Configuration Options](bash/configs/default.conf)**
- **🐛 [Issues](https://github.com/albertsikkema/ubuntu-vps-setup/issues)**

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

**Perfect for:** VPS providers, system administrators, developers deploying to production, automated infrastructure setup.

**Tested on:** Ubuntu 24.10, Ubuntu 24.04, Ubuntu 23.10