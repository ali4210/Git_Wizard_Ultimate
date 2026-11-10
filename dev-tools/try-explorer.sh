#!/usr/bin/env bash
# Standalone tester for the Workspace Explorer -- lets you drive it without
# going through the real main menu. Real confirm/backup/log/header
# behavior, same as the shipped tool, just without loading all of
# linux/git-wizard.sh's other 140 functions and its own main loop.
#
# Usage: ./try-explorer.sh /path/to/any/git/repo
set -uo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
WIZARD_MODE="advanced"   # advanced = y/N confirm; set to "beginner" to test the typed "yes i understand" confirm
DRY_RUN="false"          # set to "true" to test Dry-Run mode (nothing is actually executed)
CONFIG_DIR="/tmp/gw-explorer-tester-config"
ACTION_LOG="${CONFIG_DIR}/actions.log"
mkdir -p "$CONFIG_DIR"
touch "$ACTION_LOG"

log_action() { echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$ACTION_LOG"; }
run_git() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}${BOLD}[DRY-RUN] Would execute:${NC} git $*"
        log_action "DRY-RUN (not executed): git $*"
        return 0
    else
        log_action "EXECUTED: git $*"
        git "$@"
    fi
}
create_safety_backup() {
    local reason="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would create safety backup tag: backup/${reason}-...${NC}"
        return 0
    fi
    if git rev-parse HEAD &>/dev/null; then
        local ts tag
        ts=$(date '+%Y%m%d-%H%M%S')
        tag="backup/${reason}-${ts}"
        git tag "$tag" HEAD 2>/dev/null || true
        echo -e "${GREEN}[✔] Safety backup created: ${CYAN}${tag}${NC} ${GREEN}(recover with: git reset --hard ${tag})${NC}"
        log_action "BACKUP created: ${tag} (reason: ${reason})"
    fi
}
confirm_destructive() {
    local action_desc="$1"
    echo -e "\n${RED}${BOLD}⚠ DESTRUCTIVE ACTION: ${action_desc}${NC}"
    if [[ "$WIZARD_MODE" == "beginner" ]]; then
        echo -e "${YELLOW}Beginner Mode requires typed confirmation.${NC}"
        read -e -r -p "Type EXACTLY 'yes i understand' to proceed: " CONF
        [[ "$CONF" == "yes i understand" ]]
    else
        read -e -r -p "Proceed? (y/N): " CONF
        [[ "$CONF" =~ ^[Yy]$ ]]
    fi
}
show_action_history() { :; }

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/linux/workspace-explorer.sh"

TARGET="${1:-$(pwd)}"
cd "$TARGET" || { echo "No such directory: $TARGET"; exit 1; }

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo -e "${RED}Not a git repository: ${TARGET}${NC}"
    exit 1
fi

trap 'tput cnorm 2>/dev/null; stty sane 2>/dev/null' EXIT
ws_workspace_explorer
echo -e "\n${CYAN}Exited the Workspace Explorer. Action log: ${ACTION_LOG}${NC}"
