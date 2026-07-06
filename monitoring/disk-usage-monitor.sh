#!/bin/bash

#######################################
# Script Name: disk-usage-monitor.sh
# Purpose: Monitor disk space and alert on high usage
# Author: Rohit Prakash Jadhav
# Date: 2024
# Version: 1.5
# Used in: Just Dial Production Environment
#######################################

set -euo pipefail

# ==================== CONFIGURATION ====================
THRESHOLD="${1:-80}"
ALERT_EMAIL="${ALERT_EMAIL:-admin@example.com}"
LOG_FILE="/var/log/disk-monitor.log"
METRICS_FILE="/tmp/disk-usage-metrics.txt"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
}

warn() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[WARNING ${timestamp}]${NC} ${message}" | tee -a "${LOG_FILE}"
}

# Validate threshold
validate_threshold() {
    if ! [[ "${THRESHOLD}" =~ ^[0-9]+$ ]] || [[ ${THRESHOLD} -lt 0 ]] || [[ ${THRESHOLD} -gt 100 ]]; then
        error "Invalid threshold: ${THRESHOLD}. Must be between 0-100"
    fi
}

# Check disk usage
check_disk_usage() {
    log "Checking disk usage (Threshold: ${THRESHOLD}%)..."
    
    > "${METRICS_FILE}"  # Clear metrics file
    
    local alert_triggered=false
    
    df -h | tail -n +2 | while read -r line; do
        local filesystem=$(echo "${line}" | awk '{print $1}')
        local size=$(echo "${line}" | awk '{print $2}')
        local used=$(echo "${line}" | awk '{print $3}')
        local available=$(echo "${line}" | awk '{print $4}')
        local usage_percent=$(echo "${line}" | awk '{print $5}' | sed 's/%//')
        local mount_point=$(echo "${line}" | awk '{print $6}')
        
        # Append to metrics file
        echo "${filesystem}|${usage_percent}|${mount_point}" >> "${METRICS_FILE}"
        
        # Check against threshold
        if [[ ${usage_percent} -ge ${THRESHOLD} ]]; then
            if [[ ${usage_percent} -ge 95 ]]; then
                error "CRITICAL: ${filesystem} at ${usage_percent}% (${used}/${size}) on ${mount_point}"
                alert_triggered=true
            elif [[ ${usage_percent} -ge ${THRESHOLD} ]]; then
                warn "WARNING: ${filesystem} at ${usage_percent}% (${used}/${size}) on ${mount_point}"
                alert_triggered=true
            fi
        else
            log "✓ ${filesystem}: ${usage_percent}% - ${used}/${size} on ${mount_point}"
        fi
    done
    
    if [[ "${alert_triggered}" == "true" ]]; then
        return 1
    fi
    return 0
}

# Check inode usage
check_inode_usage() {
    log "Checking inode usage..."
    
    df -i | tail -n +2 | while read -r line; do
        local filesystem=$(echo "${line}" | awk '{print $1}')
        local total_inodes=$(echo "${line}" | awk '{print $2}')
        local used_inodes=$(echo "${line}" | awk '{print $3}')
        local inode_percent=$(echo "${line}" | awk '{print $5}' | sed 's/%//')
        local mount_point=$(echo "${line}" | awk '{print $6}')
        
        if [[ ${inode_percent} -ge 90 ]]; then
            error "CRITICAL: ${filesystem} inodes at ${inode_percent}% on ${mount_point}"
        elif [[ ${inode_percent} -ge 80 ]]; then
            warn "WARNING: ${filesystem} inodes at ${inode_percent}% on ${mount_point}"
        else
            log "✓ ${filesystem} inodes: ${inode_percent}%"
        fi
    done
}

# Generate report
generate_report() {
    log "Generating disk usage report..."
    
    cat > "/tmp/disk-usage-report.txt" << EOF
Disk Usage Report
Generated: $(date +'%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Threshold: ${THRESHOLD}%

$(df -h)

Inode Usage:
$(df -i)

Last Updated: $(date)
EOF
    
    log "Report saved to: /tmp/disk-usage-report.txt"
}

# ==================== MAIN EXECUTION ====================

main() {
    log "Starting disk usage monitoring..."
    
    validate_threshold
    
    # Check disk and inode usage
    if ! check_disk_usage; then
        warn "Disk usage exceeds threshold!"
    fi
    
    check_inode_usage
    generate_report
    
    log "Disk usage monitoring completed"
}

# Execute main function
main "$@"