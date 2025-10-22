#!/bin/bash
# File: /opt/scripts/cdn/monitoring/cdn-health-monitor.sh (installed to /usr/local/bin/cdn-health-monitor)
# Purpose: System-wide health monitoring
# Type: Cron-based (scheduled execution)
# Triggered by: Cron jobs (every 15 minutes, weekly, monthly)
#
# Cron schedule:
#   */15 * * * * /usr/local/bin/cdn-health-monitor check
#   0 4 * * 0 /usr/local/bin/cdn-health-monitor check-git
#   0 9 * * 1 /usr/local/bin/cdn-health-monitor report
#   0 3 1 * * /usr/local/bin/cdn-health-monitor clean

set -euo pipefail

# Configuration
SCRIPT_NAME="cdn-health-monitor"
VERSION="1.0.0"
COMMAND="${1:-check}"

# FIXED: Core library paths - use correct installed paths
CDN_QUOTA_FUNCTIONS="/usr/local/bin/cdn-quota-functions"
CDN_TENANT_HELPERS="/usr/local/bin/cdn-tenant-helpers"

# Directories (loaded from /etc/cdn/config.env if available)
CONFIG_FILE="/etc/cdn/config.env"
LOG_DIR="/var/log/cdn"
CACHE_DIR="/var/cache/cdn/health"
REPORT_DIR="/var/cache/cdn/reports"
SFTP_BASE="/srv/cdn/sftp"
NGINX_BASE="/srv/cdn/www"
GIT_BASE="/srv/cdn/git"

# Health check thresholds
DISK_WARN_PERCENT=80
DISK_CRIT_PERCENT=90
MEM_WARN_PERCENT=80
MEM_CRIT_PERCENT=90
CPU_WARN_PERCENT=80
SWAP_WARN_PERCENT=50
LOG_SIZE_WARN_MB=500
LOG_SIZE_CRIT_MB=1000

# Files
HEALTH_LOG="${LOG_DIR}/health_monitor.log"
STATUS_FILE="${CACHE_DIR}/health-status.txt"
ALERT_STATE="${CACHE_DIR}/alert-state.txt"

# ============================================================================
# INITIALIZATION
# ============================================================================

# Create directories
mkdir -p "$LOG_DIR" "$CACHE_DIR" "$REPORT_DIR"

# Load CDN configuration if available
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    # Update paths from config
    SFTP_BASE="${SFTP_DIR:-$SFTP_BASE}"
    NGINX_BASE="${NGINX_DIR:-$NGINX_BASE}"
    GIT_BASE="${GIT_DIR:-$GIT_BASE}"
fi

# Source core libraries (optional for health monitor)
if [[ -f "$CDN_QUOTA_FUNCTIONS" ]]; then
    source "$CDN_QUOTA_FUNCTIONS"
fi

if [[ -f "$CDN_TENANT_HELPERS" ]]; then
    source "$CDN_TENANT_HELPERS"
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$HEALTH_LOG"
    logger -t "cdn-health-monitor" -p "user.${level}" "$message"
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

should_send_health_alert() {
    local alert_key="$1"
    local cooldown="${2:-3600}"  # Default 1 hour
    
    # Load alert state
    declare -A alert_times
    if [[ -f "$ALERT_STATE" ]]; then
        while IFS='=' read -r key value; do
            alert_times["$key"]="$value"
        done < "$ALERT_STATE"
    fi
    
    local last_alert="${alert_times[$alert_key]:-0}"
    local now
    now=$(date +%s)
    local elapsed=$((now - last_alert))
    
    if [[ $elapsed -lt $cooldown ]]; then
        return 1
    fi
    
    return 0
}

mark_health_alert_sent() {
    local alert_key="$1"
    local now
    now=$(date +%s)
    
    # Update alert state file
    if [[ -f "$ALERT_STATE" ]]; then
        grep -v "^${alert_key}=" "$ALERT_STATE" > "${ALERT_STATE}.tmp" || true
        mv "${ALERT_STATE}.tmp" "$ALERT_STATE"
    fi
    
    echo "${alert_key}=${now}" >> "$ALERT_STATE"
}

send_health_alert() {
    local subject="$1"
    local body="$2"
    local alert_key="$3"
    
    if ! should_send_health_alert "$alert_key"; then
        log_debug "Alert cooldown active for: $alert_key"
        return 0
    fi
    
    # Send email if mail is available and SMTP is configured
    if command -v mail &>/dev/null; then
        local recipient="${ALERT_EMAIL:-root}"
        echo "$body" | mail -s "CDN Health Alert: $subject" "$recipient"
        mark_health_alert_sent "$alert_key"
        log_info "Health alert sent: $subject"
    else
        log_warn "Cannot send alert: mail command not available"
    fi
}

