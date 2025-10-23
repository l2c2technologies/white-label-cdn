# Multi-Tenant CDN System

A comprehensive, production-ready Content Delivery Network (CDN) system with automatic Git versioning, multi-tenant support, real-time quota monitoring, and complete management tools.

## Features

- 🚀 **Multi-Tenant Architecture**: Isolated environments per tenant
- 📦 **Automatic Git Versioning**: Every file change automatically committed
- 🔒 **Secure SFTP Access**: Chrooted SFTP with SSH key authentication
- 🌐 **Nginx CDN**: High-performance content delivery with caching
- 📊 **Gitea Integration**: Web-based Git repository management
- 💾 **Quota Management**: Per-tenant disk quotas with enforcement
- 📈 **Real-Time Monitoring**: inotify-based quota tracking and alerts
- 🏥 **System Health Monitoring**: Automated disk, memory, CPU, and service checks
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

### 5. Setup Monitoring (Optional)
```bash
sudo cdn-monitoring-setup
```

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Fast deployment guide
- **[INSTALL.md](INSTALL.md)** - Detailed installation instructions

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     CDN System Architecture                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │
│  │  Tenant  │  │  Tenant  │  │  Tenant  │   ...                 │
│  │    A     │  │    B     │  │    C     │                       │
│  └────┬─────┘  └────┬─────┘  └─────┬────┘                       │
│       │             │              │                            │
│  ┌────▼─────────────▼──────────────▼──────┐                     │
│  │         SFTP (Chrooted)                │                     │
│  └────┬───────────────────────────────────┘                     │
│       │                                                         │
│  ┌────▼───────────────────────────────────┐                     │
│  │      Auto-Commit (inotify)             │◄──┐                 │
│  └────┬───────────────────────────────────┘   │                 │
│       │                                       │                 │
│  ┌────▼───────────────────────────────────┐   │                 │
│  │      Git Repositories                  │   │                 │
│  └────┬───────────────────────────────────┘   │                 │
│       │                                       │                 │
│  ┌────▼───────────────────────────────────┐   │                 │
│  │      Nginx CDN (Public)                │   │                 │
│  └────────────────────────────────────────┘   │                 │
│                                               │                 │
│  ┌───────────────────────────────────────┐    │                 │
│  │      Gitea (Web Interface)            │    │                 │
│  └───────────────────────────────────────┘    │                 │
│                                               │                 │
│  ┌───────────────────────────────────────────────────┐          │
│  │      Monitoring & Alerting Layer                  │          │
│  ├───────────────────────────────────────────────────┤          │
│  │  • Real-time Quota Monitor (inotify)     ◄────────┘          │
│  │  • Automatic Enforcement (100% quota)             │          │
│  │  • Email Alerts (80%, 90%, 100%)                  │          │
│  │  • System Health Monitor (cron)                   │          │
│  │  • Git Integrity Checks (weekly)                  │          │
│  │  • Log Cleanup (monthly)                          │          │
│  └───────────────────────────────────────────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
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
├── cdn-tenant-manager.sh   # Tenant management
├── cdn-monitoring-setup.sh # Monitoring system setup
├── cdn-uninstall.sh        # System uninstaller
├── deploy.sh               # Deployment script
├── helpers/                # Runtime management scripts
│   ├── cdn-tenant-helpers.sh
│   ├── cdn-autocommit.sh
│   ├── cdn-quota-functions.sh
│   ├── cdn-setup-letsencrypt.sh
│   └── cdn-gitea-functions.sh
├── includes/               # Setup wizard modules
├── lib/                    # Installation libraries
├── monitoring/             # Monitoring system scripts
│   ├── cdn-health-monitor.sh
│   ├── cdn-monitoring-control.sh
│   └── cdn-quota-monitor-realtime.sh
└── templates/              # Configuration templates
    ├── nginx/
    ├── systemd/
    │   ├── cdn-autocommit@.service
    │   └── cdn-quota-monitor@.service
    └── *.template

/etc/cdn/                   # Configuration storage
├── config.env              # Main configuration
├── tenants/                # Per-tenant configs
├── quotas/                 # Quota settings
│   └── alerts_sent/        # Alert tracking
└── keys/                   # SSH keys

/srv/cdn/                   # Data storage
├── sftp/                   # SFTP directories
├── git/                    # Git repositories
├── www/                    # Nginx web root
└── backups/                # Backup storage

/var/log/cdn/               # Logging
├── *_quota_monitor.log     # Per-tenant quota logs
├── health_monitor.log      # System health logs
└── *-autocommit.log        # Per-tenant autocommit logs

