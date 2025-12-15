#!/bin/bash
##############################################################################
# IMPORT TO PROD - n8n CI/CD Pipeline
#
# Purpose: Import workflows and credentials from DEV to PROD n8n instance
# Usage: ./import_to_prod.sh [--full-db] <package_or_backup_file>
#   --full-db: Import full database (workflows, credentials, users, history)
#              Without flag: Import only workflows and credentials (default)
#
# Workflow (default mode):
#   1. Verify PROD environment and encryption key
#   2. Extract and verify import package
#   3. Import credentials (PROD will re-encrypt with its key)
#   4. Import workflows (all inactive)
#   5. Map workflow names to new PROD IDs
#   6. Selectively activate workflows that were active in DEV
#   7. Toggle webhook-based workflows for registration
#   8. Clean up decrypted files
#   9. Verify import integrity
#
# Workflow (--full-db mode):
#   1. Create backup of PROD database FIRST (for rollback)
#   2. Stop PROD n8n container
#   3. Replace database with DEV backup file
#   4. Run VACUUM to compact and verify integrity
#   5. Sync encryption key from DEV to PROD
#   6. Update config file with correct encryption key
#   7. Restart container and verify health
#
# Security:
#   - PROD backup created before any changes (allows rollback)
#   - Safe SQLite restore prevents corruption
#   - Encryption key synchronization ensures credentials work
#   - Config file updates ensure n8n can decrypt credentials
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
N8N_DIR="/srv/n8n"
IMPORT_DIR="${N8N_DIR}/migration-temp/import"
LOG_DIR="${N8N_DIR}/logs"
LOG_FILE="${LOG_DIR}/import_$(date +%Y%m%d_%H%M%S).log"

# Ensure logs directory exists
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"

# Import files
WORKFLOWS_SANITIZED="${IMPORT_DIR}/workflows_sanitized.json"
CREDENTIALS_SELECTED="${IMPORT_DIR}/credentials_selected.json"
WORKFLOWS_ACTIVE_MAP="${IMPORT_DIR}/workflows_active_map.tsv"
CHECKSUMS_FILE="${IMPORT_DIR}/checksums.txt"
EXPORT_METADATA="${IMPORT_DIR}/export_metadata.json"

# Output files
WORKFLOW_ID_MAP="${IMPORT_DIR}/workflow_id_mapping.tsv"
IMPORT_REPORT="${IMPORT_DIR}/import_report.json"

# Database connection (for PostgreSQL mode)
DB_CONTAINER="n8n-postgres-prod"
DB_USER="n8n"
DB_NAME="n8n"
DB_TYPE=""  # Will be detected: "sqlite" or "postgres"

# Full database transfer mode flag
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

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "${LOG_FILE}"
}

production_warning() {
    echo -e "${MAGENTA}[$(date +'%Y-%m-%d %H:%M:%S')] PRODUCTION:${NC} $1" | tee -a "${LOG_FILE}"
}

# Cleanup function
cleanup() {
    if [[ -d "${IMPORT_DIR}" ]]; then
        warning "Cleaning up sensitive files..."
        # Remove decrypted credentials (non-fatal if it fails)
        rm -f "${CREDENTIALS_SELECTED}" 2>/dev/null || true
        # Also try to clean up any container files if container is still running
        local container=$(get_n8n_container_name 2>/dev/null || echo "")
        if [[ -n "${container}" ]]; then
            docker exec -u root "${container}" rm -f /tmp/credentials_to_import.json /tmp/workflows_to_import.json 2>/dev/null || true
        fi
        # Keep reports and mappings for audit
    fi
}

trap cleanup EXIT

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

# Detect container manager (docker-compose or Coolify)
detect_container_manager() {
    local container=$(get_n8n_container_name)
    local labels=$(docker inspect "${container}" --format '{{.Config.Labels}}' 2>/dev/null || echo "")
    
    if echo "${labels}" | grep -q "coolify"; then
        echo "coolify"
    elif echo "${labels}" | grep -q "com.docker.compose"; then
        echo "docker-compose"
    else
        echo "unknown"
    fi
}

# Get encryption key from DEV backup metadata
get_dev_encryption_key() {
    local backup_dir="$1"
    if [[ -f "${backup_dir}/encryption_key.txt" ]]; then
        cat "${backup_dir}/encryption_key.txt"
    else
        error "Encryption key not found in backup directory"
        exit 1
    fi
}

