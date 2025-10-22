#!/bin/bash
# File: /opt/scripts/cdn/includes/step6-gitea-admin.sh
# Purpose: Configure Gitea administrator account credentials
#          Can use system user or create dedicated Gitea admin

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "STEP 6: Gitea Administrator Configuration"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cat << GITEAINFO
Gitea provides a web interface for Git repositories and version control.

An administrator account is required for:
  • Managing repositories
  • Viewing tenant file history
  • Accessing blame and diff features
  • System administration

You can either:
  1. Use your current system credentials (simplest)
  2. Create a separate Gitea administrator account

GITEAINFO

echo ""
CURRENT_USER=$(whoami)
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [[ -n "$CURRENT_EMAIL" ]]; then
    log "Detected system email: ${CURRENT_EMAIL}"
fi

echo ""
while true; do
    read -p "Use current system user for Gitea admin? (yes/no): " USE_SYSTEM_CREDS
    
    if [[ "$USE_SYSTEM_CREDS" == "yes" ]]; then
        GITEA_ADMIN_USER="$CURRENT_USER"
        
        # Get email
        if [[ -n "$CURRENT_EMAIL" ]]; then
            read -p "Use email ${CURRENT_EMAIL} for Gitea? (yes/no): " use_detected
            if [[ "$use_detected" == "yes" ]]; then
                GITEA_ADMIN_EMAIL="$CURRENT_EMAIL"
            else
                while true; do
                    read -p "Enter admin email: " GITEA_ADMIN_EMAIL
                    GITEA_ADMIN_EMAIL=$(echo "$GITEA_ADMIN_EMAIL" | xargs)
                    validate_email "$GITEA_ADMIN_EMAIL" && break
                    warn "Invalid email format"
                done
            fi
        else
            while true; do
                read -p "Enter admin email: " GITEA_ADMIN_EMAIL
                GITEA_ADMIN_EMAIL=$(echo "$GITEA_ADMIN_EMAIL" | xargs)
                validate_email "$GITEA_ADMIN_EMAIL" && break
                warn "Invalid email format"
            done
        fi
        
        # Get password
        while true; do
            read -sp "Enter Gitea admin password (min 6 chars): " GITEA_ADMIN_PASS
            echo ""
            if [[ ${#GITEA_ADMIN_PASS} -lt 6 ]]; then
                warn "Password must be at least 6 characters"
                continue
            fi
            read -sp "Confirm password: " GITEA_ADMIN_PASS_CONFIRM
            echo ""
            if [[ "$GITEA_ADMIN_PASS" == "$GITEA_ADMIN_PASS_CONFIRM" ]]; then
                break
            fi
            warn "Passwords do not match"
        done
        
        log "✓ Using system user: ${GITEA_ADMIN_USER}"
        break
        
    elif [[ "$USE_SYSTEM_CREDS" == "no" ]]; then
        # Create separate Gitea admin
        while true; do
            read -p "Gitea admin username: " GITEA_ADMIN_USER
            GITEA_ADMIN_USER=$(echo "$GITEA_ADMIN_USER" | xargs)
            [[ -n "$GITEA_ADMIN_USER" ]] && break
            warn "Username cannot be empty"
        done
        
        while true; do
            read -p "Gitea admin email: " GITEA_ADMIN_EMAIL
            GITEA_ADMIN_EMAIL=$(echo "$GITEA_ADMIN_EMAIL" | xargs)
            validate_email "$GITEA_ADMIN_EMAIL" && break
            warn "Invalid email format"
        done
        
        while true; do
            read -sp "Gitea admin password (min 6 chars): " GITEA_ADMIN_PASS
            echo ""
            if [[ ${#GITEA_ADMIN_PASS} -lt 6 ]]; then
                warn "Password must be at least 6 characters"
                continue
            fi
            read -sp "Confirm password: " GITEA_ADMIN_PASS_CONFIRM
            echo ""
            if [[ "$GITEA_ADMIN_PASS" == "$GITEA_ADMIN_PASS_CONFIRM" ]]; then
                break
            fi
            warn "Passwords do not match"
        done
        
        log "✓ Separate Gitea admin will be created: ${GITEA_ADMIN_USER}"
        break
    else
        warn "Please answer 'yes' or 'no'"
    fi
done

log "✓ Gitea administrator configured successfully"
