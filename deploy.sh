#!/bin/bash
# File: /opt/scripts/cdn/deploy.sh
# Purpose: Automated deployment script for Multi-Tenant CDN System
#          Creates directory structure, installs files, sets permissions, and validates installation

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
    mkdir -p "$INSTALL_DIR"/{helpers,includes,lib,templates}
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
    
    # Main orchestrator
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-initial-setup.sh" "${INSTALL_DIR}/cdn-initial-setup.sh" 755; then
        ((files_deployed++))
    else
        ((files_failed++))
    fi

    # Main tenant manager
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-tenant-manager.sh" "${INSTALL_DIR}/cdn-tenant-manager.sh" 755; then
        ((files_deployed++))
    else
        ((files_failed++))
    fi

    # Uninstaller
    if deploy_file "${SCRIPT_SOURCE_DIR}/cdn-uninstall.sh" "${INSTALL_DIR}/cdn-uninstall.sh" 755; then
        ((files_deployed++))
    else
        ((files_failed++))
    fi

    # Helper scripts
    for helper in cdn-tenant-helpers.sh cdn-autocommit.sh cdn-quota-functions.sh cdn-gitea-functions.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/helpers/${helper}" "${INSTALL_DIR}/helpers/${helper}" 755; then
            ((files_deployed++))
        else
            ((files_failed++))
        fi
    done
    
    # Include files
    for include in common.sh step1-domains.sh step2-sftp.sh step3-smtp.sh step4-letsencrypt.sh step5-paths.sh step6-gitea-admin.sh step7-summary.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/includes/${include}" "${INSTALL_DIR}/includes/${include}" 644; then
            ((files_deployed++))
        else
            ((files_failed++))
        fi
    done
    
    # Library files
    for lib in install-packages.sh install-nginx.sh install-gitea.sh install-helpers.sh; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/lib/${lib}" "${INSTALL_DIR}/lib/${lib}" 644; then
            ((files_deployed++))
        else
            ((files_failed++))
        fi
    done
    
    # Template files
    for template in config.env.template gitea-app.ini.template letsencrypt-setup.sh.template msmtprc.template; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/templates/${template}" "${INSTALL_DIR}/templates/${template}" 644; then
            ((files_deployed++))
        else
            ((files_failed++))
        fi
    done
    
    # Nginx templates
    for nginx_template in cdn.conf.template gitea.conf.template; do
        if deploy_file "${SCRIPT_SOURCE_DIR}/templates/nginx/${nginx_template}" "${INSTALL_DIR}/templates/nginx/${nginx_template}" 644; then
            ((files_deployed++))
        else
            ((files_failed++))
        fi
    done
    
    # Systemd template
    if deploy_file "${SCRIPT_SOURCE_DIR}/templates/systemd/cdn-autocommit@.service" "${INSTALL_DIR}/templates/systemd/cdn-autocommit@.service" 644; then
        ((files_deployed++))
    else
        ((files_failed++))
    fi
    
    # Documentation files
    for doc in INSTALL.md README.md QUICKSTART.md; do
        if [[ -f "${SCRIPT_SOURCE_DIR}/${doc}" ]]; then
            deploy_file "${SCRIPT_SOURCE_DIR}/${doc}" "${INSTALL_DIR}/${doc}" 644
            ((files_deployed++))
        fi
    done
    
    echo ""
    log "✓ Files deployed: $files_deployed"
    if [[ $files_failed -gt 0 ]]; then
        warn "Files failed: $files_failed"
    fi
}

# ==============================================================================
# VALIDATION
# ==============================================================================

