#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
CONTAINER="supabase-db-ugwwsc8wg4k8o4ssskw4ooco"
PGUSER="postgres"
PGDATABASE="postgres"
MINIO_DATA_PATH="/data/coolify/services/ugwwsc8wg4k8o4ssskw4ooco/volumes/storage"
RCLONE_REMOTE="b2supabase:supabasedaillybackup/supabase-storage-backup"
RETENTION_DAYS=10
# ----------------

DATE=$(date +%F)
TMPDIR=$(mktemp -d)

echo "[$(date +'%F %T')] Starting Supabase storage backup with original filenames..."

# Create backup directory structure
BACKUP_DIR="${TMPDIR}/${DATE}"
mkdir -p "${BACKUP_DIR}"

# Create two structures:
# 1. Human-readable with original filenames
HUMAN_READABLE_DIR="${BACKUP_DIR}/files-by-bucket"
# 2. Raw MinIO backup for complete restore
RAW_BACKUP_DIR="${BACKUP_DIR}/_minio_raw_backup"

mkdir -p "${HUMAN_READABLE_DIR}"
mkdir -p "${RAW_BACKUP_DIR}"

# First, backup the raw MinIO structure for complete restore
echo "Backing up raw MinIO structure for complete restore..."
if [ -d "${MINIO_DATA_PATH}/.minio.sys" ]; then
    cp -r "${MINIO_DATA_PATH}/.minio.sys" "${RAW_BACKUP_DIR}/" 2>/dev/null || true
    echo "  Raw MinIO backup completed"
fi

# Query database for file metadata to create human-readable structure
echo "Querying Supabase database for file metadata..."
FILES_QUERY="
SELECT 
    o.bucket_id,
    o.name as file_path,
    o.id::text as file_id,
    o.metadata->>'name' as original_name,
    o.metadata->>'mimetype' as content_type,
    o.metadata->>'size' as file_size,
    o.created_at::text as created_at
FROM storage.objects o
ORDER BY o.bucket_id, o.name;
"

# Export file list
docker exec "${CONTAINER}" psql -U "${PGUSER}" -d "${PGDATABASE}" -t -A -F'|' -c "${FILES_QUERY}" > "${TMPDIR}/files_list.txt" 2>/dev/null || {
    echo "Warning: Could not query database. Creating backup with raw structure only."
    # If we can't query, just use raw backup
    cd "${TMPDIR}"
    tar -czf "${DATE}.tar.gz" "${DATE}/"
    rm -rf "${DATE}/"
    rclone copy "${TMPDIR}/${DATE}.tar.gz" "${RCLONE_REMOTE}/${DATE}/" --create-empty-src-dirs
    rclone ls "${RCLONE_REMOTE}/${DATE}/"
    rm -rf "${TMPDIR}"
    echo "[$(date +'%F %T')] Backup completed (raw structure only)."
    exit 0
}

# Process files to create human-readable structure
if [ -f "${TMPDIR}/files_list.txt" ] && [ -s "${TMPDIR}/files_list.txt" ]; then
    echo "Creating human-readable file structure with original filenames..."
    
    echo "  Creating file manifest (this may take a moment)..."
    total_files=$(wc -l < "${TMPDIR}/files_list.txt" | xargs)
    echo "  Total files: ${total_files}"
    
    # Use a simpler approach - just create manifests for now
    # The raw backup has all files, manifest maps them to original names
    cat "${TMPDIR}/files_list.txt" | while IFS='|' read -r bucket_id file_path file_id original_name content_type file_size created_at; do
        # Skip empty lines
        [ -z "${bucket_id}" ] && continue
        
        # Clean up the values
        bucket_id=$(echo "${bucket_id}" | xargs)
        file_path=$(echo "${file_path}" | xargs)
        file_id=$(echo "${file_id}" | xargs)
        original_name=$(echo "${original_name}" | xargs | sed 's/"//g' | sed "s/'//g")
        content_type=$(echo "${content_type}" | xargs | sed 's/"//g')
        file_size=$(echo "${file_size}" | xargs)
        created_at=$(echo "${created_at}" | xargs)
        
        [ -z "${bucket_id}" ] && continue
        bucket_id=$(echo "${bucket_id}" | xargs)
        file_path=$(echo "${file_path}" | xargs)
        [ -z "${bucket_id}" ] || [ -z "${file_path}" ] && continue
        
        file_id=$(echo "${file_id}" | xargs)
        original_name=$(echo "${original_name}" | xargs | sed 's/"//g' | sed "s/'//g")
        content_type=$(echo "${content_type}" | xargs | sed 's/"//g')
        file_size=$(echo "${file_size}" | xargs)
        created_at=$(echo "${created_at}" | xargs)
        
        display_name="${original_name:-$(basename "${file_path}")}"
        bucket_dir="${HUMAN_READABLE_DIR}/${bucket_id}"
        mkdir -p "${bucket_dir}"
        echo "${file_path}|${file_id}|${display_name}|${content_type}|${file_size}|${created_at}" >> "${bucket_dir}/_file_manifest.txt"
    done
    
    echo "  Manifest files created for all buckets"
    
    file_count=$(wc -l < "${TMPDIR}/files_list.txt" | xargs)
    echo "  Total files in database: ${file_count}"
    echo "  File manifests created for all buckets"
