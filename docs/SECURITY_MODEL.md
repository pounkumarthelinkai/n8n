# Security Model

Comprehensive security guidelines for your n8n CI/CD pipeline.

## 🔒 Security Overview

This n8n CI/CD pipeline implements multiple layers of security:

1. **Environment Isolation**: Separate DEV and PROD environments
2. **Encryption Key Separation**: Different keys for each environment
3. **Credential Allowlisting**: Controlled credential migration
4. **Secure Transfer**: SSH-encrypted data transfer
5. **Access Control**: Role-based VPS access
6. **Audit Trail**: Comprehensive logging
7. **Backup Security**: Encrypted and rotated backups

## 🔑 Encryption Key Management

### Critical Rule: DIFFERENT Keys for DEV and PROD

```bash
# ❌ WRONG - Same key
DEV:  aBcD1234eFgH5678...
PROD: aBcD1234eFgH5678...  ← INSECURE!

# ✅ CORRECT - Different keys
DEV:  aBcD1234eFgH5678...
PROD: xYzW9876vUtS5432...  ← SECURE!
```

### Why Different Keys?

1. **Environment Isolation**: DEV compromise doesn't affect PROD
2. **Credential Protection**: DEV credentials can't decrypt PROD data
3. **Compliance**: Industry best practice (SOC 2, ISO 27001)
4. **Blast Radius Reduction**: Limits damage from key exposure

### Key Generation

```bash
# Generate strong encryption key (32 bytes, base64 encoded)
openssl rand -base64 32

# Output example:
# kX9mP2nQ5rS8tU1vW3xY6zA7bC4dE0fF1gH2iJ3kL4mN==

# IMPORTANT: Save this securely!
```

### Key Storage

```bash
# ✅ DO:
# - Store in password manager (1Password, LastPass, Bitwarden)
# - Save in encrypted file offline
# - Document location in secure runbook
# - Keep backup in different location

# ❌ DON'T:
# - Commit to git
# - Share via email/Slack
# - Store in plain text
# - Reuse across environments
```

### Key Rotation (Advanced)

```bash
# If key is compromised, you must:

# 1. Generate new key
NEW_KEY=$(openssl rand -base64 32)

# 2. Export all credentials (decrypted)
docker exec n8n-prod n8n export:credentials --all --decrypted --output=/tmp/creds.json

# 3. Update encryption key
sed -i "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=${NEW_KEY}/" /srv/n8n/.env

# 4. Restart n8n
docker restart n8n-prod

# 5. Re-import credentials (will be re-encrypted with new key)
docker exec n8n-prod n8n import:credentials --input=/tmp/creds.json

# 6. Delete decrypted file
docker exec n8n-prod rm /tmp/creds.json

# 7. Update GitHub Secrets
# Update PROD_ENCRYPTION_KEY in GitHub repository secrets
```

## 🎫 Credential Management

### Credential Allowlist

The allowlist controls which credentials are migrated from DEV to PROD.

#### Location

```bash
/srv/n8n/credential_allowlist.txt
```

#### Format

```bash
# Comments start with #
# One credential name pattern per line
# Wildcards: * (any characters), ? (single character)

# Exact match
production-database

# Prefix match
prod-*

# Suffix match
*-production

# Contains
*-api-*

# AVOID: Allow all (insecure)
*
```

#### Example: Secure Allowlist

```bash
# Production Database
production-postgres
production-mysql

# Production APIs
prod-api-stripe
prod-api-sendgrid
prod-api-twilio

# Production Services
slack-webhook-prod
smtp-server-prod

# NEVER include:
# - test-*
# - dev-*
# - *-dev
# - dummy-*
```

### Credential Security Best Practices

#### 1. Use Credential References (Not Hardcoded Values)

```json
// ❌ BAD - Hardcoded API key in workflow
{
  "node": "HTTP Request",
  "parameters": {
    "url": "https://api.example.com",
    "headers": {
      "Authorization": "Bearer sk_live_abc123..."
    }
  }
}

// ✅ GOOD - Reference to credential
{
  "node": "HTTP Request",
  "parameters": {
    "url": "https://api.example.com",
    "authentication": "genericCredentialType",
    "genericAuthType": "httpHeaderAuth",
    "credential": "prod-api-key"
  }
}
```

#### 2. Separate DEV and PROD Credentials

```bash
# DEV Credentials (use test/sandbox accounts)
dev-stripe-api          → sk_test_...
dev-sendgrid-api        → SG.test...
dev-database            → localhost:5432

# PROD Credentials (use production accounts)
prod-stripe-api         → sk_live_...
prod-sendgrid-api       → SG.prod...
prod-database           → prod-db.example.com:5432
```

#### 3. Minimal Permissions

```bash
# Database credentials
# ❌ BAD: Full admin access
user: admin, permissions: ALL

# ✅ GOOD: Limited access
user: n8n_app, permissions: SELECT, INSERT, UPDATE (specific tables only)
```

#### 4. Regular Audit

