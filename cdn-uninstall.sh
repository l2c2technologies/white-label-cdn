#!/bin/bash
# File: /opt/scripts/cdn/cdn-uninstall.sh (installed to /usr/local/bin/cdn-uninstall)
# Purpose: Complete uninstallation script for Multi-Tenant CDN System
#          Safely removes all components, configurations, data, and services
#          Provides backup option before removal

set -eE

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# DEBUG mode
DEBUG="${DEBUG:-false}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration file
CONFIG_FILE="/etc/cdn/config.env"

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[UNINSTALL]${NC} $1"; }

# ==============================================================================
# ERROR HANDLING
# ==============================================================================

error_handler() {
    local line_no=$1
    local bash_lineno=$2
    local last_command=$3
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "UNINSTALLATION ERROR OCCURRED" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "Command: ${last_command}" >&2
    echo "Exit Code: $?" >&2
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "" >&2
        echo "Debug Information:" >&2
        echo "  File: ${BASH_SOURCE[1]}" >&2
        echo "  Line: ${line_no}" >&2
    fi
    
    echo "" >&2
    echo "Uninstallation failed. System may be in partially removed state." >&2
    echo "Check the error and either:" >&2
    echo "  • Fix the issue and re-run uninstall" >&2
    echo "  • Manually remove remaining components" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    exit 1
}

trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND"' ERR

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

# ==============================================================================
# BACKUP BEFORE UNINSTALL
# ==============================================================================

backup_before_uninstall() {
    local backup_dir="/root/cdn-backup-before-uninstall-$(date +%Y%m%d_%H%M%S)"
    
    log "Creating backup before uninstallation..."
    mkdir -p "$backup_dir"
    
    # Backup configuration
    if [[ -d /etc/cdn ]]; then
        log "Backing up configuration..."
        tar -czf "${backup_dir}/etc-cdn.tar.gz" /etc/cdn 2>/dev/null || true
    fi
    
    # Backup data (if exists and not too large)
    if [[ -d /srv/cdn ]]; then
        local data_size=$(du -sm /srv/cdn 2>/dev/null | awk '{print $1}')
        
        if [[ -n "$data_size" ]] && [[ $data_size -lt 10000 ]]; then
            log "Backing up data (${data_size}MB)..."
            tar -czf "${backup_dir}/srv-cdn.tar.gz" /srv/cdn 2>/dev/null || true
        else
            warn "Data directory too large (${data_size}MB), skipping data backup"
            warn "Manually backup /srv/cdn if needed"
        fi
    fi
    
    # Backup logs
    if [[ -d /var/log/cdn ]]; then
        log "Backing up logs..."
        tar -czf "${backup_dir}/var-log-cdn.tar.gz" /var/log/cdn 2>/dev/null || true
    fi
    
    # Backup Gitea
    if [[ -d /home/git/gitea ]]; then
        log "Backing up Gitea..."
        tar -czf "${backup_dir}/gitea.tar.gz" /home/git/gitea 2>/dev/null || true
    fi
    
    # Save list of installed packages
    log "Saving installed packages list..."
    dpkg -l | grep -E 'nginx|git|openssh|inotify|msmtp' > "${backup_dir}/installed-packages.txt" 2>/dev/null || true
    
    # Save current system state
    cat > "${backup_dir}/system-state.txt" << EOFSTATE
CDN System Uninstallation Backup
Created: $(date)
Hostname: $(hostname)
IP: $(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)

Users backed up:
$(getent passwd | grep -E '^cdn_|^git:' || echo "None")

Services backed up:
$(systemctl list-units --all | grep -E 'cdn-|gitea|nginx' || echo "None")
EOFSTATE
    
    chmod 700 "$backup_dir"
    
    log "✓ Backup created: $backup_dir"
    echo ""
    
    return 0
}

# ==============================================================================
# STOP ALL SERVICES
# ==============================================================================

stop_all_services() {
    log "Stopping all CDN services..."
    
    # Stop all autocommit services
    for service in $(systemctl list-units --type=service --all | grep 'cdn-autocommit@' | awk '{print $1}'); do
        log "Stopping $service..."
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
    done
    
    # Stop Gitea
    if systemctl is-active --quiet gitea 2>/dev/null; then
        log "Stopping Gitea..."
        systemctl stop gitea
        systemctl disable gitea
    fi
    
    # Stop Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log "Stopping Nginx..."
        systemctl stop nginx
    fi
    
    log "✓ All services stopped"
    echo ""
}

# ==============================================================================
# REMOVE TENANT USERS AND DATA
# ==============================================================================