# Sync encryption key from DEV to PROD
sync_encryption_key() {
    local dev_key="$1"
    production_warning "Synchronizing encryption key from DEV to PROD..."
    
    local manager=$(detect_container_manager)
    local container=$(get_n8n_container_name)
    
    # Update docker-compose.yml if using docker-compose or Coolify
    if [[ "${manager}" == "docker-compose" ]] || [[ "${manager}" == "coolify" ]]; then
        # Find docker-compose.yml file
        local compose_file=$(docker inspect "${container}" --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null | cut -d',' -f1)
        
        if [[ -n "${compose_file}" ]] && [[ -f "${compose_file}" ]]; then
            log "Updating docker-compose.yml with encryption key..."
            # Backup compose file
            cp "${compose_file}" "${compose_file}.backup.$(date +%Y%m%d_%H%M%S)"
            # Add or update encryption key
            if grep -q "N8N_ENCRYPTION_KEY:" "${compose_file}"; then
                sed -i "s|N8N_ENCRYPTION_KEY:.*|N8N_ENCRYPTION_KEY: '${dev_key}'|" "${compose_file}"
            else
                # Add after N8N_BLOCK_ENV_ACCESS_IN_NODE or similar
                sed -i "/N8N_BLOCK_ENV_ACCESS_IN_NODE/a\      N8N_ENCRYPTION_KEY: '${dev_key}'" "${compose_file}"
            fi
            log "docker-compose.yml updated"
        fi
    fi
    
    # Update .env file if it exists
    if [[ -f "${N8N_DIR}/.env" ]]; then
        log "Updating .env file with encryption key..."
        cp "${N8N_DIR}/.env" "${N8N_DIR}/.env.backup.$(date +%Y%m%d_%H%M%S)"
        sed -i "s|N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=${dev_key}|" "${N8N_DIR}/.env"
        log ".env file updated"
    fi
    
    # Update config file in volume
    log "Updating config file in n8n volume..."
    local volume=$(get_n8n_volume_name)
    docker run --rm -v "${volume}:/data" alpine:latest sh -c \
        "cat > /data/config << 'EOF'
{
	\"encryptionKey\": \"${dev_key}\"
}
EOF
chown 1000:1000 /data/config && chmod 600 /data/config" || {
        error "Failed to update config file"
        exit 1
    }
    
    log "Encryption key synchronized successfully"
}

# Detect database type (SQLite or PostgreSQL)
detect_database_type() {
    local container=$(get_n8n_container_name)
    
    # Check if SQLite database file exists
    if docker exec "${container}" test -f /home/node/.n8n/database.sqlite 2>/dev/null; then
        echo "sqlite"
    # Check for PostgreSQL container
    elif docker ps --format '{{.Names}}' | grep -qE "postgres|${DB_CONTAINER}"; then
        # Try to find the actual postgres container name
        local pg_container=$(docker ps --format '{{.Names}}' | grep -E "postgres|${DB_CONTAINER}" | head -n1)
        if [[ -n "${pg_container}" ]]; then
            DB_CONTAINER="${pg_container}"
            echo "postgres"
        else
            echo "sqlite"  # Default to SQLite if can't find postgres
        fi
    else
        echo "sqlite"  # Default to SQLite if can't determine
    fi
}

# Check if running on correct environment
check_environment() {
    production_warning "Checking PRODUCTION environment..."
    
    if [[ ! -f "${N8N_DIR}/.env" ]]; then
        warning "n8n .env file not found at ${N8N_DIR}, continuing..."
    else
        # Source environment
        source "${N8N_DIR}/.env"
    fi
    
    # Check if n8n container is running
    local container=$(get_n8n_container_name 2>/dev/null || echo "")
    if [[ -z "${container}" ]]; then
        error "n8n container is not running"
        exit 1
    fi
    
    # Detect database type
    DB_TYPE=$(detect_database_type)
    if [[ "${DB_TYPE}" == "sqlite" ]]; then
        log "Detected SQLite database mode"
    elif [[ "${DB_TYPE}" == "postgres" ]]; then
        log "Detected PostgreSQL database mode (container: ${DB_CONTAINER})"
    else
        warning "Could not detect database type, defaulting to SQLite"
        DB_TYPE="sqlite"
    fi
    
    production_warning "Environment check passed - PRODUCTION environment confirmed"
}

# Prepare import directory
prepare_import_directory() {
    log "Preparing import directory..."
    
    mkdir -p "${IMPORT_DIR}"
    chmod 700 "${IMPORT_DIR}"
    
    log "Import directory ready at ${IMPORT_DIR}"
}

# Extract and verify package
extract_package() {
    local PACKAGE_PATH="$1"
    
    log "Extracting import package..."
    
    if [[ ! -f "${PACKAGE_PATH}" ]]; then
        error "Package not found: ${PACKAGE_PATH}"
        exit 1
    fi
    
    tar -xzf "${PACKAGE_PATH}" -C "${IMPORT_DIR}"
    
    log "Package extracted to ${IMPORT_DIR}"
}

# Verify checksums
verify_checksums() {
    log "Verifying checksums..."
    
    if [[ ! -f "${CHECKSUMS_FILE}" ]]; then
        error "Checksums file not found"
        exit 1
    fi
    
    cd "${IMPORT_DIR}"
    
    if sha256sum -c "${CHECKSUMS_FILE}"; then
        log "Checksum verification passed"
    else
        error "Checksum verification failed - data integrity compromised"
        exit 1
    fi
}

