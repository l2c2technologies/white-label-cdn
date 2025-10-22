#!/bin/bash
# File: /opt/scripts/cdn/cdn-tenant-manager.sh (installed to /usr/local/bin/cdn-tenant-manager)
# Purpose: Unified tenant management interface for Multi-Tenant CDN System
#          Coordinates user creation, directories, Git repos, quotas, Gitea accounts, and services
#          Main administrative tool for day-to-day tenant operations

set -eE

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# DEBUG mode: set to "true" for verbose error reporting
DEBUG="${DEBUG:-false}"

# Source global configuration
CONFIG_FILE="/etc/cdn/config.env"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ==============================================================================
# ERROR HANDLING
# ==============================================================================

error_handler() {
    local line_no=$1
    local bash_lineno=$2
    local last_command=$3
    local func_stack=($4)
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "ERROR OCCURRED IN TENANT MANAGER" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "Command: ${last_command}" >&2
    echo "Exit Code: $?" >&2
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "" >&2
        echo "Debug Information:" >&2
        echo "  File: ${BASH_SOURCE[1]}" >&2
        echo "  Line: ${line_no}" >&2
        echo "  Function: ${FUNCNAME[1]:-main}" >&2
        
        if [[ ${#BASH_SOURCE[@]} -gt 2 ]]; then
            echo "" >&2
            echo "Call Stack:" >&2
            local i=0
            while [[ $i -lt ${#FUNCNAME[@]} ]]; do
                if [[ $i -gt 0 ]]; then
                    echo "  [$i] ${FUNCNAME[$i]} (${BASH_SOURCE[$i+1]}:${BASH_LINENO[$i]})" >&2
                fi
                ((i++))
            done
        fi
    else
        echo "  Source: ${BASH_SOURCE[1]}" >&2
        echo "  Enable DEBUG mode for more details: DEBUG=true $0 $*" >&2
    fi
    
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    exit 1
}

trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND" "${FUNCNAME[*]}"' ERR

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
info() { echo -e "${BLUE}[TENANT]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==============================================================================
# PREFLIGHT CHECKS
# ==============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    echo "Please run: sudo $0 $*"
    exit 1
fi

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Configuration file not found: $CONFIG_FILE"
    echo "Please run: sudo cdn-initial-setup"
    exit 1
fi

source "$CONFIG_FILE"

# Source helper functions
if [[ -f /usr/local/bin/cdn-tenant-helpers ]]; then
    source /usr/local/bin/cdn-tenant-helpers
else
    error "Helper functions not found: /usr/local/bin/cdn-tenant-helpers"
    exit 1
fi

if [[ -f /usr/local/bin/cdn-quota-functions ]]; then
    source /usr/local/bin/cdn-quota-functions
else
    warn "Quota functions not found: /usr/local/bin/cdn-quota-functions"
fi

if [[ -f /usr/local/bin/cdn-gitea-functions ]]; then
    source /usr/local/bin/cdn-gitea-functions
else
    warn "Gitea functions not found: /usr/local/bin/cdn-gitea-functions"
fi

# ==============================================================================
# TENANT CREATION
# ==============================================================================

create_tenant() {
    local tenant_name=$1
    local tenant_email=${2:-""}
    local quota_mb=${3:-100}
    
    # Validate tenant name
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 create <tenant-name> [email] [quota-mb]"
        exit 1
    fi
    
    if ! validate_tenant_name "$tenant_name"; then
        error "Invalid tenant name: $tenant_name"
        echo "Tenant name must contain only lowercase letters, numbers, hyphens, and underscores"
        exit 1
    fi
    
    # Set default email if not provided
    if [[ -z "$tenant_email" ]]; then
        tenant_email="${tenant_name}@${CDN_DOMAIN}"
        log "Using default email: $tenant_email"
    fi
    
    # Validate email
    if ! validate_email "$tenant_email"; then
        error "Invalid email format: $tenant_email"
        exit 1
    fi
    
    echo ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "Creating New Tenant: $tenant_name"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    log "Tenant Name: $tenant_name"
    log "Email: $tenant_email"
    log "Quota: ${quota_mb}MB"
    echo ""
    
    # Check if tenant already exists
    if id "cdn_${tenant_name}" &>/dev/null; then
        error "Tenant user already exists: cdn_${tenant_name}"
        exit 1
    fi
    
    if tenant_config_exists "$tenant_name"; then
        error "Tenant configuration already exists"
        exit 1
    fi
    
    # Create tenant configuration
    log "Step 1/10: Creating tenant configuration..."
    create_tenant_config "$tenant_name" "$tenant_email" "$quota_mb"
    
    # Create system user
    log "Step 2/10: Creating system user..."
    local tenant_user="cdn_${tenant_name}"
    local tenant_home="${SFTP_DIR}/${tenant_name}"
    
    useradd -r -m -d "$tenant_home" -s /bin/bash -G sftpusers "$tenant_user"
    log "✓ User created: $tenant_user"
    
    # Create directory structure
    log "Step 3/10: Creating directory structure..."
    mkdir -p "${tenant_home}/files"
    chown root:root "$tenant_home"
    chmod 755 "$tenant_home"
    chown "${tenant_user}:${tenant_user}" "${tenant_home}/files"
    chmod 755 "${tenant_home}/files"
    log "✓ Directories created"
    
    # Initialize Git repository (bare)
    log "Step 4/10: Initializing Git repository..."
    local git_repo="${GIT_DIR}/${tenant_name}.git"
    mkdir -p "$git_repo"
    cd "$git_repo"
    git init --bare
    chown -R git:git "$git_repo"
    log "✓ Bare repository created: $git_repo"
    
    # Initialize working directory Git repository
    log "Step 5/10: Initializing working directory..."
    cd "${tenant_home}/files"
    sudo -u "$tenant_user" git init
    sudo -u "$tenant_user" git config user.name "$tenant_name"
    sudo -u "$tenant_user" git config user.email "$tenant_email"
    sudo -u "$tenant_user" git remote add origin "$git_repo"
    
    # Create initial commit
    sudo -u "$tenant_user" touch README.md
    cat > README.md << EOFREADME
# ${tenant_name} CDN Files

This directory is automatically synced to Git.
Any file changes will be committed and versioned automatically.

## Access Information

- **CDN URL**: https://${CDN_DOMAIN}/${tenant_name}/
- **Gitea Portal**: https://${GITEA_DOMAIN}/${tenant_name}/${tenant_name}
- **SFTP Access**: sftp -P ${SFTP_PORT} ${tenant_user}@${CDN_DOMAIN}

## Quota

- **Limit**: ${quota_mb}MB
- **Current Usage**: 0MB

Upload your files via SFTP and they will be automatically available on the CDN.
EOFREADME
    
    chown "${tenant_user}:${tenant_user}" README.md
    sudo -u "$tenant_user" git add README.md
    sudo -u "$tenant_user" git commit -m "Initial commit for ${tenant_name}"
    sudo -u "$tenant_user" git push -u origin master
    log "✓ Working directory initialized"
    
    # Setup post-receive hook for deployment
    log "Step 6/10: Setting up Git deployment hook..."
    cat > "${git_repo}/hooks/post-receive" << 'EOFHOOK'
#!/bin/bash
# Post-receive hook for CDN deployment

TENANT_NAME=$(basename $(dirname $(pwd)) .git)
DEPLOY_DIR="/srv/cdn/www/${TENANT_NAME}"

# Create deployment directory if it doesn't exist
mkdir -p "$DEPLOY_DIR"

# Checkout latest version
git --work-tree="$DEPLOY_DIR" --git-dir="$(pwd)" checkout -f master

# Set permissions
chown -R www-data:www-data "$DEPLOY_DIR"
chmod -R 755 "$DEPLOY_DIR"

echo "Deployed to CDN: https://$(hostname -f)/${TENANT_NAME}/"
EOFHOOK
    
    chmod +x "${git_repo}/hooks/post-receive"
    chown git:git "${git_repo}/hooks/post-receive"
    log "✓ Deployment hook configured"
    
    # Create Nginx deployment directory
    log "Step 7/10: Creating Nginx deployment directory..."
    mkdir -p "${NGINX_DIR}/${tenant_name}"
    chown www-data:www-data "${NGINX_DIR}/${tenant_name}"
    chmod 755 "${NGINX_DIR}/${tenant_name}"
    
    # Deploy initial files
    git --work-tree="${NGINX_DIR}/${tenant_name}" --git-dir="$git_repo" checkout -f master
    chown -R www-data:www-data "${NGINX_DIR}/${tenant_name}"
    log "✓ Initial deployment to CDN"
    
    # Set disk quota
    log "Step 8/10: Setting disk quota..."
    set_tenant_quota "$tenant_name" "$quota_mb"
    
    # Generate SSH key pair
    log "Step 9/10: Generating SSH key pair..."
    local key_dir="/etc/cdn/keys/${tenant_name}"
    mkdir -p "$key_dir"
    ssh-keygen -t ed25519 -f "${key_dir}/id_ed25519" -N "" -C "${tenant_email}" >/dev/null 2>&1
    chmod 600 "${key_dir}/id_ed25519"
    chmod 644 "${key_dir}/id_ed25519.pub"
    
    # Install public key for SFTP access
    mkdir -p "${tenant_home}/.ssh"
    cp "${key_dir}/id_ed25519.pub" "${tenant_home}/.ssh/authorized_keys"
    chown root:root "${tenant_home}/.ssh"
    chmod 755 "${tenant_home}/.ssh"
    chown root:root "${tenant_home}/.ssh/authorized_keys"
    chmod 644 "${tenant_home}/.ssh/authorized_keys"
    log "✓ SSH keys generated and installed"
    
    # Start autocommit service
    log "Step 10/10: Starting autocommit service..."
    systemctl enable "cdn-autocommit@${tenant_name}.service"
    systemctl start "cdn-autocommit@${tenant_name}.service"
    sleep 2
    
    if systemctl is-active --quiet "cdn-autocommit@${tenant_name}"; then
        log "✓ Autocommit service started"
    else
        warn "Autocommit service may not have started correctly"
        warn "Check status: sudo systemctl status cdn-autocommit@${tenant_name}"
    fi
    
    # Create Gitea account (optional, non-blocking)
    local onboarding_file="/tmp/${tenant_name}_onboarding_$(date +%Y%m%d_%H%M%S).txt"
    touch "$onboarding_file"
    chmod 600 "$onboarding_file"
    
    if type add_tenant_to_gitea &>/dev/null; then
        log "Creating Gitea web portal account..."
        if add_tenant_to_gitea "$tenant_name" "$onboarding_file" 2>/dev/null; then
            log "✓ Gitea account created"
        else
            warn "Gitea account creation skipped (service may not be ready)"
        fi
    fi
    
    # Generate onboarding documentation
    cat > "$onboarding_file" << EOFONBOARD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TENANT ONBOARDING INFORMATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Tenant: ${tenant_name}
Created: $(date '+%Y-%m-%d %H:%M:%S')

CDN ACCESS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your files are accessible at:
  https://${CDN_DOMAIN}/${tenant_name}/

Example:
  https://${CDN_DOMAIN}/${tenant_name}/image.jpg
  https://${CDN_DOMAIN}/${tenant_name}/styles/main.css

SFTP ACCESS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Connection Details:
  Host: ${CDN_DOMAIN}
  Port: ${SFTP_PORT}
  User: ${tenant_user}
  Auth: SSH Key (password authentication disabled)

SSH Private Key Location (SECURE THIS FILE):
  ${key_dir}/id_ed25519

Connection Command:
  sftp -i ${key_dir}/id_ed25519 -P ${SFTP_PORT} ${tenant_user}@${CDN_DOMAIN}

Upload Files:
  sftp> put localfile.jpg
  sftp> put -r local_directory/

WEB PORTAL (Gitea)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Access your file history and Git repository:
  https://${GITEA_DOMAIN}

(Credentials appended below if Gitea account was created)

QUOTA INFORMATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Disk Quota: ${quota_mb}MB
Current Usage: ~0.1MB (README.md)

Monitor usage via Gitea portal or contact your administrator.

AUTOMATIC FEATURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ Auto-Commit: All file changes automatically committed to Git
✓ Version Control: Full file history available in Gitea
✓ CDN Deployment: Files instantly available on CDN after upload
✓ Quota Monitoring: Automatic alerts when approaching limit

IMPORTANT SECURITY NOTES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  SECURE THE SSH PRIVATE KEY!
   - Store ${key_dir}/id_ed25519 securely
   - Never share or commit to version control
   - Use appropriate file permissions (600)

⚠️  DELETE THIS FILE after reviewing
   - This file contains sensitive information
   - Store credentials in a secure password manager

GETTING STARTED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Secure the SSH private key:
   cp ${key_dir}/id_ed25519 ~/secure-location/
   chmod 600 ~/secure-location/id_ed25519

2. Test SFTP connection:
   sftp -i ~/secure-location/id_ed25519 -P ${SFTP_PORT} ${tenant_user}@${CDN_DOMAIN}

3. Upload a test file:
   echo "Hello CDN" > test.txt
   sftp> put test.txt

4. Verify on CDN:
   curl https://${CDN_DOMAIN}/${tenant_name}/test.txt

5. Check version history:
   Visit https://${GITEA_DOMAIN}

SUPPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For assistance, contact your system administrator.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generated: $(date)
Tenant: ${tenant_name}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOFONBOARD
    
    chmod 600 "$onboarding_file"
    
    # Success summary
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "✓ Tenant Created Successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "Tenant: $tenant_name"
    log "Email: $tenant_email"
    log "Quota: ${quota_mb}MB"
    echo ""
    log "CDN URL: https://${CDN_DOMAIN}/${tenant_name}/"
    log "Gitea Portal: https://${GITEA_DOMAIN}"
    log "SFTP: ${tenant_user}@${CDN_DOMAIN}:${SFTP_PORT}"
    echo ""
    log "Onboarding Information: $onboarding_file"
    log "SSH Private Key: ${key_dir}/id_ed25519"
    echo ""
    warn "⚠️  IMPORTANT: Securely deliver the onboarding file and SSH key to the tenant"
    warn "⚠️  Delete the onboarding file after delivery"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ==============================================================================
# TENANT DELETION
# ==============================================================================

delete_tenant() {
    local tenant_name=$1
    local force=${2:-false}
    
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 delete <tenant-name> [--force]"
        exit 1
    fi
    
    # Check if tenant exists
    if ! id "cdn_${tenant_name}" &>/dev/null; then
        error "Tenant not found: $tenant_name"
        exit 1
    fi
    
    echo ""
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "⚠️  DANGER: DELETE TENANT"
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    warn "This will permanently delete:"
    warn "  • User account: cdn_${tenant_name}"
    warn "  • SFTP files: ${SFTP_DIR}/${tenant_name}/"
    warn "  • Git repository: ${GIT_DIR}/${tenant_name}.git"
    warn "  • CDN files: ${NGINX_DIR}/${tenant_name}/"
    warn "  • Configuration: /etc/cdn/tenants/${tenant_name}.env"
    warn "  • SSH keys: /etc/cdn/keys/${tenant_name}/"
    warn "  • Gitea account (if exists)"
    echo ""
    warn "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    if [[ "$force" != "--force" ]]; then
        read -p "Type 'DELETE ${tenant_name}' in capitals to confirm: " confirmation
        
        if [[ "$confirmation" != "DELETE ${tenant_name}" ]]; then
            log "Deletion cancelled"
            exit 0
        fi
    fi
    
    echo ""
    info "Deleting tenant: $tenant_name"
    echo ""
    
    # Stop autocommit service
    log "Step 1/8: Stopping autocommit service..."
    if systemctl is-active --quiet "cdn-autocommit@${tenant_name}"; then
        systemctl stop "cdn-autocommit@${tenant_name}"
        systemctl disable "cdn-autocommit@${tenant_name}"
        log "✓ Service stopped"
    else
        log "✓ Service not running"
    fi
    
    # Backup before deletion (optional)
    log "Step 2/8: Creating backup before deletion..."
    local backup_dir="${BACKUP_DIR}/${tenant_name}_deleted_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ -d "${SFTP_DIR}/${tenant_name}" ]]; then
        tar -czf "${backup_dir}/sftp_files.tar.gz" -C "${SFTP_DIR}" "${tenant_name}" 2>/dev/null || true
    fi
    
    if [[ -d "${GIT_DIR}/${tenant_name}.git" ]]; then
        tar -czf "${backup_dir}/git_repo.tar.gz" -C "${GIT_DIR}" "${tenant_name}.git" 2>/dev/null || true
    fi
    
    if [[ -f "/etc/cdn/tenants/${tenant_name}.env" ]]; then
        cp "/etc/cdn/tenants/${tenant_name}.env" "${backup_dir}/" 2>/dev/null || true
    fi
    
    log "✓ Backup created: $backup_dir"
    
    # Delete SFTP directory
    log "Step 3/8: Deleting SFTP directory..."
    if [[ -d "${SFTP_DIR}/${tenant_name}" ]]; then
        rm -rf "${SFTP_DIR}/${tenant_name}"
        log "✓ SFTP directory deleted"
    fi
    
    # Delete Git repository
    log "Step 4/8: Deleting Git repository..."
    if [[ -d "${GIT_DIR}/${tenant_name}.git" ]]; then
        rm -rf "${GIT_DIR}/${tenant_name}.git"
        log "✓ Git repository deleted"
    fi
    
    # Delete Nginx deployment
    log "Step 5/8: Deleting CDN files..."
    if [[ -d "${NGINX_DIR}/${tenant_name}" ]]; then
        rm -rf "${NGINX_DIR}/${tenant_name}"
        log "✓ CDN files deleted"
    fi
    
    # Delete user account
    log "Step 6/8: Deleting user account..."
    if id "cdn_${tenant_name}" &>/dev/null; then
        userdel -r "cdn_${tenant_name}" 2>/dev/null || userdel "cdn_${tenant_name}"
        log "✓ User deleted"
    fi
    
    # Delete configuration files
    log "Step 7/8: Deleting configuration files..."
    rm -f "/etc/cdn/tenants/${tenant_name}.env"
    rm -f "/etc/cdn/quotas/${tenant_name}.quota"
    rm -f "/etc/cdn/quotas/alerts_sent/${tenant_name}."*
    log "✓ Configuration deleted"
    
    # Delete SSH keys
    log "Step 8/8: Deleting SSH keys..."
    if [[ -d "/etc/cdn/keys/${tenant_name}" ]]; then
        rm -rf "/etc/cdn/keys/${tenant_name}"
        log "✓ SSH keys deleted"
    fi
    
    # Delete Gitea account (if function available)
    if type gitea_disable_user &>/dev/null; then
        log "Removing Gitea account..."
        gitea_disable_user "$tenant_name" 2>/dev/null || warn "Could not remove Gitea account"
    fi
    
    # Success
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "✓ Tenant Deleted: $tenant_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "Backup available at: $backup_dir"
    echo ""
}

# ==============================================================================
# TENANT SUSPENSION
# ==============================================================================

suspend_tenant() {
    local tenant_name=$1
    
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 suspend <tenant-name>"
        exit 1
    fi
    
    if ! id "cdn_${tenant_name}" &>/dev/null; then
        error "Tenant not found: $tenant_name"
        exit 1
    fi
    
    echo ""
    info "Suspending tenant: $tenant_name"
    echo ""
    
    # Stop autocommit service
    log "Stopping autocommit service..."
    systemctl stop "cdn-autocommit@${tenant_name}" 2>/dev/null || true
    log "✓ Service stopped"
    
    # Lock user account
    log "Locking user account..."
    passwd -l "cdn_${tenant_name}" >/dev/null 2>&1
    log "✓ Account locked"
    
    # Rename SSH authorized_keys
    log "Disabling SSH access..."
    local tenant_home="${SFTP_DIR}/${tenant_name}"
    if [[ -f "${tenant_home}/.ssh/authorized_keys" ]]; then
        mv "${tenant_home}/.ssh/authorized_keys" "${tenant_home}/.ssh/authorized_keys.suspended"
        log "✓ SSH access disabled"
    fi
    
    # Create suspension notice
    cat > "${tenant_home}/ACCOUNT_SUSPENDED.txt" << EOFSUSPEND
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    ACCOUNT SUSPENDED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your CDN account has been temporarily suspended.

Suspended: $(date)
Tenant: ${tenant_name}

Your files remain intact but access has been disabled:
  ✗ SFTP upload/modification disabled
  ✗ Auto-commit service stopped
  ✓ CDN files still publicly accessible (read-only)
  ✓ Git history preserved

To restore access, contact your system administrator.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOFSUSPEND
    
    chmod 444 "${tenant_home}/ACCOUNT_SUSPENDED.txt"
    
    echo ""
    log "✓ Tenant suspended: $tenant_name"
    log "  • SFTP access: DISABLED"
    log "  • Auto-commit: STOPPED"
    log "  • CDN files: STILL ACCESSIBLE (read-only)"
    echo ""
}

# ==============================================================================
# TENANT RESTORATION
# ==============================================================================

restore_tenant() {
    local tenant_name=$1
    
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 restore <tenant-name>"
        exit 1
    fi
    
    if ! id "cdn_${tenant_name}" &>/dev/null; then
        error "Tenant not found: $tenant_name"
        exit 1
    fi
    
    echo ""
    info "Restoring tenant: $tenant_name"
    echo ""
    
    # Unlock user account
    log "Unlocking user account..."
    passwd -u "cdn_${tenant_name}" >/dev/null 2>&1
    log "✓ Account unlocked"
    
    # Restore SSH authorized_keys
    log "Restoring SSH access..."
    local tenant_home="${SFTP_DIR}/${tenant_name}"
    if [[ -f "${tenant_home}/.ssh/authorized_keys.suspended" ]]; then
        mv "${tenant_home}/.ssh/authorized_keys.suspended" "${tenant_home}/.ssh/authorized_keys"
        chmod 644 "${tenant_home}/.ssh/authorized_keys"
        log "✓ SSH access restored"
    fi
    
    # Remove suspension notice
    rm -f "${tenant_home}/ACCOUNT_SUSPENDED.txt"
    
    # Start autocommit service
    log "Starting autocommit service..."
    systemctl start "cdn-autocommit@${tenant_name}"
    sleep 2
    
    if systemctl is-active --quiet "cdn-autocommit@${tenant_name}"; then
        log "✓ Service started"
    else
        warn "Service may not have started correctly"
    fi
    
    echo ""
    log "✓ Tenant restored: $tenant_name"
    log "  • SFTP access: ENABLED"
    log "  • Auto-commit: RUNNING"
    log "  • CDN files: ACCESSIBLE"
    echo ""
}

# ==============================================================================
# TENANT INFORMATION
# ==============================================================================

show_tenant_info() {
    local tenant_name=$1
    
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 info <tenant-name>"
        exit 1
    fi
    
    if ! id "cdn_${tenant_name}" &>/dev/null; then
        error "Tenant not found: $tenant_name"
        exit 1
    fi
    
    # Load tenant config
    local tenant_config="/etc/cdn/tenants/${tenant_name}.env"
    if [[ -f "$tenant_config" ]]; then
        source "$tenant_config"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Tenant Information: $tenant_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "IDENTITY"
    echo "  Name:       $tenant_name"
    echo "  Email:      ${GIT_USER_EMAIL:-N/A}"
    echo "  User:       cdn_${tenant_name}"
    echo "  Created:    ${CREATED_DATE:-Unknown}"
    echo ""
    
    echo "ACCESS"
    echo "  CDN URL:    https://${CDN_DOMAIN}/${tenant_name}/"
    echo "  Gitea:      https://${GITEA_DOMAIN}/${tenant_name}/${tenant_name}"
    echo "  SFTP:       sftp -P ${SFTP_PORT} cdn_${tenant_name}@${CDN_DOMAIN}"
    echo ""
    
    # Account status
    local account_status="ACTIVE"
    if passwd -S "cdn_${tenant_name}" 2>/dev/null | grep -q " L "; then
        account_status="SUSPENDED"
    fi
    echo "STATUS"
    echo "  Account:    $account_status"
    
    # Service status
    if systemctl is-active --quiet "cdn-autocommit@${tenant_name}"; then
        echo "  Service:    RUNNING"
    else
        echo "  Service:    STOPPED"
    fi
    echo ""
    
    # Quota information
    if type show_tenant_quota &>/dev/null; then
        show_tenant_quota "$tenant_name"
    else
        echo "QUOTA"
        echo "  Limit:      ${QUOTA_MB:-100}MB"
        echo ""
    fi
    
    echo "PATHS"
    echo "  SFTP:       ${SFTP_DIR}/${tenant_name}/files"
    echo "  Git:        ${GIT_DIR}/${tenant_name}.git"
    echo "  CDN:        ${NGINX_DIR}/${tenant_name}"
    echo "  Config:     /etc/cdn/tenants/${tenant_name}.env"
    echo "  SSH Key:    /etc/cdn/keys/${tenant_name}/id_ed25519"
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ==============================================================================
# LIST ALL TENANTS
# ==============================================================================

list_tenants() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "All CDN Tenants"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    printf "%-20s %-12s %-12s %-40s\n" "TENANT" "STATUS" "SERVICE" "EMAIL"
    printf "%-20s %-12s %-12s %-40s\n" "------" "------" "-------" "-----"
    
    local count=0
    
    for config_file in /etc/cdn/tenants/*.env; do
        if [[ ! -f "$config_file" ]]; then
            continue
        fi
        
        source "$config_file"
        ((count++))
        
        # Check account status
        local status="ACTIVE"
        if passwd -S "cdn_${TENANT_NAME}" 2>/dev/null | grep -q " L "; then
            status="SUSPENDED"
        fi
        
        # Check service status
        local service="RUNNING"
        if ! systemctl is-active --quiet "cdn-autocommit@${TENANT_NAME}"; then
            service="STOPPED"
        fi
        
        printf "%-20s %-12s %-12s %-40s\n" \
            "$TENANT_NAME" \
            "$status" \
            "$service" \
            "${GIT_USER_EMAIL:-N/A}"
    done
    
    echo ""
    log "Total tenants: $count"
    echo ""
}

# ==============================================================================
# QUOTA MANAGEMENT SHORTCUTS
# ==============================================================================

quota_set() {
    local tenant_name=$1
    local quota_mb=$2
    
    if [[ -z "$tenant_name" ]] || [[ -z "$quota_mb" ]]; then
        error "Tenant name and quota are required"
        echo "Usage: $0 quota-set <tenant-name> <mb>"
        exit 1
    fi
    
    set_tenant_quota "$tenant_name" "$quota_mb"
}

quota_increase() {
    local tenant_name=$1
    local increase_mb=$2
    
    if [[ -z "$tenant_name" ]] || [[ -z "$increase_mb" ]]; then
        error "Tenant name and increase amount are required"
        echo "Usage: $0 quota-increase <tenant-name> <mb>"
        exit 1
    fi
    
    increase_tenant_quota "$tenant_name" "$increase_mb"
}

quota_show() {
    local tenant_name=$1
    
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 quota-show <tenant-name>"
        exit 1
    fi
    
    show_tenant_quota "$tenant_name"
}

# ==============================================================================
# SERVICE MANAGEMENT
# ==============================================================================

restart_service() {
    local tenant_name=$1
    
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 restart <tenant-name>"
        exit 1
    fi
    
    log "Restarting autocommit service for: $tenant_name"
    systemctl restart "cdn-autocommit@${tenant_name}"
    sleep 2
    
    if systemctl is-active --quiet "cdn-autocommit@${tenant_name}"; then
        log "✓ Service restarted successfully"
    else
        error "Service failed to start"
        echo "Check logs: sudo journalctl -u cdn-autocommit@${tenant_name} -n 50"
    fi
}

service_status() {
    local tenant_name=$1
    
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 status <tenant-name>"
        exit 1
    fi
    
    systemctl status "cdn-autocommit@${tenant_name}"
}

service_logs() {
    local tenant_name=$1
    local lines=${2:-50}
    
    if [[ -z "$tenant_name" ]]; then
        error "Tenant name is required"
        echo "Usage: $0 logs <tenant-name> [lines]"
        exit 1
    fi
    
    journalctl -u "cdn-autocommit@${tenant_name}" -n "$lines" --no-pager
}

# ==============================================================================
# USAGE / HELP
# ==============================================================================

show_usage() {
    cat << EOFHELP

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CDN Tenant Manager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE: cdn-tenant-manager <command> [options]

TENANT MANAGEMENT:
  create <name> [email] [quota-mb]    Create new tenant
  delete <name> [--force]             Delete tenant (requires confirmation)
  suspend <name>                      Suspend tenant access
  restore <name>                      Restore suspended tenant
  info <name>                         Show tenant information
  list                                List all tenants

QUOTA MANAGEMENT:
  quota-set <name> <mb>               Set absolute quota
  quota-increase <name> <mb>          Increase quota
  quota-show <name>                   Show quota usage

SERVICE MANAGEMENT:
  restart <name>                      Restart autocommit service
  status <name>                       Show service status
  logs <name> [lines]                 View service logs

EXAMPLES:

  # Create tenant with default settings (100MB quota)
  cdn-tenant-manager create acmecorp

  # Create tenant with custom email and quota
  cdn-tenant-manager create acmecorp admin@acme.com 500

  # Show tenant information
  cdn-tenant-manager info acmecorp

  # Increase quota by 200MB
  cdn-tenant-manager quota-increase acmecorp 200

  # Suspend tenant temporarily
  cdn-tenant-manager suspend acmecorp

  # Restore suspended tenant
  cdn-tenant-manager restore acmecorp

  # Delete tenant (requires confirmation)
  cdn-tenant-manager delete acmecorp

  # Force delete without confirmation
  cdn-tenant-manager delete acmecorp --force

  # List all tenants
  cdn-tenant-manager list

  # View autocommit logs
  cdn-tenant-manager logs acmecorp 100

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For more information, see: /opt/scripts/cdn/INSTALL.md

EOFHELP
}

# ==============================================================================
# MAIN COMMAND ROUTER
# ==============================================================================

main() {
    local command=$1
    shift
    
    case "$command" in
        create)
            create_tenant "$@"
            ;;
        delete)
            delete_tenant "$@"
            ;;
        suspend)
            suspend_tenant "$@"
            ;;
        restore)
            restore_tenant "$@"
            ;;
        info)
            show_tenant_info "$@"
            ;;
        list)
            list_tenants
            ;;
        quota-set)
            quota_set "$@"
            ;;
        quota-increase)
            quota_increase "$@"
            ;;
        quota-show)
            quota_show "$@"
            ;;
        restart)
            restart_service "$@"
            ;;
        status)
            service_status "$@"
            ;;
        logs)
            service_logs "$@"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
fi

main "$@"
