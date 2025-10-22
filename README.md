# Multi-Tenant CDN System

A comprehensive, production-ready Content Delivery Network (CDN) system with automatic Git versioning, multi-tenant support, and complete management tools.

## Features

- 🚀 **Multi-Tenant Architecture**: Isolated environments per tenant
- 📦 **Automatic Git Versioning**: Every file change automatically committed
- 🔒 **Secure SFTP Access**: Chrooted SFTP with SSH key authentication
- 🌐 **Nginx CDN**: High-performance content delivery with caching
- 📊 **Gitea Integration**: Web-based Git repository management
- 💾 **Quota Management**: Per-tenant disk quotas with enforcement
- 📧 **Email Alerts**: Automated notifications for quota and system events
- 🔐 **Let's Encrypt SSL**: Automatic HTTPS with free certificates
- 🛠️ **Management Tools**: Comprehensive CLI tools for administration

## Quick Start

### 1. Deploy
```bash
sudo ./deploy.sh
```

### 2. Configure
```bash
sudo cdn-initial-setup
```

### 3. Setup SSL
```bash
sudo cdn-setup-letsencrypt
```

### 4. Create Tenant
```bash
sudo cdn-tenant-manager create mytenant
```

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Fast deployment guide
- **[INSTALL.md](INSTALL.md)** - Detailed installation instructions
- **[deployment-report.txt](deployment-report.txt)** - Post-deployment summary

## Architecture
```
┌─────────────────────────────────────────────────────────┐
│                     CDN System                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │  Tenant  │  │  Tenant  │  │  Tenant  │   ...         │
│  │    A     │  │    B     │  │    C     │               │
│  └────┬─────┘  └────┬─────┘  └─────┬────┘               │
│       │             │              │                    │
│  ┌────▼─────────────▼──────────────▼──────┐             │
│  │         SFTP (Chrooted)                │             │
│  └────┬───────────────────────────────────┘             │
│       │                                                 │
│  ┌────▼───────────────────────────────────┐             │
│  │      Auto-Commit (inotify)             │             │
│  └────┬───────────────────────────────────┘             │
│       │                                                 │
│  ┌────▼───────────────────────────────────┐             │
│  │      Git Repositories                  │             │
│  └────┬───────────────────────────────────┘             │
│       │                                                 │
│  ┌────▼───────────────────────────────────┐             │
│  │      Nginx CDN (Public)                │             │
│  └────────────────────────────────────────┘             │
│                                                         │
│  ┌───────────────────────────────────────┐              │
│  │      Gitea (Web Interface)            │              │
│  └───────────────────────────────────────┘              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## System Requirements

- **OS**: Ubuntu 20.04+ or Debian 11+
- **RAM**: Minimum 2GB (4GB+ recommended)
- **Disk**: Minimum 20GB free space
- **Network**: Public IP address
- **DNS**: Access to configure A records

## Directory Structure
```
/opt/scripts/cdn/           # Installation directory
├── cdn-initial-setup.sh    # Main setup wizard
├── deploy.sh               # Deployment script
├── helpers/                # Runtime management scripts
├── includes/               # Setup wizard modules
├── lib/                    # Installation libraries
└── templates/              # Configuration templates

/etc/cdn/                   # Configuration storage
├── config.env              # Main configuration
├── tenants/                # Per-tenant configs
├── quotas/                 # Quota settings
└── keys/                   # SSH keys

/srv/cdn/                   # Data storage
├── sftp/                   # SFTP directories
├── git/                    # Git repositories
├── www/                    # Nginx web root
└── backups/                # Backup storage

/usr/local/bin/             # Installed tools
├── cdn-tenant-helpers      # Tenant management
├── cdn-autocommit          # Auto-commit service
├── cdn-quota-functions     # Quota management
├── cdn-gitea-functions     # Gitea integration
└── cdn-setup-letsencrypt   # SSL management
```

## Management Commands

### Tenant Management
```bash
# Create tenant
sudo cdn-tenant-manager create <tenant> [email] [quota_mb]

# Update tenant
sudo cdn-tenant-helpers update-email <tenant> <email>
sudo cdn-tenant-helpers update-quota <tenant> <mb>

# View tenant
sudo cdn-tenant-helpers show <tenant>
sudo cdn-tenant-helpers list
```

### Quota Management
```bash
# Set quota
sudo cdn-quota-functions set <tenant> <mb>

# Check quota
sudo cdn-quota-functions show <tenant>
sudo cdn-quota-functions check-all

# Modify quota
sudo cdn-quota-functions increase <tenant> <mb>
sudo cdn-quota-functions decrease <tenant> <mb>
```

### Gitea Management
```bash
# User management
sudo cdn-gitea-functions add-user <tenant>
sudo cdn-gitea-functions reset-password <tenant>
sudo cdn-gitea-functions info <tenant>
```

## Monitoring

### Service Status
```bash
# Check Gitea
sudo systemctl status gitea

# Check auto-commit for tenant
sudo systemctl status cdn-autocommit@<tenant>

# View logs
sudo journalctl -u gitea -f
sudo journalctl -u cdn-autocommit@<tenant> -f
```

### System Health
```bash
# Check all quotas
sudo cdn-quota-functions check-all

# View CDN access logs
sudo tail -f /var/log/nginx/cdn_access.log

# View Gitea logs
sudo tail -f /home/git/gitea/log/gitea.log
```

## Security

- ✅ SSH key-only authentication (no passwords)
- ✅ Chrooted SFTP environments
- ✅ Per-tenant isolation
- ✅ Let's Encrypt SSL/TLS
- ✅ HSTS enabled
- ✅ Security headers configured
- ✅ Restricted file permissions

## Backup
```bash
# Backup configuration
sudo tar -czf cdn-config-backup.tar.gz /etc/cdn

# Backup data
sudo tar -czf cdn-data-backup.tar.gz /srv/cdn

# Backup Gitea
sudo tar -czf gitea-backup.tar.gz /home/git/gitea
```

## Uninstallation

To completely remove the CDN system:
```bash
sudo cdn-uninstall
```

This will:
- Create a complete backup before removal
- Remove all tenant accounts and data
- Remove Gitea and Git repositories
- Remove Nginx configuration
- Remove all installed scripts
- Optionally remove packages and SSL certificates

The backup is saved to `/root/cdn-backup-before-uninstall-TIMESTAMP/`

**Warning**: This action cannot be undone!


## Troubleshooting

### Debug Mode

Enable verbose error reporting:
```bash
DEBUG=true sudo cdn-initial-setup
```

### Common Issues

**Port conflicts:**
```bash
# Check what's using port 80/443
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443
```

**Permission issues:**
```bash
# Fix tenant permissions
sudo chown -R cdn_<tenant>:cdn_<tenant> /srv/cdn/sftp/<tenant>
```

**SSL certificate issues:**
```bash
# Test renewal
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal
```

## Contributing

This is a production-ready system. Contributions welcome:

1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit pull request

## License

[Your License Here]

## Support

For issues and questions:
- Review documentation in `INSTALL.md`
- Check deployment report
- Enable DEBUG mode for detailed errors
- Review system logs

## Credits

Multi-Tenant CDN System with integrated version control, quota management, and automated deployment.

---

**Version**: 1.0.0  
**Last Updated**: 2025-10-22
