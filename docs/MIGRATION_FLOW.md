# Migration Flow: DEV → PROD

Complete guide to the workflow migration process from DEV to PROD environment.

## 📊 Overview

The migration flow ensures safe, controlled promotion of workflows and credentials from DEV to PROD with:

- **Automatic Export**: Triggered on git push
- **Manual Promotion**: Requires explicit approval
- **Safety Checks**: Pre-deployment backups and validation
- **Selective Activation**: Only activate workflows that were active in DEV
- **Credential Security**: Allowlist filtering and re-encryption

## 🔄 Migration Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     DEVELOPMENT ENVIRONMENT                      │
│                                                                  │
│  ┌──────────────┐                                               │
│  │   Workflows  │────┐                                          │
│  └──────────────┘    │                                          │
│                      ▼                                           │
│  ┌──────────────┐  ┌─────────────────┐                         │
│  │ Credentials  │──►│  Export Script  │                         │
│  └──────────────┘  └────────┬────────┘                         │
│                              │                                   │
│  ┌──────────────┐           │                                   │
│  │ Active State │───────────┘                                   │
│  └──────────────┘                                               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
                    ┌─────────────────────┐
                    │  Export Package     │
                    │  - Workflows        │
                    │  - Credentials      │
                    │  - Active Map       │
                    │  - Checksums        │
                    └──────────┬──────────┘
                               │
                               │ GitHub Actions
                               │ (Manual Approval)
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                    PRODUCTION ENVIRONMENT                         │
│                                                                   │
│  ┌────────────────────┐                                          │
│  │  Pre-Import Backup │                                          │
│  └─────────┬──────────┘                                          │
│            │                                                      │
│            ▼                                                      │
│  ┌────────────────────┐                                          │
│  │   Import Script    │                                          │
│  │                    │                                          │
│  │  1. Credentials    │  (Re-encrypted with PROD key)           │
│  │  2. Workflows      │  (All inactive)                         │
│  │  3. Activation     │  (Based on DEV state)                   │
│  │  4. Webhooks       │  (Toggle for registration)              │
│  └────────────────────┘                                          │
│                                                                   │
│  ┌────────────────────┐                                          │
│  │  Smoke Tests       │                                          │
│  └────────────────────┘                                          │
└──────────────────────────────────────────────────────────────────┘
```

## 📝 Step-by-Step Process

### Phase 1: Development (DEV Environment)

#### Step 1.1: Create/Modify Workflows

```bash
# On DEV VPS or via n8n UI
# Access: http://dev-n8n.yourdomain.com

# Create or modify workflows
# Set up credentials
# Test thoroughly
# Activate workflows when ready
```

#### Step 1.2: Git Push (Optional)

```bash
# If tracking workflows in git
git add workflows/
git commit -m "Add new customer notification workflow"
git push origin main

# This triggers automatic export
```

### Phase 2: Automatic Export from DEV

#### Step 2.1: Export Triggered

When code is pushed to `main`, GitHub Actions automatically:

```yaml
# Workflow: .github/workflows/n8n-cicd.yml
on:
  push:
    branches:
      - main
```

#### Step 2.2: SSH to DEV and Run Export

```bash
# Executed by GitHub Actions
ssh root@194.238.17.118 '/srv/n8n/scripts/export_from_dev.sh'
```

#### Step 2.3: Export Process

The export script performs:

```bash
# 1. Export workflows from database
SELECT * FROM workflow_entity;

# 2. Create active state mapping
name    active    id
workflow-1    true    123
workflow-2    false   124
workflow-3    true    125

# 3. Sanitize workflows (set all to inactive)
UPDATE workflow_entity SET active = false;

# 4. Export credentials (DECRYPTED)
SELECT * FROM credentials_entity;

# 5. Filter by allowlist
# Only credentials matching patterns in credential_allowlist.txt

# 6. Package artifacts
tar -czf n8n_export_20240101_120000.tar.gz \
  workflows_sanitized.json \
  credentials_selected.json \
  workflows_active_map.tsv \
  checksums.txt \
  export_metadata.json
