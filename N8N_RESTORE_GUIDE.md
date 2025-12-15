# n8n Backup Restore Guide

## Overview
This guide explains how to restore n8n backups (workflows, credentials, data) from Backblaze B2.

## Backup Location
- **Backblaze Bucket**: `supabasedaillybackup`
- **n8n Backups**: `n8n-backups/`
- **Backup Format**: `n8n_backup_YYYYMMDD_HHMMSS.tar.gz`
- **Retention**: Last 10 backups are kept automatically

## Prerequisites
- Access to the n8n VPS server (root@69.62.82.163)
- SSH key: `C:\Users\admin\.ssh\github_deploy_key`
- rclone configured with Backblaze credentials
- Docker access to n8n container

---

## Part 1: List Available Backups

### Step 1: Connect to VPS

```bash
ssh -i C:\Users\admin\.ssh\github_deploy_key root@69.62.82.163
```

### Step 2: List All Backups

```bash
# List all n8n backups
rclone lsf b2n8n:supabasedaillybackup/n8n-backups/

# List with sizes (human-readable)
rclone ls b2n8n:supabasedaillybackup/n8n-backups/ --human-readable

# List with details (size and date)
rclone lsf b2n8n:supabasedaillybackup/n8n-backups/ -l --human-readable
```

**Example Output:**
```
n8n_backup_20251206_103925.tar.gz
n8n_backup_20251206_104534.tar.gz
```

---

## Part 2: Restore Using Restore Script (Recommended)

### Step 1: Run Restore Script

```bash
# The restore script will show available backups and prompt for selection
/usr/local/bin/restore_n8n_backup.sh
```

### Step 2: Select Backup

The script will display available backups. Enter the backup filename:

```bash
/usr/local/bin/restore_n8n_backup.sh n8n_backup_20251206_104534.tar.gz
```

### Step 3: Confirm Restore

The script will:
1. Ask for confirmation (type `yes`)
2. Stop n8n container
3. Create a safety backup of current data
4. Download the backup from Backblaze
5. Extract and restore files
6. Set correct permissions
7. Start n8n container

**Example Output:**
```
n8n Backup Restore Script
=========================

Restoring from backup: n8n_backup_20251206_104534.tar.gz

WARNING: This will replace all current n8n data!
Current n8n data will be backed up to: /var/lib/docker/volumes/n8n_data/_data/.backup_before_restore/
Are you sure you want to continue? (yes/no): yes

Stopping n8n container...
Backing up current data...
Downloading backup from Backblaze...
Extracting backup...
Restoring files to n8n data directory...
  Database restored
  Binary data restored
  Configuration restored
  Custom nodes restored
  SSH keys restored
Setting file permissions...
Starting n8n container...

==========================================
Restore completed successfully!
```

---

## Part 3: Manual Restore (Step-by-Step)

### Step 1: Download Backup

```bash
# Set backup filename
BACKUP_FILE="n8n_backup_20251206_104534.tar.gz"

# Download from Backblaze
rclone copy b2n8n:supabasedaillybackup/n8n-backups/${BACKUP_FILE} /tmp/n8n_restore/ --progress
```

### Step 2: Extract Backup

```bash
cd /tmp/n8n_restore
tar -xzf ${BACKUP_FILE}

# Check contents
ls -la n8n_backup_*/
```

**Backup Contents:**
- `database.sqlite` - All workflows, credentials, executions
- `binaryData/` - Binary files used by workflows
- `config` - n8n configuration
- `nodes/` - Custom nodes
- `ssh/` - SSH keys
- `git/` - Git repository (if used)
- `backup_info.txt` - Backup metadata

### Step 3: Stop n8n

```bash
# Stop n8n container
docker stop root-n8n-1

# Verify it's stopped
docker ps | grep n8n
```

### Step 4: Backup Current Data (Safety)

```bash
N8N_DATA_PATH="/var/lib/docker/volumes/n8n_data/_data"
SAFETY_BACKUP="${N8N_DATA_PATH}/.backup_before_restore_$(date +%Y%m%d_%H%M%S)"

# Create safety backup
mkdir -p "${SAFETY_BACKUP}"
cp -r ${N8N_DATA_PATH}/* "${SAFETY_BACKUP}/" 2>/dev/null || true

echo "Safety backup created at: ${SAFETY_BACKUP}"
```

### Step 5: Restore Files

