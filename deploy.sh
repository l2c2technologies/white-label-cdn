#!/bin/bash
# File: /opt/scripts/cdn/deploy.sh
# Purpose: Automated deployment script for Multi-Tenant CDN System
#          Creates directory structure, installs files, corrects paths, and validates installation
# Version: 2.1.0 - Updated to use /opt/scripts/cdn/* paths internally

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
# PATH CORRECTION FUNCTION
# ==============================================================================

correct_paths_in_file() {
    local file_path="$1"
    
    # Skip if file doesn't exist
    [[ ! -f "$file_path" ]] && return 0
    
    # Correct common path references to use /opt/scripts/cdn structure
    sed -i \
        -e 's|/usr/local/bin/cdn-quota-functions|/opt/scripts/cdn/helpers/cdn-quota-functions.sh|g' \
        -e 's|/usr/local/bin/cdn-tenant-helpers|/opt/scripts/cdn/helpers/cdn-tenant-helpers.sh|g' \
        -e 's|/usr/local/bin/cdn-gitea-functions|/opt/scripts/cdn/helpers/cdn-gitea-functions.sh|g' \
        -e 's|/usr/local/bin/cdn-autocommit|/opt/scripts/cdn/helpers/cdn-autocommit.sh|g' \
        -e 's|/usr/local/bin/cdn-setup-letsencrypt|/opt/scripts/cdn/helpers/cdn-setup-letsencrypt.sh|g' \
        -e 's|/usr/local/bin/cdn-tenant-manager|/opt/scripts/cdn/cdn-tenant-manager.sh|g' \
        -e 's|/usr/local/bin/cdn-health-monitor|/opt/scripts/cdn/monitoring/cdn-health-monitor.sh|g' \
        -e 's|/usr/local/bin/cdn-monitoring-control|/opt/scripts/cdn/monitoring/cdn-monitoring-control.sh|g' \
        -e 's|/usr/local/bin/cdn-quota-monitor-realtime|/opt/scripts/cdn/monitoring/cdn-quota-monitor-realtime.sh|g' \
        "$file_path"
    
    [[ "$DEBUG" == "true" ]] && log "  Path corrections applied to: $(basename $file_path)"
}

# ==============================================================================
# FILE DEPLOYMENT
# ==============================================================================

deploy_file() {
    local source_file=$1
    local dest_file=$2
    local permissions=${3:-644}
    local apply_path_correction=${4:-false}
    
    if [[ ! -f "$source_file" ]]; then
        warn "Source file not found: $source_file (skipping)"
        return 1
    fi
    
    cp "$source_file" "$dest_file"
    chmod "$permissions" "$dest_file"
    
    # Apply path corrections if requested
    if [[ "$apply_path_correction" == "true" ]]; then
        correct_paths_in_file "$dest_file"
    fi
    
    if [[ "$DEBUG" == "true" ]]; then
        log "  Deployed: $(basename $dest_file) (mode: $permissions)"
    fi
    
    return 0
}

