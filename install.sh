#!/usr/bin/env bash
# ==============================================================================
# SCRIPT NAME:  install.sh (Global Installer for Git-Wizard Ultimate)
# DESCRIPTION:  Installs git-wizard into /usr/local/bin for system-wide access.
# ==============================================================================

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}--> Installing Git-Wizard Ultimate globally onto your system...${NC}"

# Source binary path inside linux/ subdirectory
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${INSTALL_DIR}/linux/git-wizard.sh"

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo -e "\033[0;31m[!] Error: Could not find git-wizard.sh at ${SCRIPT_PATH}\033[0m"
    exit 1
fi

chmod +x "$SCRIPT_PATH"
chmod +x "${INSTALL_DIR}/autorun.sh" 2>/dev/null || true

# Symlink to /usr/local/bin for global CLI access
if [[ -w "/usr/local/bin" ]]; then
    ln -sf "$SCRIPT_PATH" /usr/local/bin/git-wizard
else
    echo -e "${CYAN}--> Requesting root permission to link binary into /usr/local/bin/git-wizard...${NC}"
    sudo ln -sf "$SCRIPT_PATH" /usr/local/bin/git-wizard
fi

echo -e "\n===================================================================="
echo -e "${GREEN}${BOLD}[✔] GIT-WIZARD IS NOW INSTALLED GLOBALLY ON YOUR SYSTEM!${NC}"
echo -e "===================================================================="
echo -e "${CYAN}📌 HOW TO USE FROM ANY FOLDER:${NC}"
echo -e "  1. Open ANY terminal and 'cd' into ANY Git repository on your machine."
echo -e "  2. Simply type: ${GREEN}${BOLD}git-wizard${NC}"
echo -e "====================================================================\n"