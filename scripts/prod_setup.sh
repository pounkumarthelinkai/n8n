#!/bin/bash
##############################################################################
# PROD VPS N8N SETUP SCRIPT
# 
# Purpose: Install or update n8n + Postgres on PROD VPS
# Usage: ./prod_setup.sh
#
# Environment Variables Required:
#   N8N_ENCRYPTION_KEY - Encryption key for credentials (DIFFERENT from DEV)
#   N8N_HOST - Hostname for n8n instance (e.g., prod-n8n.yourdomain.com)
#   WEBHOOK_URL - Webhook URL for n8n
#   POSTGRES_USER - Database username
#   POSTGRES_PASSWORD - Database password
#   POSTGRES_DB - Database name
#
# SECURITY WARNING:
#   - PROD encryption key MUST be different from DEV
#   - This is a PRODUCTION environment - extra care required
##############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
N8N_DIR="/srv/n8n"
LOG_DIR="${N8N_DIR}/logs"
BACKUP_DIR="${N8N_DIR}/backups"
COMPOSE_FILE="${N8N_DIR}/docker-compose.yml"
ENV_FILE="${N8N_DIR}/.env"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

production_warning() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] PRODUCTION:${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

production_warning "Starting PROD VPS n8n setup..."
production_warning "This is a PRODUCTION environment. Proceeding with caution..."

# Check if n8n is already installed
N8N_INSTALLED=false
if [[ -d "$N8N_DIR" ]] && [[ -f "$COMPOSE_FILE" ]]; then
    N8N_INSTALLED=true
    log "Existing n8n installation detected at ${N8N_DIR}"
    warning "Updating existing PRODUCTION installation..."
fi

# Function to check if Docker is installed
check_docker() {
    if command -v docker &> /dev/null; then
        log "Docker is already installed ($(docker --version))"
        return 0
    else
        return 1
    fi
}

# Function to install Docker
install_docker() {
    log "Installing Docker..."
    
    # Update package index
    apt-get update
    
    # Install prerequisites
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log "Docker installed successfully"
}

# Function to check if Docker Compose is installed
check_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        log "Docker Compose is already installed ($(docker-compose --version))"
        return 0
    elif docker compose version &> /dev/null; then
        log "Docker Compose plugin is already installed"
        return 0
    else
        return 1
    fi
}

# Function to install Docker Compose (standalone)
install_docker_compose() {
    log "Installing Docker Compose..."
    
    # Download latest version
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # Make it executable
    chmod +x /usr/local/bin/docker-compose
    
    # Create symbolic link
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log "Docker Compose installed successfully"
}

# Install Docker and Docker Compose if needed
if ! check_docker; then
    install_docker
fi

if ! check_docker_compose; then
    if ! docker compose version &> /dev/null; then
        install_docker_compose
    fi
fi

# Create directory structure
log "Creating directory structure..."
mkdir -p "${N8N_DIR}"
mkdir -p "${N8N_DIR}/n8n-data"
mkdir -p "${N8N_DIR}/postgres-data"
mkdir -p "${LOG_DIR}"
mkdir -p "${BACKUP_DIR}"
mkdir -p "${N8N_DIR}/migration-temp"

# Set proper permissions
chmod 755 "${N8N_DIR}"
chmod 755 "${LOG_DIR}"
chmod 755 "${BACKUP_DIR}"
chmod 700 "${N8N_DIR}/migration-temp"

# Create or update .env file
log "Configuring environment variables..."

# Production environment checks
if [[ -z "${N8N_ENCRYPTION_KEY:-}" ]]; then
    error "N8N_ENCRYPTION_KEY MUST be set for PRODUCTION"
    error "Generate one with: openssl rand -base64 32"
    error "This MUST be different from DEV key"
    exit 1
fi

if [[ -z "${N8N_HOST:-}" ]]; then
    error "N8N_HOST MUST be set for PRODUCTION"
    exit 1
fi

if [[ -z "${WEBHOOK_URL:-}" ]]; then
    warning "WEBHOOK_URL not set. Using default based on N8N_HOST"
    WEBHOOK_URL="https://${N8N_HOST}"
fi

if [[ -z "${POSTGRES_USER:-}" ]]; then
    POSTGRES_USER="n8n"
fi

if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
    error "POSTGRES_PASSWORD MUST be set for PRODUCTION"
    exit 1
fi

if [[ -z "${POSTGRES_DB:-}" ]]; then
    POSTGRES_DB="n8n"
fi

# Production-specific settings
N8N_PROTOCOL="https"
N8N_PORT="5678"

