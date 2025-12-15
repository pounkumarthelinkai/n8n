#!/bin/bash
##############################################################################
# N8N HEALTH CHECK SCRIPT
#
# Purpose: Monitor n8n health and auto-restart if needed
# Usage: ./health_check.sh
#
# Typically run via cron:
#   DEV:  */30 * * * * (every 30 minutes)
#   PROD: */15 * * * * (every 15 minutes)
##############################################################################

set -euo pipefail

# Configuration
N8N_DIR="/srv/n8n"
LOG_FILE="/srv/n8n/logs/health_check.log"
ALERT_FILE="/srv/n8n/logs/health_alert.log"
HEALTH_ENDPOINT="http://localhost:5678/healthz"
MAX_RETRIES=3
RETRY_DELAY=5

# Detect environment
if [[ -f "${N8N_DIR}/.env" ]]; then
    source "${N8N_DIR}/.env"
    ENV="${N8N_ENV:-unknown}"
else
    ENV="unknown"
fi

# Get container names based on environment
if [[ "${ENV}" == "dev" ]]; then
    N8N_CONTAINER="n8n-dev"
    DB_CONTAINER="n8n-postgres-dev"
elif [[ "${ENV}" == "prod" ]] || [[ "${ENV}" == "production" ]]; then
    N8N_CONTAINER="n8n-prod"
    DB_CONTAINER="n8n-postgres-prod"
else
    # Try to detect from running containers
    if docker ps | grep -q "n8n-dev"; then
        N8N_CONTAINER="n8n-dev"
        DB_CONTAINER="n8n-postgres-dev"
        ENV="dev"
    elif docker ps | grep -q "n8n-prod"; then
        N8N_CONTAINER="n8n-prod"
        DB_CONTAINER="n8n-postgres-prod"
        ENV="prod"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Could not detect environment" >> "${LOG_FILE}"
        exit 1
    fi
fi

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

alert() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ALERT [$ENV]: $1" >> "${ALERT_FILE}"
    log "ALERT: $1"
}

# Check n8n health endpoint
check_health() {
    if curl -sf "${HEALTH_ENDPOINT}" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Check if container is running
check_container() {
    local CONTAINER=$1
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        return 0
    else
        return 1
    fi
}

# Check database connectivity
check_database() {
    if docker exec "${DB_CONTAINER}" pg_isready -U n8n -d n8n > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Restart n8n container
restart_n8n() {
    log "Attempting to restart ${N8N_CONTAINER}..."
    alert "Restarting ${N8N_CONTAINER} due to health check failure"
    
    cd "${N8N_DIR}"
    docker-compose restart n8n
    
    # Wait for n8n to start
    sleep 10
    
    # Verify restart
    if check_health; then
        log "Restart successful"
        alert "Restart successful - ${N8N_CONTAINER} is now healthy"
        return 0
    else
        log "Restart failed - n8n still unhealthy"
        alert "CRITICAL: Restart failed - ${N8N_CONTAINER} still unhealthy"
        return 1
    fi
}

# Main health check logic
main() {
    # Check if n8n container is running
    if ! check_container "${N8N_CONTAINER}"; then
        alert "CRITICAL: ${N8N_CONTAINER} container is not running"
        
        # Try to start container
        log "Attempting to start ${N8N_CONTAINER}..."
        cd "${N8N_DIR}"
        docker-compose up -d n8n
        sleep 15
        
        if check_container "${N8N_CONTAINER}"; then
            log "Container started successfully"
        else
            alert "CRITICAL: Failed to start ${N8N_CONTAINER} container"
            exit 1
        fi
    fi
    
    # Check database is running
    if ! check_container "${DB_CONTAINER}"; then
        alert "CRITICAL: ${DB_CONTAINER} container is not running"
        
        # Try to start database
        log "Attempting to start ${DB_CONTAINER}..."
        cd "${N8N_DIR}"
        docker-compose up -d postgres
        sleep 10
        
        if check_container "${DB_CONTAINER}"; then
            log "Database container started successfully"
            # Also restart n8n to reconnect
            docker-compose restart n8n
            sleep 10
        else
            alert "CRITICAL: Failed to start ${DB_CONTAINER} container"
            exit 1
        fi
    fi
    
    # Check database connectivity
    if ! check_database; then
        alert "WARNING: Database is not responding"
        log "Database connectivity check failed"
        
        # Try restarting database
        log "Attempting to restart ${DB_CONTAINER}..."
        docker restart "${DB_CONTAINER}"
        sleep 10
        
        if check_database; then
            log "Database restart successful"
            # Restart n8n to reconnect
            docker restart "${N8N_CONTAINER}"
            sleep 10
        else
            alert "CRITICAL: Database restart failed"
        fi
    fi
    
    # Check n8n health endpoint
    if check_health; then
        log "Health check PASSED - ${N8N_CONTAINER} is healthy"
        
        # Log some stats occasionally (every hour = 4 checks for 15-min interval)
        MINUTE=$(date +%M)
        if [[ "$MINUTE" == "00" ]]; then
            # Check container stats
            MEMORY=$(docker stats --no-stream --format "{{.MemUsage}}" "${N8N_CONTAINER}" | awk '{print $1}')
            CPU=$(docker stats --no-stream --format "{{.CPUPerc}}" "${N8N_CONTAINER}")
            log "Stats: Memory=${MEMORY}, CPU=${CPU}"
        fi
        
        exit 0
    else
        log "Health check FAILED - ${N8N_CONTAINER} is unhealthy"
        alert "Health check failed for ${N8N_CONTAINER}"
        
        # Retry with delay
        for i in $(seq 1 $MAX_RETRIES); do
            log "Retry attempt $i/$MAX_RETRIES..."
            sleep $RETRY_DELAY
            
            if check_health; then
                log "Health check PASSED on retry $i"
                exit 0
            fi
        done
        
        # All retries failed - restart n8n
        log "All retries failed - proceeding with restart"
        
        if restart_n8n; then
            exit 0
        else
            alert "CRITICAL: Auto-recovery failed - manual intervention required"
            exit 1
        fi
    fi
}

# Run main function
main

exit 0

