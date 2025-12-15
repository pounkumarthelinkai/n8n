# PROD VPS Setup Guide

Complete guide for setting up the n8n PRODUCTION environment on your VPS.

## ⚠️ IMPORTANT PRODUCTION WARNINGS

This is a **PRODUCTION** environment setup. Extra care is required:

- ✅ Use **DIFFERENT** encryption key than DEV
- ✅ Use **STRONG** passwords (32+ characters)
- ✅ Enable **HTTPS/SSL** (required for production)
- ✅ Configure proper **firewall** rules
- ✅ Set up **monitoring** and **alerts**
- ✅ Test **backup/restore** procedures
- ✅ Review **security** settings

## 📋 Prerequisites

- VPS with Ubuntu 20.04+ or Debian 11+
- Root SSH access
- Minimum 4GB RAM (8GB recommended)
- 50GB+ storage
- Domain name with DNS configured
- SSL certificate
- Open port 443 (HTTPS) and 80 (HTTP)

## 🔑 VPS Connection Details

```bash
# PROD VPS Connection
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144
```

## 📝 Pre-Setup Checklist

- [ ] VPS is accessible via SSH
- [ ] Root or sudo access available
- [ ] Domain name points to VPS IP
- [ ] SSL certificate ready (Let's Encrypt or commercial)
- [ ] Firewall configured (ports 80, 443, 22)
- [ ] Backup storage available
- [ ] Monitoring system ready
- [ ] DEV environment is already set up and working

## 🚀 Installation Steps

### Step 1: Prepare Environment Variables

**CRITICAL**: Use **DIFFERENT** encryption key than DEV!

```bash
# Generate NEW encryption key for PROD (MUST BE DIFFERENT FROM DEV!)
export N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
echo "PROD Encryption Key: $N8N_ENCRYPTION_KEY" >> ~/n8n_keys_PROD.txt

# Verify it's different from DEV key
echo "This should be DIFFERENT from your DEV key!"

# Set production hostname
export N8N_HOST="n8n.yourdomain.com"

# Set webhook URL (HTTPS for production!)
export WEBHOOK_URL="https://${N8N_HOST}"

# Generate STRONG database password (longer for production)
export POSTGRES_PASSWORD=$(openssl rand -base64 32)
echo "PROD DB Password: $POSTGRES_PASSWORD" >> ~/n8n_keys_PROD.txt

# Set database credentials
export POSTGRES_USER="n8n"
export POSTGRES_DB="n8n"

# Secure the keys file
chmod 600 ~/n8n_keys_PROD.txt
```

### Step 2: Download Setup Script

```bash
# Create working directory
mkdir -p ~/n8n-setup
cd ~/n8n-setup

# Option A: If you have git access
git clone https://github.com/your-org/n8n-cicd-pipeline.git
cd n8n-cicd-pipeline

# Option B: Download directly
wget https://raw.githubusercontent.com/your-org/n8n-cicd-pipeline/main/scripts/prod_setup.sh
chmod +x prod_setup.sh
```

### Step 3: Verify Environment Variables

```bash
# CRITICAL: Verify all variables are set correctly
echo "Encryption Key: $N8N_ENCRYPTION_KEY"
echo "Database Password: $POSTGRES_PASSWORD"
echo "Host: $N8N_HOST"
echo "Webhook URL: $WEBHOOK_URL"

# Double-check encryption key is NOT the same as DEV
# Compare with your DEV key to ensure they're different
```

### Step 4: Run Setup Script

```bash
# Run the PRODUCTION setup script
./prod_setup.sh

# Script will:
# - Install Docker and Docker Compose (if not present)
# - Create directory structure at /srv/n8n
# - Configure environment variables
# - Start n8n and Postgres containers
# - Set up MORE FREQUENT health checks
# - Configure MORE FREQUENT backups
# - Configure LONGER log retention
# - Apply production-specific settings
```

### Step 5: Verify Installation

```bash
# Check if containers are running
docker ps

# You should see:
# - n8n-prod
# - n8n-postgres-prod

# Check n8n health
curl http://localhost:5678/healthz

# View logs
cd /srv/n8n
docker-compose logs -f
```

## 🔒 Security Configuration (REQUIRED FOR PRODUCTION)

### 1. Configure Firewall

```bash
# Install UFW
apt-get install -y ufw

# Allow SSH (IMPORTANT: Don't lock yourself out!)
ufw allow 22/tcp

# Allow HTTP (for SSL certificate verification)
ufw allow 80/tcp

# Allow HTTPS
ufw allow 443/tcp

# Enable firewall
ufw --force enable

# Verify rules
ufw status verbose

# IMPORTANT: Verify you can still SSH before closing session!
```

### 2. Set Up SSL with Nginx (REQUIRED)

```bash
# Install Nginx and Certbot
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx

# Create Nginx configuration for n8n
cat > /etc/nginx/sites-available/n8n << 'EOF'
# n8n Production Configuration

upstream n8n_backend {
    server localhost:5678;
    keepalive 32;
}

server {
    listen 80;
    server_name n8n.yourdomain.com;
    
    # Redirect all HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name n8n.yourdomain.com;

    # SSL Configuration (will be managed by Certbot)
    # ssl_certificate /etc/letsencrypt/live/n8n.yourdomain.com/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/n8n.yourdomain.com/privkey.pem;

    # SSL Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Large upload support for n8n
    client_max_body_size 50M;

    location / {
        proxy_pass http://n8n_backend;
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        
        # Headers
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Enable site
ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/

# Test configuration
nginx -t

# Restart Nginx
systemctl restart nginx

# Get SSL certificate from Let's Encrypt
certbot --nginx -d n8n.yourdomain.com --non-interactive --agree-tos --email your-email@example.com

# Verify SSL
curl -I https://n8n.yourdomain.com

# Set up auto-renewal
systemctl enable certbot.timer
systemctl start certbot.timer
```

### 3. Secure File Permissions

```bash
# Secure sensitive files
chmod 600 /srv/n8n/.env
chmod 600 /srv/n8n/SETUP_SUMMARY.txt
chmod 700 /srv/n8n/migration-temp
chmod 700 /srv/n8n/backups

# Ensure scripts are executable
chmod +x /srv/n8n/scripts/*.sh
chmod +x /srv/n8n/health_check.sh
```

### 4. Configure Fail2Ban (Optional but Recommended)

```bash
# Install Fail2Ban
apt-get install -y fail2ban

# Configure for SSH protection
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log
EOF

# Start Fail2Ban
systemctl enable fail2ban
systemctl start fail2ban
```

## 📂 Directory Structure

After setup, you'll have:

```
/srv/n8n/
├── docker-compose.yml        # Docker Compose (PROD config)
├── .env                       # Environment variables (SECURE!)
├── n8n-data/                 # n8n workflows and data
├── postgres-data/            # Database data
├── logs/                     # Application logs (30-day retention)
├── backups/                  # Database backups
│   ├── daily/               # Daily backups (14 retention)
│   ├── weekly/              # Weekly backups (8 retention)
│   └── manual/              # Manual backups
├── scripts/                  # Utility scripts
│   ├── backup.sh
│   ├── restore.sh
│   ├── export_from_dev.sh
│   └── import_to_prod.sh
├── migration-temp/           # Temporary migration files
│   ├── import/              # Import staging
│   └── export/              # Export staging (if needed)
├── health_check.sh          # Health monitoring (15-min interval)
├── SETUP_SUMMARY.txt        # Installation summary (SECURE!)
└── credential_allowlist.txt # Credential filter
```

## 🔧 Post-Installation Configuration

### 1. Copy Scripts to PROD VPS

```bash
# From your local machine
scp -i ~/.ssh/github_deploy_key scripts/* root@72.61.226.144:/srv/n8n/scripts/
scp -i ~/.ssh/github_deploy_key config/credential_allowlist.txt root@72.61.226.144:/srv/n8n/

# Make scripts executable
ssh root@72.61.226.144 'chmod +x /srv/n8n/scripts/*.sh'
```

### 2. Configure Credential Allowlist

```bash
# Edit allowlist for PRODUCTION
nano /srv/n8n/credential_allowlist.txt

# IMPORTANT: Remove the "*" wildcard!
# Add only specific production credential names:

production-database
prod-api-key
slack-webhook-prod
smtp-server-prod
# etc.
```

### 3. Test Backup System

```bash
# Run manual backup
/srv/n8n/scripts/backup.sh

# Verify backup was created
ls -lh /srv/n8n/backups/daily/

# Verify backup integrity
cd /srv/n8n/backups/daily
sha256sum -c *.sha256
```

### 4. Test Restore Procedure (IMPORTANT!)

```bash
# Test restore on a recent backup
# This ensures you CAN restore if needed

# List backups
ls -lh /srv/n8n/backups/daily/

# Test restore (this will overwrite current data - be careful!)
# /srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/[backup-file].sql.gz

# For safety, you might want to test restore on DEV first
```

## 📊 Monitoring Setup

### 1. Health Check Monitoring

```bash
# Verify health check is scheduled
crontab -l | grep health_check

# Expected: */15 * * * * /srv/n8n/health_check.sh (every 15 minutes)

# Test health check
/srv/n8n/health_check.sh

# View health logs
tail -f /srv/n8n/logs/health_check.log

# Check for alerts
cat /srv/n8n/logs/health_alert.log
```

### 2. Backup Monitoring

```bash
# Verify backup schedule
crontab -l | grep backup

# Expected:
# - 0 2 * * * (daily at 2 AM)
# - 0 */6 * * * (every 6 hours)

# View backup logs
tail -f /srv/n8n/logs/backup_*.log

# Verify recent backups
ls -lht /srv/n8n/backups/daily/ | head
```

### 3. Set Up External Monitoring (Recommended)

```bash
# Consider using external monitoring services:
# - UptimeRobot
# - Pingdom
# - StatusCake
# - Custom monitoring scripts

# Monitor:
# - https://n8n.yourdomain.com/healthz
# - SSL certificate expiration
# - Disk space
# - Memory usage
# - CPU usage
```

## 🧪 Testing

### 1. Access n8n UI

```bash
# Open browser
https://n8n.yourdomain.com

# Create admin user account
# DO NOT reuse DEV credentials!
```

### 2. Test Database Connection

```bash
# Connect to database
docker exec -it n8n-postgres-prod psql -U n8n -d n8n

# Check for tables
\dt

# Exit
\q
```

### 3. Test SSL/HTTPS

```bash
# Test SSL certificate
curl -I https://n8n.yourdomain.com

# Should return 200 OK with SSL headers

# Test HTTP redirect
curl -I http://n8n.yourdomain.com

# Should redirect to HTTPS (301)
```

### 4. Test Import (After First DEV Export)

```bash
# This will be done via GitHub Actions
# Or manually for testing:

# Transfer package from DEV
scp root@194.238.17.118:/srv/n8n/migration-temp/n8n_export_*.tar.gz /srv/n8n/migration-temp/

# Import
/srv/n8n/scripts/import_to_prod.sh /srv/n8n/migration-temp/[package].tar.gz

# Verify workflows imported
docker exec n8n-postgres-prod psql -U n8n -d n8n -c "SELECT COUNT(*) FROM workflow_entity;"
```

## 🐛 Troubleshooting

### Issue: SSL Certificate Errors

```bash
# Check Certbot logs
cat /var/log/letsencrypt/letsencrypt.log

# Verify DNS is correct
nslookup n8n.yourdomain.com

# Try manual certificate
certbot certonly --standalone -d n8n.yourdomain.com

# Check Nginx configuration
nginx -t
```

### Issue: Import Fails with Encryption Error

```bash
# Verify encryption key is set
grep N8N_ENCRYPTION_KEY /srv/n8n/.env

# Ensure PROD key is DIFFERENT from DEV
# Credentials must be re-encrypted with PROD key during import

# Check import logs
cat /srv/n8n/logs/import_*.log
```

### Issue: Webhooks Not Working

```bash
# Verify webhook URL in environment
grep WEBHOOK_URL /srv/n8n/.env

# Should be: https://n8n.yourdomain.com

# Check Nginx is proxying correctly
curl -I https://n8n.yourdomain.com/webhook-test

# Restart n8n to re-register webhooks
docker restart n8n-prod
```

### Issue: High Memory Usage

```bash
# Check container stats
docker stats

# Check n8n logs for memory issues
docker logs n8n-prod | grep -i memory

# Consider increasing VPS resources
# Or optimize workflows
```

## 📋 Production Maintenance Checklist

### Daily
- [ ] Check health check logs for failures
- [ ] Verify backups completed successfully
- [ ] Monitor disk space usage
- [ ] Review error logs

### Weekly
- [ ] Review active workflows
- [ ] Check for n8n updates
- [ ] Verify SSL certificate validity
- [ ] Review security logs
- [ ] Test random backup restore

### Monthly
- [ ] Update n8n to latest stable version
- [ ] Review and optimize database
- [ ] Test full disaster recovery procedure
- [ ] Review and update credential allowlist
- [ ] Audit user accounts and permissions
- [ ] Review firewall rules

### Quarterly
- [ ] Full security audit
- [ ] Performance review
- [ ] Capacity planning
- [ ] Backup strategy review

## ⚠️ Production Best Practices

1. **Never Share Encryption Keys**
   - DEV and PROD must use different keys
   - Store keys in secure password manager
   - Never commit keys to git

2. **Always Test in DEV First**
   - Test all workflows in DEV
   - Verify export/import works
   - Only promote tested workflows

3. **Monitor Continuously**
   - Set up alerts for failures
   - Monitor resource usage
   - Track workflow execution times

4. **Maintain Backups**
   - Test restore procedures regularly
   - Keep backups off-site
   - Verify backup integrity

5. **Keep Systems Updated**
   - Update n8n regularly
   - Apply security patches promptly
   - Keep Docker updated

6. **Review Security**
   - Audit credentials regularly
   - Review user access
   - Monitor failed login attempts

## 🆘 Disaster Recovery

### If PROD Fails Completely

```bash
# 1. Access PROD VPS
ssh root@72.61.226.144

# 2. Find latest backup
ls -lht /srv/n8n/backups/daily/ | head

# 3. Restore from backup
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/[latest-backup].sql.gz

# 4. Restart services
cd /srv/n8n && docker-compose restart

# 5. Verify functionality
curl https://n8n.yourdomain.com/healthz
```

### If Backup Storage Fails

```bash
# 1. Export current state from DEV
ssh root@194.238.17.118
/srv/n8n/scripts/export_from_dev.sh

# 2. Import to PROD
scp [export-package] root@72.61.226.144:/srv/n8n/migration-temp/
ssh root@72.61.226.144
/srv/n8n/scripts/import_to_prod.sh [package]
```

## ✅ Production Setup Complete Checklist

- [ ] Docker and Docker Compose installed
- [ ] n8n and Postgres containers running
- [ ] **DIFFERENT** encryption key than DEV
- [ ] **HTTPS/SSL** configured and working
- [ ] Firewall rules configured
- [ ] Fail2Ban installed and configured
- [ ] Health checks every 15 minutes
- [ ] Backups every 6 hours + daily
- [ ] Log rotation with 30-day retention
- [ ] Scripts deployed and tested
- [ ] Credential allowlist configured (NO wildcards!)
- [ ] Admin user account created
- [ ] Test import completed successfully
- [ ] Backup tested and verified
- [ ] External monitoring configured
- [ ] Disaster recovery plan documented
- [ ] Team trained on procedures

---

**Next Steps**: Proceed to [Migration Flow Guide](MIGRATION_FLOW.md) to understand the DEV→PROD promotion process.