# ============================================================================
# DISK SPACE CHECKS
# ============================================================================

check_disk_space() {
    log_info "Checking disk space..."
    
    local issues=0
    local report=""
    
    # Check root filesystem
    local root_usage
    root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    report+="Root Filesystem: ${root_usage}%\n"
    
    if [[ $root_usage -ge $DISK_CRIT_PERCENT ]]; then
        log_error "CRITICAL: Root filesystem at ${root_usage}%"
        send_health_alert "Root disk critical" \
            "Root filesystem usage: ${root_usage}%\nThreshold: ${DISK_CRIT_PERCENT}%" \
            "disk_root_critical"
        ((issues++))
    elif [[ $root_usage -ge $DISK_WARN_PERCENT ]]; then
        log_warn "WARNING: Root filesystem at ${root_usage}%"
        send_health_alert "Root disk warning" \
            "Root filesystem usage: ${root_usage}%\nThreshold: ${DISK_WARN_PERCENT}%" \
            "disk_root_warning"
        ((issues++))
    fi
    
    # Check /srv/cdn if separate mount
    if mountpoint -q /srv/cdn 2>/dev/null; then
        local cdn_usage
        cdn_usage=$(df /srv/cdn | awk 'NR==2 {print $5}' | sed 's/%//')
        
        report+="/srv/cdn: ${cdn_usage}%\n"
        
        if [[ $cdn_usage -ge $DISK_CRIT_PERCENT ]]; then
            log_error "CRITICAL: /srv/cdn at ${cdn_usage}%"
            send_health_alert "CDN disk critical" \
                "/srv/cdn usage: ${cdn_usage}%\nThreshold: ${DISK_CRIT_PERCENT}%" \
                "disk_cdn_critical"
            ((issues++))
        elif [[ $cdn_usage -ge $DISK_WARN_PERCENT ]]; then
            log_warn "WARNING: /srv/cdn at ${cdn_usage}%"
            send_health_alert "CDN disk warning" \
                "/srv/cdn usage: ${cdn_usage}%\nThreshold: ${DISK_WARN_PERCENT}%" \
                "disk_cdn_warning"
            ((issues++))
        fi
    fi
    
    echo -e "$report"
    return $issues
}

# ============================================================================
# SERVICE CHECKS
# ============================================================================

check_services() {
    log_info "Checking services..."
    
    local issues=0
    local report=""
    
    # List of critical services
    local services=("nginx" "gitea" "sshd")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            report+="✓ $service: running\n"
            log_debug "$service is running"
        else
            report+="✗ $service: STOPPED\n"
            log_error "CRITICAL: $service is not running"
            send_health_alert "Service down: $service" \
                "Service $service is not running\nServer: $(hostname)" \
                "service_${service}"
            ((issues++))
        fi
    done
    
    echo -e "$report"
    return $issues
}

# ============================================================================
# RESOURCE CHECKS
# ============================================================================

check_resources() {
    log_info "Checking system resources..."
    
    local issues=0
    local report=""
    
    # CPU usage (5-minute load average)
    local cpu_cores
    cpu_cores=$(nproc)
    local load_5min
    load_5min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | xargs)
    local cpu_usage
    cpu_usage=$(awk -v load="$load_5min" -v cores="$cpu_cores" \
        'BEGIN { printf "%.0f", (load / cores) * 100 }')
    
    report+="CPU: ${cpu_usage}% (${load_5min}/${cpu_cores} cores)\n"
    
    if [[ $cpu_usage -ge $CPU_WARN_PERCENT ]]; then
        log_warn "WARNING: CPU usage at ${cpu_usage}%"
        send_health_alert "High CPU usage" \
            "CPU usage: ${cpu_usage}%\nLoad: ${load_5min}\nCores: ${cpu_cores}" \
            "cpu_high"
        ((issues++))
    fi
    
    # Memory usage
    local mem_total mem_used mem_usage
    mem_total=$(free | awk 'NR==2 {print $2}')
    mem_used=$(free | awk 'NR==2 {print $3}')
    mem_usage=$(awk -v used="$mem_used" -v total="$mem_total" \
        'BEGIN { printf "%.0f", (used / total) * 100 }')
    
    report+="Memory: ${mem_usage}%\n"
    
    if [[ $mem_usage -ge $MEM_CRIT_PERCENT ]]; then
        log_error "CRITICAL: Memory usage at ${mem_usage}%"
        send_health_alert "Critical memory usage" \
            "Memory usage: ${mem_usage}%" \
            "memory_critical"
        ((issues++))
    elif [[ $mem_usage -ge $MEM_WARN_PERCENT ]]; then
        log_warn "WARNING: Memory usage at ${mem_usage}%"
        send_health_alert "High memory usage" \
            "Memory usage: ${mem_usage}%" \
            "memory_warning"
        ((issues++))
    fi
    
    # Swap usage
    local swap_total swap_used swap_usage
    swap_total=$(free | awk 'NR==3 {print $2}')
    swap_used=$(free | awk 'NR==3 {print $3}')
    
    if [[ $swap_total -gt 0 ]]; then
        swap_usage=$(awk -v used="$swap_used" -v total="$swap_total" \
            'BEGIN { printf "%.0f", (used / total) * 100 }')
        
        report+="Swap: ${swap_usage}%\n"
        
        if [[ $swap_usage -ge $SWAP_WARN_PERCENT ]]; then
            log_warn "WARNING: Swap usage at ${swap_usage}%"
            send_health_alert "High swap usage" \
                "Swap usage: ${swap_usage}%" \
                "swap_high"
            ((issues++))
        fi
    else
        report+="Swap: Disabled\n"
    fi
    
    echo -e "$report"
    return $issues
}