# Display export metadata
display_metadata() {
    log "Export metadata:"
    
    if [[ -f "${EXPORT_METADATA}" ]]; then
        cat "${EXPORT_METADATA}" | tee -a "${LOG_FILE}"
    else
        warning "Export metadata not found"
    fi
}

# Backup current PROD state before import
backup_before_import() {
    production_warning "Creating backup before import..."
    
    if [[ -f "${N8N_DIR}/scripts/backup.sh" ]]; then
        bash "${N8N_DIR}/scripts/backup.sh" || {
            error "Backup failed - aborting import"
            exit 1
        }
        log "Pre-import backup completed"
    else
        warning "Backup script not found - proceeding without backup"
    fi
}

# Backup PROD database using SQLite .backup command (safe method)
backup_prod_database() {
    production_warning "Creating backup of PROD database before import..."
    
    # Detect container and volume
    local container=$(get_n8n_container_name)
    local volume=$(get_n8n_volume_name)
    
    # Stop n8n for safe backup
    log "Stopping PROD n8n container for safe backup..."
    docker stop "${container}" || {
        error "Failed to stop n8n container"
        exit 1
    }
    
    # Create backup directory with timestamp
    local backup_dir="/root/n8n_backups/prod_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${backup_dir}"
    
    # Create backup using SQLite .backup command
    log "Creating PROD backup using SQLite .backup command..."
    docker run --rm -v "${volume}:/data" -v "${backup_dir}:/backup" \
        alpine:latest sh -c 'apk add --no-cache sqlite > /dev/null 2>&1 && \
        echo .backup /backup/database.sqlite | sqlite3 /data/database.sqlite && \
        echo Backup created successfully' || {
        error "Failed to create PROD backup"
        docker start "${container}"
        exit 1
    }
    
    # Verify integrity
    log "Verifying PROD backup integrity..."
    docker run --rm -v "${backup_dir}:/backup" alpine:latest sh -c \
        'apk add --no-cache sqlite > /dev/null 2>&1 && \
        echo "PRAGMA integrity_check;" | sqlite3 /backup/database.sqlite | grep -q "ok"' || {
        error "PROD backup integrity check failed"
        docker start "${container}"
        exit 1
    }
    
    # Restart n8n (will be stopped again for import)
    log "Restarting PROD n8n container..."
    docker start "${container}" || {
        error "Failed to restart n8n container"
        exit 1
    }
    
    # Wait for n8n to be ready
    sleep 5
    
    log "PROD backup created: ${backup_dir}/database.sqlite"
    echo "${backup_dir}/database.sqlite"
}

# Import full database from DEV backup
import_full_database() {
    local dev_backup_file="$1"
    
    production_warning "Importing full database from DEV backup file..."
    
    # Step 1: Create PROD backup FIRST (before any changes)
    local prod_backup=$(backup_prod_database)
    log "PROD backup created at: ${prod_backup}"
    
    # Step 2: Stop PROD n8n for import
    local container=$(get_n8n_container_name)
    local volume=$(get_n8n_volume_name)
    log "Stopping PROD n8n container for import..."
    docker stop "${container}" || {
        error "Failed to stop n8n container"
        exit 1
    }
    
    # Step 3: Get DEV encryption key
    local backup_dir=$(dirname "${dev_backup_file}")
    local dev_key=$(get_dev_encryption_key "${backup_dir}")
    log "Extracted DEV encryption key"
    
    # Step 4: Replace database with DEV backup and run VACUUM
    log "Replacing PROD database with DEV backup file..."
    docker run --rm -v "${volume}:/data" -v "${backup_dir}:/backup" \
        alpine:latest sh -c 'apk add --no-cache sqlite > /dev/null 2>&1 && \
        rm -f /data/database.sqlite* && \
        cp /backup/$(basename '${dev_backup_file}') /data/database.sqlite && \
        sqlite3 /data/database.sqlite VACUUM && \
        chown 1000:1000 /data/database.sqlite && \
        chmod 600 /data/database.sqlite && \
        echo Database restored and vacuumed' || {
        error "Failed to restore database"
        docker start "${container}"
        exit 1
    }
    
    # Step 5: Sync encryption key (extract from DEV, update PROD)
    sync_encryption_key "${dev_key}"
    
    # Step 6: Restart container
    log "Restarting PROD n8n container..."
    local manager=$(detect_container_manager)
    if [[ "${manager}" == "docker-compose" ]] || [[ "${manager}" == "coolify" ]]; then
        local compose_file=$(docker inspect "${container}" --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null | cut -d',' -f1)
        if [[ -n "${compose_file}" ]] && [[ -f "${compose_file}" ]]; then
            local compose_dir=$(dirname "${compose_file}")
            cd "${compose_dir}"
            docker compose up -d || {
                error "Failed to restart container with docker compose"
                exit 1
            }
        else
            docker start "${container}" || {
                error "Failed to restart container"
                exit 1
            }
        fi
    else
        docker start "${container}" || {
            error "Failed to restart container"
            exit 1
        }
    fi
    
    # Wait for n8n to be ready
    log "Waiting for n8n to be ready..."
    sleep 20
    
    # Step 7: Verify health
    verify_n8n_health
    
    log "Import complete. PROD backup available at: ${prod_backup}"
}

