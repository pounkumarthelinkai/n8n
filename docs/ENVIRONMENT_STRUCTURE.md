# Environment Structure

Complete directory and file structure documentation for n8n CI/CD pipeline.

## 📂 Repository Structure

```
n8n-cicd-pipeline/
├── .github/
│   └── workflows/
│       └── n8n-cicd.yml              # Main CI/CD workflow
│
├── scripts/
│   ├── dev_setup.sh                  # DEV VPS installation script
│   ├── prod_setup.sh                 # PROD VPS installation script
│   ├── export_from_dev.sh            # Export workflows from DEV
│   ├── import_to_prod.sh             # Import workflows to PROD
│   ├── backup.sh                     # Database backup script
│   └── restore.sh                    # Database restore script
│
├── config/
│   ├── env.dev.example               # DEV environment template
│   ├── env.prod.example              # PROD environment template
│   └── credential_allowlist.txt      # Credential filter configuration
│
├── templates/
│   ├── docker-compose.dev.yml        # DEV Docker Compose template
│   └── docker-compose.prod.yml       # PROD Docker Compose template
│
├── docs/
│   ├── DEV_SETUP.md                  # DEV setup guide
│   ├── PROD_SETUP.md                 # PROD setup guide
│   ├── MIGRATION_FLOW.md             # Migration process
│   ├── BACKUP_RESTORE.md             # Backup procedures
│   ├── SECURITY_MODEL.md             # Security guidelines
│   └── ENVIRONMENT_STRUCTURE.md      # This file
│
├── workflows/ (optional)
│   └── *.json                        # Workflow definitions (version controlled)
│
├── .gitignore                        # Git ignore rules
├── README.md                         # Main documentation
└── LICENSE                           # License file
```

## 🖥️ VPS Directory Structure

### DEV VPS (194.238.17.118)

```
/srv/n8n/                             # Main installation directory
│
├── docker-compose.yml                # Docker Compose configuration
├── .env                              # Environment variables (SECURE!)
│
├── n8n-data/                         # n8n application data
│   ├── .n8n/                        # n8n configuration
│   │   ├── config/                  # n8n settings
│   │   ├── nodes/                   # Custom nodes
│   │   └── credentials/             # Encrypted credential cache
│   └── database.sqlite              # (Not used with Postgres)
│
├── postgres-data/                    # PostgreSQL database files
│   ├── base/                        # Database clusters
│   ├── global/                      # Global tables
│   ├── pg_wal/                      # Write-ahead logs
│   └── postgresql.conf              # Postgres configuration
│
├── logs/                            # Application logs
│   ├── export_20240101_120000.log   # Export operation logs
│   ├── backup_20240101.log          # Backup operation logs
│   ├── health_check.log             # Health monitoring logs
│   └── n8n.log                      # n8n application logs
│
├── backups/                         # Database backups
│   ├── daily/                       # Daily backups (14-day retention)
│   │   ├── n8n_dev_20240101_020000.sql.gz
│   │   ├── n8n_dev_20240101_020000.sql.gz.sha256
│   │   ├── n8n_dev_20240101_020000.sql.gz.meta
│   │   └── ...
│   ├── weekly/                      # Weekly backups (8-week retention)
│   │   └── n8n_dev_20240107_020000.sql.gz
│   └── manual/                      # Manual backups (never auto-deleted)
│       └── n8n_dev_manual_*.sql.gz
│
├── migration-temp/                  # Migration staging area
│   ├── export/                      # Export artifacts
│   │   ├── workflows_raw.json
│   │   ├── workflows_sanitized.json
│   │   ├── workflows_active_map.tsv
│   │   ├── credentials_raw.json
│   │   ├── credentials_selected.json
│   │   ├── checksums.txt
│   │   └── export_metadata.json
│   └── n8n_export_*.tar.gz          # Export packages
│
├── scripts/                         # Utility scripts
│   ├── backup.sh                    # Database backup
│   ├── restore.sh                   # Database restore
│   ├── export_from_dev.sh           # Export workflows
│   └── import_to_prod.sh            # Import workflows (not used on DEV)
│
├── health_check.sh                  # Health monitoring script
├── credential_allowlist.txt         # Credential filter configuration
└── SETUP_SUMMARY.txt                # Installation summary (SECURE!)
```

### PROD VPS (72.61.226.144)

