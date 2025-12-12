#!/bin/bash
##############################################################################
# N8N BACKUP SCRIPT
#
# Purpose: Backup n8n database (PostgreSQL or SQLite) with rotation
# Usage: ./backup.sh [--full-db]
#   --full-db: Create full database backup (for SQLite, uses safe .backup method)
#              Without flag: Standard backup with rotation
#
# Features:
#   - Supports both PostgreSQL and SQLite databases
#   - Full database dump/backup
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

# Full database backup mode flag
FULL_DB_MODE=false

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

# Get n8n container name (auto-detect)
get_n8n_container_name() {
    local container=$(docker ps --format '{{.Names}}' | grep -iE 'n8n' | grep -vE 'postgres|db' | head -n1)
    if [[ -z "${container}" ]]; then
        error "n8n container not found"
        exit 1
    fi
    echo "${container}"
}

# Get n8n Docker volume name (auto-detect)
get_n8n_volume_name() {
    local container=$(get_n8n_container_name)
    local volume=$(docker inspect "${container}" --format '{{range .Mounts}}{{if eq .Destination "/home/node/.n8n"}}{{.Name}}{{end}}{{end}}' | head -n1)
    if [[ -z "${volume}" ]]; then
        # Try alternative detection
        volume=$(docker volume ls --format '{{.Name}}' | grep -i n8n | head -n1)
    fi
    if [[ -z "${volume}" ]]; then
        error "n8n Docker volume not found"
        exit 1
    fi
    echo "${volume}"
}

# Detect database type (SQLite or PostgreSQL)
detect_database_type() {
    local container=$(get_n8n_container_name)
    if docker exec "${container}" test -f /home/node/.n8n/database.sqlite 2>/dev/null; then
        echo "sqlite"
    elif docker ps | grep -q "n8n-postgres-dev\|n8n-postgres-prod"; then
        echo "postgres"
    else
        echo "sqlite"  # Default to SQLite if can't determine
    fi
}

# Get database container name (for PostgreSQL mode)
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

# Backup SQLite database (safe method using .backup)
backup_sqlite_database() {
    local ENV="$1"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local DAY_OF_WEEK=$(date +%u)
    
    # Determine backup type (weekly on Sunday, otherwise daily)
    local BACKUP_TYPE="daily"
    if [[ "${DAY_OF_WEEK}" == "7" ]]; then
        BACKUP_TYPE="weekly"
    fi
    
    local container=$(get_n8n_container_name)
    local volume=$(get_n8n_volume_name)
    
    log "Starting ${BACKUP_TYPE} SQLite backup for ${ENV} environment..."
    
    # Stop n8n for safe backup (if not in full-db mode, we can do online backup)
    if [[ "${FULL_DB_MODE}" == "true" ]]; then
        log "Stopping n8n container for safe backup..."
        docker stop "${container}" || {
            error "Failed to stop n8n container"
            exit 1
        }
    fi
    
    # Create backup file path
    local BACKUP_FILE="${BACKUP_DIR}/${BACKUP_TYPE}/n8n_${ENV}_${TIMESTAMP}.sqlite"
    
    # Create backup using SQLite .backup command (safe, atomic)
    log "Creating SQLite backup using .backup command..."
    local BACKUP_FILENAME="n8n_${ENV}_${TIMESTAMP}.sqlite"
    docker run --rm -v "${volume}:/data" -v "${BACKUP_DIR}/${BACKUP_TYPE}:/backup" \
        alpine:latest sh -c "apk add --no-cache sqlite > /dev/null 2>&1 && \
        if [ -f /data/.n8n/database.sqlite ]; then
            echo .backup /backup/${BACKUP_FILENAME} | sqlite3 /data/.n8n/database.sqlite && \
            echo Backup created successfully
        elif [ -f /data/database.sqlite ]; then
            echo .backup /backup/${BACKUP_FILENAME} | sqlite3 /data/database.sqlite && \
            echo Backup created successfully
        else
            echo 'Error: database.sqlite not found in expected locations'
            exit 1
        fi" || {
        error "Failed to create SQLite backup"
        if [[ "${FULL_DB_MODE}" == "true" ]]; then
            docker start "${container}" || true
        fi
        exit 1
    }
    
    # Verify integrity
    log "Verifying backup integrity..."
    docker run --rm -v "${BACKUP_DIR}/${BACKUP_TYPE}:/backup" alpine:latest sh -c \
        "apk add --no-cache sqlite > /dev/null 2>&1 && \
        echo 'PRAGMA integrity_check;' | sqlite3 /backup/${BACKUP_FILENAME} | grep -q 'ok'" || {
        error "Backup integrity check failed"
        if [[ "${FULL_DB_MODE}" == "true" ]]; then
            docker start "${container}" || true
        fi
        exit 1
    }
    
    # Restart n8n if we stopped it
    if [[ "${FULL_DB_MODE}" == "true" ]]; then
        log "Restarting n8n container..."
        docker start "${container}" || {
            error "Failed to restart n8n container"
            exit 1
        }
        sleep 5
    fi
    
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    log "SQLite backup created (${BACKUP_SIZE})"
    
    # Compress backup
    log "Compressing backup..."
    gzip -f "${BACKUP_FILE}"
    local COMPRESSED_FILE="${BACKUP_FILE}.gz"
    
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
  "database_type": "sqlite",
  "backup_type": "${BACKUP_TYPE}",
  "original_size": "$(stat -c%s ${COMPRESSED_FILE})",
  "checksum": "${CHECKSUM}",
  "n8n_version": "$(docker exec ${container} n8n --version 2>/dev/null | head -n1 || echo 'unknown')",
  "backup_method": "sqlite_backup"
}
EOF
    
    log "Backup completed: ${COMPRESSED_FILE}"
    echo "${COMPRESSED_FILE}"
}

