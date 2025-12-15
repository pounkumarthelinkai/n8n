# Quick Start Guide

Get your n8n CI/CD pipeline running in 30 minutes!

## 🎯 Prerequisites Checklist

Before starting, ensure you have:

- [ ] Two VPS servers (Ubuntu 20.04+)
- [ ] SSH access to both VPS:
  - DEV: `194.238.17.118`
  - PROD: `72.61.226.144`
- [ ] SSH key: `C:\Users\admin\.ssh\github_deploy_key`
- [ ] GitHub repository created
- [ ] Domain names (optional but recommended):
  - DEV: `dev-n8n.yourdomain.com`
  - PROD: `n8n.yourdomain.com`

## ⚡ Quick Setup (30 minutes)

### Step 1: Setup DEV VPS (10 minutes)

```bash
# Connect to DEV VPS
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118

# Clone repository
git clone https://github.com/your-org/n8n-cicd-pipeline.git
cd n8n-cicd-pipeline

# Set environment variables
export N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
export N8N_HOST="194.238.17.118:5678"
export WEBHOOK_URL="http://194.238.17.118:5678"
export POSTGRES_PASSWORD=$(openssl rand -base64 24)

# Save keys (IMPORTANT!)
echo "DEV_KEY=$N8N_ENCRYPTION_KEY" > ~/n8n_keys.txt
echo "DEV_PASS=$POSTGRES_PASSWORD" >> ~/n8n_keys.txt

# Run setup
chmod +x scripts/dev_setup.sh
./scripts/dev_setup.sh

# Wait for completion (5-10 minutes)
# Setup will install Docker, n8n, and Postgres
```

### Step 2: Setup PROD VPS (10 minutes)

```bash
# Connect to PROD VPS
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144

# Clone repository
git clone https://github.com/your-org/n8n-cicd-pipeline.git
cd n8n-cicd-pipeline

# Set environment variables (DIFFERENT KEY!)
export N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
export N8N_HOST="72.61.226.144:5678"  # Or your domain
export WEBHOOK_URL="https://72.61.226.144:5678"  # Or your domain
export POSTGRES_PASSWORD=$(openssl rand -base64 32)

# Save keys (IMPORTANT!)
echo "PROD_KEY=$N8N_ENCRYPTION_KEY" > ~/n8n_keys.txt
echo "PROD_PASS=$POSTGRES_PASSWORD" >> ~/n8n_keys.txt

# Run setup
chmod +x scripts/prod_setup.sh
./scripts/prod_setup.sh

# Wait for completion (5-10 minutes)
```

### Step 3: Configure GitHub Actions (5 minutes)

```bash
# On your local machine

# 1. Go to GitHub repository settings
# 2. Navigate to: Settings > Secrets and variables > Actions
# 3. Add these secrets:

SSH_PRIVATE_KEY          # Contents of C:\Users\admin\.ssh\github_deploy_key
DEV_ENCRYPTION_KEY       # From DEV ~/n8n_keys.txt
PROD_ENCRYPTION_KEY      # From PROD ~/n8n_keys.txt
```

### Step 4: Deploy Scripts (5 minutes)

```bash
# From your local machine (Windows PowerShell)

# Copy scripts to DEV
scp -i C:\Users\admin\.ssh\github_deploy_key scripts/* root@194.238.17.118:/srv/n8n/scripts/
scp -i C:\Users\admin\.ssh\github_deploy_key config/credential_allowlist.txt root@194.238.17.118:/srv/n8n/

# Copy scripts to PROD
scp -i C:\Users\admin\.ssh\github_deploy_key scripts/* root@72.61.226.144:/srv/n8n/scripts/
scp -i C:\Users\admin\.ssh\github_deploy_key config/credential_allowlist.txt root@72.61.226.144:/srv/n8n/

# Make scripts executable on both
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118 'chmod +x /srv/n8n/scripts/*.sh'
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144 'chmod +x /srv/n8n/scripts/*.sh'
```

## ✅ Verify Installation

### Check DEV

```bash
# Access DEV n8n
# Browser: http://194.238.17.118:5678

# Or check status
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118
/srv/n8n/scripts/check_status.sh
```

### Check PROD

```bash
# Access PROD n8n
# Browser: http://72.61.226.144:5678

# Or check status
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144
/srv/n8n/scripts/check_status.sh
```

## 🚀 First Deployment

### 1. Create Test Workflow in DEV

```bash
# 1. Access DEV: http://194.238.17.118:5678
# 2. Create first user account
# 3. Create simple workflow:
#    - HTTP Request node → GET https://api.github.com
#    - Save as "Test API Call"
# 4. Activate workflow
```

### 2. Configure Credential Allowlist

```bash
# On DEV VPS
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118

# Edit allowlist
nano /srv/n8n/credential_allowlist.txt

# Add your credential patterns (or keep * for testing)
# Save and exit (Ctrl+X, Y, Enter)
```

### 3. Run Manual Export

```bash
# On DEV VPS
/srv/n8n/scripts/export_from_dev.sh

# Check export was successful
ls -lh /srv/n8n/migration-temp/export/
cat /srv/n8n/migration-temp/export/export_metadata.json
```

