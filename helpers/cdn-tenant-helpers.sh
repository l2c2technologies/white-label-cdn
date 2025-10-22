#!/bin/bash
# File: /opt/scripts/cdn/helpers/cdn-tenant-helpers.sh (installed to /usr/local/bin/cdn-tenant-helpers)
# Purpose: Atomic functions for tenant configuration management
#          Provides create, update, validate, backup, and restore operations for tenant configs

set -e

# Source global config
CONFIG_FILE="/etc/cdn/config.env"
[[ ! -f "$CONFIG_FILE" ]] && { echo "ERROR: $CONFIG_FILE not found"; exit 1; }
source "$CONFIG_FILE"

# Tenant config directory
TENANT_CONFIG_DIR="/etc/cdn/tenants"
mkdir -p "$TENANT_CONFIG_DIR"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

#=============================================================================
# HELPER FUNCTIONS
#=============================================================================

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Get tenant config file path
get_tenant_config() {
    local tenant_name=$1
    echo "${TENANT_CONFIG_DIR}/${tenant_name}.env"
}

# Check if tenant config exists
tenant_config_exists() {
    local tenant_name=$1
    [[ -f "$(get_tenant_config "$tenant_name")" ]]
}

# Validate email format
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Validate tenant name
validate_tenant_name() {
    local tenant_name=$1
    if [[ ! "$tenant_name" =~ ^[a-z0-9_-]+$ ]]; then
        return 1
    fi
    return 0
}

#=============================================================================
# TENANT CONFIG CREATION
#=============================================================================

create_tenant_config() {
    local tenant_name=$1
    local git_email=${2:-"${tenant_name}@cdn.local"}
    local quota_mb=${3:-100}
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    
    # Validate tenant name
    if ! validate_tenant_name "$tenant_name"; then
        error "Invalid tenant name. Use only lowercase letters, numbers, hyphens, and underscores"
    fi
    
    # Validate git email
    if ! validate_email "$git_email"; then
        error "Invalid email format: $git_email"
    fi
    
    # Validate quota
    if [[ ! "$quota_mb" =~ ^[0-9]+$ ]]; then
        error "Quota must be a positive integer (MB)"
    fi
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Check if config already exists
    if [[ -f "$config_file" ]]; then
        error "Tenant config already exists: $config_file"
    fi
    
    local tenant_user="cdn_${tenant_name}"
    local watch_dir="${SFTP_DIR}/${tenant_name}/files"
    local git_repo="${GIT_DIR}/${tenant_name}.git"
    local log_file="${LOG_DIR}/${tenant_name}-autocommit.log"
    
    # Create tenant config
    cat > "$config_file" << EOL
# Tenant Configuration: ${tenant_name}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# DO NOT EDIT MANUALLY - Use cdn-tenant-helpers to update

# Tenant Identity
TENANT_NAME="${tenant_name}"
TENANT_USER="${tenant_user}"

# Directory Paths
WATCH_DIR="${watch_dir}"
GIT_REPO="${git_repo}"
LOG_FILE="${log_file}"

# Git Identity (also used for contact/alerts)
GIT_USER_NAME="${tenant_name}"
GIT_USER_EMAIL="${git_email}"

# Disk Quota (in MB)
QUOTA_MB="${quota_mb}"

# Metadata
CREATED_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
LAST_MODIFIED="$(date '+%Y-%m-%d %H:%M:%S')"
EOL
    
    # Set restrictive permissions (only root can read/write)
    chmod 600 "$config_file"
    chown root:root "$config_file"
    
    log "✓ Tenant config created: $config_file"
    log "  Tenant: $tenant_name"
    log "  Git Email: $git_email"
    log "  Quota: ${quota_mb}MB"
}

#=============================================================================
# ATOMIC UPDATE FUNCTIONS
#=============================================================================