# Backup PostgreSQL database
backup_postgres_database() {
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
    
    log "Starting ${BACKUP_TYPE} PostgreSQL backup for ${ENV} environment..."
    
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
    local container=$(get_n8n_container_name)
    cat > "${COMPRESSED_FILE}.meta" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "environment": "${ENV}",
  "hostname": "$(hostname)",
  "database_type": "postgresql",
  "database": "${DB_NAME}",
  "backup_type": "${BACKUP_TYPE}",
  "original_size": "$(stat -c%s ${COMPRESSED_FILE})",
  "checksum": "${CHECKSUM}",
  "n8n_version": "$(docker exec ${container} n8n --version 2>/dev/null | head -n1 || echo 'unknown')",
  "postgres_version": "$(docker exec ${DB_CONTAINER} psql --version 2>/dev/null | head -n1 || echo 'unknown')"
}
EOF
    
    log "Backup completed: ${COMPRESSED_FILE}"
    echo "${COMPRESSED_FILE}"
}

# Perform database backup (wrapper function)
backup_database() {
    local ENV="$1"
    local db_type=$(detect_database_type)
    
    if [[ "${db_type}" == "sqlite" ]]; then
        backup_sqlite_database "${ENV}"
    else
        local DB_CONTAINER=$(get_db_container "${ENV}")
        backup_postgres_database "${ENV}" "${DB_CONTAINER}"
    fi
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
    
    # For SQLite backups, verify database integrity after decompression
    if [[ "${BACKUP_FILE}" == *.sqlite.gz ]]; then
        log "Verifying SQLite database integrity..."
        local TEMP_DB=$(mktemp)
        gunzip -c "${BACKUP_FILE}" > "${TEMP_DB}"
        
        docker run --rm -v "$(dirname ${TEMP_DB}):/backup" alpine:latest sh -c \
            'apk add --no-cache sqlite > /dev/null 2>&1 && \
            echo "PRAGMA integrity_check;" | sqlite3 /backup/$(basename '${TEMP_DB}') | grep -q "ok"' || {
            error "SQLite database integrity check failed"
            rm -f "${TEMP_DB}"
            return 1
        }
        
        rm -f "${TEMP_DB}"
        log "SQLite database integrity verified"
    fi
    
    log "Backup verification passed"
    return 0
}

