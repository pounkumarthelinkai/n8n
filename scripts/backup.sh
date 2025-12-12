#!/bin/bash
##############################################################################
# N8N BACKUP SCRIPT
#
# Purpose: Backup n8n Postgres database with rotation
# Usage: ./backup.sh [environment]
#   environment: dev or prod (auto-detected if not specified)
#
# Features:
#   - Full Postgres database dump
#   - Compression (gzip)
#   - Automatic rotation (keep last 14 daily, 8 weekly)
#   - Integrity verification
#   - Checksums for each backup
#   - Backup metadata
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
N8N_DIR="/srv/n8n"
BACKUP_DIR="${N8N_DIR}/backups"
LOG_DIR="${N8N_DIR}/logs"
LOG_FILE="${LOG_DIR}/backup_$(date +%Y%m%d).log"

# Ensure logs directory exists
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"

# Database connection
DB_USER="n8n"
DB_NAME="n8n"

# Retention settings
DAILY_RETENTION=14
WEEKLY_RETENTION=8

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

# Detect environment
detect_environment() {
    if [[ -f "${N8N_DIR}/.env" ]]; then
        source "${N8N_DIR}/.env"
        ENV="${N8N_ENV:-unknown}"
    else
        ENV="unknown"
    fi
    
    # Detect by container name if not in .env
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

# Create backup directory
prepare_backup_directory() {
    log "Preparing backup directory..."
    
    mkdir -p "${BACKUP_DIR}/daily"
    mkdir -p "${BACKUP_DIR}/weekly"
    mkdir -p "${BACKUP_DIR}/manual"
    
    log "Backup directory ready at ${BACKUP_DIR}"
}

# Perform database backup
backup_database() {
    local ENV="$1"
    local DB_CONTAINER="$2"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local DAY_OF_WEEK=$(date +%u)
    
    # Determine backup type (weekly on Sunday, otherwise daily)
    local BACKUP_TYPE="daily"
    if [[ "${DAY_OF_WEEK}" == "7" ]]; then
        BACKUP_TYPE="weekly"
    fi
    
    local BACKUP_FILE="${BACKUP_DIR}/${BACKUP_TYPE}/n8n_${ENV}_${TIMESTAMP}.sql"
    local COMPRESSED_FILE="${BACKUP_FILE}.gz"
    
    log "Starting ${BACKUP_TYPE} backup for ${ENV} environment..."
    
    # Check if container is running
    if ! docker ps | grep -q "${DB_CONTAINER}"; then
        error "Database container ${DB_CONTAINER} is not running"
        exit 1
    fi
    
    # Create database dump
    log "Dumping database..."
    docker exec "${DB_CONTAINER}" pg_dump -U "${DB_USER}" -d "${DB_NAME}" \
        --format=plain \
        --clean \
        --if-exists \
        --no-owner \
        --no-acl \
        > "${BACKUP_FILE}"
    
    if [[ $? -ne 0 ]] || [[ ! -s "${BACKUP_FILE}" ]]; then
        error "Database dump failed"
        rm -f "${BACKUP_FILE}"
        exit 1
    fi
    
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    log "Database dump created (${BACKUP_SIZE})"
    
    # Compress backup
    log "Compressing backup..."
    gzip -f "${BACKUP_FILE}"
    
    if [[ ! -f "${COMPRESSED_FILE}" ]]; then
        error "Compression failed"
        exit 1
    fi
    
    COMPRESSED_SIZE=$(du -h "${COMPRESSED_FILE}" | cut -f1)
    log "Backup compressed (${COMPRESSED_SIZE})"
    
    # Generate checksum
    log "Generating checksum..."
    CHECKSUM=$(sha256sum "${COMPRESSED_FILE}" | awk '{print $1}')
    echo "${CHECKSUM}  $(basename ${COMPRESSED_FILE})" > "${COMPRESSED_FILE}.sha256"
    
    # Create backup metadata
    cat > "${COMPRESSED_FILE}.meta" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "environment": "${ENV}",
  "hostname": "$(hostname)",
  "database": "${DB_NAME}",
  "backup_type": "${BACKUP_TYPE}",
  "original_size": "$(stat -c%s ${COMPRESSED_FILE})",
  "checksum": "${CHECKSUM}",
  "n8n_version": "$(docker exec n8n-${ENV} n8n --version 2>/dev/null | head -n1 || echo 'unknown')",
  "postgres_version": "$(docker exec ${DB_CONTAINER} psql --version | head -n1)"
}
EOF
    
    log "Backup completed: ${COMPRESSED_FILE}"
    echo "${COMPRESSED_FILE}"
}

