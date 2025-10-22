#!/bin/bash
# File: /opt/scripts/cdn/includes/step4-letsencrypt.sh
# Purpose: Configure Let's Encrypt SSL certificate settings
#          Collects email for certificate renewal notifications

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "STEP 4: Let's Encrypt SSL Configuration"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cat << EOF
Let's Encrypt will provide free SSL/TLS certificates for your domains.

Note: DNS must be configured and propagated BEFORE running the SSL setup.
      We'll create a helper script to run after DNS is ready.

EOF

# Let's Encrypt email validation
while true; do
    read -p "Let's Encrypt account email (for renewal notices, or press ENTER to skip): " LE_EMAIL
    LE_EMAIL=$(echo "$LE_EMAIL" | xargs)
    
    if [[ -z "$LE_EMAIL" ]]; then
        warn "No email provided. Certificates will be registered without email."
        warn "You will NOT receive renewal or expiry notices!"
        read -p "Continue without email? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            LE_EMAIL=""
            break
        fi
        continue
    fi
    
    if validate_email "$LE_EMAIL"; then
        log "Email validated: ${LE_EMAIL}"
        break
    else
        warn "Invalid email format. Please enter a valid email address."
    fi
done

log "✓ Let's Encrypt configuration completed"