validate_deployment() {
    info "Validating deployment..."
 
    local validation_errors=0

    # Check main orchestrator
    if [[ ! -x "${INSTALL_DIR}/cdn-initial-setup.sh" ]]; then
        error "Main orchestrator not executable: cdn-initial-setup.sh"
        ((validation_errors++))
    else
        log "✓ Main orchestrator is executable"
    fi

    # Check tenant manager (NEW)
    if [[ ! -x "${INSTALL_DIR}/cdn-tenant-manager.sh" ]]; then
        error "Tenant manager not executable: cdn-tenant-manager.sh"
        ((validation_errors++))
    else
        log "✓ Tenant manager is executable"
    fi

    # Check uninstaller (NEW)
    if [[ ! -x "${INSTALL_DIR}/cdn-uninstall.sh" ]]; then
        error "Uninstaller not executable: cdn-uninstall.sh"
        ((validation_errors++))
    else
        log "✓ Uninstaller is executable"
    fi

    # Check helper scripts
    local helpers=(cdn-tenant-helpers.sh cdn-autocommit.sh cdn-quota-functions.sh cdn-gitea-functions.sh)
    for helper in "${helpers[@]}"; do
        if [[ ! -x "${INSTALL_DIR}/helpers/${helper}" ]]; then
            error "Helper script not executable: $helper"
            ((validation_errors++))
        fi
    done
    log "✓ Helper scripts are executable"
    
    # Check include files
    local includes=(common.sh step1-domains.sh step2-sftp.sh step3-smtp.sh step4-letsencrypt.sh step5-paths.sh step6-gitea-admin.sh step7-summary.sh)
    for include in "${includes[@]}"; do
        if [[ ! -f "${INSTALL_DIR}/includes/${include}" ]]; then
            error "Include file missing: $include"
            ((validation_errors++))
        fi
    done
    log "✓ Include files present"
    
    # Check library files
    local libs=(install-packages.sh install-nginx.sh install-gitea.sh install-helpers.sh)
    for lib in "${libs[@]}"; do
        if [[ ! -f "${INSTALL_DIR}/lib/${lib}" ]]; then
            error "Library file missing: $lib"
            ((validation_errors++))
        fi
    done
    log "✓ Library files present"
    
    # Check templates
    local templates=(config.env.template gitea-app.ini.template letsencrypt-setup.sh.template msmtprc.template)
    for template in "${templates[@]}"; do
        if [[ ! -f "${INSTALL_DIR}/templates/${template}" ]]; then
            error "Template file missing: $template"
            ((validation_errors++))
        fi
    done
    log "✓ Template files present"
    
    # Check nginx templates
    if [[ ! -f "${INSTALL_DIR}/templates/nginx/cdn.conf.template" ]] || \
       [[ ! -f "${INSTALL_DIR}/templates/nginx/gitea.conf.template" ]]; then
        error "Nginx template files missing"
        ((validation_errors++))
    else
        log "✓ Nginx templates present"
    fi
    
    # Check systemd template
    if [[ ! -f "${INSTALL_DIR}/templates/systemd/cdn-autocommit@.service" ]]; then
        error "Systemd template file missing"
        ((validation_errors++))
    else
        log "✓ Systemd template present"
    fi
    
    # Syntax check on main scripts
    if ! bash -n "${INSTALL_DIR}/cdn-initial-setup.sh" 2>/dev/null; then
        error "Syntax error in main orchestrator"
        ((validation_errors++))
    else
        log "✓ Main orchestrator syntax valid"
    fi
    
    # Syntax check on tenant manager (NEW)
    if ! bash -n "${INSTALL_DIR}/cdn-tenant-manager.sh" 2>/dev/null; then
        error "Syntax error in tenant manager"
        ((validation_errors++))
    else
        log "✓ Tenant manager syntax valid"
    fi
    
    echo ""
    
    if [[ $validation_errors -eq 0 ]]; then
        log "✓ Validation passed - deployment is complete and valid"
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
    
    cat > "$report_file" << EOFREPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CDN System Deployment Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Deployment Date: $(date '+%Y-%m-%d %H:%M:%S')
Installation Directory: ${INSTALL_DIR}
Deployed By: $(whoami)
Server: $(hostname)

Directory Structure:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${INSTALL_DIR}/
├── cdn-initial-setup.sh          # Main orchestrator
├── cdn-tenant-manager.sh         # Tenant management (NEW)
├── deploy.sh                      # This deployment script
├── INSTALL.md                     # Installation guide
├── README.md                      # Documentation
├── QUICKSTART.md                  # Quick start guide
├── deployment-report.txt          # This report
├── helpers/                       # Runtime helper scripts
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
├── lib/                          # Installation libraries
│   ├── install-packages.sh
│   ├── install-nginx.sh
│   ├── install-gitea.sh
│   └── install-helpers.sh
└── templates/                    # Configuration templates
    ├── config.env.template
    ├── gitea-app.ini.template
    ├── letsencrypt-setup.sh.template
    ├── msmtprc.template
    ├── nginx/
    │   ├── cdn.conf.template
    │   └── gitea.conf.template
    └── systemd/
        └── cdn-autocommit@.service

Symbolic Links Created:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/usr/local/bin/cdn-initial-setup → ${INSTALL_DIR}/cdn-initial-setup.sh
/usr/local/bin/cdn-tenant-manager → ${INSTALL_DIR}/cdn-tenant-manager.sh (NEW)
/usr/local/bin/cdn-deploy → ${INSTALL_DIR}/deploy.sh

File Permissions:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Executable (755):
  - cdn-initial-setup.sh
  - cdn-tenant-manager.sh (NEW)
  - deploy.sh
  - helpers/*.sh

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

Additional Information:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- All scripts include comprehensive error handling
- DEBUG mode available: DEBUG=true sudo cdn-initial-setup
- Configuration will be stored in: /etc/cdn/
- Helper scripts will be installed to: /usr/local/bin/
- Tenant manager coordinates all tenant operations (NEW)

For support and documentation, see:
${INSTALL_DIR}/INSTALL.md
${INSTALL_DIR}/README.md
${INSTALL_DIR}/QUICKSTART.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Deployment completed successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOFREPORT
    
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
    echo "Next Steps:"
    echo "  1. Review: cat ${INSTALL_DIR}/INSTALL.md"
    echo "  2. Run setup: sudo cdn-initial-setup"
    echo "  3. Create tenant: sudo cdn-tenant-manager create <name>"
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
