#!/bin/bash
# File: /opt/scripts/cdn/helpers/cdn-quota-functions.sh (installed to /usr/local/bin/cdn-quota-functions)
# Purpose: Disk quota enforcement and monitoring for CDN tenants
#          Usage calculation, quota management, checking, and enforcement

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
    exit 1
fi
source "$CONFIG_FILE"

# Validate critical paths exist
for required_var in CDN_DOMAIN BASE_DIR SFTP_DIR GIT_DIR NGINX_DIR LOG_DIR ALERT_EMAIL; do
    if [[ -z "${!required_var}" ]]; then
        error "Required configuration variable not set: $required_var"
        exit 1
    fi
done

# Paths
QUOTA_DIR="/etc/cdn/quotas"
ALERT_SENT_DIR="${QUOTA_DIR}/alerts_sent"

# Ensure directories exist
mkdir -p "$QUOTA_DIR"
mkdir -p "$ALERT_SENT_DIR"

#=============================================================================
# USAGE CALCULATION
#=============================================================================

# Calculate actual disk usage for a tenant
# Returns: usage in bytes
# Policy: SFTP + Nginx only (Git repo excluded)
calculate_tenant_usage() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    # SFTP files (user uploads)
    local sftp_dir="${SFTP_DIR}/${tenant_name}/files"
    local sftp_usage=0
    if [[ -d "$sftp_dir" ]]; then
        sftp_usage=$(du -sb "$sftp_dir" 2>/dev/null | awk '{print $1}' || echo "0")
    fi
    
    # Nginx files (deployed content)
    local nginx_dir="${NGINX_DIR}/${tenant_name}"
    local nginx_usage=0
    if [[ -d "$nginx_dir" ]]; then
        nginx_usage=$(du -sb "$nginx_dir" 2>/dev/null | awk '{print $1}' || echo "0")
    fi
    
    # Total usage (Git repo NOT included)
    local total_usage=$((sftp_usage + nginx_usage))
    
    echo "$total_usage"
}

# Get quota for tenant in bytes
get_tenant_quota_bytes() {
    local tenant_name=$1
    
    local quota_file="${QUOTA_DIR}/${tenant_name}.quota"
    
    if [[ -f "$quota_file" ]]; then
        cat "$quota_file"
    else
        # Default: 100MB if no quota file exists
        echo "104857600"
    fi
}

# Get quota from tenant config (in MB)
get_tenant_quota_mb_from_config() {
    local tenant_name=$1
    local config_file="/etc/cdn/tenants/${tenant_name}.env"
    
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        echo "${QUOTA_MB:-100}"
    else
        echo "100"
    fi
}

#=============================================================================
# QUOTA MANAGEMENT
#=============================================================================

# Set tenant quota (creates quota file)
set_tenant_quota() {
    local tenant_name=$1
    local quota_mb=$2
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    [[ -z "$quota_mb" ]] && { error "Quota (MB) required"; return 1; }
    
    # Validate quota
    if [[ ! "$quota_mb" =~ ^[0-9]+$ ]]; then
        error "Quota must be a positive integer (MB)"
        return 1
    fi
    
    if [[ "$quota_mb" -lt 1 ]]; then
        error "Quota must be at least 1MB"
        return 1
    fi
    
    local quota_bytes=$((quota_mb * 1024 * 1024))
    local quota_file="${QUOTA_DIR}/${tenant_name}.quota"
    
    # Write quota in bytes
    echo "$quota_bytes" > "$quota_file"
    chmod 644 "$quota_file"
    
    log "✓ Quota file created: $quota_file"
    log "  Tenant: $tenant_name"
    log "  Quota: ${quota_mb}MB (${quota_bytes} bytes)"
    
    # Also update tenant config file if cdn-tenant-helpers is available
    if type update_quota &>/dev/null; then
        update_quota "$tenant_name" "$quota_mb" 2>/dev/null || true
    fi
    
    # Clear any previous alert flags
    rm -f "${ALERT_SENT_DIR}/${tenant_name}."* 2>/dev/null || true
    
    return 0
}

# Set absolute quota (same as set_tenant_quota, for consistency with commands)
set_absolute_quota() {
    set_tenant_quota "$@"
}

