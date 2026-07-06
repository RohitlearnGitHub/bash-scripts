#!/bin/bash

#######################################
# Script: user-creation.sh
# Purpose: Create user accounts in bulk
# Author: Rohit Prakash Jadhav
# Date: 2024
#######################################

set -euo pipefail

CSV_FILE="${1:-users.csv}"
DEFAULT_SHELL="${2:-/bin/bash}"
CREATE_HOME="${3:-yes}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

if [[ ! -f "${CSV_FILE}" ]]; then
    error "CSV file not found: ${CSV_FILE}"
fi

log "Starting user creation from: ${CSV_FILE}"

while IFS=',' read -r username fullname groups; do
    username=$(echo "${username}" | xargs)  # Trim whitespace
    fullname=$(echo "${fullname}" | xargs)
    groups=$(echo "${groups}" | xargs)
    
    if id "${username}" &>/dev/null; then
        log "User already exists: ${username}"
    else
        useradd -m -s "${DEFAULT_SHELL}" -c "${fullname}" "${username}"
        if [[ -n "${groups}" ]]; then
            usermod -aG "${groups}" "${username}"
        fi
        log "✓ Created user: ${username}"
    fi
done < "${CSV_FILE}"

log "User creation completed!"