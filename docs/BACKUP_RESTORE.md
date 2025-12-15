# Backup & Restore Guide

Comprehensive guide for backing up and restoring your n8n environments.

## 📋 Overview

The backup system provides:

- **Automated Daily Backups**: Run at 2:00 AM
- **Production Frequency**: Additional backups every 6 hours
- **Automatic Rotation**: Keep 14 daily, 8 weekly backups
- **Integrity Verification**: Checksums for all backups
- **Compression**: Gzip compression for space efficiency
- **Metadata Tracking**: Backup information and versioning

## 🔄 Backup Strategy

### DEV Environment

```bash
Frequency: Daily at 2:00 AM
Retention: 14 days (daily) + 8 weeks (weekly)
Location: /srv/n8n/backups/
```

### PROD Environment

```bash
Frequency: Every 6 hours + Daily at 2:00 AM
Retention: 14 days (daily) + 8 weeks (weekly)
Location: /srv/n8n/backups/
```

## 📂 Backup Structure

```
/srv/n8n/backups/
├── daily/
│   ├── n8n_dev_20240101_020000.sql.gz
│   ├── n8n_dev_20240101_020000.sql.gz.sha256
│   ├── n8n_dev_20240101_020000.sql.gz.meta
│   ├── n8n_dev_20240102_020000.sql.gz
│   └── ...
├── weekly/
│   ├── n8n_dev_20240107_020000.sql.gz  (Sunday)
│   └── ...
└── manual/
    └── n8n_dev_manual_20240101_120000.sql.gz
```

## 🔧 Manual Backup

### Create Backup

```bash
# SSH to VPS
ssh root@[VPS-IP]

# Run backup script
/srv/n8n/scripts/backup.sh

# Backup will be created in appropriate directory
# Check output for location
```

### Verify Backup

```bash
# List recent backups
ls -lht /srv/n8n/backups/daily/ | head -5

# Check backup metadata
cat /srv/n8n/backups/daily/n8n_prod_*.sql.gz.meta

# Verify checksum
cd /srv/n8n/backups/daily
sha256sum -c n8n_prod_*.sql.gz.sha256
```

### Download Backup

```bash
# From your local machine
scp -i ~/.ssh/github_deploy_key \
  root@[VPS-IP]:/srv/n8n/backups/daily/n8n_prod_*.sql.gz \
  ./local-backup/

# Verify downloaded file
sha256sum n8n_prod_*.sql.gz
```

## 🔄 Restore Operations

### Restore from Recent Backup

```bash
# 1. SSH to VPS
ssh root@[VPS-IP]

# 2. List available backups
ls -lht /srv/n8n/backups/daily/

# 3. Run restore script
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/n8n_prod_20240101_020000.sql.gz

# Script will:
# - Create a safety backup
# - Stop n8n
# - Restore database
# - Start n8n
# - Verify restoration

# 4. Verify workflows
# Access n8n UI and check workflows
```

### Restore from Specific Backup

```bash
# For DEV
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/n8n_dev_20240101_020000.sql.gz

# For PROD (requires confirmation)
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/n8n_prod_20240101_020000.sql.gz
# Type 'yes' when prompted
```

### Restore from Weekly Backup

```bash
# Use weekly backups for older data
ls -lh /srv/n8n/backups/weekly/

/srv/n8n/scripts/restore.sh /srv/n8n/backups/weekly/n8n_prod_20231225_020000.sql.gz
```

### Restore from Off-Site Backup

```bash
# 1. Upload backup to VPS
scp -i ~/.ssh/github_deploy_key \
  ./local-backup/n8n_prod_20240101_020000.sql.gz \
  root@[VPS-IP]:/srv/n8n/backups/manual/

# 2. Restore
ssh root@[VPS-IP]
/srv/n8n/scripts/restore.sh /srv/n8n/backups/manual/n8n_prod_20240101_020000.sql.gz
```

## 🚨 Emergency Procedures

### Scenario 1: Database Corruption

```bash
# Symptoms:
# - n8n won't start
# - Database errors in logs
# - Workflows not loading

# Resolution:
# 1. Access VPS
ssh root@[VPS-IP]

# 2. Check database
docker logs n8n-postgres-prod

# 3. Find latest good backup
ls -lht /srv/n8n/backups/daily/ | head

# 4. Restore
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/[latest-backup].sql.gz

# 5. Verify
docker restart n8n-prod
curl https://n8n.yourdomain.com/healthz
```

### Scenario 2: Accidental Workflow Deletion

```bash
# If workflow deleted in PROD:

# Option A: Restore from backup
# 1. Find backup before deletion
ls -lht /srv/n8n/backups/

# 2. Note: This restores ENTIRE database
# All changes after backup will be lost!

# 3. Restore
/srv/n8n/scripts/restore.sh /srv/n8n/backups/[backup-file].sql.gz

# Option B: Re-import from DEV
# 1. Export from DEV
ssh root@194.238.17.118
/srv/n8n/scripts/export_from_dev.sh

# 2. Import specific workflow to PROD
# (Manual process - copy workflow JSON)
```