# Increase tenant quota
increase_tenant_quota() {
    local tenant_name=$1
    local increase_mb=$2
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    [[ -z "$increase_mb" ]] && { error "Increase amount (MB) required"; return 1; }
    
    if [[ ! "$increase_mb" =~ ^[0-9]+$ ]]; then
        error "Increase amount must be a positive integer (MB)"
        return 1
    fi
    
    # Get current quota
    local current_mb=$(get_tenant_quota_mb_from_config "$tenant_name")
    local new_mb=$((current_mb + increase_mb))
    
    log "Increasing quota for $tenant_name: ${current_mb}MB → ${new_mb}MB (+${increase_mb}MB)"
    
    set_tenant_quota "$tenant_name" "$new_mb"
}

# Decrease tenant quota (with safety check to prevent data loss)
decrease_tenant_quota() {
    local tenant_name=$1
    local decrease_mb=$2
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    [[ -z "$decrease_mb" ]] && { error "Decrease amount (MB) required"; return 1; }
    
    if [[ ! "$decrease_mb" =~ ^[0-9]+$ ]]; then
        error "Decrease amount must be a positive integer (MB)"
        return 1
    fi
    
    # Get current quota
    local current_mb=$(get_tenant_quota_mb_from_config "$tenant_name")
    local proposed_new_mb=$((current_mb - decrease_mb))
    
    # Basic validation: cannot go below 1MB
    if [[ $proposed_new_mb -lt 1 ]]; then
        error "Cannot decrease quota below 1MB (would result in ${proposed_new_mb}MB)"
        return 1
    fi
    
    # SAFETY CHECK: Calculate current usage
    log "Performing safety check before decreasing quota..."
    
    local current_usage_bytes=$(calculate_tenant_usage "$tenant_name")
    local current_usage_mb=$((current_usage_bytes / 1024 / 1024))
    
    log "Current usage: ${current_usage_mb}MB"
    log "Current quota: ${current_mb}MB"
    log "Proposed new quota: ${proposed_new_mb}MB"
    
    # Check if new quota would be less than current usage
    if [[ $proposed_new_mb -lt $current_usage_mb ]]; then
        error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        error "QUOTA DECREASE BLOCKED - Would Cause Data Loss!"
        error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        error ""
        error "Tenant:           $tenant_name"
        error "Current usage:    ${current_usage_mb}MB"
        error "Current quota:    ${current_mb}MB"
        error "Proposed quota:   ${proposed_new_mb}MB (decrease by ${decrease_mb}MB)"
        error ""
        error "The proposed quota (${proposed_new_mb}MB) is LESS than current usage (${current_usage_mb}MB)."
        error "This would put the tenant over quota and potentially cause data loss."
        error ""
        error "Required actions:"
        error "  1. Tenant must free up at least $((current_usage_mb - proposed_new_mb))MB of space"
        error "  2. Current usage must be reduced to below ${proposed_new_mb}MB"
        error "  3. Then retry the quota decrease"
        error ""
        error "Alternative: Increase quota instead of decreasing"
        error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        return 1
    fi
    
    # Calculate headroom
    local headroom_mb=$((proposed_new_mb - current_usage_mb))
    local headroom_pct=$((headroom_mb * 100 / proposed_new_mb))
    
    # Warn if very tight (less than 10% headroom)
    if [[ $headroom_pct -lt 10 ]]; then
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warn "WARNING: Low Headroom After Decrease"
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warn ""
        warn "Tenant:           $tenant_name"
        warn "Current usage:    ${current_usage_mb}MB"
        warn "Current quota:    ${current_mb}MB"
        warn "New quota:        ${proposed_new_mb}MB"
        warn "Headroom:         ${headroom_mb}MB (${headroom_pct}%)"
        warn ""
        warn "The tenant will have only ${headroom_mb}MB of free space after this decrease."
        warn "They will be at $((100 - headroom_pct))% of their new quota."
        warn ""
        
        echo -n "Are you sure you want to proceed? Type 'yes' to confirm: "
        read -r confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            log "Quota decrease cancelled by user"
            return 0
        fi
    fi
    
    # Safe to proceed
    log "✓ Safety check passed: Decreasing quota is safe"
    log "  Current usage: ${current_usage_mb}MB"
    log "  New quota: ${proposed_new_mb}MB"
    log "  Headroom: ${headroom_mb}MB (${headroom_pct}% free space)"
    
    log "Decreasing quota for $tenant_name: ${current_mb}MB → ${proposed_new_mb}MB (-${decrease_mb}MB)"
    
    set_tenant_quota "$tenant_name" "$proposed_new_mb"
    
    log "✓ Quota decreased successfully"
    log "  Tenant now has ${headroom_mb}MB of free space (${headroom_pct}% of quota)"
}

