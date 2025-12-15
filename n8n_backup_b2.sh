#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
N8N_DATA_PATH="/var/lib/docker/volumes/n8n_data/_data"
N8N_CONTAINER="root-n8n-1"
RCLONE_REMOTE="b2n8n:supabasedaillybackup/n8n-backups"
RETENTION_COUNT=10
# ----------------

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE=$(date +%F)
TMPDIR=$(mktemp -d)

echo "[$(date +'%F %T')] Starting n8n backup (workflows, data, credentials)..."

# Create backup directory
BACKUP_DIR="${TMPDIR}/n8n_backup_${TIMESTAMP}"
mkdir -p "${BACKUP_DIR}"

# 1. Backup database (contains workflows, credentials, executions)
echo "Backing up n8n database (workflows, credentials, executions)..."
if [ -f "${N8N_DATA_PATH}/database.sqlite" ]; then
    # Stop n8n temporarily to ensure clean backup (optional - can be commented out for zero-downtime)
    # docker stop "${N8N_CONTAINER}" 2>/dev/null || true
    
    # Copy database
    cp "${N8N_DATA_PATH}/database.sqlite" "${BACKUP_DIR}/database.sqlite"
    
    # Restart n8n if we stopped it
    # docker start "${N8N_CONTAINER}" 2>/dev/null || true
    
    echo "  Database backed up: $(du -h ${BACKUP_DIR}/database.sqlite | cut -f1)"
else
    echo "  Warning: database.sqlite not found at ${N8N_DATA_PATH}/database.sqlite"
fi

# 2. Backup binary data
echo "Backing up binary data..."
if [ -d "${N8N_DATA_PATH}/binaryData" ]; then
    cp -r "${N8N_DATA_PATH}/binaryData" "${BACKUP_DIR}/binaryData" 2>/dev/null || true
    echo "  Binary data backed up"
fi

# 3. Backup configuration
echo "Backing up configuration..."
if [ -f "${N8N_DATA_PATH}/config" ]; then
    cp "${N8N_DATA_PATH}/config" "${BACKUP_DIR}/config" 2>/dev/null || true
    echo "  Configuration backed up"
fi

# 4. Backup custom nodes
echo "Backing up custom nodes..."
if [ -d "${N8N_DATA_PATH}/nodes" ]; then
    cp -r "${N8N_DATA_PATH}/nodes" "${BACKUP_DIR}/nodes" 2>/dev/null || true
    echo "  Custom nodes backed up"
fi

# 5. Backup SSH keys
echo "Backing up SSH keys..."
if [ -d "${N8N_DATA_PATH}/ssh" ]; then
    cp -r "${N8N_DATA_PATH}/ssh" "${BACKUP_DIR}/ssh" 2>/dev/null || true
    echo "  SSH keys backed up"
fi

# 6. Backup git repository if exists
if [ -d "${N8N_DATA_PATH}/git" ]; then
    cp -r "${N8N_DATA_PATH}/git" "${BACKUP_DIR}/git" 2>/dev/null || true
    echo "  Git repository backed up"
fi

# 7. Export workflows and credentials via n8n API (if accessible)
echo "Attempting to export workflows via API..."
API_URL="https://n8n.sesai.in/api/v1"
# This would require API credentials - adding as optional
# curl -s "${API_URL}/workflows" -H "X-N8N-API-KEY: YOUR_KEY" > "${BACKUP_DIR}/workflows_export.json" 2>/dev/null || true

# Create backup info file
cat > "${BACKUP_DIR}/backup_info.txt" << EOF
n8n Backup Information
======================
Backup Date: $(date +'%F %T')
Backup Timestamp: ${TIMESTAMP}
n8n Container: ${N8N_CONTAINER}
n8n Data Path: ${N8N_DATA_PATH}

Contents:
- database.sqlite: Contains all workflows, credentials, executions, and settings
- binaryData/: Binary files used by workflows
- config: n8n configuration
- nodes/: Custom nodes
- ssh/: SSH keys for connections
- git/: Git repository (if used)

To restore:
1. Stop n8n: docker stop ${N8N_CONTAINER}
2. Restore files to: ${N8N_DATA_PATH}/
3. Set correct permissions: chown -R 1000:1000 ${N8N_DATA_PATH}/
4. Start n8n: docker start ${N8N_CONTAINER}
EOF

# Compress the backup
echo "Compressing backup..."
cd "${TMPDIR}"
tar -czf "n8n_backup_${TIMESTAMP}.tar.gz" "n8n_backup_${TIMESTAMP}/"
BACKUP_SIZE=$(du -h "n8n_backup_${TIMESTAMP}.tar.gz" | cut -f1)
echo "  Backup size: ${BACKUP_SIZE}"
rm -rf "n8n_backup_${TIMESTAMP}/"

# Upload to Backblaze
echo "Uploading to Backblaze..."
rclone copy "${TMPDIR}/n8n_backup_${TIMESTAMP}.tar.gz" "${RCLONE_REMOTE}/" --create-empty-src-dirs --progress

# Verify upload
echo "Verifying upload..."
rclone ls "${RCLONE_REMOTE}/" | grep "n8n_backup_${TIMESTAMP}"

# Cleanup old backups (keep only last 10)
echo "Cleaning up old backups (keeping only last ${RETENTION_COUNT})..."
# List all backups, sort by name (which includes timestamp), keep only last RETENTION_COUNT
BACKUP_LIST=$(rclone lsf "${RCLONE_REMOTE}/" | grep "n8n_backup_" | sort -r | tail -n +$((RETENTION_COUNT + 1)))

if [ -n "${BACKUP_LIST}" ]; then
    echo "${BACKUP_LIST}" | while read -r old_backup; do
        if [ -n "${old_backup}" ]; then
            echo "  Deleting old backup: ${old_backup}"
            rclone delete "${RCLONE_REMOTE}/${old_backup}" 2>/dev/null || true
        fi
    done
else
    echo "  No old backups to delete"
fi

# Show current backups
echo ""
echo "Current backups (last ${RETENTION_COUNT}):"
rclone lsf "${RCLONE_REMOTE}/" | grep "n8n_backup_" | sort -r | head -${RETENTION_COUNT}

# Cleanup temp files
rm -rf "${TMPDIR}"

echo ""
echo "[$(date +'%F %T')] n8n backup completed successfully."
echo "  Backup file: n8n_backup_${TIMESTAMP}.tar.gz"
echo "  Size: ${BACKUP_SIZE}"
echo "  Location: ${RCLONE_REMOTE}/"

