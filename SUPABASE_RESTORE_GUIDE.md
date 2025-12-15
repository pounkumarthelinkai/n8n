# Supabase Backup Restore Guide

## Overview
This guide explains how to restore Supabase database and storage backups from Backblaze B2.

## Backup Location
- **Backblaze Bucket**: `supabasedaillybackup`
- **Database Backups**: `supabase-daily-backup/YYYY-MM-DD/`
- **Storage Backups**: `supabase-storage-backup/YYYY-MM-DD/`

## Prerequisites
- Access to the VPS server (root@31.97.63.184)
- SSH key: `C:\Users\admin\.ssh\github_deploy_key`
- rclone configured with Backblaze credentials
- Docker access to Supabase containers

---

## Part 1: Restoring Database Backup

### Step 1: List Available Backups

```bash
# Connect to VPS
ssh -i C:\Users\admin\.ssh\github_deploy_key root@31.97.63.184

# List available database backups
rclone lsd b2supabase:supabasedaillybackup/supabase-daily-backup/
```

### Step 2: Download the Backup

```bash
# Download a specific backup (replace YYYY-MM-DD with actual date)
BACKUP_DATE="2025-12-06"
rclone copy b2supabase:supabasedaillybackup/supabase-daily-backup/${BACKUP_DATE}/ /tmp/supabase_restore/ --progress
```

### Step 3: Extract Backup Files

```bash
cd /tmp/supabase_restore/${BACKUP_DATE}
ls -lh
# You should see: schema.sql.gz, data.sql.gz, roles.sql.gz
```

### Step 4: Stop Supabase (Optional - for clean restore)

```bash
# Check container name
docker ps | grep supabase-db

# Stop the database container (this will stop all Supabase services)
# Only do this if you need a complete restore
docker stop supabase-db-ugwwsc8wg4k8o4ssskw4ooco
```

### Step 5: Restore Database

```bash
# Set variables
CONTAINER="supabase-db-ugwwsc8wg4k8o4ssskw4ooco"
PGUSER="postgres"
PGDATABASE="postgres"
BACKUP_DIR="/tmp/supabase_restore/${BACKUP_DATE}"

# 1. Restore roles/globals first
echo "Restoring roles..."
gunzip -c ${BACKUP_DIR}/roles.sql.gz | docker exec -i ${CONTAINER} psql -U ${PGUSER} -d postgres

# 2. Restore schema
echo "Restoring schema..."
gunzip -c ${BACKUP_DIR}/schema.sql.gz | docker exec -i ${CONTAINER} psql -U ${PGUSER} -d ${PGDATABASE}

# 3. Restore data (this may take time for large databases)
echo "Restoring data..."
gunzip -c ${BACKUP_DIR}/data.sql.gz | docker exec -i ${CONTAINER} psql -U ${PGUSER} -d ${PGDATABASE}
```

### Step 6: Verify Restore

```bash
# Check if tables exist
docker exec ${CONTAINER} psql -U ${PGUSER} -d ${PGDATABASE} -c "\dt"

# Check row counts
docker exec ${CONTAINER} psql -U ${PGUSER} -d ${PGDATABASE} -c "SELECT schemaname, tablename, n_tup_ins FROM pg_stat_user_tables LIMIT 10;"
```

### Step 7: Restart Supabase (if stopped)

```bash
docker start supabase-db-ugwwsc8wg4k8o4ssskw4ooco
```

---

## Part 2: Restoring Storage Backup

### Step 1: List Available Storage Backups

```bash
rclone lsd b2supabase:supabasedaillybackup/supabase-storage-backup/
```

### Step 2: Download Storage Backup

```bash
BACKUP_DATE="2025-12-06"
rclone copy b2supabase:supabasedaillybackup/supabase-storage-backup/${BACKUP_DATE}/ /tmp/storage_restore/ --progress
```

### Step 3: Extract Storage Backup

```bash
cd /tmp/storage_restore/${BACKUP_DATE}
tar -xzf *.tar.gz
ls -la
```

### Step 4: Restore Storage Files

You have two options:

#### Option A: Restore from Raw MinIO Backup (Complete Restore)

```bash
# This restores the entire MinIO structure
MINIO_DATA_PATH="/data/coolify/services/ugwwsc8wg4k8o4ssskw4ooco/volumes/storage"

# Stop MinIO container
docker stop supabase-minio-ugwwsc8wg4k8o4ssskw4ooco

# Backup current data (safety)
cp -r ${MINIO_DATA_PATH}/.minio.sys ${MINIO_DATA_PATH}/.minio.sys.backup_$(date +%Y%m%d_%H%M%S)

# Restore from backup
cp -r /tmp/storage_restore/${BACKUP_DATE}/_minio_raw_backup/.minio.sys/* ${MINIO_DATA_PATH}/.minio.sys/

# Set permissions
chown -R 1000:1000 ${MINIO_DATA_PATH} 2>/dev/null || true

# Start MinIO container
docker start supabase-minio-ugwwsc8wg4k8o4ssskw4ooco
```

#### Option B: Restore Individual Files (Selective Restore)

```bash
# Use the restore script
/usr/local/bin/restore_supabase_storage.sh /tmp/storage_restore/${BACKUP_DATE}
```

Or manually restore files using the manifest:

```bash
# The backup contains:
# - files-by-bucket/: Files with original names
# - _file_manifest.txt: Mapping of UUIDs to original names
# - _minio_raw_backup/: Complete MinIO structure

# For selective restore, use Supabase Storage API or copy files manually
```

