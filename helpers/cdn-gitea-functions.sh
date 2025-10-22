#!/bin/bash
# File: /opt/scripts/cdn/helpers/cdn-gitea-functions.sh (installed to /usr/local/bin/cdn-gitea-functions)
# Purpose: Manage Gitea user accounts and repositories for CDN tenants
#          Handles user creation, password resets, and repository linking

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load global configuration
CONFIG_FILE="/etc/cdn/config.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Configuration file not found: $CONFIG_FILE"
    return 1
fi
source "$CONFIG_FILE"

# Gitea binary path
GITEA_BIN="/usr/local/bin/gitea"
GITEA_CONFIG="${GITEA_WORK_DIR}/custom/conf/app.ini"

# Validate Gitea is installed and running
validate_gitea() {
    if [[ ! -f "$GITEA_BIN" ]]; then
        warn "Gitea binary not found at: $GITEA_BIN"
        return 1
    fi
    
    if ! systemctl is-active --quiet gitea; then
        warn "Gitea service is not running"
        return 1
    fi
    
    return 0
}

#=============================================================================
# USER MANAGEMENT
#=============================================================================

# Add tenant to Gitea (create user account and repository)
add_tenant_to_gitea() {
    local tenant_name=$1
    local onboarding_file=$2
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    # Validate Gitea is available
    if ! validate_gitea; then
        warn "Gitea not available, skipping Gitea user creation"
        return 1
    fi
    
    log "Creating Gitea user for tenant: $tenant_name"
    
    # Generate random password for initial setup
    local temp_password=$(openssl rand -base64 16)
    
    # Get tenant email from config if available
    local tenant_email=""
    local tenant_config="/etc/cdn/tenants/${tenant_name}.env"
    if [[ -f "$tenant_config" ]]; then
        source "$tenant_config"
        tenant_email="${GIT_USER_EMAIL}"
    fi
    
    # Fallback to default pattern if no email in config
    if [[ -z "$tenant_email" ]]; then
        tenant_email="${tenant_name}@${CDN_DOMAIN}"
    fi
    
    # Create Gitea user
    log "Creating Gitea user: $tenant_name"
    if su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user create \
        --username '${tenant_name}' \
        --password '${temp_password}' \
        --email '${tenant_email}' \
        --must-change-password \
        --config ${GITEA_CONFIG}" 2>&1 | grep -v "Password"; then
        
        log "✓ Gitea user created: $tenant_name"
        
        # Save credentials to onboarding file
        if [[ -n "$onboarding_file" ]] && [[ -f "$onboarding_file" ]]; then
            cat >> "$onboarding_file" << EOFOBOARD

GITEA LOGIN CREDENTIALS (SECURE FILE - DELETE AFTER USE)
====================================================================
URL:        https://${GITEA_DOMAIN}
Username:   ${tenant_name}
Password:   ${temp_password}

⚠️  IMPORTANT: You MUST change this password on first login!

This is a temporary password. Gitea will require you to set a new
password when you first log in.
====================================================================
EOFOBOARD
            chmod 600 "$onboarding_file"
            log "✓ Gitea credentials added to onboarding file"
        fi
        
        # Create separate secure file for password
        local secure_file="${LOG_DIR}/${tenant_name}_gitea_password_$(date +%Y%m%d_%H%M%S).txt"
        cat > "$secure_file" << EOFSF1
Gitea Credentials for: ${tenant_name}
Generated: $(date)

URL:      https://${GITEA_DOMAIN}
Username: ${tenant_name}
Password: ${temp_password}

⚠️  This is a temporary password.
⚠️  User must change it on first login.
⚠️  DELETE THIS FILE after sending to tenant.
⚠️  Send via secure channel only (encrypted email, password-protected archive, etc.)
EOFSF1
        chmod 600 "$secure_file"
        log "✓ Secure credentials file: $secure_file"
        
        # Create repository access for the tenant's Git repo
        log "Linking Git repository to Gitea..."
        create_gitea_repo "$tenant_name"
        
        return 0
    else
        error "Failed to create Gitea user: $tenant_name"
        return 1
    fi
}

