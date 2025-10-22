#!/bin/bash
# File: /opt/scripts/cdn/helpers/cdn-autocommit.sh (installed to /usr/local/bin/cdn-autocommit)
# Purpose: Unified auto-commit script for all CDN tenants
#          Watches for file changes and automatically commits to Git

set -e

# Tenant name is passed as first argument
TENANT_NAME="${1}"

if [[ -z "$TENANT_NAME" ]]; then
    echo "ERROR: Tenant name required"
    echo "Usage: $0 <tenant_name>"
    exit 1
fi

# Load tenant configuration
TENANT_CONFIG_DIR="/etc/cdn/tenants"
TENANT_CONFIG="${TENANT_CONFIG_DIR}/${TENANT_NAME}.env"

if [[ ! -f "$TENANT_CONFIG" ]]; then
    echo "ERROR: Tenant config not found: $TENANT_CONFIG"
    exit 1
fi

# Source tenant configuration
source "$TENANT_CONFIG"

# Validate required variables
[[ -z "$WATCH_DIR" ]] && { echo "ERROR: WATCH_DIR not set in config"; exit 1; }
[[ -z "$GIT_REPO" ]] && { echo "ERROR: GIT_REPO not set in config"; exit 1; }
[[ -z "$LOG_FILE" ]] && { echo "ERROR: LOG_FILE not set in config"; exit 1; }
[[ -z "$GIT_USER_NAME" ]] && { echo "ERROR: GIT_USER_NAME not set in config"; exit 1; }
[[ -z "$GIT_USER_EMAIL" ]] && { echo "ERROR: GIT_USER_EMAIL not set in config"; exit 1; }

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Change to watch directory
cd "$WATCH_DIR" || {
    log_message "ERROR: Cannot access WATCH_DIR: $WATCH_DIR"
    exit 1
}

# Configure git identity from tenant config
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

log_message "Auto-commit watcher started for ${TENANT_NAME}"
log_message "Git Identity: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"

# Watch for file changes using inotifywait
inotifywait -m -r -e modify,create,delete,move "$WATCH_DIR" \
    --exclude '\.git/' \
    --format '%w%f %e' | while read -r file event; do
    
    log_message "Detected: $event on $file"
    
    # Wait for file operations to complete
    sleep 2
    
    # Check if there are changes
    if [[ -n $(git status --porcelain) ]]; then
        log_message "Changes detected, committing..."
        
        # Stage all changes
        git add -A
        
        # Create commit message with details
        CHANGED_FILES=$(git status --porcelain | wc -l)
        COMMIT_MSG="Auto-commit: $CHANGED_FILES file(s) changed at $(date '+%Y-%m-%d %H:%M:%S')"
        
        # Commit
        if git commit -m "$COMMIT_MSG"; then
            log_message "Committed: $COMMIT_MSG"
            
            # Push to bare repository (triggers post-receive hook)
            if git push origin master 2>&1 | tee -a "$LOG_FILE"; then
                log_message "✓ Pushed and deployed successfully"
            else
                log_message "ERROR: Failed to push"
            fi
        else
            log_message "Nothing to commit or commit failed"
        fi
    fi
done
