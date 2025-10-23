#!/bin/bash
# File: /opt/scripts/cdn/lib/install-helpers.sh
# Purpose: Install helper scripts and set up management tools
#          Deploys tenant management, quota functions, Gitea integration, autocommit scripts, and SSL setup

install_helper_scripts() {
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Installing Helper Scripts"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Ensure target directory exists
    mkdir -p /usr/local/bin
    
    # Install tenant manager (MAIN MANAGEMENT TOOL)
    log "Installing tenant manager..."
    if [[ -f "${SCRIPT_DIR}/cdn-tenant-manager.sh" ]]; then
        cp "${SCRIPT_DIR}/cdn-tenant-manager.sh" /usr/local/bin/cdn-tenant-manager
        chmod 755 /usr/local/bin/cdn-tenant-manager
        log "✓ Installed: /usr/local/bin/cdn-tenant-manager"
    else
        error "Tenant manager not found: ${SCRIPT_DIR}/cdn-tenant-manager.sh"
        return 1
    fi
    
    # Install tenant helpers
    log "Installing tenant helper functions..."
    if [[ -f "${SCRIPT_DIR}/helpers/cdn-tenant-helpers.sh" ]]; then
        cp "${SCRIPT_DIR}/helpers/cdn-tenant-helpers.sh" /usr/local/bin/cdn-tenant-helpers
        chmod 755 /usr/local/bin/cdn-tenant-helpers
        log "✓ Installed: /usr/local/bin/cdn-tenant-helpers"
    else
        error "Tenant helpers not found"
        return 1
    fi
    
    # Install autocommit script
    log "Installing autocommit script..."
    if [[ -f "${SCRIPT_DIR}/helpers/cdn-autocommit.sh" ]]; then
        cp "${SCRIPT_DIR}/helpers/cdn-autocommit.sh" /usr/local/bin/cdn-autocommit
        chmod 755 /usr/local/bin/cdn-autocommit
        log "✓ Installed: /usr/local/bin/cdn-autocommit"
    else
        error "Autocommit script not found"
        return 1
    fi
    
    # Install quota functions
    log "Installing quota management functions..."
    if [[ -f "${SCRIPT_DIR}/helpers/cdn-quota-functions.sh" ]]; then
        cp "${SCRIPT_DIR}/helpers/cdn-quota-functions.sh" /usr/local/bin/cdn-quota-functions
        chmod 755 /usr/local/bin/cdn-quota-functions
        log "✓ Installed: /usr/local/bin/cdn-quota-functions"
    else
        warn "Quota functions not found (optional)"
    fi
    
    # Install Gitea functions
    log "Installing Gitea integration functions..."
    if [[ -f "${SCRIPT_DIR}/helpers/cdn-gitea-functions.sh" ]]; then
        cp "${SCRIPT_DIR}/helpers/cdn-gitea-functions.sh" /usr/local/bin/cdn-gitea-functions
        chmod 755 /usr/local/bin/cdn-gitea-functions
        log "✓ Installed: /usr/local/bin/cdn-gitea-functions"
    else
        warn "Gitea functions not found (optional)"
    fi
    
    # Install systemd service template
    log "Installing systemd service template..."
    if [[ -f "${SCRIPT_DIR}/templates/systemd/cdn-autocommit@.service" ]]; then
        cp "${SCRIPT_DIR}/templates/systemd/cdn-autocommit@.service" /etc/systemd/system/
        chmod 644 /etc/systemd/system/cdn-autocommit@.service
        systemctl daemon-reload
        log "✓ Installed: /etc/systemd/system/cdn-autocommit@.service"
    else
        error "Systemd service template not found"
        return 1
    fi

    # Install uninstaller
    log "Installing uninstaller..."
    if [[ -f "${SCRIPT_DIR}/cdn-uninstall.sh" ]]; then
        cp "${SCRIPT_DIR}/cdn-uninstall.sh" /usr/local/bin/cdn-uninstall
        chmod 755 /usr/local/bin/cdn-uninstall
        log "✓ Installed: /usr/local/bin/cdn-uninstall"
    else
        warn "Uninstaller not found (optional)"
    fi

    # Verify installations
    log "Verifying helper script installations..."
    local verification_failed=0
    
    # Check tenant manager
    if [[ -x /usr/local/bin/cdn-tenant-manager ]]; then
        log "✓ cdn-tenant-manager is executable"
    else
        error "cdn-tenant-manager installation failed"
        ((verification_failed++))
    fi
    
    # Check tenant helpers
    if [[ -x /usr/local/bin/cdn-tenant-helpers ]]; then
        log "✓ cdn-tenant-helpers is executable"
    else
        error "cdn-tenant-helpers installation failed"
        ((verification_failed++))
    fi
    
    # Check autocommit
    if [[ -x /usr/local/bin/cdn-autocommit ]]; then
        log "✓ cdn-autocommit is executable"
    else
        error "cdn-autocommit installation failed"
        ((verification_failed++))
    fi
    
    # Check quota functions
    if [[ -x /usr/local/bin/cdn-quota-functions ]]; then
        log "✓ cdn-quota-functions is executable"
    else
        warn "cdn-quota-functions not installed (optional)"
    fi
    
    # Check Gitea functions
    if [[ -x /usr/local/bin/cdn-gitea-functions ]]; then
        log "✓ cdn-gitea-functions is executable"
    else
        warn "cdn-gitea-functions not installed (optional)"
    fi
    
    # Check systemd service
    if [[ -f /etc/systemd/system/cdn-autocommit@.service ]]; then
        log "✓ Systemd service template installed"
    else
        error "Systemd service template installation failed"
        ((verification_failed++))
    fi
    
    # Check Let's Encrypt setup script
    if [[ -x /usr/local/bin/cdn-setup-letsencrypt ]]; then
        log "✓ cdn-setup-letsencrypt is executable"
    else
        warn "cdn-setup-letsencrypt not installed (optional)"
    fi
    
    if [[ $verification_failed -gt 0 ]]; then
        error "Helper script installation verification failed"
        return 1
    fi
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "✓ Helper Scripts Installation Complete"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    log "Available commands:"
    log "  • cdn-tenant-manager     - Main tenant management tool"
    log "  • cdn-tenant-helpers     - Tenant configuration functions"
    log "  • cdn-quota-functions    - Quota management"
    log "  • cdn-gitea-functions    - Gitea integration"
    log "  • cdn-autocommit         - Auto-commit service (used by systemd)"
    log "  • cdn-setup-letsencrypt  - SSL certificate setup and management"
    log "  • cdn-uninstall          - Complete system removal"
    echo ""
    
    log "Quick start:"
    log "  sudo cdn-tenant-manager create <tenant-name>"
    echo ""
    
    log "SSL setup (after DNS configuration):"
    log "  sudo cdn-setup-letsencrypt"
    echo ""
    
    return 0
}

# Auto-execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_helper_scripts
fi
