#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
CONTAINER="supabase-db-ugwwsc8wg4k8o4ssskw4ooco"
PGUSER="postgres"
PGDATABASE="postgres"
MINIO_DATA_PATH="/data/coolify/services/ugwwsc8wg4k8o4ssskw4ooco/volumes/storage"
# ----------------

echo "Supabase Storage Restore Script"
echo "================================"
echo ""

if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup_directory>"
    echo ""
    echo "Example: $0 /path/to/2025-12-06"
    echo ""
    echo "The backup directory should contain:"
    echo "  - Bucket folders with files"
    echo "  - _file_manifest.txt files (optional)"
    echo "  - _minio_raw_backup/ folder (for complete restore)"
    exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "${BACKUP_DIR}" ]; then
    echo "Error: Backup directory not found: ${BACKUP_DIR}"
    exit 1
fi

echo "Backup directory: ${BACKUP_DIR}"
echo ""

# Check if this is a raw MinIO backup
if [ -d "${BACKUP_DIR}/_minio_raw_backup" ]; then
    echo "Found raw MinIO backup. Restoring complete MinIO structure..."
    echo "WARNING: This will replace the entire MinIO storage!"
    read -p "Are you sure? (yes/no): " confirm
    if [ "${confirm}" != "yes" ]; then
        echo "Restore cancelled."
        exit 0
    fi
    
    # Stop MinIO if needed (optional, might not be necessary)
    echo "Restoring MinIO structure..."
    cp -r "${BACKUP_DIR}/_minio_raw_backup"/* "${MINIO_DATA_PATH}/.minio.sys/" 2>/dev/null || {
        echo "Error: Could not restore MinIO structure"
        exit 1
    }
    
    echo "MinIO structure restored. You may need to restart the MinIO container."
    echo "Restore completed!"
    exit 0
fi

# Restore files by bucket
echo "Restoring files by bucket..."
for bucket_dir in "${BACKUP_DIR}"/*; do
    if [ -d "${bucket_dir}" ] && [ "$(basename "${bucket_dir}")" != "_minio_raw_backup" ]; then
        bucket_name=$(basename "${bucket_dir}")
        echo ""
        echo "Processing bucket: ${bucket_name}"
        
        # Check if bucket exists in Supabase
        bucket_exists=$(docker exec "${CONTAINER}" psql -U "${PGUSER}" -d "${PGDATABASE}" -t -A -c "SELECT COUNT(*) FROM storage.buckets WHERE name='${bucket_name}';" 2>/dev/null || echo "0")
        
        if [ "${bucket_exists}" = "0" ]; then
            echo "  Warning: Bucket '${bucket_name}' does not exist in Supabase."
            echo "  You may need to create it first or files will be restored to MinIO only."
        fi
        
        # Restore files
        file_count=0
        find "${bucket_dir}" -type f ! -name "_file_manifest.txt" ! -name "*.meta" ! -name "README*" | while read -r file_path; do
            relative_path=$(echo "${file_path}" | sed "s|${bucket_dir}/||")
            echo "  Restoring: ${relative_path}"
            
            # For now, copy to a restore location
            # In production, you would use Supabase Storage API or MinIO client
            restore_path="${MINIO_DATA_PATH}/restore/${bucket_name}/${relative_path}"
            mkdir -p "$(dirname "${restore_path}")"
            cp "${file_path}" "${restore_path}" 2>/dev/null || true
            ((file_count++))
        done
        
        echo "  Restored files from bucket: ${bucket_name}"
    fi
done

echo ""
echo "=========================================="
echo "Restore completed!"
echo ""
echo "NOTE: Files have been copied to: ${MINIO_DATA_PATH}/restore/"
echo "To complete the restore, you may need to:"
echo "1. Use Supabase Storage API to upload files"
echo "2. Or use MinIO client (mc) to sync files"
echo "3. Or manually move files to the correct MinIO structure"
echo ""
echo "For Supabase Storage API upload, you can use:"
echo "  supabase storage upload <bucket> <file-path> <storage-path>"
echo "=========================================="

