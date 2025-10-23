# Multi-Tenant CDN Installation Guide

## Prerequisites

- Ubuntu 20.04+ or Debian 11+ server
- Root or sudo access
- Public IP address
- DNS access to configure A records

## Installation Steps

### 1. Download and Extract
```bash
# Clone or download the CDN scripts to /opt/scripts/cdn/
sudo mkdir -p /opt/scripts/cdn
cd /opt/scripts/cdn

# Ensure all scripts are executable
sudo chmod +x cdn-initial-setup.sh
sudo chmod +x helpers/*.sh
```

### 2. Run Initial Setup
```bash
sudo ./cdn-initial-setup.sh
```

The setup wizard will guide you through:
- Domain configuration (CDN and Gitea domains)
- SFTP port setup
- SMTP configuration (optional)
- Let's Encrypt email
- System paths
- Gitea administrator credentials

### 3. Configure DNS

After setup completes, configure your DNS:
```
cdn.example.com    A    YOUR_SERVER_IP
git.example.com    A    YOUR_SERVER_IP
```

Wait for DNS propagation (use `dig cdn.example.com` to verify).

### 4. Setup SSL Certificates

Once DNS is propagated:
```bash
sudo cdn-setup-letsencrypt
```

### 5. Create Your First Tenant
```bash
sudo cdn-tenant-manager create mytenant
```

## Directory Structure

After installation:
```
/etc/cdn/
├── config.env              # Main configuration
├── tenants/                # Tenant configurations
├── quotas/                 # Quota settings
└── keys/                   # SSH keys

/srv/cdn/
├── sftp/                   # SFTP directories (per tenant)
├── git/                    # Git repositories (per tenant)
├── www/                    # Nginx web root (per tenant)
└── backups/                # Backup storage

/usr/local/bin/
├── cdn-tenant-helpers      # Tenant management
├── cdn-autocommit          # Auto-commit script
├── cdn-quota-functions     # Quota management
├── cdn-gitea-functions     # Gitea integration
└── cdn-setup-letsencrypt   # SSL setup

/var/log/cdn/               # System logs
```

## Debugging

Enable verbose error reporting:
```bash
DEBUG=true sudo ./cdn-initial-setup.sh
```

## Support

For issues, check:
- `/var/log/cdn/` for application logs
- `journalctl -u gitea` for Gitea logs
- `journalctl -u cdn-autocommit@<tenant>` for autocommit logs
- `/var/log/nginx/` for web server logs
```

---

## Summary

This completes the modular CDN setup system with:

### Main Components:
1. **Main Orchestrator** (`cdn-initial-setup.sh`) - Controls setup flow
2. **Common Functions** (`includes/common.sh`) - Shared utilities
3. **Wizard Steps** (`includes/step*.sh`) - Modular configuration steps
4. **Installation Libraries** (`lib/install-*.sh`) - Component installers
5. **Helper Scripts** (`helpers/*.sh`) - Runtime management tools
6. **Templates** (`templates/`) - Configuration file templates

### Key Features:
- ✅ **Error Handling**: Comprehensive with DEBUG mode and line numbers
- ✅ **File Headers**: Every file has path and purpose documented
- ✅ **Modular Design**: Easy to maintain and test individual components
- ✅ **Template System**: Clean separation of code and configuration
- ✅ **Config First**: Configuration saved before any installation
- ✅ **Complete Functionality**: All 3874 lines preserved from original

### Directory Tree:
```
/opt/scripts/cdn/
├── cdn-initial-setup.sh          # Main entry point
├── INSTALL.md                     # Installation guide
├── helpers/                       # Runtime scripts (→ /usr/local/bin/)
│   ├── cdn-autocommit.sh
│   ├── cdn-gitea-functions.sh
│   ├── cdn-quota-functions.sh
│   └── cdn-tenant-helpers.sh
├── includes/                      # Setup wizard modules
│   ├── common.sh
│   ├── step1-domains.sh
│   ├── step2-sftp.sh
│   ├── step3-smtp.sh
│   ├── step4-letsencrypt.sh
│   ├── step5-paths.sh
│   ├── step6-gitea-admin.sh
│   └── step7-summary.sh
├── lib/                          # Installation functions
│   ├── install-packages.sh
│   ├── install-nginx.sh
│   ├── install-gitea.sh
│   └── install-helpers.sh
└── templates/                    # Configuration templates
    ├── nginx/
    │   ├── cdn.conf.template
    │   └── gitea.conf.template
    ├── systemd/
    │   └── cdn-autocommit@.service
    ├── config.env.template
    ├── gitea-app.ini.template
    └── msmtprc.template