```bash
EXTRACTED_DIR="/tmp/n8n_restore/n8n_backup_20251206_104534"
N8N_DATA_PATH="/var/lib/docker/volumes/n8n_data/_data"

# Restore database
if [ -f "${EXTRACTED_DIR}/database.sqlite" ]; then
    cp "${EXTRACTED_DIR}/database.sqlite" "${N8N_DATA_PATH}/database.sqlite"
    echo "✓ Database restored"
fi

# Restore binary data
if [ -d "${EXTRACTED_DIR}/binaryData" ]; then
    rm -rf "${N8N_DATA_PATH}/binaryData"
    cp -r "${EXTRACTED_DIR}/binaryData" "${N8N_DATA_PATH}/binaryData"
    echo "✓ Binary data restored"
fi

# Restore configuration
if [ -f "${EXTRACTED_DIR}/config" ]; then
    cp "${EXTRACTED_DIR}/config" "${N8N_DATA_PATH}/config"
    echo "✓ Configuration restored"
fi

# Restore custom nodes
if [ -d "${EXTRACTED_DIR}/nodes" ]; then
    rm -rf "${N8N_DATA_PATH}/nodes"
    cp -r "${EXTRACTED_DIR}/nodes" "${N8N_DATA_PATH}/nodes"
    echo "✓ Custom nodes restored"
fi

# Restore SSH keys
if [ -d "${EXTRACTED_DIR}/ssh" ]; then
    rm -rf "${N8N_DATA_PATH}/ssh"
    cp -r "${EXTRACTED_DIR}/ssh" "${N8N_DATA_PATH}/ssh"
    echo "✓ SSH keys restored"
fi

# Restore git repository
if [ -d "${EXTRACTED_DIR}/git" ]; then
    rm -rf "${N8N_DATA_PATH}/git"
    cp -r "${EXTRACTED_DIR}/git" "${N8N_DATA_PATH}/git"
    echo "✓ Git repository restored"
fi
```

### Step 6: Set Permissions

```bash
N8N_DATA_PATH="/var/lib/docker/volumes/n8n_data/_data"

# Set correct ownership (n8n runs as user 1000 or ubuntu)
chown -R 1000:1000 "${N8N_DATA_PATH}" 2>/dev/null || \
chown -R ubuntu:ubuntu "${N8N_DATA_PATH}" 2>/dev/null || \
echo "Note: Permissions may need manual adjustment"
```

### Step 7: Start n8n

```bash
# Start n8n container
docker start root-n8n-1

# Verify it's running
docker ps | grep n8n

# Check logs
docker logs root-n8n-1 --tail 50
```

### Step 8: Verify Restore

```bash
# Wait a few seconds for n8n to start
sleep 10

# Check if n8n is accessible
curl -I https://n8n.sesai.in 2>/dev/null | head -1

# Or check container health
docker ps | grep n8n
```

---

## Part 4: Selective Restore (Specific Components)

### Restore Only Workflows

```bash
# Extract backup
cd /tmp
tar -xzf n8n_backup_YYYYMMDD_HHMMSS.tar.gz

# Stop n8n
docker stop root-n8n-1

# Backup current database
cp /var/lib/docker/volumes/n8n_data/_data/database.sqlite \
   /var/lib/docker/volumes/n8n_data/_data/database.sqlite.backup

# Extract only database from backup
cp n8n_backup_*/database.sqlite /var/lib/docker/volumes/n8n_data/_data/

# Start n8n
docker start root-n8n-1
```

### Restore Only Credentials

```bash
# Use SQLite to extract credentials from backup database
sqlite3 /tmp/n8n_restore/n8n_backup_*/database.sqlite \
  "SELECT name, type, data FROM credentials;" > /tmp/credentials_export.txt

# Review credentials
cat /tmp/credentials_export.txt

# Then manually import via n8n UI or restore full database
```

### Restore Only Custom Nodes

```bash
# Extract and restore custom nodes only
tar -xzf n8n_backup_YYYYMMDD_HHMMSS.tar.gz
cp -r n8n_backup_*/nodes/* /var/lib/docker/volumes/n8n_data/_data/nodes/

# Restart n8n to load new nodes
docker restart root-n8n-1
```

---

## Part 5: Complete Disaster Recovery

### Full System Restore Script

