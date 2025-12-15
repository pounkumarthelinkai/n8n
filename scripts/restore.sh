#!/bin/bash
##############################################################################
# N8N RESTORE SCRIPT
#
# Purpose: Restore n8n Postgres database from backup
# Usage: ./restore.sh <backup_file>
#
# WARNING: This will OVERWRITE the current database!
#          Make sure to create a backup before restoring.
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
N8N_DIR="/srv/n8n"
LOG_DIR="${N8N_DIR}/logs"
LOG_FILE="${LOG_DIR}/restore_$(date +%Y%m%d_%H%M%S).log"

# Database connection
DB_USER="n8n"
DB_NAME="n8n"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "${LOG_FILE}" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "${LOG_FILE}"
}

critical() {
    echo -e "${MAGENTA}[$(date +'%Y-%m-%d %H:%M:%S')] CRITICAL:${NC} $1" | tee -a "${LOG_FILE}"
}

# Detect environment
detect_environment() {
    if [[ -f "${N8N_DIR}/.env" ]]; then
        source "${N8N_DIR}/.env"
        ENV="${N8N_ENV:-unknown}"
    else
        ENV="unknown"
    fi
    
    if [[ "${ENV}" == "unknown" ]]; then
        if docker ps | grep -q "n8n-dev"; then
            ENV="dev"
        elif docker ps | grep -q "n8n-prod"; then
            ENV="prod"
        else
            error "Could not detect environment"
            exit 1
        fi
    fi
    
    echo "${ENV}"
}

# Get database container name
get_db_container() {
    local ENV="$1"
    
    if [[ "${ENV}" == "dev" ]]; then
        echo "n8n-postgres-dev"
    elif [[ "${ENV}" == "prod" ]] || [[ "${ENV}" == "production" ]]; then
        echo "n8n-postgres-prod"
    else
        error "Invalid environment: ${ENV}"
        exit 1
    fi
}

# Verify backup file
verify_backup_file() {
    local BACKUP_FILE="$1"
    
    log "Verifying backup file..."
    
    if [[ ! -f "${BACKUP_FILE}" ]]; then
        error "Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
    
    # Verify checksum if available
    if [[ -f "${BACKUP_FILE}.sha256" ]]; then
        cd "$(dirname ${BACKUP_FILE})"
        if sha256sum -c "${BACKUP_FILE}.sha256" 2>&1 | grep -q "OK"; then
            log "Checksum verification passed"
        else
            error "Checksum verification failed"
            exit 1
        fi
    else
        warning "Checksum file not found - proceeding without verification"
    fi
    
    # Test decompression
    if [[ "${BACKUP_FILE}" == *.gz ]]; then
        if gzip -t "${BACKUP_FILE}" 2>/dev/null; then
            log "Compression integrity verified"
        else
            error "Backup file is corrupted"
            exit 1
        fi
    fi
    
    log "Backup file verification passed"
}

# Create pre-restore backup
create_pre_restore_backup() {
    critical "Creating safety backup before restore..."
    
    if [[ -f "${N8N_DIR}/scripts/backup.sh" ]]; then
        bash "${N8N_DIR}/scripts/backup.sh" || {
            error "Safety backup failed"
            return 1
        }
        log "Safety backup completed"
    else
        warning "Backup script not found - no safety backup created"
    fi
}

# Stop n8n (keep database running)
stop_n8n() {
    local ENV="$1"
    
    log "Stopping n8n container..."
    
    docker stop "n8n-${ENV}" || {
        error "Failed to stop n8n container"
        exit 1
    }
    
    log "n8n stopped"
}

# Start n8n
start_n8n() {
    local ENV="$1"
    
    log "Starting n8n container..."
    
    docker start "n8n-${ENV}" || {
        error "Failed to start n8n container"
        exit 1
    }
    
    # Wait for n8n to be ready
    log "Waiting for n8n to be ready..."
    sleep 10
    
    # Health check
    local MAX_RETRIES=30
    local RETRY=0
    while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
        if docker exec "n8n-${ENV}" wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
            log "n8n is ready"
            return 0
        fi
        RETRY=$((RETRY + 1))
        sleep 2
    done
    
    error "n8n failed to start properly"
    exit 1
}