```bash
# Monthly: Review all credentials
docker exec n8n-postgres-prod psql -U n8n -d n8n -c \
  "SELECT name, type, created_at FROM credentials_entity ORDER BY created_at DESC;"

# Check for:
# - Unused credentials
# - Test credentials in PROD
# - Overly permissive credentials
# - Old/stale credentials
```

## 🔐 Access Control

### VPS Access

#### SSH Key Management

```bash
# Generate dedicated key for automation
ssh-keygen -t ed25519 -f ~/.ssh/n8n_deploy_key -C "n8n-deploy"

# Set restrictive permissions
chmod 600 ~/.ssh/n8n_deploy_key
chmod 644 ~/.ssh/n8n_deploy_key.pub

# Add to VPS
ssh-copy-id -i ~/.ssh/n8n_deploy_key root@[VPS-IP]
```

#### Limit Root Access

```bash
# Create dedicated user for n8n operations
adduser n8nadmin
usermod -aG docker n8nadmin

# Grant sudo for specific commands only
cat > /etc/sudoers.d/n8nadmin << 'EOF'
n8nadmin ALL=(ALL) NOPASSWD: /usr/bin/docker
n8nadmin ALL=(ALL) NOPASSWD: /srv/n8n/scripts/*.sh
EOF

# Use this user instead of root
ssh n8nadmin@[VPS-IP]
```

#### Disable Password Authentication

```bash
# Edit SSH config
nano /etc/ssh/sshd_config

# Set:
PasswordAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes

# Restart SSH
systemctl restart sshd
```

### n8n User Management

#### Production n8n Access

```bash
# Create separate accounts for team members
# NEVER share accounts

# Use email-based accounts
admin@company.com         → Admin role
dev1@company.com          → Member role
dev2@company.com          → Member role

# Set up SSO if possible (enterprise plan)
# Enables centralized access control
```

#### Audit Logging

```bash
# Enable n8n audit logging (enterprise feature)
# Or monitor execution logs

# Check who executed workflows
docker exec n8n-postgres-prod psql -U n8n -d n8n -c \
  "SELECT 
     w.name as workflow,
     e.finished_at,
     e.mode,
     e.started_at
   FROM execution_entity e
   JOIN workflow_entity w ON e.workflow_id = w.id
   ORDER BY e.finished_at DESC
   LIMIT 20;"
```

## 🛡️ Network Security

### Firewall Configuration

```bash
# DEV VPS (More Permissive)
ufw allow 22/tcp          # SSH
ufw allow 5678/tcp        # n8n (direct access for testing)

# PROD VPS (More Restrictive)
ufw allow 22/tcp          # SSH (consider limiting to specific IPs)
ufw allow 80/tcp          # HTTP (for SSL verification)
ufw allow 443/tcp         # HTTPS only
ufw deny 5678/tcp         # Block direct n8n access (use Nginx proxy)
```

### IP Whitelisting (Optional)

```bash
# Limit SSH access to specific IPs
ufw delete allow 22/tcp
ufw allow from 1.2.3.4 to any port 22 proto tcp
ufw allow from 5.6.7.8 to any port 22 proto tcp

# Or limit SSH to VPN only
ufw allow from 10.0.0.0/24 to any port 22 proto tcp
```

### SSL/TLS Configuration

```bash
# Use strong SSL configuration
# Already configured in PROD setup, but verify:

# Test SSL strength
nmap --script ssl-enum-ciphers -p 443 n8n.yourdomain.com

# Or use online tools:
# - SSL Labs: https://www.ssllabs.com/ssltest/
# - Check certificate expiration
echo | openssl s_client -servername n8n.yourdomain.com \
  -connect n8n.yourdomain.com:443 2>/dev/null | \
  openssl x509 -noout -dates
```

## 📝 Audit & Logging

### Log Security

```bash
# Secure log files
chmod 640 /srv/n8n/logs/*.log
chown root:adm /srv/n8n/logs/*.log

# Never log sensitive data
# Review logs for accidentally logged secrets:
grep -ri "password\|api_key\|secret\|token" /srv/n8n/logs/ || echo "✓ Clean"
```

### Export/Import Audit Trail

```bash
# Every export/import creates logs
/srv/n8n/logs/export_YYYYMMDD_HHMMSS.log
/srv/n8n/logs/import_YYYYMMDD_HHMMSS.log

# These contain:
# - Timestamp
# - What was exported/imported
# - Workflow counts
# - Credential counts
# - Success/failure status

# Review regularly
tail -f /srv/n8n/logs/import_*.log
```

### Backup Audit

```bash
# Track all backup operations
/srv/n8n/logs/backup_YYYYMMDD.log

# Contains:
# - Backup timestamp
# - Backup location
# - Backup size
# - Checksum
# - Success/failure
```

## 🚨 Security Incidents

### Scenario 1: Encryption Key Compromised

```bash
# IMMEDIATE ACTIONS:

# 1. Rotate encryption key (see Key Rotation above)
# 2. Audit all credential access
# 3. Change all production credentials
# 4. Review logs for unauthorized access
# 5. Notify security team
# 6. Document incident
```

### Scenario 2: Unauthorized VPS Access

