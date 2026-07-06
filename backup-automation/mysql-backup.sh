#!/bin/bash

#######################################
# Script Name: mysql-backup.sh
# Purpose: Automated MySQL database backup with rotation
# Author: Rohit Prakash Jadhav
# Date: 2024
# Version: 2.0
# Used in: Just Dial Production Environment
#######################################

set -euo pipefail

# ==================== CONFIGURATION ====================
BACKUP_DIR="${1:-/var/backups/mysql}"
RETENTION_DAYS="${2:-30}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
BACKUP_TYPE="${3:-daily}"
LOG_FILE="/var/log/mysql-backup.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==================== FUNCTIONS ====================

log() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}]${NC} ${message}" | tee -a "${LOG_FILE}"
}

error() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR ${timestamp}]${NC} ${message}" | tee -a "${LOG_FILE}"
    exit 1
}

warn() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[WARNING ${timestamp}]${NC} ${message}" | tee -a "${LOG_FILE}"
}

# Validate MySQL connection
validate_mysql_connection() {
    log "Validating MySQL connection..."
    
    if ! mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1" &>/dev/null; then
        error "Failed to connect to MySQL. Check credentials."
    fi
    
    log "MySQL connection validated successfully"
}

# Create backup directory
create_backup_directory() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log "Creating backup directory: ${BACKUP_DIR}"
        mkdir -p "${BACKUP_DIR}"
        chmod 700 "${BACKUP_DIR}"
    fi
}

# Perform full database backup
backup_all_databases() {
    log "Starting full database backup..."
    
    local backup_file="${BACKUP_DIR}/all-databases-$(date +'%Y%m%d-%H%M%S').sql.gz"
    local temp_file="/tmp/mysql-backup-$$.sql"
    
    # Backup all databases
    if mysqldump -u "${DB_USER}" -p"${DB_PASSWORD}" \
        --all-databases \
        --single-transaction \
        --quick \
        --lock-tables=false \
        > "${temp_file}" 2>>"${LOG_FILE}"; then
        
        # Compress backup
        gzip -9 "${temp_file}"
        mv "${temp_file}.gz" "${backup_file}"
        
        local size=$(du -h "${backup_file}" | cut -f1)
        log "✓ Full backup completed: ${backup_file} (${size})"
        echo "${backup_file}"
    else
        error "Failed to backup databases"
    fi
}

# Backup individual databases
backup_individual_databases() {
    log "Starting individual database backups..."
    
    local databases
    databases=$(mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -e "SHOW DATABASES;" | grep -v "^Database$" | grep -v "information_schema" | grep -v "performance_schema" | grep -v "mysql")
    
    for db in ${databases}; do
        local backup_file="${BACKUP_DIR}/${db}-$(date +'%Y%m%d-%H%M%S').sql.gz"
        local temp_file="/tmp/${db}-backup-$$.sql"
        
        if mysqldump -u "${DB_USER}" -p"${DB_PASSWORD}" \
            --single-transaction \
            --quick \
            --lock-tables=false \
            "${db}" > "${temp_file}" 2>>"${LOG_FILE}"; then
            
            gzip -9 "${temp_file}"
            mv "${temp_file}.gz" "${backup_file}"
            
            local size=$(du -h "${backup_file}" | cut -f1)
            log "✓ Database backup: ${db} - ${size}"
        else
            warn "Failed to backup database: ${db}"
        fi
    done
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up backups older than ${RETENTION_DAYS} days..."
    
    local deleted_count=0
    local freed_space=0
    
    while IFS= read -r file; do
        local size=$(du -b "${file}" | cut -f1)
        rm -f "${file}"
        deleted_count=$((deleted_count + 1))
        freed_space=$((freed_space + size))
    done < <(find "${BACKUP_DIR}" -type f -mtime +"${RETENTION_DAYS}")
    
    if [[ ${deleted_count} -gt 0 ]]; then
        local freed_mb=$((freed_space / 1024 / 1024))
        log "✓ Deleted ${deleted_count} old backups (freed ${freed_mb}MB)"
    else
        log "No old backups to delete"
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    log "Verifying backup integrity: ${backup_file}"
    
    if gzip -t "${backup_file}" 2>>"${LOG_FILE}"; then
        log "✓ Backup integrity verified"
        return 0
    else
        error "Backup integrity check failed: ${backup_file}"
    fi
}

# Generate backup report
generate_report() {
    log "Generating backup report..."
    
    local total_backups=$(find "${BACKUP_DIR}" -type f | wc -l)
    local total_size=$(du -sh "${BACKUP_DIR}" | cut -f1)
    local latest_backup=$(find "${BACKUP_DIR}" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
    
    log "════════════════════════════════════════"
    log "Backup Report"
    log "════════════════════════════════════════"
    log "Backup Directory: ${BACKUP_DIR}"
    log "Total Backups: ${total_backups}"
    log "Total Size: ${total_size}"
    log "Latest Backup: ${latest_backup}"
    log "Retention Days: ${RETENTION_DAYS}"
    log "Backup Type: ${BACKUP_TYPE}"
    log "════════════════════════════════════════"
}

# ==================== MAIN EXECUTION ====================

main() {
    log "Starting MySQL backup process..."
    log "Backup Type: ${BACKUP_TYPE} | Retention: ${RETENTION_DAYS} days"
    
    # Pre-flight checks
    validate_mysql_connection
    create_backup_directory
    
    # Perform backup
    case "${BACKUP_TYPE}" in
        daily)
            backup_all_databases
            ;;
        individual)
            backup_individual_databases
            ;;
        full)
            backup_all_databases
            backup_individual_databases
            ;;
        *)
            error "Invalid backup type: ${BACKUP_TYPE}. Use: daily, individual, or full"
            ;;
    esac
    
    # Post-backup operations
    cleanup_old_backups
    generate_report
    
    log "MySQL backup process completed successfully!"
}

# Trap errors
trap 'error "Script interrupted or failed"' INT TERM

# Execute main function
main "$@"