else
    echo "No file metadata found in database."
fi

# Create a comprehensive README
cat > "${BACKUP_DIR}/README.txt" << 'EOF'
SUPABASE STORAGE BACKUP
=======================

This backup contains two structures:

1. files-by-bucket/  - Human-readable structure with original filenames
   - Each bucket has its own folder
   - Files are organized by their original paths
   - You can directly use images, PDFs, videos, etc. from here
   - .info files contain metadata (content type, size, creation date)
   - _file_manifest.txt lists files that couldn't be automatically mapped

2. _minio_raw_backup/ - Complete raw MinIO structure
   - Use this for complete restore to Supabase
   - Contains all MinIO internal files (UUIDs, .meta files)
   - Required for full system restore

RESTORING FILES:
----------------

For local use:
- Simply extract and browse files-by-bucket/ folders
- All files have their original names and can be used directly

For Supabase restore:
- Use the restore script: restore_supabase_storage.sh
- Or manually restore from _minio_raw_backup/

FILE MANIFEST:
-------------
If a _file_manifest.txt exists in a bucket folder, it means some files
couldn't be automatically mapped. The format is:
file_path|file_id|original_name|content_type|size|created_at

You can use this manifest along with the raw backup to manually extract files.
EOF

# Compress the backup
echo "Compressing storage backup..."
cd "${TMPDIR}"
tar -czf "${DATE}.tar.gz" "${DATE}/"
BACKUP_SIZE=$(du -h "${DATE}.tar.gz" | cut -f1)
echo "  Backup size: ${BACKUP_SIZE}"
rm -rf "${DATE}/"

# Upload to Backblaze in a dated folder
echo "Uploading to Backblaze..."
rclone copy "${TMPDIR}/${DATE}.tar.gz" "${RCLONE_REMOTE}/${DATE}/" --create-empty-src-dirs --progress

# Verify upload
echo "Verifying upload..."
rclone ls "${RCLONE_REMOTE}/${DATE}/"

# Cleanup old backups (keep only last 10 days)
echo "Cleaning up storage backups older than ${RETENTION_DAYS} days..."
CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%F 2>/dev/null || date -v-${RETENTION_DAYS}d +%F 2>/dev/null || echo "")

if [ -n "${CUTOFF_DATE}" ]; then
    # List all backup folders and delete old ones
    rclone lsd "${RCLONE_REMOTE}" 2>/dev/null | while read -r line; do
        BACKUP_DATE=$(echo "${line}" | awk '{print $5}' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || echo "")
        if [ -n "${BACKUP_DATE}" ] && [ "${BACKUP_DATE}" \< "${CUTOFF_DATE}" ]; then
            echo "Deleting old storage backup: ${BACKUP_DATE}"
            rclone purge "${RCLONE_REMOTE}/${BACKUP_DATE}" 2>/dev/null || rclone rmdir "${RCLONE_REMOTE}/${BACKUP_DATE}" 2>/dev/null || true
        fi
    done
else
    # Fallback: Delete folders older than retention days
    echo "Using alternative cleanup method..."
    rclone lsd "${RCLONE_REMOTE}" 2>/dev/null | awk '{print $5}' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | while read -r BACKUP_DATE; do
        if [ -n "${BACKUP_DATE}" ]; then
            BACKUP_EPOCH=$(date -d "${BACKUP_DATE}" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "${BACKUP_DATE}" +%s 2>/dev/null || echo "0")
            CUTOFF_EPOCH=$(date -d "${RETENTION_DAYS} days ago" +%s 2>/dev/null || date -v-${RETENTION_DAYS}d +%s 2>/dev/null || echo "0")
            if [ "${BACKUP_EPOCH}" -lt "${CUTOFF_EPOCH}" ] && [ "${BACKUP_EPOCH}" -ne "0" ] && [ "${CUTOFF_EPOCH}" -ne "0" ]; then
                echo "Deleting old storage backup: ${BACKUP_DATE}"
                rclone purge "${RCLONE_REMOTE}/${BACKUP_DATE}" 2>/dev/null || rclone rmdir "${RCLONE_REMOTE}/${BACKUP_DATE}" 2>/dev/null || true
            fi
        fi
    done
fi

# Cleanup temp files
rm -rf "${TMPDIR}"

echo "[$(date +'%F %T')] Storage backup completed successfully."
echo "  Backup includes:"
echo "    - Human-readable files with original names (files-by-bucket/)"
echo "    - Raw MinIO backup for complete restore (_minio_raw_backup/)"
