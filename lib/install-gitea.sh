#!/bin/bash
# File: /opt/scripts/cdn/lib/install-gitea.sh
# Purpose: Download, install, and configure Gitea for version control
#          Creates git user, downloads binary, and sets up systemd service

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Installing Gitea"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

GITEA_VERSION="1.24.6"
GITEA_WORK_DIR="/home/git/gitea"

log "Gitea version: ${GITEA_VERSION}"

# Create git user if doesn't exist
if ! id "git" &>/dev/null; then
    adduser --system --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git
    log "✓ Git user created"
fi

# Download Gitea
log "Downloading Gitea ${GITEA_VERSION}..."
cd /tmp
GITEA_URL="https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64"

if wget -O gitea "${GITEA_URL}"; then
    log "✓ Gitea binary downloaded"
else
    error "Failed to download Gitea from ${GITEA_URL}"
    exit 1
fi

chmod +x gitea
mv gitea /usr/local/bin/gitea
log "✓ Gitea binary installed"

# Create directory structure
log "Creating Gitea directory structure..."
mkdir -p "${GITEA_WORK_DIR}"/{custom/conf,data,log}
chown -R git:git "${GITEA_WORK_DIR}"

# Generate secrets
log "Generating secure secrets..."
SECRET_KEY=$(openssl rand -base64 48)
INTERNAL_TOKEN=$(openssl rand -base64 48)
JWT_SECRET=$(openssl rand -base64 48)

export SECRET_KEY INTERNAL_TOKEN JWT_SECRET
export GIT_DIR="${BASE_DIR}/git"

# Create Gitea configuration
log "Creating Gitea configuration..."
process_template "${SCRIPT_DIR}/templates/gitea-app.ini.template" "${GITEA_WORK_DIR}/custom/conf/app.ini"

chown -R git:git "${GITEA_WORK_DIR}/custom"
log "✓ Gitea configuration created"

# Create systemd service
log "Creating Gitea systemd service..."
cat > /etc/systemd/system/gitea.service << EOFGSRV
[Unit]
Description=Gitea (Git with a cup of tea)
After=syslog.target
After=network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=${GITEA_WORK_DIR}
ExecStart=/usr/local/bin/gitea web --config ${GITEA_WORK_DIR}/custom/conf/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=${GITEA_WORK_DIR}

[Install]
WantedBy=multi-user.target
EOFGSRV

systemctl daemon-reload
systemctl enable gitea
systemctl start gitea

log "Waiting for Gitea to start..."
sleep 5

if systemctl is-active --quiet gitea; then
    log "✓ Gitea service started"
else
    error "Gitea failed to start. Check: sudo journalctl -u gitea -n 50"
    exit 1
fi

# Create admin user
log "Creating Gitea admin user: ${GITEA_ADMIN_USER}..."
su - git -c "cd ${GITEA_WORK_DIR} && /usr/local/bin/gitea admin user create \
    --username '${GITEA_ADMIN_USER}' \
    --password '${GITEA_ADMIN_PASS}' \
    --email '${GITEA_ADMIN_EMAIL}' \
    --admin \
    --config ${GITEA_WORK_DIR}/custom/conf/app.ini" 2>&1 | grep -v "Password" || true

log "✓ Gitea installation completed"