remove_all_tenants() {
    log "Removing all tenant users and data..."
    
    local tenant_count=0
    
    # Find all CDN tenant users
    for user in $(getent passwd | grep '^cdn_' | cut -d: -f1); do
        log "Removing tenant user: $user"
        
        # Stop any running processes for this user
        pkill -u "$user" 2>/dev/null || true
        
        # Remove user and home directory
        userdel -r "$user" 2>/dev/null || userdel "$user" 2>/dev/null || true
        
        ((tenant_count++))
    done
    
    if [[ $tenant_count -gt 0 ]]; then
        log "✓ Removed $tenant_count tenant user(s)"
    else
        log "No tenant users found"
    fi
    
    echo ""
}

# ==============================================================================
# REMOVE GIT USER
# ==============================================================================

remove_git_user() {
    log "Removing git user..."
    
    if id git &>/dev/null; then
        # Stop any git processes
        pkill -u git 2>/dev/null || true
        
        # Remove user
        userdel -r git 2>/dev/null || userdel git 2>/dev/null || true
        log "✓ Git user removed"
    else
        log "Git user not found"
    fi
    
    echo ""
}

# ==============================================================================
# REMOVE GROUPS
# ==============================================================================

remove_groups() {
    log "Removing CDN groups..."
    
    if getent group sftpusers >/dev/null; then
        groupdel sftpusers 2>/dev/null || true
        log "✓ Removed sftpusers group"
    fi
    
    if getent group git >/dev/null; then
        groupdel git 2>/dev/null || true
        log "✓ Removed git group"
    fi
    
    echo ""
}

# ==============================================================================
# REMOVE SYSTEMD SERVICES
# ==============================================================================

remove_systemd_services() {
    log "Removing systemd services..."
    
    # Remove autocommit service template
    if [[ -f /etc/systemd/system/cdn-autocommit@.service ]]; then
        rm -f /etc/systemd/system/cdn-autocommit@.service
        log "✓ Removed cdn-autocommit@.service"
    fi
    
    # Remove Gitea service
    if [[ -f /etc/systemd/system/gitea.service ]]; then
        rm -f /etc/systemd/system/gitea.service
        log "✓ Removed gitea.service"
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    log "✓ Systemd services removed"
    echo ""
}

# ==============================================================================
# REMOVE NGINX CONFIGURATION
# ==============================================================================

remove_nginx_configuration() {
    log "Removing Nginx configuration..."
    
    # Remove CDN site
    if [[ -L /etc/nginx/sites-enabled/cdn ]]; then
        rm -f /etc/nginx/sites-enabled/cdn
        log "✓ Removed CDN site (enabled)"
    fi
    
    if [[ -f /etc/nginx/sites-available/cdn ]]; then
        rm -f /etc/nginx/sites-available/cdn
        log "✓ Removed CDN site (available)"
    fi
    
    # Remove Gitea site
    if [[ -L /etc/nginx/sites-enabled/gitea ]]; then
        rm -f /etc/nginx/sites-enabled/gitea
        log "✓ Removed Gitea site (enabled)"
    fi
    
    if [[ -f /etc/nginx/sites-available/gitea ]]; then
        rm -f /etc/nginx/sites-available/gitea
        log "✓ Removed Gitea site (available)"
    fi
    
    # Remove cache directory
    if [[ -d /var/cache/nginx/cdn ]]; then
        rm -rf /var/cache/nginx/cdn
        log "✓ Removed Nginx cache"
    fi
    
    # Test and reload Nginx if still installed
    if command -v nginx &>/dev/null; then
        if nginx -t 2>/dev/null; then
            systemctl reload nginx 2>/dev/null || true
        fi
    fi
    
    log "✓ Nginx configuration removed"
    echo ""
}

# ==============================================================================
# REMOVE INSTALLED SCRIPTS
# ==============================================================================

remove_installed_scripts() {
    log "Removing installed scripts..."
    
    local scripts=(
        /usr/local/bin/cdn-tenant-manager
        /usr/local/bin/cdn-tenant-helpers
        /usr/local/bin/cdn-autocommit
        /usr/local/bin/cdn-quota-functions
        /usr/local/bin/cdn-gitea-functions
        /usr/local/bin/cdn-setup-letsencrypt
        /usr/local/bin/cdn-initial-setup
        /usr/local/bin/cdn-deploy
        /usr/local/bin/cdn-uninstall
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]] || [[ -L "$script" ]]; then
            rm -f "$script"
            log "✓ Removed $(basename $script)"
        fi
    done
    
    log "✓ Installed scripts removed"
    echo ""
}