#=============================================================================
# QUOTA CHECKING AND ENFORCEMENT
#=============================================================================

# Show tenant quota and usage
show_tenant_quota() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    # Get quota
    local quota_bytes=$(get_tenant_quota_bytes "$tenant_name")
    local quota_mb=$((quota_bytes / 1024 / 1024))
    
    # Calculate usage
    local total_usage=$(calculate_tenant_usage "$tenant_name")
    local usage_mb=$((total_usage / 1024 / 1024))
    local usage_pct=$((total_usage * 100 / quota_bytes))
    
    # Get breakdown
    local sftp_dir="${SFTP_DIR}/${tenant_name}/files"
    local nginx_dir="${NGINX_DIR}/${tenant_name}"
    
    local sftp_usage=0
    [[ -d "$sftp_dir" ]] && sftp_usage=$(du -sb "$sftp_dir" 2>/dev/null | awk '{print $1}' || echo "0")
    
    local nginx_usage=0
    [[ -d "$nginx_dir" ]] && nginx_usage=$(du -sb "$nginx_dir" 2>/dev/null | awk '{print $1}' || echo "0")
    
    local sftp_mb=$((sftp_usage / 1024 / 1024))
    local nginx_mb=$((nginx_usage / 1024 / 1024))
    
    # Status indicator
    local status="✓ OK"
    local status_color="$GREEN"
    
    if [[ $usage_pct -ge 100 ]]; then
        status="🚨 OVER QUOTA"
        status_color="$RED"
    elif [[ $usage_pct -ge 90 ]]; then
        status="⚠️  CRITICAL"
        status_color="$RED"
    elif [[ $usage_pct -ge 80 ]]; then
        status="⚠️  WARNING"
        status_color="$YELLOW"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Tenant Quota Status: $tenant_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "Status:        ${status_color}${status}${NC}"
    echo "Quota:         ${quota_mb}MB"
    echo "Usage:         ${usage_mb}MB (${usage_pct}%)"
    echo ""
    echo "Breakdown:"
    echo "  SFTP files:   ${sftp_mb}MB"
    echo "  Nginx files:  ${nginx_mb}MB"
    echo "  ────────────────────"
    echo "  Total:        ${usage_mb}MB"
    echo ""
    echo "Note: Git repository usage not counted (infrastructure cost)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Check tenant quota and enforce if needed
check_tenant_quota() {
    local tenant_name=$1
    local silent=${2:-false}  # Optional: silent mode (no output except errors)
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    # Get quota
    local quota_bytes=$(get_tenant_quota_bytes "$tenant_name")
    local quota_mb=$((quota_bytes / 1024 / 1024))
    
    # Calculate usage
    local total_usage=$(calculate_tenant_usage "$tenant_name")
    local usage_mb=$((total_usage / 1024 / 1024))
    local usage_pct=$((total_usage * 100 / quota_bytes))
    
    [[ "$silent" != "true" ]] && log "Checking quota for $tenant_name: ${usage_mb}MB / ${quota_mb}MB (${usage_pct}%)"
    
    # Determine status and actions
    if [[ $usage_pct -ge 100 ]]; then
        error "Tenant $tenant_name OVER QUOTA: ${usage_pct}% (${usage_mb}MB / ${quota_mb}MB)"
        send_quota_alert "$tenant_name" "critical" "$usage_pct" "$usage_mb" "$quota_mb"
        return 1
        
    elif [[ $usage_pct -ge 90 ]]; then
        warn "Tenant $tenant_name at CRITICAL level: ${usage_pct}% (${usage_mb}MB / ${quota_mb}MB)"
        send_quota_alert "$tenant_name" "critical" "$usage_pct" "$usage_mb" "$quota_mb"
        return 1
        
    elif [[ $usage_pct -ge 80 ]]; then
        warn "Tenant $tenant_name at WARNING level: ${usage_pct}% (${usage_mb}MB / ${quota_mb}MB)"
        send_quota_alert "$tenant_name" "warning" "$usage_pct" "$usage_mb" "$quota_mb"
        return 1
        
    else
        [[ "$silent" != "true" ]] && log "✓ Tenant $tenant_name quota OK: ${usage_pct}%"
        return 0
    fi
}

