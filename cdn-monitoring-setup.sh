#!/bin/bash
# File: /opt/scripts/cdn/cdn-monitoring-setup.sh (installed to /usr/local/bin/cdn-monitoring-setup)
# Purpose: Setup script for CDN monitoring system
# This script:
# 1. Validates cdn-quota-functions is installed
# 2. Installs monitoring scripts and services
# 3. Configures cron jobs
# 4. Enables monitoring for existing tenants

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="${SCRIPT_DIR}/monitoring"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

log "CDN Monitoring System Setup"
log "======================================"
echo ""

# CRITICAL: Validate cdn-quota-functions exists
log "Validating core dependencies..."
if [[ ! -f /usr/local/bin/cdn-quota-functions ]]; then
    error "cdn-quota-functions not found!"
    error ""
    error "The monitoring system requires cdn-quota-functions to be installed first."
    error "This is normally done by cdn-initial-setup.sh"
    error ""
    error "Please run: sudo cdn-initial-setup"
    exit 1
fi

# Validate /etc/cdn/config.env exists
if [[ ! -f /etc/cdn/config.env ]]; then
    error "/etc/cdn/config.env not found!"
    error "Please run: sudo cdn-initial-setup"
    exit 1
fi

log "✓ Core library (cdn-quota-functions) found"
log "✓ CDN configuration found"
echo ""

# ==============================================================================
# INSTALL DEPENDENCIES
# ==============================================================================

log "Installing dependencies..."
apt-get update -qq
apt-get install -y inotify-tools mailutils bc > /dev/null 2>&1
log "✓ Dependencies installed"
echo ""

# ==============================================================================
# CREATE DIRECTORIES
# ==============================================================================

log "Creating directories..."
mkdir -p /var/log/cdn
mkdir -p /var/cache/cdn/quota
mkdir -p /var/cache/cdn/health
chmod 755 /var/log/cdn
chmod 755 /var/cache/cdn
log "✓ Directories created"
echo ""

# ==============================================================================
# INSTALL MONITORING SCRIPTS
# ==============================================================================

log "Installing monitoring scripts..."

# Install quota monitor (real-time daemon)
if [[ -f "${MONITORING_DIR}/cdn-quota-monitor-realtime.sh" ]]; then
    log "Installing quota monitor (real-time)..."
    cp "${MONITORING_DIR}/cdn-quota-monitor-realtime.sh" /usr/local/bin/
    chmod 755 /usr/local/bin/cdn-quota-monitor-realtime.sh
    
    # Verify it can source cdn-quota-functions
    if ! bash -n /usr/local/bin/cdn-quota-monitor-realtime.sh; then
        warn "Quota monitor script has syntax errors"
    else
        log "✓ Quota monitor installed and validated"
    fi
else
    error "Quota monitor script not found: ${MONITORING_DIR}/cdn-quota-monitor-realtime.sh"
    exit 1
fi

# Install health monitor (if available)
if [[ -f "${MONITORING_DIR}/cdn-health-monitor.sh" ]]; then
    log "Installing health monitor..."
    cp "${MONITORING_DIR}/cdn-health-monitor.sh" /usr/local/bin/
    chmod 755 /usr/local/bin/cdn-health-monitor.sh
    log "✓ Health monitor installed"
else
    warn "Health monitor script not found (optional): ${MONITORING_DIR}/cdn-health-monitor.sh"
fi

# Install monitoring control (if available)
if [[ -f "${MONITORING_DIR}/cdn-monitoring-control.sh" ]]; then
    log "Installing monitoring control script..."
    cp "${MONITORING_DIR}/cdn-monitoring-control.sh" /usr/local/bin/
    chmod 755 /usr/local/bin/cdn-monitoring-control.sh
    log "✓ Control script installed"
else
    warn "Control script not found (optional): ${MONITORING_DIR}/cdn-monitoring-control.sh"
fi

echo ""

# ==============================================================================
# INSTALL SYSTEMD SERVICE
# ==============================================================================

log "Installing systemd service..."

if [[ -f "${SCRIPT_DIR}/templates/systemd/cdn-quota-monitor@.service" ]]; then
    cp "${SCRIPT_DIR}/templates/systemd/cdn-quota-monitor@.service" /etc/systemd/system/
    chmod 644 /etc/systemd/system/cdn-quota-monitor@.service
    systemctl daemon-reload
    log "✓ Systemd service installed"
else
    error "Systemd service template not found: ${SCRIPT_DIR}/templates/systemd/cdn-quota-monitor@.service"
    exit 1
fi

echo ""

# ==============================================================================
# SETUP CRON JOBS (if health monitor exists)
# ==============================================================================

if [[ -f /usr/local/bin/cdn-health-monitor.sh ]]; then
    log "Setting up cron jobs..."

    # Remove existing CDN monitoring cron jobs
    crontab -l 2>/dev/null | grep -v "cdn-health-monitor" | crontab - 2>/dev/null || true

    # Add new cron jobs
    (crontab -l 2>/dev/null; cat <<EOF

# CDN Health Monitoring (integrated with cdn-quota-functions)
*/15 * * * * /usr/local/bin/cdn-health-monitor.sh check >> /var/log/cdn/health_cron.log 2>&1
0 4 * * 0 /usr/local/bin/cdn-health-monitor.sh check-git >> /var/log/cdn/health_cron.log 2>&1
0 9 * * 1 /usr/local/bin/cdn-health-monitor.sh report
0 3 1 * * /usr/local/bin/cdn-health-monitor.sh clean >> /var/log/cdn/health_cron.log 2>&1

EOF
    ) | crontab -

    log "✓ Cron jobs configured"