```bash
#!/bin/bash
# Complete n8n restore script

set -euo pipefail

BACKUP_FILE="${1:-}"
N8N_DATA_PATH="/var/lib/docker/volumes/n8n_data/_data"
N8N_CONTAINER="root-n8n-1"
RCLONE_REMOTE="b2n8n:supabasedaillybackup/n8n-backups"

if [ -z "${BACKUP_FILE}" ]; then
    echo "Usage: $0 <backup_filename>"
    echo ""
    echo "Available backups:"
    rclone lsf "${RCLONE_REMOTE}/" | grep "n8n_backup_" | sort -r
    exit 1
fi

echo "=========================================="
echo "n8n Complete Restore"
echo "=========================================="
echo "Backup: ${BACKUP_FILE}"
echo ""

# Safety check
read -p "This will replace ALL n8n data. Continue? (yes/no): " confirm
if [ "${confirm}" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Create temp directory
TMPDIR=$(mktemp -d)
cd "${TMPDIR}"

# Download backup
echo "Step 1: Downloading backup..."
rclone copy "${RCLONE_REMOTE}/${BACKUP_FILE}" . --progress

# Extract backup
echo "Step 2: Extracting backup..."
tar -xzf "${BACKUP_FILE}"
EXTRACTED_DIR=$(find . -type d -name "n8n_backup_*" | head -1)

# Stop n8n
echo "Step 3: Stopping n8n..."
docker stop "${N8N_CONTAINER}"

# Create safety backup
echo "Step 4: Creating safety backup..."
SAFETY_BACKUP="${N8N_DATA_PATH}/.safety_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${SAFETY_BACKUP}"
cp -r "${N8N_DATA_PATH}"/* "${SAFETY_BACKUP}/" 2>/dev/null || true

# Restore files
echo "Step 5: Restoring files..."
cp "${EXTRACTED_DIR}/database.sqlite" "${N8N_DATA_PATH}/database.sqlite"
[ -d "${EXTRACTED_DIR}/binaryData" ] && rm -rf "${N8N_DATA_PATH}/binaryData" && cp -r "${EXTRACTED_DIR}/binaryData" "${N8N_DATA_PATH}/"
[ -f "${EXTRACTED_DIR}/config" ] && cp "${EXTRACTED_DIR}/config" "${N8N_DATA_PATH}/config"
[ -d "${EXTRACTED_DIR}/nodes" ] && rm -rf "${N8N_DATA_PATH}/nodes" && cp -r "${EXTRACTED_DIR}/nodes" "${N8N_DATA_PATH}/"
[ -d "${EXTRACTED_DIR}/ssh" ] && rm -rf "${N8N_DATA_PATH}/ssh" && cp -r "${EXTRACTED_DIR}/ssh" "${N8N_DATA_PATH}/"
[ -d "${EXTRACTED_DIR}/git" ] && rm -rf "${N8N_DATA_PATH}/git" && cp -r "${EXTRACTED_DIR}/git" "${N8N_DATA_PATH}/"

# Set permissions
echo "Step 6: Setting permissions..."
chown -R 1000:1000 "${N8N_DATA_PATH}" 2>/dev/null || chown -R ubuntu:ubuntu "${N8N_DATA_PATH}" 2>/dev/null || true

# Start n8n
echo "Step 7: Starting n8n..."
docker start "${N8N_CONTAINER}"

# Cleanup
rm -rf "${TMPDIR}"

echo ""
echo "=========================================="
echo "Restore completed successfully!"
echo "Safety backup: ${SAFETY_BACKUP}"
echo "n8n URL: https://n8n.sesai.in"
echo "=========================================="
```

**Save and use:**
```bash
# Save script
nano /usr/local/bin/n8n_full_restore.sh
chmod +x /usr/local/bin/n8n_full_restore.sh

# Run restore
/usr/local/bin/n8n_full_restore.sh n8n_backup_20251206_104534.tar.gz
```

---

## Part 6: Verify Backup Before Restore

### Check Backup Integrity

```bash
# Download and verify backup size
BACKUP_FILE="n8n_backup_20251206_104534.tar.gz"
rclone ls b2n8n:supabasedaillybackup/n8n-backups/${BACKUP_FILE}

# Expected size: ~1.1 GB (compressed)
# If size is 0 bytes, the backup may be incomplete
```

### Test Extract Locally

```bash
# Download to temp location
rclone copy b2n8n:supabasedaillybackup/n8n-backups/${BACKUP_FILE} /tmp/test_restore/

# Extract and check contents
cd /tmp/test_restore
tar -xzf ${BACKUP_FILE}
ls -lh n8n_backup_*/

# Check database file exists and has size
ls -lh n8n_backup_*/database.sqlite
# Should show ~3.2GB file
```

---

## Troubleshooting

### Issue: Restore script not found