```
/srv/n8n/                             # Main installation directory
│
├── docker-compose.yml                # Docker Compose configuration (PROD)
├── .env                              # Environment variables (SECURE!)
│                                     # DIFFERENT encryption key than DEV!
│
├── n8n-data/                         # n8n application data
│   └── .n8n/                        # n8n configuration
│       └── ...                      # (same structure as DEV)
│
├── postgres-data/                    # PostgreSQL database files
│   └── ...                          # (same structure as DEV)
│
├── logs/                            # Application logs (30-day retention)
│   ├── import_20240101_120000.log   # Import operation logs
│   ├── backup_20240101.log          # Backup operation logs (more frequent)
│   ├── health_check.log             # Health monitoring (15-min interval)
│   ├── health_alert.log             # Critical alerts
│   └── n8n.log                      # n8n application logs
│
├── backups/                         # Database backups (more frequent)
│   ├── daily/                       # Daily backups (14-day retention)
│   │   └── n8n_prod_*.sql.gz
│   ├── weekly/                      # Weekly backups (8-week retention)
│   │   └── n8n_prod_*.sql.gz
│   └── manual/                      # Manual backups
│       └── n8n_prod_manual_*.sql.gz
│
├── migration-temp/                  # Migration staging area
│   ├── import/                      # Import artifacts
│   │   ├── workflows_sanitized.json
│   │   ├── credentials_selected.json  # (deleted after import)
│   │   ├── workflows_active_map.tsv
│   │   ├── workflow_id_mapping.tsv
│   │   ├── import_report.json
│   │   └── checksums.txt
│   ├── export/                      # (optional, for testing)
│   └── n8n_export_*.tar.gz          # Received export packages
│
├── scripts/                         # Utility scripts
│   ├── backup.sh                    # Database backup (6-hour + daily)
│   ├── restore.sh                   # Database restore
│   ├── export_from_dev.sh           # (optional, for testing)
│   └── import_to_prod.sh            # Import workflows
│
├── health_check.sh                  # Health monitoring (more frequent)
├── credential_allowlist.txt         # Credential filter configuration
└── SETUP_SUMMARY.txt                # Installation summary (SECURE!)
```

## 🐳 Docker Container Structure

### Containers

```bash
# DEV Environment
n8n-dev                 # n8n application container
n8n-postgres-dev        # PostgreSQL database container

# PROD Environment
n8n-prod                # n8n application container
n8n-postgres-prod       # PostgreSQL database container
```

### Container Volumes

```yaml
# n8n container volumes
volumes:
  - ./n8n-data:/home/node/.n8n         # n8n data directory
  - ./logs:/logs                        # Log directory

# postgres container volumes
volumes:
  - ./postgres-data:/var/lib/postgresql/data   # Database files
```

### Container Networks

```yaml
# Both environments use bridge network
networks:
  n8n-network:
    driver: bridge
```

## 🗄️ Database Structure

### PostgreSQL Tables (n8n database)

```sql
-- Main tables
workflow_entity              -- Workflow definitions
credentials_entity           -- Encrypted credentials
execution_entity             -- Workflow execution history
webhook_entity               -- Webhook registrations
tag_entity                   -- Workflow tags
user                         -- n8n users
settings                     -- System settings

-- Relationship tables
workflows_tags               -- Workflow-tag relationships
shared_workflow              -- Workflow sharing/permissions
shared_credentials           -- Credential sharing/permissions
```

### Important Columns

```sql
-- workflow_entity
id                          -- Unique workflow ID (changes on import!)
name                        -- Workflow name
active                      -- Active status (true/false)
nodes                       -- JSON: workflow nodes
connections                 -- JSON: node connections
settings                    -- JSON: workflow settings
created_at                  -- Creation timestamp
updated_at                  -- Last update timestamp

-- credentials_entity
id                          -- Unique credential ID
name                        -- Credential name
type                        -- Credential type (e.g., 'httpBasicAuth')
data                        -- Encrypted credential data
created_at                  -- Creation timestamp
updated_at                  -- Last update timestamp
```

## 📄 Configuration Files

### .env File

```bash
# Location: /srv/n8n/.env
# Permissions: 600 (read/write owner only)
# Owner: root

# Critical variables:
N8N_ENCRYPTION_KEY          # DIFFERENT for DEV and PROD!
N8N_HOST                    # Hostname/domain
WEBHOOK_URL                 # Webhook base URL
POSTGRES_PASSWORD           # Database password

# MUST NOT be committed to git!
```

### docker-compose.yml

```bash
# Location: /srv/n8n/docker-compose.yml
# Permissions: 644 (read-write owner, read group/other)

# Defines:
# - Service configuration (n8n, postgres)
# - Container names
# - Port mappings
# - Volume mounts
# - Environment variables
# - Health checks
# - Restart policies
```

### credential_allowlist.txt

```bash
# Location: /srv/n8n/credential_allowlist.txt
# Permissions: 644

# Controls which credentials are exported/imported
# One pattern per line
# Supports wildcards (*, ?)
# Comments start with #
```

## 📦 Export Package Structure

```
n8n_export_20240101_120000.tar.gz
├── workflows_sanitized.json          # Workflows (all inactive)
├── credentials_selected.json         # Filtered credentials (DECRYPTED!)
├── workflows_active_map.tsv          # Active state mapping
├── checksums.txt                     # SHA256 checksums
└── export_metadata.json              # Export information
```

### File Formats

#### workflows_sanitized.json

```json
[
  {
    "name": "Customer Notification",
    "active": false,  // Always false in export
    "nodes": [...],
    "connections": {...},
    "settings": {...}
    // "id" removed (will be regenerated on import)
  },
  ...
]
```

#### credentials_selected.json