/var/cache/cdn/             # Cache and state
├── quota/                  # Quota state files
│   └── *.state             # Current usage data
├── health/                 # Health check status
└── reports/                # Health reports

/usr/local/bin/             # Installed tools
├── cdn-initial-setup       # Setup wizard
├── cdn-tenant-manager      # Tenant management
├── cdn-monitoring-setup    # Monitoring setup
├── cdn-monitoring-control  # Monitoring control
├── cdn-tenant-helpers      # Tenant config functions
├── cdn-autocommit          # Auto-commit service
├── cdn-quota-functions     # Quota management
├── cdn-gitea-functions     # Gitea integration
├── cdn-health-monitor      # System health checks
└── cdn-setup-letsencrypt   # SSL management
```

## Management Commands

### Tenant Management
```bash
# Create tenant
sudo cdn-tenant-manager create <tenant> [email] [quota_mb]

# Update tenant
sudo cdn-tenant-manager update-email <tenant> <email>
sudo cdn-tenant-manager update-quota <tenant> <mb>

# View tenant
sudo cdn-tenant-manager show <tenant>
sudo cdn-tenant-manager list

# Suspend/restore
sudo cdn-tenant-manager suspend <tenant>
sudo cdn-tenant-manager restore <tenant>

# Delete tenant
sudo cdn-tenant-manager delete <tenant>
```

### Quota Management
```bash
# Set quota
sudo cdn-tenant-manager quota-set <tenant> <mb>

# Check quota
sudo cdn-tenant-manager quota-show <tenant>

# Modify quota
sudo cdn-tenant-manager quota-increase <tenant> <mb>
sudo cdn-tenant-manager quota-decrease <tenant> <mb>
```

### Monitoring Management
```bash
# Setup monitoring system
sudo cdn-monitoring-setup

# Control per-tenant monitors
sudo cdn-monitoring-control start <tenant>
sudo cdn-monitoring-control stop <tenant>
sudo cdn-monitoring-control restart <tenant>
sudo cdn-monitoring-control status <tenant>
sudo cdn-monitoring-control logs <tenant>

# Bulk operations
sudo cdn-monitoring-control start all
sudo cdn-monitoring-control stop all
sudo cdn-monitoring-control status

# System health
sudo cdn-monitoring-control health
```

### System Health Monitoring
```bash
# Run health check
sudo cdn-health-monitor check

# Check Git repositories
sudo cdn-health-monitor check-git

# Generate report
sudo cdn-health-monitor report

# Clean old logs
sudo cdn-health-monitor clean
```

### Gitea Management
```bash
# User management
sudo cdn-gitea-functions add-user <tenant>
sudo cdn-gitea-functions reset-password <tenant>
sudo cdn-gitea-functions info <tenant>
```

## Monitoring Features

### Real-Time Quota Monitoring

The system includes a comprehensive monitoring solution that tracks tenant usage in real-time:

- **inotify-based**: Instant detection of file changes
- **Automatic enforcement**: Read-only mode at 100% quota
- **Email alerts**: Notifications at 80%, 90%, and 100%
- **Alert cooldown**: Prevents alert spam (1 hour minimum)
- **Integration**: Uses `cdn-quota-functions` for consistency
- **Per-tenant services**: Systemd service per tenant

#### Setup
```bash
# Install monitoring system
sudo cdn-monitoring-setup

# Starts monitoring for all existing tenants
# Creates systemd services: cdn-quota-monitor@<tenant>.service
```

#### Control
```bash
# View status
sudo cdn-monitoring-control status

# Start/stop monitors
sudo cdn-monitoring-control start <tenant>
sudo cdn-monitoring-control stop all

# View logs
sudo cdn-monitoring-control logs <tenant> 100
```

### System Health Monitoring

Automated health checks run on a schedule via cron:

- **Every 15 minutes**: Disk space, services, resources, quotas
- **Weekly**: Git repository integrity checks
- **Weekly**: System health reports
- **Monthly**: Log cleanup

#### Features
- Disk space monitoring (warning at 80%, critical at 90%)
- Service status checks (nginx, gitea, sshd)
- Resource monitoring (CPU, memory, swap)
- Log file size tracking
- Tenant quota summary
- Git repository integrity verification

#### Logs
```bash
# View health monitor logs
sudo tail -f /var/log/cdn/health_monitor.log

# View recent health reports
ls -lh /var/cache/cdn/reports/
```

## Monitoring

### Service Status
```bash
# Check Gitea
sudo systemctl status gitea

# Check auto-commit for tenant
sudo systemctl status cdn-autocommit@<tenant>

# Check quota monitor for tenant
sudo systemctl status cdn-quota-monitor@<tenant>

