#!/bin/bash
# File: /opt/scripts/cdn/monitoring/cdn-quota-monitor-realtime.sh
# Purpose: Real-time quota monitoring using inotify
# Type: Per-tenant daemon (runs continuously)
# Triggered by: systemd service cdn-quota-monitor@<tenant>.service
# Installed to: /usr/local/bin/cdn-quota-monitor-realtime

set -euo pipefail

# Configuration
SCRIPT_NAME="cdn-quota-monitor-realtime"
VERSION="1.0.0"
TENANT="${1:-}"

# FIXED: Core library paths - use correct installed paths
CDN_QUOTA_FUNCTIONS="/usr/local/bin/cdn-quota-functions"
CDN_TENANT_HELPERS="/usr/local/bin/cdn-tenant-helpers"

# Directories (these will be set from /etc/cdn/config.env)
CONFIG_FILE="/etc/cdn/config.env"
LOG_DIR="/var/log/cdn"
CACHE_DIR="/var/cache/cdn/quota"

# Monitoring configuration
DEBOUNCE_SECONDS=3
CHECK_INTERVAL=300  # Fallback check every 5 minutes
ALERT_COOLDOWN=3600 # 1 hour between duplicate alerts

# Alert thresholds (aligned with cdn-quota-functions)
THRESHOLD_WARNING=80
THRESHOLD_CRITICAL=90
THRESHOLD_FULL=100

# ============================================================================
# INITIALIZATION
# ============================================================================

# Validate tenant argument
if [[ -z "$TENANT" ]]; then
    echo "ERROR: Tenant name required" >&2
    echo "Usage: $0 <tenant>" >&2
    exit 1
fi

# Validate tenant format
if [[ ! "$TENANT" =~ ^[a-z0-9_-]+$ ]]; then
    echo "ERROR: Invalid tenant name: $TENANT" >&2
    exit 1
fi

# Load CDN configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: CDN configuration not found: $CONFIG_FILE" >&2
    exit 1
fi
source "$CONFIG_FILE"

# Source core libraries
if [[ ! -f "$CDN_QUOTA_FUNCTIONS" ]]; then
    echo "ERROR: Core library not found: $CDN_QUOTA_FUNCTIONS" >&2
    echo "Please ensure cdn-initial-setup.sh completed successfully" >&2
    exit 1
fi
source "$CDN_QUOTA_FUNCTIONS"

if [[ -f "$CDN_TENANT_HELPERS" ]]; then
    source "$CDN_TENANT_HELPERS"
fi

# Tenant directories (use paths from config)
TENANT_SFTP="${SFTP_DIR}/${TENANT}/files"
TENANT_NGINX="${NGINX_DIR}/${TENANT}"
TENANT_LOG="${LOG_DIR}/${TENANT}_quota_monitor.log"
TENANT_STATE="${CACHE_DIR}/${TENANT}.state"
TENANT_ALERT_CACHE="${CACHE_DIR}/${TENANT}.alerts"

# Create required directories
mkdir -p "$LOG_DIR" "$CACHE_DIR"
mkdir -p "$(dirname "$TENANT_STATE")"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] [$TENANT] $message" | tee -a "$TENANT_LOG"
    
    # Also log to syslog for systemd journal
    logger -t "cdn-quota-monitor-${TENANT}" -p "user.${level}" "$message"
}

log_info() { log_message "info" "$@"; }
log_warn() { log_message "warning" "$@"; }
log_error() { log_message "error" "$@"; }
log_debug() { 
    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_message "debug" "$@"
    fi
}

# ============================================================================
# ALERT MANAGEMENT
# ============================================================================

should_send_alert() {
    local alert_key="$1"
    local alert_file="${TENANT_ALERT_CACHE}.${alert_key}"
    
    # Check if alert was sent recently
    if [[ -f "$alert_file" ]]; then
        local last_alert
        last_alert=$(stat -c %Y "$alert_file" 2>/dev/null || echo 0)
        local now
        now=$(date +%s)
        local elapsed=$((now - last_alert))
        
        if [[ $elapsed -lt $ALERT_COOLDOWN ]]; then
            log_debug "Alert cooldown active for $alert_key (${elapsed}s/${ALERT_COOLDOWN}s)"
            return 1
        fi
    fi
    
    return 0
}

mark_alert_sent() {
    local alert_key="$1"
    local alert_file="${TENANT_ALERT_CACHE}.${alert_key}"
    touch "$alert_file"
    log_debug "Alert marked as sent: $alert_key"
}

send_monitor_alert() {
    local level="$1"      # warning, critical
    local usage_pct="$2"
    local used_mb="$3"
    local quota_mb="$4"
    
    local alert_key="${level}_${usage_pct}"
    
    # Check cooldown
    if ! should_send_alert "$alert_key"; then
        return 0
    fi
    
    # Use core library's alert function if available
    if declare -f send_quota_alert &>/dev/null; then
        send_quota_alert "$TENANT" "$level" "$usage_pct" "$used_mb" "$quota_mb"
        mark_alert_sent "$alert_key"
        log_info "Alert sent via cdn-quota-functions: $level at ${usage_pct}%"
    else
        log_warn "cdn-quota-functions alert system not available"
    fi
}

# ============================================================================
# QUOTA CHECK & ENFORCEMENT
# ============================================================================