```json
[
  {
    "name": "prod-api-key",
    "type": "httpBasicAuth",
    "data": {
      "user": "admin",
      "password": "decrypted_password"  // ⚠️ DECRYPTED!
    }
  },
  ...
]
```

#### workflows_active_map.tsv

```tsv
name    active    id
Customer Notification    true    123
Order Processing    false    124
Daily Report    true    125
```

#### checksums.txt

```
a1b2c3d4e5f6...  workflows_sanitized.json
1a2b3c4d5e6f...  credentials_selected.json
9z8y7x6w5v4u...  workflows_active_map.tsv
```

#### export_metadata.json

```json
{
  "export_timestamp": "2024-01-01T12:00:00Z",
  "source_environment": "dev",
  "source_host": "dev-server",
  "workflow_count": 15,
  "credential_count": 8,
  "active_workflow_count": 10,
  "n8n_version": "1.19.4",
  "export_script_version": "1.0.0"
}
```

## 🔒 File Permissions

### Critical Files (600 - Owner Read/Write Only)

```bash
/srv/n8n/.env
/srv/n8n/SETUP_SUMMARY.txt
/srv/n8n/backups/**/*.sql.gz
```

### Secure Directories (700 - Owner Full Access Only)

```bash
/srv/n8n/migration-temp/
/srv/n8n/backups/
```

### Executable Scripts (755 - Owner RWX, Others RX)

```bash
/srv/n8n/scripts/*.sh
/srv/n8n/health_check.sh
```

### Configuration Files (644 - Owner RW, Others R)

```bash
/srv/n8n/docker-compose.yml
/srv/n8n/credential_allowlist.txt
```

## 📊 Disk Space Planning

### Expected Sizes

```bash
# Per environment
/srv/n8n/n8n-data/          # 100-500 MB (grows with workflows)
/srv/n8n/postgres-data/     # 50-200 MB (grows with executions)
/srv/n8n/logs/              # 10-50 MB (rotated regularly)
/srv/n8n/backups/daily/     # ~20 MB per backup × 14 = ~280 MB
/srv/n8n/backups/weekly/    # ~20 MB per backup × 8 = ~160 MB

# Total: ~1-2 GB per environment
```

### Monitoring

```bash
# Check disk usage
df -h /srv/n8n

# Check directory sizes
du -sh /srv/n8n/*

# Find large files
find /srv/n8n -type f -size +50M -exec ls -lh {} \;

# Clean up if needed
# - Remove old logs
# - Rotate backups manually
# - Clean old export packages
find /srv/n8n/migration-temp -name "*.tar.gz" -mtime +30 -delete
```

## 🔄 Data Flow

### Export Flow

```
n8n UI/Database
    ↓
export_from_dev.sh
    ↓
/srv/n8n/migration-temp/export/
    ├── workflows_raw.json
    ├── credentials_raw.json
    └── ...
    ↓
Package (tar.gz)
    ↓
/srv/n8n/migration-temp/n8n_export_*.tar.gz
    ↓
GitHub Actions (artifacts)
    ↓
Local developer machine (optional)
```

### Import Flow

```
GitHub Actions / Local transfer
    ↓
/srv/n8n/migration-temp/[package].tar.gz
    ↓
Extract
    ↓
/srv/n8n/migration-temp/import/
    ├── workflows_sanitized.json
    ├── credentials_selected.json
    └── ...
    ↓
import_to_prod.sh
    ↓
PostgreSQL Database (re-encrypted)
    ↓
n8n UI (workflows visible)
```

## 📝 Naming Conventions

### Files

```bash
# Backups
n8n_{environment}_{YYYYMMDD}_{HHMMSS}.sql.gz

# Logs
{operation}_{YYYYMMDD}_{HHMMSS}.log
backup_YYYYMMDD.log
export_YYYYMMDD_HHMMSS.log

# Export packages
n8n_export_{YYYYMMDD}_{HHMMSS}.tar.gz
```

### Credentials

```bash
# Environment prefix
dev-{service}-{purpose}      # DEV
prod-{service}-{purpose}     # PROD

# Examples
dev-stripe-api
prod-stripe-api
dev-database-main
prod-database-main
```

### Workflows

```bash
# Descriptive names
{purpose}-{action}
customer-notification
order-processing
daily-report
webhook-slack-alert
```

## ✅ Structure Checklist

### After DEV Setup
- [ ] /srv/n8n directory exists
- [ ] docker-compose.yml present
- [ ] .env file secured (600)
- [ ] n8n-data directory created
- [ ] postgres-data directory created
- [ ] logs directory created
- [ ] backups directory structure created
- [ ] scripts directory with all scripts
- [ ] health_check.sh present and executable
- [ ] credential_allowlist.txt present

### After PROD Setup
- [ ] Same as DEV, plus:
- [ ] Different encryption key verified
- [ ] migration-temp/import directory exists
- [ ] health_alert.log present
- [ ] More frequent backup schedule verified

---

**This structure ensures**:
- **Organized**: Everything in logical locations
- **Secure**: Sensitive files properly protected
- **Maintainable**: Easy to find and update
- **Scalable**: Can grow with your needs

**Next**: Review all documentation and start implementing!