# Write .env file
cat > "${ENV_FILE}" <<EOF
# N8N Configuration - PRODUCTION Environment
# Generated on $(date)
# WARNING: This is a PRODUCTION environment

# N8N Settings
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_HOST=${N8N_HOST}
N8N_PORT=${N8N_PORT}
N8N_PROTOCOL=${N8N_PROTOCOL}
WEBHOOK_URL=${WEBHOOK_URL}
N8N_EDITOR_BASE_URL=${N8N_PROTOCOL}://${N8N_HOST}
GENERIC_TIMEZONE=UTC
N8N_LOG_LEVEL=warn
N8N_LOG_OUTPUT=file

# Database Settings
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
DB_POSTGRESDB_USER=${POSTGRES_USER}
DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}

# Postgres Settings
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_NON_ROOT_USER=${POSTGRES_USER}
POSTGRES_NON_ROOT_PASSWORD=${POSTGRES_PASSWORD}

# Environment
N8N_ENV=production

# Security Settings
N8N_SECURE_COOKIE=true
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
EOF

chmod 600 "${ENV_FILE}"
log "Environment file created at ${ENV_FILE}"

# Create docker-compose.yml with production optimizations
log "Creating Docker Compose configuration..."

cat > "${COMPOSE_FILE}" <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n-postgres-prod
    restart: always
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}']
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-prod
    restart: always
    ports:
      - "5678:5678"
    environment:
      - DB_TYPE=${DB_TYPE}
      - DB_POSTGRESDB_HOST=${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_POSTGRESDB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=${N8N_PORT}
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - N8N_LOG_LEVEL=${N8N_LOG_LEVEL}
      - N8N_LOG_OUTPUT=${N8N_LOG_OUTPUT}
      - N8N_SECURE_COOKIE=${N8N_SECURE_COOKIE}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=${N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS}
    volumes:
      - ./n8n-data:/home/node/.n8n
      - ./logs:/logs
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ['CMD-SHELL', 'wget --spider -q http://localhost:5678/healthz || exit 1']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - n8n-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "5"

networks:
  n8n-network:
    driver: bridge
EOF

log "Docker Compose file created at ${COMPOSE_FILE}"

# If n8n was already installed, update it carefully
if [[ "$N8N_INSTALLED" == true ]]; then
    production_warning "Updating existing PRODUCTION installation..."
    production_warning "Creating backup before update..."
    
    # Create pre-update backup
    if [[ -f "${N8N_DIR}/scripts/backup.sh" ]]; then
        bash "${N8N_DIR}/scripts/backup.sh" || warning "Backup failed, proceeding anyway"
    fi
    
    cd "${N8N_DIR}"
    docker-compose down
    docker-compose pull
    docker-compose up -d
    log "n8n updated successfully"
else
    log "Starting n8n for the first time..."
    cd "${N8N_DIR}"
    docker-compose up -d
    log "n8n started successfully"
fi

# Wait for services to be healthy
log "Waiting for services to be healthy..."
sleep 15

# Check if services are running
if docker ps | grep -q "n8n-prod"; then
    log "n8n container is running"
else
    error "n8n container failed to start"
    docker-compose logs n8n
    exit 1
fi

if docker ps | grep -q "n8n-postgres-prod"; then
    log "Postgres container is running"
else
    error "Postgres container failed to start"
    docker-compose logs postgres
    exit 1
fi

# Create health check script
log "Creating health check script..."
cat > "${N8N_DIR}/health_check.sh" <<'HEALTHEOF'
#!/bin/bash
# Health check script for n8n - PRODUCTION

HEALTH_ENDPOINT="http://localhost:5678/healthz"
LOG_FILE="/srv/n8n/logs/health_check.log"
ALERT_FILE="/srv/n8n/logs/health_alert.log"

check_health() {
    if curl -sf "${HEALTH_ENDPOINT}" > /dev/null 2>&1; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Health check PASSED" >> "${LOG_FILE}"
        return 0
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Health check FAILED" >> "${LOG_FILE}"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] PRODUCTION n8n health check FAILED" >> "${ALERT_FILE}"
        return 1
    fi
}

# Run health check
if check_health; then
    exit 0
else
    # Try to restart if unhealthy
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Attempting to restart n8n..." >> "${LOG_FILE}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] PRODUCTION: Attempting emergency restart" >> "${ALERT_FILE}"
    cd /srv/n8n && docker-compose restart n8n
    sleep 15
    if check_health; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restart successful" >> "${LOG_FILE}"
        exit 0
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restart failed - MANUAL INTERVENTION REQUIRED" >> "${LOG_FILE}"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] CRITICAL: PRODUCTION n8n restart failed" >> "${ALERT_FILE}"
        exit 1
    fi
