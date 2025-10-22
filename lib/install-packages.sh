#!/bin/bash
# File: /opt/scripts/cdn/lib/install-packages.sh
# Purpose: Install required system packages for CDN operation
#          Handles apt updates, package installation, and SMTP configuration

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Installing Required Packages"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log "Updating package lists..."
apt-get update

log "Installing core packages..."
apt-get install -y nginx git openssh-server rsync inotify-tools

if [[ "$SMTP_ENABLED" == "true" ]]; then
    log "Installing SMTP tools (msmtp)..."
    apt-get install -y msmtp msmtp-mta mailutils
    
    log "Configuring msmtp for SMTP relay..."
    
    TLS_SETTING="on"
    if [[ "$USE_TLS" != "yes" ]]; then
        TLS_SETTING="off"
    fi
    
    process_template "${SCRIPT_DIR}/templates/msmtprc.template" "/etc/msmtprc"
    
    chmod 644 /etc/msmtprc
    touch /var/log/msmtp.log
    chmod 666 /var/log/msmtp.log
    
    log "✓ msmtp configured"
    
    # Test SMTP
    echo ""
    log "Testing SMTP configuration..."
    log "Sending test email to: ${ALERT_EMAIL}"
    
    if echo "CDN system configured successfully at $(date). SMTP is working correctly." | \
       mail -s "CDN Setup Complete - SMTP Test" "${ALERT_EMAIL}" 2>&1; then
        log "✓ Test email sent successfully!"
        echo ""
        read -p "Did you receive the test email? (yes/no): " EMAIL_RECEIVED
        
        if [[ "$EMAIL_RECEIVED" != "yes" ]]; then
            warn "Test email may not have been received"
            warn "Check logs: /var/log/msmtp.log"
            echo ""
            read -p "Press ENTER to continue..."
        fi
    else
        warn "Failed to send test email"
        warn "Check logs: /var/log/msmtp.log"
        echo ""
        read -p "Press ENTER to continue..."
    fi
fi

# Configure SSH for chroot SFTP
log "Configuring SSH for chroot SFTP..."
groupadd -f sftpusers

if ! grep -q "Match Group sftpusers" /etc/ssh/sshd_config; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    cat >> /etc/ssh/sshd_config << SSHEOF

# CDN Multi-Tenant SFTP Configuration
Match Group sftpusers
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication no
    PubkeyAuthentication yes
SSHEOF
    systemctl restart sshd
    log "✓ SSH configured for chroot SFTP"
fi

# Create directory structure
log "Creating directory structure..."
mkdir -p "${BASE_DIR}"/{sftp,git,www,backups}
mkdir -p /var/log/cdn

log "✓ Packages installed successfully"
