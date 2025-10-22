#!/bin/bash
# File: /opt/scripts/cdn/includes/common.sh
# Purpose: Common functions and utilities shared across all setup scripts
#          Provides logging, validation, and helper functions

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

info() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

validate_positive_integer() {
    local value=$1
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# CONFIGURATION MANAGEMENT
# ==============================================================================

save_configuration() {
    # Create config directory structure
    mkdir -p "${CONFIG_DIR}"/{tenants,quotas/alerts_sent,keys}
    chmod 700 "${CONFIG_DIR}/keys"
    
    # Process template and save configuration
    local template="${SCRIPT_DIR}/templates/config.env.template"
    
    if [[ ! -f "$template" ]]; then
        error "Configuration template not found: $template"
        return 1
    fi
    
    # Read template and substitute variables
    eval "cat << EOF
$(cat "$template")
EOF
" > "$CONFIG_FILE"
    
    # Secure the configuration file
    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
    
    return 0
}

# ==============================================================================
# FILE OPERATIONS
# ==============================================================================

process_template() {
    local template_file=$1
    local output_file=$2
    
    if [[ ! -f "$template_file" ]]; then
        error "Template file not found: $template_file"
        return 1
    fi
    
    # Evaluate template with variable substitution
    eval "cat << EOF
$(cat "$template_file")
EOF
" > "$output_file"
    
    return 0
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

check_port_available() {
    local port=$1
    
    if netstat -tuln 2>/dev/null | grep -q ":${port} " || \
       ss -tuln 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    
    return 0
}

get_current_ssh_port() {
    local port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [[ -z "$port" ]]; then
        echo "22"
    else
        echo "$port"
    fi
}