```bash
# IMMEDIATE ACTIONS:

# 1. Revoke compromised SSH keys
ssh-keygen -R [VPS-IP]
# Remove public key from ~/.ssh/authorized_keys on VPS

# 2. Create new SSH keys
ssh-keygen -t ed25519 -f ~/.ssh/n8n_new_key

# 3. Audit recent activity
last -10
history

# 4. Check for unauthorized changes
docker ps -a
crontab -l
ls -la /srv/n8n/scripts/

# 5. Restore from clean backup if needed
# 6. Update all secrets in GitHub Actions
# 7. Notify team
```

### Scenario 3: Credential Leak

```bash
# IMMEDIATE ACTIONS:

# 1. Identify leaked credential
# 2. Revoke/rotate the credential immediately
# 3. Check usage in logs
docker exec n8n-postgres-prod psql -U n8n -d n8n -c \
  "SELECT name, type FROM credentials_entity WHERE name = '[leaked-cred]';"

# 4. Replace in all workflows using it
# 5. Re-export from DEV (with new credential)
# 6. Re-import to PROD
# 7. Test affected workflows
# 8. Document incident
```

## ✅ Security Checklist

### Initial Setup
- [ ] Different encryption keys for DEV and PROD
- [ ] Strong passwords (32+ characters)
- [ ] SSH key-based authentication only
- [ ] Firewall configured
- [ ] SSL/HTTPS enabled (PROD)
- [ ] File permissions secured
- [ ] Credential allowlist configured

### Ongoing (Weekly)
- [ ] Review recent exports/imports
- [ ] Check health check logs
- [ ] Monitor failed login attempts
- [ ] Verify SSL certificate validity
- [ ] Check for software updates

### Monthly
- [ ] Audit credentials
- [ ] Review user access
- [ ] Check firewall rules
- [ ] Review logs for anomalies
- [ ] Test backup security
- [ ] Update encryption keys if needed

### Quarterly
- [ ] Full security audit
- [ ] Penetration testing
- [ ] Disaster recovery drill
- [ ] Update security documentation
- [ ] Team security training

## 🔍 Security Monitoring

### Set Up Monitoring

```bash
# Monitor failed SSH attempts
cat > /srv/n8n/scripts/security_monitor.sh << 'EOF'
#!/bin/bash
# Security monitoring script

LOG_FILE="/srv/n8n/logs/security_monitor.log"

echo "=== Security Check $(date) ===" >> $LOG_FILE

# Failed SSH attempts
echo "Failed SSH attempts:" >> $LOG_FILE
grep "Failed password" /var/log/auth.log | tail -5 >> $LOG_FILE

# Docker events
echo "Recent Docker events:" >> $LOG_FILE
docker events --since 1h --filter 'type=container' >> $LOG_FILE 2>&1

# File changes in sensitive directories
echo "File changes:" >> $LOG_FILE
find /srv/n8n/scripts -type f -mtime -1 >> $LOG_FILE

echo "====================" >> $LOG_FILE
EOF

chmod +x /srv/n8n/scripts/security_monitor.sh

# Run daily
echo "0 1 * * * /srv/n8n/scripts/security_monitor.sh" | crontab -a
```

## 📚 Security Resources

### External Tools

- **SSL Testing**: https://www.ssllabs.com/ssltest/
- **Security Headers**: https://securityheaders.com/
- **Password Generator**: https://1password.com/password-generator/
- **OWASP Guidelines**: https://owasp.org/

### Best Practices

1. **Defense in Depth**: Multiple security layers
2. **Least Privilege**: Minimum necessary permissions
3. **Separation of Duties**: Different people for different roles
4. **Regular Audits**: Weekly/monthly security reviews
5. **Incident Response Plan**: Document what to do when things go wrong

## ⚠️ Common Security Mistakes

### 1. Using Same Encryption Key

```bash
# ❌ WRONG
DEV_KEY=abc123
PROD_KEY=abc123

# ✅ CORRECT
DEV_KEY=abc123
PROD_KEY=xyz789
```

### 2. Wildcards in Credential Allowlist

```bash
# ❌ WRONG (allows everything)
*

# ✅ CORRECT (specific)
prod-api-key
production-database
```

### 3. Hardcoded Secrets

```bash
# ❌ WRONG
{
  "password": "mySecretPass123"
}

# ✅ CORRECT
{
  "credentials": "{{$credentials.myCredential}}"
}
```

### 4. Weak Passwords

```bash
# ❌ WRONG
password123
admin2024

# ✅ CORRECT
kX9mP2nQ5rS8tU1vW3xY6zA7bC4dE0fF
```

### 5. No Backup Testing

```bash
# ❌ WRONG: Never test restores
# Backups exist but never verified

# ✅ CORRECT: Regular restore tests
# Monthly: Test restore procedure
# Quarterly: Full disaster recovery drill
```

---

**Remember**: Security is not a one-time setup, it's an ongoing process. Regular reviews and updates are essential.

**Next**: Read [Environment Structure](ENVIRONMENT_STRUCTURE.md) for directory layout details.

