#!/bin/bash
# File: /opt/scripts/cdn/monitoring/cdn-monitoring-control.sh
# Installed to: /usr/local/bin/cdn-monitoring-control
# Purpose: Unified control interface for CDN monitoring system
#          Manages per-tenant quota monitors and system health monitoring
# Version: 1.0.0

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_NAME="cdn-monitoring-control"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
CONFIG_FILE="/etc/cdn/config.env"
SFTP_BASE="/srv/cdn/sftp"
LOG_DIR="/var/log/cdn"
CACHE_DIR="/var/cache/cdn/quota"

# Service name template
SERVICE_TEMPLATE="cdn-quota-monitor@"

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
info() { echo -e "${BLUE}[CONTROL]${NC} $*"; }
debug() { 
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    echo "Usage: sudo $0 <command> [options]"
    exit 1
fi

# Load CDN configuration if available
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    # Override paths from config if available
    SFTP_BASE="${SFTP_DIR:-$SFTP_BASE}"
    LOG_DIR="${LOG_DIR:-/var/log/cdn}"
fi

# Create necessary directories
mkdir -p "$LOG_DIR" "$CACHE_DIR"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Check if systemd service exists
service_exists() {
    local tenant="$1"
    systemctl list-unit-files "${SERVICE_TEMPLATE}${tenant}.service" &>/dev/null
}

# Check if service is active
service_is_active() {
    local tenant="$1"
    systemctl is-active --quiet "${SERVICE_TEMPLATE}${tenant}.service" 2>/dev/null
}

# Check if service is enabled
service_is_enabled() {
    local tenant="$1"
    systemctl is-enabled --quiet "${SERVICE_TEMPLATE}${tenant}.service" 2>/dev/null
}

# Get all tenants with monitoring
get_all_tenants() {
    local tenants=()
    
    # Find all tenant directories
    if [[ -d "$SFTP_BASE" ]]; then
        for tenant_dir in "$SFTP_BASE"/*; do
            if [[ -d "$tenant_dir" ]]; then
                local tenant
                tenant=$(basename "$tenant_dir")
                
                # Check if tenant user exists
                if id "cdn_${tenant}" &>/dev/null 2>&1; then
                    tenants+=("$tenant")
                fi
            fi
        done
    fi
    
    printf "%s\n" "${tenants[@]}"
}

# Validate tenant name
validate_tenant() {
    local tenant="$1"
    
    if [[ ! "$tenant" =~ ^[a-z0-9_-]+$ ]]; then
        error "Invalid tenant name: $tenant"
        return 1
    fi
    
    if ! id "cdn_${tenant}" &>/dev/null 2>&1; then
        error "Tenant not found: $tenant"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# MONITORING OPERATIONS
# ==============================================================================

# Start monitoring for tenant
start_monitor() {
    local tenant="$1"
    
    if ! validate_tenant "$tenant"; then
        return 1
    fi
    
    log "Starting quota monitor for: $tenant"
    
    if service_is_active "$tenant"; then
        warn "Monitor already running for: $tenant"
        return 0
    fi
    
    if ! service_exists "$tenant"; then
        error "Service not found: ${SERVICE_TEMPLATE}${tenant}.service"
        error "Ensure monitoring system is installed: sudo cdn-monitoring-setup"
        return 1
    fi
    
    if systemctl start "${SERVICE_TEMPLATE}${tenant}.service"; then
        sleep 2
        
        if service_is_active "$tenant"; then
            log "✓ Monitor started for: $tenant"
            return 0
        else
            error "Monitor failed to start for: $tenant"
            error "Check logs: sudo journalctl -u ${SERVICE_TEMPLATE}${tenant} -n 50"
            return 1
        fi
    else
        error "Failed to start monitor for: $tenant"
        return 1
    fi
}

# Stop monitoring for tenant
stop_monitor() {
    local tenant="$1"
    
    if ! validate_tenant "$tenant"; then
        return 1
    fi
    
    log "Stopping quota monitor for: $tenant"
    
    if ! service_is_active "$tenant"; then
        warn "Monitor not running for: $tenant"
        return 0
    fi
    
    if systemctl stop "${SERVICE_TEMPLATE}${tenant}.service"; then
        log "✓ Monitor stopped for: $tenant"
        return 0
    else
        error "Failed to stop monitor for: $tenant"
        return 1
    fi
}

# Restart monitoring for tenant
restart_monitor() {
    local tenant="$1"
    
    if ! validate_tenant "$tenant"; then
        return 1
    fi
    
    log "Restarting quota monitor for: $tenant"
    
    if systemctl restart "${SERVICE_TEMPLATE}${tenant}.service"; then
        sleep 2
        
        if service_is_active "$tenant"; then
            log "✓ Monitor restarted for: $tenant"
            return 0
        else
            error "Monitor failed to restart for: $tenant"
            return 1
        fi
    else
        error "Failed to restart monitor for: $tenant"
        return 1
    fi
}

# Enable monitoring at boot
enable_monitor() {
    local tenant="$1"
    
    if ! validate_tenant "$tenant"; then
        return 1
    fi
    
    log "Enabling quota monitor at boot for: $tenant"
    
    if service_is_enabled "$tenant"; then
        warn "Monitor already enabled for: $tenant"
        return 0
    fi
    
    if systemctl enable "${SERVICE_TEMPLATE}${tenant}.service"; then
        log "✓ Monitor enabled for: $tenant"
        return 0
    else
        error "Failed to enable monitor for: $tenant"
        return 1
    fi
}

# Disable monitoring at boot
disable_monitor() {
    local tenant="$1"
    
    if ! validate_tenant "$tenant"; then
        return 1
    fi
    
    log "Disabling quota monitor at boot for: $tenant"
    
    if ! service_is_enabled "$tenant"; then
        warn "Monitor already disabled for: $tenant"
        return 0
    fi
    
    if systemctl disable "${SERVICE_TEMPLATE}${tenant}.service"; then
        log "✓ Monitor disabled for: $tenant"
        return 0
    else
        error "Failed to disable monitor for: $tenant"
        return 1
    fi
}

# ==============================================================================
# BULK OPERATIONS
# ==============================================================================

# Start all monitors
start_all() {
    log "Starting monitors for all tenants..."
    echo ""
    
    local tenants
    mapfile -t tenants < <(get_all_tenants)
    
    if [[ ${#tenants[@]} -eq 0 ]]; then
        warn "No tenants found"
        return 0
    fi
    
    local success=0
    local failed=0
    
    for tenant in "${tenants[@]}"; do
        if start_monitor "$tenant"; then
            ((success++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bulk Start Complete"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Started: $success"
    [[ $failed -gt 0 ]] && error "Failed: $failed" || log "Failed: 0"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return 0
}

# Stop all monitors
stop_all() {
    log "Stopping monitors for all tenants..."
    echo ""
    
    local tenants
    mapfile -t tenants < <(get_all_tenants)
    
    if [[ ${#tenants[@]} -eq 0 ]]; then
        warn "No tenants found"
        return 0
    fi
    
    local success=0
    local failed=0
    
    for tenant in "${tenants[@]}"; do
        if stop_monitor "$tenant"; then
            ((success++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bulk Stop Complete"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Stopped: $success"
    [[ $failed -gt 0 ]] && error "Failed: $failed" || log "Failed: 0"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return 0
}

# Restart all monitors
restart_all() {
    log "Restarting monitors for all tenants..."
    echo ""
    
    local tenants
    mapfile -t tenants < <(get_all_tenants)
    
    if [[ ${#tenants[@]} -eq 0 ]]; then
        warn "No tenants found"
        return 0
    fi
    
    local success=0
    local failed=0
    
    for tenant in "${tenants[@]}"; do
        if restart_monitor "$tenant"; then
            ((success++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bulk Restart Complete"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Restarted: $success"
    [[ $failed -gt 0 ]] && error "Failed: $failed" || log "Failed: 0"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return 0
}

# Enable all monitors
enable_all() {
    log "Enabling monitors for all tenants..."
    echo ""
    
    local tenants
    mapfile -t tenants < <(get_all_tenants)
    
    if [[ ${#tenants[@]} -eq 0 ]]; then
        warn "No tenants found"
        return 0
    fi
    
    local success=0
    local failed=0
    
    for tenant in "${tenants[@]}"; do
        if enable_monitor "$tenant"; then
            ((success++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bulk Enable Complete"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Enabled: $success"
    [[ $failed -gt 0 ]] && error "Failed: $failed" || log "Failed: 0"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return 0
}

# Disable all monitors
disable_all() {
    log "Disabling monitors for all tenants..."
    echo ""
    
    local tenants
    mapfile -t tenants < <(get_all_tenants)
    
    if [[ ${#tenants[@]} -eq 0 ]]; then
        warn "No tenants found"
        return 0
    fi
    
    local success=0
    local failed=0
    
    for tenant in "${tenants[@]}"; do
        if disable_monitor "$tenant"; then
            ((success++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bulk Disable Complete"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Disabled: $success"
    [[ $failed -gt 0 ]] && error "Failed: $failed" || log "Failed: 0"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return 0
}

# ==============================================================================
# STATUS AND INFORMATION
# ==============================================================================

# Show status for specific tenant
show_tenant_status() {
    local tenant="$1"
    
    if ! validate_tenant "$tenant"; then
        return 1
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Monitoring Status: $tenant"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Service status
    local status_text="STOPPED"
    local status_color="$RED"
    
    if service_is_active "$tenant"; then
        status_text="RUNNING"
        status_color="$GREEN"
    fi
    
    echo -e "Service Status:    ${status_color}${status_text}${NC}"
    
    # Boot status
    local boot_text="DISABLED"
    local boot_color="$RED"
    
    if service_is_enabled "$tenant"; then
        boot_text="ENABLED"
        boot_color="$GREEN"
    fi
    
    echo -e "Boot Enabled:      ${boot_color}${boot_text}${NC}"
    
    # Show systemd status
    echo ""
    systemctl status "${SERVICE_TEMPLATE}${tenant}.service" --no-pager || true
    
    # Show recent log entries
    echo ""
    echo "Recent Log Entries (last 10):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    journalctl -u "${SERVICE_TEMPLATE}${tenant}.service" -n 10 --no-pager || true
    
    # Show quota status if available
    if [[ -f "${CACHE_DIR}/${tenant}.state" ]]; then
        echo ""
        echo "Current Quota Status:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        source "${CACHE_DIR}/${tenant}.state"
        
        local status_icon="✓"
        local status_color="$GREEN"
        
        if [[ ${USAGE_PCT:-0} -ge 100 ]]; then
            status_icon="🚨"
            status_color="$RED"
        elif [[ ${USAGE_PCT:-0} -ge 90 ]]; then
            status_icon="⚠️"
            status_color="$RED"
        elif [[ ${USAGE_PCT:-0} -ge 80 ]]; then
            status_icon="⚠️"
            status_color="$YELLOW"
        fi
        
        echo -e "${status_color}${status_icon} Usage: ${USED_MB:-0}MB / ${QUOTA_MB:-0}MB (${USAGE_PCT:-0}%)${NC}"
        
        if [[ -n "${LAST_CHECK:-}" ]]; then
            local last_check_time
            last_check_time=$(date -d "@${LAST_CHECK}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
            echo "  Last Check: $last_check_time"
        fi
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    return 0
}

# Show status for all tenants
show_all_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "All Tenant Monitoring Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local tenants
    mapfile -t tenants < <(get_all_tenants)
    
    if [[ ${#tenants[@]} -eq 0 ]]; then
        warn "No tenants found"
        return 0
    fi
    
    # Header
    printf "%-20s %-12s %-12s %-20s\n" "TENANT" "STATUS" "BOOT" "QUOTA"
    printf "%-20s %-12s %-12s %-20s\n" "------" "------" "----" "-----"
    
    local total=0
    local running=0
    local stopped=0
    local enabled=0
    
    for tenant in "${tenants[@]}"; do
        ((total++))
        
        # Status
        local status="STOPPED"
        if service_is_active "$tenant"; then
            status="RUNNING"
            ((running++))
        else
            ((stopped++))
        fi
        
        # Boot enabled
        local boot="DISABLED"
        if service_is_enabled "$tenant"; then
            boot="ENABLED"
            ((enabled++))
        fi
        
        # Quota
        local quota="N/A"
        if [[ -f "${CACHE_DIR}/${tenant}.state" ]]; then
            source "${CACHE_DIR}/${tenant}.state"
            quota="${USAGE_PCT:-0}% (${USED_MB:-0}/${QUOTA_MB:-0}MB)"
        fi
        
        printf "%-20s %-12s %-12s %-20s\n" "$tenant" "$status" "$boot" "$quota"
    done
    
    echo ""
    echo "Summary:"
    echo "  Total Tenants:    $total"
    echo "  Running:          $running"
    echo "  Stopped:          $stopped"
    echo "  Enabled at Boot:  $enabled"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    return 0
}

# List all monitored tenants
list_tenants() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Monitored Tenants"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local tenants
    mapfile -t tenants < <(get_all_tenants)
    
    if [[ ${#tenants[@]} -eq 0 ]]; then
        warn "No tenants found"
        return 0
    fi
    
    for tenant in "${tenants[@]}"; do
        local indicator="○"
        local color="$RED"
        
        if service_is_active "$tenant"; then
            indicator="●"
            color="$GREEN"
        fi
        
        echo -e "${color}${indicator}${NC} $tenant"
    done
    
    echo ""
    log "Total: ${#tenants[@]} tenant(s)"
    echo ""
    
    return 0
}

# View logs for tenant
view_logs() {
    local tenant="$1"
    local lines="${2:-50}"
    
    if ! validate_tenant "$tenant"; then
        return 1
    fi
    
    log "Viewing logs for: $tenant (last $lines lines)"
    echo ""
    
    journalctl -u "${SERVICE_TEMPLATE}${tenant}.service" -n "$lines" --no-pager
    
    return 0
}

# Run system health check
run_health_check() {
    log "Running system health check..."
    echo ""
    
    if command -v cdn-health-monitor &>/dev/null; then
        cdn-health-monitor check
    else
        warn "Health monitor not installed"
        warn "Install with: sudo cdn-monitoring-setup"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# USAGE
# ==============================================================================

show_usage() {
    cat << 'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CDN Monitoring Control Interface
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE: cdn-monitoring-control <command> [options]

INDIVIDUAL TENANT OPERATIONS:
  start <tenant>              Start quota monitoring
  stop <tenant>               Stop quota monitoring
  restart <tenant>            Restart quota monitoring
  enable <tenant>             Enable monitoring at boot
  disable <tenant>            Disable monitoring at boot
  status <tenant>             Show detailed status
  logs <tenant> [lines]       View logs (default: 50 lines)

BULK OPERATIONS:
  start all                   Start monitoring for all tenants
  stop all                    Stop monitoring for all tenants
  restart all                 Restart monitoring for all tenants
  enable all                  Enable monitoring at boot for all
  disable all                 Disable monitoring at boot for all
  status                      Show status for all tenants
  list                        List all monitored tenants

SYSTEM HEALTH:
  health                      Run system health check

EXAMPLES:

  # Start monitoring for specific tenant
  cdn-monitoring-control start acmecorp

  # Start monitoring for all tenants
  cdn-monitoring-control start all

  # Check status of all tenants
  cdn-monitoring-control status

  # View detailed status for specific tenant
  cdn-monitoring-control status acmecorp

  # View logs for tenant (last 100 lines)
  cdn-monitoring-control logs acmecorp 100

  # Enable monitoring at boot for all tenants
  cdn-monitoring-control enable all

  # List all monitored tenants
  cdn-monitoring-control list

  # Run system health check
  cdn-monitoring-control health

MONITORING FEATURES:
  • Real-time quota tracking via inotify
  • Automatic enforcement at 100% quota
  • Email alerts at 80%, 90%, 100%
  • Integration with cdn-quota-functions
  • Per-tenant systemd services

LOGS & STATE:
  Logs:  /var/log/cdn/<tenant>_quota_monitor.log
  State: /var/cache/cdn/quota/<tenant>.state
  
SYSTEMD JOURNAL:
  sudo journalctl -u cdn-quota-monitor@<tenant> -f

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For detailed documentation, see: /opt/scripts/cdn/MONITORING.md

EOF
}

# ==============================================================================
# COMMAND ROUTER
# ==============================================================================

main() {
    local command="${1:-}"
    
    if [[ -z "$command" ]]; then
        show_usage
        exit 1
    fi
    
    case "$command" in
        start)
            shift
            local target="${1:-}"
            
            if [[ -z "$target" ]]; then
                error "Tenant name required"
                echo "Usage: $0 start <tenant|all>"
                exit 1
            fi
            
            if [[ "$target" == "all" ]]; then
                start_all
            else
                start_monitor "$target"
            fi
            ;;
        
        stop)
            shift
            local target="${1:-}"
            
            if [[ -z "$target" ]]; then
                error "Tenant name required"
                echo "Usage: $0 stop <tenant|all>"
                exit 1
            fi
            
            if [[ "$target" == "all" ]]; then
                stop_all
            else
                stop_monitor "$target"
            fi
            ;;
        
        restart)
            shift
            local target="${1:-}"
            
            if [[ -z "$target" ]]; then
                error "Tenant name required"
                echo "Usage: $0 restart <tenant|all>"
                exit 1
            fi
            
            if [[ "$target" == "all" ]]; then
                restart_all
            else
                restart_monitor "$target"
            fi
            ;;
        
        enable)
            shift
            local target="${1:-}"
            
            if [[ -z "$target" ]]; then
                error "Tenant name required"
                echo "Usage: $0 enable <tenant|all>"
                exit 1
            fi
            
            if [[ "$target" == "all" ]]; then
                enable_all
            else
                enable_monitor "$target"
            fi
            ;;
        
        disable)
            shift
            local target="${1:-}"
            
            if [[ -z "$target" ]]; then
                error "Tenant name required"
                echo "Usage: $0 disable <tenant|all>"
                exit 1
            fi
            
            if [[ "$target" == "all" ]]; then
                disable_all
            else
                disable_monitor "$target"
            fi
            ;;
        
        status)
            shift
            local target="${1:-}"
            
            if [[ -z "$target" ]]; then
                show_all_status
            else
                show_tenant_status "$target"
            fi
            ;;
        
        list)
            list_tenants
            ;;
        
        logs)
            shift
            local tenant="${1:-}"
            local lines="${2:-50}"
            
            if [[ -z "$tenant" ]]; then
                error "Tenant name required"
                echo "Usage: $0 logs <tenant> [lines]"
                exit 1
            fi
            
            view_logs "$tenant" "$lines"
            ;;
        
        health)
            run_health_check
            ;;
        
        help|--help|-h)
            show_usage
            ;;
        
        version|--version|-v)
            echo "$SCRIPT_NAME version $VERSION"
            ;;
        
        *)
            error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

main "$@"