```

#### Step 2.4: Upload Artifacts

```bash
# GitHub Actions uploads artifacts
- n8n_export_20240101_120000.tar.gz
- Export logs
- Export metadata
```

### Phase 3: Manual Promotion Decision

#### Step 3.1: Review Export

```bash
# Check GitHub Actions run
# Review:
# - Number of workflows exported
# - Number of credentials selected
# - Export logs for errors
# - Active workflow count
```

#### Step 3.2: Decide to Promote

```bash
# Go to GitHub Actions
# Run workflow: n8n CI/CD Pipeline
# Select: "Promote to Production" = true
# Click: "Run workflow"
```

### Phase 4: Production Import

#### Step 4.1: Pre-Deployment Backup

```bash
# Automatic backup before import
/srv/n8n/scripts/backup.sh

# Creates:
/srv/n8n/backups/daily/n8n_prod_20240101_115500.sql.gz
```

#### Step 4.2: Transfer Package to PROD

```bash
# GitHub Actions transfers package
scp n8n_export_20240101_120000.tar.gz \
  root@72.61.226.144:/srv/n8n/migration-temp/
```

#### Step 4.3: Import Credentials

```bash
# Credentials are imported and RE-ENCRYPTED with PROD key

# DEV encryption key: abc123...
# PROD encryption key: xyz789...  (DIFFERENT!)

# Process:
# 1. Read decrypted credentials from package
# 2. Import to PROD database
# 3. n8n re-encrypts with PROD key
# 4. Delete decrypted files
```

#### Step 4.4: Import Workflows

```bash
# Workflows imported as INACTIVE

# All workflows are imported with:
active = false

# This ensures no accidental activation
```

#### Step 4.5: Map Workflow IDs

```bash
# Create mapping: DEV name → PROD ID

# DEV:
workflow-1 → ID 123
workflow-2 → ID 124
workflow-3 → ID 125

# PROD (after import):
workflow-1 → ID 456  (NEW ID!)
workflow-2 → ID 457
workflow-3 → ID 458
```

#### Step 4.6: Selective Activation

```bash
# Read active state from export

# Active in DEV:
workflow-1: true
workflow-2: false
workflow-3: true

# Apply to PROD:
UPDATE workflow_entity SET active = true WHERE id = 456;  -- workflow-1
# workflow-2 stays inactive
UPDATE workflow_entity SET active = true WHERE id = 458;  -- workflow-3

# Result: Only workflow-1 and workflow-3 are active in PROD
```

#### Step 4.7: Webhook Registration

```bash
# For workflows with webhooks, toggle to register

# Find webhook workflows
SELECT id FROM workflow_entity 
WHERE active = true 
AND nodes LIKE '%webhook%';

# Toggle each (deactivate then reactivate)
UPDATE workflow_entity SET active = false WHERE id = 456;
-- Wait 1 second
UPDATE workflow_entity SET active = true WHERE id = 456;

# Restart n8n to ensure registration
docker restart n8n-prod
```

### Phase 5: Verification

#### Step 5.1: Smoke Tests

```bash
# GitHub Actions runs tests

# 1. Health check
curl https://n8n.yourdomain.com/healthz

# 2. Database counts
SELECT COUNT(*) FROM workflow_entity;
SELECT COUNT(*) FROM workflow_entity WHERE active = true;
SELECT COUNT(*) FROM credentials_entity;

# 3. Container status
docker ps | grep n8n-prod
docker ps | grep n8n-postgres-prod
```

#### Step 5.2: Manual Verification

```bash
# Access n8n UI
https://n8n.yourdomain.com

# Verify:
# - Workflows appear
# - Correct workflows are active
# - Credentials are available
# - Webhooks are working
```

### Phase 6: Cleanup

#### Step 6.1: Remove Sensitive Files

```bash
# Automatically done by import script

# Delete decrypted credentials
rm -f /srv/n8n/migration-temp/import/credentials_selected.json

