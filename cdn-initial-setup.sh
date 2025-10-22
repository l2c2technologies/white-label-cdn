#!/bin/bash
# File: /opt/scripts/cdn/cdn-initial-setup.sh
# Purpose: Main orchestrator for Multi-Tenant CDN Initial Setup
#          Coordinates all setup steps and manages installation flow

set -eE

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# DEBUG mode: set to "true" for verbose error reporting with line numbers
# Default: true (verbose)
DEBUG="${DEBUG:-true}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration destination
CONFIG_DIR="/etc/cdn"
CONFIG_FILE="${CONFIG_DIR}/config.env"

# ==============================================================================
# ERROR HANDLING
# ==============================================================================

error_handler() {
    local line_no=$1
    local bash_lineno=$2
    local last_command=$3
    local func_stack=($4)
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "ERROR OCCURRED" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "Command: ${last_command}" >&2
    echo "Exit Code: $?" >&2
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "" >&2
        echo "Debug Information:" >&2
        echo "  File: ${BASH_SOURCE[1]}" >&2
        echo "  Line: ${line_no}" >&2
        echo "  Function: ${FUNCNAME[1]:-main}" >&2
        
        if [[ ${#BASH_SOURCE[@]} -gt 2 ]]; then
            echo "" >&2
            echo "Call Stack:" >&2
            local i=0
            while [[ $i -lt ${#FUNCNAME[@]} ]]; do
                if [[ $i -gt 0 ]]; then
                    echo "  [$i] ${FUNCNAME[$i]} (${BASH_SOURCE[$i+1]}:${BASH_LINENO[$i]})" >&2
                fi
                ((i++))
            done
        fi
    else
        echo "  Source: ${BASH_SOURCE[1]}" >&2
    fi
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    exit 1
}

trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND" "${FUNCNAME[*]}"' ERR

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root" >&2
    echo "Please run: sudo $0" >&2
    exit 1
fi

# Check required directories exist
if [[ ! -d "${SCRIPT_DIR}/includes" ]]; then
    echo "ERROR: includes directory not found at ${SCRIPT_DIR}/includes" >&2
    exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
    echo "ERROR: lib directory not found at ${SCRIPT_DIR}/lib" >&2
    exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/templates" ]]; then
    echo "ERROR: templates directory not found at ${SCRIPT_DIR}/templates" >&2
    exit 1
fi

# ==============================================================================
# LOAD COMMON FUNCTIONS
# ==============================================================================

source "${SCRIPT_DIR}/includes/common.sh" || {
    echo "ERROR: Failed to source common.sh" >&2
    exit 1
}

# ==============================================================================
# BANNER
# ==============================================================================

clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║      Multi-Tenant CDN with Auto-Commit & Versioning       ║
║                  Initial Setup Wizard                     ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

This wizard will configure your CDN system.
You'll need to provide:
  • Domain names for CDN and Gitea
  • SMTP settings for email alerts (via msmtp)
  • Let's Encrypt email for SSL certificates
  • Basic configuration options

EOF

if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG MODE: Enabled (verbose error reporting)"
    echo ""
fi

echo "Press ENTER to continue..."
read -r

# ==============================================================================
# CONFIGURATION WIZARD STEPS
# ==============================================================================

log "Starting configuration wizard..."
echo ""

# Step 1: Domain Configuration
source "${SCRIPT_DIR}/includes/step1-domains.sh"

# Step 2: SFTP Port Configuration
source "${SCRIPT_DIR}/includes/step2-sftp.sh"

# Step 3: SMTP Configuration
source "${SCRIPT_DIR}/includes/step3-smtp.sh"

# Step 4: Let's Encrypt Configuration
source "${SCRIPT_DIR}/includes/step4-letsencrypt.sh"

# Step 5: System Paths
source "${SCRIPT_DIR}/includes/step5-paths.sh"

# Step 6: Gitea Administrator
source "${SCRIPT_DIR}/includes/step6-gitea-admin.sh"

# Step 7: Summary and Confirmation
source "${SCRIPT_DIR}/includes/step7-summary.sh"

# ==============================================================================
# SAVE CONFIGURATION (FIRST!)
# ==============================================================================

log "Saving configuration to ${CONFIG_FILE}..."
save_configuration

log "✓ Configuration saved successfully"
echo ""

# ==============================================================================
# INSTALLATION PHASE
# ==============================================================================

log "Starting installation phase..."
echo ""

# Install system packages
source "${SCRIPT_DIR}/lib/install-packages.sh"

# Install and configure Nginx
source "${SCRIPT_DIR}/lib/install-nginx.sh"

# Install and configure Gitea
source "${SCRIPT_DIR}/lib/install-gitea.sh"

# Install helper scripts
source "${SCRIPT_DIR}/lib/install-helpers.sh"

# ==============================================================================
# COMPLETION
# ==============================================================================

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Initial Setup Complete!"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cat << EOF
Configuration Summary:
  • Configuration file: ${CONFIG_FILE}
  • CDN Domain: ${CDN_DOMAIN}
  • Gitea Domain: ${GITEA_DOMAIN}
  • SFTP Port: ${SFTP_PORT}
  • Base Directory: ${BASE_DIR}

Next Steps:

1. Configure DNS (CRITICAL):
   ${CDN_DOMAIN}    → $(hostname -I | awk '{print $1}')
   ${GITEA_DOMAIN}  → $(hostname -I | awk '{print $1}')

2. Wait for DNS propagation (test with: dig ${CDN_DOMAIN})

3. Setup Let's Encrypt SSL certificates:
   sudo cdn-setup-letsencrypt

4. Create your first tenant:
   sudo cdn-tenant-manager create <tenant-name>

Gitea Access:
  • Web interface: https://${GITEA_DOMAIN}
  • Admin user: ${GITEA_ADMIN_USER}
  • Admin email: ${GITEA_ADMIN_EMAIL}

SFTP Access for Tenants:
  • Connection: sftp -P ${SFTP_PORT} cdn_<tenant>@${CDN_DOMAIN}
  • Port ${SFTP_PORT} must be accessible from internet

EOF

log "Setup completed successfully!"
log "Review configuration at: ${CONFIG_FILE}"