# View logs
sudo journalctl -u gitea -f
sudo journalctl -u cdn-autocommit@<tenant> -f
sudo journalctl -u cdn-quota-monitor@<tenant> -f
```

### System Health
```bash
# Run health check
sudo cdn-health-monitor check

# Check all quotas
sudo cdn-tenant-manager quota-show <tenant>

# View CDN access logs
sudo tail -f /var/log/nginx/cdn_access.log

# View Gitea logs
sudo tail -f /home/git/gitea/log/gitea.log

# View per-tenant quota logs
sudo tail -f /var/log/cdn/<tenant>_quota_monitor.log
```

### Monitoring Status
```bash
# View all tenant monitoring status
sudo cdn-monitoring-control status

# List monitored tenants
sudo cdn-monitoring-control list

# Check specific tenant
sudo cdn-monitoring-control status <tenant>
```

## Security

- ✅ SSH key-only authentication (no passwords)
- ✅ Chrooted SFTP environments
- ✅ Per-tenant isolation
- ✅ Let's Encrypt SSL/TLS
- ✅ HSTS enabled
- ✅ Security headers configured
- ✅ Restricted file permissions
- ✅ Automatic quota enforcement
- ✅ Real-time monitoring and alerts

## Backup

### Manual Backup
```bash
# Backup configuration
sudo tar -czf cdn-config-backup.tar.gz /etc/cdn

# Backup data
sudo tar -czf cdn-data-backup.tar.gz /srv/cdn

# Backup Gitea
sudo tar -czf gitea-backup.tar.gz /home/git/gitea

# Backup logs
sudo tar -czf cdn-logs-backup.tar.gz /var/log/cdn
```

### Automated Backup (recommended)
```bash
# Setup automated daily backups with retention
cat > /etc/cron.daily/cdn-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/srv/cdn/backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/config.tar.gz" /etc/cdn
tar -czf "$BACKUP_DIR/data.tar.gz" /srv/cdn/sftp /srv/cdn/git
tar -czf "$BACKUP_DIR/gitea.tar.gz" /home/git/gitea
find /srv/cdn/backups -type d -mtime +30 -exec rm -rf {} \;
EOF

chmod +x /etc/cron.daily/cdn-backup
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
- Remove monitoring system
- Optionally remove packages and SSL certificates

The backup is saved to `/root/cdn-backup-before-uninstall-TIMESTAMP/`

**Warning**: This action cannot be undone!

## Troubleshooting

### Debug Mode

Enable verbose error reporting:
```bash
DEBUG=true sudo cdn-initial-setup
DEBUG=true sudo cdn-tenant-manager create tenant1
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

**Quota monitoring not working:**
```bash
# Check if monitoring service is running
sudo systemctl status cdn-quota-monitor@<tenant>

# Restart monitoring service
sudo cdn-monitoring-control restart <tenant>

# View logs for errors
sudo journalctl -u cdn-quota-monitor@<tenant> -n 100

# Check quota functions are installed
ls -lh /usr/local/bin/cdn-quota-functions

# Manually check quota
sudo cdn-tenant-manager quota-show <tenant>
```

**Email alerts not sending:**
```bash
# Check SMTP configuration
cat /etc/msmtprc

# Test email
echo "test" | mail -s "Test" your@email.com

# Check msmtp logs
sudo tail -f /var/log/msmtp.log

# Verify SMTP settings in config
grep SMTP /etc/cdn/config.env
```

**Health monitor issues:**
```bash
# Check if health monitor is installed
which cdn-health-monitor

# Run manual health check
sudo cdn-health-monitor check

# View health logs
sudo tail -f /var/log/cdn/health_monitor.log

# Check cron jobs
sudo crontab -l | grep cdn-health
```

## Performance Optimization

### Nginx Caching
```bash
# View cache size
du -sh /var/cache/nginx/cdn