# Keep audit trail
# - Export package (encrypted)
# - Import logs
# - Workflow mappings
```

#### Step 6.2: Rotate Old Packages

```bash
# Automatic cleanup of packages older than 7 days
find /srv/n8n/migration-temp -name "*.tar.gz" -mtime +7 -delete
```

## 🔒 Security Considerations

### 1. Credential Handling

```bash
# DEV Export:
# - Credentials decrypted with DEV key
# - Filtered by allowlist
# - Stored temporarily in package

# Transfer:
# - Package transferred over SSH
# - Encrypted channel

# PROD Import:
# - Credentials imported to PROD
# - Re-encrypted with PROD key (DIFFERENT!)
# - Decrypted files deleted immediately
```

### 2. Encryption Key Separation

```plaintext
DEV Key:  aBcD1234eFgH5678...
PROD Key: xYzW9876vUtS5432...  ← MUST BE DIFFERENT!

Why?
- Prevents DEV credentials from working in PROD
- Isolates environments
- Reduces blast radius if DEV is compromised
```

### 3. Credential Allowlist

```bash
# /srv/n8n/credential_allowlist.txt

# Bad (allows everything):
*

# Good (specific):
production-database
prod-api-key
slack-webhook-prod
smtp-server

# Never export test/dev credentials!
```

### 4. Workflow Activation Control

```bash
# Problem: Accidentally activating ALL workflows
# Solution: Selective activation based on DEV state

# DEV active state is preserved
# Only those workflows are activated in PROD
# Others remain inactive for manual review
```

## 📊 Migration Scenarios

### Scenario 1: New Workflow

```bash
# 1. Create in DEV
# 2. Test thoroughly
# 3. Activate in DEV
# 4. Git push (triggers export)
# 5. Review export
# 6. Promote to PROD (manual)
# 7. Workflow imported and activated
```

### Scenario 2: Workflow Update

```bash
# 1. Modify in DEV
# 2. Test changes
# 3. Keep activated (or activate)
# 4. Export (on push)
# 5. Promote to PROD
# 6. Workflow updated in PROD
# 7. Active state preserved
```

### Scenario 3: New Credential

```bash
# 1. Add credential in DEV
# 2. Add to allowlist: /srv/n8n/credential_allowlist.txt
# 3. Add same credential in PROD (manually or via export)
# 4. Export will include it
# 5. Import will re-encrypt for PROD
```

### Scenario 4: Deactivating Workflow

```bash
# 1. Deactivate in DEV
# 2. Export (workflow exported as inactive)
# 3. Promote to PROD
# 4. Workflow in PROD is deactivated
```

### Scenario 5: Emergency Rollback

```bash
# If import fails or causes issues:

# 1. SSH to PROD
ssh root@72.61.226.144

# 2. Find pre-import backup
ls -lht /srv/n8n/backups/daily/ | head

# 3. Restore
/srv/n8n/scripts/restore.sh /srv/n8n/backups/daily/[backup].sql.gz

# 4. Restart n8n
docker restart n8n-prod

# 5. Verify
curl https://n8n.yourdomain.com/healthz
```

## 🧪 Testing the Pipeline

### Test 1: Simple Workflow Migration

```bash
# 1. Create simple workflow in DEV
# - HTTP Request node
# - No credentials needed
# - Activate

# 2. Run export manually
ssh root@194.238.17.118
/srv/n8n/scripts/export_from_dev.sh

# 3. Check export
ls -lh /srv/n8n/migration-temp/export/
cat /srv/n8n/migration-temp/export/export_metadata.json

# 4. Transfer to PROD
scp /srv/n8n/migration-temp/n8n_export_*.tar.gz root@72.61.226.144:/srv/n8n/migration-temp/

# 5. Import to PROD
ssh root@72.61.226.144
/srv/n8n/scripts/import_to_prod.sh /srv/n8n/migration-temp/[package].tar.gz

# 6. Verify in PROD UI
# Should see workflow, activated
```

### Test 2: Credential Migration

```bash
# 1. Add test credential in DEV
# - Type: Generic Credential Auth
# - Name: test-credential-prod

# 2. Update allowlist
echo "test-credential-prod" >> /srv/n8n/credential_allowlist.txt

# 3. Export
/srv/n8n/scripts/export_from_dev.sh