update_git_email() {
    local tenant_name=$1
    local new_email=$2
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    [[ -z "$new_email" ]] && error "Email address required"
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Check if tenant exists
    if ! tenant_config_exists "$tenant_name"; then
        error "Tenant config not found: $tenant_name"
    fi
    
    # Validate email format
    if ! validate_email "$new_email"; then
        error "Invalid email format: $new_email"
    fi
    
    # Backup config file
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update config file
    sed -i "s|^GIT_USER_EMAIL=.*|GIT_USER_EMAIL=\"${new_email}\"|" "$config_file"
    
    # Update last modified timestamp
    sed -i "s|^LAST_MODIFIED=.*|LAST_MODIFIED=\"$(date '+%Y-%m-%d %H:%M:%S')\"|" "$config_file"
    
    log "✓ Config file updated"
    
    # Update git config in working directory
    local watch_dir="${SFTP_DIR}/${tenant_name}/files"
    if [[ -d "$watch_dir/.git" ]]; then
        cd "$watch_dir"
        local tenant_user="cdn_${tenant_name}"
        sudo -u "$tenant_user" git config user.email "$new_email"
        log "✓ Git config updated in working directory"
    else
        warn "Working directory not found or not a git repository: $watch_dir"
    fi
    
    log "✓ Git email updated for tenant: $tenant_name"
    log "  New email: $new_email"
    
    # Restart autocommit service to pick up changes
    if systemctl is-active --quiet "cdn-autocommit@${tenant_name}" 2>/dev/null; then
        systemctl restart "cdn-autocommit@${tenant_name}"
        sleep 1
        if systemctl is-active --quiet "cdn-autocommit@${tenant_name}"; then
            log "✓ Autocommit service restarted successfully"
        else
            warn "Autocommit service restart may have failed"
            warn "Check with: sudo systemctl status cdn-autocommit@${tenant_name}"
        fi
    else
        warn "Autocommit service not running for tenant: $tenant_name"
    fi
}

update_git_name() {
    local tenant_name=$1
    local new_name=$2
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    [[ -z "$new_name" ]] && error "Git name required"
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Check if tenant exists
    if ! tenant_config_exists "$tenant_name"; then
        error "Tenant config not found: $tenant_name"
    fi
    
    # Backup config file
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update config file
    sed -i "s|^GIT_USER_NAME=.*|GIT_USER_NAME=\"${new_name}\"|" "$config_file"
    
    # Update last modified timestamp
    sed -i "s|^LAST_MODIFIED=.*|LAST_MODIFIED=\"$(date '+%Y-%m-%d %H:%M:%S')\"|" "$config_file"
    
    log "✓ Config file updated"
    
    # Update git config in working directory
    local watch_dir="${SFTP_DIR}/${tenant_name}/files"
    if [[ -d "$watch_dir/.git" ]]; then
        cd "$watch_dir"
        local tenant_user="cdn_${tenant_name}"
        sudo -u "$tenant_user" git config user.name "$new_name"
        log "✓ Git config updated in working directory"
    else
        warn "Working directory not found or not a git repository: $watch_dir"
    fi
    
    log "✓ Git name updated for tenant: $tenant_name"
    log "  New name: $new_name"
    
    # Restart autocommit service to pick up changes
    if systemctl is-active --quiet "cdn-autocommit@${tenant_name}" 2>/dev/null; then
        systemctl restart "cdn-autocommit@${tenant_name}"
        sleep 1
        if systemctl is-active --quiet "cdn-autocommit@${tenant_name}"; then
            log "✓ Autocommit service restarted successfully"
        else
            warn "Autocommit service restart may have failed"
            warn "Check with: sudo systemctl status cdn-autocommit@${tenant_name}"
        fi
    else
        warn "Autocommit service not running for tenant: $tenant_name"
    fi
}

update_quota() {
    local tenant_name=$1
    local new_quota_mb=$2
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    [[ -z "$new_quota_mb" ]] && error "Quota (MB) required"
    
    # Validate quota
    if [[ ! "$new_quota_mb" =~ ^[0-9]+$ ]]; then
        error "Quota must be a positive integer (MB)"
    fi
    
    if [[ "$new_quota_mb" -lt 1 ]]; then
        error "Quota must be at least 1MB"
    fi
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Check if tenant exists
    if ! tenant_config_exists "$tenant_name"; then
        error "Tenant config not found: $tenant_name"
    fi
    
    # Backup config file
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update config file
    sed -i "s|^QUOTA_MB=.*|QUOTA_MB=\"${new_quota_mb}\"|" "$config_file"
    
    # Update last modified timestamp
    sed -i "s|^LAST_MODIFIED=.*|LAST_MODIFIED=\"$(date '+%Y-%m-%d %H:%M:%S')\"|" "$config_file"
    
    log "✓ Quota updated in config for tenant: $tenant_name"
    log "  New quota: ${new_quota_mb}MB"
}

#=============================================================================
# DISPLAY FUNCTIONS
#=============================================================================

show_tenant_config() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Check if tenant exists
    if ! tenant_config_exists "$tenant_name"; then
        error "Tenant config not found: $tenant_name"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Tenant Configuration: $tenant_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    cat "$config_file"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Config file location: $config_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

