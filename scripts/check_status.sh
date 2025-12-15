#!/bin/bash
##############################################################################
# N8N STATUS CHECK SCRIPT
#
# Purpose: Display comprehensive status of n8n installation
# Usage: ./check_status.sh
##############################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
N8N_DIR="/srv/n8n"

# Detect environment
if [[ -f "${N8N_DIR}/.env" ]]; then
    source "${N8N_DIR}/.env"
    ENV="${N8N_ENV:-unknown}"
else
    ENV="unknown"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  n8n Status Report${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Environment
echo -e "${GREEN}Environment:${NC} ${ENV}"
echo -e "${GREEN}Host:${NC} $(hostname)"
echo -e "${GREEN}Date:${NC} $(date)"
echo ""

# Container Status
echo -e "${BLUE}=== Container Status ===${NC}"
if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "n8n\|postgres"; then
    echo -e "${GREEN}✓${NC} Containers running"
else
    echo -e "${RED}✗${NC} No containers found"
fi
echo ""

# Health Check
echo -e "${BLUE}=== Health Check ===${NC}"
if curl -sf http://localhost:5678/healthz > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} n8n is healthy"
else
    echo -e "${RED}✗${NC} n8n health check failed"
fi
echo ""

# Database Status
echo -e "${BLUE}=== Database Status ===${NC}"
if [[ "${ENV}" == "dev" ]]; then
    DB_CONTAINER="n8n-postgres-dev"
elif [[ "${ENV}" == "prod" ]] || [[ "${ENV}" == "production" ]]; then
    DB_CONTAINER="n8n-postgres-prod"
else
    DB_CONTAINER="n8n-postgres-dev"
fi

if docker exec "${DB_CONTAINER}" pg_isready -U n8n -d n8n > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Database is ready"
    
    # Get workflow count
    WORKFLOW_COUNT=$(docker exec "${DB_CONTAINER}" psql -U n8n -d n8n -t -c \
        "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null | tr -d ' ' || echo "0")
    echo "  Workflows: ${WORKFLOW_COUNT}"
    
    # Get active workflow count
    ACTIVE_COUNT=$(docker exec "${DB_CONTAINER}" psql -U n8n -d n8n -t -c \
        "SELECT COUNT(*) FROM workflow_entity WHERE active = true;" 2>/dev/null | tr -d ' ' || echo "0")
    echo "  Active: ${ACTIVE_COUNT}"
    
    # Get credential count
    CRED_COUNT=$(docker exec "${DB_CONTAINER}" psql -U n8n -d n8n -t -c \
        "SELECT COUNT(*) FROM credentials_entity;" 2>/dev/null | tr -d ' ' || echo "0")
    echo "  Credentials: ${CRED_COUNT}"
    
    # Get recent execution count
    EXEC_COUNT=$(docker exec "${DB_CONTAINER}" psql -U n8n -d n8n -t -c \
        "SELECT COUNT(*) FROM execution_entity WHERE finished_at > NOW() - INTERVAL '24 hours';" \
        2>/dev/null | tr -d ' ' || echo "0")
    echo "  Executions (24h): ${EXEC_COUNT}"
else
    echo -e "${RED}✗${NC} Database is not responding"
fi
echo ""

# Resource Usage
echo -e "${BLUE}=== Resource Usage ===${NC}"
if [[ "${ENV}" == "dev" ]]; then
    N8N_CONTAINER="n8n-dev"
elif [[ "${ENV}" == "prod" ]] || [[ "${ENV}" == "production" ]]; then
    N8N_CONTAINER="n8n-prod"
else
    N8N_CONTAINER="n8n-dev"
fi

if docker ps | grep -q "${N8N_CONTAINER}"; then
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" \
        "${N8N_CONTAINER}" "${DB_CONTAINER}" 2>/dev/null || echo "  Stats unavailable"
else
    echo "  Container not running"
fi
echo ""

# Disk Usage
echo -e "${BLUE}=== Disk Usage ===${NC}"
if [[ -d "${N8N_DIR}" ]]; then
    df -h "${N8N_DIR}" | tail -1
    echo ""
    echo "  Directory Sizes:"
    du -sh "${N8N_DIR}"/{n8n-data,postgres-data,logs,backups} 2>/dev/null | sed 's/^/    /'
else
    echo "  n8n directory not found"
fi
echo ""

# Backup Status
echo -e "${BLUE}=== Backup Status ===${NC}"
if [[ -d "${N8N_DIR}/backups/daily" ]]; then
    LATEST_BACKUP=$(ls -t "${N8N_DIR}/backups/daily/"*.sql.gz 2>/dev/null | head -1)
    if [[ -n "${LATEST_BACKUP}" ]]; then
        BACKUP_AGE=$(stat -c %Y "${LATEST_BACKUP}")
        CURRENT_TIME=$(date +%s)
        AGE_HOURS=$(( (CURRENT_TIME - BACKUP_AGE) / 3600 ))
        
        echo "  Latest backup: $(basename ${LATEST_BACKUP})"
        echo "  Age: ${AGE_HOURS} hours ago"
        echo "  Size: $(du -h ${LATEST_BACKUP} | cut -f1)"
        
        if [[ ${AGE_HOURS} -gt 25 ]]; then
            echo -e "  ${RED}✗${NC} Backup is older than 24 hours!"
        else
            echo -e "  ${GREEN}✓${NC} Backup is recent"
        fi
        
        # Count backups
        DAILY_COUNT=$(ls -1 "${N8N_DIR}/backups/daily/"*.sql.gz 2>/dev/null | wc -l)
        WEEKLY_COUNT=$(ls -1 "${N8N_DIR}/backups/weekly/"*.sql.gz 2>/dev/null | wc -l)
        echo "  Daily backups: ${DAILY_COUNT}"
        echo "  Weekly backups: ${WEEKLY_COUNT}"
    else
        echo -e "  ${YELLOW}⚠${NC} No backups found"
    fi
else
    echo "  Backup directory not found"
fi
echo ""

# Recent Logs
echo -e "${BLUE}=== Recent Activity ===${NC}"
if [[ -f "${N8N_DIR}/logs/health_check.log" ]]; then
    echo "  Recent health checks:"
    tail -3 "${N8N_DIR}/logs/health_check.log" 2>/dev/null | sed 's/^/    /' || echo "    No health check logs"
fi

if [[ -f "${N8N_DIR}/logs/health_alert.log" ]]; then
    ALERT_COUNT=$(wc -l < "${N8N_DIR}/logs/health_alert.log" 2>/dev/null || echo "0")
    if [[ ${ALERT_COUNT} -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}⚠${NC} Health Alerts: ${ALERT_COUNT} total"
        echo "  Recent alerts:"
        tail -3 "${N8N_DIR}/logs/health_alert.log" 2>/dev/null | sed 's/^/    /'
    fi
fi
echo ""

# Cron Jobs
echo -e "${BLUE}=== Scheduled Tasks ===${NC}"
CRON_JOBS=$(crontab -l 2>/dev/null | grep -v "^#" | grep "n8n\|backup\|health" || echo "")
if [[ -n "${CRON_JOBS}" ]]; then
    echo "${CRON_JOBS}" | sed 's/^/  /'
else
    echo "  No scheduled tasks found"
fi
echo ""

# Configuration
echo -e "${BLUE}=== Configuration ===${NC}"
if [[ -f "${N8N_DIR}/.env" ]]; then
    echo "  N8N_HOST: ${N8N_HOST:-not set}"
    echo "  WEBHOOK_URL: ${WEBHOOK_URL:-not set}"
    echo "  N8N_PROTOCOL: ${N8N_PROTOCOL:-not set}"
    echo "  DB_TYPE: ${DB_TYPE:-not set}"
    echo "  Encryption key: $(if [[ -n "${N8N_ENCRYPTION_KEY:-}" ]]; then echo "Set (${#N8N_ENCRYPTION_KEY} chars)"; else echo "Not set"; fi)"
else
    echo "  .env file not found"
fi
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  End of Status Report${NC}"
echo -e "${BLUE}========================================${NC}"

