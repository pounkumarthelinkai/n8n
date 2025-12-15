# Quick Reference Card - n8n CI/CD Pipeline

## 🔐 Encryption Keys (SAVE THESE!)

```
DEV:  Hu9ULwSu+ebw2ZEDHjSJYZvhZXqnyemlEcGT8uR9u4Y=
PROD: phJ3GSA0d9cGPkhiNL97lonX08jtllbuwdF96AZb/FA=
```

## 📡 VPS Connection Commands

```bash
# DEV VPS
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118

# PROD VPS
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144
```

## 🚀 Common Operations

### Export from DEV (Workflows & Credentials)
```bash
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118
/srv/n8n/scripts/export_from_dev.sh
```

### Export from DEV (Full Database)
```bash
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118
/srv/n8n/scripts/export_from_dev.sh --full-db
# Backup location: /root/n8n_backups/dev_safe_backup_YYYYMMDD_HHMMSS/database.sqlite
```

### Import to PROD (Workflows & Credentials)
```bash
# Transfer package first
scp -i C:\Users\admin\.ssh\github_deploy_key \
  root@194.238.17.118:/srv/n8n/migration-temp/n8n_export_*.tar.gz \
  root@72.61.226.144:/srv/n8n/migration-temp/

# Then import
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144
/srv/n8n/scripts/import_to_prod.sh /srv/n8n/migration-temp/n8n_export_*.tar.gz
```

### Import to PROD (Full Database)
```bash
# Transfer backup file first
scp -i C:\Users\admin\.ssh\github_deploy_key \
  root@194.238.17.118:/root/n8n_backups/dev_safe_backup_*/database.sqlite \
  root@72.61.226.144:/root/n8n_backups/dev_safe_backup/

# Then import (PROD backup created automatically)
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144
/srv/n8n/scripts/import_to_prod.sh --full-db \
  /root/n8n_backups/dev_safe_backup/database.sqlite
```

## 🔄 Transfer Modes

### Workflows-Only Mode (Default)
- ✅ Exports workflows and credentials
- ✅ Uses credential allowlist
- ✅ Credentials re-encrypted with PROD key
- ⚡ Fast transfer (~30 seconds)
- 📝 Use for: Regular workflow updates

### Full Database Mode
- ✅ Exports complete database
- ✅ Includes: workflows, credentials, users, history
- ✅ Automatic encryption key sync
- ⏱️ Slower transfer (~16 minutes for 1.7GB)
- 📝 Use for: Complete migration, disaster recovery
- 🔒 Automatic PROD backup before import

### Check Status
```bash
# On either VPS
/srv/n8n/scripts/check_status.sh
```

### Manual Backup
```bash
# On either VPS
/srv/n8n/scripts/backup.sh
```

### View Logs
```bash
# Export logs
tail -f /srv/n8n/logs/export_*.log

# Import logs
tail -f /srv/n8n/logs/import_*.log

# Health check
tail -f /srv/n8n/logs/health_check.log
```

## 📂 Important Directories

```
/srv/n8n/scripts/           # All CI/CD scripts
/srv/n8n/logs/              # Operation logs
/srv/n8n/backups/           # Database backups
/srv/n8n/migration-temp/    # Export/import staging
/srv/n8n/.env               # Environment config
```

## 🔄 Backup Locations

### Full Database Backups
```
DEV:  /root/n8n_backups/dev_safe_backup_YYYYMMDD_HHMMSS/
PROD: /root/n8n_backups/prod_backup_YYYYMMDD_HHMMSS/
```

### Legacy Backups
```
DEV:  /root/n8n_backup_20251211_063647/  (920MB)
PROD: /root/n8n_backup_20251211_063722/  (44KB)
```

## 🌐 n8n URLs

```
DEV:  https://n8n.thelinkai.com/
PROD: https://n8n-prod.thelinkai.com
```

## 📝 GitHub Secrets Needed

```
SSH_PRIVATE_KEY         # Contents of C:\Users\admin\.ssh\github_deploy_key
DEV_ENCRYPTION_KEY      # Hu9ULwSu+ebw2ZEDHjSJYZvhZXqnyemlEcGT8uR9u4Y=
PROD_ENCRYPTION_KEY     # phJ3GSA0d9cGPkhiNL97lonX08jtllbuwdF96AZb/FA=
```

## ⚡ Troubleshooting

```bash
# n8n not responding
docker restart root-n8n-1            # DEV
docker restart n8n-p8so440wk0kk0w40c48cgg00  # PROD

# Check containers
docker ps

# Check logs
docker logs root-n8n-1               # DEV
docker logs n8n-p8so440wk0kk0w40c48cgg00     # PROD

# Restore from backup
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/[backup-file].sql.gz
```

## 📊 Current Container Names

```
DEV:  root-n8n-1
PROD: n8n-p8so440wk0kk0w40c48cgg00
```

## ✅ Quick Health Check

```bash
# On either VPS
curl http://localhost:5678/healthz
```

---

**REMEMBER:** 
- ⚠️ DEV and PROD have DIFFERENT encryption keys
- ⚠️ Backup keys to password manager
- ⚠️ Update credential allowlist before production migration
- ⚠️ Test in DEV first, then promote to PROD

