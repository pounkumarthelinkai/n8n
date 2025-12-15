# n8n CI/CD Pipeline - Two-Environment Setup

A complete CI/CD pipeline for n8n workflow automation, featuring automated deployment from DEV to PROD with secure credential management and workflow promotion.

## 🌟 Features

- **Two-Environment Setup**: Separate DEV and PROD VPS instances
- **Dual Transfer Modes**: 
  - **Workflows-Only**: Export/import workflows and credentials (default)
  - **Full Database**: Complete database transfer (workflows, credentials, users, history)
- **Automated Export/Import**: Seamless workflow migration from DEV to PROD
- **Secure Credential Management**: Credential allowlisting and encryption key separation
- **Automatic Encryption Key Sync**: Synchronizes encryption keys for credential decryption
- **Corruption Prevention**: Safe SQLite backup using `.backup` command
- **GitHub Actions Integration**: Automated CI/CD with transfer mode selection
- **Database Backup & Restore**: Automated daily backups with rotation
- **Health Monitoring**: Automated health checks and self-healing
- **Workflow Activation Control**: Only activate workflows that were active in DEV
- **Webhook Registration**: Automatic webhook re-registration on import
- **Rollback Capability**: Automatic PROD backup before import for easy rollback

## 📋 Prerequisites

- Two VPS servers (DEV and PROD)
- Ubuntu 20.04+ or Debian 11+
- Root SSH access to both servers
- GitHub repository for version control
- SSH key for GitHub Actions authentication

## 🚀 Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/your-org/n8n-cicd-pipeline.git
cd n8n-cicd-pipeline
```

### 2. Setup DEV VPS

```bash
# SSH into DEV VPS
ssh -i ~/.ssh/github_deploy_key root@194.238.17.118

# Download and run setup script
wget https://raw.githubusercontent.com/your-org/n8n-cicd-pipeline/main/scripts/dev_setup.sh
chmod +x dev_setup.sh

# Set environment variables
export N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
export N8N_HOST="dev-n8n.yourdomain.com"
export WEBHOOK_URL="http://dev-n8n.yourdomain.com"
export POSTGRES_PASSWORD=$(openssl rand -base64 24)

# Run setup
./dev_setup.sh
```

### 3. Setup PROD VPS

```bash
# SSH into PROD VPS
ssh -i ~/.ssh/github_deploy_key root@72.61.226.144

# Download and run setup script
wget https://raw.githubusercontent.com/your-org/n8n-cicd-pipeline/main/scripts/prod_setup.sh
chmod +x prod_setup.sh

# Set environment variables (USE DIFFERENT ENCRYPTION KEY!)
export N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
export N8N_HOST="n8n.yourdomain.com"
export WEBHOOK_URL="https://n8n.yourdomain.com"
export POSTGRES_PASSWORD=$(openssl rand -base64 32)