# ============================================================================
# LOG FILE CHECKS
# ============================================================================

check_log_files() {
    log_info "Checking log files..."
    
    local issues=0
    local report=""
    
    # Check main log directory
    if [[ -d "$LOG_DIR" ]]; then
        while IFS= read -r -d '' logfile; do
            local size_mb
            size_mb=$(du -m "$logfile" | awk '{print $1}')
            local basename
            basename=$(basename "$logfile")
            
            if [[ $size_mb -ge $LOG_SIZE_CRIT_MB ]]; then
                report+="✗ $basename: ${size_mb}MB (CRITICAL)\n"
                log_error "CRITICAL: Large log file $basename (${size_mb}MB)"
                ((issues++))
            elif [[ $size_mb -ge $LOG_SIZE_WARN_MB ]]; then
                report+="⚠ $basename: ${size_mb}MB (WARNING)\n"
                log_warn "WARNING: Large log file $basename (${size_mb}MB)"
                ((issues++))
            fi
        done < <(find "$LOG_DIR" -type f -name "*.log" -print0)
    fi
    
    if [[ $issues -eq 0 ]]; then
        report="All log files within normal size"
    fi
    
    echo -e "$report"
    return $issues
}

# ============================================================================
# TENANT QUOTA CHECKS
# ============================================================================

