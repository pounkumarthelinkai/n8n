#!/bin/bash
##############################################################################
# EXPORT FROM DEV - n8n CI/CD Pipeline
#
# Purpose: Export workflows and credentials from DEV n8n instance
# Usage: ./export_from_dev.sh [--full-db]
#   --full-db: Export full database (workflows, credentials, users, history)
#              Without flag: Export only workflows and credentials (default)
#
# Workflow (default mode):
#   1. Export all workflows from DEV
#   2. Export credentials (DECRYPTED) from DEV
#   3. Create workflow active state mapping
#   4. Sanitize workflows (set all active=false)
#   5. Filter credentials by allowlist
#   6. Generate checksums for verification
#   7. Package artifacts for import to PROD
#
# Workflow (--full-db mode):
#   1. Create safe SQLite backup using .backup command
#   2. Verify backup integrity
#   3. Extract encryption key from config
#   4. Package backup file and encryption key info
#
# Security:
#   - Credentials are temporarily decrypted (default mode)
#   - Allowlist filtering applied (default mode)
#   - Safe SQLite backup prevents corruption (full-db mode)
#   - Artifacts secured with proper permissions
#   - Checksums for integrity verification
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
N8N_DIR="/srv/n8n"
EXPORT_DIR="${N8N_DIR}/migration-temp/export"
LOG_DIR="${N8N_DIR}/logs"
LOG_FILE="${LOG_DIR}/export_$(date +%Y%m%d_%H%M%S).log"
ALLOWLIST_FILE="${N8N_DIR}/credential_allowlist.txt"

# Ensure logs directory exists
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"

# Output files
WORKFLOWS_RAW="${EXPORT_DIR}/workflows_raw.json"
WORKFLOWS_SANITIZED="${EXPORT_DIR}/workflows_sanitized.json"
WORKFLOWS_ACTIVE_MAP="${EXPORT_DIR}/workflows_active_map.tsv"
WORKFLOWS_OWNER_MAP="${EXPORT_DIR}/workflows_owner_map.tsv"
CREDENTIALS_RAW="${EXPORT_DIR}/credentials_raw.json"
CREDENTIALS_SELECTED="${EXPORT_DIR}/credentials_selected.json"
CHECKSUMS_FILE="${EXPORT_DIR}/checksums.txt"
EXPORT_METADATA="${EXPORT_DIR}/export_metadata.json"

# Database connection (for PostgreSQL mode)
DB_CONTAINER="n8n-postgres-dev"
DB_USER="n8n"
DB_NAME="n8n"
DB_HOST="localhost"

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

