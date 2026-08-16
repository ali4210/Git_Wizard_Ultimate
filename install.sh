#!/usr/bin/env bash
# ==============================================================================
# SCRIPT NAME:  install.sh (Global Installer for Git-Wizard Ultimate)
# DESCRIPTION:  Installs git-wizard into /usr/local/bin for system-wide access,
#               and offers to install the full optional tool stack (gh, glab,
#               delta, chafa, lazygit, git-absorb, ghq, act/gitlab-ci-local).
# ==============================================================================

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# ==============================================================================
# OPTIONAL TOOL STACK — same detect -> offer -> fallback pattern used inside
# git-wizard.sh itself (Settings > Tool Stack Manager), offered once up front
# so new users don't have to discover each tool one screen at a time.
# ==============================================================================
detect_pkg_manager() {
    if command -v apt &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v pacman &>/dev/null; then echo "pacman"
    elif command -v zypper &>/dev/null; then echo "zypper"
    elif command -v brew &>/dev/null; then echo "brew"
    else echo "unknown"
    fi
}

get_install_command() {
    local tool="$1" pm="$2"
    case "$pm" in
        apt)
            case "$tool" in
                delta) echo "sudo apt install -y git-delta" ;;
                *) echo "sudo apt install -y ${tool}" ;;
            esac
            ;;
        dnf)    echo "sudo dnf install -y ${tool}" ;;
        pacman) echo "sudo pacman -S --noconfirm ${tool}" ;;
        zypper) echo "sudo zypper install -y ${tool}" ;;
        brew)   echo "brew install ${tool}" ;;
        *)      echo "" ;;
    esac
}

PM=$(detect_pkg_manager)

echo -e "${CYAN}${BOLD}📦 OPTIONAL TOOL STACK${NC}"
echo -e "${CYAN}git-wizard works fully without these, but each one unlocks specific features.${NC}\n"

TOOLS=(
    "gh|GitHub CLI — required for GitHub Issues/PRs/Releases/Actions (Module 6)"
    "glab|GitLab CLI — required for GitLab Issues/MRs/Releases/Pipelines (Module 6)"
    "delta|Prettier syntax-highlighted diffs (Delta Diff Suite, Repo History Viewer)"
    "chafa|Renders the terminal header logo as a real image instead of ASCII art"
    "lazygit|Full visual terminal UI for git (Tool Stack Manager > Bonus Tools)"
    "git-absorb|Auto-squashes fixup commits into the right earlier commit"
    "ghq|Organized local clone manager across GitHub and GitLab repos"
)

for entry in "${TOOLS[@]}"; do
    tool="${entry%%|*}"
    purpose="${entry#*|}"

    if command -v "$tool" &>/dev/null; then
        echo -e "  ${GREEN}[✔] ${tool}${NC} — already installed"
        continue
    fi

    echo -e "  ${YELLOW}[ ] ${tool}${NC} — ${CYAN}${purpose}${NC}"
    cmd=$(get_install_command "$tool" "$PM")
    if [[ -z "$cmd" ]]; then
        echo -e "      ${RED}No install command known for your package manager — skip and install manually if wanted.${NC}"
        continue
    fi
    read -p "      Install now with '${cmd}'? (y/N): " DOIT
    if [[ "$DOIT" =~ ^[Yy]$ ]]; then
        if eval "$cmd"; then
            echo -e "      ${GREEN}[✔] Installed.${NC}"
        else
            echo -e "      ${RED}[!] Repository install failed — git-wizard's own Tool Stack Manager (Main Menu > option 8)${NC}"
            echo -e "      ${RED}    can retry this later with an automatic binary-pull fallback.${NC}"
        fi
    else
        echo -e "      ${CYAN}Skipped — install anytime later from git-wizard's Tool Stack Manager.${NC}"
    fi
    echo ""
done

echo -e "\n${CYAN}${BOLD}Local CI testing (optional, needs Docker):${NC}"
echo -e "  ${CYAN}act${NC} (GitHub Actions) and ${CYAN}gitlab-ci-local${NC} (GitLab CI) are best installed on-demand —"
echo -e "  git-wizard's Tool Stack Manager > Bonus Tools > Local CI Testing detects which one you need"
echo -e "  automatically based on whether your repo has .github/workflows or .gitlab-ci.yml, and installs it then."

echo -e "\n===================================================================="
echo -e "${GREEN}${BOLD}Setup complete. Run 'git-wizard' from any repo to get started!${NC}"
echo -e "====================================================================\n"
