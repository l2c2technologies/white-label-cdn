#!/bin/bash
# File: /opt/scripts/cdn/deploy.sh
# Purpose: Automated deployment script for Multi-Tenant CDN System
#          Creates directory structure, installs files, sets permissions, and validates installation
# Version: 2.0.0 - Added monitoring system support

set -eE

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Target installation directory
INSTALL_DIR="/opt/scripts/cdn"

# Script source directory (where this script is run from)
SCRIPT_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DEBUG mode: set to "true" for verbose output
DEBUG="${DEBUG:-false}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
info() { echo -e "${BLUE}[DEPLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==============================================================================
# ERROR HANDLING
# ==============================================================================

error_handler() {
    local line_no=$1
    local bash_lineno=$2
    local last_command=$3
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "DEPLOYMENT ERROR OCCURRED" >&2
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
    echo "Deployment failed. Please review the error and try again." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    exit 1
}

trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND"' ERR

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================

preflight_checks() {
    info "Running preflight checks..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
    
    # Check if installation directory already exists
    if [[ -d "$INSTALL_DIR" ]] && [[ "$INSTALL_DIR" != "$SCRIPT_SOURCE_DIR" ]]; then
        warn "Installation directory already exists: $INSTALL_DIR"
        read -p "Do you want to backup and overwrite? (yes/no): " response
        
        if [[ "$response" == "yes" ]]; then
            local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
            log "Backing up existing installation to: $backup_dir"
            mv "$INSTALL_DIR" "$backup_dir"
        else
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Check available disk space (need at least 1GB free)
    local available_space=$(df /opt | tail -1 | awk '{print $4}')
    if [[ $available_space -lt 1048576 ]]; then
        warn "Low disk space available in /opt: ${available_space}KB"
        warn "Recommended: At least 1GB free space"
        read -p "Continue anyway? (yes/no): " response
        [[ "$response" != "yes" ]] && exit 0
    fi
    
    log "✓ Preflight checks passed"
    echo ""
}

# ==============================================================================
# DIRECTORY STRUCTURE CREATION
# ==============================================================================

create_directory_structure() {
    info "Creating directory structure..."
    
    # Create main installation directory
    mkdir -p "$INSTALL_DIR"
    
    # Create subdirectories
    mkdir -p "$INSTALL_DIR"/{helpers,includes,lib,templates,monitoring}
    mkdir -p "$INSTALL_DIR"/templates/{nginx,systemd}
    
    log "✓ Directory structure created at: $INSTALL_DIR"
}

# ==============================================================================
# FILE DEPLOYMENT
# ==============================================================================

deploy_file() {
    local source_file=$1
    local dest_file=$2
    local permissions=${3:-644}
    
    if [[ ! -f "$source_file" ]]; then
        warn "Source file not found: $source_file (skipping)"
        return 1
    fi
    
    cp "$source_file" "$dest_file"
    chmod "$permissions" "$dest_file"
    
    if [[ "$DEBUG" == "true" ]]; then
        log "  Deployed: $(basename $dest_file) (mode: $permissions)"
    fi
    
    return 0
}

deploy_all_files() {
    info "Deploying files..."
    
    local files_deployed=0
    local files_failed=0
    
    # ===== MAIN SCRIPTS =====
    
    # Main orchestrator
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-initial-setup.sh" "${INSTALL_DIR}/cdn-initial-setup.sh" 755; then
        files_deployed=$((files_deployed + 1))
    else
        files_failed=$((files_failed + 1))
    fi

    # Main tenant manager
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-tenant-manager.sh" "${INSTALL_DIR}/cdn-tenant-manager.sh" 755; then
        files_deployed=$((files_deployed + 1))
    else
        files_failed=$((files_failed + 1))
    fi

    # Uninstaller
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-uninstall.sh" "${INSTALL_DIR}/cdn-uninstall.sh" 755; then
        files_deployed=$((files_deployed + 1))
    else
        files_failed=$((files_failed + 1))
    fi

    # Monitoring setup script (NEW)
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-monitoring-setup.sh" "${INSTALL_DIR}/cdn-monitoring-setup.sh" 755; then
        files_deployed=$((files_deployed + 1))
        log "✓ Deployed monitoring setup script"
    else
        files_failed=$((files_failed + 1))
        warn "Monitoring setup script not found (optional)"
    fi

    # ===== HELPER SCRIPTS =====
    
    log "Deploying helper scripts..."
    for helper in cdn-tenant-helpers.sh cdn-autocommit.sh cdn-quota-functions.sh cdn-gitea-functions.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/helpers/${helper}" "${INSTALL_DIR}/helpers/${helper}" 755; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # ===== MONITORING SCRIPTS (NEW) =====
    
    log "Deploying monitoring system scripts..."
    local monitoring_scripts=(
        "cdn-health-monitor.sh"
        "cdn-monitoring-control.sh"
        "cdn-quota-monitor-realtime.sh"
    )
    
    for monitor_script in "${monitoring_scripts[@]}"; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/monitoring/${monitor_script}" \
                      "${INSTALL_DIR}/monitoring/${monitor_script}" 755; then
            files_deployed=$((files_deployed + 1))
            log "✓ Deployed monitoring/${monitor_script}"
        else
            files_failed=$((files_failed + 1))
            warn "Monitoring script not found: ${monitor_script} (optional)"
        fi
    done
    
    # ===== INCLUDE FILES =====
    
    log "Deploying include files..."
    for include in common.sh step1-domains.sh step2-sftp.sh step3-smtp.sh \
                   step4-letsencrypt.sh step5-paths.sh step6-gitea-admin.sh step7-summary.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/includes/${include}" "${INSTALL_DIR}/includes/${include}" 644; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # ===== LIBRARY FILES =====
    
    log "Deploying library files..."
    for lib in install-packages.sh install-nginx.sh install-gitea.sh install-helpers.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/lib/${lib}" "${INSTALL_DIR}/lib/${lib}" 644; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # ===== TEMPLATE FILES =====
    
    log "Deploying template files..."
    for template in config.env.template gitea-app.ini.template \
                    letsencrypt-setup.sh.template msmtprc.template; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/templates/${template}" \
                      "${INSTALL_DIR}/templates/${template}" 644; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # Nginx templates
    log "Deploying Nginx templates..."
    for nginx_template in cdn.conf.template gitea.conf.template; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/templates/nginx/${nginx_template}" \
                      "${INSTALL_DIR}/templates/nginx/${nginx_template}" 644; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # Systemd templates
    log "Deploying systemd templates..."
    
    # Original autocommit template
    if deploy_file "${SCRIPT_SOURCE_DIR}/templates/systemd/cdn-autocommit@.service" \
                  "${INSTALL_DIR}/templates/systemd/cdn-autocommit@.service" 644; then
        files_deployed=$((files_deployed + 1))
    else
        files_failed=$((files_failed + 1))
    fi
    
    # NEW: Quota monitor template
    if deploy_file "${SCRIPT_SOURCE_DIR}/templates/systemd/cdn-quota-monitor@.service" \
                  "${INSTALL_DIR}/templates/systemd/cdn-quota-monitor@.service" 644; then
        files_deployed=$((files_deployed + 1))
        log "✓ Deployed quota monitor systemd template"
    else
        files_failed=$((files_failed + 1))
        warn "Quota monitor systemd template not found (optional)"
    fi
    
    # ===== DOCUMENTATION FILES =====
    
    log "Deploying documentation files..."
    for doc in INSTALL.md README.md QUICKSTART.md; do
        if [[ -f "${SCRIPT_SOURCE_DIR}/${doc}" ]]; then
            deploy_file "${SCRIPT_SOURCE_DIR}/${doc}" "${INSTALL_DIR}/${doc}" 644
            files_deployed=$((files_deployed + 1))
        else
            warn "Documentation file not found: ${doc} (optional)"
        fi
    done
    
    # ===== DEPLOYMENT SCRIPT ITSELF =====
    
    # Copy deploy.sh itself to installation directory
    if [[ -f "${SCRIPT_SOURCE_DIR}/deploy.sh" ]]; then
        deploy_file "${SCRIPT_SOURCE_DIR}/deploy.sh" "${INSTALL_DIR}/deploy.sh" 755
        files_deployed=$((files_deployed + 1))
    fi
    
    echo ""
    log "✓ Files deployed: $files_deployed"
    if [[ $files_failed -gt 0 ]]; then
        warn "Files failed/skipped: $files_failed"
    fi
}

# ==============================================================================
# VALIDATION
# ==============================================================================

validate_deployment() {
    info "Validating deployment..."
 
    local validation_errors=0

    # ===== CHECK MAIN SCRIPTS =====
    
    log "Validating main scripts..."
    
    # Check main orchestrator
    if [[ -x "${INSTALL_DIR}/cdn-initial-setup.sh" ]]; then
        log "✓ cdn-initial-setup.sh is executable"
    else
        error "cdn-initial-setup.sh installation failed"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check tenant manager
    if [[ -x "${INSTALL_DIR}/cdn-tenant-manager.sh" ]]; then
        log "✓ cdn-tenant-manager.sh is executable"
    else
        error "cdn-tenant-manager.sh installation failed"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check uninstaller
    if [[ -x "${INSTALL_DIR}/cdn-uninstall.sh" ]]; then
        log "✓ cdn-uninstall.sh is executable"
    else
        error "cdn-uninstall.sh installation failed"
        validation_errors=$((validation_errors + 1))
    fi

    # Check monitoring setup (optional but should warn)
    if [[ -x "${INSTALL_DIR}/cdn-monitoring-setup.sh" ]]; then
        log "✓ cdn-monitoring-setup.sh is executable"
    else
        warn "cdn-monitoring-setup.sh not installed (monitoring features unavailable)"
    fi

    # ===== CHECK HELPER SCRIPTS =====
    
    log "Validating helper scripts..."
    local helpers=(cdn-tenant-helpers.sh cdn-autocommit.sh cdn-quota-functions.sh cdn-gitea-functions.sh)
    for helper in "${helpers[@]}"; do
        if [[ -x "${INSTALL_DIR}/helpers/${helper}" ]]; then
            log "✓ ${helper} is executable"
        else
            error "Helper script not executable: $helper"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # ===== CHECK MONITORING SCRIPTS (NEW) =====
    
    log "Validating monitoring scripts..."
    local monitoring_count=0
    local monitoring_scripts=(
        "cdn-health-monitor.sh"
        "cdn-monitoring-control.sh"
        "cdn-quota-monitor-realtime.sh"
    )
    
    for monitor_script in "${monitoring_scripts[@]}"; do
        if [[ -x "${INSTALL_DIR}/monitoring/${monitor_script}" ]]; then
            log "✓ monitoring/${monitor_script} is executable"
            monitoring_count=$((monitoring_count + 1))
        else
            warn "Monitoring script not found: ${monitor_script} (optional)"
        fi
    done
    
    if [[ $monitoring_count -eq ${#monitoring_scripts[@]} ]]; then
        log "✓ All monitoring scripts present"
    elif [[ $monitoring_count -gt 0 ]]; then
        warn "Partial monitoring installation: ${monitoring_count}/${#monitoring_scripts[@]} scripts"
    else
        warn "No monitoring scripts installed (monitoring features unavailable)"
    fi
    
    # ===== CHECK INCLUDE FILES =====
    
    log "Validating include files..."
    local includes=(common.sh step1-domains.sh step2-sftp.sh step3-smtp.sh step4-letsencrypt.sh step5-paths.sh step6-gitea-admin.sh step7-summary.sh)
    for include in "${includes[@]}"; do
        if [[ -f "${INSTALL_DIR}/includes/${include}" ]]; then
            log "✓ ${include} present"
        else
            error "Include file missing: $include"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # ===== CHECK LIBRARY FILES =====
    
    log "Validating library files..."
    local libs=(install-packages.sh install-nginx.sh install-gitea.sh install-helpers.sh)
    for lib in "${libs[@]}"; do
        if [[ -f "${INSTALL_DIR}/lib/${lib}" ]]; then
            log "✓ ${lib} present"
        else
            error "Library file missing: $lib"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # ===== CHECK TEMPLATES =====
    
    log "Validating templates..."
    local templates=(config.env.template gitea-app.ini.template letsencrypt-setup.sh.template msmtprc.template)
    for template in "${templates[@]}"; do
        if [[ -f "${INSTALL_DIR}/templates/${template}" ]]; then
            log "✓ ${template} present"
        else
            error "Template file missing: $template"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # Check nginx templates
    if [[ -f "${INSTALL_DIR}/templates/nginx/cdn.conf.template" ]] && \
       [[ -f "${INSTALL_DIR}/templates/nginx/gitea.conf.template" ]]; then
        log "✓ Nginx templates present"
    else
        error "Nginx template files missing"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check systemd templates
    local systemd_templates=0
    if [[ -f "${INSTALL_DIR}/templates/systemd/cdn-autocommit@.service" ]]; then
        systemd_templates=$((systemd_templates + 1))
        log "✓ Autocommit systemd template present"
    else
        error "Autocommit systemd template missing"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [[ -f "${INSTALL_DIR}/templates/systemd/cdn-quota-monitor@.service" ]]; then
        systemd_templates=$((systemd_templates + 1))
        log "✓ Quota monitor systemd template present"
    else
        warn "Quota monitor systemd template not found (monitoring unavailable)"
    fi
    
    # ===== SYNTAX VALIDATION =====
    
    log "Running syntax validation..."
    
    # Check main scripts syntax
    if ! bash -n "${INSTALL_DIR}/cdn-initial-setup.sh" 2>/dev/null; then
        error "Syntax error in main orchestrator"
        validation_errors=$((validation_errors + 1))
    else
        log "✓ Main orchestrator syntax valid"
    fi
    
    if ! bash -n "${INSTALL_DIR}/cdn-tenant-manager.sh" 2>/dev/null; then
        error "Syntax error in tenant manager"
        validation_errors=$((validation_errors + 1))
    else
        log "✓ Tenant manager syntax valid"
    fi
    
    # Validate monitoring setup if present
    if [[ -f "${INSTALL_DIR}/cdn-monitoring-setup.sh" ]]; then
        if ! bash -n "${INSTALL_DIR}/cdn-monitoring-setup.sh" 2>/dev/null; then
            warn "Syntax error in monitoring setup script"
        else
            log "✓ Monitoring setup syntax valid"
        fi
    fi
    
    echo ""
    
    # ===== SUMMARY =====
    
    if [[ $validation_errors -eq 0 ]]; then
        log "✓ Validation passed - deployment is complete and valid"
        
        if [[ $monitoring_count -eq ${#monitoring_scripts[@]} ]]; then
            log "✓ Full installation including monitoring system"
        elif [[ $monitoring_count -gt 0 ]]; then
            warn "Partial installation - some monitoring components missing"
        else
            warn "Core installation complete - monitoring system not installed"
        fi
        
        return 0
    else
        error "Validation failed with $validation_errors error(s)"
        return 1
    fi
}

# ==============================================================================
# CREATE SYMBOLIC LINKS (OPTIONAL)
# ==============================================================================

create_symlinks() {
    info "Creating convenient symbolic links..."
 
    # Create symlink for easy access to main script
    if [[ ! -L /usr/local/bin/cdn-initial-setup ]]; then
        ln -sf "${INSTALL_DIR}/cdn-initial-setup.sh" /usr/local/bin/cdn-initial-setup
        log "✓ Created symlink: /usr/local/bin/cdn-initial-setup"
    fi

    # Create symlink for tenant manager
    if [[ ! -L /usr/local/bin/cdn-tenant-manager ]]; then
        ln -sf "${INSTALL_DIR}/cdn-tenant-manager.sh" /usr/local/bin/cdn-tenant-manager
        log "✓ Created symlink: /usr/local/bin/cdn-tenant-manager"
    fi

    # Create symlink for uninstaller
    if [[ ! -L /usr/local/bin/cdn-uninstall ]]; then
        ln -sf "${INSTALL_DIR}/cdn-uninstall.sh" /usr/local/bin/cdn-uninstall
        log "✓ Created symlink: /usr/local/bin/cdn-uninstall"
    fi

    # Create symlink for monitoring setup (if present)
    if [[ -f "${INSTALL_DIR}/cdn-monitoring-setup.sh" ]] && [[ ! -L /usr/local/bin/cdn-monitoring-setup ]]; then
        ln -sf "${INSTALL_DIR}/cdn-monitoring-setup.sh" /usr/local/bin/cdn-monitoring-setup
        log "✓ Created symlink: /usr/local/bin/cdn-monitoring-setup"
    fi

    # Create symlink for deploy script itself
    if [[ -f "${INSTALL_DIR}/deploy.sh" ]] && [[ ! -L /usr/local/bin/cdn-deploy ]]; then
        ln -sf "${INSTALL_DIR}/deploy.sh" /usr/local/bin/cdn-deploy
        log "✓ Created symlink: /usr/local/bin/cdn-deploy"
    fi
}

# ==============================================================================
# GENERATE DEPLOYMENT REPORT
# ==============================================================================

generate_deployment_report() {
    local report_file="${INSTALL_DIR}/deployment-report.txt"
    
    # Check if monitoring is installed
    local monitoring_status="Not Installed"
    local monitoring_scripts_installed=0
    
    if [[ -f "${INSTALL_DIR}/cdn-monitoring-setup.sh" ]]; then
        monitoring_status="Installed"
    fi
    
    if [[ -d "${INSTALL_DIR}/monitoring" ]]; then
        monitoring_scripts_installed=$(find "${INSTALL_DIR}/monitoring" -name "*.sh" -type f | wc -l)
    fi
    
    cat > "$report_file" << EOFCREATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CDN System Deployment Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Deployment Date: $(date '+%Y-%m-%d %H:%M:%S')
Installation Directory: ${INSTALL_DIR}
Deployed By: $(whoami)
Server: $(hostname)
Version: 2.0.0 (with monitoring support)

Directory Structure:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${INSTALL_DIR}/
├── cdn-initial-setup.sh          # Main orchestrator
├── cdn-tenant-manager.sh         # Tenant management
├── cdn-uninstall.sh              # System uninstaller
├── cdn-monitoring-setup.sh       # Monitoring setup (${monitoring_status})
├── deploy.sh                     # This deployment script
├── INSTALL.md                    # Installation guide
├── README.md                     # Documentation
├── QUICKSTART.md                 # Quick start guide
├── deployment-report.txt         # This report
├── helpers/                      # Runtime helper scripts
│   ├── cdn-autocommit.sh
│   ├── cdn-gitea-functions.sh
│   ├── cdn-quota-functions.sh
│   └── cdn-tenant-helpers.sh
├── includes/                     # Setup wizard modules
│   ├── common.sh
│   ├── step1-domains.sh
│   ├── step2-sftp.sh
│   ├── step3-smtp.sh
│   ├── step4-letsencrypt.sh
│   ├── step5-paths.sh
│   ├── step6-gitea-admin.sh
│   └── step7-summary.sh
├── lib/                         # Installation libraries
│   ├── install-packages.sh
│   ├── install-nginx.sh
│   ├── install-gitea.sh
│   └── install-helpers.sh
├── monitoring/                  # Monitoring system (${monitoring_scripts_installed} scripts)
│   ├── cdn-health-monitor.sh
│   ├── cdn-monitoring-control.sh
│   └── cdn-quota-monitor-realtime.sh
└── templates/                   # Configuration templates
    ├── config.env.template
    ├── gitea-app.ini.template
    ├── letsencrypt-setup.sh.template
    ├── msmtprc.template
    ├── nginx/
    │   ├── cdn.conf.template
    │   └── gitea.conf.template
    └── systemd/
        ├── cdn-autocommit@.service
        └── cdn-quota-monitor@.service

Symbolic Links Created:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/usr/local/bin/cdn-initial-setup → ${INSTALL_DIR}/cdn-initial-setup.sh
/usr/local/bin/cdn-tenant-manager → ${INSTALL_DIR}/cdn-tenant-manager.sh
/usr/local/bin/cdn-uninstall → ${INSTALL_DIR}/cdn-uninstall.sh
/usr/local/bin/cdn-monitoring-setup → ${INSTALL_DIR}/cdn-monitoring-setup.sh
/usr/local/bin/cdn-deploy → ${INSTALL_DIR}/deploy.sh

File Permissions:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Executable (755):
  - cdn-initial-setup.sh
  - cdn-tenant-manager.sh
  - cdn-uninstall.sh
  - cdn-monitoring-setup.sh
  - deploy.sh
  - helpers/*.sh
  - monitoring/*.sh

Readable (644):
  - includes/*.sh
  - lib/*.sh
  - templates/*
  - *.md

Next Steps:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Review the installation guide:
   cat ${INSTALL_DIR}/INSTALL.md

2. Run the initial setup wizard:
   sudo ${INSTALL_DIR}/cdn-initial-setup.sh
   
   Or using the symlink:
   sudo cdn-initial-setup

3. Configure DNS for your domains

4. Setup SSL certificates:
   sudo cdn-setup-letsencrypt

5. Create your first tenant:
   sudo cdn-tenant-manager create <tenant-name>
   
   Example:
   sudo cdn-tenant-manager create acmecorp admin@acme.com 500

6. (Optional) Setup monitoring system:
   sudo cdn-monitoring-setup

Quick Reference - Tenant Management:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create tenant:
  sudo cdn-tenant-manager create <name> [email] [quota-mb]

List tenants:
  sudo cdn-tenant-manager list

Show tenant info:
  sudo cdn-tenant-manager info <name>

Manage quota:
  sudo cdn-tenant-manager quota-set <name> <mb>
  sudo cdn-tenant-manager quota-increase <name> <mb>
  sudo cdn-tenant-manager quota-show <name>

Suspend/restore:
  sudo cdn-tenant-manager suspend <name>
  sudo cdn-tenant-manager restore <name>

Delete tenant:
  sudo cdn-tenant-manager delete <name>

View logs:
  sudo cdn-tenant-manager logs <name>

Monitoring System Features (if installed):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Setup monitoring:
  sudo cdn-monitoring-setup

Control monitoring:
  sudo cdn-monitoring-control status          # View all tenant status
  sudo cdn-monitoring-control start all       # Start all monitors
  sudo cdn-monitoring-control stop <tenant>   # Stop specific monitor
  sudo cdn-monitoring-control logs <tenant>   # View monitor logs

System health:
  sudo cdn-health-monitor check               # Run health check
  sudo cdn-health-monitor report              # Generate report

Features:
  • Real-time quota monitoring via inotify
  • Automatic enforcement at 100% quota
  • Email alerts at 80%, 90%, 100%
  • System health monitoring (disk, memory, services)
  • Git repository integrity checks
  • Automated log cleanup

Additional Information:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- All scripts include comprehensive error handling
- DEBUG mode available: DEBUG=true sudo cdn-initial-setup
- Configuration will be stored in: /etc/cdn/
- Helper scripts will be installed to: /usr/local/bin/
- Tenant manager coordinates all tenant operations
- Monitoring system provides real-time quota tracking

Installation Status:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Core System: Installed ✓
Monitoring System: ${monitoring_status}
Monitoring Scripts: ${monitoring_scripts_installed}/3

For support and documentation, see:
${INSTALL_DIR}/INSTALL.md
${INSTALL_DIR}/README.md
${INSTALL_DIR}/QUICKSTART.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Deployment completed successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOFCREATE
    
    chmod 644 "$report_file"
    log "✓ Deployment report created: $report_file"
}

# ==============================================================================
# MAIN DEPLOYMENT SEQUENCE
# ==============================================================================

main() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║      Multi-Tenant CDN System - Deployment Script          ║
║                   Version 2.0.0                           ║
║             (with Monitoring Support)                     ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

This script will deploy the CDN system to your server.

EOF

    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG MODE: Enabled"
        echo ""
    fi

    echo "Installation Directory: $INSTALL_DIR"
    echo "Source Directory: $SCRIPT_SOURCE_DIR"
    echo ""
    
    read -p "Press ENTER to continue with deployment..."
    echo ""
    
    # Run deployment steps
    preflight_checks
    create_directory_structure
    deploy_all_files
    
    echo ""
    validate_deployment
    
    echo ""
    create_symlinks
    
    echo ""
    generate_deployment_report
    
    # Final summary
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Deployment Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Installation Location: ${INSTALL_DIR}"
    echo "Deployment Report: ${INSTALL_DIR}/deployment-report.txt"
    echo ""
    
    # Check monitoring installation
    if [[ -f "${INSTALL_DIR}/cdn-monitoring-setup.sh" ]]; then
        log "✓ Core system + Monitoring system installed"
    else
        log "✓ Core system installed (monitoring not available)"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "  1. Review: cat ${INSTALL_DIR}/INSTALL.md"
    echo "  2. Run setup: sudo cdn-initial-setup"
    echo "  3. Create tenant: sudo cdn-tenant-manager create <name>"
    
    if [[ -f "${INSTALL_DIR}/cdn-monitoring-setup.sh" ]]; then
        echo "  4. Setup monitoring: sudo cdn-monitoring-setup"
    fi
    
    echo ""
    log "Thank you for using the Multi-Tenant CDN System!"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
