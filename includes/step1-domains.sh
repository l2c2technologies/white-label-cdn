#!/bin/bash
# File: /opt/scripts/cdn/includes/step1-domains.sh
# Purpose: Collect and validate CDN and Gitea domain names
#          Ensures domains are properly formatted and different from each other

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "STEP 1: Domain Configuration"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ==============================================================================
# CDN DOMAIN
# ==============================================================================

while true; do
    read -p "Enter your CDN domain (e.g., cdn.example.com): " CDN_DOMAIN
    CDN_DOMAIN=$(echo "$CDN_DOMAIN" | xargs)
    
    if [[ -z "$CDN_DOMAIN" ]]; then
        warn "CDN domain cannot be empty"
        continue
    fi
    
    if ! validate_domain "$CDN_DOMAIN"; then
        warn "Invalid domain format. Please use format: subdomain.domain.com"
        continue
    fi
    
    echo ""
    read -p "CDN will be accessible at: https://${CDN_DOMAIN}/<tenant>/  Is this correct? (yes/no): " confirm
    [[ "$confirm" == "yes" ]] && break
    echo ""
done

echo ""

# ==============================================================================
# GITEA DOMAIN
# ==============================================================================

while true; do
    read -p "Enter your Gitea domain (e.g., git.example.com): " GITEA_DOMAIN
    GITEA_DOMAIN=$(echo "$GITEA_DOMAIN" | xargs)
    
    if [[ -z "$GITEA_DOMAIN" ]]; then
        warn "Gitea domain cannot be empty"
        continue
    fi
    
    if ! validate_domain "$GITEA_DOMAIN"; then
        warn "Invalid domain format. Please use format: subdomain.domain.com"
        continue
    fi
    
    if [[ "$GITEA_DOMAIN" == "$CDN_DOMAIN" ]]; then
        warn "Gitea domain must be different from CDN domain"
        continue
    fi
    
    echo ""
    read -p "Gitea will be accessible at: https://${GITEA_DOMAIN}  Is this correct? (yes/no): " confirm
    [[ "$confirm" == "yes" ]] && break
    echo ""
done

log "✓ Domains configured successfully"
