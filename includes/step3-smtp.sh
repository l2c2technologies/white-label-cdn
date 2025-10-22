#!/bin/bash
# File: /opt/scripts/cdn/includes/step3-smtp.sh
# Purpose: Configure SMTP settings for email notifications and alerts
#          Validates email addresses and connection parameters

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "STEP 3: SMTP Configuration (for alerts and notifications)"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Do you want to configure SMTP for email notifications? (yes/no): " CONFIGURE_SMTP
echo ""

if [[ "$CONFIGURE_SMTP" == "yes" ]]; then
    # SMTP Host validation
    while true; do
        read -p "SMTP server hostname (e.g., smtp.gmail.com): " SMTP_HOST
        SMTP_HOST=$(echo "$SMTP_HOST" | xargs)
        
        if [[ -z "$SMTP_HOST" ]]; then
            warn "SMTP host cannot be empty"
            continue
        fi
        
        if ! validate_domain "$SMTP_HOST"; then
            warn "Invalid hostname format"
            continue
        fi
        
        break
    done
    
    # SMTP Port validation
    while true; do
        read -p "SMTP port (typically 587 for TLS, 465 for SSL): " SMTP_PORT
        SMTP_PORT=$(echo "$SMTP_PORT" | xargs)
        
        if ! validate_port "$SMTP_PORT"; then
            warn "Invalid port number (must be 1-65535)"
            continue
        fi
        
        break
    done
    
    # SMTP Username (email) validation
    while true; do
        read -p "SMTP username (email address): " SMTP_USER
        SMTP_USER=$(echo "$SMTP_USER" | xargs)
        
        if [[ -z "$SMTP_USER" ]]; then
            warn "SMTP username cannot be empty"
            continue
        fi
        
        if ! validate_email "$SMTP_USER"; then
            warn "Invalid email format"
            continue
        fi
        
        break
    done
    
    # SMTP Password
    while true; do
        read -sp "SMTP password: " SMTP_PASS
        echo ""
        
        if [[ -z "$SMTP_PASS" ]]; then
            warn "SMTP password cannot be empty"
            continue
        fi
        
        break
    done
    
    # From Email validation
    while true; do
        read -p "From email address (for notifications): " SMTP_FROM
        SMTP_FROM=$(echo "$SMTP_FROM" | xargs)
        
        if [[ -z "$SMTP_FROM" ]]; then
            warn "From email cannot be empty"
            continue
        fi
        
        if ! validate_email "$SMTP_FROM"; then
            warn "Invalid email format"
            continue
        fi
        
        break
    done
    
    # Alert Email validation
    while true; do
        read -p "Alert recipient email address: " ALERT_EMAIL
        ALERT_EMAIL=$(echo "$ALERT_EMAIL" | xargs)
        
        if [[ -z "$ALERT_EMAIL" ]]; then
            warn "Alert email cannot be empty"
            continue
        fi
        
        if ! validate_email "$ALERT_EMAIL"; then
            warn "Invalid email format"
            continue
        fi
        
        break
    done
    
    # TLS/SSL
    read -p "Use TLS/STARTTLS? (yes/no, default: yes): " USE_TLS
    USE_TLS=${USE_TLS:-yes}
    
    SMTP_ENABLED="true"
    log "✓ SMTP configured successfully"
else
    SMTP_ENABLED="false"
    SMTP_HOST=""
    SMTP_PORT=""
    SMTP_USER=""
    SMTP_PASS=""
    SMTP_FROM=""
    ALERT_EMAIL=""
    USE_TLS="yes"
    
    warn "Email notifications will be disabled"
fi