# 4. Check credentials were filtered
cat /srv/n8n/migration-temp/export/credentials_selected.json

# 5. Import to PROD
# ... (same as Test 1)

# 6. Verify credential exists in PROD
# Check in UI under Credentials
```

### Test 3: Selective Activation

```bash
# 1. In DEV:
#    - Workflow A: Active
#    - Workflow B: Inactive
#    - Workflow C: Active

# 2. Export
/srv/n8n/scripts/export_from_dev.sh

# 3. Check active map
cat /srv/n8n/migration-temp/export/workflows_active_map.tsv

# 4. Import to PROD
# ... (standard import)

# 5. Verify in PROD:
#    - Workflow A: Should be Active
#    - Workflow B: Should be Inactive
#    - Workflow C: Should be Active
```

## 📈 Best Practices

### 1. Always Test in DEV First

- Create workflows in DEV
- Test thoroughly
- Activate only when ready
- Then promote to PROD

### 2. Use Meaningful Names

```bash
# Good:
customer-notification-workflow
order-processing-prod
webhook-slack-alerts

# Bad:
workflow-1
test
my-workflow
```

### 3. Review Before Promotion

- Check export logs
- Review active workflows list
- Verify credentials are allowlisted
- Check for any errors

### 4. Monitor After Deployment

- Check n8n UI in PROD
- Monitor logs for errors
- Test webhook endpoints
- Verify executions are running

### 5. Maintain Allowlist

```bash
# Review regularly
cat /srv/n8n/credential_allowlist.txt

# Remove unused credentials
# Add new production credentials
# Never use wildcards in production
```

## 🆘 Troubleshooting

### Issue: Export Shows 0 Workflows

```bash
# Check DEV database
docker exec n8n-postgres-dev psql -U n8n -d n8n -c \
  "SELECT COUNT(*) FROM workflow_entity;"

# If 0, create workflows in DEV first
```

### Issue: Credentials Not Exported

```bash
# Check allowlist
cat /srv/n8n/credential_allowlist.txt

# Ensure credential names match patterns
# Check export log for filtering
cat /srv/n8n/logs/export_*.log | grep credential
```

### Issue: Import Fails with "Encryption Key Error"

```bash
# This is EXPECTED if using same key
# DEV and PROD MUST have different keys

# Check keys are different:
ssh root@194.238.17.118 'grep N8N_ENCRYPTION_KEY /srv/n8n/.env'
ssh root@72.61.226.144 'grep N8N_ENCRYPTION_KEY /srv/n8n/.env'

# They should be DIFFERENT
```

### Issue: Workflows Not Activated in PROD

```bash
# Check active map
cat /srv/n8n/migration-temp/import/workflows_active_map.tsv

# Check import log
cat /srv/n8n/logs/import_*.log | grep -i active

# Manually activate if needed
docker exec n8n-postgres-prod psql -U n8n -d n8n -c \
  "UPDATE workflow_entity SET active = true WHERE name = 'my-workflow';"
```

### Issue: Webhooks Not Working

```bash
# Restart n8n to re-register
docker restart n8n-prod

# Check webhook URL in environment
grep WEBHOOK_URL /srv/n8n/.env

# Should be: https://n8n.yourdomain.com

# Test webhook
curl -X POST https://n8n.yourdomain.com/webhook-test/[webhook-id]
```

## ✅ Migration Checklist

### Before Migration
- [ ] Workflows tested in DEV
- [ ] Credentials allowlisted
- [ ] Export runs successfully
- [ ] Export package validated
- [ ] PROD backup exists

### During Migration
- [ ] Pre-deployment backup created
- [ ] Package transferred to PROD
- [ ] Import runs without errors
- [ ] Smoke tests pass

### After Migration
- [ ] Workflows visible in PROD UI
- [ ] Correct workflows activated
- [ ] Credentials available
- [ ] Webhooks working
- [ ] No errors in logs
- [ ] Sensitive files cleaned up

---

**Next**: Read [Backup & Restore Guide](BACKUP_RESTORE.md) for disaster recovery procedures.