check_tenant_quotas() {
    log_info "Checking tenant quotas..."
    
    local report=""
    local total_tenants=0
    local warning_tenants=0
    local critical_tenants=0
    
    if [[ ! -d "$SFTP_BASE" ]]; then
        echo "No tenants configured"
        return 0
    fi
    
    # Iterate through tenants
    for tenant_dir in "$SFTP_BASE"/*/; do
        [[ ! -d "$tenant_dir" ]] && continue
        
        local tenant
        tenant=$(basename "$tenant_dir")
        ((total_tenants++))
        
        # Get usage via core library if available
        if declare -f calculate_tenant_usage &>/dev/null && \
           declare -f get_tenant_quota_bytes &>/dev/null; then
            
            local usage_bytes quota_bytes usage_pct
            usage_bytes=$(calculate_tenant_usage "$tenant" 2>/dev/null || echo "0")
            quota_bytes=$(get_tenant_quota_bytes "$tenant" 2>/dev/null || echo "0")
            
            if [[ "$quota_bytes" -gt 0 ]]; then
                usage_pct=$(awk -v used="$usage_bytes" -v quota="$quota_bytes" \
                    'BEGIN { printf "%.0f", (used / quota) * 100 }')
                
                if [[ $usage_pct -ge 90 ]]; then
                    report+="⚠ $tenant: ${usage_pct}% (CRITICAL)\n"
                    ((critical_tenants++))
                elif [[ $usage_pct -ge 80 ]]; then
                    report+="⚠ $tenant: ${usage_pct}% (WARNING)\n"
                    ((warning_tenants++))
                fi
            fi
        fi
    done
    
    if [[ $total_tenants -eq 0 ]]; then
        echo "No tenants found"
    elif [[ $critical_tenants -eq 0 ]] && [[ $warning_tenants -eq 0 ]]; then
        echo "All tenant quotas OK ($total_tenants tenants)"
    else
        echo -e "Tenant Quota Summary:\n$report"
        echo "Total: $total_tenants, Warning: $warning_tenants, Critical: $critical_tenants"
    fi
    
    return 0
}

# ============================================================================
# GIT REPOSITORY CHECK
# ============================================================================

check_git_repositories() {
    log_info "Checking Git repository integrity..."
    
    local issues=0
    local report=""
    local repo_count=0
    
    if [[ ! -d "$GIT_BASE" ]]; then
        echo "No Git repositories found"
        return 0
    fi
    
    for repo_dir in "$GIT_BASE"/*.git; do
        [[ ! -d "$repo_dir" ]] && continue
        
        local repo_name
        repo_name=$(basename "$repo_dir")
        ((repo_count++))
        
        # Check repository integrity
        if git -C "$repo_dir" fsck --quiet 2>/dev/null; then
            report+="✓ $repo_name: OK\n"
        else
            report+="✗ $repo_name: ERRORS\n"
            log_error "Git repository has errors: $repo_name"
            send_health_alert "Git repository errors" \
                "Repository $repo_name has integrity errors\nRun: git -C $repo_dir fsck" \
                "git_${repo_name}"
            ((issues++))
        fi
    done
    
    if [[ $repo_count -eq 0 ]]; then
        echo "No Git repositories to check"
    else
        echo -e "$report"
        echo "Checked $repo_count repositories, $issues errors found"
    fi
    
    return $issues
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
    log_info "Generating health report..."
    
    local report_file="${REPORT_DIR}/health-report-$(date +%Y%m%d-%H%M%S).txt"
    local report_content
    
    report_content=$(cat <<-EOF
		CDN HEALTH MONITORING REPORT
		============================
		
		Generated: $(date '+%Y-%m-%d %H:%M:%S')
		Server: $(hostname)
		Uptime: $(uptime -p)
		
		DISK SPACE
		----------
		$(check_disk_space)
		
		SERVICES
		--------
		$(check_services)
		
		RESOURCES
		---------
		$(check_resources)
		
		LOG FILES
		---------
		$(check_log_files)
		
		TENANT QUOTAS
		-------------
		$(check_tenant_quotas)
		
		============================
		End of Report
	EOF
    )
    
    echo "$report_content" | tee "$report_file"
    log_info "Report saved to: $report_file"
    
    # Keep only last 30 reports
    find "$REPORT_DIR" -name "health-report-*.txt" -type f -mtime +30 -delete 2>/dev/null || true
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup_logs() {
    log_info "Cleaning up old logs..."
    
    # Clean logs older than 90 days
    find "$LOG_DIR" -name "*.log" -type f -mtime +90 -delete 2>/dev/null || true
    
    # Clean old reports (keep 30 days)
    find "$REPORT_DIR" -name "health-report-*.txt" -type f -mtime +30 -delete 2>/dev/null || true
    
    # Clean old cache files
    find "$CACHE_DIR" -name "*.tmp" -type f -mtime +7 -delete 2>/dev/null || true
    
    log_info "Cleanup completed"
}

# ============================================================================
# MAIN FUNCTIONS
# ============================================================================

run_health_check() {
    log_info "Running health check..."
    
    local total_issues=0
    
    check_disk_space || ((total_issues+=$?))
    check_services || ((total_issues+=$?))
    check_resources || ((total_issues+=$?))
    check_log_files || ((total_issues+=$?))
    check_tenant_quotas || ((total_issues+=$?))
    
    # Save status
    cat > "$STATUS_FILE" <<-EOF
		LAST_CHECK=$(date +%s)
		LAST_CHECK_TIME=$(date '+%Y-%m-%d %H:%M:%S')
		TOTAL_ISSUES=$total_issues
	EOF
    
    if [[ $total_issues -eq 0 ]]; then
        log_info "Health check completed: All OK"
    else
        log_warn "Health check completed: $total_issues issue(s) found"
    fi
    
    return 0
}

# ============================================================================
# COMMAND DISPATCHER
# ============================================================================

case "$COMMAND" in
    check)
        run_health_check
        ;;
    check-git)
        check_git_repositories
        ;;
    report)
        generate_report
        ;;
    clean)
        cleanup_logs
        ;;
    status)
        if [[ -f "$STATUS_FILE" ]]; then
            cat "$STATUS_FILE"
        else
            echo "No status file found. Run: $0 check"
        fi
        ;;
    *)
        echo "Usage: $0 {check|check-git|report|clean|status}"
        echo ""
        echo "Commands:"
        echo "  check      - Run health checks (use in cron: */15 * * * *)"
        echo "  check-git  - Check Git repository integrity (weekly)"
        echo "  report     - Generate full health report (weekly)"
        echo "  clean      - Clean up old logs (monthly)"
        echo "  status     - Show last check status"
        exit 1
        ;;
esac
