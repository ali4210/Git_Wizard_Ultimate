#!/usr/bin/env bash
# Auto-fix permissions for all modules and scripts in the repository
find "$(dirname "$0")" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null
# ==============================================================================
# TOOL NAME:    autorun.sh (Git-Wizard Master Launcher)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master Launcher for Git-Wizard CLI Suite with chafa Auto-Installer.
# ==============================================================================

# NOTE: 'set -e' was removed — same reasoning as linux/git-wizard.sh. If the
# chafa install command below fails (network issue, package not in this
# repo, sudo prompt cancelled, etc.), errexit would kill autorun.sh right
# there and NEVER launch git-wizard.sh at all. chafa is a cosmetic nicety,
# not a hard requirement — its failure should never block the actual tool
# from starting. We handle nonzero exits manually where it matters instead.

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

# --- Launcher-only config (deliberately SEPARATE from git-wizard.sh's own
# ~/.git-wizard/config — that file gets fully overwritten by save_config()
# every time git-wizard.sh saves settings, which would silently wipe any
# flag we stored there. This file is autorun.sh's alone.) ---
LAUNCHER_CONFIG_DIR="${HOME}/.git-wizard"
LAUNCHER_CONFIG="${LAUNCHER_CONFIG_DIR}/launcher_config"
mkdir -p "$LAUNCHER_CONFIG_DIR"

# ==============================================================================
# COMMAND-LINE FLAGS — -f (flush cache) / --hard (full reset)
# Neither of these touches installed tools (jq, gh, delta, chafa, etc.) —
# only git-wizard's OWN saved state about itself.
# ==============================================================================
case "$1" in
    -f|--flush)
        echo -e "${YELLOW}[i] Flushing git-wizard's launcher cache (chafa prompt state)...${NC}"
        rm -f "$LAUNCHER_CONFIG"
        echo -e "${GREEN}[✔] Cache cleared — you'll be asked about chafa again this run.${NC}\n"
        ;;
    --hard)
        echo -e "${RED}${BOLD}[!] HARD RESET${NC}${RED} — this erases git-wizard's saved settings, action${NC}"
        echo -e "${RED}history, and launcher cache. Installed tools (jq/gh/delta/etc) are NOT${NC}"
        echo -e "${RED}touched and stay installed. Your PAT Vault is NEVER touched by this flag —${NC}"
        echo -e "${RED}it can only be cleared manually, token-by-token, from inside the tool.${NC}"
        read -p "    Type 'yes' to confirm: " HARDCONF
        if [[ "$HARDCONF" == "yes" ]]; then
            rm -f "${HOME}/.git-wizard/config"
            rm -f "${HOME}/.git-wizard/actions.log"
            rm -f "${HOME}/.git-wizard/launcher_config"
            rm -f "${HOME}/.git-wizard"/tool-backup-* 2>/dev/null
            echo -e "${GREEN}[✔] git-wizard has been reset to a fresh-install state.${NC}"
            echo -e "${CYAN}    (PAT Vault left untouched: ${HOME}/.git-wizard/pat_vault.env)${NC}\n"
        else
            echo -e "${YELLOW}[i] Hard reset cancelled — nothing was changed.${NC}\n"
        fi
        ;;
    "") ;;  # normal run, no flag
    *)
        echo -e "${YELLOW}[i] Unknown flag '$1' — ignoring. Supported: -f (flush cache), --hard (full reset).${NC}\n"
        ;;
esac

CHAFA_PROMPT_ANSWERED="false"
if [[ -f "$LAUNCHER_CONFIG" ]]; then
    source "$LAUNCHER_CONFIG"
fi

clear
echo -e "${CYAN}${BOLD}====================================================================${NC}"
echo -e "${CYAN}${BOLD}        🧙‍♂️ GIT-WIZARD ULTIMATE - MASTER LAUNCHER (LINUX)           ${NC}"
echo -e "${CYAN}${BOLD}====================================================================${NC}"
echo ""

# --- Check & Auto-Install chafa (asked once ever, never blocks the launcher) ---
if ! command -v chafa &>/dev/null && [[ "$CHAFA_PROMPT_ANSWERED" != "true" ]]; then
    echo -e "${YELLOW}[!] 'chafa' (Terminal PNG Image Renderer) is not installed.${NC}"
    read -p "Would you like to install 'chafa' now to render high-res GitHub images? (y/N): " INSTALL_CONF

    if [[ "$INSTALL_CONF" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}--> Detecting package manager and installing 'chafa'...${NC}"
        INSTALL_OK="false"
        if command -v apt &>/dev/null; then
            sudo apt update && sudo apt install -y chafa && INSTALL_OK="true"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y chafa && INSTALL_OK="true"
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm chafa && INSTALL_OK="true"
        elif command -v zypper &>/dev/null; then
            sudo zypper install -y chafa && INSTALL_OK="true"
        elif command -v brew &>/dev/null; then
            brew install chafa && INSTALL_OK="true"
        elif [[ "$(uname -s)" == "Darwin" ]]; then
            echo -e "${YELLOW}[i] Homebrew not found — installing it first (this is the standard way to get chafa on macOS)...${NC}"
            NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [[ -d "/opt/homebrew/bin" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -x "/usr/local/bin/brew" ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            if command -v brew &>/dev/null; then
                brew install chafa && INSTALL_OK="true"
            fi
        else
            echo -e "${RED}[!] Could not detect a supported package manager. Skipping 'chafa' installation.${NC}"
        fi

        if [[ "$INSTALL_OK" != "true" ]] && command -v snap &>/dev/null; then
            echo -e "${YELLOW}[i] Repository install didn't work — trying snap as a universal fallback...${NC}"
            sudo snap install chafa && INSTALL_OK="true"
        fi

        if [[ "$INSTALL_OK" == "true" ]]; then
            echo -e "${GREEN}[✔] chafa installed successfully.${NC}"
        else
            echo -e "${YELLOW}[i] chafa install didn't complete — continuing with the standard ASCII header logo instead.${NC}"
            echo -e "${CYAN}    (This never blocks git-wizard from launching. This usually just means your distro's apt/dnf/pacman${NC}"
            echo -e "${CYAN}    repos don't ship 'chafa' by default — e.g. Parrot sometimes needs backports enabled for it.${NC}"
            echo -e "${CYAN}    Install manually anytime from https://github.com/hpjansson/chafa/releases,${NC}"
            echo -e "${CYAN}    or run './autorun.sh -f' to be asked again next launch.)${NC}"
        fi
    else
        echo -e "${CYAN}[i] Continuing with standard ASCII header logo.${NC}"
    fi

    # Remember that we asked — success, failure, or decline all count as
    # "answered." User can always force a re-ask by deleting the file noted
    # above, or by installing chafa manually (the `! command -v chafa` check
    # up top will then just naturally skip this whole block anyway).
    echo 'CHAFA_PROMPT_ANSWERED="true"' > "$LAUNCHER_CONFIG"
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
