#!/bin/bash

#######################################
# Script Name: log-rotation.sh
# Purpose: Automated log rotation with compression and archival
# Author: Rohit Prakash Jadhav
# Date: 2024
# Version: 1.8
# Used in: Just Dial Production Environment
#######################################

set -euo pipefail

# ==================== CONFIGURATION ====================
LOG_FILE="${1:-/var/log/app.log}"
RETENTION_DAYS="${2:-30}"
MAX_BACKUPS="${3:-10}"
COMPRESS_AFTER_DAYS="${4:-7}"
ARCHIVE_DIR="/var/log/archive"
LOG_DIR="/var/log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==================== FUNCTIONS ====================

log() {
    local message="$1"
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${message}"
}

error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} ${message}" >&2
    exit 1
}

warn() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} ${message}"
}

# Validate input
validate_input() {
    if [[ ! -f "${LOG_FILE}" ]]; then
        error "Log file not found: ${LOG_FILE}"
    fi
    
    if ! [[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
        error "Invalid retention days: ${RETENTION_DAYS}"
    fi
    
    if ! [[ "${MAX_BACKUPS}" =~ ^[0-9]+$ ]]; then
        error "Invalid max backups: ${MAX_BACKUPS}"
    fi
}

# Create archive directory
create_archive_directory() {
    if [[ ! -d "${ARCHIVE_DIR}" ]]; then
        log "Creating archive directory: ${ARCHIVE_DIR}"
        mkdir -p "${ARCHIVE_DIR}"
        chmod 755 "${ARCHIVE_DIR}"
    fi
}

# Rotate log file
rotate_log() {
    log "Starting log rotation for: ${LOG_FILE}"
    
    local base_name=$(basename "${LOG_FILE}")
    local timestamp=$(date +'%Y%m%d-%H%M%S')
    local rotated_file="${LOG_DIR}/${base_name}.${timestamp}"
    
    # Check if log file exists and has content
    if [[ -f "${LOG_FILE}" ]]; then
        local file_size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}" 2>/dev/null)
        
        if [[ ${file_size} -gt 0 ]]; then
            # Rotate the file
            mv "${LOG_FILE}" "${rotated_file}"
            log "✓ Log rotated: ${LOG_FILE} -> ${rotated_file}"
            
            # Create new empty log file
            touch "${LOG_FILE}"
            
            # Restore original permissions
            if [[ -f "${rotated_file}" ]]; then
                chmod $(stat -c%a "${rotated_file}") "${LOG_FILE}" 2>/dev/null || true
                chown $(stat -c%U:%G "${rotated_file}") "${LOG_FILE}" 2>/dev/null || true
            fi
            
            echo "${rotated_file}"
        else
            log "Log file is empty, skipping rotation"
        fi
    else
        warn "Log file does not exist: ${LOG_FILE}"
    fi
}

# Compress old logs
compress_old_logs() {
    log "Compressing logs older than ${COMPRESS_AFTER_DAYS} days..."
    
    find "${LOG_DIR}" -name "$(basename "${LOG_FILE}").*" -type f -mtime +"${COMPRESS_AFTER_DAYS}" ! -name "*.gz" | while read -r file; do
        if [[ -f "${file}" ]]; then
            log "Compressing: ${file}"
            gzip -9 "${file}"
            
            if [[ -f "${file}.gz" ]]; then
                log "✓ Compressed: ${file}.gz"
            fi
        fi
    done
}

# Archive compressed logs
archive_logs() {
    log "Archiving compressed logs..."
    
    find "${LOG_DIR}" -name "$(basename "${LOG_FILE}")*.gz" -type f | while read -r file; do
        local archive_file="${ARCHIVE_DIR}/$(basename "${file}")"
        
        if mv "${file}" "${archive_file}"; then
            log "✓ Archived: ${archive_file}"
        else
            warn "Failed to archive: ${file}"
        fi
    done
}

# Cleanup old backups
cleanup_old_logs() {
    log "Cleaning up logs older than ${RETENTION_DAYS} days..."
    
    local deleted_count=0
    local freed_space=0
    
    # Cleanup in log directory
    while IFS= read -r file; do
        local size=$(stat -f%z "${file}" 2>/dev/null || stat -c%s "${file}" 2>/dev/null)
        rm -f "${file}"
        deleted_count=$((deleted_count + 1))
        freed_space=$((freed_space + size))
        log "Deleted: ${file}"
    done < <(find "${LOG_DIR}" -name "$(basename "${LOG_FILE}").*" -type f -mtime +"${RETENTION_DAYS}")
    
    # Cleanup in archive directory
    while IFS= read -r file; do
        local size=$(stat -f%z "${file}" 2>/dev/null || stat -c%s "${file}" 2>/dev/null)
        rm -f "${file}"
        deleted_count=$((deleted_count + 1))
        freed_space=$((freed_space + size))
        log "Deleted: ${file}"
    done < <(find "${ARCHIVE_DIR}" -name "$(basename "${LOG_FILE}").*" -type f -mtime +"${RETENTION_DAYS}")
    
    if [[ ${deleted_count} -gt 0 ]]; then
        local freed_mb=$((freed_space / 1024 / 1024))
        log "✓ Deleted ${deleted_count} old logs (freed ${freed_mb}MB)"
    else
        log "No old logs to delete"
    fi
}

# Enforce maximum backups
enforce_max_backups() {
    log "Enforcing maximum backup limit: ${MAX_BACKUPS}..."
    
    local backup_count
    backup_count=$(find "${LOG_DIR}" -name "$(basename "${LOG_FILE}").*" -type f | wc -l)
    backup_count=$((backup_count + $(find "${ARCHIVE_DIR}" -name "$(basename "${LOG_FILE}").*" -type f | wc -l)))
    
    if [[ ${backup_count} -gt ${MAX_BACKUPS} ]]; then
        local remove_count=$((backup_count - MAX_BACKUPS))
        log "Found ${backup_count} backups, removing oldest ${remove_count}..."
        
        find "${LOG_DIR}" "${ARCHIVE_DIR}" -name "$(basename "${LOG_FILE}").*" -type f -printf '%T@ %p\n' | \
            sort -n | head -n "${remove_count}" | cut -d' ' -f2- | while read -r file; do
            rm -f "${file}"
            log "✓ Removed: ${file}"
        done
    fi
}

# Generate rotation report
generate_report() {
    log "Generating rotation report..."
    
    local total_backups
    total_backups=$(find "${LOG_DIR}" "${ARCHIVE_DIR}" -name "$(basename "${LOG_FILE}").*" -type f | wc -l)
    
    local total_size
    total_size=$(du -sh "${LOG_DIR}" 2>/dev/null | cut -f1)
    
    local archive_size
    archive_size=$(du -sh "${ARCHIVE_DIR}" 2>/dev/null | cut -f1)
    
    log "════════════════════════════════════════"
    log "Log Rotation Report"
    log "════════════════════════════════════════"
    log "Log File: ${LOG_FILE}"
    log "Total Backups: ${total_backups}"
    log "Log Directory Size: ${total_size}"
    log "Archive Directory Size: ${archive_size}"
    log "Retention Days: ${RETENTION_DAYS}"
    log "Max Backups: ${MAX_BACKUPS}"
    log "════════════════════════════════════════"
}

# ==================== MAIN EXECUTION ====================

main() {
    log "Starting log rotation process..."
    log "Log File: ${LOG_FILE}"
    log "Retention: ${RETENTION_DAYS} days | Max Backups: ${MAX_BACKUPS}"
    
    # Pre-flight checks
    validate_input
    create_archive_directory
    
    # Perform rotation
    rotate_log
    
    # Post-rotation operations
    compress_old_logs
    archive_logs
    enforce_max_backups
    cleanup_old_logs
    generate_report
    
    log "Log rotation completed successfully!"
}

# Trap errors
trap 'error "Script interrupted or failed"' INT TERM

# Execute main function
main "$@"