# Clear cache if needed
sudo rm -rf /var/cache/nginx/cdn/*
sudo systemctl reload nginx
```

### Git Repository Optimization
```bash
# Optimize git repository for tenant
cd /srv/cdn/git/<tenant>.git
sudo -u git git gc --aggressive --prune=now

# Optimize all repositories
for repo in /srv/cdn/git/*.git; do
    echo "Optimizing $repo"
    cd "$repo"
    sudo -u git git gc --aggressive --prune=now
done
```

### Log Rotation
```bash
# Setup log rotation for CDN logs
cat > /etc/logrotate.d/cdn << 'EOF'
/var/log/cdn/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF
```

## Advanced Configuration

### Custom Quota Thresholds

Edit `/usr/local/bin/cdn-quota-monitor-realtime.sh`:
```bash
# Default thresholds
THRESHOLD_WARNING=80   # Warning at 80%
THRESHOLD_CRITICAL=90  # Critical at 90%
THRESHOLD_FULL=100     # Enforce at 100%
```

### Custom Health Check Intervals

Edit crontab:
```bash
sudo crontab -e

# Change health check frequency
*/15 * * * * # Every 15 minutes (default)
*/5 * * * *  # Every 5 minutes (more frequent)
0 * * * *    # Every hour (less frequent)
```

### Custom Alert Cooldown

Edit monitoring scripts:
```bash
# In cdn-quota-monitor-realtime.sh
ALERT_COOLDOWN=3600  # 1 hour (default)
ALERT_COOLDOWN=7200  # 2 hours
ALERT_COOLDOWN=1800  # 30 minutes
```

## API Integration (Future)

The system is designed to support API integration:

```bash
# Example: Create tenant via API (planned)
curl -X POST https://api.cdn.example.com/tenants \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "newtenant", "quota": 500}'

# Example: Check quota via API (planned)
curl https://api.cdn.example.com/tenants/newtenant/quota \
  -H "Authorization: Bearer $TOKEN"
```

## Contributing

This is a production-ready system. Contributions welcome:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test thoroughly on a test instance
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Submit pull request

### Development Guidelines

- Follow existing code structure
- Add comprehensive error handling
- Include logging for debugging
- Test with multiple tenants
- Update documentation
- Verify monitoring integration

## Testing

### Test Installation
```bash
# Deploy to test instance
sudo ./deploy.sh

# Run setup with test domains
sudo cdn-initial-setup
# Use test domains like: cdn.test.local, git.test.local

# Create test tenant
sudo cdn-tenant-manager create testuser test@example.com 100

# Upload test file via SFTP
echo "test" > test.txt
sftp -P 2222 -i /etc/cdn/keys/testuser/id_ed25519 \
  cdn_testuser@cdn.test.local << EOF
put test.txt
bye
EOF

# Verify CDN access
curl http://cdn.test.local/testuser/test.txt

# Test quota enforcement
# ... fill quota to 100% and verify read-only mode

# Test monitoring
sudo cdn-monitoring-setup
sudo cdn-monitoring-control status testuser

# Test cleanup
sudo cdn-tenant-manager delete testuser --force
sudo cdn-uninstall
```

## License

[Your License Here]

## Support

For issues and questions:
- Review documentation in `INSTALL.md`
- Check deployment report at `/opt/scripts/cdn/deployment-report.txt`
- Enable DEBUG mode for detailed errors
- Review system logs in `/var/log/cdn/`
- Check monitoring status: `sudo cdn-monitoring-control status`
- Run health check: `sudo cdn-health-monitor check`

### Common Support Scenarios

**Scenario 1: Tenant over quota**
```bash
# Check current usage
sudo cdn-tenant-manager quota-show <tenant>

# Options:
# 1. Increase quota
sudo cdn-tenant-manager quota-increase <tenant> 100

# 2. Ask tenant to delete files
# 3. Enforce remains until under quota
```

**Scenario 2: Monitoring not working**
```bash
# Reinstall monitoring
sudo cdn-monitoring-setup

# Start monitors
sudo cdn-monitoring-control start all

# Check status
sudo cdn-monitoring-control status
```

**Scenario 3: Performance issues**
```bash
# Check disk space
df -h

# Check memory
free -h

# Optimize Git repos
cd /srv/cdn/git && sudo -u git git gc --aggressive

# Check Nginx cache size
du -sh /var/cache/nginx/cdn

# Run health check
sudo cdn-health-monitor check
```

## Credits

Multi-Tenant CDN System with integrated version control, real-time quota monitoring, automated alerts, and comprehensive system health monitoring.

**Version**: 2.0.0  
**Last Updated**: 2025-10-22

### Changelog

**2.0.0 (2025-10-22)**
- ✨ Added real-time quota monitoring system
- ✨ Added system health monitoring
- ✨ Added automated log cleanup
- ✨ Added Git repository integrity checks
- 🔧 Enhanced email alert system with cooldown
- 🔧 Automatic quota enforcement at 100%
- 📊 Monitoring control interface
- 📧 Multi-recipient alert support
- 🏥 Health reports and status tracking

**1.0.0 (Initial Release)**
- 🚀 Multi-tenant CDN architecture
- 📦 Automatic Git versioning
- 🔒 Secure SFTP with SSH keys
- 🌐 Nginx CDN with caching
- 📊 Gitea web interface
- 💾 Disk quota management
- 📧 Email alerts
- 🔐 Let's Encrypt SSL

---

**🎉 Ready to deploy? Start with:** `sudo ./deploy.sh`