# Check all tenant quotas
check_all_quotas() {
    log "Checking quotas for all tenants..."
    echo ""
    
    local total=0
    local ok=0
    local warning=0
    local critical=0
    local over=0
    
    for tenant_dir in "${SFTP_DIR}"/*; do
        if [[ ! -d "$tenant_dir" ]]; then
            continue
        fi
        
        local tenant=$(basename "$tenant_dir")
        
        # Skip if not a valid tenant
        if ! id "cdn_${tenant}" &>/dev/null 2>&1; then
            continue
        fi
        
        ((total++))
        
        # Get quota and usage
        local quota_bytes=$(get_tenant_quota_bytes "$tenant")
        local quota_mb=$((quota_bytes / 1024 / 1024))
        local usage=$(calculate_tenant_usage "$tenant")
        local usage_mb=$((usage / 1024 / 1024))
        local usage_pct=$((usage * 100 / quota_bytes))
        
        # Categorize
        local status="OK"
        if [[ $usage_pct -ge 100 ]]; then
            status="OVER"
            ((over++))
        elif [[ $usage_pct -ge 90 ]]; then
            status="CRITICAL"
            ((critical++))
        elif [[ $usage_pct -ge 80 ]]; then
            status="WARNING"
            ((warning++))
        else
            ((ok++))
        fi
        
        printf "%-20s %3d%% (%4dMB / %4dMB) [%s]\n" \
            "$tenant" "$usage_pct" "$usage_mb" "$quota_mb" "$status"
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Summary:"
    echo "  Total tenants:      $total"
    echo "  OK (<80%):          $ok"
    echo "  Warning (80-89%):   $warning"
    echo "  Critical (90-99%):  $critical"
    echo "  Over quota (100%+): $over"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#=============================================================================
# ALERT SYSTEM
#=============================================================================

# Send quota alert email (with rate limiting to prevent spam)
send_quota_alert() {
    local tenant_name=$1
    local alert_level=$2  # "warning" or "critical"
    local usage_pct=$3
    local usage_mb=$4
    local quota_mb=$5
    
    # Check if SMTP is enabled
    if [[ "$SMTP_ENABLED" != "true" ]] || [[ -z "$ALERT_EMAIL" ]]; then
        return 0
    fi
    
    # Rate limiting: don't send same alert twice within 24 hours
    local alert_flag="${ALERT_SENT_DIR}/${tenant_name}.${alert_level}"
    local current_time=$(date +%s)
    
    if [[ -f "$alert_flag" ]]; then
        local last_alert_time=$(cat "$alert_flag")
        local time_diff=$((current_time - last_alert_time))
        
        # 24 hours = 86400 seconds
        if [[ $time_diff -lt 86400 ]]; then
            # Alert already sent recently, skip
            return 0
        fi
    fi
    
    # Get tenant email from config (using GIT_USER_EMAIL)
    local tenant_email=""
    local tenant_config="/etc/cdn/tenants/${tenant_name}.env"
    
    if [[ -f "$tenant_config" ]]; then
        source "$tenant_config"
        tenant_email="${GIT_USER_EMAIL}"  # Git email IS the contact email
    fi
    
    # Prepare email subject and body
    local subject
    local emoji
    
    if [[ "$alert_level" == "critical" ]]; then
        subject="🚨 CDN Quota Alert: ${tenant_name} at ${usage_pct}% (CRITICAL)"
        emoji="🚨"
    else
        subject="⚠️ CDN Quota Alert: ${tenant_name} at ${usage_pct}% (Warning)"
        emoji="⚠️"
    fi
    
    local email_body=$(cat << EOFBODY1
CDN Quota Alert
═══════════════════════════════════════════════════════════

${emoji} QUOTA ${alert_level^^}

Tenant:        ${tenant_name}
Usage:         ${usage_mb}MB / ${quota_mb}MB (${usage_pct}%)
Status:        ${alert_level^^}

CDN URL:       https://${CDN_DOMAIN}/${tenant_name}/
Gitea Portal:  https://${GITEA_DOMAIN}

Action Required:
───────────────────────────────────────────────────────────
The tenant "${tenant_name}" is approaching or has exceeded
their disk quota limit.

Recommended actions:
- Review and delete unnecessary files
- Contact administrator to increase quota
- Archive old content

Current quota can be increased with:
  sudo cdn-tenant-manager quota-increase ${tenant_name} <MB>

Or set new absolute quota:
  sudo cdn-tenant-manager quota-set ${tenant_name} <MB>

───────────────────────────────────────────────────────────
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Server: $(hostname)

Note: This alert will not be sent again for 24 hours unless
the status changes.
EOFBODY1
)
    
    # Build recipient list
    local recipients=""
    
    # Add tenant email if available
    if [[ -n "$tenant_email" ]]; then
        recipients="$tenant_email"
    fi
    
    # Always include admin
    if [[ -n "$recipients" ]]; then
        recipients="${recipients},${ALERT_EMAIL}"
    else
        recipients="${ALERT_EMAIL}"
    fi
    
    # Send email
    if echo "$email_body" | mail -s "$subject" "$recipients" 2>/dev/null; then
        log "✓ Quota alert email sent for $tenant_name ($alert_level)"
        
        # Record that alert was sent
        echo "$current_time" > "$alert_flag"
    else
        warn "Failed to send quota alert email for $tenant_name"
    fi
}

# Send quota enforcement alert email
send_quota_enforcement_alert() {
    local tenant_name=$1
    local action=$2  # "enforced" or "unenforced"
    local usage_pct=$3
    local usage_mb=$4
    local quota_mb=$5
    
    # Check if SMTP is enabled
    if [[ "$SMTP_ENABLED" != "true" ]] || [[ -z "$ALERT_EMAIL" ]]; then
        warn "SMTP not enabled, enforcement alert not sent for: $tenant_name"
        return 0
    fi
    
    # Get tenant email from config (using GIT_USER_EMAIL)
    local tenant_email=""
    local tenant_config="/etc/cdn/tenants/${tenant_name}.env"
    
    if [[ -f "$tenant_config" ]]; then
        source "$tenant_config"
        tenant_email="${GIT_USER_EMAIL}"  # Git email IS the contact email
    fi
    
    # Prepare email based on action
    local subject
    local email_body
    
    if [[ "$action" == "enforced" ]]; then
        subject="🚨 URGENT: Your CDN Account is Now READ-ONLY - ${tenant_name}"
        email_body=$(cat << EOFBODY2
CDN QUOTA ENFORCEMENT NOTICE
═══════════════════════════════════════════════════════════

🚨 YOUR ACCOUNT IS NOW READ-ONLY

Tenant:        ${tenant_name}
Usage:         ${usage_mb}MB / ${quota_mb}MB (${usage_pct}%)
Status:        ENFORCED (Read-Only)

CDN URL:       https://${CDN_DOMAIN}/${tenant_name}/
Gitea Portal:  https://${GITEA_DOMAIN}

WHAT HAPPENED?
───────────────────────────────────────────────────────────
Your account has exceeded its disk quota limit. To prevent
system issues, your upload directory has been made READ-ONLY.

CURRENT RESTRICTIONS:
───────────────────────────────────────────────────────────
  ✗ You CANNOT upload new files
  ✗ You CANNOT modify existing files
  ✓ You CAN read and download files
  ✓ You CAN delete files to free up space

HOW TO RESTORE ACCESS:
───────────────────────────────────────────────────────────

Option 1: Free Up Space (Immediate)
  1. Connect via SFTP: sftp -P ${SFTP_PORT:-22} cdn_${tenant_name}@${CDN_DOMAIN}
  2. Delete unnecessary files to reduce usage below ${quota_mb}MB
  3. Contact administrator to verify and restore access

Option 2: Request Quota Increase
  1. Contact your system administrator
  2. Request a quota increase to accommodate your needs
  3. Administrator will evaluate and approve if appropriate

IMPORTANT NOTES:
───────────────────────────────────────────────────────────
- Your existing files are still accessible via CDN
- No data has been deleted
- You can delete files via SFTP to free up space
- Once usage is below quota, access can be restored

NEED HELP?
───────────────────────────────────────────────────────────
Contact your system administrator at: ${ALERT_EMAIL}

View your files online: https://${GITEA_DOMAIN}

───────────────────────────────────────────────────────────
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Server: $(hostname)

This is an automated message. Please do not reply to this email.
Contact your administrator for assistance.
EOFBODY2
)
    else  # action == "unenforced"
        subject="✓ CDN Account Access Restored - ${tenant_name}"
        email_body=$(cat << EOFBODY3
CDN QUOTA ENFORCEMENT REMOVED
═══════════════════════════════════════════════════════════

✓ YOUR ACCOUNT ACCESS HAS BEEN RESTORED

Tenant:        ${tenant_name}
Usage:         ${usage_mb}MB / ${quota_mb}MB (${usage_pct}%)
Status:        ACTIVE (Read-Write)

CDN URL:       https://${CDN_DOMAIN}/${tenant_name}/
Gitea Portal:  https://${GITEA_DOMAIN}

WHAT HAPPENED?
───────────────────────────────────────────────────────────
Your account's read-only restriction has been lifted.
You now have full read-write access again.

CURRENT ACCESS:
───────────────────────────────────────────────────────────
  ✓ You CAN upload new files
  ✓ You CAN modify existing files
  ✓ You CAN read and download files
  ✓ You CAN delete files

CURRENT STATUS:
───────────────────────────────────────────────────────────
  Current Usage:  ${usage_mb}MB
  Quota Limit:    ${quota_mb}MB
  Usage:          ${usage_pct}%
  Free Space:     $((quota_mb - usage_mb))MB

RECOMMENDATIONS:
───────────────────────────────────────────────────────────
- Monitor your usage regularly via Gitea portal
- Delete old or unnecessary files periodically
- Contact administrator if you need more space
- Keep usage below 80% to avoid future restrictions

TO PREVENT FUTURE RESTRICTIONS:
───────────────────────────────────────────────────────────
- Stay below ${quota_mb}MB usage
- Clean up old files regularly
- Request quota increase if needed consistently
- Monitor email alerts for quota warnings

CONNECT TO YOUR ACCOUNT:
───────────────────────────────────────────────────────────
  SFTP: sftp -P ${SFTP_PORT:-22} cdn_${tenant_name}@${CDN_DOMAIN}
  Web:  https://${GITEA_DOMAIN}

───────────────────────────────────────────────────────────
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Server: $(hostname)

This is an automated message. Please do not reply to this email.
Contact your administrator for assistance at: ${ALERT_EMAIL}
EOFBODY3
)
    fi
    
    # Build recipient list
    local recipients=""
    
    # Add tenant email if set and valid
    if [[ -n "$tenant_email" ]]; then
        recipients="$tenant_email"
        log "Sending enforcement notification to tenant: $tenant_email"
    fi
    
    # Always CC administrator
    if [[ -n "$recipients" ]]; then
        recipients="${recipients},${ALERT_EMAIL}"
    else
        # Tenant email not available, send to admin only
        recipients="${ALERT_EMAIL}"
        warn "No tenant email configured, sending to admin only: ${ALERT_EMAIL}"
    fi
    
    # Send the email
    if echo "$email_body" | mail -s "$subject" "$recipients" 2>/dev/null; then
        log "✓ Quota enforcement alert sent to: $recipients"
    else
        warn "Failed to send enforcement alert email"
    fi
    
    # Create a flag file to track enforcement notifications
    local enforcement_flag="${ALERT_SENT_DIR}/${tenant_name}.enforcement.${action}"
    echo "$(date +%s)" > "$enforcement_flag"
}

#=============================================================================
# ENFORCEMENT ACTIONS
#=============================================================================

# Enforce quota (make SFTP directory read-only if over quota)
enforce_quota_readonly() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    local sftp_files="${SFTP_DIR}/${tenant_name}/files"
    
    if [[ ! -d "$sftp_files" ]]; then
        error "SFTP directory not found: $sftp_files"
        return 1
    fi
    
    # Get current quota and usage for email
    local quota_bytes=$(get_tenant_quota_bytes "$tenant_name")
    local quota_mb=$((quota_bytes / 1024 / 1024))
    local usage_bytes=$(calculate_tenant_usage "$tenant_name")
    local usage_mb=$((usage_bytes / 1024 / 1024))
    local usage_pct=$((usage_bytes * 100 / quota_bytes))
    
    # Make directory read-only
    chmod 555 "$sftp_files"
    
    # Create notice file
    cat > "${sftp_files}/QUOTA_EXCEEDED.txt" << EOT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                          QUOTA EXCEEDED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your disk quota has been exceeded.

This directory is now READ-ONLY until you:
1. Delete unnecessary files to free up space, OR
2. Contact your administrator to increase your quota

Current actions are restricted:
  ✗ Cannot upload new files
  ✗ Cannot modify existing files
  ✓ Can read and download files
  ✓ Can delete files to free space

To check your current usage:
  Contact your system administrator

For quota increase requests:
  Contact your system administrator

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOT
    
    chmod 444 "${sftp_files}/QUOTA_EXCEEDED.txt"
    
    warn "✓ Quota enforcement: $tenant_name directory set to READ-ONLY"
    
    # Send email alert to tenant
    send_quota_enforcement_alert "$tenant_name" "enforced" "$usage_pct" "$usage_mb" "$quota_mb"
    
    # Also log to tenant's autocommit log if it exists
    local tenant_log="${LOG_DIR}/${tenant_name}-autocommit.log"
    if [[ -f "$tenant_log" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - QUOTA ENFORCED: Directory set to READ-ONLY (${usage_pct}%)" >> "$tenant_log"
    fi
    
    return 0
}

# Remove quota enforcement (restore write access)
unenforce_quota_readonly() {
    local tenant_name=$1
    
    [[ -z "$tenant_name" ]] && { error "Tenant name required"; return 1; }
    
    local sftp_files="${SFTP_DIR}/${tenant_name}/files"
    local tenant_user="cdn_${tenant_name}"
    
    if [[ ! -d "$sftp_files" ]]; then
        error "SFTP directory not found: $sftp_files"
        return 1
    fi
    
    # Get current quota and usage for email
    local quota_bytes=$(get_tenant_quota_bytes "$tenant_name")
    local quota_mb=$((quota_bytes / 1024 / 1024))
    local usage_bytes=$(calculate_tenant_usage "$tenant_name")
    local usage_mb=$((usage_bytes / 1024 / 1024))
    local usage_pct=$((usage_bytes * 100 / quota_bytes))
    
    # Restore write permissions
    chmod 755 "$sftp_files"
    chown -R "${tenant_user}:${tenant_user}" "$sftp_files"
    
    # Remove notice file
    rm -f "${sftp_files}/QUOTA_EXCEEDED.txt"
    
    log "✓ Quota enforcement removed: $tenant_name directory restored to READ-WRITE"
    
    # Send email notification about restoration
    send_quota_enforcement_alert "$tenant_name" "unenforced" "$usage_pct" "$usage_mb" "$quota_mb"
    
    # Also log to tenant's autocommit log if it exists
    local tenant_log="${LOG_DIR}/${tenant_name}-autocommit.log"
    if [[ -f "$tenant_log" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - QUOTA ENFORCEMENT REMOVED: Directory restored to READ-WRITE (${usage_pct}%)" >> "$tenant_log"
    fi
    
    return 0
}

#=============================================================================
# CLEANUP FUNCTIONS
#=============================================================================

# Clean up old alert flags (older than 7 days)
cleanup_old_alerts() {
    find "$ALERT_SENT_DIR" -type f -mtime +7 -delete 2>/dev/null || true
    log "✓ Cleaned up old alert flags"
}

#=============================================================================
# COMMAND ROUTER (if executed directly)
#=============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        set)
            set_tenant_quota "$2" "$3"
            ;;
        show)
            show_tenant_quota "$2"
            ;;
        check)
            check_tenant_quota "$2"
            ;;
        check-all)
            check_all_quotas
            ;;
        increase)
            increase_tenant_quota "$2" "$3"
            ;;
        decrease)
            decrease_tenant_quota "$2" "$3"
            ;;
        enforce)
            enforce_quota_readonly "$2"
            ;;
        unenforce)
            unenforce_quota_readonly "$2"
            ;;
        cleanup)
            cleanup_old_alerts
            ;;
        *)
            echo "CDN Quota Management Functions"
            echo ""
            echo "Usage: $0 {command} [options]"
            echo ""
            echo "Commands:"
            echo "  set <tenant> <mb>       Set quota for tenant"
            echo "  show <tenant>           Show quota and usage"
            echo "  check <tenant>          Check quota and send alerts"
            echo "  check-all               Check all tenant quotas"
            echo "  increase <tenant> <mb>  Increase quota"
            echo "  decrease <tenant> <mb>  Decrease quota (with safety check)"
            echo "  enforce <tenant>        Make directory read-only + send alert"
            echo "  unenforce <tenant>      Restore write access + send alert"
            echo "  cleanup                 Clean old alert flags"
            echo ""
            echo "Note: This script is meant to be sourced by cdn-tenant-manager.sh"
            echo "      Contact email uses GIT_USER_EMAIL from tenant config"
            echo ""
            exit 1
            ;;
    esac
fi