### Scenario 3: Credential Loss

```bash
# If credentials lost or corrupted:

# Option A: Restore from backup
/srv/n8n/scripts/restore.sh /srv/n8n/backups/[backup-before-loss].sql.gz

# Option B: Re-import from DEV
# Run full DEV → PROD migration
# See MIGRATION_FLOW.md
```

### Scenario 4: Complete VPS Failure

```bash
# If VPS is completely down/destroyed:

# 1. Provision new VPS
# 2. Run setup script
./prod_setup.sh

# 3. Download backup from off-site
scp ./offsite-backup/[latest-backup].sql.gz root@[NEW-VPS]:/srv/n8n/backups/manual/

# 4. Restore
ssh root@[NEW-VPS]
/srv/n8n/scripts/restore.sh /srv/n8n/backups/manual/[backup].sql.gz

# 5. Update DNS to point to new VPS
# 6. Update SSL certificate if needed
```

## 📊 Backup Monitoring

### Check Backup Status

```bash
# View recent backup logs
tail -f /srv/n8n/logs/backup_*.log

# Check last backup time
ls -lht /srv/n8n/backups/daily/ | head -1

# View backup statistics
/srv/n8n/scripts/backup.sh | grep -A 10 "Backup statistics"
```

### Verify Backup Schedule

```bash
# Check cron jobs
crontab -l

# DEV should show:
# 0 2 * * * /srv/n8n/scripts/backup.sh

# PROD should show:
# 0 2 * * * /srv/n8n/scripts/backup.sh
# 0 */6 * * * /srv/n8n/scripts/backup.sh
```

### Test Backup Integrity

```bash
# Verify checksums
cd /srv/n8n/backups/daily
for checksum in *.sha256; do
    echo "Checking $checksum..."
    sha256sum -c "$checksum"
done

# Test decompression
gzip -t /srv/n8n/backups/daily/*.sql.gz
echo "All backups are valid"
```

## 💾 Off-Site Backup Strategy

### Option 1: Cloud Storage (Recommended)

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure cloud provider (example: AWS S3)
rclone config

# Create backup sync script
cat > /srv/n8n/scripts/backup_to_cloud.sh << 'EOF'
#!/bin/bash
# Sync backups to cloud storage

BACKUP_DIR="/srv/n8n/backups"
REMOTE="s3:your-bucket/n8n-backups"

# Sync daily backups
rclone sync ${BACKUP_DIR}/daily/ ${REMOTE}/daily/ --progress

# Sync weekly backups
rclone sync ${BACKUP_DIR}/weekly/ ${REMOTE}/weekly/ --progress

echo "Cloud backup completed"
EOF

chmod +x /srv/n8n/scripts/backup_to_cloud.sh

# Add to cron (daily at 3 AM, after local backup)
echo "0 3 * * * /srv/n8n/scripts/backup_to_cloud.sh >> /srv/n8n/logs/cloud_backup.log 2>&1" | crontab -a
```

### Option 2: Remote Server

```bash
# Set up SSH key for remote server
ssh-keygen -t rsa -b 4096 -f ~/.ssh/backup_server
ssh-copy-id -i ~/.ssh/backup_server.pub user@backup-server

# Create remote sync script
cat > /srv/n8n/scripts/backup_to_remote.sh << 'EOF'
#!/bin/bash
# Sync backups to remote server

BACKUP_DIR="/srv/n8n/backups"
REMOTE="user@backup-server:/backups/n8n/"

# Sync using rsync
rsync -avz --delete \
    -e "ssh -i ~/.ssh/backup_server" \
    ${BACKUP_DIR}/ \
    ${REMOTE}

echo "Remote backup completed"
EOF

chmod +x /srv/n8n/scripts/backup_to_remote.sh

# Add to cron
echo "0 3 * * * /srv/n8n/scripts/backup_to_remote.sh >> /srv/n8n/logs/remote_backup.log 2>&1" | crontab -a
```

### Option 3: Manual Download

```bash
# Download all backups periodically
mkdir -p ~/n8n-backups-$(date +%Y%m)

scp -r -i ~/.ssh/github_deploy_key \
    root@72.61.226.144:/srv/n8n/backups/ \
    ~/n8n-backups-$(date +%Y%m)/
```

## 🔒 Backup Security

### Encrypt Backups

```bash
# Install gpg
apt-get install -y gnupg

# Generate encryption key
gpg --gen-key

# Encrypt backup
gpg --encrypt --recipient your-email@example.com \
    /srv/n8n/backups/daily/n8n_prod_20240101_020000.sql.gz

# Creates: n8n_prod_20240101_020000.sql.gz.gpg

