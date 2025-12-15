#!/bin/bash
##############################################################################
# DEPLOY SCRIPTS - n8n CI/CD Pipeline
#
# Purpose: Deploy updated scripts to both DEV and PROD VPS instances
# Usage: ./deploy_scripts.sh [--dev-only] [--prod-only]
#
# Workflow:
#   1. Backup existing scripts on both VPS
#   2. Deploy updated scripts to DEV VPS
#   3. Deploy updated scripts to PROD VPS
#   4. Set executable permissions
#   5. Verify deployment
#
# Security:
#   - Creates backups before overwriting
#   - Verifies file transfers
#   - Sets proper permissions
##############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# VPS Configuration (should match GitHub Actions)
DEV_VPS_HOST="${DEV_VPS_HOST:-194.238.17.118}"
PROD_VPS_HOST="${PROD_VPS_HOST:-72.61.226.144}"
VPS_USER="${VPS_USER:-root}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/github_deploy_key}"

# Flags
DEPLOY_DEV=true
DEPLOY_PROD=true

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dev-only)
                DEPLOY_DEV=true
                DEPLOY_PROD=false
                shift
                ;;
            --prod-only)
                DEPLOY_DEV=false
                DEPLOY_PROD=true
                shift
                ;;
            --ssh-key)
                SSH_KEY="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                echo "Usage: $0 [--dev-only] [--prod-only] [--ssh-key <path>]"
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check SSH key exists
    if [[ ! -f "${SSH_KEY}" ]]; then
        error "SSH key not found: ${SSH_KEY}"
        error "Please set SSH_KEY environment variable or use --ssh-key option"
        exit 1
    fi
    
    # Check scripts exist
    local scripts=("export_from_dev.sh" "import_to_prod.sh")
    for script in "${scripts[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
            error "Script not found: ${SCRIPT_DIR}/${script}"
            exit 1
        fi
    done
    
    log "Prerequisites check passed"
}

# Deploy scripts to VPS
deploy_to_vps() {
    local vps_host="$1"
    local vps_name="$2"
    
    log "Deploying scripts to ${vps_name} (${vps_host})..."
    
    # Test SSH connection
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "${VPS_USER}@${vps_host}" "echo 'SSH connection successful'" || {
        error "Failed to connect to ${vps_name} (${vps_host})"
        return 1
    }
    
    # Create backup directory
    ssh -i "${SSH_KEY}" "${VPS_USER}@${vps_host}" << 'ENDSSH'
        mkdir -p /srv/n8n/scripts/backups
        BACKUP_DIR="/srv/n8n/scripts/backups/backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${BACKUP_DIR}"
        echo "${BACKUP_DIR}"
ENDSSH
    
    local backup_dir=$(ssh -i "${SSH_KEY}" "${VPS_USER}@${vps_host}" \
        "mkdir -p /srv/n8n/scripts/backups && echo /srv/n8n/scripts/backups/backup_\$(date +%Y%m%d_%H%M%S) && mkdir -p /srv/n8n/scripts/backups/backup_\$(date +%Y%m%d_%H%M%S)")
    
    # Backup existing scripts
    log "Backing up existing scripts..."
    ssh -i "${SSH_KEY}" "${VPS_USER}@${vps_host}" << ENDSSH
        BACKUP_DIR="${backup_dir}"
        mkdir -p "\${BACKUP_DIR}"
        if [ -f /srv/n8n/scripts/export_from_dev.sh ]; then
            cp /srv/n8n/scripts/export_from_dev.sh "\${BACKUP_DIR}/"
        fi
        if [ -f /srv/n8n/scripts/import_to_prod.sh ]; then
            cp /srv/n8n/scripts/import_to_prod.sh "\${BACKUP_DIR}/"
        fi
        echo "Backup created at: \${BACKUP_DIR}"
ENDSSH
    
    # Create scripts directory if it doesn't exist
    ssh -i "${SSH_KEY}" "${VPS_USER}@${vps_host}" "mkdir -p /srv/n8n/scripts"
    
    # Deploy scripts
    log "Deploying updated scripts..."
    scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${SCRIPT_DIR}/export_from_dev.sh" \
        "${SCRIPT_DIR}/import_to_prod.sh" \
        "${VPS_USER}@${vps_host}:/srv/n8n/scripts/" || {
        error "Failed to deploy scripts to ${vps_name}"
        return 1
    }
    
    # Set executable permissions
    log "Setting executable permissions..."
    ssh -i "${SSH_KEY}" "${VPS_USER}@${vps_host}" << 'ENDSSH'
        chmod +x /srv/n8n/scripts/export_from_dev.sh
        chmod +x /srv/n8n/scripts/import_to_prod.sh
        echo "Permissions set"
ENDSSH
    
    # Verify deployment
    log "Verifying deployment..."
    ssh -i "${SSH_KEY}" "${VPS_USER}@${vps_host}" << 'ENDSSH'
        if [ ! -f /srv/n8n/scripts/export_from_dev.sh ] || [ ! -f /srv/n8n/scripts/import_to_prod.sh ]; then
            echo "ERROR: Scripts not found after deployment"
            exit 1
        fi
        if [ ! -x /srv/n8n/scripts/export_from_dev.sh ] || [ ! -x /srv/n8n/scripts/import_to_prod.sh ]; then
            echo "ERROR: Scripts are not executable"
            exit 1
        fi
        echo "Deployment verified successfully"
ENDSSH || {
        error "Deployment verification failed for ${vps_name}"
        return 1
    }
    
    log "Successfully deployed scripts to ${vps_name}"
    log "Backup location: ${backup_dir}"
}

# Main execution
main() {
    log "=========================================="
    log "Starting Script Deployment"
    log "=========================================="
    
    parse_arguments "$@"
    check_prerequisites
    
    if [[ "${DEPLOY_DEV}" == "true" ]]; then
        log ""
        log "Deploying to DEV VPS..."
        deploy_to_vps "${DEV_VPS_HOST}" "DEV" || {
            error "Failed to deploy to DEV VPS"
            exit 1
        }
    fi
    
    if [[ "${DEPLOY_PROD}" == "true" ]]; then
        log ""
        log "Deploying to PROD VPS..."
        deploy_to_vps "${PROD_VPS_HOST}" "PROD" || {
            error "Failed to deploy to PROD VPS"
            exit 1
        }
    fi
    
    log ""
    log "=========================================="
    log "Deployment completed successfully!"
    log "=========================================="
    log ""
    log "Scripts deployed to:"
    [[ "${DEPLOY_DEV}" == "true" ]] && log "  - DEV: ${DEV_VPS_HOST}"
    [[ "${DEPLOY_PROD}" == "true" ]] && log "  - PROD: ${PROD_VPS_HOST}"
    log ""
    log "Script locations:"
    log "  - /srv/n8n/scripts/export_from_dev.sh"
    log "  - /srv/n8n/scripts/import_to_prod.sh"
    log ""
    log "Next steps:"
    log "  1. Test scripts on DEV first"
    log "  2. Verify scripts work correctly"
    log "  3. Update GitHub Actions workflow if needed"
}

# Run main function
main "$@"

exit 0