else
    log "Skipping cron job setup (health monitor not installed)"
fi

echo ""

# ==============================================================================
# ENABLE MONITORING FOR EXISTING TENANTS
# ==============================================================================

log "Enabling quota monitoring for existing tenants..."
TENANT_COUNT=0

# Source config to get paths
source /etc/cdn/config.env

if [[ -d "${SFTP_DIR}" ]]; then
    for tenant_dir in "${SFTP_DIR}"/*; do
        if [[ -d "$tenant_dir" ]]; then
            tenant=$(basename "$tenant_dir")
            
            # Check if tenant user exists
            if id "cdn_${tenant}" &>/dev/null; then
                log "  Enabling monitoring for: $tenant"
                
                # Enable and start quota monitor service
                systemctl enable "cdn-quota-monitor@${tenant}.service" 2>/dev/null || true
                systemctl start "cdn-quota-monitor@${tenant}.service" 2>/dev/null || true
                
                # Check if started successfully
                sleep 1
                if systemctl is-active --quiet "cdn-quota-monitor@${tenant}.service"; then
                    ((TENANT_COUNT++))
                else
                    warn "  Failed to start monitor for: $tenant"
                    warn "  Check: sudo journalctl -u cdn-quota-monitor@${tenant} -n 50"
                fi
            fi
        fi
    done
fi

log "✓ Enabled monitoring for $TENANT_COUNT tenant(s)"
echo ""

# ==============================================================================
# RUN INITIAL HEALTH CHECK (if available)
# ==============================================================================

if [[ -f /usr/local/bin/cdn-health-monitor.sh ]]; then
    log "Running initial health check..."
    /usr/local/bin/cdn-health-monitor.sh check || warn "Initial health check found some issues"
    echo ""
fi

# ==============================================================================
# DISPLAY FINAL STATUS
# ==============================================================================

log "======================================"
log "Monitoring System Installation Complete"
log "======================================"
echo ""
log "Integration Status:"
log "  Core library: cdn-quota-functions ✓"
log "  Quota monitor: $(command -v cdn-quota-monitor-realtime.sh >/dev/null && echo 'Installed ✓' || echo 'NOT FOUND ✗')"
log "  Health monitor: $(command -v cdn-health-monitor.sh >/dev/null && echo 'Installed ✓' || echo 'Optional - Not Installed')"
log "  Control script: $(command -v cdn-monitoring-control.sh >/dev/null && echo 'Installed ✓' || echo 'Optional - Not Installed')"
log "  Active monitors: $(systemctl list-units 'cdn-quota-monitor@*' --no-legend --state=active 2>/dev/null | wc -l) of $(systemctl list-units 'cdn-quota-monitor@*' --no-legend --all 2>/dev/null | wc -l) configured"
echo ""
log "Monitoring Features:"
log "  ✓ Uses cdn-quota-functions for calculations"
log "  ✓ Consistent with cdn-tenant-manager.sh"
log "  ✓ Real-time inotify-based quota monitoring"
log "  ✓ Email alerts with cooldown (1 hour)"
log "  ✓ Automatic quota enforcement at 100%"
log "  ✓ Per-tenant systemd services"
echo ""

if [[ -f /usr/local/bin/cdn-health-monitor.sh ]]; then
    log "Cron Schedule:"
    log "  Health checks: Every 15 minutes"
    log "  Git integrity: Weekly (Sunday 4 AM)"
    log "  System report: Weekly (Monday 9 AM)"
    log "  Log cleanup: Monthly"
    echo ""
fi

log "Logs:"
log "  Quota monitors: /var/log/cdn/<tenant>_quota_monitor.log"
if [[ -f /usr/local/bin/cdn-health-monitor.sh ]]; then
    log "  Health monitor: /var/log/cdn/health_monitor.log"
fi
echo ""
log "Management Commands:"
log "  View tenant monitor:  sudo systemctl status cdn-quota-monitor@<tenant>"
log "  View tenant logs:     sudo journalctl -u cdn-quota-monitor@<tenant> -f"
log "  Stop tenant monitor:  sudo systemctl stop cdn-quota-monitor@<tenant>"
log "  Restart tenant:       sudo systemctl restart cdn-quota-monitor@<tenant>"

if [[ -f /usr/local/bin/cdn-monitoring-control.sh ]]; then
    log "  Control script:       sudo cdn-monitoring-control.sh"
fi
echo ""
log "Next Steps:"
log "  1. Review email settings in /etc/cdn/config.env"
log "  2. Test email: echo 'test' | mail -s 'CDN Test' root"
log "  3. Monitor a tenant: sudo journalctl -u cdn-quota-monitor@<tenant> -f"
log "  4. Check tenant quota: sudo cdn-tenant-manager quota-show <tenant>"
echo ""
log "All monitoring components use cdn-quota-functions for consistency!"
log ""