deploy_all_files() {
    info "Deploying files with path corrections..."
    
    local files_deployed=0
    local files_failed=0
    
    # ===== MAIN SCRIPTS (with path correction) =====
    
    log "Deploying main scripts..."
    
    # Main orchestrator
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-initial-setup.sh" "${INSTALL_DIR}/cdn-initial-setup.sh" 755 true; then
        files_deployed=$((files_deployed + 1))
    else
        files_failed=$((files_failed + 1))
    fi

    # Main tenant manager
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-tenant-manager.sh" "${INSTALL_DIR}/cdn-tenant-manager.sh" 755 true; then
        files_deployed=$((files_deployed + 1))
    else
        files_failed=$((files_failed + 1))
    fi

    # Uninstaller
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-uninstall.sh" "${INSTALL_DIR}/cdn-uninstall.sh" 755 true; then
        files_deployed=$((files_deployed + 1))
    else
        files_failed=$((files_failed + 1))
    fi

    # Monitoring setup script
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-monitoring-setup.sh" "${INSTALL_DIR}/cdn-monitoring-setup.sh" 755 true; then
        files_deployed=$((files_deployed + 1))
        log "✓ Deployed monitoring setup script"
    else
        files_failed=$((files_failed + 1))
        warn "Monitoring setup script not found (optional)"
    fi

    # ===== HELPER SCRIPTS (with path correction) =====
    
    log "Deploying helper scripts..."
    for helper in cdn-tenant-helpers.sh cdn-autocommit.sh cdn-quota-functions.sh cdn-gitea-functions.sh cdn-setup-letsencrypt.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/helpers/${helper}" "${INSTALL_DIR}/helpers/${helper}" 755 true; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # ===== MONITORING SCRIPTS (with path correction) =====
    
    log "Deploying monitoring system scripts..."
    local monitoring_scripts=(
        "cdn-health-monitor.sh"
        "cdn-monitoring-control.sh"
        "cdn-quota-monitor-realtime.sh"
    )
    
    for monitor_script in "${monitoring_scripts[@]}"; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/monitoring/${monitor_script}" \
                      "${INSTALL_DIR}/monitoring/${monitor_script}" 755 true; then
            files_deployed=$((files_deployed + 1))
            log "✓ Deployed monitoring/${monitor_script}"
        else
            files_failed=$((files_failed + 1))
            warn "Monitoring script not found: ${monitor_script} (optional)"
        fi
    done
    
    # ===== INCLUDE FILES (no path correction needed) =====
    
    log "Deploying include files..."
    for include in common.sh step1-domains.sh step2-sftp.sh step3-smtp.sh \
                   step4-letsencrypt.sh step5-paths.sh step6-gitea-admin.sh step7-summary.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/includes/${include}" "${INSTALL_DIR}/includes/${include}" 644 false; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # ===== LIBRARY FILES (with path correction) =====
    
    log "Deploying library files..."
    for lib in install-packages.sh install-nginx.sh install-gitea.sh install-helpers.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/lib/${lib}" "${INSTALL_DIR}/lib/${lib}" 644 true; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # ===== TEMPLATE FILES (with path correction for systemd) =====
    
    log "Deploying template files..."
    for template in config.env.template gitea-app.ini.template \
                    msmtprc.template; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/templates/${template}" \
                      "${INSTALL_DIR}/templates/${template}" 644 false; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # Nginx templates
    log "Deploying Nginx templates..."
    for nginx_template in cdn.conf.template gitea.conf.template; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/templates/nginx/${nginx_template}" \
                      "${INSTALL_DIR}/templates/nginx/${nginx_template}" 644 false; then
            files_deployed=$((files_deployed + 1))
        else
            files_failed=$((files_failed + 1))
        fi
    done
    
    # Systemd templates (with path correction)
    log "Deploying systemd templates..."
    
    # Autocommit template
    if deploy_file "${SCRIPT_SOURCE_DIR}/templates/systemd/cdn-autocommit@.service" \
                  "${INSTALL_DIR}/templates/systemd/cdn-autocommit@.service" 644 true; then
        files_deployed=$((files_deployed + 1))
    else
        files_failed=$((files_failed + 1))
    fi
    
    # Quota monitor template
    if deploy_file "${SCRIPT_SOURCE_DIR}/templates/systemd/cdn-quota-monitor@.service" \
                  "${INSTALL_DIR}/templates/systemd/cdn-quota-monitor@.service" 644 true; then
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
            deploy_file "${SCRIPT_SOURCE_DIR}/${doc}" "${INSTALL_DIR}/${doc}" 644 false
            files_deployed=$((files_deployed + 1))
        else
            warn "Documentation file not found: ${doc} (optional)"
        fi
    done
    
    # ===== DEPLOYMENT SCRIPT ITSELF =====
    
    # Copy deploy.sh itself to installation directory
    if [[ -f "${SCRIPT_SOURCE_DIR}/deploy.sh" ]]; then
        deploy_file "${SCRIPT_SOURCE_DIR}/deploy.sh" "${INSTALL_DIR}/deploy.sh" 755 false
        files_deployed=$((files_deployed + 1))
    fi
    
    echo ""
    log "✓ Files deployed: $files_deployed"
    if [[ $files_failed -gt 0 ]]; then
        warn "Files failed/skipped: $files_failed"
    fi
    log "✓ Path corrections applied to all scripts"
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

    # Check monitoring setup
    if [[ -x "${INSTALL_DIR}/cdn-monitoring-setup.sh" ]]; then
        log "✓ cdn-monitoring-setup.sh is executable"
    else
        warn "cdn-monitoring-setup.sh not installed (monitoring features unavailable)"
    fi

    # ===== CHECK HELPER SCRIPTS =====
    
    log "Validating helper scripts..."
    local helpers=(cdn-tenant-helpers.sh cdn-autocommit.sh cdn-quota-functions.sh cdn-gitea-functions.sh cdn-setup-letsencrypt.sh)
    for helper in "${helpers[@]}"; do
        if [[ -x "${INSTALL_DIR}/helpers/${helper}" ]]; then
            log "✓ ${helper} is executable"
        else
            error "Helper script not executable: $helper"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # ===== CHECK MONITORING SCRIPTS =====
    
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
    
    # ===== VALIDATE PATH CORRECTIONS =====
    
    log "Validating path corrections..."
    
    # Check that /usr/local/bin references were replaced
    local bad_refs=0
    
    # Check main scripts
    for script in "${INSTALL_DIR}/cdn-tenant-manager.sh" \
                  "${INSTALL_DIR}/cdn-monitoring-setup.sh" \
                  "${INSTALL_DIR}/monitoring/cdn-health-monitor.sh" \
                  "${INSTALL_DIR}/monitoring/cdn-quota-monitor-realtime.sh"; do
        if [[ -f "$script" ]]; then
            if grep -q "/usr/local/bin/cdn-quota-functions" "$script" 2>/dev/null; then
                error "Found uncorrected path in: $(basename $script)"
                error "  Still references /usr/local/bin/cdn-quota-functions"
                ((bad_refs++))
                ((validation_errors++))
            fi
            
            if grep -q "/usr/local/bin/cdn-tenant-helpers" "$script" 2>/dev/null; then
                error "Found uncorrected path in: $(basename $script)"
                error "  Still references /usr/local/bin/cdn-tenant-helpers"
                ((bad_refs++))
                ((validation_errors++))
            fi
        fi
    done
    
    # Check systemd templates
    for template in "${INSTALL_DIR}/templates/systemd/cdn-autocommit@.service" \
                    "${INSTALL_DIR}/templates/systemd/cdn-quota-monitor@.service"; do
        if [[ -f "$template" ]]; then
            if grep -q "/usr/local/bin/cdn-autocommit" "$template" 2>/dev/null; then
                error "Found uncorrected path in systemd template: $(basename $template)"
                ((bad_refs++))
                ((validation_errors++))
            fi
        fi
    done
    
    if [[ $bad_refs -eq 0 ]]; then
        log "✓ All paths correctly reference /opt/scripts/cdn/*"
    else
        error "Found $bad_refs uncorrected path reference(s)"
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
    local templates=(config.env.template gitea-app.ini.template msmtprc.template)
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
    if [[ -f "${INSTALL_DIR}/templates/systemd/cdn-autocommit@.service" ]]; then
        log "✓ Autocommit systemd template present"
    else
        error "Autocommit systemd template missing"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [[ -f "${INSTALL_DIR}/templates/systemd/cdn-quota-monitor@.service" ]]; then
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
        log "✓ All scripts use /opt/scripts/cdn/* paths internally"
        
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
# NO SYMLINKS - ALL REFERENCES USE /opt/scripts/cdn/*
# ==============================================================================

# Note: We do NOT create symlinks in /usr/local/bin/
# All scripts are executed directly from /opt/scripts/cdn/

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
Version: 2.1.0 (paths use /opt/scripts/cdn/* internally)

IMPORTANT: Path Structure
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

All scripts use /opt/scripts/cdn/* paths:
  • Helper scripts:     /opt/scripts/cdn/helpers/*.sh
  • Monitoring scripts: /opt/scripts/cdn/monitoring/*.sh
  • Main scripts:       /opt/scripts/cdn/*.sh

No symlinks are created. All commands use full paths:
  • sudo /opt/scripts/cdn/cdn-tenant-manager.sh
  • sudo /opt/scripts/cdn/cdn-initial-setup.sh
  • sudo /opt/scripts/cdn/cdn-monitoring-setup.sh

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
│   ├── cdn-setup-letsencrypt.sh
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
    ├── msmtprc.template
    ├── nginx/
    │   ├── cdn.conf.template
    │   └── gitea.conf.template
    └── systemd/
        ├── cdn-autocommit@.service
        └── cdn-quota-monitor@.service

Path Correction Details:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

All references to /usr/local/bin/* have been replaced with:
  /usr/local/bin/cdn-quota-functions 
    → /opt/scripts/cdn/helpers/cdn-quota-functions.sh
  
  /usr/local/bin/cdn-tenant-helpers
    → /opt/scripts/cdn/helpers/cdn-tenant-helpers.sh
  
  /usr/local/bin/cdn-gitea-functions
    → /opt/scripts/cdn/helpers/cdn-gitea-functions.sh
  
  /usr/local/bin/cdn-autocommit
    → /opt/scripts/cdn/helpers/cdn-autocommit.sh

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

3. Configure DNS for your domains

4. Setup SSL certificates:
   sudo ${INSTALL_DIR}/helpers/cdn-setup-letsencrypt.sh

5. Create your first tenant:
   sudo ${INSTALL_DIR}/cdn-tenant-manager.sh create <tenant-name>
   
   Example:
   sudo ${INSTALL_DIR}/cdn-tenant-manager.sh create acmecorp admin@acme.com 500

6. (Optional) Setup monitoring system:
   sudo ${INSTALL_DIR}/cdn-monitoring-setup.sh

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
  • Uses /opt/scripts/cdn/* paths for consistency

Additional Information:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- All scripts include comprehensive error handling
- DEBUG mode available: DEBUG=true sudo cdn-initial-setup
- Configuration will be stored in: /etc/cdn/
- Helper scripts are in: ${INSTALL_DIR}/helpers/
- Monitoring scripts are in: ${INSTALL_DIR}/monitoring/
- User commands via symlinks: /usr/local/bin/cdn-*
- Scripts internally use: /opt/scripts/cdn/* paths

Installation Status:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Core System: Installed ✓
Monitoring System: ${monitoring_status}
Monitoring Scripts: ${monitoring_scripts_installed}/3
Path Structure: /opt/scripts/cdn/* (corrected) ✓

For support and documentation, see:
${INSTALL_DIR}/INSTALL.md
${INSTALL_DIR}/README.md
${INSTALL_DIR}/QUICKSTART.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Deployment completed successfully!
All internal paths use /opt/scripts/cdn/* structure.
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
║                   Version 2.1.0                           ║
║        (With /opt/scripts/cdn/* Path Structure)           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

This script will deploy the CDN system with corrected paths.

All scripts will internally reference /opt/scripts/cdn/* paths.
User-facing commands available via /usr/local/bin/cdn-* symlinks.

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
    log "✓ All scripts use /opt/scripts/cdn/* paths internally"
    log "✓ User commands available via /usr/local/bin/cdn-* symlinks"
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