### Step 5: Verify Storage Restore

```bash
# Check if buckets are accessible
docker exec supabase-minio-ugwwsc8wg4k8o4ssskw4ooco mc ls /data 2>/dev/null || echo "Check MinIO status"

# Or query database for storage objects
docker exec supabase-db-ugwwsc8wg4k8o4ssskw4ooco psql -U postgres -d postgres -c "SELECT COUNT(*) FROM storage.objects;"
```

---

## Part 3: Complete Disaster Recovery

### Full System Restore (Database + Storage)

```bash
#!/bin/bash
# Complete restore script

BACKUP_DATE="2025-12-06"
CONTAINER="supabase-db-ugwwsc8wg4k8o4ssskw4ooco"
PGUSER="postgres"
PGDATABASE="postgres"
MINIO_DATA_PATH="/data/coolify/services/ugwwsc8wg4k8o4ssskw4ooco/volumes/storage"

echo "Starting complete Supabase restore..."

# 1. Download backups
echo "Downloading backups..."
mkdir -p /tmp/supabase_full_restore
rclone copy b2supabase:supabasedaillybackup/supabase-daily-backup/${BACKUP_DATE}/ /tmp/supabase_full_restore/db/ --progress
rclone copy b2supabase:supabasedaillybackup/supabase-storage-backup/${BACKUP_DATE}/ /tmp/supabase_full_restore/storage/ --progress

# 2. Stop Supabase services
echo "Stopping Supabase services..."
docker stop supabase-db-ugwwsc8wg4k8o4ssskw4ooco
docker stop supabase-minio-ugwwsc8wg4k8o4ssskw4ooco

# 3. Backup current data (safety)
echo "Creating safety backup..."
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p /backup/safety_backup_${BACKUP_TIMESTAMP}
cp -r ${MINIO_DATA_PATH} /backup/safety_backup_${BACKUP_TIMESTAMP}/storage 2>/dev/null || true

# 4. Restore database
echo "Restoring database..."
gunzip -c /tmp/supabase_full_restore/db/roles.sql.gz | docker exec -i ${CONTAINER} psql -U ${PGUSER} -d postgres
gunzip -c /tmp/supabase_full_restore/db/schema.sql.gz | docker exec -i ${CONTAINER} psql -U ${PGUSER} -d ${PGDATABASE}
gunzip -c /tmp/supabase_full_restore/db/data.sql.gz | docker exec -i ${CONTAINER} psql -U ${PGUSER} -d ${PGDATABASE}

# 5. Restore storage
echo "Restoring storage..."
cd /tmp/supabase_full_restore/storage/${BACKUP_DATE}
tar -xzf *.tar.gz
cp -r _minio_raw_backup/.minio.sys/* ${MINIO_DATA_PATH}/.minio.sys/

# 6. Set permissions
chown -R 1000:1000 ${MINIO_DATA_PATH} 2>/dev/null || true

# 7. Start services
echo "Starting Supabase services..."
docker start supabase-db-ugwwsc8wg4k8o4ssskw4ooco
docker start supabase-minio-ugwwsc8wg4k8o4ssskw4ooco

# 8. Verify
echo "Verifying restore..."
sleep 10
docker exec ${CONTAINER} psql -U ${PGUSER} -d ${PGDATABASE} -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"

echo "Restore completed!"
```

---

## Troubleshooting

### Issue: Database restore fails with permission errors

**Solution:**
```bash
# Ensure you're using the correct user
docker exec -i ${CONTAINER} psql -U postgres -d postgres
```

### Issue: Storage files not accessible after restore

**Solution:**
```bash
# Check MinIO container status
docker ps | grep minio

# Check permissions
ls -la /data/coolify/services/ugwwsc8wg4k8o4ssskw4ooco/volumes/storage/

# Restart MinIO
docker restart supabase-minio-ugwwsc8wg4k8o4ssskw4ooco
```

### Issue: Backup files not found

**Solution:**
```bash
# Verify rclone connection
rclone lsd b2supabase:supabasedaillybackup/

# Check if backup exists
rclone ls b2supabase:supabasedaillybackup/supabase-daily-backup/YYYY-MM-DD/
```

### Issue: Restore takes too long

**Solution:**
- Large databases may take 30+ minutes to restore
- Monitor progress: `docker exec ${CONTAINER} psql -U postgres -c "SELECT COUNT(*) FROM pg_stat_activity;"`
- Consider restoring during maintenance window

---

## Quick Reference

### Download Latest Backup
```bash
LATEST_BACKUP=$(rclone lsd b2supabase:supabasedaillybackup/supabase-daily-backup/ | tail -1 | awk '{print $5}')
echo "Latest backup: ${LATEST_BACKUP}"
```

### Check Backup Contents
```bash
rclone ls b2supabase:supabasedaillybackup/supabase-daily-backup/YYYY-MM-DD/
```

### Verify Backup Integrity
```bash
# Check file sizes
rclone size b2supabase:supabasedaillybackup/supabase-daily-backup/YYYY-MM-DD/
```

---

## Important Notes

1. **Always backup current data** before restoring
2. **Test restores** in a staging environment first
3. **Database restores** may take time for large databases
4. **Storage restores** require stopping MinIO container
5. **Verify backups** before deleting old data
6. **Keep multiple backup copies** for critical data

---

## Support

For issues or questions:
- Check backup logs: `/var/log/supabase_backup_b2.log`
- Check storage backup logs: `/var/log/supabase_storage_backup_b2.log`
- Verify rclone configuration: `rclone config show b2supabase`

