#!/bin/bash
# File: /opt/scripts/cdn/includes/step7-summary.sh
# Purpose: Display configuration summary and get user confirmation
#          Final checkpoint before proceeding with installation

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Configuration Summary"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cat << EOF
CDN Domain:              ${CDN_DOMAIN}
Gitea Domain:            ${GITEA_DOMAIN}
SFTP Port:               ${SFTP_PORT}
Base Directory:          ${BASE_DIR}
Cache Size:              ${CACHE_SIZE}
Backup Retention:        ${BACKUP_RETENTION} days

Gitea Admin:             ${GITEA_ADMIN_USER}
Gitea Email:             ${GITEA_ADMIN_EMAIL}

SMTP Enabled:            ${SMTP_ENABLED}
EOF

if [[ "$SMTP_ENABLED" == "true" ]]; then
    cat << EOF
SMTP Host:               ${SMTP_HOST}
SMTP Port:               ${SMTP_PORT}
SMTP User:               ${SMTP_USER}
From Email:              ${SMTP_FROM}
Alert Email:             ${ALERT_EMAIL}
Use TLS:                 ${USE_TLS}
EOF
fi

if [[ -n "$LE_EMAIL" ]]; then
    echo "Let's Encrypt Email:     ${LE_EMAIL}"
else
    echo "Let's Encrypt Email:     (none - no renewal notices)"
fi

echo ""
read -p "Proceed with installation? (yes/no): " PROCEED

if [[ "$PROCEED" != "yes" ]]; then
    log "Installation cancelled by user"
    exit 0
fi

log "✓ Configuration confirmed, proceeding with installation..."