# ==============================================================================
# REMOVE DATA DIRECTORIES
# ==============================================================================

remove_data_directories() {
    log "Removing data directories..."
    
    # /srv/cdn
    if [[ -d /srv/cdn ]]; then
        rm -rf /srv/cdn
        log "✓ Removed /srv/cdn"
    fi
    
    # /var/log/cdn
    if [[ -d /var/log/cdn ]]; then
        rm -rf /var/log/cdn
        log "✓ Removed /var/log/cdn"
    fi
    
    # /etc/cdn
    if [[ -d /etc/cdn ]]; then
        rm -rf /etc/cdn
        log "✓ Removed /etc/cdn"
    fi
    
    # /var/lib/cdn
    if [[ -d /var/lib/cdn ]]; then
        rm -rf /var/lib/cdn
        log "✓ Removed /var/lib/cdn"
    fi
    
    # /home/git
    if [[ -d /home/git ]]; then
        rm -rf /home/git
        log "✓ Removed /home/git"
    fi
    
    log "✓ Data directories removed"
    echo ""
}

# ==============================================================================
# REMOVE INSTALLATION DIRECTORY
# ==============================================================================

remove_installation_directory() {
    log "Removing installation directory..."
    
    if [[ -d /opt/scripts/cdn ]]; then
        rm -rf /opt/scripts/cdn
        log "✓ Removed /opt/scripts/cdn"
    fi
    
    echo ""
}

# ==============================================================================
# REMOVE SSHD CONFIGURATION
# ==============================================================================

remove_sshd_configuration() {
    log "Cleaning up SSHD configuration..."
    
    if grep -q "# CDN SFTP Configuration" /etc/ssh/sshd_config; then
        # Remove CDN-specific SSHD config
        sed -i '/# CDN SFTP Configuration/,/^$/d' /etc/ssh/sshd_config
        
        # Restart SSHD
        systemctl restart sshd
        
        log "✓ SSHD configuration cleaned"
    else
        log "No CDN SSHD configuration found"
    fi
    
    echo ""
}

# ==============================================================================
# REMOVE CRON JOBS
# ==============================================================================

remove_cron_jobs() {
    log "Removing cron jobs..."
    
    # Remove any CDN-related cron jobs
    if [[ -f /etc/cron.d/cdn-quota-check ]]; then
        rm -f /etc/cron.d/cdn-quota-check
        log "✓ Removed CDN cron jobs"
    fi
    
    # Check user crontabs
    for user in $(getent passwd | grep '^cdn_' | cut -d: -f1); do
        crontab -u "$user" -r 2>/dev/null || true
    done
    
    log "✓ Cron jobs checked and removed"
    echo ""
}

# ==============================================================================
# OPTIONAL: REMOVE PACKAGES
# ==============================================================================

remove_packages() {
    log "Removing installed packages..."
    warn "This will remove Nginx, Gitea, and related packages"
    echo ""
    
    read -p "Do you want to remove packages? (yes/no): " remove_pkgs
    
    if [[ "$remove_pkgs" == "yes" ]]; then
        log "Removing packages..."
        
        # Stop services first
        systemctl stop nginx 2>/dev/null || true
        systemctl stop gitea 2>/dev/null || true
        
        # Remove packages
        apt-get remove --purge -y \
            nginx \
            nginx-common \
            git \
            inotify-tools \
            msmtp \
            msmtp-mta 2>/dev/null || true
        
        # Clean up
        apt-get autoremove -y 2>/dev/null || true
        apt-get autoclean 2>/dev/null || true
        
        log "✓ Packages removed"
    else
        log "Skipping package removal"
    fi
    
    echo ""
}

# ==============================================================================
# REMOVE SSL CERTIFICATES
# ==============================================================================

remove_ssl_certificates() {
    log "Checking for SSL certificates..."
    
    # Check if certbot is installed
    if command -v certbot &>/dev/null; then
        warn "Let's Encrypt certificates found"
        echo ""
        
        read -p "Do you want to remove SSL certificates? (yes/no): " remove_ssl
        
        if [[ "$remove_ssl" == "yes" ]]; then
            # List certificates
            log "Removing certificates..."
            certbot delete --non-interactive 2>/dev/null || true
            log "✓ SSL certificates removed"
        else
            log "Skipping SSL certificate removal"
        fi
    else
        log "No SSL certificates found"
    fi
    
    echo ""
}

# ==============================================================================
# FINAL CLEANUP
# ==============================================================================

