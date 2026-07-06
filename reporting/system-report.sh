#!/bin/bash

#######################################
# Script Name: system-report.sh
# Purpose: Generate comprehensive system report
# Author: Rohit Prakash Jadhav
# Date: 2024
# Version: 1.2
#######################################

set -euo pipefail

REPORT_DIR="/tmp/system-reports"
TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
REPORT_FILE="${REPORT_DIR}/system-report-${TIMESTAMP}.txt"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create report directory
mkdir -p "${REPORT_DIR}"

# Generate report
cat > "${REPORT_FILE}" << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║           SYSTEM HEALTH REPORT
╚═══════════════════════════════════════════════════════════════╝

1. SYSTEM INFORMATION
───────────────────────────────────────────────────────────────
EOF

echo "Hostname: $(hostname)" >> "${REPORT_FILE}"
echo "Kernel: $(uname -r)" >> "${REPORT_FILE}"
echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')" >> "${REPORT_FILE}"
echo "Uptime: $(uptime -p)" >> "${REPORT_FILE}"
echo "Load Average: $(cat /proc/loadavg | awk '{print $1, $2, $3}')" >> "${REPORT_FILE}"

echo "" >> "${REPORT_FILE}"
echo "2. HARDWARE INFORMATION" >> "${REPORT_FILE}"
echo "───────────────────────────────────────────────────────────────" >> "${REPORT_FILE}"
echo "CPU Cores: $(nproc)" >> "${REPORT_FILE}"
echo "Total RAM: $(free -h | grep Mem | awk '{print $2}')" >> "${REPORT_FILE}"

echo "" >> "${REPORT_FILE}"
echo "3. DISK USAGE" >> "${REPORT_FILE}"
echo "───────────────────────────────────────────────────────────────" >> "${REPORT_FILE}"
df -h >> "${REPORT_FILE}"

echo "" >> "${REPORT_FILE}"
echo "4. MEMORY USAGE" >> "${REPORT_FILE}"
echo "───────────────────────────────────────────────────────────────" >> "${REPORT_FILE}"
free -h >> "${REPORT_FILE}"

echo "" >> "${REPORT_FILE}"
echo "5. NETWORK CONFIGURATION" >> "${REPORT_FILE}"
echo "───────────────────────────────────────────────────────────────" >> "${REPORT_FILE}"
echo "IP Addresses: $(hostname -I)" >> "${REPORT_FILE}"

echo "" >> "${REPORT_FILE}"
echo "6. TOP RUNNING SERVICES" >> "${REPORT_FILE}"
echo "───────────────────────────────────────────────────────────────" >> "${REPORT_FILE}"
systemctl list-units --type=service --state=running 2>/dev/null | head -20 >> "${REPORT_FILE}"

echo "" >> "${REPORT_FILE}"
echo "═══════════════════════════════════════════════════════════════" >> "${REPORT_FILE}"
echo "Report saved to: ${REPORT_FILE}" >> "${REPORT_FILE}"
echo "Generated: $(date)" >> "${REPORT_FILE}"

echo -e "${GREEN}✓ System report generated successfully!${NC}"
echo -e "${BLUE}Report saved to: ${REPORT_FILE}${NC}"

cat "${REPORT_FILE}"