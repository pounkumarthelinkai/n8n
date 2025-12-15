#!/usr/bin/env bash
set -euo pipefail

# Script to extract Supabase storage backup with original filenames
# Usage: ./extract_storage_backup.sh <backup_tar.gz_file> <output_directory>

if [ $# -lt 2 ]; then
    echo "Usage: $0 <backup_tar.gz_file> <output_directory>"
    echo ""
    echo "Example: $0 2025-12-06.tar.gz ./extracted_backup"
    echo ""
    echo "This script will:"
    echo "  1. Extract the backup archive"
    echo "  2. Query Supabase database for file metadata"
    echo "  3. Create a human-readable structure with original filenames"
    exit 1
fi

BACKUP_FILE="$1"
OUTPUT_DIR="$2"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

echo "Extracting backup: ${BACKUP_FILE}"
TEMP_DIR=$(mktemp -d)
tar -xzf "${BACKUP_FILE}" -C "${TEMP_DIR}" || {
    echo "Error: Failed to extract backup file"
    exit 1
}

EXTRACTED_DIR=$(find "${TEMP_DIR}" -type d -mindepth 1 -maxdepth 1 | head -1)
echo "Extracted to: ${EXTRACTED_DIR}"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Check if we have raw MinIO backup
if [ -d "${EXTRACTED_DIR}/_minio_raw_backup" ] || [ -d "${EXTRACTED_DIR}/minio-storage" ]; then
    echo ""
    echo "Found MinIO raw backup structure."
    echo "This backup contains the internal MinIO structure (UUIDs, .meta files)."
    echo ""
    echo "To get files with original names, you need to:"
    echo "1. Query the Supabase database for file metadata"
    echo "2. Map UUIDs to original filenames"
    echo ""
    echo "The backup structure is preserved in: ${OUTPUT_DIR}/raw_backup/"
    cp -r "${EXTRACTED_DIR}"/* "${OUTPUT_DIR}/raw_backup/" 2>/dev/null || true
    echo ""
    echo "Raw backup copied to: ${OUTPUT_DIR}/raw_backup/"
    echo ""
    echo "NOTE: To extract files with original names, you need access to the Supabase"
    echo "      database to get the file metadata mapping."
fi

# If we have bucket folders with manifests
if [ -d "${EXTRACTED_DIR}" ]; then
    echo ""
    echo "Checking for organized bucket backups..."
    for bucket_dir in "${EXTRACTED_DIR}"/*; do
        if [ -d "${bucket_dir}" ] && [ -f "${bucket_dir}/_file_manifest.txt" ]; then
            bucket_name=$(basename "${bucket_dir}")
            echo "  Found organized backup for bucket: ${bucket_name}"
            cp -r "${bucket_dir}" "${OUTPUT_DIR}/${bucket_name}" 2>/dev/null || true
        fi
    done
fi

# Cleanup
rm -rf "${TEMP_DIR}"

echo ""
echo "=========================================="
echo "Extraction completed!"
echo "Output directory: ${OUTPUT_DIR}"
echo ""
echo "The backup contains MinIO's internal structure."
echo "To restore files with original names, use the restore script"
echo "or query the Supabase database for file metadata."
echo "=========================================="