**Solution:**
```bash
# Check if restore script exists
ls -la /usr/local/bin/restore_n8n_backup.sh

# If missing, it should be at:
# /usr/local/bin/restore_n8n_backup.sh
```

### Issue: n8n won't start after restore

**Solution:**
```bash
# Check container logs
docker logs root-n8n-1 --tail 100

# Check file permissions
ls -la /var/lib/docker/volumes/n8n_data/_data/

# Fix permissions
chown -R 1000:1000 /var/lib/docker/volumes/n8n_data/_data/

# Restart container
docker restart root-n8n-1
```

### Issue: Database is corrupted

**Solution:**
```bash
# Check database integrity
sqlite3 /var/lib/docker/volumes/n8n_data/_data/database.sqlite "PRAGMA integrity_check;"

# If corrupted, restore from safety backup
cp /var/lib/docker/volumes/n8n_data/_data/.backup_before_restore_*/database.sqlite \
   /var/lib/docker/volumes/n8n_data/_data/database.sqlite
```

### Issue: Workflows missing after restore

**Solution:**
```bash
# Verify database was restored correctly
sqlite3 /var/lib/docker/volumes/n8n_data/_data/database.sqlite \
  "SELECT COUNT(*) FROM workflow_entity;"

# Check if workflows exist
sqlite3 /var/lib/docker/volumes/n8n_data/_data/database.sqlite \
  "SELECT name, active FROM workflow_entity LIMIT 10;"
```

### Issue: Credentials not working

**Solution:**
```bash
# Credentials are encrypted in the database
# If they don't work, you may need to:
# 1. Re-enter credentials in n8n UI
# 2. Or restore from a backup where credentials were working
# 3. Check if encryption keys match
```

### Issue: Backup file shows 0 bytes

**Solution:**
```bash
# Check actual file size via rclone
rclone ls b2n8n:supabasedaillybackup/n8n-backups/ | grep "n8n_backup_"

# If 0 bytes, the upload may have failed
# Check backup logs
tail -50 /var/log/n8n_backup_b2.log

# Re-run backup if needed
/usr/local/bin/n8n_backup_b2.sh
```

---

## Quick Reference

### List Latest Backup
```bash
LATEST_BACKUP=$(rclone lsf b2n8n:supabasedaillybackup/n8n-backups/ | grep "n8n_backup_" | sort -r | head -1)
echo "Latest backup: ${LATEST_BACKUP}"
```

### Quick Restore (One Command)
```bash
# Using restore script
LATEST=$(rclone lsf b2n8n:supabasedaillybackup/n8n-backups/ | grep "n8n_backup_" | sort -r | head -1)
/usr/local/bin/restore_n8n_backup.sh "${LATEST}"
```

### Check Backup Age
```bash
# List backups with dates
rclone lsf b2n8n:supabasedaillybackup/n8n-backups/ -l --human-readable | grep "n8n_backup_"
```

### Verify n8n After Restore
```bash
# Check container status
docker ps | grep n8n

# Check if accessible
curl -I https://n8n.sesai.in

# Check database
sqlite3 /var/lib/docker/volumes/n8n_data/_data/database.sqlite \
  "SELECT COUNT(*) FROM workflow_entity;"
```

---

## Important Notes

1. **Always create a safety backup** before restoring
2. **Stop n8n** before restoring to prevent data corruption
3. **Database file is large** (~3.2GB) - restore may take 5-10 minutes
4. **Workflows and credentials** are stored in the database
5. **Custom nodes** are in the nodes/ directory
6. **SSH keys** are in the ssh/ directory
7. **Test restores** in a staging environment first
8. **Keep multiple backups** for critical workflows

---

## Backup Schedule

- **Frequency**: Daily at 2:00 AM UTC
- **Retention**: Last 10 backups (older backups auto-deleted)
- **Location**: `supabasedaillybackup/n8n-backups/`
- **Logs**: `/var/log/n8n_backup_b2.log`

---

## Support

For issues or questions:
- Check backup logs: `tail -50 /var/log/n8n_backup_b2.log`
- Verify rclone configuration: `rclone config show b2n8n`
- Check n8n container: `docker logs root-n8n-1 --tail 100`
- Verify backup exists: `rclone ls b2n8n:supabasedaillybackup/n8n-backups/`

---

## Emergency Contacts

- **n8n VPS**: root@69.62.82.163
- **SSH Key**: `C:\Users\admin\.ssh\github_deploy_key`
- **n8n URL**: https://n8n.sesai.in
- **Container Name**: root-n8n-1

