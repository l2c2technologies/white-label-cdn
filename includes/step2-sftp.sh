#!/bin/bash
# File: /opt/scripts/cdn/includes/step2-sftp.sh
# Purpose: Configure SFTP port for tenant access
#          Handles SSH port changes with safety checks and firewall reminders

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "STEP 2: SFTP Port Configuration"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Detect current SSH port
CURRENT_SSH_PORT=$(get_current_ssh_port)
log "SSH is currently configured for port: ${CURRENT_SSH_PORT}"

echo ""
cat << SSHINFO
SFTP Port Configuration Options:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current SSH daemon is listening on port: ${CURRENT_SSH_PORT}

Choose how to configure SFTP access for tenants:

1. Use existing SSH port (${CURRENT_SSH_PORT})
   • Tenants will connect to port ${CURRENT_SSH_PORT}
   • No SSH configuration changes needed
   • Simplest and safest option

2. Change SSH to a different port
   • You specify a new port for SSH daemon
   • Requires SSH restart
   • ⚠️  WARNING: May disconnect current SSH sessions!
   • Ensure you can reconnect on the new port

3. Manual configuration
   • You'll configure SSH port separately
   • Script will record the port for configuration only
   • Advanced users only

SSHINFO

echo ""
while true; do
    read -p "Choose option (1/2/3): " SSH_OPTION
    
    case "$SSH_OPTION" in
        1)
            SFTP_PORT="$CURRENT_SSH_PORT"
            log "✓ Using existing SSH port: ${SFTP_PORT}"
            log "No SSH configuration changes needed"
            break
            ;;
        2)
            echo ""
            while true; do
                read -p "Enter new SSH port (1-65535): " NEW_PORT
                NEW_PORT=$(echo "$NEW_PORT" | xargs)
                
                if ! validate_port "$NEW_PORT"; then
                    warn "Invalid port number (must be 1-65535)"
                    continue
                fi
                
                if [[ "$NEW_PORT" == "$CURRENT_SSH_PORT" ]]; then
                    warn "That's the same as the current port. Choose option 1 instead."
                    continue
                fi
                
                # Check if port is available
                log "Checking if port ${NEW_PORT} is available..."
                if ! check_port_available "$NEW_PORT"; then
                    warn "Port ${NEW_PORT} is already in use!"
                    netstat -tuln 2>/dev/null | grep ":${NEW_PORT} " || \
                    ss -tuln 2>/dev/null | grep ":${NEW_PORT} "
                    echo ""
                    read -p "Try a different port? (yes/no): " retry
                    [[ "$retry" == "yes" ]] && continue || continue 2
                fi
                
                log "✓ Port ${NEW_PORT} is available"
                
                # Confirm the change
                echo ""
                warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                warn "⚠️  CRITICAL: SSH Port Change Confirmation"
                warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                warn "Current port: ${CURRENT_SSH_PORT}"
                warn "New port:     ${NEW_PORT}"
                warn ""
                warn "After this change:"
                warn "  • SSH daemon will restart immediately"
                warn "  • Current session may be disconnected"
                warn "  • You MUST reconnect using: ssh -p ${NEW_PORT} user@host"
                warn "  • Firewall must allow the new port"
                warn ""
                warn "Before proceeding, ensure:"
                warn "  ✓ You have console/panel access to server"
                warn "  ✓ Firewall rules are updated (or will be)"
                warn "  ✓ You can reconnect if disconnected"
                warn ""
                warn "Firewall configuration:"
                warn "  sudo ufw allow ${NEW_PORT}/tcp"
                warn "  sudo firewall-cmd --permanent --add-port=${NEW_PORT}/tcp"
                warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                read -p "Type 'CHANGE PORT' in capitals to confirm: " CONFIRM
                
                if [[ "$CONFIRM" != "CHANGE PORT" ]]; then
                    warn "Port change cancelled"
                    echo ""
                    read -p "Return to option selection? (yes/no): " return_menu
                    [[ "$return_menu" == "yes" ]] && continue 2 || exit 0
                fi
                
                # Backup sshd_config
                BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
                cp /etc/ssh/sshd_config "$BACKUP_FILE"
                log "✓ SSH config backed up to: ${BACKUP_FILE}"
                
                # Update sshd_config
                if grep -q "^Port " /etc/ssh/sshd_config; then
                    sed -i "s/^Port .*/Port ${NEW_PORT}/" /etc/ssh/sshd_config
                elif grep -q "^#Port " /etc/ssh/sshd_config; then
                    sed -i "s/^#Port .*/Port ${NEW_PORT}/" /etc/ssh/sshd_config
                else
                    sed -i "1iPort ${NEW_PORT}" /etc/ssh/sshd_config
                fi
                
                # Test SSH configuration
                log "Testing SSH configuration..."
                if ! sshd -t 2>/dev/null; then
                    error "SSH configuration test failed!"
                    cp "$BACKUP_FILE" /etc/ssh/sshd_config
                    error "Configuration restored from backup"
                    exit 1
                fi
                
                log "✓ SSH configuration is valid"
                
                # Restart SSH daemon
                log "Restarting SSH daemon on port ${NEW_PORT}..."
                systemctl restart sshd
                
                # Verify SSH is running
                sleep 2
                if systemctl is-active --quiet sshd; then
                    log "✓ SSH daemon restarted successfully"
                    SFTP_PORT="$NEW_PORT"
                    
                    echo ""
                    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    warn "SSH Port Changed Successfully"
                    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    warn "New port: ${SFTP_PORT}"
                    warn ""
                    warn "To reconnect, use:"
                    warn "  ssh -p ${SFTP_PORT} $(whoami)@$(hostname -I | awk '{print $1}')"
                    warn ""
                    warn "If you lose connection, use console access to restore:"
                    warn "  cp ${BACKUP_FILE} /etc/ssh/sshd_config"
                    warn "  systemctl restart sshd"
                    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    read -p "Press ENTER to continue..."
                else
                    error "SSH daemon failed to start!"
                    error "Restoring backup configuration..."
                    cp "$BACKUP_FILE" /etc/ssh/sshd_config
                    systemctl restart sshd
                    error "Backup restored. Please check configuration manually."
                    exit 1
                fi
                
                break 2
            done
            ;;
        3)
            echo ""
            log "Manual SSH configuration selected"
            while true; do
                read -p "Enter the SFTP port you will configure manually (1-65535): " MANUAL_PORT
                MANUAL_PORT=$(echo "$MANUAL_PORT" | xargs)
                
                if ! validate_port "$MANUAL_PORT"; then
                    warn "Invalid port number (must be 1-65535)"
                    continue
                fi
                
                SFTP_PORT="$MANUAL_PORT"
                log "✓ SFTP port recorded as: ${SFTP_PORT}"
                warn "You must configure SSH to listen on this port manually"
                break 2
            done
            ;;
        *)
            warn "Invalid option. Please choose 1, 2, or 3."
            ;;
    esac
done

# Show firewall reminder if non-standard port
if [[ "$SFTP_PORT" != "22" ]]; then
    echo ""
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "Firewall Configuration Required"
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "Ensure your firewall allows TCP port ${SFTP_PORT}"
    warn ""
    warn "Ubuntu/Debian (UFW):"
    warn "  sudo ufw allow ${SFTP_PORT}/tcp"
    warn ""
    warn "CentOS/RHEL (firewalld):"
    warn "  sudo firewall-cmd --permanent --add-port=${SFTP_PORT}/tcp"
    warn "  sudo firewall-cmd --reload"
    warn ""
    warn "Cloud Providers (AWS/GCP/Azure/etc):"
    warn "  Update security group rules to allow inbound TCP ${SFTP_PORT}"
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

log "✓ SFTP port configured successfully"