# Verify backup integrity
verify_backup() {
    local BACKUP_FILE="$1"
    
    log "Verifying backup integrity..."
    
    if [[ ! -f "${BACKUP_FILE}" ]]; then
        error "Backup file not found: ${BACKUP_FILE}"
        return 1
    fi
    
    # Verify checksum
    if [[ -f "${BACKUP_FILE}.sha256" ]]; then
        cd "$(dirname ${BACKUP_FILE})"
        if sha256sum -c "${BACKUP_FILE}.sha256" 2>&1 | grep -q "OK"; then
            log "Checksum verification passed"
        else
            error "Checksum verification failed"
            return 1
        fi
    else
        warning "Checksum file not found - skipping verification"
    fi
    
    # Test decompression
    if gzip -t "${BACKUP_FILE}" 2>/dev/null; then
        log "Compression integrity verified"
    else
        error "Backup file is corrupted"
        return 1
    fi
    
    log "Backup verification passed"
    return 0
}

# Rotate old backups
rotate_backups() {
    log "Rotating old backups..."
    
    # Rotate daily backups (keep last DAILY_RETENTION)
    local DAILY_COUNT=$(find "${BACKUP_DIR}/daily" -name "*.sql.gz" -type f | wc -l)
    if [[ ${DAILY_COUNT} -gt ${DAILY_RETENTION} ]]; then
        log "Rotating daily backups (keep ${DAILY_RETENTION}, found ${DAILY_COUNT})"
        find "${BACKUP_DIR}/daily" -name "*.sql.gz" -type f -printf '%T+ %p\n' | \
            sort -r | tail -n +$((DAILY_RETENTION + 1)) | cut -d' ' -f2- | \
            while read file; do
                log "Removing old daily backup: $(basename ${file})"
                rm -f "${file}" "${file}.sha256" "${file}.meta"
            done
    fi
    
    # Rotate weekly backups (keep last WEEKLY_RETENTION)
    local WEEKLY_COUNT=$(find "${BACKUP_DIR}/weekly" -name "*.sql.gz" -type f | wc -l)
    if [[ ${WEEKLY_COUNT} -gt ${WEEKLY_RETENTION} ]]; then
        log "Rotating weekly backups (keep ${WEEKLY_RETENTION}, found ${WEEKLY_COUNT})"
        find "${BACKUP_DIR}/weekly" -name "*.sql.gz" -type f -printf '%T+ %p\n' | \
            sort -r | tail -n +$((WEEKLY_RETENTION + 1)) | cut -d' ' -f2- | \
            while read file; do
                log "Removing old weekly backup: $(basename ${file})"
                rm -f "${file}" "${file}.sha256" "${file}.meta"
            done
    fi
    
    log "Backup rotation completed"
}

# Display backup statistics
show_backup_stats() {
    log "Backup statistics:"
    
    local DAILY_COUNT=$(find "${BACKUP_DIR}/daily" -name "*.sql.gz" -type f 2>/dev/null | wc -l)
    local WEEKLY_COUNT=$(find "${BACKUP_DIR}/weekly" -name "*.sql.gz" -type f 2>/dev/null | wc -l)
    local MANUAL_COUNT=$(find "${BACKUP_DIR}/manual" -name "*.sql.gz" -type f 2>/dev/null | wc -l)
    
    local DAILY_SIZE=$(du -sh "${BACKUP_DIR}/daily" 2>/dev/null | cut -f1 || echo "0")
    local WEEKLY_SIZE=$(du -sh "${BACKUP_DIR}/weekly" 2>/dev/null | cut -f1 || echo "0")
    local MANUAL_SIZE=$(du -sh "${BACKUP_DIR}/manual" 2>/dev/null | cut -f1 || echo "0")
    local TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "0")
    
    log "  Daily backups: ${DAILY_COUNT} (${DAILY_SIZE})"
    log "  Weekly backups: ${WEEKLY_COUNT} (${WEEKLY_SIZE})"
    log "  Manual backups: ${MANUAL_COUNT} (${MANUAL_SIZE})"
    log "  Total size: ${TOTAL_SIZE}"
    
    # Show oldest and newest backups
    local OLDEST=$(find "${BACKUP_DIR}" -name "*.sql.gz" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort | head -n1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "none")
    local NEWEST=$(find "${BACKUP_DIR}" -name "*.sql.gz" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort -r | head -n1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "none")
    
    log "  Oldest backup: ${OLDEST}"
    log "  Newest backup: ${NEWEST}"
}

# Main execution
main() {
    log "=========================================="
    log "Starting n8n Backup"
    log "=========================================="
    
    # Detect environment
    ENV=$(detect_environment)
    log "Environment: ${ENV}"
    
    # Get database container
    DB_CONTAINER=$(get_db_container "${ENV}")
    log "Database container: ${DB_CONTAINER}"
    
    # Prepare backup directory
    prepare_backup_directory
    
    # Perform backup
    BACKUP_FILE=$(backup_database "${ENV}" "${DB_CONTAINER}")
    
    # Verify backup
    if verify_backup "${BACKUP_FILE}"; then
        log "Backup verified successfully"
    else
        error "Backup verification failed"
        exit 1
    fi
    
    # Rotate old backups
    rotate_backups
    
    # Show statistics
    show_backup_stats
    
    log "=========================================="
    log "Backup completed successfully"
    log "=========================================="
    log "Backup file: ${BACKUP_FILE}"
    log "Log file: ${LOG_FILE}"
}

# Run main function
main

exit 0