# Verify n8n health
verify_n8n_health() {
    log "Verifying n8n health..."
    local container=$(get_n8n_container_name)
    
    local max_attempts=10
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if docker exec "${container}" wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
            log "n8n health check passed"
            return 0
        fi
        attempt=$((attempt + 1))
        log "Waiting for n8n to be healthy (attempt ${attempt}/${max_attempts})..."
        sleep 5
    done
    
    error "n8n health check failed after ${max_attempts} attempts"
    error "Check logs: docker logs ${container}"
    exit 1
}

# Import credentials
import_credentials() {
    log "Importing credentials to PROD..."
    
    if [[ ! -f "${CREDENTIALS_SELECTED}" ]]; then
        warning "No credentials file found - skipping credential import"
        return
    fi
    
    CREDENTIAL_COUNT=$(python3 -c "import json; print(len(json.load(open('${CREDENTIALS_SELECTED}'))))" 2>/dev/null || echo "0")
    
    if [[ "${CREDENTIAL_COUNT}" == "0" ]]; then
        warning "No credentials to import"
        return
    fi
    
    log "Importing ${CREDENTIAL_COUNT} credentials..."
    
    local container=$(get_n8n_container_name)
    
    # Copy credentials to container
    docker cp "${CREDENTIALS_SELECTED}" "${container}:/tmp/credentials_to_import.json"
    
    # Set proper ownership (n8n container typically runs as user 1000)
    docker exec "${container}" chown 1000:1000 /tmp/credentials_to_import.json 2>/dev/null || true
    
    # Import credentials using n8n CLI (will re-encrypt with PROD key)
    source "${N8N_DIR}/.env"
    docker exec -e N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}" "${container}" \
        n8n import:credentials --input=/tmp/credentials_to_import.json || {
            error "Failed to import credentials"
            # Try to clean up with root user if needed
            docker exec -u root "${container}" rm -f /tmp/credentials_to_import.json 2>/dev/null || true
            exit 1
        }
    
    # Clean up from container (try as root user to ensure it works)
    docker exec -u root "${container}" rm -f /tmp/credentials_to_import.json 2>/dev/null || {
        warning "Could not remove credentials file from container (non-critical)"
    }
    
    log "Credentials imported and re-encrypted with PROD key"
}