# Create/link repository in Gitea
create_gitea_repo() {
    local tenant_name=$1
    local git_repo="${GIT_DIR}/${tenant_name}.git"
    
    [[ ! -d "$git_repo" ]] && { error "Git repository not found: $git_repo"; return 1; }
    
    log "Creating Gitea repository for: $tenant_name"
    
    # Ensure the repository is owned by git user for Gitea access
    chown -R git:git "$git_repo"
    
    # Method 1: Use Gitea CLI to create repository as the user
    # Note: This requires migrating/adopting the existing repo
    if su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin repo adopt \
        --owner '${tenant_name}' \
        --name '${tenant_name}' \
        --config ${GITEA_CONFIG}" 2>&1; then
        
        log "✓ Repository adopted by Gitea: ${tenant_name}/${tenant_name}"
        return 0
    fi
    
    # Method 2 (fallback): Manual migration approach
    warn "Repo adoption failed, trying manual migration..."
    
    # Create repo directory structure expected by Gitea
    local gitea_user_dir="${GIT_DIR}/${tenant_name}"
    local gitea_repo_dir="${gitea_user_dir}/${tenant_name}.git"
    
    mkdir -p "$gitea_user_dir"
    
    # If symlink doesn't exist, create it
    if [[ ! -L "$gitea_repo_dir" ]] && [[ ! -d "$gitea_repo_dir" ]]; then
        ln -s "$git_repo" "$gitea_repo_dir"
        log "✓ Repository linked at: $gitea_repo_dir"
    fi
    
    # Set proper ownership
    chown -R git:git "$gitea_user_dir"
    
    # Create repository in Gitea database via API
    local api_url="http://localhost:3000/api/v1/repos/migrate"
    local gitea_token=$(get_gitea_admin_token)
    
    if [[ -n "$gitea_token" ]]; then
        curl -X POST "$api_url" \
            -H "Authorization: token $gitea_token" \
            -H "Content-Type: application/json" \
            -d "{
                \"clone_addr\": \"${git_repo}\",
                \"uid\": $(get_gitea_user_id \"${tenant_name}\"),
                \"repo_name\": \"${tenant_name}\",
                \"mirror\": false,
                \"private\": false,
                \"description\": \"CDN files for ${tenant_name}\"
            }" 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            log "✓ Repository migrated to Gitea"
            return 0
        fi
    fi
    
    warn "Could not create repository in Gitea database"
    warn "Repository exists on disk but may not appear in web UI"
    warn "Administrator can manually migrate it via Gitea admin panel"
    
    return 0
}

# Helper: Get Gitea admin token
get_gitea_admin_token() {
    local token_file="/etc/cdn/.gitea-admin-token"
    
    if [[ -f "$token_file" ]]; then
        cat "$token_file"
        return 0
    fi
    
    # Generate new token
    local token=$(su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user generate-access-token \
        --username '${GITEA_ADMIN_USER}' \
        --token-name 'cdn-auto-management' \
        --scopes 'all' \
        --config ${GITEA_CONFIG}" 2>&1 | grep -oP '[a-f0-9]{40}' | head -1)
    
    if [[ -n "$token" ]]; then
        echo "$token" > "$token_file"
        chmod 600 "$token_file"
        echo "$token"
    fi
}

# Helper: Get Gitea user ID by username
get_gitea_user_id() {
    local username=$1
    
    local api_url="http://localhost:3000/api/v1/users/${username}"
    local gitea_token=$(get_gitea_admin_token)
    
    if [[ -n "$gitea_token" ]]; then
        curl -s "$api_url" \
            -H "Authorization: token $gitea_token" | \
            grep -oP '"id":\s*\K\d+' | head -1
    fi
}

# Reset Gitea password for tenant
gitea_reset_password() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    if ! validate_gitea; then
        error "Gitea not available"
        return 1
    fi
    
    # Check if user exists
    if ! su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user list \
        --config ${GITEA_CONFIG}" | grep -q "^${tenant_name}"; then
        error "Gitea user not found: $tenant_name"
        return 1
    fi
    
    log "Resetting Gitea password for: $tenant_name"
    
    # Generate new temporary password
    local new_password=$(openssl rand -base64 16)
    
    # Reset password using Gitea CLI
    if su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user change-password \
        --username '${tenant_name}' \
        --password '${new_password}' \
        --must-change-password \
        --config ${GITEA_CONFIG}" 2>&1; then
        
        log "✓ Password reset successfully"
        
        # Save new credentials
        local secure_file="${LOG_DIR}/${tenant_name}_gitea_password_reset_$(date +%Y%m%d_%H%M%S).txt"
        cat > "$secure_file" << EOFSF2
Gitea Password Reset for: ${tenant_name}
Generated: $(date)

URL:      https://${GITEA_DOMAIN}
Username: ${tenant_name}
Password: ${new_password}

⚠️  This is a temporary password.
⚠️  User must change it on next login.
⚠️  DELETE THIS FILE after sending to tenant.
⚠️  Send via secure channel only.
EOFSF2
        chmod 600 "$secure_file"
        
        echo ""
        log "═══════════════════════════════════════════════════════════"
        log "New Gitea Password Generated"
        log "═══════════════════════════════════════════════════════════"
        log "Username: ${tenant_name}"
        log "Password: ${new_password}"
        log ""
        log "Credentials saved to: $secure_file"
        log ""
        warn "⚠️  Send this password to tenant via secure channel"
        warn "⚠️  User must change password on next login"
        warn "⚠️  Delete the secure file after sending"
        log "═══════════════════════════════════════════════════════════"
        echo ""
        
        return 0
    else
        error "Failed to reset password"
        return 1
    fi
}

