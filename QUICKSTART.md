# Quick Start Deployment Guide

## One-Command Deployment

### Option 1: Deploy from Local Directory

If you have all files in a directory:
```bash
cd /path/to/cdn-scripts
sudo ./deploy.sh
```

### Option 2: Deploy with Debug Mode

For verbose output during deployment:
```bash
DEBUG=true sudo ./deploy.sh
```

### Option 3: Custom Installation Directory

Deploy to a different location:
```bash
INSTALL_DIR=/custom/path sudo ./deploy.sh
```

## What the Deployment Script Does

1. **Preflight Checks**
   - Verifies root access
   - Checks disk space
   - Backs up existing installation if found

2. **Directory Structure**
   - Creates `/opt/scripts/cdn/` and subdirectories
   - Organizes files into helpers/, includes/, lib/, templates/

3. **File Deployment**
   - Copies all scripts and templates
   - Sets correct permissions (755 for executables, 644 for data)
   - Validates all files are present

4. **Validation**
   - Syntax checks on main scripts
   - Verifies all required files exist
   - Confirms proper permissions

5. **Convenience Setup**
   - Creates symlinks in `/usr/local/bin/`
   - Generates deployment report
   - Provides next steps

## After Deployment

### 1. Review Installation
```bash
cat /opt/scripts/cdn/deployment-report.txt
```

### 2. Read Documentation
```bash
cat /opt/scripts/cdn/INSTALL.md
```

### 3. Run Initial Setup
```bash
sudo cdn-initial-setup
# OR
sudo /opt/scripts/cdn/cdn-initial-setup.sh
```

### 4. Configure DNS

Point your domains to server IP:
```
cdn.example.com    A    YOUR_SERVER_IP
git.example.com    A    YOUR_SERVER_IP
```

### 5. Setup SSL

After DNS propagation:
```bash
sudo cdn-setup-letsencrypt
```

### 6. Create First Tenant
```bash
sudo cdn-tenant-manager create mytenant
```

## Troubleshooting Deployment

### Permission Denied
```bash
# Ensure deploy.sh is executable
chmod +x deploy.sh
sudo ./deploy.sh
```

### Deployment Fails
```bash
# Run with debug mode
DEBUG=true sudo ./deploy.sh
```

### Disk Space Issues
```bash
# Check available space
df -h /opt

# Clean up if needed
sudo apt-get clean
sudo apt-get autoremove
```

### Validation Errors

Check the deployment report for specific errors:
```bash
cat /opt/scripts/cdn/deployment-report.txt
```

## Uninstallation

To remove the deployment:
```bash
# Backup configuration first if needed
sudo cp -r /etc/cdn /root/cdn-config-backup

# Remove installation
sudo rm -rf /opt/scripts/cdn

# Remove symlinks
sudo rm -f /usr/local/bin/cdn-initial-setup
sudo rm -f /usr/local/bin/cdn-deploy
```

## Re-deployment

To redeploy (updates):
```bash
cd /path/to/updated-cdn-scripts
sudo ./deploy.sh
# Answer "yes" when asked to backup and overwrite
```

## Deployment on Different Systems

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y git wget curl
cd /opt/scripts/cdn
sudo ./deploy.sh
```

### CentOS/RHEL
```bash
sudo yum install -y git wget curl
cd /opt/scripts/cdn
sudo ./deploy.sh
```

### From Git Repository
```bash
sudo mkdir -p /opt/scripts
cd /opt/scripts
sudo git clone <your-repo-url> cdn
cd cdn
sudo ./deploy.sh
```

## Verification Commands

### Check Installation
```bash
# Verify main script
ls -lh /opt/scripts/cdn/cdn-initial-setup.sh

# Verify symlinks
ls -lh /usr/local/bin/cdn-*

# Check directory structure
tree /opt/scripts/cdn -L 2

# View deployment report
cat /opt/scripts/cdn/deployment-report.txt
```

### Test Syntax
```bash
# Test main orchestrator
bash -n /opt/scripts/cdn/cdn-initial-setup.sh

# Test helper scripts
for script in /opt/scripts/cdn/helpers/*.sh; do
    echo "Testing: $(basename $script)"
    bash -n "$script"
done
```

## Support

For deployment issues:

1. Check deployment report: `/opt/scripts/cdn/deployment-report.txt`
2. Run with DEBUG mode: `DEBUG=true sudo ./deploy.sh`
3. Review logs: Check console output for specific errors
4. Verify permissions: All `.sh` files should be executable

## Next Steps

After successful deployment:

1. ✅ Run `sudo cdn-initial-setup`
2. ✅ Configure your domains
3. ✅ Setup SSL certificates
4. ✅ Create your first tenant
5. ✅ Test SFTP access
6. ✅ Verify CDN is serving files

Enjoy your Multi-Tenant CDN System! 🚀
