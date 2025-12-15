#!/bin/bash
##############################################################################
# N8N CLEANUP SCRIPT
#
# Purpose: Clean up old files, logs, and free disk space
# Usage: ./cleanup.sh [--dry-run]
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
N8N_DIR="/srv/n8n"
DRY_RUN=false

# Parse arguments
if [[ $# -gt 0 ]] && [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - No files will be deleted${NC}"
    echo ""
fi

# Logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Calculate size before cleanup
TOTAL_SIZE_BEFORE=$(du -sb "${N8N_DIR}" 2>/dev/null | cut -f1 || echo "0")

log "Starting cleanup process..."
echo ""

# 1. Clean old export packages (older than 7 days)
log "Cleaning old export packages..."
if [[ -d "${N8N_DIR}/migration-temp" ]]; then
    EXPORT_COUNT=$(find "${N8N_DIR}/migration-temp" -name "*.tar.gz" -mtime +7 2>/dev/null | wc -l)
    if [[ ${EXPORT_COUNT} -gt 0 ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            echo "  Would delete ${EXPORT_COUNT} export packages"
            find "${N8N_DIR}/migration-temp" -name "*.tar.gz" -mtime +7 -ls 2>/dev/null
        else
            find "${N8N_DIR}/migration-temp" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null
            echo "  Deleted ${EXPORT_COUNT} old export packages"
        fi
    else
        echo "  No old export packages found"
    fi
else
    echo "  Migration directory not found"
fi
echo ""

# 2. Clean old log files (compress logs older than 7 days)
log "Compressing old log files..."
if [[ -d "${N8N_DIR}/logs" ]]; then
    LOG_COUNT=$(find "${N8N_DIR}/logs" -name "*.log" -mtime +7 ! -name "*.gz" 2>/dev/null | wc -l)
    if [[ ${LOG_COUNT} -gt 0 ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            echo "  Would compress ${LOG_COUNT} log files"
            find "${N8N_DIR}/logs" -name "*.log" -mtime +7 ! -name "*.gz" -ls 2>/dev/null
        else
            find "${N8N_DIR}/logs" -name "*.log" -mtime +7 ! -name "*.gz" -exec gzip {} \; 2>/dev/null
            echo "  Compressed ${LOG_COUNT} log files"
        fi
    else
        echo "  No old log files to compress"
    fi
    
    # Delete very old compressed logs (older than 30 days)
    OLD_LOG_COUNT=$(find "${N8N_DIR}/logs" -name "*.log.gz" -mtime +30 2>/dev/null | wc -l)
    if [[ ${OLD_LOG_COUNT} -gt 0 ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            echo "  Would delete ${OLD_LOG_COUNT} very old log files"
        else
            find "${N8N_DIR}/logs" -name "*.log.gz" -mtime +30 -delete 2>/dev/null
            echo "  Deleted ${OLD_LOG_COUNT} very old log files"
        fi
    fi
else
    echo "  Logs directory not found"
fi
echo ""

# 3. Clean temporary files
log "Cleaning temporary files..."
TEMP_COUNT=0

# Clean migration temp files (keep packages, delete extracted files older than 1 day)
if [[ -d "${N8N_DIR}/migration-temp/export" ]]; then
    EXPORT_TEMP=$(find "${N8N_DIR}/migration-temp/export" -type f -mtime +1 2>/dev/null | wc -l)
    TEMP_COUNT=$((TEMP_COUNT + EXPORT_TEMP))
    if [[ ${EXPORT_TEMP} -gt 0 ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            echo "  Would delete ${EXPORT_TEMP} temporary export files"
        else
            find "${N8N_DIR}/migration-temp/export" -type f -mtime +1 -delete 2>/dev/null
            echo "  Deleted ${EXPORT_TEMP} temporary export files"
        fi
    fi
fi

if [[ -d "${N8N_DIR}/migration-temp/import" ]]; then
    IMPORT_TEMP=$(find "${N8N_DIR}/migration-temp/import" -type f -mtime +1 2>/dev/null | wc -l)
    TEMP_COUNT=$((TEMP_COUNT + IMPORT_TEMP))
    if [[ ${IMPORT_TEMP} -gt 0 ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            echo "  Would delete ${IMPORT_TEMP} temporary import files"
        else
            find "${N8N_DIR}/migration-temp/import" -type f -mtime +1 -delete 2>/dev/null
            echo "  Deleted ${IMPORT_TEMP} temporary import files"
        fi
    fi
fi

if [[ ${TEMP_COUNT} -eq 0 ]]; then
    echo "  No temporary files to clean"
fi
echo ""

# 4. Clean Docker (if not dry run)
if [[ "${DRY_RUN}" == false ]]; then
    log "Cleaning Docker resources..."
    
    # Remove unused images
    IMAGES_REMOVED=$(docker image prune -f 2>&1 | grep "Total reclaimed space" || echo "0B")
    echo "  Images: ${IMAGES_REMOVED}"
    
    # Remove unused volumes (be careful!)
    # VOLUMES_REMOVED=$(docker volume prune -f 2>&1 | grep "Total reclaimed space" || echo "0B")
    # echo "  Volumes: ${VOLUMES_REMOVED}"
    
    # Remove build cache
    CACHE_REMOVED=$(docker builder prune -f 2>&1 | grep "Total" || echo "0B")
    echo "  Cache: ${CACHE_REMOVED}"
else
    echo "Skipping Docker cleanup in dry-run mode"
fi
echo ""

# 5. Check for large files
log "Checking for large files (>100MB)..."
LARGE_FILES=$(find "${N8N_DIR}" -type f -size +100M 2>/dev/null || true)
if [[ -n "${LARGE_FILES}" ]]; then
    warning "Found large files:"
    echo "${LARGE_FILES}" | while read file; do
        SIZE=$(du -h "$file" | cut -f1)
        echo "  ${SIZE} - ${file}"
    done
else
    echo "  No large files found"
fi
echo ""

# 6. Database cleanup (vacuum)
log "Optimizing database..."
if [[ "${DRY_RUN}" == false ]]; then
    # Detect container
    if docker ps | grep -q "n8n-postgres-dev"; then
        DB_CONTAINER="n8n-postgres-dev"
    elif docker ps | grep -q "n8n-postgres-prod"; then
        DB_CONTAINER="n8n-postgres-prod"
    else
        warning "No database container found"
        DB_CONTAINER=""
    fi
    
    if [[ -n "${DB_CONTAINER}" ]]; then
        echo "  Running VACUUM ANALYZE..."
        docker exec "${DB_CONTAINER}" psql -U n8n -d n8n -c "VACUUM ANALYZE;" 2>/dev/null && \
            echo "  ✓ Database optimized" || \
            warning "Database optimization failed"
    fi
else
    echo "  Skipping database optimization in dry-run mode"
fi
echo ""

# Calculate size after cleanup
TOTAL_SIZE_AFTER=$(du -sb "${N8N_DIR}" 2>/dev/null | cut -f1 || echo "0")
SAVED=$((TOTAL_SIZE_BEFORE - TOTAL_SIZE_AFTER))
SAVED_MB=$((SAVED / 1024 / 1024))

# Summary
log "Cleanup Summary:"
echo "  Size before: $(numfmt --to=iec-i --suffix=B ${TOTAL_SIZE_BEFORE} 2>/dev/null || echo "${TOTAL_SIZE_BEFORE} bytes")"
echo "  Size after:  $(numfmt --to=iec-i --suffix=B ${TOTAL_SIZE_AFTER} 2>/dev/null || echo "${TOTAL_SIZE_AFTER} bytes")"
if [[ ${SAVED_MB} -gt 0 ]]; then
    echo "  Space saved: ${SAVED_MB} MB"
else
    echo "  Space saved: Minimal"
fi
echo ""

# Disk space
log "Current disk usage:"
df -h "${N8N_DIR}" | tail -1
echo ""

if [[ "${DRY_RUN}" == true ]]; then
    echo -e "${YELLOW}DRY RUN COMPLETE - No changes were made${NC}"
    echo "Run without --dry-run to perform actual cleanup"
else
    log "Cleanup completed successfully"
fi

