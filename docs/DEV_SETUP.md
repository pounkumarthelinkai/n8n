# DEV VPS Setup Guide

Complete guide for setting up the n8n DEV environment on your VPS.

## 📋 Prerequisites

- VPS with Ubuntu 20.04+ or Debian 11+
- Root SSH access
- Minimum 2GB RAM
- 20GB storage
- Open port 5678 (or your preferred port)

## 🔑 VPS Connection Details

```bash
# DEV VPS Connection
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118
```

## 📝 Pre-Setup Checklist

- [ ] VPS is accessible via SSH
- [ ] Root or sudo access available
- [ ] Firewall allows port 5678 (or configured port)
- [ ] Domain name configured (optional but recommended)
- [ ] SSL certificate ready (optional for DEV)

## 🚀 Installation Steps

### Step 1: Prepare Environment Variables

Before running the setup script, prepare your environment variables:

```bash
# Generate encryption key (save this securely!)
export N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
echo "DEV Encryption Key: $N8N_ENCRYPTION_KEY" >> ~/n8n_keys.txt

# Set hostname (use your domain or IP)
export N8N_HOST="dev-n8n.yourdomain.com"
# OR use IP address:
# export N8N_HOST="194.238.17.118:5678"

# Set webhook URL
export WEBHOOK_URL="http://${N8N_HOST}"

# Generate secure database password
export POSTGRES_PASSWORD=$(openssl rand -base64 24)
echo "DEV DB Password: $POSTGRES_PASSWORD" >> ~/n8n_keys.txt

# Set database credentials
export POSTGRES_USER="n8n"
export POSTGRES_DB="n8n"
```

### Step 2: Download Setup Script

```bash
# Create working directory
mkdir -p ~/n8n-setup
cd ~/n8n-setup

# Option A: If you have git access to the repo
git clone https://github.com/your-org/n8n-cicd-pipeline.git
cd n8n-cicd-pipeline

# Option B: Download directly
wget https://raw.githubusercontent.com/your-org/n8n-cicd-pipeline/main/scripts/dev_setup.sh
chmod +x dev_setup.sh
```

### Step 3: Run Setup Script

```bash
# Make sure all environment variables are set
echo "Encryption Key: $N8N_ENCRYPTION_KEY"
echo "Database Password: $POSTGRES_PASSWORD"
echo "Host: $N8N_HOST"

# Run the setup script
./dev_setup.sh

# Script will:
# - Install Docker and Docker Compose (if not present)
# - Create directory structure at /srv/n8n
# - Configure environment variables
# - Start n8n and Postgres containers
# - Set up health checks and backups
# - Configure log rotation
```

### Step 4: Verify Installation

```bash
# Check if containers are running
docker ps

# You should see:
# - n8n-dev
# - n8n-postgres-dev

# Check n8n health
curl http://localhost:5678/healthz

# View logs
cd /srv/n8n
docker-compose logs -f
```

### Step 5: Initial Configuration

```bash
# Access n8n web interface
# Open browser: http://194.238.17.118:5678
# OR: http://dev-n8n.yourdomain.com

# Create first user account
# Set up initial credentials
# Configure workflows
```

## 📂 Directory Structure

After setup, you'll have:

```
/srv/n8n/
├── docker-compose.yml        # Docker Compose configuration
├── .env                       # Environment variables (SECURE!)
├── n8n-data/                 # n8n workflows and data
├── postgres-data/            # Database data
├── logs/                     # Application logs
├── backups/                  # Database backups
│   ├── daily/               # Daily backups
│   ├── weekly/              # Weekly backups
│   └── manual/              # Manual backups
├── scripts/                  # Utility scripts
│   ├── backup.sh
│   ├── restore.sh
│   ├── export_from_dev.sh
│   └── import_to_prod.sh
├── migration-temp/           # Temporary migration files
│   └── export/              # Export staging
├── health_check.sh          # Health monitoring script
├── SETUP_SUMMARY.txt        # Installation summary (SECURE!)
└── credential_allowlist.txt # Credential filter
```

## 🔧 Post-Installation Configuration

### 1. Copy Scripts to VPS

```bash
# From your local machine
scp -i ~/.ssh/github_deploy_key scripts/* root@194.238.17.118:/srv/n8n/scripts/
scp -i ~/.ssh/github_deploy_key config/credential_allowlist.txt root@194.238.17.118:/srv/n8n/

# Make scripts executable
ssh root@194.238.17.118 'chmod +x /srv/n8n/scripts/*.sh'
```

### 2. Configure Credential Allowlist

```bash
# Edit allowlist
nano /srv/n8n/credential_allowlist.txt

# Add credential name patterns (one per line)
# Example:
production-*
prod-api
slack-webhook
```

### 3. Test Backup System

```bash
# Run manual backup
/srv/n8n/scripts/backup.sh

# Verify backup was created
ls -lh /srv/n8n/backups/daily/

# Test restore (optional)
# /srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/[backup-file].sql.gz
```

### 4. Test Export Function

```bash
# Run export test
/srv/n8n/scripts/export_from_dev.sh

# Check export artifacts
ls -lh /srv/n8n/migration-temp/export/

# Verify export package
ls -lh /srv/n8n/migration-temp/*.tar.gz
```

## 🔒 Security Hardening

### 1. Secure Environment Files