# Restore database
restore_database() {
    local BACKUP_FILE="$1"
    local DB_CONTAINER="$2"
    
    log "Restoring database from ${BACKUP_FILE}..."
    
    # Decompress if needed
    local SQL_FILE="${BACKUP_FILE}"
    if [[ "${BACKUP_FILE}" == *.gz ]]; then
        log "Decompressing backup..."
        SQL_FILE="/tmp/restore_temp.sql"
        gunzip -c "${BACKUP_FILE}" > "${SQL_FILE}"
    fi
    
    # Copy SQL file to container
    log "Copying backup to database container..."
    docker cp "${SQL_FILE}" "${DB_CONTAINER}:/tmp/restore.sql"
    
    # Restore database
    log "Executing database restore..."
    docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -f /tmp/restore.sql
    
    if [[ $? -ne 0 ]]; then
        error "Database restore failed"
        # Clean up
        docker exec "${DB_CONTAINER}" rm -f /tmp/restore.sql
        [[ "${SQL_FILE}" == "/tmp/restore_temp.sql" ]] && rm -f "${SQL_FILE}"
        exit 1
    fi
    
    # Clean up
    docker exec "${DB_CONTAINER}" rm -f /tmp/restore.sql
    [[ "${SQL_FILE}" == "/tmp/restore_temp.sql" ]] && rm -f "${SQL_FILE}"
    
    log "Database restored successfully"
}

# Verify restore
verify_restore() {
    local DB_CONTAINER="$1"
    
    log "Verifying restore..."
    
    # Check if tables exist
    local TABLE_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')
    
    if [[ ${TABLE_COUNT} -gt 0 ]]; then
        log "Found ${TABLE_COUNT} tables"
    else
        error "No tables found after restore"
        return 1
    fi
    
    # Check workflow count
    local WORKFLOW_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -c \
        "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null | tr -d ' ' || echo "0")
    
    log "Workflows in database: ${WORKFLOW_COUNT}"
    
    log "Restore verification passed"
}

# Main execution
main() {
    critical "=========================================="
    critical "Starting n8n Database Restore"
    critical "WARNING: This will OVERWRITE current data"
    critical "=========================================="
    
    # Check arguments
    if [[ $# -eq 0 ]]; then
        error "Usage: $0 <backup_file>"
        error "Example: $0 /srv/n8n/backups/daily/n8n_prod_20240101_120000.sql.gz"
        exit 1
    fi
    
    BACKUP_FILE="$1"
    
    # Detect environment
    ENV=$(detect_environment)
    log "Environment: ${ENV}"
    
    if [[ "${ENV}" == "prod" ]] || [[ "${ENV}" == "production" ]]; then
        critical "PRODUCTION ENVIRONMENT DETECTED"
        warning "You are about to restore PRODUCTION database"
        read -p "Are you sure? Type 'yes' to continue: " -r
        if [[ ! $REPLY == "yes" ]]; then
            log "Restore cancelled by user"
            exit 0
        fi
    fi
    
    # Get database container
    DB_CONTAINER=$(get_db_container "${ENV}")
    log "Database container: ${DB_CONTAINER}"
    
    # Verify backup file
    verify_backup_file "${BACKUP_FILE}"
    
    # Create safety backup
    if ! create_pre_restore_backup; then
        warning "Failed to create safety backup"
        read -p "Continue without safety backup? Type 'yes' to continue: " -r
        if [[ ! $REPLY == "yes" ]]; then
            log "Restore cancelled by user"
            exit 0
        fi
    fi
    
    # Stop n8n
    stop_n8n "${ENV}"
    
    # Restore database
    restore_database "${BACKUP_FILE}" "${DB_CONTAINER}"
    
    # Verify restore
    verify_restore "${DB_CONTAINER}"
    
    # Start n8n
    start_n8n "${ENV}"
    
    critical "=========================================="
    critical "Restore completed successfully"
    critical "=========================================="
    log "Log file: ${LOG_FILE}"
    log ""
    log "Next steps:"
    log "  1. Verify n8n is working correctly"
    log "  2. Check workflows are present"
    log "  3. Test critical workflows"
}

# Run main function
main "$@"

exit 0

