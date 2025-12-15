#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
CONTAINER="supabase-db-ugwwsc8wg4k8o4ssskw4ooco"
PGUSER="postgres"
PGDATABASE="postgres"
RCLONE_REMOTE="b2supabase:supabasedaillybackup/supabase-daily-backup"
RETENTION_DAYS=10
# ----------------

DATE=$(date +%F)
TMPDIR=$(mktemp -d)

echo "[$(date +'%F %T')] Starting Supabase backup (direct to Backblaze)..."

# 1) Schema
echo "Dumping schema..."
docker exec "${CONTAINER}" pg_dump -U "${PGUSER}" -d "${PGDATABASE}" --schema-only > "${TMPDIR}/schema.sql"

# 2) Data
echo "Dumping data..."
docker exec "${CONTAINER}" pg_dump -U "${PGUSER}" -d "${PGDATABASE}" --data-only --inserts > "${TMPDIR}/data.sql"

# 3) Roles/globals
echo "Dumping roles..."
docker exec "${CONTAINER}" pg_dumpall -U "${PGUSER}" --globals-only > "${TMPDIR}/roles.sql"

# Compress before upload
echo "Compressing files..."
gzip "${TMPDIR}"/*.sql

# Upload to Backblaze in a dated folder
echo "Uploading to Backblaze..."
rclone copy "${TMPDIR}" "${RCLONE_REMOTE}/${DATE}" --create-empty-src-dirs

# Verify upload
echo "Verifying upload..."
rclone ls "${RCLONE_REMOTE}/${DATE}"

# Cleanup old backups (keep only last 10 days)
echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%F 2>/dev/null || date -v-${RETENTION_DAYS}d +%F 2>/dev/null || echo "")

if [ -n "${CUTOFF_DATE}" ]; then
    # List all backup folders and delete old ones
    rclone lsd "${RCLONE_REMOTE}" 2>/dev/null | while read -r line; do
        BACKUP_DATE=$(echo "${line}" | awk '{print $5}' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || echo "")
        if [ -n "${BACKUP_DATE}" ] && [ "${BACKUP_DATE}" \< "${CUTOFF_DATE}" ]; then
            echo "Deleting old backup: ${BACKUP_DATE}"
            rclone purge "${RCLONE_REMOTE}/${BACKUP_DATE}" 2>/dev/null || rclone rmdir "${RCLONE_REMOTE}/${BACKUP_DATE}" 2>/dev/null || true
        fi
    done
else
    # Fallback: Delete folders older than retention days using find-like approach
    echo "Using alternative cleanup method..."
    # Get list of all backup dates and manually calculate
    rclone lsd "${RCLONE_REMOTE}" 2>/dev/null | awk '{print $5}' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | while read -r BACKUP_DATE; do
        if [ -n "${BACKUP_DATE}" ]; then
            # Calculate days difference (simplified - assumes date format YYYY-MM-DD)
            BACKUP_EPOCH=$(date -d "${BACKUP_DATE}" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "${BACKUP_DATE}" +%s 2>/dev/null || echo "0")
            CUTOFF_EPOCH=$(date -d "${RETENTION_DAYS} days ago" +%s 2>/dev/null || date -v-${RETENTION_DAYS}d +%s 2>/dev/null || echo "0")
            if [ "${BACKUP_EPOCH}" -lt "${CUTOFF_EPOCH}" ] && [ "${BACKUP_EPOCH}" -ne "0" ] && [ "${CUTOFF_EPOCH}" -ne "0" ]; then
                echo "Deleting old backup: ${BACKUP_DATE}"
                rclone purge "${RCLONE_REMOTE}/${BACKUP_DATE}" 2>/dev/null || rclone rmdir "${RCLONE_REMOTE}/${BACKUP_DATE}" 2>/dev/null || true
            fi
        fi
    done
fi

# Cleanup temp files
rm -rf "${TMPDIR}"

echo "[$(date +'%F %T')] Backup completed successfully."