# Import workflows
import_workflows() {
    log "Importing workflows to PROD..."
    
    if [[ ! -f "${WORKFLOWS_SANITIZED}" ]]; then
        error "Workflows file not found"
        exit 1
    fi
    
    WORKFLOW_COUNT=$(python3 -c "import json; print(len(json.load(open('${WORKFLOWS_SANITIZED}'))))")
    
    if [[ "${WORKFLOW_COUNT}" == "0" ]]; then
        warning "No workflows to import"
        return
    fi
    
    log "Importing ${WORKFLOW_COUNT} workflows (all inactive)..."
    
    local container=$(get_n8n_container_name)
    
    # Copy workflows to container
    docker cp "${WORKFLOWS_SANITIZED}" "${container}:/tmp/workflows_to_import.json"
    
    # Set proper ownership (n8n container typically runs as user 1000)
    docker exec "${container}" chown 1000:1000 /tmp/workflows_to_import.json 2>/dev/null || true
    
    # Import workflows using n8n CLI with better error handling
    log "Starting workflow import process..."
    
    # Get count before import for comparison
    if [[ "${DB_TYPE}" == "sqlite" ]]; then
        local volume=$(get_n8n_volume_name)
        COUNT_BEFORE=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            if [ -f /data/.n8n/database.sqlite ]; then \
                sqlite3 /data/.n8n/database.sqlite \"SELECT COUNT(*) FROM workflow_entity;\" 2>/dev/null; \
            elif [ -f /data/database.sqlite ]; then \
                sqlite3 /data/database.sqlite \"SELECT COUNT(*) FROM workflow_entity;\" 2>/dev/null; \
            else \
                echo '0'; \
            fi" | tr -d ' ' || echo "0")
    else
        COUNT_BEFORE=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null | tr -d ' ' || echo "0")
    fi
    log "Workflows in PROD before import: ${COUNT_BEFORE}"
    
    # Import workflows individually to catch errors and handle duplicates
    # First, delete ALL existing workflows to ensure clean import
    log "Deleting all existing workflows to ensure clean import..."
    
    if [[ "${DB_TYPE}" == "sqlite" ]]; then
        local volume=$(get_n8n_volume_name)
        # Delete all workflows
        DELETED_COUNT=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            if [ -f /data/.n8n/database.sqlite ]; then \
                sqlite3 /data/.n8n/database.sqlite \"SELECT COUNT(*) FROM workflow_entity;\" 2>/dev/null; \
            elif [ -f /data/database.sqlite ]; then \
                sqlite3 /data/database.sqlite \"SELECT COUNT(*) FROM workflow_entity;\" 2>/dev/null; \
            else \
                echo '0'; \
            fi" | tr -d ' ' || echo "0")
        
        if [[ "${DELETED_COUNT}" != "0" ]]; then
            docker run --rm -v "${volume}:/data" alpine:latest sh -c \
                "apk add --no-cache sqlite > /dev/null 2>&1 && \
                if [ -f /data/.n8n/database.sqlite ]; then \
                    sqlite3 /data/.n8n/database.sqlite \"DELETE FROM workflow_entity;\" 2>/dev/null; \
                elif [ -f /data/database.sqlite ]; then \
                    sqlite3 /data/database.sqlite \"DELETE FROM workflow_entity;\" 2>/dev/null; \
                fi" > /dev/null 2>&1
            log "Deleted ${DELETED_COUNT} existing workflow(s) to allow clean import"
        fi
    else
        # PostgreSQL mode
        DELETED_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null | tr -d ' ' || echo "0")
        
        if [[ "${DELETED_COUNT}" != "0" ]]; then
            docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c \
                "DELETE FROM workflow_entity;" > /dev/null 2>&1
            log "Deleted ${DELETED_COUNT} existing workflow(s) to allow clean import"
        fi
    fi
    
    # Now import all workflows (they should all import successfully since we cleared everything)
    log "Importing workflows..."
    IMPORT_OUTPUT=$(docker exec "${container}" \
        n8n import:workflow --input=/tmp/workflows_to_import.json --separate 2>&1) || {
        error "Failed to import workflows"
        error "Import output: ${IMPORT_OUTPUT}"
        # Try to clean up with root user if needed
        docker exec -u root "${container}" rm -f /tmp/workflows_to_import.json 2>/dev/null || true
        exit 1
    }
    
    # Always log import output for debugging
    if [[ -n "${IMPORT_OUTPUT}" ]]; then
        log "Import output:"
        echo "${IMPORT_OUTPUT}" | while IFS= read -r line; do
            if [[ -n "${line}" ]]; then
                log "  ${line}"
            fi
        done
    fi
    
    # Verify import count matches expected
    if [[ "${DB_TYPE}" == "sqlite" ]]; then
        local volume=$(get_n8n_volume_name)
        COUNT_AFTER=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            if [ -f /data/.n8n/database.sqlite ]; then \
                sqlite3 /data/.n8n/database.sqlite \"SELECT COUNT(*) FROM workflow_entity;\" 2>/dev/null; \
            elif [ -f /data/database.sqlite ]; then \
                sqlite3 /data/database.sqlite \"SELECT COUNT(*) FROM workflow_entity;\" 2>/dev/null; \
            else \
                echo '0'; \
            fi" | tr -d ' ' || echo "0")
    else
        COUNT_AFTER=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null | tr -d ' ' || echo "0")
    fi
    
    ADDED_COUNT=$((COUNT_AFTER - COUNT_BEFORE))
    log "Workflows in PROD after import: ${COUNT_AFTER} (added: ${ADDED_COUNT})"
    
    if [[ "${ADDED_COUNT}" -lt "${WORKFLOW_COUNT}" ]]; then
        warning "Import count mismatch: Expected to add ${WORKFLOW_COUNT} workflows, but only ${ADDED_COUNT} were added"
        warning "Some workflows may have failed to import, were skipped (possibly duplicates), or already existed"
        warning "This is non-fatal - continuing with import process"
    else
        log "Verified: ${ADDED_COUNT} workflows added (expected ${WORKFLOW_COUNT})"
    fi
    
    # Clean up from container (try as root user to ensure it works)
    docker exec -u root "${container}" rm -f /tmp/workflows_to_import.json 2>/dev/null || {
        warning "Could not remove workflows file from container (non-critical)"
    }
    
    log "Workflows imported successfully (all inactive)"
}

# Create workflow ID mapping (DEV name -> PROD ID)
create_workflow_id_mapping() {
    log "Creating workflow ID mapping..."
    
    local container=$(get_n8n_container_name)
    
    if [[ "${DB_TYPE}" == "sqlite" ]]; then
        # SQLite mode: query database file using temporary container
        local volume=$(get_n8n_volume_name)
        if docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            if [ -f /data/.n8n/database.sqlite ]; then \
                sqlite3 /data/.n8n/database.sqlite \"SELECT name, id FROM workflow_entity ORDER BY name;\" 2>/dev/null; \
            elif [ -f /data/database.sqlite ]; then \
                sqlite3 /data/database.sqlite \"SELECT name, id FROM workflow_entity ORDER BY name;\" 2>/dev/null; \
            else \
                echo 'Error: database.sqlite not found' >&2; \
                exit 1; \
            fi" \
            > "${WORKFLOW_ID_MAP}" 2>/dev/null; then
            log "Workflow ID mapping created successfully"
        else
            warning "Failed to create workflow ID mapping from SQLite - workflows will remain inactive"
            warning "You can activate workflows manually in the n8n UI"
            # Create empty file so activation step can skip gracefully
            touch "${WORKFLOW_ID_MAP}"
        fi
    else
        # PostgreSQL mode
        docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -F$'\t' -c \
            "SELECT name, id FROM workflow_entity ORDER BY name;" \
            > "${WORKFLOW_ID_MAP}" || {
            error "Failed to create workflow ID mapping from PostgreSQL"
            exit 1
        }
    fi
    
    log "Workflow ID mapping created"
}

