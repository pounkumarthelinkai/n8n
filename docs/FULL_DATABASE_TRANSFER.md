# Full Database Transfer Guide

Complete guide for transferring the full n8n database (workflows, credentials, users, execution history) from DEV to PROD.

## Overview

The full database transfer mode transfers **everything** from DEV to PROD:
- ✅ All workflows (with active states preserved)
- ✅ All credentials (encrypted, automatically decrypted)
- ✅ All users and user accounts
- ✅ Execution history
- ✅ User preferences and settings
- ✅ All n8n data

## Prerequisites

1. Both DEV and PROD must use **SQLite** database (not PostgreSQL)
2. Encryption keys must be synchronized (handled automatically)
3. Both VPS servers must be accessible via SSH
4. Updated scripts must be deployed to both servers

## Safety Features

### 1. Safe Backup Method
- Uses SQLite's `.backup` command (atomic, prevents corruption)
- Never copies live database files directly
- Creates backup files that are then transferred

### 2. Automatic Backups
- **DEV**: Backup created before export
- **PROD**: Backup created before import (allows rollback)

### 3. Integrity Verification
- Backup integrity checked before transfer
- Database integrity verified after restore
- VACUUM operation compacts database

### 4. Encryption Key Synchronization
- Automatically extracts encryption key from DEV
- Updates PROD docker-compose.yml or .env file
- Updates PROD config file (`/home/node/.n8n/config`)
- Restarts container to apply changes

## Usage

### Manual Transfer

#### Step 1: Export from DEV

```bash
# SSH to DEV server
ssh root@194.238.17.118

# Run export with --full-db flag
/srv/n8n/scripts/export_from_dev.sh --full-db

# Output will show backup location:
# DEV backup created: /root/n8n_backups/dev_safe_backup_YYYYMMDD_HHMMSS/database.sqlite
```

#### Step 2: Transfer Backup File

```bash
# From your local machine
scp -i ~/.ssh/github_deploy_key \
  root@194.238.17.118:/root/n8n_backups/dev_safe_backup_YYYYMMDD_HHMMSS/database.sqlite \
  root@72.61.226.144:/root/n8n_backups/dev_safe_backup/
```

#### Step 3: Import to PROD

```bash
# SSH to PROD server
ssh root@72.61.226.144

# Run import with --full-db flag
/srv/n8n/scripts/import_to_prod.sh --full-db \
  /root/n8n_backups/dev_safe_backup/database.sqlite
```

### GitHub Actions Transfer

1. Go to GitHub Actions
2. Select "n8n CI/CD Pipeline"
3. Click "Run workflow"
4. Select transfer mode: **"full-database"**
5. Click "Run workflow"

The workflow will:
1. Create backup on DEV
2. Create backup on PROD (before import)
3. Transfer backup file from DEV to PROD
4. Import database to PROD
5. Sync encryption keys
6. Update config files
7. Restart containers
8. Verify health

## What Gets Transferred

### Included in Full Database Transfer

- **Workflows**: All workflows with their configurations
- **Credentials**: All credentials (automatically decrypted/re-encrypted)
- **Users**: All user accounts and passwords
- **Execution History**: All workflow execution records
- **User Preferences**: Settings and preferences
- **Workflow Statistics**: Usage metrics
- **Tags**: Workflow tags
- **Webhooks**: Webhook configurations

### Not Included

- Binary data files (stored separately)
- Custom nodes (if installed separately)
- SSH keys (if stored separately)

## Encryption Key Handling

### Automatic Synchronization

The import script automatically:
1. Extracts encryption key from DEV config file
2. Updates PROD docker-compose.yml (if using docker-compose/Coolify)
3. Updates PROD .env file (if exists)
4. Updates PROD config file (`/home/node/.n8n/config`)
5. Restarts container to apply changes

### Why This is Safe

- Credentials in the database are encrypted with DEV's key
- After transfer, PROD uses DEV's key (synchronized)
- Credentials can be decrypted because keys match
- No manual re-entry of credentials needed

## Rollback Procedure

If something goes wrong, you can rollback using the PROD backup:

```bash
# SSH to PROD
ssh root@72.61.226.144

# Find the backup created before import
ls -lht /root/n8n_backups/prod_backup_*/

# Restore from backup
/srv/n8n/scripts/import_to_prod.sh --full-db \
  /root/n8n_backups/prod_backup_YYYYMMDD_HHMMSS/database.sqlite
```

## Verification

After import, verify everything works:

```bash
# Check n8n health
docker exec <n8n-container> wget -q -O- http://localhost:5678/healthz

# Check database size
docker exec <n8n-container> ls -lh /home/node/.n8n/database.sqlite

# Check workflows count
docker exec <n8n-container> n8n list:workflow | wc -l

# Check credentials (should be decryptable)
# Access n8n UI and verify credentials are visible
```

## Troubleshooting

### Issue: "Couldn't connect with these settings" for credentials

**Cause**: Encryption key mismatch

**Solution**: 
1. Verify encryption key is synchronized
2. Check config file matches environment variable
3. Restart container

### Issue: Database corruption errors

**Cause**: Backup was corrupted during transfer

**Solution**:
1. Use rollback procedure
2. Re-transfer backup file
3. Verify file integrity before import

### Issue: Container won't start after import

**Cause**: Config file has invalid JSON

**Solution**:
1. Check config file format
2. Restore from PROD backup
3. Re-run import

## Best Practices

1. **Always backup PROD first** - The script does this automatically
2. **Test on DEV first** - Verify backup works before transferring
3. **Monitor logs** - Check import logs for any issues
4. **Verify after import** - Test workflows and credentials
5. **Keep backups** - Don't delete backup files immediately

## Comparison: Full DB vs Workflows-Only

| Feature | Full Database | Workflows-Only |
|---------|--------------|----------------|
| Workflows | ✅ All | ✅ All |
| Credentials | ✅ All (auto) | ✅ Selected (allowlist) |
| Users | ✅ All | ❌ No |
| Execution History | ✅ All | ❌ No |
| User Preferences | ✅ All | ❌ No |
| Transfer Speed | Slower (large file) | Faster (small package) |
| Use Case | Complete migration | Regular updates |

## Security Considerations

1. **Backup files contain sensitive data** - Handle with care
2. **Encryption keys are synchronized** - Both environments use same key
3. **Transfer over SSH** - Encrypted channel
4. **Backup files are large** - May take time to transfer
5. **Credentials are included** - No need for separate credential export

## Support

For issues or questions:
1. Check logs: `/srv/n8n/logs/import_*.log`
2. Verify backups: `/root/n8n_backups/`
3. Check container status: `docker ps`
4. Review GitHub Actions logs

