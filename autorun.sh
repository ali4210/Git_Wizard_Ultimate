#!/usr/bin/env bash
# Auto-fix permissions for all modules and scripts in the repository
find "$(dirname "$0")" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null
# ==============================================================================
# TOOL NAME:    autorun.sh (Git-Wizard Master Launcher)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master Launcher for Git-Wizard CLI Suite with chafa Auto-Installer.
# ==============================================================================

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# ==============================================================================
# TERMINAL HYGIENE — same fix as linux/git-wizard.sh.
# ------------------------------------------------------------------------------
# autorun.sh prints its own banner BEFORE handing off to git-wizard.sh. Even
# though git-wizard.sh enters/exits the alternate screen buffer correctly on
# its own, this launcher's pre-launch banner was drawn on the NORMAL screen
# buffer beforehand — so it stayed behind in the scrollback after everything
# else exited. Entering the alt-buffer here too means the ENTIRE session
# (launcher banner + the tool itself) disappears cleanly on exit, leaving the
# user's original terminal scrollback untouched.
# ==============================================================================
_gw_restore_terminal() {
    printf '\033[?1049l'
    tput cnorm 2>/dev/null || true
    stty sane 2>/dev/null || true
}
_gw_handle_interrupt() {
    _gw_restore_terminal
    exit 130
}
trap _gw_restore_terminal EXIT
trap _gw_handle_interrupt INT TERM
printf '\033[?1049h\033[H'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/linux/git-wizard.sh"
IMAGE_PATH="${SCRIPT_DIR}/assets/octocat.png"

clear
echo -e "${CYAN}${BOLD}====================================================================${NC}"
echo -e "${CYAN}${BOLD}        🧙‍♂️ GIT-WIZARD ULTIMATE - MASTER LAUNCHER (LINUX)           ${NC}"
echo -e "${CYAN}${BOLD}====================================================================${NC}"
echo ""

# --- Check & Auto-Install chafa ---
if ! command -v chafa &>/dev/null; then
echo -e "${YELLOW}[!] 'chafa' (Terminal PNG Image Renderer) is not installed.${NC}"
read -p "Would you like to install 'chafa' now to render high-res GitHub images? (y/N): " INSTALL_CONF
if [[ "$INSTALL_CONF" =~ ^[Yy]$ ]]; then
echo -e "${GREEN}--> Detecting package manager and installing 'chafa'...${NC}"
if command -v apt &>/dev/null; then
sudo apt update && sudo apt install -y chafa
elif command -v dnf &>/dev/null; then
sudo dnf install -y chafa
elif command -v pacman &>/dev/null; then
sudo pacman -S --noconfirm chafa
elif command -v zypper &>/dev/null; then
sudo zypper install -y chafa
else
echo -e "${RED}[!] Could not detect package manager. Skipping 'chafa' installation.${NC}"
fi
else
echo -e "${CYAN}[i] Continuing with standard ASCII header logo.${NC}"
fi
echo ""
fi

if [[ -f "$TARGET_SCRIPT" ]]; then
chmod +x "$TARGET_SCRIPT"
echo -e "${GREEN}--> Launching Git-Wizard Core Engine...${NC}\n"
sleep 1
# NOTE: previously this used `exec`, which replaces autorun.sh's process
# image entirely — that's actually fine for the alt-buffer fix (the child
# inherits the same terminal state), but since git-wizard.sh sets up its
# OWN trap/alt-buffer pair independently, `exec`-ing it means OUR trap
# above never fires for the child's exit. We deliberately do NOT exec here
# anymore — we call it as a normal child process so _gw_restore_terminal
# still runs when the whole launcher finishes, covering both the banner
# above AND anything printed between the child exiting and our own exit.
"$TARGET_SCRIPT"
else
echo -e "${RED}[!] Error: Could not find 'linux/git-wizard.sh' in ${SCRIPT_DIR}${NC}"
exit 1
fi
