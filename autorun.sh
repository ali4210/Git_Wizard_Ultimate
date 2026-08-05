#!/usr/bin/env bash
# ==============================================================================
# TOOL NAME:    autorun.sh (Git-Wizard Master Launcher)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master Launcher for Git-Wizard CLI Suite.
# ==============================================================================

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/linux/git-wizard.sh"

clear
echo -e "${CYAN}${BOLD}====================================================================${NC}"
echo -e "${CYAN}${BOLD}        🧙‍♂️ GIT-WIZARD ULTIMATE - MASTER LAUNCHER (LINUX)           ${NC}"
echo -e "${CYAN}${BOLD}====================================================================${NC}"
echo ""

if [[ -f "$TARGET_SCRIPT" ]]; then
    chmod +x "$TARGET_SCRIPT"
    echo -e "${GREEN}--> Launching Git-Wizard Core Engine...${NC}\n"
    sleep 1
    exec "$TARGET_SCRIPT"
else
    echo -e "${YELLOW}[!] Error: Could not find 'linux/git-wizard.sh' in ${SCRIPT_DIR}${NC}"
    exit 1
fi