show_git_config() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Check if tenant exists
    if ! tenant_config_exists "$tenant_name"; then
        error "Tenant config not found: $tenant_name"
    fi
    
    # Load config
    source "$config_file"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Git Configuration: $tenant_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Configuration File Settings:"
    echo "  Git User Name:  $GIT_USER_NAME"
    echo "  Git User Email: $GIT_USER_EMAIL"
    echo ""
    
    # Also show from actual git config in working directory
    local watch_dir="${SFTP_DIR}/${tenant_name}/files"
    if [[ -d "$watch_dir/.git" ]]; then
        cd "$watch_dir"
        echo "Current Git Config (in working directory):"
        echo "  user.name:  $(git config user.name 2>/dev/null || echo 'NOT SET')"
        echo "  user.email: $(git config user.email 2>/dev/null || echo 'NOT SET')"
        echo ""
        
        # Check if they match
        local git_name=$(git config user.name 2>/dev/null || echo "")
        local git_email=$(git config user.email 2>/dev/null || echo "")
        
        if [[ "$git_name" != "$GIT_USER_NAME" ]] || [[ "$git_email" != "$GIT_USER_EMAIL" ]]; then
            warn "Configuration mismatch detected!"
            warn "Git config in working directory differs from config file"
            warn "Run: sudo ./cdn-tenant-manager.sh restart $tenant_name"
        fi
    else
        warn "Working directory not found or not a git repository: $watch_dir"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

