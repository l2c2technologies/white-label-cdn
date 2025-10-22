#!/bin/bash
# File: /opt/scripts/cdn/includes/step5-paths.sh
# Purpose: Configure system paths and operational parameters
#          Sets base directory, cache size, and backup retention

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "STEP 5: System Paths (default values recommended)"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Base directory for CDN data [/srv/cdn]: " BASE_DIR
BASE_DIR=${BASE_DIR:-/srv/cdn}

read -p "Nginx cache size limit [10g]: " CACHE_SIZE
CACHE_SIZE=${CACHE_SIZE:-10g}

read -p "Backup retention days [30]: " BACKUP_RETENTION
BACKUP_RETENTION=${BACKUP_RETENTION:-30}

log "✓ System paths configured successfully"