# Activate workflows that were active in DEV
activate_workflows() {
    log "Activating workflows that were active in DEV..."
    
    if [[ ! -f "${WORKFLOWS_ACTIVE_MAP}" ]]; then
        warning "Active state mapping not found - skipping activation"
        return
    fi
    
    if [[ ! -f "${WORKFLOW_ID_MAP}" ]] || [[ ! -s "${WORKFLOW_ID_MAP}" ]]; then
        warning "Workflow ID mapping not available - skipping activation"
        warning "Workflows will remain inactive (you can activate them manually in n8n UI)"
        return
    fi
    
    # Count active workflows in DEV
    ACTIVE_COUNT=$(grep -c $'\ttrue\t' "${WORKFLOWS_ACTIVE_MAP}" || echo "0")
    
    if [[ "${ACTIVE_COUNT}" == "0" ]]; then
        log "No workflows were active in DEV - nothing to activate"
        return
    fi
    
    production_warning "Activating ${ACTIVE_COUNT} workflows in PROD..."
    
    # Use Python to process and activate
    local container=$(get_n8n_container_name)
    local volume=$(get_n8n_volume_name)
    python3 <<PYTHON_SCRIPT
import sys
import subprocess
import os

try:
    # Read active state from DEV
    active_workflows = set()
    with open('${WORKFLOWS_ACTIVE_MAP}', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                name, active = parts[0], parts[1]
                if active.lower() == 'true':
                    active_workflows.add(name)
    
    # Read workflow IDs from PROD
    workflow_ids = {}
    with open('${WORKFLOW_ID_MAP}', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                name, workflow_id = parts[0], parts[1]
                workflow_ids[name] = workflow_id
    
    # Activate workflows
    activated = 0
    db_type = '${DB_TYPE}'
    volume = '${volume}'
    db_container = '${DB_CONTAINER}'
    db_user = '${DB_USER}'
    db_name = '${DB_NAME}'
    
    for name in active_workflows:
        if name in workflow_ids:
            workflow_id = workflow_ids[name]
            # Update database to set active=true
            if db_type == 'sqlite':
                cmd = [
                    'docker', 'run', '--rm', '-v', f'{volume}:/data',
                    'alpine:latest', 'sh', '-c',
                    f"apk add --no-cache sqlite > /dev/null 2>&1 && "
                    f"sqlite3 /data/database.sqlite \"UPDATE workflow_entity SET active = 1 WHERE id = '{workflow_id}';\""
                ]
            else:
                cmd = [
                    'docker', 'exec', db_container,
                    'psql', '-U', db_user, '-d', db_name, '-c',
                    f"UPDATE workflow_entity SET active = true WHERE id = '{workflow_id}';"
                ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                print(f"Activated: {name} (ID: {workflow_id})")
                activated += 1
            else:
                print(f"Failed to activate: {name} - {result.stderr}", file=sys.stderr)
        else:
            print(f"Workflow not found in PROD: {name}", file=sys.stderr)
    
    print(f"Activated {activated} workflows")
    
except Exception as e:
    print(f"Error activating workflows: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    
    if [[ $? -ne 0 ]]; then
        warning "Failed to activate some workflows - they will remain inactive"
        warning "You can activate workflows manually in the n8n UI"
        return 0  # Don't fail the entire import
    fi
    
    log "Workflows activated successfully"
}

# Toggle webhook workflows for registration
toggle_webhook_workflows() {
    log "Toggling webhook-based workflows for registration..."
    
    local container=$(get_n8n_container_name)
    
    # Get list of active workflows with webhooks
    if [[ "${DB_TYPE}" == "sqlite" ]]; then
        local volume=$(get_n8n_volume_name)
        WEBHOOK_WORKFLOW_IDS=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            sqlite3 /data/database.sqlite \"SELECT DISTINCT id FROM workflow_entity WHERE active = 1 AND nodes LIKE '%\\\"type\\\":\\\"n8n-nodes-base.webhook\\\"%';\" 2>/dev/null" || echo "")
    else
        WEBHOOK_WORKFLOW_IDS=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT DISTINCT w.id FROM workflow_entity w WHERE w.active = true AND w.nodes::text LIKE '%\"type\":\"n8n-nodes-base.webhook\"%';" \
            || echo "")
    fi
    
    if [[ -z "${WEBHOOK_WORKFLOW_IDS}" ]]; then
        log "No webhook workflows to toggle"
        return
    fi
    
    WEBHOOK_COUNT=$(echo "${WEBHOOK_WORKFLOW_IDS}" | wc -l)
    log "Found ${WEBHOOK_COUNT} webhook workflows - toggling for registration..."
    
    # Toggle each webhook workflow (deactivate then reactivate)
    while IFS= read -r WORKFLOW_ID; do
        if [[ -n "${WORKFLOW_ID}" ]]; then
            if [[ "${DB_TYPE}" == "sqlite" ]]; then
                local volume=$(get_n8n_volume_name)
                # Deactivate
                docker run --rm -v "${volume}:/data" alpine:latest sh -c \
                    "apk add --no-cache sqlite > /dev/null 2>&1 && \
                    sqlite3 /data/database.sqlite \"UPDATE workflow_entity SET active = 0 WHERE id = '${WORKFLOW_ID}';\" 2>/dev/null" > /dev/null 2>&1
                sleep 1
                # Reactivate
                docker run --rm -v "${volume}:/data" alpine:latest sh -c \
                    "apk add --no-cache sqlite > /dev/null 2>&1 && \
                    sqlite3 /data/database.sqlite \"UPDATE workflow_entity SET active = 1 WHERE id = '${WORKFLOW_ID}';\" 2>/dev/null" > /dev/null 2>&1
            else
                # Deactivate
                docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c \
                    "UPDATE workflow_entity SET active = false WHERE id = ${WORKFLOW_ID};" > /dev/null
                sleep 1
                # Reactivate
                docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c \
                    "UPDATE workflow_entity SET active = true WHERE id = ${WORKFLOW_ID};" > /dev/null
            fi
            log "Toggled webhook workflow ID: ${WORKFLOW_ID}"
        fi
    done <<< "${WEBHOOK_WORKFLOW_IDS}"
    
    # Restart n8n to ensure webhooks are registered
    log "Restarting n8n to register webhooks..."
    docker restart "${container}"
    sleep 10
    
    log "Webhook workflows toggled and registered"
}

# Verify import
verify_import() {
    log "Verifying import..."
    
    local container=$(get_n8n_container_name)
    local volume=$(get_n8n_volume_name)
    
    # Count workflows in PROD
    if [[ "${DB_TYPE}" == "sqlite" ]]; then
        PROD_WORKFLOW_COUNT=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            sqlite3 /data/database.sqlite 'SELECT COUNT(*) FROM workflow_entity;' 2>/dev/null" | tr -d ' ' || echo "0")
        
        PROD_ACTIVE_COUNT=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            sqlite3 /data/database.sqlite 'SELECT COUNT(*) FROM workflow_entity WHERE active = 1;' 2>/dev/null" | tr -d ' ' || echo "0")
        
        PROD_CREDENTIAL_COUNT=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            sqlite3 /data/database.sqlite 'SELECT COUNT(*) FROM credentials_entity;' 2>/dev/null" | tr -d ' ' || echo "0")
    else
        PROD_WORKFLOW_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM workflow_entity;")
        
        PROD_ACTIVE_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM workflow_entity WHERE active = true;")
        
        PROD_CREDENTIAL_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM credentials_entity;")
    fi
    
    log "PROD now has:"
    log "  - ${PROD_WORKFLOW_COUNT} total workflows"
    log "  - ${PROD_ACTIVE_COUNT} active workflows"
    log "  - ${PROD_CREDENTIAL_COUNT} credentials"
    
    # Check if n8n is healthy
    local container=$(get_n8n_container_name)
    if docker exec "${container}" wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
        log "n8n health check passed"
    else
        error "n8n health check failed"
        exit 1
    fi
    
    log "Import verification passed"
}

# Create import report
create_import_report() {
    log "Creating import report..."
    
    local container=$(get_n8n_container_name)
    local volume=$(get_n8n_volume_name)
    
    if [[ "${DB_TYPE}" == "sqlite" ]]; then
        PROD_WORKFLOW_COUNT=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            sqlite3 /data/database.sqlite 'SELECT COUNT(*) FROM workflow_entity;' 2>/dev/null" | tr -d ' ' || echo "0")
        
        PROD_ACTIVE_COUNT=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            sqlite3 /data/database.sqlite 'SELECT COUNT(*) FROM workflow_entity WHERE active = 1;' 2>/dev/null" | tr -d ' ' || echo "0")
        
        PROD_CREDENTIAL_COUNT=$(docker run --rm -v "${volume}:/data" alpine:latest sh -c \
            "apk add --no-cache sqlite > /dev/null 2>&1 && \
            sqlite3 /data/database.sqlite 'SELECT COUNT(*) FROM credentials_entity;' 2>/dev/null" | tr -d ' ' || echo "0")
    else
        PROD_WORKFLOW_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM workflow_entity;")
        
        PROD_ACTIVE_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM workflow_entity WHERE active = true;")
        
        PROD_CREDENTIAL_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM credentials_entity;")
    fi
    
    local container=$(get_n8n_container_name)
    cat > "${IMPORT_REPORT}" <<EOF
{
  "import_timestamp": "$(date -Iseconds)",
  "target_environment": "production",
  "target_host": "$(hostname)",
  "workflows_imported": ${PROD_WORKFLOW_COUNT},
  "workflows_activated": ${PROD_ACTIVE_COUNT},
  "credentials_imported": ${PROD_CREDENTIAL_COUNT},
  "n8n_version": "$(docker exec ${container} n8n --version 2>/dev/null | head -n1 || echo 'unknown')",
  "import_script_version": "1.0.0",
  "status": "success"
}
EOF
    
    log "Import report created"
    cat "${IMPORT_REPORT}" | tee -a "${LOG_FILE}"
}

# Main execution
main() {
    # Parse command line arguments
    if [[ "$#" -gt 0 ]] && [[ "$1" == "--full-db" ]]; then
        FULL_DB_MODE=true
        shift
        
        production_warning "=========================================="
        production_warning "Starting PROD n8n Full Database Import"
        production_warning "=========================================="
        
        check_environment
        
        # Check if backup file path is provided
        if [[ $# -eq 0 ]]; then
            error "Usage: $0 --full-db <path_to_dev_backup_file>"
            error "Example: $0 --full-db /root/n8n_backups/dev_safe_backup_20241212_070800/database.sqlite"
            exit 1
        fi
        
        local backup_file="$1"
        
        if [[ ! -f "${backup_file}" ]]; then
            error "Backup file not found: ${backup_file}"
            exit 1
        fi
        
        # Import full database
        import_full_database "${backup_file}"
        
        production_warning "=========================================="
        production_warning "Full database import completed successfully!"
        production_warning "=========================================="
        log ""
        log "Log file: ${LOG_FILE}"
        log ""
        log "Next steps:"
        log "  1. Verify workflows are working correctly"
        log "  2. Test credentials are decryptable"
        log "  3. Test webhook endpoints"
        log "  4. Monitor logs for any issues"
    else
        production_warning "=========================================="
        production_warning "Starting PROD n8n Import Process (Workflows & Credentials)"
        production_warning "=========================================="
        
        check_environment
        prepare_import_directory
        
        # Check if package path is provided as argument
        if [[ $# -eq 0 ]]; then
            # Auto-fetch latest export from DEV
            log "No package provided - fetching latest export from DEV..."
            
            DEV_VPS_HOST="194.238.17.118"
            DEV_VPS_USER="root"
            
            # Find latest export package on DEV
            LATEST_PACKAGE=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                "${DEV_VPS_USER}@${DEV_VPS_HOST}" \
                "ls -t /srv/n8n/migration-temp/n8n_export_*.tar.gz 2>/dev/null | head -n1" || echo "")
            
            if [[ -z "${LATEST_PACKAGE}" ]]; then
                error "No export package found on DEV VPS"
                error "Please run export script on DEV first, or provide package path:"
                error "  $0 /srv/n8n/migration-temp/n8n_export_YYYYMMDD_HHMMSS.tar.gz"
                exit 1
            fi
            
            PACKAGE_NAME=$(basename "${LATEST_PACKAGE}")
            PACKAGE_PATH="${N8N_DIR}/migration-temp/${PACKAGE_NAME}"
            
            log "Found latest export: ${LATEST_PACKAGE}"
            log "Copying to PROD..."
            
            # Copy package from DEV to PROD
            scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                "${DEV_VPS_USER}@${DEV_VPS_HOST}:${LATEST_PACKAGE}" \
                "${PACKAGE_PATH}" || {
                error "Failed to copy package from DEV"
                exit 1
            }
            
            log "Package copied to: ${PACKAGE_PATH}"
        else
            PACKAGE_PATH="$1"
        fi
        
        extract_package "${PACKAGE_PATH}"
        verify_checksums
        display_metadata
        backup_before_import
        import_credentials
        import_workflows
        create_workflow_id_mapping
        activate_workflows
        toggle_webhook_workflows
        verify_import
        create_import_report
        
        production_warning "=========================================="
        production_warning "Import completed successfully!"
        production_warning "=========================================="
        log ""
        log "Import report: ${IMPORT_REPORT}"
        log "Log file: ${LOG_FILE}"
        log ""
        log "Next steps:"
        log "  1. Verify workflows are working correctly"
        log "  2. Test webhook endpoints"
        log "  3. Monitor logs for any issues"
        log "  4. Remove temporary import files"
        log ""
        warning "Decrypted credential files will be automatically cleaned up"
    fi
}

# Run main function
main "$@"

exit 0