# Disable Gitea user (web access only, SFTP unaffected)
gitea_disable_user() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    if ! validate_gitea; then
        error "Gitea not available"
        return 1
    fi
    
    log "Disabling Gitea web access for: $tenant_name"
    
    # Use Gitea CLI to deactivate user
    if su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user change-password \
        --username '${tenant_name}' \
        --password '$(openssl rand -base64 32)' \
        --config ${GITEA_CONFIG}" 2>&1 && \
       su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user delete \
        --username '${tenant_name}' \
        --config ${GITEA_CONFIG}" 2>&1 | grep -q "Success"; then
        
        log "✓ Gitea web access disabled"
        log "Note: SFTP access remains active"
        return 0
    else
        warn "Failed to disable Gitea user"
        warn "User may need to be disabled manually via Gitea admin panel"
        return 1
    fi
}

# Enable Gitea user (recreate if deleted)
gitea_enable_user() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    if ! validate_gitea; then
        error "Gitea not available"
        return 1
    fi
    
    # Check if user already exists
    if su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user list \
        --config ${GITEA_CONFIG}" | grep -q "^${tenant_name}"; then
        log "Gitea user already exists and is active: $tenant_name"
        return 0
    fi
    
    log "Re-enabling Gitea access for: $tenant_name"
    
    # Recreate user using same process as add_tenant_to_gitea
    local onboarding_file="${LOG_DIR}/${tenant_name}_gitea_reenable_$(date +%Y%m%d_%H%M%S).txt"
    touch "$onboarding_file"
    chmod 600 "$onboarding_file"
    
    if add_tenant_to_gitea "$tenant_name" "$onboarding_file"; then
        log "✓ Gitea access re-enabled"
        log "Credentials saved to: $onboarding_file"
        return 0
    else
        error "Failed to re-enable Gitea access"
        return 1
    fi
}

#=============================================================================
# REPOSITORY MANAGEMENT
#=============================================================================

# Get Gitea repository URL for tenant
get_gitea_repo_url() {
    local tenant_name=$1
    echo "https://${GITEA_DOMAIN}/${tenant_name}/${tenant_name}.git"
}

# Check if Gitea user exists
gitea_user_exists() {
    local tenant_name=$1
    
    if ! validate_gitea; then
        return 1
    fi
    
    su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user list \
        --config ${GITEA_CONFIG}" | grep -q "^${tenant_name}"
    return $?
}

# Show Gitea user information
show_gitea_user_info() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    if ! validate_gitea; then
        warn "Gitea not available"
        return 1
    fi
    
    echo ""
    log "═══════════════════════════════════════════════════════════"
    log "Gitea User Information: $tenant_name"
    log "═══════════════════════════════════════════════════════════"
    echo ""
    
    if gitea_user_exists "$tenant_name"; then
        log "Status: Active"
        log "Web Portal: https://${GITEA_DOMAIN}"
        log "Repository: $(get_gitea_repo_url "$tenant_name")"
        
        # Get user details
        su - git -c "cd ${GITEA_WORK_DIR} && ${GITEA_BIN} admin user list \
            --config ${GITEA_CONFIG}" | grep "^${tenant_name}" || true
    else
        warn "Status: Not Found"
        warn "User does not exist in Gitea"
        warn "Run: sudo ./cdn-tenant-manager.sh gitea-enable $tenant_name"
    fi
    
    echo ""
    log "═══════════════════════════════════════════════════════════"
    echo ""
}

#=============================================================================
# COMMAND ROUTER (if executed directly)
#=============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        add-user)
            add_tenant_to_gitea "$2" "$3"
            ;;
        
        reset-password)
            gitea_reset_password "$2"
            ;;
        
        disable)
            gitea_disable_user "$2"
            ;;
        
        enable)
            gitea_enable_user "$2"
            ;;
        
        exists)
            gitea_user_exists "$2" && echo "yes" || echo "no"
            ;;
        
        info)
            show_gitea_user_info "$2"
            ;;
        
        *)
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "CDN Gitea Integration Functions"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "COMMANDS:"
            echo "  add-user <tenant> [onboarding_file]   Create Gitea user"
            echo "  reset-password <tenant>               Reset user password"
            echo "  disable <tenant>                      Disable web access"
            echo "  enable <tenant>                       Enable web access"
            echo "  exists <tenant>                       Check if user exists"
            echo "  info <tenant>                         Show user information"
            echo ""
            echo "EXAMPLES:"
            echo "  $0 add-user acmecorp /tmp/onboarding.txt"
            echo "  $0 reset-password acmecorp"
            echo "  $0 info acmecorp"
            echo ""
            echo "Note: This script is meant to be sourced by cdn-tenant-manager.sh"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            exit 1
            ;;
    esac
fi