# To decrypt later:
gpg --decrypt n8n_prod_20240101_020000.sql.gz.gpg > backup.sql.gz
```

### Secure Backup Storage

```bash
# Set restrictive permissions
chmod 700 /srv/n8n/backups
chmod 600 /srv/n8n/backups/*/*.gz

# Only root can access
chown -R root:root /srv/n8n/backups
```

## 📅 Backup Retention Policy

### Default Retention

```bash
Daily Backups:  14 days
Weekly Backups: 8 weeks
Manual Backups: Never deleted automatically
```

### Adjust Retention

Edit `/srv/n8n/scripts/backup.sh`:

```bash
# Change these values:
DAILY_RETENTION=14   # Change to desired days
WEEKLY_RETENTION=8   # Change to desired weeks
```

### Manual Cleanup

```bash
# Remove backups older than 30 days
find /srv/n8n/backups/daily -name "*.sql.gz" -mtime +30 -delete

# Remove all manual backups
rm -f /srv/n8n/backups/manual/*.sql.gz
```

## 🧪 Testing Backup/Restore

### Test 1: Create and Restore Backup

```bash
# 1. Create test workflow in DEV
# - Simple HTTP request workflow
# - Note: "Test Backup Workflow"

# 2. Create backup
/srv/n8n/scripts/backup.sh

# 3. Delete the workflow (via UI)

# 4. Restore backup
LATEST=$(ls -t /srv/n8n/backups/daily/*.sql.gz | head -1)
/srv/n8n/scripts/restore.sh "$LATEST"

# 5. Verify workflow is back
# Check n8n UI - workflow should reappear
```

### Test 2: Backup Integrity

```bash
# Verify all checksums
cd /srv/n8n/backups/daily
sha256sum -c *.sha256

# Test all compressions
for backup in *.sql.gz; do
    echo "Testing $backup..."
    gzip -t "$backup" && echo "✓ OK" || echo "✗ CORRUPTED"
done
```

### Test 3: Cross-Environment Restore

```bash
# Copy PROD backup to DEV for testing
scp root@72.61.226.144:/srv/n8n/backups/daily/n8n_prod_*.sql.gz /tmp/

# Restore to DEV (for testing)
ssh root@194.238.17.118
/srv/n8n/scripts/restore.sh /tmp/n8n_prod_*.sql.gz

# This tests restore procedure without affecting PROD
```

## 📊 Backup Reports

### Generate Backup Report

```bash
cat > /srv/n8n/scripts/backup_report.sh << 'EOF'
#!/bin/bash
# Generate backup report

echo "=== n8n Backup Report ==="
echo "Generated: $(date)"
echo ""

echo "Backup Counts:"
echo "  Daily:  $(ls /srv/n8n/backups/daily/*.sql.gz 2>/dev/null | wc -l)"
echo "  Weekly: $(ls /srv/n8n/backups/weekly/*.sql.gz 2>/dev/null | wc -l)"
echo "  Manual: $(ls /srv/n8n/backups/manual/*.sql.gz 2>/dev/null | wc -l)"
echo ""

echo "Storage Usage:"
du -sh /srv/n8n/backups/*
echo ""

echo "Latest Backups:"
ls -lht /srv/n8n/backups/daily/*.sql.gz | head -3
echo ""

echo "Oldest Backups:"
ls -lt /srv/n8n/backups/daily/*.sql.gz | tail -3
EOF

chmod +x /srv/n8n/scripts/backup_report.sh

# Run report
/srv/n8n/scripts/backup_report.sh
```

## ✅ Backup Checklist

### Daily
- [ ] Verify backup completed (check logs)
- [ ] Check backup file exists
- [ ] Monitor disk space

### Weekly
- [ ] Test backup integrity (checksums)
- [ ] Verify backup rotation working
- [ ] Review backup logs for errors

### Monthly
- [ ] Test restore procedure
- [ ] Verify off-site backups
- [ ] Review retention policy
- [ ] Update backup documentation

### Quarterly
- [ ] Full disaster recovery test
- [ ] Review backup strategy
- [ ] Audit backup security
- [ ] Update backup scripts if needed

## 🆘 Troubleshooting

### Issue: Backup Fails

```bash
# Check logs
tail -f /srv/n8n/logs/backup_*.log

# Check disk space
df -h

# Check database container
docker ps | grep postgres

# Manual backup attempt
docker exec n8n-postgres-prod pg_dump -U n8n n8n > /tmp/test_backup.sql
```

### Issue: Restore Fails

```bash
# Check backup file integrity
gzip -t /srv/n8n/backups/daily/[backup].sql.gz

# Check database is running
docker ps | grep postgres

# Try manual restore
gunzip -c [backup].sql.gz | docker exec -i n8n-postgres-prod psql -U n8n -d n8n
```

### Issue: Disk Space Full

```bash
# Check usage
df -h /srv/n8n

# Remove old backups
find /srv/n8n/backups -name "*.sql.gz" -mtime +30 -delete

# Compress logs
find /srv/n8n/logs -name "*.log" -mtime +7 -exec gzip {} \;

# Clean Docker
docker system prune -a
```

---

**Important**: Always test your backups! A backup is only as good as your ability to restore it.

**Next**: Read [Security Model](SECURITY_MODEL.md) for security best practices.