check_and_enforce_quota() {
    log_debug "Starting quota check for $TENANT"
    
    # Calculate current usage via core library
    local usage_bytes
    usage_bytes=$(calculate_tenant_usage "$TENANT" 2>/dev/null || echo "0")
    
    if [[ "$usage_bytes" == "0" ]] || [[ -z "$usage_bytes" ]]; then
        log_warn "Failed to calculate usage, skipping check"
        return 1
    fi
    
    # Get quota limit via core library
    local quota_bytes
    quota_bytes=$(get_tenant_quota_bytes "$TENANT" 2>/dev/null || echo "0")
    
    if [[ "$quota_bytes" == "0" ]] || [[ -z "$quota_bytes" ]]; then
        log_debug "No quota set for tenant, skipping enforcement"
        return 0
    fi
    
    # Calculate percentage
    local usage_pct
    usage_pct=$(awk -v used="$usage_bytes" -v quota="$quota_bytes" \
        'BEGIN { printf "%.0f", (used / quota) * 100 }')
    
    # Convert to MB for display
    local used_mb=$((usage_bytes / 1024 / 1024))
    local quota_mb=$((quota_bytes / 1024 / 1024))
    
    log_info "Quota check: ${used_mb}MB/${quota_mb}MB (${usage_pct}%)"
    
    # Store current state
    cat > "$TENANT_STATE" <<-EOF
	TENANT=$TENANT
	USAGE_BYTES=$usage_bytes
	QUOTA_BYTES=$quota_bytes
	USAGE_PCT=$usage_pct
	USED_MB=$used_mb
	QUOTA_MB=$quota_mb
	LAST_CHECK=$(date +%s)
	EOF
    
    # Check thresholds and take action
    if [[ $usage_pct -ge $THRESHOLD_FULL ]]; then
        log_warn "Quota exceeded: ${usage_pct}% (threshold: ${THRESHOLD_FULL}%)"
        send_monitor_alert "critical" "$usage_pct" "$used_mb" "$quota_mb"
        
        # Enforce read-only mode via core library
        if declare -f enforce_quota_readonly &>/dev/null; then
            enforce_quota_readonly "$TENANT"
            log_info "Enforced read-only mode for $TENANT"
        else
            log_error "enforce_quota_readonly function not available from cdn-quota-functions"
        fi
        
    elif [[ $usage_pct -ge $THRESHOLD_CRITICAL ]]; then
        log_warn "Quota critical: ${usage_pct}% (threshold: ${THRESHOLD_CRITICAL}%)"
        send_monitor_alert "critical" "$usage_pct" "$used_mb" "$quota_mb"
        
    elif [[ $usage_pct -ge $THRESHOLD_WARNING ]]; then
        log_info "Quota warning: ${usage_pct}% (threshold: ${THRESHOLD_WARNING}%)"
        send_monitor_alert "warning" "$usage_pct" "$used_mb" "$quota_mb"
    fi
    
    return 0
}

# ============================================================================
# FILE EVENT HANDLING
# ============================================================================

handle_file_event() {
    local event_type="$1"
    local file_path="$2"
    
    log_debug "File event: $event_type on $file_path"
    
    # Debounce: wait a bit for multiple events to settle
    sleep "$DEBOUNCE_SECONDS"
    
    # Perform quota check
    check_and_enforce_quota
}

# ============================================================================
# MONITORING LOOP
# ============================================================================

start_monitoring() {
    log_info "Starting real-time quota monitoring for $TENANT"
    log_info "Version: $VERSION"
    log_info "Monitoring: $TENANT_SFTP, $TENANT_NGINX"
    log_info "Thresholds: ${THRESHOLD_WARNING}%, ${THRESHOLD_CRITICAL}%, ${THRESHOLD_FULL}%"
    log_info "Using cdn-quota-functions for consistency"
    
    # Verify directories exist
    local watch_dirs=()
    if [[ -d "$TENANT_SFTP" ]]; then
        watch_dirs+=("$TENANT_SFTP")
        log_info "Watching SFTP: $TENANT_SFTP"
    else
        log_warn "SFTP directory not found: $TENANT_SFTP"
    fi
    
    if [[ -d "$TENANT_NGINX" ]]; then
        watch_dirs+=("$TENANT_NGINX")
        log_info "Watching Nginx: $TENANT_NGINX"
    else
        log_warn "Nginx directory not found: $TENANT_NGINX"
    fi
    
    if [[ ${#watch_dirs[@]} -eq 0 ]]; then
        log_error "No directories to monitor, exiting"
        exit 1
    fi
    
    # Initial quota check
    log_info "Performing initial quota check"
    check_and_enforce_quota
    
    # Setup inotify monitoring
    log_info "Starting inotify watches"
    
    # Monitor file creation, deletion, modification, and moves
    inotifywait -m -r -e create,delete,modify,move \
        --format '%e %w%f' \
        "${watch_dirs[@]}" 2>&1 | \
    while read -r event_line; do
        # Parse event
        local event_type
        event_type=$(echo "$event_line" | awk '{print $1}')
        local file_path
        file_path=$(echo "$event_line" | cut -d' ' -f2-)
        
        # Handle event in background
        handle_file_event "$event_type" "$file_path" &
        
        # Limit background jobs to prevent overload
        while [[ $(jobs -r | wc -l) -ge 5 ]]; do
            sleep 1
        done
    done &
    
    local inotify_pid=$!
    log_info "Inotify process started (PID: $inotify_pid)"
    
    # Fallback periodic check
    while true; do
        sleep "$CHECK_INTERVAL"
        log_debug "Periodic fallback check"
        check_and_enforce_quota &
    done
}

# ============================================================================
# SIGNAL HANDLING
# ============================================================================

cleanup() {
    log_info "Received shutdown signal, cleaning up"
    
    # Kill all background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Final quota check
    check_and_enforce_quota
    
    log_info "Quota monitor stopped for $TENANT"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Verify inotify-tools is installed
    if ! command -v inotifywait &>/dev/null; then
        log_error "inotifywait not found. Install inotify-tools package."
        exit 1
    fi
    
    # Start monitoring
    start_monitoring
}

# Run main function
main "$@"