### 4. Transfer to PROD

```bash
# Find latest export package
PACKAGE=$(ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118 \
  'ls -t /srv/n8n/migration-temp/n8n_export_*.tar.gz | head -1')

# Copy to PROD
scp -i C:\Users\admin\.ssh\github_deploy_key \
  root@194.238.17.118:$PACKAGE \
  ./n8n_export.tar.gz

scp -i C:\Users\admin\.ssh\github_deploy_key \
  ./n8n_export.tar.gz \
  root@72.61.226.144:/srv/n8n/migration-temp/
```

### 5. Import to PROD

```bash
# On PROD VPS
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144

# Run import
/srv/n8n/scripts/import_to_prod.sh /srv/n8n/migration-temp/n8n_export.tar.gz

# Verify import
# Access PROD UI: http://72.61.226.144:5678
# Check that "Test API Call" workflow appears and is active
```

## 🎉 Success! What's Next?

### Enable Automatic Deployment

```bash
# 1. Push code to main branch
git add .
git commit -m "Initial n8n CI/CD setup"
git push origin main

# 2. Check GitHub Actions
# Go to: https://github.com/your-org/n8n-cicd-pipeline/actions
# You should see the workflow running

# 3. For production deployment
# Go to Actions > n8n CI/CD Pipeline > Run workflow
# Enable "Promote to Production"
# Click "Run workflow"
```

### Recommended Next Steps

1. **Configure SSL** (for production):
   - Follow [PROD_SETUP.md](docs/PROD_SETUP.md#security-configuration-required-for-production)
   - Set up Nginx with Let's Encrypt

2. **Customize Credential Allowlist**:
   - Edit `/srv/n8n/credential_allowlist.txt`
   - Replace `*` with specific credential names
   - More info: [SECURITY_MODEL.md](docs/SECURITY_MODEL.md#credential-management)

3. **Set Up Monitoring**:
   - Configure external health monitoring
   - Set up alerts for failures
   - More info: [PROD_SETUP.md](docs/PROD_SETUP.md#monitoring-setup)

4. **Test Backup/Restore**:
   - Create manual backup: `/srv/n8n/scripts/backup.sh`
   - Test restore procedure
   - More info: [BACKUP_RESTORE.md](docs/BACKUP_RESTORE.md)

5. **Create More Workflows**:
   - Build workflows in DEV
   - Test thoroughly
   - Promote to PROD via GitHub Actions

## 📚 Full Documentation

- [README.md](README.md) - Complete overview
- [DEV_SETUP.md](docs/DEV_SETUP.md) - Detailed DEV setup
- [PROD_SETUP.md](docs/PROD_SETUP.md) - Detailed PROD setup
- [MIGRATION_FLOW.md](docs/MIGRATION_FLOW.md) - Migration process
- [BACKUP_RESTORE.md](docs/BACKUP_RESTORE.md) - Backup procedures
- [SECURITY_MODEL.md](docs/SECURITY_MODEL.md) - Security guidelines
- [ENVIRONMENT_STRUCTURE.md](docs/ENVIRONMENT_STRUCTURE.md) - Directory structure

## 🆘 Troubleshooting

### n8n won't start

```bash
# Check logs
docker logs n8n-dev  # or n8n-prod

# Restart
cd /srv/n8n && docker-compose restart
```

### Can't access n8n UI

```bash
# Check if containers are running
docker ps

# Check firewall
ufw status

# Check n8n is listening
netstat -tulpn | grep 5678
```

### Export/Import fails

```bash
# Check logs
cat /srv/n8n/logs/export_*.log
cat /srv/n8n/logs/import_*.log

# Verify encryption keys are different
ssh root@194.238.17.118 'grep N8N_ENCRYPTION_KEY /srv/n8n/.env'
ssh root@72.61.226.144 'grep N8N_ENCRYPTION_KEY /srv/n8n/.env'
```

## 💡 Quick Commands

```bash
# View status
/srv/n8n/scripts/check_status.sh

# Create backup
/srv/n8n/scripts/backup.sh

# Restore backup
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/[backup-file].sql.gz

# Export workflows
/srv/n8n/scripts/export_from_dev.sh

# Import workflows
/srv/n8n/scripts/import_to_prod.sh /srv/n8n/migration-temp/[package].tar.gz

# Clean up old files
/srv/n8n/scripts/cleanup.sh --dry-run  # Preview
/srv/n8n/scripts/cleanup.sh            # Actually clean

# View logs
tail -f /srv/n8n/logs/*.log

# Restart n8n
cd /srv/n8n && docker-compose restart
```

## ⚠️ Important Reminders

1. **Save your encryption keys!** You can't decrypt credentials without them.
2. **DEV and PROD must have DIFFERENT encryption keys!**
3. **Test in DEV before deploying to PROD!**
4. **Configure credential allowlist before production use!**
5. **Set up SSL for production!**
6. **Test your backups regularly!**

---

**Need help?** Check the [full documentation](README.md) or open an issue on GitHub.

**Ready to go?** Start creating workflows in DEV and promote them to PROD! 🚀

