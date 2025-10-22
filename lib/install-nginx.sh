#!/bin/bash
# File: /opt/scripts/cdn/lib/install-nginx.sh
# Purpose: Configure Nginx for CDN and Gitea reverse proxy
#          Creates virtual hosts from templates and enables sites

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Configuring Nginx"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log "Creating Nginx configuration for CDN..."
process_template "${SCRIPT_DIR}/templates/nginx/cdn.conf.template" "/etc/nginx/sites-available/cdn"

log "Creating Nginx configuration for Gitea..."
process_template "${SCRIPT_DIR}/templates/nginx/gitea.conf.template" "/etc/nginx/sites-available/gitea"

# Enable sites
log "Enabling Nginx sites..."
ln -sf /etc/nginx/sites-available/cdn /etc/nginx/sites-enabled/cdn
ln -sf /etc/nginx/sites-available/gitea /etc/nginx/sites-enabled/gitea
rm -f /etc/nginx/sites-enabled/default

# Create cache directory
log "Creating cache directory..."
mkdir -p /var/cache/nginx/cdn
chown -R www-data:www-data /var/cache/nginx/cdn

# Test and reload nginx
log "Testing Nginx configuration..."
nginx -t

log "Reloading Nginx..."
systemctl reload nginx

log "✓ Nginx configured successfully"
