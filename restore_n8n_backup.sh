#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
N8N_DATA_PATH="/var/lib/docker/volumes/n8n_data/_data"
N8N_CONTAINER="root-n8n-1"
RCLONE_REMOTE="b2n8n:supabasedaillybackup/n8n-backups"
# ----------------

echo "n8n Backup Restore Script"
echo "========================="
echo ""

if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup_filename>"
    echo ""
    echo "Available backups:"
    rclone lsf "${RCLONE_REMOTE}/" | grep "n8n_backup_" | sort -r
    echo ""
    echo "Example: $0 n8n_backup_20251206_103157.tar.gz"
    exit 1
fi

BACKUP_FILE="$1"

echo "Restoring from backup: ${BACKUP_FILE}"
echo ""
echo "WARNING: This will replace all current n8n data!"
echo "Current n8n data will be backed up to: ${N8N_DATA_PATH}/.backup_before_restore/"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "${confirm}" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Stop n8n
echo "Stopping n8n container..."
docker stop "${N8N_CONTAINER}" || {
    echo "Error: Could not stop n8n container"
    exit 1
}

# Backup current data before restore
echo "Backing up current data..."
BACKUP_BEFORE_RESTORE="${N8N_DATA_PATH}/.backup_before_restore_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${BACKUP_BEFORE_RESTORE}"
cp -r "${N8N_DATA_PATH}"/* "${BACKUP_BEFORE_RESTORE}/" 2>/dev/null || true
echo "  Current data backed up to: ${BACKUP_BEFORE_RESTORE}"

# Download backup
echo "Downloading backup from Backblaze..."
TMPDIR=$(mktemp -d)
rclone copy "${RCLONE_REMOTE}/${BACKUP_FILE}" "${TMPDIR}/" --progress

if [ ! -f "${TMPDIR}/${BACKUP_FILE}" ]; then
    echo "Error: Backup file not found: ${BACKUP_FILE}"
    docker start "${N8N_CONTAINER}" 2>/dev/null || true
    exit 1
fi

# Extract backup
echo "Extracting backup..."
cd "${TMPDIR}"
tar -xzf "${BACKUP_FILE}" || {
    echo "Error: Failed to extract backup"
    docker start "${N8N_CONTAINER}" 2>/dev/null || true
    exit 1
}

EXTRACTED_DIR=$(find . -type d -name "n8n_backup_*" | head -1)
if [ -z "${EXTRACTED_DIR}" ]; then
    echo "Error: Could not find extracted backup directory"
    docker start "${N8N_CONTAINER}" 2>/dev/null || true
    exit 1
fi

# Restore files
echo "Restoring files to n8n data directory..."
if [ -f "${EXTRACTED_DIR}/database.sqlite" ]; then
    cp "${EXTRACTED_DIR}/database.sqlite" "${N8N_DATA_PATH}/database.sqlite"
    echo "  Database restored"
fi

if [ -d "${EXTRACTED_DIR}/binaryData" ]; then
    rm -rf "${N8N_DATA_PATH}/binaryData"
    cp -r "${EXTRACTED_DIR}/binaryData" "${N8N_DATA_PATH}/binaryData"
    echo "  Binary data restored"
fi

if [ -f "${EXTRACTED_DIR}/config" ]; then
    cp "${EXTRACTED_DIR}/config" "${N8N_DATA_PATH}/config"
    echo "  Configuration restored"
fi

if [ -d "${EXTRACTED_DIR}/nodes" ]; then
    rm -rf "${N8N_DATA_PATH}/nodes"
    cp -r "${EXTRACTED_DIR}/nodes" "${N8N_DATA_PATH}/nodes"
    echo "  Custom nodes restored"
fi

if [ -d "${EXTRACTED_DIR}/ssh" ]; then
    rm -rf "${N8N_DATA_PATH}/ssh"
    cp -r "${EXTRACTED_DIR}/ssh" "${N8N_DATA_PATH}/ssh"
    echo "  SSH keys restored"
fi

if [ -d "${EXTRACTED_DIR}/git" ]; then
    rm -rf "${N8N_DATA_PATH}/git"
    cp -r "${EXTRACTED_DIR}/git" "${N8N_DATA_PATH}/git"
    echo "  Git repository restored"
fi

# Set correct permissions
echo "Setting file permissions..."
chown -R 1000:1000 "${N8N_DATA_PATH}" 2>/dev/null || chown -R ubuntu:ubuntu "${N8N_DATA_PATH}" 2>/dev/null || true

# Cleanup
rm -rf "${TMPDIR}"

# Start n8n
echo "Starting n8n container..."
docker start "${N8N_CONTAINER}" || {
    echo "Error: Could not start n8n container"
    echo "Please check the container status: docker ps -a | grep n8n"
    exit 1
}

echo ""
echo "=========================================="
echo "Restore completed successfully!"
echo ""
echo "n8n has been restored from: ${BACKUP_FILE}"
echo "Previous data backed up to: ${BACKUP_BEFORE_RESTORE}"
echo ""
echo "Please verify n8n is running: docker ps | grep n8n"
echo "Access n8n at: https://n8n.sesai.in"
echo "=========================================="