final_cleanup() {
    log "Performing final cleanup..."
    
    # Remove any leftover files
    find /tmp -name "*cdn*" -type f -mtime +1 -delete 2>/dev/null || true
    find /tmp -name "*gitea*" -type f -mtime +1 -delete 2>/dev/null || true
    
    # Clear any cached package data
    apt-get clean 2>/dev/null || true
    
    log "✓ Final cleanup complete"
    echo ""
}

# ==============================================================================
# VERIFICATION
# ==============================================================================

verify_removal() {
    log "Verifying removal..."
    
    local issues=0
    
    # Check for remaining tenant users
    if getent passwd | grep -q '^cdn_'; then
        warn "Some tenant users still exist"
        ((issues++))
    fi
    
    # Check for remaining services
    if systemctl list-units --all | grep -q 'cdn-autocommit'; then
        warn "Some CDN services still exist"
        ((issues++))
    fi
    
    # Check for remaining directories
    local dirs=(/srv/cdn /etc/cdn /var/log/cdn /opt/scripts/cdn /home/git)
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            warn "Directory still exists: $dir"
            ((issues++))
        fi
    done
    
    # Check for remaining scripts
    local scripts=(/usr/local/bin/cdn-*)
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]] || [[ -L "$script" ]]; then
            warn "Script still exists: $script"
            ((issues++))
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Verification complete - system is clean"
    else
        warn "Verification found $issues issue(s)"
        warn "Manual cleanup may be required"
    fi
    
    echo ""
}

# ==============================================================================
# MAIN UNINSTALLATION FLOW
# ==============================================================================

main() {
    clear
    
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║           Multi-Tenant CDN System - UNINSTALLER           ║
║                                                           ║
║    !!! WARNING: This will remove ALL CDN components !!!   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

EOF

    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "⚠️  DANGER: COMPLETE SYSTEM REMOVAL"
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    warn "This will permanently remove:"
    warn "  • All tenant accounts and data"
    warn "  • Git repositories"
    warn "  • Gitea installation"
    warn "  • Nginx CDN configuration"
    warn "  • All configuration files"
    warn "  • SSH keys"
    warn "  • Systemd services"
    warn "  • Installed scripts"
    warn "  • Log files"
    echo ""
    warn "A backup will be created before removal."
    echo ""
    warn "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    read -p "Type 'UNINSTALL' in capitals to confirm: " confirmation
    
    if [[ "$confirmation" != "UNINSTALL" ]]; then
        log "Uninstallation cancelled"
        exit 0
    fi
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Starting CDN System Uninstallation"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Create backup
    backup_before_uninstall
    
    # Stop all services
    stop_all_services
    
    # Remove tenants
    remove_all_tenants
    
    # Remove git user
    remove_git_user
    
    # Remove groups
    remove_groups
    
    # Remove systemd services
    remove_systemd_services
    
    # Remove nginx configuration
    remove_nginx_configuration
    
    # Remove installed scripts
    remove_installed_scripts
    
    # Remove cron jobs
    remove_cron_jobs
    
    # Remove SSHD config
    remove_sshd_configuration
    
    # Remove data directories
    remove_data_directories
    
    # Remove installation directory
    remove_installation_directory
    
    # Optional: Remove SSL certificates
    remove_ssl_certificates
    
    # Optional: Remove packages
    remove_packages
    
    # Final cleanup
    final_cleanup
    
    # Verify removal
    verify_removal
    
    # Final message
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "✓ CDN System Uninstallation Complete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "Backup location: /root/cdn-backup-before-uninstall-*"
    echo ""
    log "The CDN system has been removed from this server."
    log "You may want to:"
    log "  • Review the backup files"
    log "  • Reboot the server"
    log "  • Check for any remaining configuration"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << EOFHELP

CDN System Uninstaller

This script completely removes the Multi-Tenant CDN System from this server.

USAGE:
  sudo cdn-uninstall [OPTIONS]

OPTIONS:
  --help, -h          Show this help message

WHAT THIS SCRIPT DOES:
  1. Creates backup of all data and configuration
  2. Stops all services
  3. Removes all tenant users
  4. Removes Git and Gitea
  5. Removes Nginx configuration
  6. Removes systemd services
  7. Removes installed scripts
  8. Removes data directories
  9. Optionally removes packages and SSL certificates

BACKUP:
  A complete backup is created before removal at:
  /root/cdn-backup-before-uninstall-TIMESTAMP/

WARNING:
  This action cannot be undone. Make sure you have backups!

EOFHELP
    exit 0
fi

# Run main uninstallation
main "$@"

exit 0