# Run setup
./prod_setup.sh
```

### 4. Configure GitHub Actions

1. Go to your GitHub repository settings
2. Navigate to **Settings > Secrets and variables > Actions**
3. Add the following secrets:

```
SSH_PRIVATE_KEY: Your SSH private key
DEV_ENCRYPTION_KEY: DEV environment encryption key
PROD_ENCRYPTION_KEY: PROD environment encryption key
```

### 5. Deploy Scripts to VPS

```bash
# Copy scripts to DEV VPS
scp -i ~/.ssh/github_deploy_key scripts/* root@194.238.17.118:/srv/n8n/scripts/

# Copy scripts to PROD VPS
scp -i ~/.ssh/github_deploy_key scripts/* root@72.61.226.144:/srv/n8n/scripts/

# Copy credential allowlist to both VPS
scp -i ~/.ssh/github_deploy_key config/credential_allowlist.txt root@194.238.17.118:/srv/n8n/
scp -i ~/.ssh/github_deploy_key config/credential_allowlist.txt root@72.61.226.144:/srv/n8n/
```

## 📂 Project Structure

```
n8n-cicd-pipeline/
├── .github/
│   └── workflows/
│       └── n8n-cicd.yml          # GitHub Actions workflow
├── scripts/
│   ├── dev_setup.sh              # DEV VPS setup
│   ├── prod_setup.sh             # PROD VPS setup
│   ├── export_from_dev.sh        # Export workflows from DEV
│   ├── import_to_prod.sh         # Import workflows to PROD
│   ├── backup.sh                 # Database backup
│   └── restore.sh                # Database restore
├── config/
│   ├── env.dev.example           # DEV environment template
│   ├── env.prod.example          # PROD environment template
│   └── credential_allowlist.txt  # Credential filter
├── templates/
│   ├── docker-compose.dev.yml    # DEV Docker Compose
│   └── docker-compose.prod.yml   # PROD Docker Compose
├── docs/
│   ├── DEV_SETUP.md             # DEV setup guide
│   ├── PROD_SETUP.md            # PROD setup guide
│   ├── MIGRATION_FLOW.md        # Migration process
│   ├── BACKUP_RESTORE.md        # Backup procedures
│   ├── SECURITY_MODEL.md        # Security guidelines
│   └── ENVIRONMENT_STRUCTURE.md # Directory structure
└── README.md                     # This file
```

## 🔄 Workflow

### Automatic Export (on push to main)

1. Developer pushes workflows to `main` branch
2. GitHub Actions triggers automatically
3. Exports workflows and credentials from DEV
4. Validates export integrity
5. Uploads artifacts to GitHub

### Manual Promotion to PROD

1. Go to **Actions** tab in GitHub
2. Select **n8n CI/CD Pipeline** workflow
3. Click **Run workflow**
4. Enable **"Promote to Production"** option
5. Workflow will:
   - Create pre-deployment backup
   - Transfer export package to PROD
   - Import workflows (all inactive)
   - Activate workflows that were active in DEV
   - Register webhooks
   - Run smoke tests
   - Clean up sensitive files

## 🔒 Security Features

- **Separate Encryption Keys**: DEV and PROD use different keys
- **Credential Allowlist**: Only approved credentials are migrated
- **Decrypted File Cleanup**: Temporary decrypted files are removed
- **Inactive Import**: Workflows imported as inactive, activated selectively
- **Pre-deployment Backups**: Automatic backup before each deployment
- **Checksum Verification**: All transfers are checksum-validated

## 📊 Monitoring & Maintenance

### Health Checks

- **DEV**: Every 30 minutes
- **PROD**: Every 15 minutes
- Auto-restart on failure

### Backups

- **DEV**: Daily at 2:00 AM
- **PROD**: Every 6 hours + daily at 2:00 AM
- Retention: 14 daily, 8 weekly

### Log Rotation

- **DEV**: 14 days retention
- **PROD**: 30 days retention
- Automatic compression

## 🛠️ Common Operations

### View Logs

```bash
# DEV
ssh root@194.238.17.118
cd /srv/n8n && docker-compose logs -f

# PROD
ssh root@72.61.226.144
cd /srv/n8n && docker-compose logs -f
```

### Manual Backup

```bash
ssh root@[VPS-IP]
/srv/n8n/scripts/backup.sh
```

### Restore from Backup

```bash
ssh root@[VPS-IP]
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/[backup-file].sql.gz
```

### Manual Export from DEV

```bash
ssh root@194.238.17.118
/srv/n8n/scripts/export_from_dev.sh
```

### Manual Import to PROD

```bash
# Transfer package first
scp [package].tar.gz root@72.61.226.144:/srv/n8n/migration-temp/

# SSH and import
ssh root@72.61.226.144
/srv/n8n/scripts/import_to_prod.sh /srv/n8n/migration-temp/[package].tar.gz
```

## 📚 Documentation

- [DEV Setup Guide](docs/DEV_SETUP.md) - Detailed DEV VPS setup
- [PROD Setup Guide](docs/PROD_SETUP.md) - Detailed PROD VPS setup
- [Migration Flow](docs/MIGRATION_FLOW.md) - Step-by-step migration process
- [Backup & Restore](docs/BACKUP_RESTORE.md) - Backup procedures and recovery
- [Security Model](docs/SECURITY_MODEL.md) - Security guidelines and best practices
- [Environment Structure](docs/ENVIRONMENT_STRUCTURE.md) - Directory and file structure

## 🐛 Troubleshooting

### n8n Container Won't Start

```bash
# Check logs
docker logs n8n-dev  # or n8n-prod

# Check environment variables
cat /srv/n8n/.env

# Restart services
cd /srv/n8n && docker-compose restart
```

### Database Connection Issues

```bash
# Check Postgres container
docker ps | grep postgres

# Test database connection
docker exec n8n-postgres-dev psql -U n8n -d n8n -c "SELECT 1;"
```

### Webhook Not Working After Import

Webhooks are automatically toggled during import. If issues persist:

```bash
# Manually restart n8n
docker restart n8n-prod

# Check webhook registration in n8n logs
docker logs n8n-prod | grep webhook
```

### Export/Import Failures

```bash
# Check logs
cat /srv/n8n/logs/export_*.log
cat /srv/n8n/logs/import_*.log

# Verify encryption keys match between environments
# (DEV and PROD should have DIFFERENT keys)
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

MIT License - see LICENSE file for details

## 🆘 Support

- **Documentation**: Check the [docs/](docs/) directory
- **Issues**: Open an issue on GitHub
- **Discussions**: Use GitHub Discussions

## 🔗 Links

- [n8n Documentation](https://docs.n8n.io/)
- [Docker Documentation](https://docs.docker.com/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## ⚠️ Important Notes

1. **Never use the same encryption key for DEV and PROD**
2. **Review credential allowlist before each deployment**
3. **Test workflows in DEV before promoting to PROD**
4. **Always create backups before major changes**
5. **Monitor logs after deployments**
6. **Keep SSH keys secure and never commit them**

## 📅 Version History

- **v1.0.0** (Current) - Initial release
  - Two-environment setup
  - Automated CI/CD pipeline
  - Secure credential management
  - Backup and restore functionality
  - Health monitoring

---

**Built with ❤️ for automated workflow management**