```bash
# Ensure proper permissions
chmod 600 /srv/n8n/.env
chmod 600 /srv/n8n/SETUP_SUMMARY.txt
chmod 700 /srv/n8n/migration-temp
```

### 2. Configure Firewall

```bash
# Install UFW if not present
apt-get install -y ufw

# Allow SSH
ufw allow 22/tcp

# Allow n8n port
ufw allow 5678/tcp

# Enable firewall
ufw --force enable

# Check status
ufw status
```

### 3. Set Up SSL (Optional but Recommended)

```bash
# Install Nginx
apt-get install -y nginx certbot python3-certbot-nginx

# Configure Nginx reverse proxy
cat > /etc/nginx/sites-available/n8n << 'EOF'
server {
    listen 80;
    server_name dev-n8n.yourdomain.com;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Enable site
ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# Get SSL certificate
certbot --nginx -d dev-n8n.yourdomain.com
```

## 📊 Monitoring Setup

### 1. Check Health Monitoring

```bash
# View health check cron
crontab -l | grep health_check

# Expected: */30 * * * * /srv/n8n/health_check.sh

# Test health check manually
/srv/n8n/health_check.sh

# View health logs
tail -f /srv/n8n/logs/health_check.log
```

### 2. Check Backup Schedule

```bash
# View backup cron
crontab -l | grep backup

# Expected: 0 2 * * * /srv/n8n/scripts/backup.sh

# View backup logs
tail -f /srv/n8n/logs/backup_*.log
```

## 🧪 Testing

### 1. Create Test Workflow

```bash
# Access n8n UI
# Create a simple workflow:
# - HTTP Request node (GET https://api.github.com)
# - Save workflow

# Test webhook
# - Create workflow with Webhook node
# - Note the webhook URL
# - Test with curl:
curl -X POST http://dev-n8n.yourdomain.com/webhook-test/[webhook-id]
```

### 2. Test Database Connection

```bash
# Connect to database
docker exec -it n8n-postgres-dev psql -U n8n -d n8n

# Run test queries
SELECT COUNT(*) FROM workflow_entity;
SELECT COUNT(*) FROM credentials_entity;
\q
```

### 3. Test Export Function

```bash
# Export workflows
/srv/n8n/scripts/export_from_dev.sh

# Check export output
cat /srv/n8n/logs/export_*.log
```

## 🐛 Troubleshooting

### Issue: Docker not installed

```bash
# Check Docker status
systemctl status docker

# If not running, start it
systemctl start docker
systemctl enable docker
```

### Issue: Containers won't start

```bash
# Check Docker logs
docker logs n8n-dev
docker logs n8n-postgres-dev

# Check for port conflicts
netstat -tulpn | grep 5678

# Restart containers
cd /srv/n8n
docker-compose down
docker-compose up -d
```

### Issue: Can't access n8n UI

```bash
# Check if n8n is listening
netstat -tulpn | grep 5678

# Check firewall
ufw status

# Test locally
curl http://localhost:5678/healthz

# Check logs
docker logs n8n-dev
```

### Issue: Database connection errors

```bash
# Check Postgres container
docker ps | grep postgres

# Check database logs
docker logs n8n-postgres-dev

# Test connection
docker exec n8n-postgres-dev psql -U n8n -d n8n -c "SELECT 1;"

# Restart database
docker restart n8n-postgres-dev
```

### Issue: Encryption key lost

```bash
# Check SETUP_SUMMARY.txt
cat /srv/n8n/SETUP_SUMMARY.txt

# Or check .env
grep N8N_ENCRYPTION_KEY /srv/n8n/.env

# IMPORTANT: If lost, you cannot decrypt existing credentials!
# You'll need to re-create them
```

## 🔄 Updating n8n

```bash
# Pull latest images
cd /srv/n8n
docker-compose pull

# Restart containers
docker-compose down
docker-compose up -d

# Check version
docker exec n8n-dev n8n --version
```

## 📋 Maintenance Checklist

### Daily
- [ ] Check health check logs
- [ ] Verify backup completed

### Weekly
- [ ] Review application logs
- [ ] Check disk space usage
- [ ] Test workflow functionality

### Monthly
- [ ] Update n8n to latest version
- [ ] Review and rotate backups
- [ ] Review credential allowlist
- [ ] Test backup restore procedure

## 📝 Important Notes

1. **Save your encryption key securely!** Without it, you cannot decrypt credentials.
2. **Never commit `.env` or `SETUP_SUMMARY.txt` to git!**
3. **This is a DEV environment** - security can be relaxed compared to PROD.
4. **Test exports regularly** to ensure CI/CD pipeline works.
5. **Monitor disk space** - backups and logs can grow.

## 🆘 Getting Help

If you encounter issues:

1. Check logs: `/srv/n8n/logs/`
2. Review Docker logs: `docker logs n8n-dev`
3. Check GitHub issues
4. Review n8n documentation: https://docs.n8n.io/

## ✅ Setup Complete Checklist

- [ ] Docker and Docker Compose installed
- [ ] n8n and Postgres containers running
- [ ] Health checks configured
- [ ] Backup system operational
- [ ] Scripts deployed and tested
- [ ] Credential allowlist configured
- [ ] Firewall rules set
- [ ] SSL configured (if applicable)
- [ ] First user account created
- [ ] Test workflows created
- [ ] Export function tested
- [ ] Encryption key backed up securely

---

**Next Steps**: Proceed to [PROD Setup Guide](PROD_SETUP.md) to set up your production environment.