# Cleanup function
cleanup() {
    if [[ -d "${EXPORT_DIR}" ]]; then
        warning "Cleaning up sensitive files..."
        # Keep sanitized versions but remove raw exports
        rm -f "${CREDENTIALS_RAW}"
        rm -f "${WORKFLOWS_RAW}"
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

# Detect database type (SQLite or PostgreSQL)
detect_database_type() {
    local container=$(get_n8n_container_name)
    if docker exec "${container}" test -f /home/node/.n8n/database.sqlite 2>/dev/null; then
        echo "sqlite"
    elif docker ps | grep -q "${DB_CONTAINER}"; then
        echo "postgres"
    else
        echo "sqlite"  # Default to SQLite if can't determine
    fi
}

# Get encryption key from config file
get_encryption_key() {
    local container=$(get_n8n_container_name)
    local key=$(docker exec "${container}" cat /home/node/.n8n/config 2>/dev/null | grep -o '"encryptionKey"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    if [[ -z "${key}" ]]; then
        error "Could not extract encryption key from config file"
        exit 1
    fi
    echo "${key}"
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_file="$1"
    log "Verifying backup integrity..."
    
    docker run --rm -v "$(dirname ${backup_file}):/backup" alpine:latest sh -c \
        'apk add --no-cache sqlite > /dev/null 2>&1 && \
        echo "PRAGMA integrity_check;" | sqlite3 /backup/$(basename '${backup_file}') | grep -q "ok"' || {
        error "Backup integrity check failed - database may be corrupted"
        exit 1
    }
    
    log "Backup integrity verified"
}

# Check if running on correct environment
check_environment() {
    log "Checking environment..."
    
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
    
    # For PostgreSQL mode, check if postgres container is running
    if [[ "${FULL_DB_MODE}" == "false" ]]; then
        if ! docker ps | grep -q "${DB_CONTAINER}"; then
            warning "Postgres container ${DB_CONTAINER} not found, assuming SQLite mode"
        fi
    fi
    
    log "Environment check passed - DEV environment confirmed"
}

# Create export directory
prepare_export_directory() {
    log "Preparing export directory..."
    
    rm -rf "${EXPORT_DIR}"
    mkdir -p "${EXPORT_DIR}"
    chmod 700 "${EXPORT_DIR}"
    
    log "Export directory created at ${EXPORT_DIR}"
}

# Export workflows from database
export_workflows() {
    log "Exporting workflows from DEV..."
    
    local container=$(get_n8n_container_name)
    local db_type=$(detect_database_type)
    
    if [[ "${db_type}" == "sqlite" ]]; then
        log "Using SQLite mode - exporting via n8n CLI..."
        
        # Export workflows using n8n CLI
        docker exec "${container}" n8n export:workflow --all --output=/tmp/workflows_export.json || {
            error "Failed to export workflows via n8n CLI"
            exit 1
        }
        
        # Copy exported workflows out of container
        docker cp "${container}:/tmp/workflows_export.json" "${WORKFLOWS_RAW}"
        
        # Clean up from container
        docker exec "${container}" rm -f /tmp/workflows_export.json
        
        # Convert n8n export format to array format if needed
        if ! python3 -c "import json; json.load(open('${WORKFLOWS_RAW}'))" 2>/dev/null; then
            # If export is not valid JSON, try to fix it
            python3 <<PYTHON_SCRIPT
import json
import sys

try:
    with open('${WORKFLOWS_RAW}', 'r') as f:
        content = f.read().strip()
        # Try to parse as JSON
        if content.startswith('['):
            workflows = json.loads(content)
        else:
            # If it's a single object, wrap in array
            workflows = [json.loads(content)]
        
        with open('${WORKFLOWS_RAW}', 'w') as f:
            json.dump(workflows, f, indent=2)
except Exception as e:
    print(f"Error processing workflows: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
        fi
        
        # Count workflows
        WORKFLOW_COUNT=$(python3 -c "import json; print(len(json.load(open('${WORKFLOWS_RAW}'))))" 2>/dev/null || echo "0")
        
        # Create active state mapping from exported workflows
        log "Creating workflow active state mapping..."
        python3 <<PYTHON_SCRIPT
import json
import sys

try:
    with open('${WORKFLOWS_RAW}', 'r') as f:
        workflows = json.load(f)
    
    with open('${WORKFLOWS_ACTIVE_MAP}', 'w') as f:
        for wf in workflows:
            name = wf.get('name', 'Unknown')
            active = str(wf.get('active', False)).lower()
            wf_id = wf.get('id', '')
            f.write(f"{name}\t{active}\t{wf_id}\n")
    
    # Also create owner/project mapping
    with open('${WORKFLOWS_OWNER_MAP}', 'w') as f:
        for wf in workflows:
            name = wf.get('name', 'Unknown')
            project_id = wf.get('projectId', '')
            # Get project name if available
            project = wf.get('project', {})
            project_name = project.get('name', '') if isinstance(project, dict) else ''
            f.write(f"{name}\t{project_id}\t{project_name}\n")
except Exception as e:
    print(f"Error creating active map: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
        
        log "Exported ${WORKFLOW_COUNT} workflows via n8n CLI"
    else
        log "Using PostgreSQL mode - exporting via database..."
        
        # Export workflows from PostgreSQL database
        docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -F"," -c \
            "SELECT json_agg(row_to_json(t)) FROM (SELECT * FROM workflow_entity ORDER BY name) t;" \
            > "${WORKFLOWS_RAW}"
        
        if [[ ! -s "${WORKFLOWS_RAW}" ]]; then
            error "Failed to export workflows or no workflows found"
            exit 1
        fi
        
        # Count workflows
        WORKFLOW_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c \
            "SELECT COUNT(*) FROM workflow_entity;")
        
        log "Exported ${WORKFLOW_COUNT} workflows"
        
        # Create active state mapping (workflow name -> active status)
        log "Creating workflow active state mapping..."
        docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -F$'\t' -c \
            "SELECT name, active, id FROM workflow_entity ORDER BY name;" \
            > "${WORKFLOWS_ACTIVE_MAP}"
    fi
    
    log "Active state mapping created"
}

# Sanitize workflows (set all to inactive)
sanitize_workflows() {
    log "Sanitizing workflows (setting all to inactive)..."
    
    # Use Python to sanitize JSON
    python3 <<PYTHON_SCRIPT
import json
import sys

try:
    with open('${WORKFLOWS_RAW}', 'r') as f:
        workflows = json.load(f)
    
    if not workflows:
        print("No workflows to sanitize", file=sys.stderr)
        sys.exit(0)
    
    # Set all workflows to inactive and remove IDs
    # Preserve owner/project information for proper assignment
    sanitized_count = 0
    for workflow in workflows:
        # Set inactive
        workflow['active'] = False
        
        # Remove old IDs (will be regenerated on import)
        if 'id' in workflow:
            del workflow['id']
        
        # Preserve owner/project information (projectId, project) if present
        # This ensures workflows are assigned to correct user/project
        # Note: n8n CLI import may still assign to current user, but we preserve the data
        
        sanitized_count += 1
    
    with open('${WORKFLOWS_SANITIZED}', 'w') as f:
        json.dump(workflows, f, indent=2)
    
    print(f"Sanitized {sanitized_count} workflows")
    
except Exception as e:
    print(f"Error sanitizing workflows: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    
    if [[ $? -ne 0 ]]; then
        error "Failed to sanitize workflows"
        exit 1
    fi
    
    log "Workflows sanitized successfully"
}

# Export credentials (DECRYPTED)
export_credentials() {
    log "Exporting credentials from DEV..."
    warning "Credentials will be temporarily DECRYPTED - handle with care"
    
    local container=$(get_n8n_container_name)
    local db_type=$(detect_database_type)
    
    # Check if encryption key is available
    if [[ -f "${N8N_DIR}/.env" ]]; then
        source "${N8N_DIR}/.env"
    fi
    
    # Always use n8n CLI for credential export (works for both SQLite and PostgreSQL)
    log "Exporting credentials via n8n CLI..."
    
    # Use n8n's built-in export which handles decryption
    docker exec "${container}" n8n export:credentials --all --output=/tmp/credentials_decrypted.json || {
        warning "Failed to export credentials via n8n CLI, checking if any exist..."
        echo "[]" > "${CREDENTIALS_RAW}"
        return
    }
    
    # Copy decrypted credentials out of container
    docker cp "${container}:/tmp/credentials_decrypted.json" "${CREDENTIALS_RAW}"
    
    # Clean up from container
    docker exec "${container}" rm -f /tmp/credentials_decrypted.json
    
    # Validate and count credentials
    if [[ ! -s "${CREDENTIALS_RAW}" ]]; then
        warning "No credentials found or failed to export"
        echo "[]" > "${CREDENTIALS_RAW}"
        return
    fi
    
    # Ensure valid JSON array
    if ! python3 -c "import json; json.load(open('${CREDENTIALS_RAW}'))" 2>/dev/null; then
        python3 <<PYTHON_SCRIPT
import json
import sys

try:
    with open('${CREDENTIALS_RAW}', 'r') as f:
        content = f.read().strip()
        if content.startswith('['):
            creds = json.loads(content)
        else:
            creds = [json.loads(content)]
        
        with open('${CREDENTIALS_RAW}', 'w') as f:
            json.dump(creds, f, indent=2)
except Exception as e:
    print(f"Error processing credentials: {e}", file=sys.stderr)
    with open('${CREDENTIALS_RAW}', 'w') as f:
        json.dump([], f)
PYTHON_SCRIPT
    fi
    
    CREDENTIAL_COUNT=$(python3 -c "import json; print(len(json.load(open('${CREDENTIALS_RAW}'))))" 2>/dev/null || echo "0")
    
    log "Exported ${CREDENTIAL_COUNT} credentials (decrypted)"
    log "Credentials decrypted successfully"
}

# Filter credentials by allowlist
filter_credentials() {
    log "Filtering credentials by allowlist..."
    
    # Create default allowlist if it doesn't exist
    if [[ ! -f "${ALLOWLIST_FILE}" ]]; then
        warning "Credential allowlist not found at ${ALLOWLIST_FILE}"
        warning "Creating default allowlist (allows all credentials)"
        echo "*" > "${ALLOWLIST_FILE}"
    fi
    
    # Read allowlist
    ALLOWLIST=$(cat "${ALLOWLIST_FILE}" | grep -v '^#' | grep -v '^$' || true)
    
    if [[ -z "${ALLOWLIST}" ]] || [[ "${ALLOWLIST}" == "*" ]]; then
        warning "Allowlist is empty or set to '*' - ALL credentials will be exported"
        warning "Consider creating a specific allowlist for security"
        cp "${CREDENTIALS_RAW}" "${CREDENTIALS_SELECTED}"
        return
    fi
    
    # Filter credentials using Python
    python3 <<PYTHON_SCRIPT
import json
import sys
import re

try:
    with open('${CREDENTIALS_RAW}', 'r') as f:
        credentials = json.load(f)
    
    if not credentials:
        print("No credentials to filter")
        with open('${CREDENTIALS_SELECTED}', 'w') as f:
            json.dump([], f)
        sys.exit(0)
    
    # Read allowlist
    allowlist = """${ALLOWLIST}""".strip().split('\n')
    allowlist = [pattern.strip() for pattern in allowlist if pattern.strip()]
    
    # Filter credentials
    selected = []
    for cred in credentials:
        name = cred.get('name', '')
        # Check if name matches any pattern in allowlist
        for pattern in allowlist:
            # Convert shell-style wildcards to regex
            regex_pattern = pattern.replace('*', '.*').replace('?', '.')
            if re.match(f'^{regex_pattern}$', name):
                selected.append(cred)
                print(f"Selected credential: {name}")
                break
    
    with open('${CREDENTIALS_SELECTED}', 'w') as f:
        json.dump(selected, f, indent=2)
    
    print(f"Filtered {len(credentials)} credentials -> {len(selected)} selected")
    
except Exception as e:
    print(f"Error filtering credentials: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    
    if [[ $? -ne 0 ]]; then
        error "Failed to filter credentials"
        exit 1
    fi
    
    log "Credentials filtered successfully"
}

# Generate checksums for verification
generate_checksums() {
    log "Generating checksums..."
    
    cd "${EXPORT_DIR}"
    
    sha256sum workflows_sanitized.json > "${CHECKSUMS_FILE}"
    sha256sum credentials_selected.json >> "${CHECKSUMS_FILE}"
    sha256sum workflows_active_map.tsv >> "${CHECKSUMS_FILE}"
    if [[ -f "${WORKFLOWS_OWNER_MAP}" ]]; then
        sha256sum workflows_owner_map.tsv >> "${CHECKSUMS_FILE}"
    fi
    
    log "Checksums generated"
    cat "${CHECKSUMS_FILE}" | tee -a "${LOG_FILE}"
}

# Create export metadata
create_metadata() {
    log "Creating export metadata..."
    
    local container=$(get_n8n_container_name)
    WORKFLOW_COUNT=$(python3 -c "import json; print(len(json.load(open('${WORKFLOWS_SANITIZED}'))))")
    CREDENTIAL_COUNT=$(python3 -c "import json; print(len(json.load(open('${CREDENTIALS_SELECTED}'))))")
    ACTIVE_WORKFLOW_COUNT=$(grep -c $'\ttrue\t' "${WORKFLOWS_ACTIVE_MAP}" || echo "0")
    
    cat > "${EXPORT_METADATA}" <<EOF
{
  "export_timestamp": "$(date -Iseconds)",
  "source_environment": "dev",
  "source_host": "$(hostname)",
  "workflow_count": ${WORKFLOW_COUNT},
  "credential_count": ${CREDENTIAL_COUNT},
  "active_workflow_count": ${ACTIVE_WORKFLOW_COUNT},
  "n8n_version": "$(docker exec ${container} n8n --version 2>/dev/null | head -n1 || echo 'unknown')",
  "export_script_version": "1.0.0"
}
EOF
    
    log "Export metadata created"
    cat "${EXPORT_METADATA}" | tee -a "${LOG_FILE}"
}

# Create export package
create_export_package() {
    log "Creating export package..."
    
    PACKAGE_NAME="n8n_export_$(date +%Y%m%d_%H%M%S).tar.gz"
    PACKAGE_PATH="${N8N_DIR}/migration-temp/${PACKAGE_NAME}"
    
    cd "${EXPORT_DIR}"
    tar -czf "${PACKAGE_PATH}" \
        workflows_sanitized.json \
        credentials_selected.json \
        workflows_active_map.tsv \
        workflows_owner_map.tsv \
        checksums.txt \
        export_metadata.json
    
    chmod 600 "${PACKAGE_PATH}"
    
    log "Export package created: ${PACKAGE_PATH}"
    echo "${PACKAGE_PATH}"
}

# Validate export
validate_export() {
    log "Validating export..."
    
    # Check if files exist and are not empty
    for file in "${WORKFLOWS_SANITIZED}" "${CREDENTIALS_SELECTED}" "${WORKFLOWS_ACTIVE_MAP}"; do
        if [[ ! -f "${file}" ]]; then
            error "Missing export file: ${file}"
            exit 1
        fi
    done
    
    # Validate JSON files
    python3 <<PYTHON_SCRIPT
import json
import sys

try:
    with open('${WORKFLOWS_SANITIZED}', 'r') as f:
        workflows = json.load(f)
        if not isinstance(workflows, list):
            raise ValueError("Workflows must be a list")
    
    with open('${CREDENTIALS_SELECTED}', 'r') as f:
        credentials = json.load(f)
        if not isinstance(credentials, list):
            raise ValueError("Credentials must be a list")
    
    print("Export validation passed")
    
except Exception as e:
    print(f"Export validation failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    
    if [[ $? -ne 0 ]]; then
        error "Export validation failed"
        exit 1
    fi
    
    log "Export validation passed"
}

# Backup DEV database using SQLite .backup command (safe method)
backup_dev_database() {
    log "Creating safe SQLite backup of DEV database..."
    
    # Detect container and volume
    local container=$(get_n8n_container_name)
    local volume=$(get_n8n_volume_name)
    
    # Stop n8n for safe backup
    log "Stopping DEV n8n container for safe backup..."
    docker stop "${container}" || {
        error "Failed to stop n8n container"
        exit 1
    }
    
    # Create backup directory with timestamp
    local backup_dir="/root/n8n_backups/dev_safe_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${backup_dir}"
    
    # Create backup using SQLite .backup command (safe, atomic)
    log "Creating backup using SQLite .backup command..."
    docker run --rm -v "${volume}:/data" -v "${backup_dir}:/backup" \
        alpine:latest sh -c 'apk add --no-cache sqlite > /dev/null 2>&1 && \
        echo .backup /backup/database.sqlite | sqlite3 /data/database.sqlite && \
        echo Backup created successfully' || {
        error "Failed to create backup"
        docker start "${container}"
        exit 1
    }
    
    # Verify integrity
    verify_backup_integrity "${backup_dir}/database.sqlite"
    
    # Get encryption key
    local encryption_key=$(get_encryption_key)
    
    # Save encryption key info
    echo "${encryption_key}" > "${backup_dir}/encryption_key.txt"
    chmod 600 "${backup_dir}/encryption_key.txt"
    
    # Create metadata
    cat > "${backup_dir}/backup_metadata.json" <<EOF
{
  "backup_timestamp": "$(date -Iseconds)",
  "source_environment": "dev",
  "source_host": "$(hostname)",
  "backup_method": "sqlite_backup",
  "database_size": "$(du -h ${backup_dir}/database.sqlite | cut -f1)",
  "n8n_version": "$(docker exec ${container} n8n --version 2>/dev/null | head -n1 || echo 'unknown')",
  "backup_script_version": "2.0.0"
}
EOF
    
    # Restart n8n
    log "Restarting DEV n8n container..."
    docker start "${container}" || {
        error "Failed to restart n8n container"
        exit 1
    }
    
    # Wait for n8n to be ready
    sleep 5
    
    log "DEV backup created: ${backup_dir}/database.sqlite"
    echo "${backup_dir}/database.sqlite"
}

# Main execution
main() {
    # Parse command line arguments
    if [[ "$#" -gt 0 ]] && [[ "$1" == "--full-db" ]]; then
        FULL_DB_MODE=true
        log "=========================================="
        log "Starting DEV n8n Full Database Backup"
        log "=========================================="
        
        check_environment
        
        # Create full database backup
        BACKUP_FILE=$(backup_dev_database)
        BACKUP_DIR=$(dirname "${BACKUP_FILE}")
        
        log "=========================================="
        log "Full database backup completed successfully!"
        log "=========================================="
        log ""
        log "Backup location: ${BACKUP_DIR}"
        log "Backup file: ${BACKUP_FILE}"
        log "Log file: ${LOG_FILE}"
        log ""
        log "Next steps:"
        log "  1. Transfer backup file to PROD VPS"
        log "  2. Run import_to_prod.sh --full-db <backup_file> on PROD VPS"
        log ""
        warning "IMPORTANT: Backup file contains all data including credentials"
        warning "Transfer securely and handle with care"
        
        # Output backup path for GitHub Actions
        echo "${BACKUP_FILE}" > /tmp/dev_backup_path.txt
    else
        log "=========================================="
        log "Starting DEV n8n Export Process (Workflows & Credentials)"
        log "=========================================="
        
        check_environment
        prepare_export_directory
        export_workflows
        sanitize_workflows
        export_credentials
        filter_credentials
        generate_checksums
        create_metadata
        validate_export
        
        PACKAGE_PATH=$(create_export_package)
        
        log "=========================================="
        log "Export completed successfully!"
        log "=========================================="
        log ""
        log "Export location: ${EXPORT_DIR}"
        log "Package: ${PACKAGE_PATH}"
        log "Log file: ${LOG_FILE}"
        log ""
        log "Next steps:"
        log "  1. Review exported artifacts in ${EXPORT_DIR}"
        log "  2. Transfer package to PROD VPS"
        log "  3. Run import_to_prod.sh on PROD VPS"
        log ""
        warning "IMPORTANT: Exported credentials are DECRYPTED"
        warning "Handle with extreme care and delete after import"
    fi
}

# Run main function
main "$@"

exit 0