list_all_tenant_configs() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "All Tenant Configurations"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [[ ! -d "$TENANT_CONFIG_DIR" ]] || [[ -z "$(ls -A $TENANT_CONFIG_DIR 2>/dev/null)" ]]; then
        warn "No tenant configurations found"
        return 0
    fi
    
    printf "%-20s %-40s %-15s\n" "TENANT" "GIT EMAIL" "QUOTA (MB)"
    printf "%-20s %-40s %-15s\n" "------" "---------" "----------"
    
    for config_file in "$TENANT_CONFIG_DIR"/*.env; do
        if [[ -f "$config_file" ]]; then
            # Source the config
            source "$config_file"
            
            printf "%-20s %-40s %-15s\n" \
                "$TENANT_NAME" \
                "$GIT_USER_EMAIL" \
                "$QUOTA_MB"
        fi
    done
    
    echo ""
    local count=$(ls -1 "$TENANT_CONFIG_DIR"/*.env 2>/dev/null | wc -l)
    log "Total tenant configurations: $count"
    echo ""
}

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

validate_tenant_config() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Check if tenant exists
    if ! tenant_config_exists "$tenant_name"; then
        error "Tenant config not found: $tenant_name"
    fi
    
    echo ""
    log "Validating tenant configuration: $tenant_name"
    echo ""
    
    local errors=0
    
    # Source config
    source "$config_file"
    
    # Validate required variables
    if [[ -z "$TENANT_NAME" ]]; then
        warn "✗ TENANT_NAME not set"
        ((errors++))
    else
        log "✓ TENANT_NAME: $TENANT_NAME"
    fi
    
    if [[ -z "$TENANT_USER" ]]; then
        warn "✗ TENANT_USER not set"
        ((errors++))
    else
        log "✓ TENANT_USER: $TENANT_USER"
    fi
    
    if [[ -z "$WATCH_DIR" ]]; then
        warn "✗ WATCH_DIR not set"
        ((errors++))
    else
        if [[ -d "$WATCH_DIR" ]]; then
            log "✓ WATCH_DIR exists: $WATCH_DIR"
        else
            warn "✗ WATCH_DIR does not exist: $WATCH_DIR"
            ((errors++))
        fi
    fi
    
    if [[ -z "$GIT_REPO" ]]; then
        warn "✗ GIT_REPO not set"
        ((errors++))
    else
        if [[ -d "$GIT_REPO" ]]; then
            log "✓ GIT_REPO exists: $GIT_REPO"
        else
            warn "✗ GIT_REPO does not exist: $GIT_REPO"
            ((errors++))
        fi
    fi
    
    if [[ -z "$LOG_FILE" ]]; then
        warn "✗ LOG_FILE not set"
        ((errors++))
    else
        log "✓ LOG_FILE: $LOG_FILE"
    fi
    
    if [[ -z "$GIT_USER_NAME" ]]; then
        warn "✗ GIT_USER_NAME not set"
        ((errors++))
    else
        log "✓ GIT_USER_NAME: $GIT_USER_NAME"
    fi
    
    if [[ -z "$GIT_USER_EMAIL" ]]; then
        warn "✗ GIT_USER_EMAIL not set"
        ((errors++))
    else
        if validate_email "$GIT_USER_EMAIL"; then
            log "✓ GIT_USER_EMAIL: $GIT_USER_EMAIL"
        else
            warn "✗ GIT_USER_EMAIL invalid format: $GIT_USER_EMAIL"
            ((errors++))
        fi
    fi
    
    if [[ -z "$QUOTA_MB" ]]; then
        warn "✗ QUOTA_MB not set"
        ((errors++))
    else
        if [[ "$QUOTA_MB" =~ ^[0-9]+$ ]]; then
            log "✓ QUOTA_MB: ${QUOTA_MB}MB"
        else
            warn "✗ QUOTA_MB invalid format: $QUOTA_MB"
            ((errors++))
        fi
    fi
    
    echo ""
    if [[ $errors -eq 0 ]]; then
        log "✓ Configuration validation passed"
    else
        error "Configuration validation failed with $errors error(s)"
    fi
}

#=============================================================================
# BACKUP AND RESTORE FUNCTIONS
#=============================================================================

backup_tenant_config() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Check if tenant exists
    if ! tenant_config_exists "$tenant_name"; then
        error "Tenant config not found: $tenant_name"
    fi
    
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    cp "$config_file" "$backup_file"
    
    log "✓ Config backed up to: $backup_file"
}

restore_tenant_config() {
    local tenant_name=$1
    local backup_file=$2
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    [[ -z "$backup_file" ]] && error "Backup file path required"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    # Backup current config before restore
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${config_file}.pre-restore.$(date +%Y%m%d_%H%M%S)"
        log "✓ Current config backed up"
    fi
    
    cp "$backup_file" "$config_file"
    
    log "✓ Config restored from: $backup_file"
    
    # Restart service
    if systemctl is-active --quiet "cdn-autocommit@${tenant_name}" 2>/dev/null; then
        systemctl restart "cdn-autocommit@${tenant_name}"
        log "✓ Autocommit service restarted"
    fi
}

#=============================================================================
# CLEANUP FUNCTIONS
#=============================================================================

cleanup_old_backups() {
    local tenant_name=$1
    local keep_days=${2:-30}
    
    [[ -z "$tenant_name" ]] && error "Tenant name required"
    
    local config_file=$(get_tenant_config "$tenant_name")
    
    log "Cleaning up backups older than $keep_days days for: $tenant_name"
    
    local count=0
    while IFS= read -r backup_file; do
        rm -f "$backup_file"
        ((count++))
    done < <(find "$(dirname "$config_file")" -name "${tenant_name}.env.backup.*" -mtime +${keep_days})
    
    if [[ $count -gt 0 ]]; then
        log "✓ Removed $count old backup(s)"
    else
        log "No old backups to remove"
    fi
}

#=============================================================================
# COMMAND ROUTER
#=============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly, not sourced
    
    case "${1:-}" in
        create)
            create_tenant_config "$2" "$3" "$4"
            ;;
        
        update-email)
            update_git_email "$2" "$3"
            ;;
        
        update-name)
            update_git_name "$2" "$3"
            ;;
        
        update-quota)
            update_quota "$2" "$3"
            ;;
        
        show)
            show_tenant_config "$2"
            ;;
        
        show-git)
            show_git_config "$2"
            ;;
        
        list)
            list_all_tenant_configs
            ;;
        
        validate)
            validate_tenant_config "$2"
            ;;
        
        backup)
            backup_tenant_config "$2"
            ;;
        
        restore)
            restore_tenant_config "$2" "$3"
            ;;
        
        cleanup-backups)
            cleanup_old_backups "$2" "$3"
            ;;
        
        *)
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "CDN Tenant Helper Functions"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "CONFIGURATION MANAGEMENT:"
            echo "  create <tenant> [email] [quota_mb]    Create tenant config"
            echo "  show <tenant>                         Show full tenant config"
            echo "  show-git <tenant>                     Show git configuration"
            echo "  list                                  List all tenant configs"
            echo "  validate <tenant>                     Validate tenant config"
            echo ""
            echo "UPDATE COMMANDS:"
            echo "  update-email <tenant> <email>         Update git email"
            echo "  update-name <tenant> <name>           Update git name"
            echo "  update-quota <tenant> <mb>            Update quota"
            echo ""
            echo "BACKUP & RESTORE:"
            echo "  backup <tenant>                       Backup tenant config"
            echo "  restore <tenant> <backup_file>        Restore from backup"
            echo "  cleanup-backups <tenant> [days]       Remove old backups (default: 30 days)"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            exit 1
            ;;
    esac
fi
