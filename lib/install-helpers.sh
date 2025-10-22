#!/bin/bash
# File: /opt/scripts/cdn/lib/install-helpers.sh
# Purpose: Install helper scripts and set up management tools
#          Deploys tenant management, quota functions, Gitea integration, and autocommit scripts

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
    log "  • cdn-uninstall          - Complete system removal"
    echo ""
    
    log "Quick start:"
    log "  sudo cdn-tenant-manager create <tenant-name>"
    echo ""
    
    return 0
}

# Auto-execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_helper_scripts
fi
```

---

## 3. Updated Directory Structure

After deployment, the structure will be:
```
/opt/scripts/cdn/
├── cdn-initial-setup.sh              # Main orchestrator
├── cdn-tenant-manager.sh             # Tenant management 
├── cdn-uninstall.sh                  # System uninstaller 
├── deploy.sh                          # Deployment script
├── helpers/
│   ├── cdn-autocommit.sh
│   ├── cdn-gitea-functions.sh
│   ├── cdn-quota-functions.sh
│   └── cdn-tenant-helpers.sh
├── includes/
│   ├── common.sh
│   ├── step1-domains.sh
│   ├── step2-sftp.sh
│   ├── step3-smtp.sh
│   ├── step4-letsencrypt.sh
│   ├── step5-paths.sh
│   ├── step6-gitea-admin.sh
│   └── step7-summary.sh
├── INSTALL.md
├── lib/
│   ├── install-gitea.sh
│   ├── install-helpers.sh
│   ├── install-nginx.sh
│   └── install-packages.sh
├── QUICKSTART.md
├── README.md
└── templates/
    ├── config.env.template
    ├── gitea-app.ini.template
    ├── letsencrypt-setup.sh.template
    ├── msmtprc.template
    ├── nginx/
    │   ├── cdn.conf.template
    │   └── gitea.conf.template
    └── systemd/
        └── cdn-autocommit@.service

/usr/local/bin/ (after installation)
├── cdn-autocommit
├── cdn-gitea-functions
├── cdn-initial-setup → /opt/scripts/cdn/cdn-initial-setup.sh
├── cdn-quota-functions
├── cdn-setup-letsencrypt
├── cdn-tenant-helpers
└── cdn-tenant-manager → /opt/scripts/cdn/cdn-tenant-manager.sh