# Rotate old backups
rotate_backups() {
    log "Rotating old backups..."
    
    # Rotate daily backups (keep last DAILY_RETENTION) - handle both .sql.gz and .sqlite.gz
    local DAILY_COUNT=$(find "${BACKUP_DIR}/daily" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f | wc -l)
    if [[ ${DAILY_COUNT} -gt ${DAILY_RETENTION} ]]; then
        log "Rotating daily backups (keep ${DAILY_RETENTION}, found ${DAILY_COUNT})"
        find "${BACKUP_DIR}/daily" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f -printf '%T+ %p\n' | \
            sort -r | tail -n +$((DAILY_RETENTION + 1)) | cut -d' ' -f2- | \
            while read file; do
                log "Removing old daily backup: $(basename ${file})"
                rm -f "${file}" "${file}.sha256" "${file}.meta"
            done
    fi
    
    # Rotate weekly backups (keep last WEEKLY_RETENTION) - handle both .sql.gz and .sqlite.gz
    local WEEKLY_COUNT=$(find "${BACKUP_DIR}/weekly" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f | wc -l)
    if [[ ${WEEKLY_COUNT} -gt ${WEEKLY_RETENTION} ]]; then
        log "Rotating weekly backups (keep ${WEEKLY_RETENTION}, found ${WEEKLY_COUNT})"
        find "${BACKUP_DIR}/weekly" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f -printf '%T+ %p\n' | \
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
    
    local DAILY_COUNT=$(find "${BACKUP_DIR}/daily" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f 2>/dev/null | wc -l)
    local WEEKLY_COUNT=$(find "${BACKUP_DIR}/weekly" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f 2>/dev/null | wc -l)
    local MANUAL_COUNT=$(find "${BACKUP_DIR}/manual" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f 2>/dev/null | wc -l)
    
    local DAILY_SIZE=$(du -sh "${BACKUP_DIR}/daily" 2>/dev/null | cut -f1 || echo "0")
    local WEEKLY_SIZE=$(du -sh "${BACKUP_DIR}/weekly" 2>/dev/null | cut -f1 || echo "0")
    local MANUAL_SIZE=$(du -sh "${BACKUP_DIR}/manual" 2>/dev/null | cut -f1 || echo "0")
    local TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "0")
    
    log "  Daily backups: ${DAILY_COUNT} (${DAILY_SIZE})"
    log "  Weekly backups: ${WEEKLY_COUNT} (${WEEKLY_SIZE})"
    log "  Manual backups: ${MANUAL_COUNT} (${MANUAL_SIZE})"
    log "  Total size: ${TOTAL_SIZE}"
    
    # Show oldest and newest backups
    local OLDEST=$(find "${BACKUP_DIR}" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort | head -n1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "none")
    local NEWEST=$(find "${BACKUP_DIR}" \( -name "*.sql.gz" -o -name "*.sqlite.gz" \) -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort -r | head -n1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "none")
    
    log "  Oldest backup: ${OLDEST}"
    log "  Newest backup: ${NEWEST}"
}

# Main execution
main() {
    # Parse command line arguments
    if [[ "$#" -gt 0 ]] && [[ "$1" == "--full-db" ]]; then
        FULL_DB_MODE=true
    fi
    
    log "=========================================="
    log "Starting n8n Backup"
    log "=========================================="
    
    # Detect environment
    ENV=$(detect_environment)
    log "Environment: ${ENV}"
    
    # Detect database type
    local db_type=$(detect_database_type)
    log "Database type: ${db_type}"
    
    # Prepare backup directory
    prepare_backup_directory
    
    # Perform backup
    BACKUP_FILE=$(backup_database "${ENV}")
    
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
main "$@"

exit 0