fi
HEALTHEOF

chmod +x "${N8N_DIR}/health_check.sh"

# Set up daily backup cron job (more frequent for production)
log "Setting up backup cron jobs..."
# Daily at 2 AM
CRON_JOB_DAILY="0 2 * * * /srv/n8n/scripts/backup.sh >> /srv/n8n/logs/backup.log 2>&1"
# Every 6 hours as additional safety
CRON_JOB_6H="0 */6 * * * /srv/n8n/scripts/backup.sh >> /srv/n8n/logs/backup.log 2>&1"

(crontab -l 2>/dev/null | grep -v "backup.sh"; echo "$CRON_JOB_DAILY"; echo "$CRON_JOB_6H") | crontab -

# Set up health check (every 15 minutes for production)
HEALTH_CRON="*/15 * * * * /srv/n8n/health_check.sh"
(crontab -l 2>/dev/null | grep -v "health_check.sh"; echo "$HEALTH_CRON") | crontab -

# Create scripts directory
mkdir -p "${N8N_DIR}/scripts"

# Set up log rotation with longer retention for production
log "Configuring log rotation..."
cat > /etc/logrotate.d/n8n <<'LOGROTATEEOF'
/srv/n8n/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    missingok
    create 0644 root root
}
LOGROTATEEOF

log "Log rotation configured (30 day retention)"

# Display summary
echo ""
echo "============================================"
echo "  n8n PRODUCTION Environment Setup Complete!"
echo "============================================"
echo ""
production_warning "This is a PRODUCTION environment"
echo ""
echo "n8n URL: ${N8N_PROTOCOL}://${N8N_HOST}"
echo "Installation directory: ${N8N_DIR}"
echo "Logs directory: ${LOG_DIR}"
echo "Backup directory: ${BACKUP_DIR}"
echo ""
echo "To view logs:"
echo "  docker-compose -f ${COMPOSE_FILE} logs -f"
echo ""
echo "To restart services:"
echo "  cd ${N8N_DIR} && docker-compose restart"
echo ""
echo "To stop services:"
echo "  cd ${N8N_DIR} && docker-compose down"
echo ""
echo "IMPORTANT: Credentials saved in ${N8N_DIR}/SETUP_SUMMARY.txt"
echo "Keep this file SECURE and backed up separately"
echo ""
echo "============================================"

# Create a summary file
cat > "${N8N_DIR}/SETUP_SUMMARY.txt" <<SUMMARYEOF
N8N PRODUCTION Environment Setup Summary
Generated on: $(date)

!!!!! PRODUCTION ENVIRONMENT - KEEP SECURE !!!!!

Environment: PRODUCTION
Installation Directory: ${N8N_DIR}
n8n URL: ${N8N_PROTOCOL}://${N8N_HOST}

Credentials (KEEP EXTREMELY SECURE):
- N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
- POSTGRES_USER: ${POSTGRES_USER}
- POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
- POSTGRES_DB: ${POSTGRES_DB}

Service Status:
- n8n container: n8n-prod
- Postgres container: n8n-postgres-prod

Directories:
- Data: ${N8N_DIR}/n8n-data
- Postgres: ${N8N_DIR}/postgres-data
- Logs: ${LOG_DIR}
- Backups: ${BACKUP_DIR}
- Migration temp: ${N8N_DIR}/migration-temp

Automated Tasks:
- Full backup: 2:00 AM daily + every 6 hours (cron)
- Health check: Every 15 minutes (cron)
- Log rotation: Daily, keep 30 days

Useful Commands:
- View logs: cd ${N8N_DIR} && docker-compose logs -f
- Restart: cd ${N8N_DIR} && docker-compose restart
- Stop: cd ${N8N_DIR} && docker-compose down
- Start: cd ${N8N_DIR} && docker-compose up -d
- Backup: ${N8N_DIR}/scripts/backup.sh

Security Notes:
- Encryption key is DIFFERENT from DEV (required)
- HTTPS enforced
- Secure cookies enabled
- Health monitoring active
- Frequent backups enabled
SUMMARYEOF

chmod 600 "${N8N_DIR}/SETUP_SUMMARY.txt"

log "Setup summary saved to ${N8N_DIR}/SETUP_SUMMARY.txt"
production_warning "PROD VPS setup completed successfully!"
production_warning "Remember: This is a PRODUCTION environment - monitor closely"

exit 0

