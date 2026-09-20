#!/usr/bin/env bash
# ==============================================================================
# TOOL NAME:    git-wizard.sh (Universal Global CLI Edition V2.0 - Gold Standard)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Interactive CLI Suite for Git/GitHub Onboarding & Workflows.
# COMPATIBILITY: Debian, Ubuntu, Kali Linux, RHEL, CentOS, Fedora, Arch, macOS
# NEW IN V2.0:  Beginner/Advanced modes, Module 5 (Team & OSS Collaboration),
#               Dry-Run Mode, Safety/Backup Engine, Cross-Distro Package Check,
#               Tool Action History, Live Sync Status Indicator.
# ==============================================================================

# NOTE: 'set -e' was removed. It caused the ENTIRE tool to exit to the shell
# whenever any external command (gh, glab, docker, etc.) returned non-zero —
# e.g. a 403 from GitHub, "no script found", or a missing scope. The script
# already checks return codes manually where it matters (run_git, confirm_*,
# etc.), so global errexit was doing more harm than good.

# ==============================================================================
# TERMINAL HYGIENE — alternate screen buffer + guaranteed restoration
# ------------------------------------------------------------------------------
# Without this, every menu redraw (plain `clear`) pushes a new frame into the
# user's terminal SCROLLBACK history instead of a dedicated TUI viewport —
# scrolling up after a session shows dozens of stacked duplicate menus.
# Entering the alternate screen buffer (used by vim/htop/less) isolates all
# of git-wizard's drawing into a temporary view that vanishes on exit,
# leaving the user's original scrollback untouched.
#
# The trap ALSO guarantees the cursor is restored (tput cnorm) even if the
# user Ctrl+C's out of an arrow-key menu (tput civis) instead of pressing
# q/Enter — otherwise the terminal cursor stays invisible after exit.
# ==============================================================================
_gw_restore_terminal() {
    printf '\033[?1049l'   # leave alternate screen buffer, return to normal scrollback
    tput cnorm 2>/dev/null || true   # ensure cursor is visible
    stty sane 2>/dev/null || true    # reset terminal line discipline defensively
}
_gw_handle_interrupt() {
    _gw_restore_terminal
    exit 130
}
trap _gw_restore_terminal EXIT
trap _gw_handle_interrupt INT TERM
printf '\033[?1049h\033[H'   # enter alternate screen buffer, move cursor home

SCRIPT_VERSION="2.1.0"

# --- Paths ---
TARGET_REPO_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
CONFIG_DIR="${HOME}/.git-wizard"
CONFIG_FILE="${CONFIG_DIR}/config"
ACTION_LOG="${CONFIG_DIR}/actions.log"
mkdir -p "$CONFIG_DIR"
touch "$ACTION_LOG"

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Global Runtime State (loaded from config, can be toggled in-session) ---
WIZARD_MODE=""          # beginner | advanced
DRY_RUN="false"          # true | false
AUTO_SYNC_CHECK="false"  # true | false
SYNC_DETAIL_LEVEL="standard"  # minimal | standard | full
VCS_PROVIDER=""          # github | gitlab (auto-detected or user-chosen, per-launch)
UPDATE_REPO=""           # e.g. "ali4210/git-wizard" - set via Settings
LAST_UPDATE_CHECK=""     # unix timestamp of last update check
UPDATE_NOTICE=""         # populated by check_for_updates if a newer version exists
GLOBAL_CLI_ENABLED="false"
# ==============================================================================
# CONFIG PERSISTENCE
# ==============================================================================
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    return 0
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
WIZARD_MODE="${WIZARD_MODE}"
DRY_RUN="${DRY_RUN}"
AUTO_SYNC_CHECK="${AUTO_SYNC_CHECK}"
SYNC_DETAIL_LEVEL="${SYNC_DETAIL_LEVEL}"
UPDATE_REPO="${UPDATE_REPO}"
LAST_UPDATE_CHECK="${LAST_UPDATE_CHECK}"
GLOBAL_CLI_ENABLED="${GLOBAL_CLI_ENABLED}"
EOF
}
# ==============================================================================
# TOOL ACTION LOG (this is git-wizard's own history, NOT git's commit history)
# ==============================================================================
log_action() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ${msg}" >> "$ACTION_LOG"
}

show_action_history() {
    show_header
    echo -e "${YELLOW}${BOLD}📜 GIT-WIZARD ACTION HISTORY (Last 25 Actions)${NC}\n"
    if [[ ! -s "$ACTION_LOG" ]]; then
        echo -e "${CYAN}No actions recorded yet.${NC}"
    else
        tail -n 25 "$ACTION_LOG" | while IFS= read -r line; do
            echo -e "  ${GREEN}•${NC} ${line}"
        done
    fi
    pause
}

# ==============================================================================
# DRY-RUN WRAPPER
# Every destructive/network git command should be routed through this.
# Usage: run_git push origin main --force
# ==============================================================================
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

# ==============================================================================
# COMMIT WITH HOOK-RETRY
# Wraps `git commit` so pre-commit hooks that auto-fix files (trailing
# whitespace, EOF newlines, etc.) and exit non-zero ON PURPOSE don't block
# the workflow. Retries the commit ONCE after re-staging, but ONLY if the
# failure left new unstaged changes behind (the hook's fingerprint) — a
# genuine hook failure (lint error, oversized file, conflict marker) still
# stops here and shows the real error instead of retrying blindly.
# Usage: commit_with_hook_retry "commit message"   → returns 0/1
# ==============================================================================
commit_with_hook_retry() {
    local msg="$1"
    local retried="false"
    while true; do
        if run_git commit -m "$msg"; then
            return 0
        fi

        if [[ "$retried" == "false" && -n "$(git status --porcelain)" ]]; then
            echo -e "\n${YELLOW}[i] A pre-commit hook modified your files (formatting auto-fixes) — that's expected.${NC}"
            echo -e "${CYAN}--> Re-staging the fixed files and retrying the commit...${NC}\n"
            run_git add .
            retried="true"
            continue
        fi

        echo -e "${RED}[!] Commit failed — this looks like a real hook failure, not just auto-fixed formatting.${NC}"
        echo -e "${YELLOW}    Check the hook output above, fix the issue, then try again.${NC}"
        return 1
    done
}

# ==============================================================================
# SAFETY & BACKUP ENGINE
# Creates a lightweight recovery point before destructive operations.
# ==============================================================================
create_safety_backup() {
    local reason="$1"
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        return 0
    fi
    local ts
    ts=$(date '+%Y%m%d-%H%M%S')
    local tag_name="backup/${reason}-${ts}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would create safety backup tag: ${tag_name}${NC}"
        return 0
    fi

    if git rev-parse HEAD &>/dev/null; then
        git tag "$tag_name" HEAD 2>/dev/null || true
        echo -e "${GREEN}[✔] Safety backup created: ${CYAN}${tag_name}${NC} ${GREEN}(recover with: git reset --hard ${tag_name})${NC}"
        log_action "BACKUP created: ${tag_name} (reason: ${reason})"
    fi
}

confirm_destructive() {
    local action_desc="$1"
    echo -e "\n${RED}${BOLD}⚠ DESTRUCTIVE ACTION: ${action_desc}${NC}"
    if [[ "$WIZARD_MODE" == "beginner" ]]; then
        echo -e "${YELLOW}Beginner Mode requires typed confirmation.${NC}"
        read -e -p "Type EXACTLY 'yes i understand' to proceed: " CONF
        [[ "$CONF" == "yes i understand" ]]
    else
        read -e -p "Proceed? (y/N): " CONF
        [[ "$CONF" =~ ^[Yy]$ ]]
    fi
}

# ==============================================================================
# FORCE SYNC WITH ORIGIN — Nuclear recovery when a local machine has badly
# diverged/tangled and you just want local to match GitHub exactly.
# Steps: detect branch/remote -> backup -> fetch -> hard reset -> clean debris.
# ==============================================================================
force_sync_with_origin() {
    show_header
    echo -e "${RED}${BOLD}☢️  FORCE SYNC WITH ORIGIN (Nuclear Reset)${NC}\n"
    echo -e "${YELLOW}This makes your LOCAL branch identical to GitHub's version.${NC}"
    echo -e "${YELLOW}Any local commits or changes not already on origin will be LOST (a backup tag is created first).${NC}\n"

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}[!] Not inside a Git repository.${NC}"
        pause
        return
    fi

    # --- Step 1: Detect active branch & remote origin ---
    echo -e "${CYAN}[1/5] Detecting active branch & remote origin...${NC}"
    local BRANCH
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
        echo -e "${RED}[!] Could not determine active branch (possibly detached HEAD).${NC}"
        pause
        return
    fi
    if ! git remote get-url origin &>/dev/null; then
        echo -e "${RED}[!] No 'origin' remote configured. Set one via Module 1 first.${NC}"
        pause
        return
    fi
    local ORIGIN_URL
    ORIGIN_URL=$(git remote get-url origin)
    echo -e "${GREEN}    Branch: ${BRANCH}${NC}"
    echo -e "${GREEN}    Origin: ${ORIGIN_URL}${NC}"

    if ! confirm_destructive "Force-sync local branch '${BRANCH}' to match origin/${BRANCH} exactly"; then
        echo -e "${YELLOW}[i] Cancelled — no changes made.${NC}"
        pause
        return
    fi

    # --- Step 2: Create automated safety backup tag/branch ---
    echo -e "\n${CYAN}[2/5] Creating automated safety backup...${NC}"
    create_safety_backup "pre-force-sync-${BRANCH}"

    # --- Step 3: Fetch fresh refspec from origin ---
    echo -e "\n${CYAN}[3/5] Fetching fresh refs from origin...${NC}"
    if ! run_git fetch origin; then
        echo -e "${RED}[!] Fetch failed. Check your connection/remote. Aborting — nothing was reset.${NC}"
        pause
        return
    fi

    if ! git rev-parse --verify "origin/${BRANCH}" &>/dev/null; then
        echo -e "${RED}[!] 'origin/${BRANCH}' does not exist on the remote. Aborting — nothing was reset.${NC}"
        echo -e "${YELLOW}    (Check the branch name, or that it's actually pushed to GitHub.)${NC}"
        pause
        return
    fi

    # --- Step 4: Hard reset local branch to origin/<branch> ---
    echo -e "\n${CYAN}[4/5] Hard resetting local '${BRANCH}' to 'origin/${BRANCH}'...${NC}"
    run_git reset --hard "origin/${BRANCH}"

    # --- Step 5: Clean untracked/leftover merge debris ---
    echo -e "\n${CYAN}[5/5] Cleaning untracked files & leftover merge debris (-fd)...${NC}"
    run_git clean -fd

    echo -e "\n${GREEN}${BOLD}[✔] Force sync complete. Local '${BRANCH}' now matches origin/${BRANCH} exactly.${NC}"
    echo -e "${GREEN}    Recover anything lost with: git reset --hard <backup-tag-name-shown-above>${NC}"
    pause
}

# ==============================================================================
# CROSS-DISTRO PACKAGE VERIFICATION
# ==============================================================================
detect_pkg_manager() {
    if command -v apt &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v pacman &>/dev/null; then echo "pacman"
    elif command -v brew &>/dev/null; then echo "brew"
    else echo "unknown"
    fi
}
# ==============================================================================
# ENSURE GIT ITSELF IS INSTALLED (bootstrap — must run before anything else
# touches the 'git' command).
#   Linux fast path:  native package manager (apt/dnf/pacman) — seconds.
#   macOS fast path:  Apple's Command Line Tools (xcode-select --install) —
#                      this is what actually ships git on stock Macs, and is
#                      lighter than pulling all of Homebrew just for git.
#   Universal fallback (Linux AND macOS): Homebrew — no sudo required.
# ==============================================================================
ensure_git_installed() {
    if command -v git &>/dev/null; then
        return 0
    fi

    echo -e "${YELLOW}[i] 'git' is not installed on this system — installing automatically...${NC}"

    local os
    os=$(uname -s)

    # --------------------------------------------------------------------
    # macOS (Darwin) — try Apple's own Command Line Tools FIRST.
    # --------------------------------------------------------------------
    if [[ "$os" == "Darwin" ]]; then
        echo -e "${CYAN}[i] macOS detected. Apple's Command Line Tools include git and are the${NC}"
        echo -e "${CYAN}    lightest official way to get it (no full Homebrew needed).${NC}\n"

        if xcode-select -p &>/dev/null; then
            # CLT path exists but git still isn't on PATH — unusual, but
            # handle it rather than assume. Re-trigger install to repair.
            echo -e "${YELLOW}[i] Command Line Tools appear to be present but 'git' wasn't found.${NC}"
            echo -e "${CYAN}    Attempting to repair the CLT install...${NC}"
        fi

        echo -e "${YELLOW}${BOLD}[!] A native macOS dialog is about to appear.${NC}"
        echo -e "${YELLOW}    Click \"Install\" on it (this is Apple's own installer, not git-wizard's —${NC}"
        echo -e "${YELLOW}    there is no way to script around this specific first-time prompt).${NC}\n"

        xcode-select --install 2>/dev/null

        echo -e "${CYAN}--> Waiting for Command Line Tools installation to complete...${NC}"
        echo -e "${CYAN}    (This runs in its own window. Come back here once it finishes.)${NC}\n"

        # Poll rather than block forever — xcode-select --install itself
        # returns almost immediately (it just launches the GUI installer),
        # so we watch for `git` to actually appear rather than trusting a
        # fixed sleep. Capped at ~10 minutes to avoid hanging indefinitely
        # if the user closes the dialog without installing.
        local waited=0
        local max_wait=600
        while ! command -v git &>/dev/null && [[ $waited -lt $max_wait ]]; do
            sleep 5
            waited=$((waited + 5))
            if (( waited % 30 == 0 )); then
                echo -e "${CYAN}    ...still waiting (${waited}s elapsed, up to ${max_wait}s)${NC}"
            fi
        done

        if command -v git &>/dev/null; then
            echo -e "${GREEN}[✔] git installed successfully via Command Line Tools.${NC}"
            log_action "Bootstrapped git via macOS Command Line Tools"
            return 0
        fi

        echo -e "${YELLOW}[i] Command Line Tools install didn't complete (timed out or was cancelled).${NC}"
        echo -e "${CYAN}--> Falling back to Homebrew...${NC}"
        # falls through to the shared Homebrew fallback below
    fi

    # --------------------------------------------------------------------
    # Linux — native package manager fast path.
    # --------------------------------------------------------------------
    if [[ "$os" != "Darwin" ]]; then
        local pm
        pm=$(detect_pkg_manager)
        case "$pm" in
            apt)
                echo -e "${CYAN}--> Running: sudo apt update && sudo apt install -y git${NC}"
                sudo apt update && sudo apt install -y git
                ;;
            dnf)
                echo -e "${CYAN}--> Running: sudo dnf install -y git${NC}"
                sudo dnf install -y git
                ;;
            pacman)
                echo -e "${CYAN}--> Running: sudo pacman -Sy --noconfirm git${NC}"
                sudo pacman -Sy --noconfirm git
                ;;
            brew)
                echo -e "${CYAN}--> Running: brew install git${NC}"
                brew install git
                ;;
            *)
                echo -e "${YELLOW}[i] No supported native package manager detected.${NC}"
                ;;
        esac

        if command -v git &>/dev/null; then
            echo -e "${GREEN}[✔] git installed successfully via ${pm}.${NC}"
            return 0
        fi
        echo -e "${YELLOW}[i] Native package manager install failed or unavailable.${NC}"
        echo -e "${CYAN}--> Falling back to Homebrew (works on Linux too, no sudo required)...${NC}"
    fi

    # --------------------------------------------------------------------
    # Shared fallback for BOTH platforms: Homebrew.
    # --------------------------------------------------------------------
    if ! command -v brew &>/dev/null; then
        echo -e "${CYAN}    Installing Homebrew first...${NC}"
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Surface brew into THIS session immediately regardless of platform
        # or CPU architecture — covers Apple Silicon, Intel Mac, and Linux.
        if [[ -d "/opt/homebrew/bin" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"                      # Apple Silicon Mac
        elif [[ -d "/usr/local/bin" ]] && [[ -x "/usr/local/bin/brew" ]]; then
            eval "$(/usr/local/bin/brew shellenv)"                        # Intel Mac
        elif [[ -d "/home/linuxbrew/.linuxbrew/bin" ]]; then
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"        # Linux
        elif [[ -d "${HOME}/.linuxbrew/bin" ]]; then
            eval "$(${HOME}/.linuxbrew/bin/brew shellenv)"                # Linux (user-local)
        fi
    fi

    if command -v brew &>/dev/null; then
        brew install git
        hash -r 2>/dev/null || true
    fi

    if command -v git &>/dev/null; then
        echo -e "${GREEN}[✔] git installed successfully via Homebrew fallback.${NC}"
        log_action "Bootstrapped git via Homebrew fallback"
        return 0
    fi

    echo -e "${RED}[!] Could not install git automatically through any method.${NC}"
    if [[ "$os" == "Darwin" ]]; then
        echo -e "${YELLOW}    Please finish the Command Line Tools install manually (Apple menu ->${NC}"
        echo -e "${YELLOW}    check for a pending install dialog), or install Homebrew yourself from${NC}"
        echo -e "${YELLOW}    https://brew.sh, then re-run git-wizard.${NC}"
    else
        echo -e "${YELLOW}    Please install git manually for your distro, then re-run git-wizard.${NC}"
    fi
    return 1
}
# Package names differ per manager for some tools (e.g. delta -> git-delta, gh -> github-cli on Arch)
get_package_name() {
    local tool="$1" pm="$2"
    case "$tool" in
        delta)
            case "$pm" in
                apt|dnf|brew) echo "git-delta" ;;
                pacman)       echo "git-delta" ;;
                *)            echo "$tool" ;;
            esac
            ;;
        gh)
            case "$pm" in
                pacman) echo "github-cli" ;;
                *)      echo "gh" ;;
            esac
            ;;
        glab)
            case "$pm" in
                *) echo "glab" ;;
            esac
            ;;
        *) echo "$tool" ;;
    esac
}

get_install_command() {
    local tool="$1" pm="$2"
    local pkg
    pkg=$(get_package_name "$tool" "$pm")
    case "$pm" in
        apt)    echo "sudo apt update && sudo apt install -y ${pkg}" ;;
        dnf)    echo "sudo dnf install -y ${pkg}" ;;
        pacman) echo "sudo pacman -Sy --noconfirm ${pkg}" ;;
        brew)   echo "brew install ${pkg}" ;;
        *)      echo "" ;;
    esac
}

suggest_install() {
    local tool="$1"
    local pm
    pm=$(detect_pkg_manager)
    echo -e "${YELLOW}[i] '${tool}' is not installed.${NC}"
    local cmd
    cmd=$(get_install_command "$tool" "$pm")
    if [[ -n "$cmd" ]]; then
        echo -e "    Install with: ${GREEN}${cmd}${NC}"
    else
        echo -e "    Please install '${tool}' using your system's package manager."
    fi
}

# Actually offers to run the install command, not just print it.
offer_install() {
    local tool="$1"
    local pm
    pm=$(detect_pkg_manager)

    if [[ "$pm" != "unknown" ]]; then
        local cmd
        cmd=$(get_install_command "$tool" "$pm")
        echo -e "  ${CYAN}    Detected package manager: ${pm}${NC}"
        echo -e "  ${CYAN}    Option A (repository): ${GREEN}${cmd}${NC}"
        read -e -p "      Install '${tool}' from the repository now? (y/N): " DOINSTALL
        if [[ "$DOINSTALL" =~ ^[Yy]$ ]]; then
            echo -e "  ${CYAN}--> Running: ${cmd}${NC}"
            if eval "$cmd"; then
                echo -e "  ${GREEN}[✔] '${tool}' installed successfully via ${pm}.${NC}"
                log_action "Installed optional tool: ${tool} (via ${pm})"
                return
            else
                echo -e "  ${RED}[!] Repository install failed (package may not exist in this repo, or needs sudo/permissions).${NC}"
                log_action "FAILED repo install of optional tool: ${tool} (via ${pm})"
            fi
        else
            echo -e "  ${YELLOW}[i] Skipped repository install.${NC}"
        fi
    else
        echo -e "  ${RED}[!] Could not detect a supported package manager (apt/dnf/pacman/brew).${NC}"
    fi

    # Fallback path: pull a prebuilt binary directly from the tool's GitHub releases.
    case "$tool" in
        gh|delta|glab|git-absorb|ghq|jq)
            read -e -p "      Try pulling a prebuilt binary from GitHub releases instead? (y/N): " DOBINARY
            if [[ "$DOBINARY" =~ ^[Yy]$ ]]; then
                install_from_binary "$tool"
            else
                echo -e "  ${YELLOW}[i] Skipped. Install '${tool}' manually anytime.${NC}"
            fi
            ;;
        chafa)
            echo -e "  ${YELLOW}[i] chafa doesn't publish static binaries — it's source-tarball-only upstream.${NC}"
            if command -v snap &>/dev/null; then
                read -e -p "      Try installing via snap instead? (y/N): " DOSNAP
                if [[ "$DOSNAP" =~ ^[Yy]$ ]]; then
                    sudo snap install chafa && echo -e "  ${GREEN}[✔] chafa installed via snap.${NC}" || echo -e "  ${RED}[!] snap install failed.${NC}"
                fi
            else
                echo -e "  ${CYAN}    No snap available either — build from source: https://github.com/hpjansson/chafa/releases${NC}"
            fi
            ;;
        lazygit|act)
            read -e -p "      Try pulling a prebuilt binary from GitHub releases instead? (y/N): " DOBINARY
            if [[ "$DOBINARY" =~ ^[Yy]$ ]]; then
                install_from_binary "$tool"
            else
                echo -e "  ${YELLOW}[i] Skipped. Install '${tool}' manually anytime.${NC}"
            fi
            ;;
        *)
            echo -e "  ${YELLOW}[i] No prebuilt binary releases available for '${tool}' — repository/source install is the only option.${NC}"
            ;;
    esac
}

# ==============================================================================
# BINARY-PULL FALLBACK
# Downloads a prebuilt release binary directly from GitHub when the
# distro's repository doesn't carry the package (or install failed).
# Installs into ~/.local/bin (created if missing, no sudo required).
# ==============================================================================
detect_binary_arch() {
    local kind="$1"  # "gh_style" or "gnu_target"
    local m
    m=$(uname -m)
    local os
    os=$(uname -s)

    if [[ "$kind" == "gh_style" ]]; then
        case "$m" in
            x86_64|amd64) echo "amd64" ;;
            aarch64|arm64) echo "arm64" ;;
            *) echo "" ;;
        esac
    else
        case "$m" in
            x86_64|amd64) echo "x86_64-unknown-linux-gnu" ;;
            aarch64|arm64) echo "aarch64-unknown-linux-gnu" ;;
            *) echo "" ;;
        esac
    fi
}

fetch_latest_release_tag() {
    local repo="$1"       # e.g. "cli/cli"
    local fallback="$2"   # hardcoded fallback tag if API call fails/rate-limited
    local tag
    tag=$(curl -fsSL --max-time 10 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
          | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')
    if [[ -z "$tag" ]]; then
        echo -e "  ${YELLOW}[i] Could not reach/parse GitHub API (rate-limited or offline). Falling back to a known-good version: ${fallback}${NC}" >&2
        tag="$fallback"
    fi
    echo "$tag"
}

# ==============================================================================
# SHARED BINARY FETCHER — used by install_from_binary() for every tool, on
# both Linux and macOS. Handles raw-binary downloads, .tar.gz, and .zip
# uniformly so each tool's case block only has to supply a URL + filenames.
# ==============================================================================
_gw_fetch_and_install_binary() {
    # $1=install_dir $2=url $3=archive_type(tar|zip|raw) $4=find_name $5=install_as $6=log_label
    local install_dir="$1" url="$2" atype="$3" findname="$4" installas="$5" label="$6"
    local tmpdir
    tmpdir=$(mktemp -d)
    echo -e "  ${CYAN}--> Downloading: ${url}${NC}"

    if [[ "$atype" == "raw" ]]; then
        if curl -fsSL --max-time 60 "$url" -o "${install_dir}/${installas}"; then
            chmod +x "${install_dir}/${installas}"
            echo -e "  ${GREEN}[✔] ${installas} installed to ${install_dir}/${installas}${NC}"
            log_action "Installed ${label} via binary pull"
            rm -rf "$tmpdir"; return 0
        else
            echo -e "  ${RED}[!] Download failed. Check your connection or try the repository/brew install instead.${NC}"
            rm -rf "$tmpdir"; return 1
        fi
    fi

    local archfile="${tmpdir}/dl.${atype}"
    if ! curl -fsSL --max-time 60 "$url" -o "$archfile"; then
        echo -e "  ${RED}[!] Download failed. Check your connection or try the repository/brew install instead.${NC}"
        rm -rf "$tmpdir"; return 1
    fi

    if [[ "$atype" == "zip" ]]; then
        if ! command -v unzip &>/dev/null; then
            echo -e "  ${RED}[!] 'unzip' is required for this download (brew install unzip / apt install unzip).${NC}"
            rm -rf "$tmpdir"; return 1
        fi
        unzip -q "$archfile" -d "$tmpdir"
    else
        tar -xzf "$archfile" -C "$tmpdir" 2>/dev/null
    fi

    local binpath
    binpath=$(find "$tmpdir" -type f -name "$findname" | head -1)
    if [[ -n "$binpath" ]]; then
        cp "$binpath" "${install_dir}/${installas}"
        chmod +x "${install_dir}/${installas}"
        echo -e "  ${GREEN}[✔] ${installas} installed to ${install_dir}/${installas}${NC}"
        log_action "Installed ${label} via binary pull"
        rm -rf "$tmpdir"; return 0
    else
        echo -e "  ${RED}[!] Downloaded archive but couldn't locate the '${findname}' binary inside it.${NC}"
        rm -rf "$tmpdir"; return 1
    fi
}
install_from_binary() {
    local tool="$1"
    local install_dir="${HOME}/.local/bin"
    mkdir -p "$install_dir"

    local os m
    os=$(uname -s)
    m=$(uname -m)

    if [[ "$os" != "Linux" && "$os" != "Darwin" ]]; then
        echo -e "  ${YELLOW}[i] Binary auto-install currently supports Linux and macOS only.${NC}"
        return
    fi

    # Two arch-naming families seen across these tools' release assets:
    #   gnu_target: x86_64-unknown-linux-gnu / x86_64-apple-darwin  (delta, git-absorb)
    #   gh_style:   amd64 / arm64                                   (gh, glab, ghq)
    #   x86_style:  x86_64 / arm64                                  (lazygit, act, jq mac)
    local gnu_target="" gh_arch="" x86_arch=""
    if [[ "$os" == "Linux" ]]; then
        case "$m" in
            x86_64|amd64)  gnu_target="x86_64-unknown-linux-gnu";  gh_arch="amd64"; x86_arch="x86_64" ;;
            aarch64|arm64) gnu_target="aarch64-unknown-linux-gnu"; gh_arch="arm64"; x86_arch="arm64"  ;;
            *) echo -e "  ${RED}[!] Unsupported CPU architecture (${m}) for binary pull.${NC}"; return ;;
        esac
    else
        case "$m" in
            x86_64|amd64) gnu_target="x86_64-apple-darwin";  gh_arch="amd64"; x86_arch="x86_64" ;;
            arm64)        gnu_target="aarch64-apple-darwin"; gh_arch="arm64"; x86_arch="arm64"  ;;
            *) echo -e "  ${RED}[!] Unsupported CPU architecture (${m}) for binary pull.${NC}"; return ;;
        esac
    fi

    case "$tool" in
        gh)
            local tag ver url atype
            tag=$(fetch_latest_release_tag "cli/cli" "v2.63.0"); ver="${tag#v}"
            if [[ "$os" == "Darwin" ]]; then
                url="https://github.com/cli/cli/releases/download/${tag}/gh_${ver}_macOS_${gh_arch}.zip"; atype="zip"
            else
                url="https://github.com/cli/cli/releases/download/${tag}/gh_${ver}_linux_${gh_arch}.tar.gz"; atype="tar"
            fi
            _gw_fetch_and_install_binary "$install_dir" "$url" "$atype" "gh" "gh" "gh (${tag})"
            ;;
        delta)
            local tag ver url
            tag=$(fetch_latest_release_tag "dandavison/delta" "0.18.2"); ver="${tag#v}"
            url="https://github.com/dandavison/delta/releases/download/${tag}/delta-${ver}-${gnu_target}.tar.gz"
            _gw_fetch_and_install_binary "$install_dir" "$url" "tar" "delta" "delta" "delta (${tag})"
            ;;
        glab)
            local tag ver url platform
            tag=$(curl -fsSL --max-time 10 "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases?per_page=1&order_by=released_at&sort=desc" 2>/dev/null \
                  | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')
            [[ -z "$tag" ]] && tag="v1.51.0"
            ver="${tag#v}"
            [[ "$os" == "Darwin" ]] && platform="darwin" || platform="linux"
            url="https://gitlab.com/gitlab-org/cli/-/releases/${tag}/downloads/glab_${ver}_${platform}_${gh_arch}.tar.gz"
            _gw_fetch_and_install_binary "$install_dir" "$url" "tar" "glab" "glab" "glab (${tag})"
            ;;
        git-absorb)
            local tag url
            tag=$(fetch_latest_release_tag "tummychow/git-absorb" "0.6.11")
            url="https://github.com/tummychow/git-absorb/releases/download/${tag}/git-absorb-${gnu_target}"
            _gw_fetch_and_install_binary "$install_dir" "$url" "raw" "" "git-absorb" "git-absorb (${tag})"
            [[ $? -ne 0 ]] && echo -e "  ${CYAN}    Alternative: cargo install git-absorb (needs Rust)${NC}"
            ;;
        jq)
            local tag url platform
            tag=$(fetch_latest_release_tag "jqlang/jq" "jq-1.7.1")
            [[ "$os" == "Darwin" ]] && platform="macos" || platform="linux"
            url="https://github.com/jqlang/jq/releases/download/${tag}/jq-${platform}-${gh_arch}"
            _gw_fetch_and_install_binary "$install_dir" "$url" "raw" "" "jq" "jq (${tag})"
            ;;
        ghq)
            local tag url platform
            tag=$(fetch_latest_release_tag "x-motemen/ghq" "v1.7.1")
            [[ "$os" == "Darwin" ]] && platform="darwin" || platform="linux"
            url="https://github.com/x-motemen/ghq/releases/download/${tag}/ghq_${platform}_${gh_arch}.zip"
            _gw_fetch_and_install_binary "$install_dir" "$url" "zip" "ghq" "ghq" "ghq (${tag})"
            ;;
        lazygit)
            local tag ver url platform
            tag=$(fetch_latest_release_tag "jesseduffield/lazygit" "v0.44.1"); ver="${tag#v}"
            [[ "$os" == "Darwin" ]] && platform="Darwin" || platform="Linux"
            url="https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_${platform}_${x86_arch}.tar.gz"
            _gw_fetch_and_install_binary "$install_dir" "$url" "tar" "lazygit" "lazygit" "lazygit (${tag})"
            ;;
        act)
            local tag url platform
            tag=$(fetch_latest_release_tag "nektos/act" "v0.2.68")
            [[ "$os" == "Darwin" ]] && platform="Darwin" || platform="Linux"
            url="https://github.com/nektos/act/releases/download/${tag}/act_${platform}_${x86_arch}.tar.gz"
            _gw_fetch_and_install_binary "$install_dir" "$url" "tar" "act" "act" "act (${tag})"
            ;;
    esac

    if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
        export PATH="${install_dir}:$PATH"
        hash -r 2>/dev/null || true
        local path_line="export PATH=\"${install_dir}:\$PATH\""
        for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
            touch "$rc" 2>/dev/null
            if ! grep -qF "$path_line" "$rc" 2>/dev/null; then
                {
                    echo ''
                    echo '# Added by git-wizard: makes binary-installed tools (gh/delta/glab/etc) available'
                    echo "$path_line"
                } >> "$rc" 2>/dev/null
            fi
        done
        echo -e "  ${GREEN}[✔] ${install_dir} added to PATH for this session AND future terminals.${NC}"
        log_action "PATH updated in-session + persisted: ${install_dir}"
    fi
}

check_optional_tools() {
    show_header
    echo -e "${YELLOW}${BOLD}🔎 CROSS-DISTRO TOOL VERIFICATION${NC}\n"
    for tool in gh glab delta chafa; do
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}[✔] ${tool} — installed${NC}"
        else
            echo -e "  ${RED}[✘] ${tool} — missing${NC}"
            offer_install "$tool"
            echo ""
        fi
    done
    pause
}

# ==============================================================================
# SELF-UPDATE CHECK
# Compares SCRIPT_VERSION against the latest release tag of UPDATE_REPO.
# Non-blocking on startup (cached for 24h), full manual check via Settings.
# ==============================================================================
version_is_newer() {
    # returns 0 (true) if $1 > $2, using simple numeric dot-comparison
    local a="$1" b="$2"
    if [[ "$a" == "$b" ]]; then return 1; fi
    local IFS=.
    local -a va=($a) vb=($b)
    local i
    for ((i=0; i<3; i++)); do
        local na=${va[i]:-0} nb=${vb[i]:-0}
        if ((10#$na > 10#$nb)); then return 0; fi
        if ((10#$na < 10#$nb)); then return 1; fi
    done
    return 1
}

configure_update_repo() {
    show_header
    echo -e "${YELLOW}${BOLD}⚙️ SELF-UPDATE SOURCE${NC}\n"
    echo -e "Current: ${CYAN}${UPDATE_REPO:-not set}${NC}\n"
    echo -e "Enter your GitHub repo in the form ${GREEN}username/repo-name${NC} (the one this script lives in)."
    read -e -p "Repo (ENTER to leave unchanged): " NEWREPO
    if [[ -n "$NEWREPO" ]]; then
        UPDATE_REPO="$NEWREPO"
        save_config
        echo -e "${GREEN}[✔] Update source set to: ${UPDATE_REPO}${NC}"
    fi
    pause
}

check_for_updates() {
    local silent="$1"  # "silent" = only print if update found (used on startup)

    if [[ -z "$UPDATE_REPO" ]]; then
        if [[ "$silent" != "silent" ]]; then
            echo -e "${YELLOW}[i] No update source configured yet.${NC}"
            configure_update_repo
        fi
        return
    fi

    local api_response http_code body latest
    api_response=$(curl -sS --max-time 8 -w '\n%{http_code}' "https://api.github.com/repos/${UPDATE_REPO}/releases/latest" 2>&1)
    http_code=$(echo "$api_response" | tail -1)
    body=$(echo "$api_response" | sed '$d')

    LAST_UPDATE_CHECK=$(date +%s)
    save_config

    if [[ "$http_code" == "000" || -z "$http_code" ]]; then
        if [[ "$silent" != "silent" ]]; then
            echo -e "${YELLOW}[i] Could not reach GitHub — check your network connection.${NC}"
        fi
        return
    elif [[ "$http_code" == "404" ]]; then
        if [[ "$silent" != "silent" ]]; then
            echo -e "${YELLOW}[i] '${UPDATE_REPO}' is reachable but has no published Releases yet.${NC}"
            echo -e "${CYAN}    (Pushing commits/tags isn't the same as a Release. Create one on GitHub: Releases -> Draft a new release.)${NC}"
        fi
        return
    elif [[ "$http_code" == "403" ]]; then
        if [[ "$silent" != "silent" ]]; then
            echo -e "${YELLOW}[i] GitHub API rate limit hit for your IP. Try again later.${NC}"
        fi
        return
    elif [[ "$http_code" != "200" ]]; then
        if [[ "$silent" != "silent" ]]; then
            echo -e "${YELLOW}[i] Unexpected response from GitHub (HTTP ${http_code}).${NC}"
        fi
        return
    fi

    latest=$(echo "$body" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"v?([^"]+)".*/\1/')
    if [[ -z "$latest" ]]; then
        if [[ "$silent" != "silent" ]]; then
            echo -e "${YELLOW}[i] Got a response from GitHub but couldn't parse a version tag out of it.${NC}"
        fi
        return
    fi

    if version_is_newer "$latest" "$SCRIPT_VERSION"; then
        UPDATE_NOTICE="🎉 Update available: v${latest} (you have v${SCRIPT_VERSION}) — https://github.com/${UPDATE_REPO}/releases/latest"
        if [[ "$silent" != "silent" ]]; then
            echo -e "${GREEN}${BOLD}${UPDATE_NOTICE}${NC}"
        fi
    else
        UPDATE_NOTICE=""
        if [[ "$silent" != "silent" ]]; then
            echo -e "${GREEN}[✔] You're up to date (v${SCRIPT_VERSION}).${NC}"
        fi
    fi
}

maybe_auto_check_updates() {
    [[ -z "$UPDATE_REPO" ]] && return
    local now
    now=$(date +%s)
    if [[ -z "$LAST_UPDATE_CHECK" ]]; then
        check_for_updates silent
        return
    fi
    local elapsed=$(( now - LAST_UPDATE_CHECK ))
    if (( elapsed > 86400 )); then
        check_for_updates silent
    fi
}

# ==============================================================================
# PRE-COMMIT HOOKS SETUP
# Installs the 'pre-commit' framework (if missing), writes a sensible default
# .pre-commit-config.yaml for THIS repo, and activates the git hook.
# ==============================================================================
# ==============================================================================
# SELF-UPDATE / ROLLBACK — updates git-wizard's OWN installation (SCRIPT_DIR),
# never touches any of the user's other project repos. Every update tags the
# current state first, so rollback is always available.
# ==============================================================================
update_git_wizard() {
    show_header
    echo -e "${YELLOW}${BOLD}⬆️  UPDATE GIT-WIZARD${NC}\n"

    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}[!] $SCRIPT_DIR isn't a git repository — git-wizard wasn't installed via 'git clone'.${NC}"
        echo -e "${CYAN}    Re-download the latest version manually from your GitHub/GitLab repo instead.${NC}"
        pause
        return
    fi

    if [[ -z "$UPDATE_REPO" ]]; then
        echo -e "${YELLOW}[i] No update source configured yet.${NC}"
        configure_update_repo
        [[ -z "$UPDATE_REPO" ]] && { pause; return; }
    fi

    local branch
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
        echo -e "${RED}[!] You have uncommitted local changes in the git-wizard install directory itself.${NC}"
        echo -e "${CYAN}    (This is separate from your project repos — it means you edited git-wizard.sh directly.)${NC}"
        echo -e "${CYAN}    Commit or discard those first, or updating could conflict.${NC}"
        pause
        return
    fi

    local backup_tag="tool-backup-$(date '+%Y%m%d-%H%M%S')"
    git -C "$SCRIPT_DIR" tag "$backup_tag" HEAD
    echo -e "${GREEN}[✔] Safety tag created: ${CYAN}${backup_tag}${NC} ${GREEN}(this is how you'll roll back if the update has a bug)${NC}\n"
    log_action "Tool self-update: created backup tag ${backup_tag}"

    echo -e "${CYAN}--> Fetching latest from ${UPDATE_REPO}...${NC}"
    if ! git -C "$SCRIPT_DIR" fetch origin "$branch" 2>&1; then
        echo -e "${RED}[!] Fetch failed. Check your connection. No changes were made (backup tag is harmless if unused).${NC}"
        pause
        return
    fi

    echo -e "${CYAN}--> Pulling latest changes into ${SCRIPT_DIR}...${NC}"
    if git -C "$SCRIPT_DIR" pull origin "$branch" 2>&1; then
        echo -e "\n${GREEN}${BOLD}[✔] git-wizard updated successfully.${NC}"
        echo -e "${CYAN}    Restart git-wizard to use the new version.${NC}"
        echo -e "${CYAN}    If this update causes a problem, use Settings > Rollback git-wizard — pick '${backup_tag}'.${NC}"
        log_action "Tool self-update: pulled latest (backup: ${backup_tag})"
    else
        echo -e "\n${RED}[!] Pull failed (possibly a conflict). Nothing was lost — roll back with:${NC}"
        echo -e "${GREEN}    git -C \"${SCRIPT_DIR}\" reset --hard ${backup_tag}${NC}"
    fi
    pause
}

create_tool_checkpoint() {
    show_header
    echo -e "${YELLOW}${BOLD}📍 CREATE A GIT-WIZARD CHECKPOINT${NC}\n"

    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}[!] $SCRIPT_DIR isn't a git repository — checkpoints need it to be a git clone.${NC}"
        pause
        return
    fi

    echo -e "${CYAN}This saves the CURRENT state of git-wizard itself as a rollback point —${NC}"
    echo -e "${CYAN}useful before you manually edit the script, even if you're not updating right now.${NC}\n"

    local backup_tag="tool-backup-$(date '+%Y%m%d-%H%M%S')"
    if git -C "$SCRIPT_DIR" tag "$backup_tag" HEAD 2>&1; then
        echo -e "${GREEN}[✔] Checkpoint created: ${CYAN}${backup_tag}${NC}"
        echo -e "${CYAN}    Roll back to it anytime via Settings > Rollback git-wizard.${NC}"
        log_action "Manual tool checkpoint created: ${backup_tag}"
    else
        echo -e "${RED}[!] Couldn't create the checkpoint tag.${NC}"
    fi
    pause
}

rollback_git_wizard() {
    show_header
    echo -e "${YELLOW}${BOLD}⏪ ROLLBACK GIT-WIZARD TO A PREVIOUS VERSION${NC}\n"

    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}[!] $SCRIPT_DIR isn't a git repository — nothing to roll back.${NC}"
        pause
        return
    fi

    local tag_lines=()
    while IFS= read -r t; do
        [[ -n "$t" ]] && tag_lines+=("tag"$'\t'"$t")
    done < <(git -C "$SCRIPT_DIR" tag -l 'tool-backup-*' --sort=-creatordate)

    if [[ ${#tag_lines[@]} -eq 0 ]]; then
        echo -e "${YELLOW}[i] No backup tags found yet — rollback points are only created when you run 'Update git-wizard'.${NC}"
        pause
        return
    fi

    if ! select_from_lines_interactive "📌 SELECT A BACKUP TO ROLL BACK TO" "${tag_lines[@]}"; then
        pause
        return
    fi
    local tag="${SELECTED_LINE#*$'\t'}"

    show_header
    echo -e "${YELLOW}${BOLD}⏪ ROLLBACK TO: ${tag}${NC}\n"
    echo -e "${CYAN}This only affects the git-wizard TOOL itself (${SCRIPT_DIR}).${NC}"
    echo -e "${CYAN}It does NOT touch any of your other project repos or their local files.${NC}\n"

    if confirm_destructive "Roll back git-wizard to ${tag} — any changes made to the tool since then are discarded"; then
        if git -C "$SCRIPT_DIR" reset --hard "$tag"; then
            echo -e "\n${GREEN}[✔] Rolled back to ${tag}.${NC}"
            echo -e "${CYAN}    Restart git-wizard to use this version.${NC}"
            log_action "Tool rolled back to ${tag}"
        else
            echo -e "${RED}[!] Rollback failed.${NC}"
        fi
    fi
    pause
}

setup_precommit_hooks() {
    show_header
    echo -e "${YELLOW}${BOLD}🪝 PRE-COMMIT HOOKS SETUP${NC}\n"

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}[!] Not inside a Git repository. cd into one first.${NC}"
        pause
        return
    fi

    if ! command -v pre-commit &>/dev/null; then
        echo -e "${YELLOW}[i] 'pre-commit' is not installed.${NC}"

        local installed_ok="false"

        if command -v pipx &>/dev/null; then
            echo -e "  ${CYAN}Detected pipx (best option on Kali/Debian). Install with: ${GREEN}pipx install pre-commit${NC}"
            read -e -p "  Install now via pipx? (y/N): " DOPIPX
            if [[ "$DOPIPX" =~ ^[Yy]$ ]]; then
                if pipx install pre-commit; then
                    echo -e "  ${GREEN}[✔] pre-commit installed via pipx.${NC}"
                    log_action "Installed pre-commit via pipx"
                    installed_ok="true"
                else
                    echo -e "  ${RED}[!] pipx install failed.${NC}"
                fi
            fi
        fi

        if [[ "$installed_ok" != "true" ]] && (command -v pip3 &>/dev/null || command -v pip &>/dev/null); then
            local pipcmd="pip3"
            command -v pip3 &>/dev/null || pipcmd="pip"
            echo -e "  ${CYAN}Fallback: ${GREEN}${pipcmd} install --user --break-system-packages pre-commit${NC}"
            echo -e "  ${YELLOW}(Kali/Debian block plain pip installs system-wide — PEP 668 — this flag opts you into a safe user-level install.)${NC}"
            read -e -p "  Install now? (y/N): " DOPIP
            if [[ "$DOPIP" =~ ^[Yy]$ ]]; then
                if "$pipcmd" install --user --break-system-packages pre-commit; then
                    echo -e "  ${GREEN}[✔] pre-commit installed.${NC}"
                    log_action "Installed pre-commit via ${pipcmd} --break-system-packages"
                    installed_ok="true"
                else
                    echo -e "  ${RED}[!] pip install failed even with --break-system-packages.${NC}"
                fi
            fi
        fi

        if [[ "$installed_ok" != "true" ]] && ! command -v pipx &>/dev/null && ! command -v pip3 &>/dev/null && ! command -v pip &>/dev/null; then
            echo -e "  ${RED}[!] No pip/pip3/pipx found. Install one first, e.g.: ${GREEN}sudo apt install pipx${NC}"
            echo -e "      Or see: https://pre-commit.com/#install"
        fi

        if [[ "$installed_ok" != "true" ]]; then
            echo -e "  ${YELLOW}[i] pre-commit not installed. Come back once it's set up.${NC}"
            pause
            return
        fi
    fi

    # Re-check PATH visibility after a --user/pipx install
    if ! command -v pre-commit &>/dev/null; then
        echo -e "${YELLOW}[i] pre-commit installed but not on PATH yet.${NC}"
        echo -e "    Try: ${GREEN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC} then re-run this option."
        pause
        return
    fi

    local config_path="${TARGET_REPO_DIR}/.pre-commit-config.yaml"
    if [[ -f "$config_path" ]]; then
        echo -e "${GREEN}[✔] .pre-commit-config.yaml already exists in this repo.${NC}"
    else
        echo -e "${CYAN}--> Writing a sensible default .pre-commit-config.yaml...${NC}"
        cat > "$config_path" <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: check-merge-conflict
EOF
        echo -e "${GREEN}[✔] .pre-commit-config.yaml created.${NC}"
        log_action "Created .pre-commit-config.yaml"
    fi

    echo -e "${CYAN}--> Activating git hook (pre-commit install)...${NC}"
    if pre-commit install; then
        echo -e "${GREEN}[✔] Pre-commit hooks are now active for this repo.${NC}"
        echo -e "${CYAN}    Edit .pre-commit-config.yaml anytime to add more hooks (e.g. black, prettier, eslint).${NC}"
        log_action "pre-commit hooks activated for ${TARGET_REPO_DIR}"
    else
        echo -e "${RED}[!] Failed to activate hooks. Check the output above.${NC}"
    fi
    pause
}

# ==============================================================================
# HEADER / SYNC STATUS BAR
# ==============================================================================
get_sync_status() {
    if ! git -C "$TARGET_REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo ""
        return
    fi
    local branch
    branch=$(git -C "$TARGET_REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    [[ -z "$branch" ]] && { echo ""; return; }

    local fetch_ok="true"
    if ! git -C "$TARGET_REPO_DIR" fetch --quiet 2>/dev/null; then
        fetch_ok="false"
    fi

    local upstream
    upstream=$(git -C "$TARGET_REPO_DIR" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null || echo "")
    if [[ -z "$upstream" ]]; then
        echo -e "${YELLOW}🔄 ${branch}: no upstream tracking set${NC}"
        return
    fi

    local ahead behind
    ahead=$(git -C "$TARGET_REPO_DIR" rev-list --count "${upstream}..${branch}" 2>/dev/null || echo 0)
    behind=$(git -C "$TARGET_REPO_DIR" rev-list --count "${branch}..${upstream}" 2>/dev/null || echo 0)

    # --- Working tree state: split modified vs untracked ---
    local status_out modified_count untracked_count dirty_count
    status_out=$(git -C "$TARGET_REPO_DIR" status --porcelain 2>/dev/null)
    modified_count=$(echo "$status_out" | grep -vc '^??' 2>/dev/null); modified_count=${modified_count:-0}
    untracked_count=$(echo "$status_out" | grep -c '^??' 2>/dev/null); untracked_count=${untracked_count:-0}
    [[ -z "$status_out" ]] && { modified_count=0; untracked_count=0; }
    dirty_count=$((modified_count + untracked_count))

    # --- Severity tier: green (synced) / yellow (ahead only) / orange (behind) / red (dirty+behind) ---
    local color icon status_text
    if [[ "$dirty_count" -gt 0 && "$behind" -gt 0 ]]; then
        color="$RED"; icon="🔴"; status_text="High risk — uncommitted work AND remote has moved on"
    elif [[ "$behind" -gt 0 ]]; then
        color="\033[0;33m"; icon="🟠"; status_text="Behind — pull recommended"   # orange
    elif [[ "$ahead" -gt 0 ]]; then
        color="$YELLOW"; icon="🟡"; status_text="Ahead — push when ready"
    elif [[ "$dirty_count" -gt 0 ]]; then
        color="$YELLOW"; icon="🟡"; status_text="Uncommitted local changes"
    else
        color="$GREEN"; icon="✅"; status_text="Fully synced"
    fi

    local line="${color}🔄 ${branch}: ${icon} ${status_text}  (⬆️ ${ahead} ahead  ⬇️ ${behind} behind, ${upstream})${NC}"

    if [[ "$fetch_ok" != "true" ]]; then
        line="${line}\n${RED}🚫 Last fetch failed — the numbers above may be stale (check network)${NC}"
    else
        line="${line}\n${GREEN}🌐 Remote reachable — data is current${NC}"
    fi

    if [[ "$dirty_count" -gt 0 ]]; then
        line="${line}\n${RED}⚠️  ✏️ ${modified_count} modified   ➕ ${untracked_count} untracked — not yet committed or pushed${NC}"
    fi

    if [[ "$branch" == "main" || "$branch" == "master" ]] && [[ "$dirty_count" -gt 0 || "$ahead" -gt 0 ]]; then
        line="${line}\n${RED}⚠️  Uncommitted/unpushed work directly on '${branch}' — consider a feature branch (Module 5)${NC}"
    fi

    if [[ "$SYNC_DETAIL_LEVEL" == "standard" || "$SYNC_DETAIL_LEVEL" == "full" ]]; then
        local stash_count
        stash_count=$(git -C "$TARGET_REPO_DIR" stash list 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$stash_count" -gt 0 ]]; then
            line="${line}\n${CYAN}📦 ${stash_count} stash(es) saved — don't forget these${NC}"
        fi

        local last_commit_rel
        last_commit_rel=$(git -C "$TARGET_REPO_DIR" log -1 --format='%cr' 2>/dev/null || echo "")
        if [[ -n "$last_commit_rel" ]]; then
            line="${line}\n${CYAN}🕐 Last commit: ${last_commit_rel}${NC}"
        fi
    fi

    if [[ "$SYNC_DETAIL_LEVEL" == "full" && "$behind" -gt 0 ]]; then
        if git -C "$TARGET_REPO_DIR" merge-tree "$(git -C "$TARGET_REPO_DIR" merge-base "$branch" "$upstream")" "$branch" "$upstream" 2>/dev/null | grep -q "^<<<<<<< "; then
            line="${line}\n${RED}⚠️  Pulling may CONFLICT — review before Safe Update Sync${NC}"
        else
            line="${line}\n${GREEN}✅ Pull will likely be clean (no conflict markers detected)${NC}"
        fi
    fi

    line="${line}\n${CYAN}🔧 Detail Level: ${SYNC_DETAIL_LEVEL}  (Settings > option 3 to change)${NC}"

    echo -e "$line"
}

disable_precommit_hooks() {
    show_header
    echo -e "${YELLOW}${BOLD}🪝 DISABLE PRE-COMMIT HOOKS${NC}\n"

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}[!] Not inside a Git repository. cd into one first.${NC}"
        pause
        return
    fi

    if [[ -f ".git/hooks/pre-commit" ]]; then
        rm -f ".git/hooks/pre-commit"
        echo -e "${GREEN}[✔] Pre-commit hook disabled for this repo.${NC}"
        echo -e "${CYAN}    (Your .pre-commit-config.yaml is left untouched — re-enable anytime.)${NC}"
        log_action "pre-commit hooks disabled for ${TARGET_REPO_DIR}"
    else
        echo -e "${YELLOW}[i] No active pre-commit hook found for this repo.${NC}"
    fi
    pause
}

repo_precommit_hook_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🪝 REPOSITORY PRE-COMMIT HOOK${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Enable Pre-Commit Hook for This Repo"
        echo -e "  ${RED}[2]${NC} Disable Pre-Commit Hook for This Repo"
        echo -e "  ${GREEN}[0]${NC} Back"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-2]: " PC_CHOICE
        case $PC_CHOICE in
            1) setup_precommit_hooks ;;
            2) disable_precommit_hooks ;;
            0) break ;;
        esac
    done
}

show_header() {
    clear
    IMAGE_PATH="${SCRIPT_DIR}/assets/octocat.png"

    if command -v chafa &>/dev/null && [[ -f "$IMAGE_PATH" ]]; then
        chafa --size=35x15 "$IMAGE_PATH"
        echo ""
    else
        echo -e "${CYAN}${BOLD}"
        cat << "EOF"

                                            @@@@@@@@@@@@
                                      @@@@@@@@@@@@@@@@@@@@@@@@@
                                 @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                   @@@@@@@@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@      @@@@@@@@@@@
                  @@@@@@@@@@@          @@@@@@          @@@@@@          @@@@@@@@@@@
                 @@@@@@@@@@@@                                          @@@@@@@@@@@@
                @@@@@@@@@@@@@                                          @@@@@@@@@@@@@
               @@@@@@@@@@@@@@                                          @@@@@@@@@@@@@@
              @@@@@@@@@@@@@@@@                                        @@@@@@@@@@@@@@@@
              @@@@@@@@@@@@@@                                            @@@@@@@@@@@@@@
              @@@@@@@@@@@@@                                              @@@@@@@@@@@@@
             @@@@@@@@@@@@@@                                               @@@@@@@@@@@@@
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@
             @@@@@@@@@@@@@                                                @@@@@@@@@@@@@
             @@@@@@@@@@@@@@                                              @@@@@@@@@@@@@@
             @@@@@@@@@@@@@@                                              @@@@@@@@@@@@@@
              @@@@@@@@@@@@@@                                            @@@@@@@@@@@@@@
              @@@@@@@@@@@@@@@                                          @@@@@@@@@@@@@@@
              @@@@@@@@@@@@@@@@@                                      @@@@@@@@@@@@@@@@@
               @@@@@@@@@@@@@@@@@@                                  @@@@@@@@@@@@@@@@@@
                @@@@@@@   @@@@@@@@@@                            @@@@@@@@@@@@@@@@@@@@
                @@@@@@@@     @@@@@@@@@@@@@@              @@@@@@@@@@@@@@@@@@@@@@@@@@@
                  @@@@@@@@    @@@@@@@@@@@                  @@@@@@@@@@@@@@@@@@@@@@@
                   @@@@@@@@     @@@@@@@@@                  @@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@                               @@@@@@@@@@@@@@@@@@@@@
                     -@@@@@@@                              @@@@@@@@@@@@@@@@@@@-
                       @@@@@@@@                            @@@@@@@@@@@@@@@@@@
                         @@@@@@@@@@@@@@@@                  @@@@@@@@@@@@@@@@
                           @@@@@@@@@@@@@@                  @@@@@@@@@@@@@@
                             %@@@@@@@@@@@                  @@@@@@@@@@@%
                                 @@@@@@@@                  @@@@@@@@
                                     @@@                    @@@
                :::::::: ::::::::::: ::::::::::: :::    ::: :::    ::: :::::::::
                :+:    :+:    :+:         :+:     :+:    :+: :+:    :+: :+:    :+:
                +:+           +:+         +:+     +:+    +:+ +:+    +:+ +:+    +:+
                :#:           +#+         +#+     +#++:++#++ +#+    +:+ +#++:++#+
                +#+   +#+#    +#+         +#+     +#+    +#+ +#+    +#+ +#+    +#+
                #+#    #+#    #+#         #+#     #+#    #+# #+#    #+# #+#    #+#
                ######## ###########     ###     ###    ###  ########  #########
				:::       ::: ::::::::::: :::::::::
				:+:       :+:     :+:          :+:
				+:+       +:+     +:+         +:+
				+#+  +:+  +#+     +#+        +#+
				+#+ +#+#+ +#+     +#+       +#+
				 #+#+# #+#+#      #+#      #+#
				  ###   ###   ########### #########
EOF
        echo -e "${NC}"
    fi

    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${CYAN}${BOLD}         🧙‍♂️ GIT-WIZARD ULTIMATE - GITHUB WORKFLOW ENGINE           ${NC}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${YELLOW}Active Repository Context:${NC} ${BOLD}${TARGET_REPO_DIR}${NC}"
    echo -e "${YELLOW}Mode:${NC} ${BOLD}${WIZARD_MODE^}${NC}   ${YELLOW}Dry-Run:${NC} ${BOLD}${DRY_RUN}${NC}   ${YELLOW}Auto-Sync:${NC} ${BOLD}${AUTO_SYNC_CHECK}${NC} ${CYAN}[Settings > option 3: GitHub Sync]${NC}"

    if [[ "$AUTO_SYNC_CHECK" == "true" ]]; then
        local status_line
        status_line=$(get_sync_status)
        if [[ -n "$status_line" ]]; then
            echo -e "$status_line"
        fi
    fi
    if [[ -n "$UPDATE_NOTICE" ]]; then
        echo -e "${GREEN}${BOLD}${UPDATE_NOTICE}${NC}"
    fi
    echo ""
}

pause() {
    echo ""
    read -e -p "Press [ENTER] to return to menu..."
}

show_uptodate_celebration() {
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"
          ,~-.
         (   ' )-.          ,~'`-.
      ,~' `   ' ) )        _(    _) )
     ( ( .--.===.--.    (   `    ' )
      `.%%.;::|888.#`.   `-'`~~=~'
      /%%/::::|8888\##\
     |%%/:::::|88888\##|
     |%%|:::::|88888|##|.,-.
     \%%|:::::|88888|##/    )_
      \%\:::::|88888/#/ ( `'   )
       \%\::::|8888/#/(  ,  -'`-.
   ,~-. `%\:::|888/#'(  (      ') )
  (   ) )_ `\__|__/'    `~-~=--~~='
 ( ` ')  ) [VVVVV]
(_(_.~~~'   \|_|/   hjw
            [XXX]
            `"""'
EOF
    echo -e "${NC}"
    echo -e "${GREEN}${BOLD}Everything up-to-date! Code is safe and synced on GitHub!${NC}"
}

clean_remote_url() {
    local input_url="$1"
    input_url=$(echo "$input_url" | sed -E 's/^git remote (add|set-url) origin //I' | xargs)
    echo "$input_url"
}

# ==============================================================================
# FIRST-RUN MODE WRAPPER
# ==============================================================================
mode_selection_wrapper() {
    clear
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${CYAN}${BOLD}         🧙‍♂️ WELCOME TO GIT-WIZARD — CHOOSE YOUR MODE            ${NC}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}\n"
    echo -e "  ${GREEN}[1] Beginner Mode${NC}"
    echo -e "      - Simplified menus, extra typed confirmations on destructive actions"
    echo -e "      - Dry-Run suggested by default, automatic safety backups\n"
    echo -e "  ${GREEN}[2] Advanced Mode${NC}"
    echo -e "      - Full menu access, faster confirmations, all Module 5 workflows visible"
    echo -e "      - Safety backups still run automatically (cheap insurance)\n"
    echo -e "${CYAN}You can change this anytime from the Main Menu.${NC}"
    echo -e "====================================================================\n"
    read -e -p "Select mode [1-2]: " MODE_CHOICE
    case $MODE_CHOICE in
        1) WIZARD_MODE="beginner"; DRY_RUN="true" ;;
        2) WIZARD_MODE="advanced"; DRY_RUN="false" ;;
        *) WIZARD_MODE="beginner"; DRY_RUN="true" ;;
    esac
    save_config
    log_action "Mode set to: ${WIZARD_MODE}"
}



select_wizard_mode() {
    local lines=(
        "beginner"$'\t'"Beginner — simplified menus, typed confirmations on destructive actions"
        "advanced"$'\t'"Advanced — full menu access, faster confirmations, all workflows visible"
    )
    if ! select_from_lines_interactive "📌 SELECT MODE (current: ${WIZARD_MODE})" "${lines[@]}"; then
        return
    fi
    WIZARD_MODE="${SELECTED_LINE%%$'\t'*}"
    save_config
    log_action "Mode switched to: ${WIZARD_MODE}"
    echo -e "${GREEN}[✔] Switched to ${WIZARD_MODE} mode.${NC}"
    sleep 1
}

select_dry_run_state() {
    local lines=(
        "false"$'\t'"Off — commands actually run (real git operations)"
        "true"$'\t'"On — commands are only PRINTED, nothing is actually executed"
    )
    if ! select_from_lines_interactive "📌 DRY-RUN MODE (current: ${DRY_RUN})" "${lines[@]}"; then
        return
    fi
    DRY_RUN="${SELECTED_LINE%%$'\t'*}"
    save_config
    log_action "Dry-Run set to: ${DRY_RUN}"
    echo -e "${GREEN}[✔] Dry-Run mode is now: ${DRY_RUN}${NC}"
    sleep 1
}

select_auto_sync_state() {
    local lines=("off"$'\t'"Off — no sync panel shown in header" "on"$'\t'"On — sync panel shown in header on every screen")
    if ! select_from_lines_interactive "📌 GITHUB SYNC PANEL — ENABLE OR DISABLE (current: ${AUTO_SYNC_CHECK})" "${lines[@]}"; then
        return
    fi
    local choice="${SELECTED_LINE%%$'\t'*}"
    if [[ "$choice" == "on" ]]; then
        AUTO_SYNC_CHECK="true"
    else
        AUTO_SYNC_CHECK="false"
    fi
    save_config
    log_action "Auto-Sync panel set to: ${AUTO_SYNC_CHECK}"
    echo -e "${GREEN}[✔] GitHub Sync Panel is now: ${AUTO_SYNC_CHECK}${NC}"
    sleep 1
}

select_sync_detail_level() {
    local lines=(
        "minimal"$'\t'"Minimal — sync tier, fetch reachability, modified/untracked split"
        "standard"$'\t'"Standard — adds stash count + last commit freshness"
        "full"$'\t'"Full — adds conflict-risk preview before pulling (slower, extra git calls)"
    )
    if ! select_from_lines_interactive "📌 SYNC PANEL DETAIL LEVEL (current: ${SYNC_DETAIL_LEVEL})" "${lines[@]}"; then
        return
    fi
    SYNC_DETAIL_LEVEL="${SELECTED_LINE%%$'\t'*}"
    save_config
    log_action "Sync Panel Detail Level set to: ${SYNC_DETAIL_LEVEL}"
    echo -e "${GREEN}[✔] Sync Panel Detail Level is now: ${SYNC_DETAIL_LEVEL}${NC}"
    sleep 1
}

github_sync_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🔄 GITHUB SYNC — Panel Settings${NC}\n"
        echo -e "${CYAN}This controls the live sync status panel shown at the top of every screen.${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Enable / Disable Sync Panel  ${CYAN}(current: ${AUTO_SYNC_CHECK})${NC}"
        echo -e "      ${CYAN}Turns the whole panel on or off. If Off, nothing below matters — no panel is shown.${NC}"
        echo -e "  ${GREEN}[2]${NC} Set Detail Level  ${CYAN}(current: ${SYNC_DETAIL_LEVEL})${NC}"
        echo -e "      ${CYAN}Minimal / Standard / Full — only visible when the panel is On (option 1).${NC}"
        echo -e "  ${GREEN}[3]${NC} Preview Panel Now"
        echo -e "      ${CYAN}Shows exactly what the panel looks like at your current settings, right now.${NC}"
        echo -e "  ${GREEN}[4]${NC} What's the difference between levels? (Guide)"
        echo -e "  ${GREEN}[0]${NC} Back to Module 5"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-4]: " GSCHOICE
        case $GSCHOICE in
            1) select_auto_sync_state ;;
            2) select_sync_detail_level ;;
            3)
                show_header
                echo -e "${YELLOW}${BOLD}🔄 LIVE PREVIEW${NC}\n"
                if [[ "$AUTO_SYNC_CHECK" != "true" ]]; then
                    echo -e "${RED}[!] Panel is currently OFF (option 1). Nothing would show in the header right now.${NC}"
                    echo -e "${CYAN}    Turn it On first to see the panel here and on every screen.${NC}"
                else
                    local preview
                    preview=$(get_sync_status)
                    if [[ -n "$preview" ]]; then
                        echo -e "$preview"
                    else
                        echo -e "${YELLOW}[i] Not inside a Git repository — nothing to preview here.${NC}"
                    fi
                fi
                pause
                ;;
            4)
                show_header
                echo -e "${YELLOW}${BOLD}📖 SYNC PANEL DETAIL LEVELS EXPLAINED${NC}\n"
                echo -e "${GREEN}${BOLD}Minimal:${NC}"
                echo -e "  - Sync tier (✅/🟡/🟠/🔴) with ahead/behind counts"
                echo -e "  - 🌐/🚫 whether the last fetch actually reached GitHub"
                echo -e "  - ✏️ modified / ➕ untracked file counts if you're dirty"
                echo -e "  - Fastest option — one fetch, no extra git calls\n"
                echo -e "${GREEN}${BOLD}Standard (default):${NC}"
                echo -e "  - Everything in Minimal, PLUS:"
                echo -e "  - 📦 stash count, if you have any stashed work sitting around"
                echo -e "  - 🕐 how long ago your last commit was\n"
                echo -e "${GREEN}${BOLD}Full:${NC}"
                echo -e "  - Everything in Standard, PLUS:"
                echo -e "  - ⚠️/✅ a conflict-risk check when you're behind — runs a dry-run merge"
                echo -e "    to warn you BEFORE you use Safe Update Sync"
                echo -e "  - Slightly slower to render since it does extra git work every screen\n"
                echo -e "${YELLOW}Note:${NC} none of this shows anywhere unless the panel itself is turned On (option 1)."
                pause
                ;;
            0) break ;;
        esac
    done
}

# --- Non-Git Repository Verification & Setup ---
# --- Non-Git Repository Verification & Setup ---
check_git_repo() {
    # Loop until the directory IS a git repo (user inits) or user chooses to exit.
    # Returns 0 if we're now inside a git repo (either already was, or just initialized).
    # Returns 1 if user chose Exit.
    while ! git -C "$TARGET_REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; do
        show_header

        # ─── DEMO ASCII ART — Replace everything between INITART markers with yours ───
        echo -e "${CYAN}"
        cat << 'INITART'


           .                                      ............     .                            .
      .                             ...::-===+=+***++++++=-:..         .  . .       . .
                .              .....:=#%%%@@@@@@@@@@@@@@%@@@%#*=:..
                       .  . ....:=+#%@@@@%@@@@@@@@@@@@@@@@@@@@@@%#*=..
            .               .:+#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#@#=...  .
              .           .:+#@@@@%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%%%*:..     .            ..
         .              ..-*%%@%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%+..
       .               ..+%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@@@@@@@@@@@-...
                     ...#%%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#+..    .
.                    ..:%%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%#-.                 .
         .           ..*%%@@@@@@@@@%@@@@@@@@@@@@@@@@%##****#@@@@@@@@@@@@@@@@%-.
                     .=%@@@@@@@@@@@@@@@@%%###*###***++=======++#%@@@@@@@@@@@@*...
          .          .+%@@@@@@@%@@@@%#+====-========-------=====++*#@@@@@@@@%*:.. .
                     .:%@@@@@@@@@@%*===-----------------------====++#@@@@@@@@-...     .          .
                     ..*@@@@@@@%*+====-------------------------====++%@@@@@@@-..               .
                     ..=%@@@@@%*=====-----:::::----------------=====+*@@@@@@%..
                     ...+%%@@@#+===--------:::::---------------======+%@@@@%:..  .                .
                     ...:%@@@@#+==----------::::--------------=======+*@@@@-...     .
                       ..%@@@#+===--==---:::::::::::::::::---==+++====+*@@@:...   .            .
                       ..+@@%+=====*###%#*+==-::::::::::-=+*%%%@@%%*+==+%@#....               .    .
                      . .-@@%+====***+++++++=--::::::---=+++++=+++**+===#@=....         .   .
       .             ....=#@#========----===+==---:---======---=====++==*@#=...              .
                     ...+=+%#=======++=======++=-----===========++++====*%*+...
                 .   ...+==#*=----=+#*=%#%#*+====----====++#%@@=+#*=====+*++-..
                    ....=-=#+==----=====**====------========+*==++===-===#*==..
                  .  ...:==#+=----------==-----------==----======------==*#+:..               .
                     ....-=*+=-----------------------==----------------==*#+...
                      ...:=**=-----------------------==----------------==#*+... .
                        .:=*#+=---------::::--==-----===--:-----------==*#+=...
                        ..=*%*==------::::-----=-::--==----:::-------==+#%*:...
                        ..-*%%+===----::-----====--=++++=------------==*%%*:...
     .                  ...-#%*+==----:-----=+*+++++***+=----------===+#%#-....            .
                        ...:+%%*+==------=+****+++++++###*+==----===++*%%*=:...   .
    .                   ...:+%%%*++=---==**+===========++****+=====++*#%*+-..
   .      .             ..:=*#%%%**+==-=+++**+++======+******+===++*#%%#==:..
           .            ..-=+*#%%%#**====---==++=====++++==-=+=++*#%%%%*=-...                .
                        ..:-+###%%%%#++==---==**#%%%##*+=====++**#%%%%%+-:..     .
                      . ...:++++#%@%%#*+======+*#%%#*+==-===+**#%@@@%**+:...
                        ....:-=+%%%%%%%#*+===++*+*+==++===++*#%%%@@%%=-:....
                     .    ...:+#%%%%%@@@%#**+*++++++**#***##%%@@@%%%%#=.....
                   .        .=#%%#%%%%%@%%%%%%#%%#%%%%%%%%%%%@@@%%%%%%##+:..  .
                     .......+*#%%%%%%%%@@@@%%%%@@@@@@@@@@@@@@@%%%%%%%%####*-.......
            . ..........:=*#*##%%#%%%%%%@%%%%@@@@@@@%%@@@@%%%%%%%%%%%%######***=.......... .
              .......-+**###*##%%##%%%%%%%%%%%%%@@@%@@@%%%%%%%%%%%%%%##%%########*+-......
   .   ..........:++***########%%#####%%%%%%%%%%@%%%%%@%%%%%%%%%%%%%%%######%##%###***+-.........
      ......:-+******##########%@#**####%%%%%%%%%%%@%%%%%%%%%%%%%%%%%%%%%#############*#**+-:......
.........:=+**##################%%#*#####%%%%%%%%@@%%%%%%%%%%%%%%%%%%%%%%%%%%%#######*****###**=:...
.....:-+++******####################***###%#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#%%%#####*##***********#**+
.:-=+***###******##**##*######################%%%%%%%%%%%%%%%%%%%%%%%#############**************###*
+*******#*##*****#####################%###%%%########%%%%%%%%%%%%%%##%#####%##########***********##*
*******#####*#***#*###*################%%%%#%%%%#***#%%%%%##%%%%%%################**#*###****##**###
********#*#***######*#######*########%%%%%%%####%#**########%%%%%%######%########************#***###
****#########******#####*###############%%%%#######**###%%#####################********##**#**##****
****##**#######*******##*######################%%%#####%%########################**#*##*####**#**###
*****##*###*****#***###**#*################%###%%%%%%%%%####*#################***#**#***##******####
#****##*#*****#**####*#**#*##*####*##*#########%%%%%%###########*####**#########*****#*###***#****#*
*#***#**#*##*#****#***##***#*#########**########%%%%%########**#####****########******###**##**#*#**
*#****#*####*******#**###*****######*##*######%#%%############**##*#**#######*#****#####*###****#***
****###*####**##********#*###*########*###**##%%###**#############*####*#****##*###########**###***#
**#**##**###****######*####***#*#####*######**%######*##########**#####*###*###*##*######***###**###
####**###########*##*#####*###*########*######%####**########**#*###*#*###**#####################***
##****###*####**#**#*###***###**######**##*###%########%#####***##########****##############*#######
#*##*##########*******###*####**########**####%#####*#####******#####*#*###############*############
%##*##*#########**#########*##*######**#####%#%#####*#######**####*##############%#########*########
#################*###**#*##############################%###*#*########**#*####%#%#**####%%#########%
%%###*########%##*#######**##############%#################****########**#####%%%##*##############%%
#%%##########%%###*#######*#########################################**#######%%#########%%########%%

                              ╔═══════════════════════════════════════╗
                              ║   F I R S T   T I M E   S E T U P     ║
                              ╚═══════════════════════════════════════╝

                               This folder is NOT a Git repository yet.

INITART
        echo -e "${NC}"

        echo -e "${YELLOW}  📂 Directory: ${BOLD}${TARGET_REPO_DIR}${NC}\n"
        echo -e "${CYAN}  Available Actions:${NC}"
        echo -e "  ${GREEN}[1]${NC} ${BOLD}🚀  Initialize a new Git Repository here${NC} ${CYAN}(git init → enters main menu)${NC}"
        echo -e "  ${RED}[2]${NC} ${BOLD}🚪  Exit${NC} ${CYAN}(quit git-wizard, nothing changes)${NC}"
        echo -e "\n  ===================================================================="
        read -e -p "  Select choice [1-2]: " NON_REPO_CHOICE

        case "$NON_REPO_CHOICE" in
            1)
                echo ""
                echo -e "${CYAN}  → Initializing Git repository...${NC}"
                if run_git init && run_git branch -M main 2>/dev/null; then
                    echo -e "${GREEN}${BOLD}  [✔] Initialized empty Git repository in ${TARGET_REPO_DIR}!${NC}"
                    echo -e "${GREEN}  [✔] Entering main menu now...${NC}"
                    log_action "Initialized new git repo at ${TARGET_REPO_DIR}"
                    echo ""
                    # The while loop condition will now be FALSE (repo exists),
                    # so the loop exits naturally and we return 0 below.
                else
                    echo -e "${RED}  [✘] git init failed! Check permissions or disk space.${NC}"
                    log_action "FAILED git init at ${TARGET_REPO_DIR}"
                    pause
                    # Loop continues — user stays in this menu to try again or exit.
                fi
                ;;
            2)
                echo -e "${YELLOW}  Exiting git-wizard. Nothing was changed.${NC}"
                return 1
                ;;
            *)
                echo -e "${RED}  Invalid choice! Please enter 1 or 2.${NC}"
                sleep 1
                # Loop continues — re-shows the menu automatically.
                ;;
        esac
    done

    # If we get here, the directory IS a git repo.
    return 0
}
enable_global_cli() {
    show_header
    echo -e "${YELLOW}${BOLD}⚡ MODULE: UNIVERSAL GLOBAL CLI INSTALLER${NC}\n"
    local SCRIPT_PATH="${SCRIPT_DIR}/linux/git-wizard.sh"
    chmod +x "$SCRIPT_PATH"
    if [[ -w "/usr/local/bin" ]]; then
        ln -sf "$SCRIPT_PATH" /usr/local/bin/git-wizard
    else
        sudo ln -sf "$SCRIPT_PATH" /usr/local/bin/git-wizard
    fi

    # Persist the "enabled" state so it's never re-offered, and so the tool
    # re-asserts the symlink on every future launch (see
    # ensure_global_cli_persisted, called at startup). This is what makes
    # it survive reboots and new terminals.
    GLOBAL_CLI_ENABLED="true"
    save_config

    # Make sure /usr/local/bin is actually on PATH in FUTURE shells too —
    # append an export line to every shell rc file we can find, once, idempotently.
    local path_line='export PATH="/usr/local/bin:$PATH"'
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        touch "$rc" 2>/dev/null
        if ! grep -qF "$path_line" "$rc" 2>/dev/null; then
            {
                echo ''
                echo '# Added by git-wizard: ensures git-wizard is found in every new terminal'
                echo "$path_line"
            } >> "$rc" 2>/dev/null
        fi
    done
    export PATH="/usr/local/bin:$PATH"
    hash -r 2>/dev/null || true

    echo -e "\n${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${GREEN}${BOLD}[✔] GIT-WIZARD IS NOW INSTALLED GLOBALLY — PERMANENTLY.${NC}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${CYAN}HOW TO USE FROM ANY FOLDER ON THIS MACHINE:${NC}"
    echo -e "  ${GREEN}1.${NC} Open a NEW terminal window (this one already works too)."
    echo -e "  ${GREEN}2.${NC} cd into any repo you want to work on."
    echo -e "  ${GREEN}3.${NC} Simply type: ${GREEN}${BOLD}git-wizard${NC}"
    echo -e "\n${CYAN}This stays enabled across reboots and new terminals until you${NC}"
    echo -e "${CYAN}explicitly disable it from Settings > option 12 (Disable Global CLI).${NC}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}\n"

    log_action "Global CLI enabled permanently (symlink + PATH persisted)"
    pause
}

disable_global_cli() {
    show_header
    echo -e "${YELLOW}${BOLD}⚡ DISABLE UNIVERSAL GLOBAL CLI${NC}\n"
    if [[ -L "/usr/local/bin/git-wizard" || -f "/usr/local/bin/git-wizard" ]]; then
        if [[ -w "/usr/local/bin" ]]; then
            rm -f "/usr/local/bin/git-wizard"
        else
            sudo rm -f "/usr/local/bin/git-wizard"
        fi
        echo -e "${GREEN}[✔] Removed /usr/local/bin/git-wizard symlink.${NC}"
    else
        echo -e "${YELLOW}[i] No symlink found (already removed).${NC}"
    fi

    local path_line='export PATH="/usr/local/bin:$PATH"'
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        if [[ -f "$rc" ]] && grep -qF "$path_line" "$rc" 2>/dev/null; then
            sed -i "\|# Added by git-wizard: ensures git-wizard is found in every new terminal|d" "$rc" 2>/dev/null
            sed -i "\|${path_line}|d" "$rc" 2>/dev/null
            echo -e "${GREEN}[✔] Cleaned up PATH entry from ${rc}${NC}"
        fi
    done

    GLOBAL_CLI_ENABLED="false"
    save_config
    log_action "Global CLI disabled permanently"
    echo -e "\n${GREEN}[✔] Global CLI has been permanently disabled.${NC}"
    echo -e "${CYAN}    You can still run it directly via: ${SCRIPT_DIR}/linux/git-wizard.sh${NC}"
    pause
}

# Called once at startup. If previously enabled permanently, silently
# re-assert the symlink (cheap, idempotent) so it self-heals even if
# something else removed /usr/local/bin/git-wizard.
ensure_global_cli_persisted() {
    [[ "$GLOBAL_CLI_ENABLED" != "true" ]] && return
    local SCRIPT_PATH="${SCRIPT_DIR}/linux/git-wizard.sh"
    [[ -f "$SCRIPT_PATH" ]] || return
    if [[ ! -L "/usr/local/bin/git-wizard" ]]; then
        if [[ -w "/usr/local/bin" ]]; then
            ln -sf "$SCRIPT_PATH" /usr/local/bin/git-wizard 2>/dev/null || true
        else
            sudo -n ln -sf "$SCRIPT_PATH" /usr/local/bin/git-wizard 2>/dev/null || true
        fi
    fi
}
# ==============================================================================
# SSH GITHUB SETUP END-TO-END
# Generates a new ED25519 SSH key (if none exists), starts ssh-agent,
# adds the key to the agent, and pushes the public key to GitHub via `gh`.
# End-to-end: zero browser, zero copy-paste. Asks for custom title.
# ==============================================================================
one_click_ssh_to_github() {
    show_header
    echo -e "${YELLOW}${BOLD}🚀 SSH GITHUB SETUP END-TO-END${NC}\n"
    echo -e "${CYAN}This will automatically:${NC}"
    echo -e "  ${GREEN}1.${NC} Check for existing SSH keys"
    echo -e "  ${GREEN}2.${NC} Generate a new ED25519 key (with your custom title) if needed"
    echo -e "  ${GREEN}3.${NC} Start ssh-agent & load the key"
    echo -e "  ${GREEN}4.${NC} Upload the public key to your GitHub account via API"
    echo -e "  ${GREEN}5.${NC} Test the SSH connection to GitHub"
    echo ""

    # --- Prerequisite: gh installed + authenticated (self-healing) ---
    if ! ensure_gh_ready; then
        pause
        return
    fi

    local gh_user
    gh_user=$(gh api user --jq '.login' 2>/dev/null)
    echo -e "${GREEN}[✔] GitHub CLI authenticated as: ${BOLD}${gh_user}${NC}\n"

    local CUSTOM_KEY_TITLE=""  # Will hold the user's desired title for GitHub

    # --- Step 1: Check for existing SSH keys ---
    echo -e "${CYAN}[1/5] Checking for existing SSH keys...${NC}"
    local SSH_DIR="${HOME}/.ssh"
    local KEY_PATH="${SSH_DIR}/id_ed25519"
    local PUB_PATH="${KEY_PATH}.pub"
    local KEY_EXISTS="false"

    if [[ -f "$KEY_PATH" && -f "$PUB_PATH" ]]; then
        KEY_EXISTS="true"
        echo -e "${YELLOW}[i] Found existing key: ${KEY_PATH}${NC}"
        local fingerprint
        fingerprint=$(ssh-keygen -lf "$PUB_PATH" 2>/dev/null | awk '{print $2}')
        echo -e "${CYAN}    Fingerprint: ${fingerprint}${NC}"
        echo ""
        read -e -p "    Generate a NEW key instead? (y/N): " GEN_NEW
        if [[ "$GEN_NEW" =~ ^[Yy]$ ]]; then
            local ts
            ts=$(date '+%Y%m%d-%H%M%S')
            KEY_PATH="${SSH_DIR}/id_ed25519-gitwizard-${ts}"
            PUB_PATH="${KEY_PATH}.pub"
            KEY_EXISTS="false"
            echo -e "${CYAN}    Will generate new key at: ${KEY_PATH}${NC}"
        fi
    elif [[ -f "${SSH_DIR}/id_rsa" && -f "${SSH_DIR}/id_rsa.pub" ]]; then
        echo -e "${YELLOW}[i] Found old-style RSA key: ${SSH_DIR}/id_rsa${NC}"
        echo -e "${CYAN}    ED25519 is faster and more secure. Recommend generating a new one.${NC}"
        echo ""
        read -e -p "    Generate a new ED25519 key? (Y/n): " GEN_NEW
        if [[ "$GEN_NEW" =~ ^[Yy]$ || -z "$GEN_NEW" ]]; then
            local ts
            ts=$(date '+%Y%m%d-%H%M%S')
            KEY_PATH="${SSH_DIR}/id_ed25519-gitwizard-${ts}"
            PUB_PATH="${KEY_PATH}.pub"
            KEY_EXISTS="false"
        else
            KEY_PATH="${SSH_DIR}/id_rsa"
            PUB_PATH="${SSH_DIR}/id_rsa.pub"
            KEY_EXISTS="true"
        fi
    fi

    # --- Step 2: Generate key if needed (with Title Prompt) ---
    if [[ "$KEY_EXISTS" != "true" ]]; then
        echo -e "\n${CYAN}[2/5] Naming your new SSH key...${NC}"
        echo -e "${CYAN}    (This title will appear in your GitHub SSH settings table)${NC}"
        read -e -p "    Enter a title for this key (e.g., 'My-Kali-VM'): " CUSTOM_KEY_TITLE

        # Fallback if user just presses ENTER
        if [[ -z "$CUSTOM_KEY_TITLE" ]]; then
            local ts_fb
            ts_fb=$(date '+%Y%m%d-%H%M%S')
            CUSTOM_KEY_TITLE="git-wizard-auto-$(hostname)-${ts_fb}"
            echo -e "    ${YELLOW}No title entered. Using default: ${CUSTOM_KEY_TITLE}${NC}"
        fi

        echo -e "\n${CYAN}    Generating ED25519 SSH key...${NC}"
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}[DRY-RUN] Would execute: ssh-keygen -t ed25519 -C \"${gh_user}@git-wizard\" -f ${KEY_PATH} -N \"\"${NC}"
            log_action "DRY-RUN: would generate SSH key at ${KEY_PATH}"
        else
            ssh-keygen -t ed25519 -C "${gh_user}@git-wizard" -f "$KEY_PATH" -N "" 2>&1
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}[!] ssh-keygen failed.${NC}"
                pause
                return
            fi
            chmod 600 "$KEY_PATH"
            chmod 644 "$PUB_PATH"
            echo -e "${GREEN}[✔] Key generated: ${KEY_PATH}${NC}"
            echo -e "${GREEN}[✔] GitHub Title: ${BOLD}${CUSTOM_KEY_TITLE}${NC}"
            log_action "Generated new SSH key: ${KEY_PATH} (Title: ${CUSTOM_KEY_TITLE})"
        fi
    else
        echo -e "${GREEN}[✔] Using existing key: ${KEY_PATH}${NC}"
        echo -e "${CYAN}[2/5] Skipped — key already exists.${NC}"
    fi

    # --- Step 3: Start ssh-agent & add key ---
    echo -e "\n${CYAN}[3/5] Starting ssh-agent & loading key...${NC}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would start ssh-agent and add ${KEY_PATH}${NC}"
    else
        if [[ -n "$SSH_AGENT_PID" ]]; then
            kill "$SSH_AGENT_PID" 2>/dev/null || true
            unset SSH_AGENT_PID
            unset SSH_AUTH_SOCK
        fi
        eval "$(ssh-agent -s)" >/dev/null 2>&1
        ssh-add "$KEY_PATH" 2>&1
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}[✔] Key added to ssh-agent (PID: ${SSH_AGENT_PID})${NC}"
        else
            echo -e "${YELLOW}[!] ssh-add returned non-zero. Key file exists but agent may have issues.${NC}"
            echo -e "${CYAN}    Connection test below will confirm if it works regardless.${NC}"
        fi
    fi

    # --- Step 3.5: Pre-check — is this key ALREADY on GitHub? ---
    echo -e "\n${CYAN}[3.5/5] Checking if this key is already on your GitHub account...${NC}"
    local NEEDS_UPLOAD="true"
    local LOCAL_FP
    LOCAL_FP=$(ssh-keygen -lf "$PUB_PATH" 2>/dev/null | awk '{print $2}')
    local GH_FINGERPRINTS
    GH_FINGERPRINTS=$(gh api user/keys --jq '.[].fingerprint' 2>/dev/null)

    if [[ -n "$GH_FINGERPRINTS" ]] && echo "$GH_FINGERPRINTS" | grep -qF "$LOCAL_FP"; then
        NEEDS_UPLOAD="false"
        echo -e "${YELLOW}[i] This exact key is ALREADY on your GitHub account.${NC}"
        echo -e "${CYAN}    GitHub does not allow duplicate keys. No upload needed.${NC}"
        local MATCHED_TITLE
        MATCHED_TITLE=$(gh api user/keys --jq ".[] | select(.fingerprint == \"${LOCAL_FP}\") | .title" 2>/dev/null)
        if [[ -n "$MATCHED_TITLE" ]]; then
            echo -e "${CYAN}    Registered on GitHub as: ${GREEN}${MATCHED_TITLE}${NC}"
        fi
    else
        echo -e "${GREEN}[✔] This key is NOT on GitHub yet — upload will proceed.${NC}"
    fi

    # --- Step 4: Upload public key to GitHub via `gh ssh-key add` ---
    echo -e "\n${CYAN}[4/5] Uploading public key to GitHub account '${gh_user}'...${NC}"

    if [[ "$NEEDS_UPLOAD" != "true" ]]; then
        echo -e "${CYAN}    Skipped — key already present on GitHub (see step 3.5 above).${NC}"

    elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute: gh ssh-key add ${PUB_PATH} --title \"${CUSTOM_KEY_TITLE}\"${NC}"
        log_action "DRY-RUN: would upload SSH key to GitHub"

    else
        # Use the custom title if provided, otherwise fallback to a generic upload title
        local key_title="$CUSTOM_KEY_TITLE"
        if [[ -z "$key_title" ]]; then
            key_title="git-wizard-upload-$(hostname)-$(date '+%Y%m%d-%H%M%S')"
        fi

        local upload_output
        upload_output=$(gh ssh-key add "$PUB_PATH" --title "$key_title" 2>&1)
        local upload_exit=$?

        if [[ $upload_exit -eq 0 ]] && ! echo "$upload_output" | grep -qi "error\|fail\|already"; then
            echo -e "${GREEN}[✔] Public key uploaded to GitHub!${NC}"
            echo -e "${CYAN}    Title on GitHub: ${BOLD}${key_title}${NC}"
            log_action "Uploaded SSH key to GitHub: ${key_title}"
        elif echo "$upload_output" | grep -qi "already"; then
            echo -e "${YELLOW}[i] This key is already on GitHub. No duplicate was created.${NC}"
            log_action "SSH key already present on GitHub, skipped upload"
        else
            echo -e "${RED}[!] Failed to upload key to GitHub.${NC}"
            echo -e "${YELLOW}    Error: ${upload_output}${NC}"
            echo ""
            echo -e "${CYAN}    Fallback — copy this key manually to:${NC}"
            echo -e "${CYAN}    GitHub → Settings → SSH and GPG keys → New SSH key${NC}"
            echo ""
            echo -e "${BOLD}─── PUBLIC KEY (copy below) ───${NC}"
            cat "$PUB_PATH"
            echo -e "${BOLD}─── END PUBLIC KEY ───${NC}"
            pause
            return
        fi
    fi

    # --- Step 5: Test connection ---
    echo -e "\n${CYAN}[5/5] Testing SSH connection to GitHub...${NC}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute: ssh -T git@github.com${NC}"
    else
        echo -e "${CYAN}    (waiting 3 seconds for GitHub to propagate the key...)${NC}"
        sleep 3

        local test_output
        test_output=$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -T git@github.com 2>&1)

        if echo "$test_output" | grep -qi "successfully authenticated"; then
            echo -e "${GREEN}${BOLD}[✔] SSH CONNECTION TO GITHUB IS WORKING!${NC}"
            echo -e "${GREEN}    ${test_output}${NC}"
        elif echo "$test_output" | grep -qi "permission denied"; then
            echo -e "${RED}[!] Permission denied — GitHub doesn't recognize this key.${NC}"
            echo -e "${YELLOW}    This can happen if GitHub hasn't finished propagating.${NC}"
            echo -e "${YELLOW}    Wait 30 seconds and test manually: ${GREEN}ssh -T git@github.com${NC}"
        else
            echo -e "${YELLOW}[i] Unexpected response:${NC}"
            echo -e "    ${test_output}${NC}"
        fi
    fi

    # --- Summary ---
    echo -e "\n${GREEN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✅ SSH-TO-GITHUB PIPELINE COMPLETE!${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Key file:      ${KEY_PATH}${NC}"
    echo -e "${CYAN}  Public key:    ${PUB_PATH}${NC}"
    echo -e "${CYAN}  GitHub user:   ${gh_user}${NC}"
    if [[ "$NEEDS_UPLOAD" != "true" ]]; then
        echo -e "${YELLOW}  Upload:        Skipped — key was already on GitHub${NC}"
    else
        echo -e "${GREEN}  Upload Title:  ${CUSTOM_KEY_TITLE:-Default}  (Added to GitHub)${NC}"
    fi
    echo -e "${CYAN}  You can now use SSH URLs: ${GREEN}git@github.com:user/repo.git${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"

    log_action "One-click SSH-to-GitHub pipeline completed (key: ${KEY_PATH})"
    pause
}
# ==============================================================================
# GITHUB SSH KEY MANAGER (List, Delete, & Purge All)
# Audits all SSH keys registered on your GitHub account and allows safe
# removal of stale/orphaned keys (e.g., from destroyed VMs), or a full
# nuclear purge of every key at once.
# ==============================================================================
# ==============================================================================
# GITHUB SSH KEY MANAGER (Interactive TUI - Perfect Table & Purge)
# ==============================================================================
manage_github_ssh_keys() {
    if ! ensure_gh_ready; then
        pause
        return
    fi
    if ! ensure_jq_ready; then
        pause
        return
    fi

    local gh_user
    gh_user=$(gh api user --jq '.login' 2>/dev/null)
    local GRAY='\033[90m'
    local DIM='\033[2m'

    # --- Internal: Draw the Perfect Table ---
    _draw_table() {
        local json="$1"
        clear
        echo -e "${YELLOW}${BOLD}🔑 GITHUB SSH KEY MANAGER (${gh_user})${NC}\n"

        local count
        count=$(echo "$json" | jq '. | length')

        # Precise column widths: ID=12, TITLE=30, FINGERPRINT=40, DATE=12
        local sep_top="┌────────────┬──────────────────────────────┬────────────────────────────────────────┬────────────┐"
        local sep_mid="├────────────┼──────────────────────────────┼────────────────────────────────────────┼────────────┤"
        local sep_bot="└────────────┴──────────────────────────────┴────────────────────────────────────────┴────────────┘"

        echo -e "${CYAN}${sep_top}${NC}"
        printf "${CYAN}│${BOLD} %-10s ${NC}${CYAN}│${BOLD} %-28s ${NC}${CYAN}│${BOLD} %-40s ${NC}${CYAN}│${BOLD} %-10s ${NC}${CYAN}│${NC}\n" "ID" "TITLE" "FINGERPRINT" "ADDED ON"
        echo -e "${CYAN}${sep_mid}${NC}"

        if [[ "$count" -eq 0 ]]; then
            printf "${CYAN}│${NC} %-10s ${CYAN}│${NC} %-28s ${CYAN}│${NC} %-40s ${CYAN}│${NC} %-10s ${CYAN}│${NC}\n" "" "No keys found" "" ""
        else
            # Safely handle null values using jq's // syntax
            echo "$json" | jq -r '.[] | "\(.id)|\(.title // "Untitled")|\(.fingerprint // "N/A")|\(.created_at // "Unknown")"' | while IFS='|' read -r id title fp created; do
                printf "${CYAN}│${NC} %-10s ${CYAN}│${NC} %-28s ${CYAN}│${NC} %-40s ${CYAN}│${NC} %-10s ${CYAN}│${NC}\n" "${id:0:10}" "${title:0:28}" "${fp:0:40}" "${created%%T*}"
            done
        fi
        echo -e "${CYAN}${sep_bot}${NC}"
    }

    # --- Internal: Arrow Key Selector ---
    _arrow_select_key() {
        local json="$1"
        tput civis 2>/dev/null

        local ids=(); local titles=(); local fps=()
        while IFS='|' read -r id title fp created; do
            ids+=("$id")
            titles+=("${title:-Untitled}")
            [[ "$fp" == "null" || -z "$fp" ]] && fp="N/A"
            fps+=("$fp")
        done < <(echo "$json" | jq -r '.[] | "\(.id)|\(.title)|\(.fingerprint)|\(.created_at)"')

        local count=${#ids[@]}
        local selected=0

        while true; do
            clear
            echo -e "${RED}${BOLD}🗑️  SELECT A KEY TO DELETE${NC}\n"
            echo -e "${DIM}Use arrow keys to navigate, ENTER to select, Q to cancel.${NC}\n"

            for ((i=0; i<count; i++)); do
                if [[ $i -eq $selected ]]; then
                    printf "  ${GREEN}➤ [${CYAN}%-10s${GREEN}] ${BOLD}%-30s${NC} ${GRAY}| %.48s${NC}\n" "${ids[$i]}" "${titles[$i]}" "${fps[$i]}"
                else
                    printf "  ${GRAY}  [%-10s] %-30s | %.48s${NC}\n" "${ids[$i]}" "${titles[$i]}" "${fps[$i]}"
                fi
            done

            echo -e "\n${CYAN}[↑/↓] Navigate   [ENTER] Select   [Q] Cancel${NC}"

            local key
            IFS= read -rsn1 key
            if [[ $key == $'\x1b' ]]; then
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A') ((selected--)); [ $selected -lt 0 ] && selected=$((count-1)) ;;
                    '[B') ((selected++)); [ $selected -ge count ] && selected=0 ;;
                esac
            elif [[ -z "$key" ]]; then
                tput cnorm 2>/dev/null
                _arrow_confirm_delete "${ids[$selected]}" "${titles[$selected]}" "${fps[$selected]}"
                return $?
            elif [[ "$key" =~ ^[Qq]$ ]]; then
                tput cnorm 2>/dev/null
                return 2
            fi
        done
    }

    # --- Internal: Arrow Key Yes/No Confirmation ---
    _arrow_confirm_delete() {
        local id="$1" title="$2" fp="$3"
        local selected="Yes"

        while true; do
            clear
            echo -e "${RED}${BOLD}⚠️  DELETE THIS KEY?${NC}\n"
            echo -e "  ${BOLD}Title:${NC}       ${title}"
            echo -e "  ${BOLD}Fingerprint:${NC} ${fp}"
            echo -e "  ${BOLD}ID:${NC}          ${id}\n"
            echo -e "  Are you sure you want to permanently delete this key?\n"

            if [[ "$selected" == "Yes" ]]; then
                echo -e "  ${GREEN}➤ [ YES ]     ${GRAY}[ NO ]${NC}"
            else
                echo -e "  ${GRAY}[ YES ]     ${RED}➤ [ NO ]${NC}"
            fi

            echo -e "\n${CYAN}[←/→] Toggle   [ENTER] Confirm   [Q] Cancel${NC}"

            local key
            IFS= read -rsn1 key
            if [[ $key == $'\x1b' ]]; then
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[D') selected="Yes" ;;
                    '[C') selected="No" ;;
                esac
            elif [[ -z "$key" ]]; then
                if [[ "$selected" == "Yes" ]]; then
                    echo -e "\n${CYAN}--> Deleting key from GitHub...${NC}"
                    if gh api -X DELETE "/user/keys/${id}" &>/dev/null; then
                        echo -e "${GREEN}${BOLD}[✔] Successfully deleted: ${title}${NC}"
                        log_action "Deleted GitHub SSH key: ${title} (ID: ${id})"
                        sleep 1
                        return 0
                    else
                        echo -e "${RED}[!] Failed to delete key.${NC}"
                        sleep 2
                        return 1
                    fi
                else
                    return 1
                fi
            elif [[ "$key" =~ ^[Qq]$ ]]; then
                return 1
            fi
        done
    }

    # ==========================================================================
    # MAIN MENU LOOP
    # ==========================================================================
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🔑 GITHUB SSH KEY MANAGER (${gh_user})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} 📋 List & Manage SSH Keys (Interactive Table)"
        echo -e "  ${RED}[2]${NC} ☢️  PURGE ALL SSH KEYS (delete every key)"
        echo -e "  ${GREEN}[0]${NC} Back to SSH Manager"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-2]: " KEY_MGR_CHOICE

        case $KEY_MGR_CHOICE in
            1)
                while true; do
                    local keys_json
                    keys_json=$(gh api user/keys --paginate 2>&1)

                    if [[ $? -ne 0 ]] || [[ -z "$keys_json" ]]; then
                        echo -e "${RED}[!] Failed to fetch keys.${NC}"; pause; break
                    fi

                    local key_count
                    key_count=$(echo "$keys_json" | jq '. | length')

                    _draw_table "$keys_json"

                    if [[ "$key_count" -eq 0 ]]; then
                        echo -e "\n${YELLOW}[i] No keys to manage.${NC}"
                        pause
                        break
                    fi

                    echo ""
                    read -e -p "Press [D] to select a key for deletion, or [ENTER] to go back: " LIST_ACTION

                    if [[ "$LIST_ACTION" =~ ^[Dd]$ ]]; then
                        _arrow_select_key "$keys_json"
                        local select_status=$?
                        if [[ $select_status -eq 0 ]]; then
                            continue
                        else
                            break
                        fi
                    else
                        break
                    fi
                done
                ;;
            2)
                echo -e "\n${CYAN}Fetching all SSH keys for purge preview...${NC}\n"
                local keys_json
                keys_json=$(gh api user/keys --paginate 2>&1)

                if [[ $? -ne 0 ]] || [[ -z "$keys_json" ]]; then
                    echo -e "${RED}[!] Failed to fetch keys.${NC}"; pause; continue
                fi

                local key_count
                key_count=$(echo "$keys_json" | jq '. | length')

                if [[ "$key_count" -eq 0 ]]; then
                    echo -e "${GREEN}[✔] You already have 0 keys. Nothing to purge.${NC}"
                    pause
                    continue
                fi

                _draw_table "$keys_json"

                echo ""
                echo -e "${RED}${BOLD}⚠  WARNING:${NC}"
                echo -e "${RED}   After this, ${BOLD}NO${RED} machine will be able to SSH into your GitHub account${NC}"
                echo -e "${RED}   until you generate a new key and add it (SSH Manager → Option 3).${NC}"
                echo ""

                if confirm_destructive "Purge ALL ${key_count} SSH key(s) from your GitHub account"; then
                    echo -e "\n${CYAN}--> Purging all SSH keys...${NC}"
                    local success_count=0; local fail_count=0
                    local key_ids
                    key_ids=$(echo "$keys_json" | jq -r '.[].id')

                    for kid in $key_ids; do
                        local kid_title
                        kid_title=$(echo "$keys_json" | jq -r ".[] | select(.id == ${kid}) | .title")
                        if gh api -X DELETE "/user/keys/${kid}" &>/dev/null; then
                            echo -e "  ${GREEN}✘${NC} Deleted: ${kid_title}"
                            success_count=$((success_count + 1))
                        else
                            echo -e "  ${RED}✘${NC} FAILED: ${kid_title}"
                            fail_count=$((fail_count + 1))
                        fi
                    done

                    echo -e "\n${GREEN}${BOLD}═══════════════════════════════════════${NC}"
                    echo -e "${GREEN}${BOLD}  ☢️  PURGE COMPLETE${NC}"
                    echo -e "${GREEN}${BOLD}═══════════════════════════════════════${NC}"
                    echo -e "  Deleted: ${GREEN}${success_count}${NC}  |  Failed: ${RED}${fail_count}${NC}"
                    echo -e "${CYAN}  Next: Use SSH Manager → Option 3 to add a fresh key.${NC}"
                    echo -e "${GREEN}${BOLD}═══════════════════════════════════════${NC}"
                    log_action "PURGED all GitHub SSH keys (deleted: ${success_count}, failed: ${fail_count})"
                else
                    echo -e "\n${YELLOW}[i] Purge cancelled. All keys are safe.${NC}"
                fi
                pause
                ;;
            0) break ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}
# ==============================================================================
# SSH SERVICE INSTALLER & STARTER
# Ensures openssh-client and openssh-server are installed, then starts
# and enables the service so the machine is ready for key generation.
# ==============================================================================
install_and_start_ssh() {
    show_header
    echo -e "${YELLOW}${BOLD}📡 SSH SERVICE INSTALLER & STARTER${NC}\n"

    local pm
    pm=$(detect_pkg_manager)

    local ssh_installed="true"
    if ! command -v ssh &>/dev/null; then ssh_installed="false"; fi
    if ! command -v ssh-keygen &>/dev/null; then ssh_installed="false"; fi

    if [[ "$ssh_installed" == "false" ]]; then
        echo -e "${CYAN}[1/3] Installing OpenSSH Client & Server...${NC}"
        local cmd
        case "$pm" in
            apt)    cmd="sudo apt update && sudo apt install -y openssh-client openssh-server" ;;
            dnf)    cmd="sudo dnf install -y openssh-clients openssh-server" ;;
            pacman) cmd="sudo pacman -S --noconfirm openssh" ;;
            brew)   echo -e "${YELLOW}[i] macOS comes with SSH pre-installed. Skipping package install.${NC}"; cmd="" ;;
            *)      echo -e "${RED}[!] Unsupported package manager.${NC}"; pause; return ;;
        esac

        if [[ -n "$cmd" ]]; then
            if eval "$cmd"; then
                echo -e "${GREEN}[✔] OpenSSH installed successfully via ${pm}.${NC}"
                log_action "Installed OpenSSH via ${pm}"
            else
                echo -e "${RED}[!] Failed to install OpenSSH.${NC}"
                pause
                return
            fi
        fi
    else
        echo -e "${GREEN}[✔] SSH tools are already installed.${NC}"
        echo -e "${CYAN}[1/3] Skipped.${NC}"
    fi

    echo -e "\n${CYAN}[2/3] Starting SSH service...${NC}"
    if sudo systemctl start ssh 2>/dev/null || sudo systemctl start sshd 2>/dev/null; then
        echo -e "${GREEN}[✔] SSH service started.${NC}"
    else
        echo -e "${YELLOW}[!] Could not start SSH service (might not be applicable on all systems, or requires sudo).${NC}"
    fi

    echo -e "\n${CYAN}[3/3] Enabling SSH service on boot...${NC}"
    if sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable sshd 2>/dev/null; then
        echo -e "${GREEN}[✔] SSH service enabled on boot.${NC}"
    else
        echo -e "${YELLOW}[!] Could not enable SSH service on boot.${NC}"
    fi

    echo -e "\n${GREEN}${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✅ SSH SETUP COMPLETE FOR THIS SYSTEM${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Services are enabled. You can now:${NC}"
    echo -e "  ${GREEN}→${NC} Go to option 2 for generating a new Public SSH key and apply that SSH key to your GitHub account manually."
    echo -e "  ${GREEN}→${NC} Go to option number 3: One-click end-to-end SSH setup from system to GitHub with Autonomous Pipeline"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════${NC}"

    log_action "SSH services started and enabled"
    pause
}

# ==============================================================================
# SSH MANAGER HUB (Orchestrator)
# Consolidates all SSH-related tasks into one clean sub-menu.
# ==============================================================================
# ==============================================================================
# SSH MANAGER HUB (Orchestrator)
# ==============================================================================
manage_ssh_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}📡 SSH MANAGER (Keys, Services & GitHub Integration)${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Install & Start SSH Service (Permanently Enable)"
        echo -e "  ${GREEN}[2]${NC} Generate New SSH Key (ED25519) & Show Public Key"
        echo -e "  ${GREEN}[3]${NC} 🔗 SSH GitHub Manager (Setup End-to-End, List, Test & Purge)"
        echo -e "  ${GREEN}[0]${NC} Back to Module 1"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-3]: " SSH_CHOICE

        case $SSH_CHOICE in
            1)
                install_and_start_ssh
                ;;
            2)
                if [[ -f ~/.ssh/id_ed25519 ]]; then
                    echo -e "\n${YELLOW}[!] SSH key already exists at ~/.ssh/id_ed25519${NC}"
                else
                    EMAIL=$(git config --global user.email || echo "user@github.com")
                    ssh-keygen -t ed25519 -C "$EMAIL" -f ~/.ssh/id_ed25519 -N ""
                    log_action "New SSH keypair generated"
                    echo -e "${GREEN}[✔] New SSH key generated!${NC}"
                fi
                echo -e "\n${BOLD}─── PUBLIC KEY ───${NC}"
                cat ~/.ssh/id_ed25519.pub
                echo -e "${BOLD}─── END KEY ───${NC}"
                pause
                ;;
            3)
                manage_ssh_github_menu
                ;;
            0) break ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}
# ==============================================================================
# SSH GITHUB MANAGER (Sub-Hub)
# Consolidates GitHub-specific SSH operations.
# ==============================================================================
# ==============================================================================
# SSH GITHUB MANAGER (Sub-Hub)
# ==============================================================================
manage_ssh_github_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🔗 SSH GITHUB MANAGER${NC}\n"
        echo -e "  ${GREEN}[1]${NC} 🚀 SSH GitHub Setup End-to-End (Auto-generate + Auto-upload + Test)"
        echo -e "  ${GREEN}[2]${NC} 🔑 Manage GitHub SSH Keys (Interactive TUI List & Purge)"
        echo -e "  ${GREEN}[3]${NC} 🧪 Test SSH Connection to GitHub"
        echo -e "  ${GREEN}[0]${NC} Back to SSH Manager"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-3]: " GH_SSH_CHOICE

        case $GH_SSH_CHOICE in
            1)
                one_click_ssh_to_github
                ;;
            2)
                manage_github_ssh_keys
                ;;
            3)
                ssh -T git@github.com || true; pause
                ;;
            0) break ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# PERSONAL ACCESS TOKEN (PAT) VAULT MANAGER
# Securely stores, views, and manages GitHub PATs locally since GitHub
# only displays them once upon creation. Handles browser auto-open for creation.
# ==============================================================================
# ==============================================================================
# VAULT SECURITY HELPERS
# Handle password hashing, config loading/saving, and access prompts.
# ==============================================================================
_hash_pass() {
    echo -n "$1" | sha256sum | awk '{print $1}'
}

_load_vault_config() {
    VAULT_PASS_HASH=""
    VAULT_LOCK_STATUS="unlocked"
    if [[ -f "$VAULT_CONFIG" ]]; then
        VAULT_PASS_HASH=$(grep '^PASS_HASH=' "$VAULT_CONFIG" 2>/dev/null | cut -d'=' -f2-)
        VAULT_LOCK_STATUS=$(grep '^LOCK_STATUS=' "$VAULT_CONFIG" 2>/dev/null | cut -d'=' -f2-)
        [[ -z "$VAULT_LOCK_STATUS" ]] && VAULT_LOCK_STATUS="unlocked"
    fi
}

_save_vault_config() {
    cat > "$VAULT_CONFIG" <<EOF
PASS_HASH=${VAULT_PASS_HASH}
LOCK_STATUS=${VAULT_LOCK_STATUS}
EOF
    chmod 600 "$VAULT_CONFIG" 2>/dev/null
}

_prompt_vault_access() {
    _load_vault_config

    # 1. If no password is set at all, force creation
    if [[ -z "$VAULT_PASS_HASH" ]]; then
        echo -e "${YELLOW}[i] First time using the vault. Please create a master password.${NC}"
        echo -e "${CYAN}    (You can toggle the lock on/off later in Vault Security Settings)${NC}"
        while true; do
            read -s -p "    Create vault password: " p1
            echo ""
            read -s -p "    Confirm vault password: " p2
            echo ""
            if [[ "$p1" == "$p2" && -n "$p1" ]]; then
                VAULT_PASS_HASH=$(_hash_pass "$p1")
                VAULT_LOCK_STATUS="unlocked" # Defaults to unlocked for easy access
                _save_vault_config
                echo -e "${GREEN}[✔] Vault password created. Vault is UNLOCKED for easy access.${NC}"
                return 0
            else
                echo -e "${RED}[!] Passwords did not match or were empty. Try again.${NC}"
            fi
        done
    fi

    # 2. If vault is unlocked, allow access without password
    if [[ "$VAULT_LOCK_STATUS" == "unlocked" ]]; then
        return 0
    fi

    # 3. If vault is locked, ask for password
    if [[ "$VAULT_LOCK_STATUS" == "locked" ]]; then
        echo -e "${YELLOW}[🔒] Vault is LOCKED. Enter master password to proceed.${NC}"
        local attempts=3
        while [[ $attempts -gt 0 ]]; do
            read -s -p "    Password: " p_input
            echo ""
            if [[ "$(_hash_pass "$p_input")" == "$VAULT_PASS_HASH" ]]; then
                echo -e "${GREEN}[✔] Access granted.${NC}"
                return 0
            else
                attempts=$((attempts-1))
                echo -e "${RED}[!] Incorrect password. ${attempts} attempts remaining.${NC}"
            fi
        done
        echo -e "${RED}[!] Access denied. Returning to menu.${NC}"
        sleep 2
        return 1
    fi

    return 1
}

_manage_vault_security_settings() {
    while true; do
        show_header
        _load_vault_config
        echo -e "${YELLOW}${BOLD}🔐 VAULT SECURITY SETTINGS${NC}\n"

        local status_color="$GREEN"
        local status_text="UNLOCKED (No password required to view)"
        if [[ "$VAULT_LOCK_STATUS" == "locked" ]]; then
            status_color="$RED"
            status_text="LOCKED (Password required to view)"
        fi
        if [[ -z "$VAULT_PASS_HASH" ]]; then
            status_text="NOT INITIALIZED (No password set yet)"
            status_color="$YELLOW"
        fi

        echo -e "  Current Status: ${status_color}${BOLD}${status_text}${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Set / Change Vault Password"
        echo -e "  ${GREEN}[2]${NC} Toggle Vault Lock (Currently: ${status_color}${VAULT_LOCK_STATUS^^}${NC}${GREEN})${NC}"
        echo -e "  ${GREEN}[0]${NC} Back to Vault"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-2]: " SEC_CHOICE

        case $SEC_CHOICE in
            1)
                echo -e "\n${CYAN}Setting new vault password...${NC}"
                while true; do
                    read -s -p "    Enter NEW vault password: " p1
                    echo ""
                    read -s -p "    Confirm NEW vault password: " p2
                    echo ""
                    if [[ "$p1" == "$p2" && -n "$p1" ]]; then
                        VAULT_PASS_HASH=$(_hash_pass "$p1")
                        [[ -z "$VAULT_LOCK_STATUS" ]] && VAULT_LOCK_STATUS="unlocked"
                        _save_vault_config
                        echo -e "${GREEN}[✔] Vault password changed successfully!${NC}"
                        log_action "Vault password changed"
                        sleep 1
                        break
                    else
                        echo -e "${RED}[!] Passwords did not match or were empty.${NC}"
                    fi
                done
                pause
                ;;
            2)
                if [[ -z "$VAULT_PASS_HASH" ]]; then
                    echo -e "\n${RED}[!] Please set a password first (Option 1).${NC}"
                    pause
                    continue
                fi
                if [[ "$VAULT_LOCK_STATUS" == "unlocked" ]]; then
                    echo -e "\n${YELLOW}[i] Locking the vault will require a password to view/save/delete tokens.${NC}"
                    read -e -p "    Lock the vault now? (y/N): " DO_LOCK
                    if [[ "$DO_LOCK" =~ ^[Yy]$ ]]; then
                        VAULT_LOCK_STATUS="locked"
                        _save_vault_config
                        echo -e "${RED}[✔] Vault is now LOCKED.${NC}"
                        log_action "Vault locked"
                    fi
                else
                    echo -e "\n${CYAN}[i] Unlocking the vault will allow access WITHOUT a password.${NC}"
                    read -e -p "    Unlock the vault now? (y/N): " DO_UNLOCK
                    if [[ "$DO_UNLOCK" =~ ^[Yy]$ ]]; then
                        VAULT_LOCK_STATUS="unlocked"
                        _save_vault_config
                        echo -e "${GREEN}[✔] Vault is now UNLOCKED.${NC}"
                        log_action "Vault unlocked"
                    fi
                fi
                pause
                ;;
            0) break ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# PERSONAL ACCESS TOKEN (PAT) VAULT MANAGER
# ==============================================================================
manage_pat_vault() {
    # Declare without 'local' so helper functions above can access them
    VAULT_FILE="${CONFIG_DIR}/pat_vault.env"
    VAULT_CONFIG="${CONFIG_DIR}/.vault_config"

    touch "$VAULT_FILE" 2>/dev/null
    chmod 600 "$VAULT_FILE" 2>/dev/null
    touch "$VAULT_CONFIG" 2>/dev/null
    chmod 600 "$VAULT_CONFIG" 2>/dev/null

    while true; do
        show_header
        _load_vault_config

        local lock_icon="🔓"
        if [[ "$VAULT_LOCK_STATUS" == "locked" ]]; then lock_icon="🔒"; fi

        echo -e "${YELLOW}${BOLD}🔑 PERSONAL ACCESS TOKEN (PAT) VAULT ${lock_icon}${NC}\n"
        echo -e "${CYAN}GitHub only shows a PAT once. This vault securely stores it for reuse.${NC}\n"
        echo -e "  ${GREEN}[1]${NC} 🌐 Create New Token (Opens browser + Save to Vault)"
        echo -e "  ${GREEN}[2]${NC} 📋 View Saved Tokens"
        echo -e "  ${RED}[3]${NC} 🗑️  Delete a Saved Token"
        echo -e "  ${CYAN}[4]${NC} 🔐 Vault Security Settings (Password & Lock Toggle)"
        echo -e "  ${GREEN}[0]${NC} Back to SSH Manager"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-4]: " PAT_CHOICE

        case $PAT_CHOICE in
            1)
                if ! _prompt_vault_access; then continue; fi

                echo -e "\n${CYAN}What type of token do you want to create?${NC}\n"
                echo -e "  ${GREEN}[1]${NC} Fine-grained token (Recommended - restrict to specific repos)"
                echo -e "  ${GREEN}[2]${NC} Classic token (Legacy - global account access)"
                echo -e "  ${GREEN}[0]${NC} Cancel"
                read -e -p "Select [0-2]: " TOKEN_TYPE

                local token_url=""
                case $TOKEN_TYPE in
                    1) token_url="https://github.com/settings/personal-access-tokens/new" ;;
                    2) token_url="https://github.com/settings/tokens/new" ;;
                    *) continue ;;
                esac

                echo -e "\n${GREEN}[✔] Attempting to open your browser to GitHub...${NC}"
                echo -e "${YELLOW}[i] If your browser didn't open (e.g., headless server/SSH), copy the URL below.${NC}"
                echo -e "${YELLOW}[i] Complete the creation in your browser (tick your desired boxes).${NC}"
                echo -e "${YELLOW}[i] Copy the generated token (starts with github_pat_ or ghp_).${NC}\n"

                echo -e "${CYAN}${BOLD}──────────── GITHUB URL ────────────${NC}"
                echo -e "${GREEN}${token_url}${NC}"
                echo -e "${CYAN}${BOLD}────────────────────────────────────${NC}\n"

                if command -v xdg-open &>/dev/null; then
                    xdg-open "$token_url" 2>/dev/null &
                elif command -v open &>/dev/null; then
                    open "$token_url" 2>/dev/null &
                fi

                read -e -p "Paste your new token here (or press ENTER to cancel): " NEW_TOKEN

                if [[ -z "$NEW_TOKEN" ]]; then
                    echo -e "${YELLOW}[i] Cancelled.${NC}"
                    pause
                    continue
                fi

                if [[ ! "$NEW_TOKEN" =~ ^(ghp_|github_pat_) ]]; then
                    echo -e "${RED}[!] Invalid token format. Tokens must start with 'ghp_' or 'github_pat_'.${NC}"
                    pause
                    continue
                fi

                echo ""
                read -e -p "Enter a name/alias for this token (e.g., 'Jenkins-Kali-Server'): " TOKEN_ALIAS
                if [[ -z "$TOKEN_ALIAS" ]]; then
                    TOKEN_ALIAS="token-$(date '+%Y%m%d-%H%M%S')"
                fi

                if grep -q "^${TOKEN_ALIAS}=" "$VAULT_FILE" 2>/dev/null; then
                    echo -e "${RED}[!] A token with this alias already exists. Please use a different name.${NC}"
                    pause
                    continue
                fi

                echo "${TOKEN_ALIAS}=${NEW_TOKEN}" >> "$VAULT_FILE"
                chmod 600 "$VAULT_FILE"

                echo -e "\n${GREEN}${BOLD}[✔] Token securely saved to vault as '${TOKEN_ALIAS}'!${NC}"
                log_action "Saved new PAT to vault: ${TOKEN_ALIAS}"
                pause
                ;;

            2)
                if ! _prompt_vault_access; then continue; fi

                echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
                echo -e "${BOLD}              SAVED PERSONAL ACCESS TOKENS${NC}"
                echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"

                if [[ ! -s "$VAULT_FILE" ]]; then
                    echo -e "${YELLOW}[i] Vault is empty. Create a token first (Option 1).${NC}"
                else
                    local idx=1
                    while IFS='=' read -r alias token; do
                        [[ -z "$alias" ]] && continue
                        printf "  ${GREEN}[%d]${NC} ${BOLD}%-25s${NC}\n" "$idx" "$alias"
                        echo -e "      ${CYAN}Token: ${GREEN}${token}${NC}\n"
                        idx=$((idx+1))
                    done < "$VAULT_FILE"
                fi
                pause
                ;;

            3)
                if ! _prompt_vault_access; then continue; fi

                if [[ ! -s "$VAULT_FILE" ]]; then
                    echo -e "\n${YELLOW}[i] Vault is empty. Nothing to delete.${NC}"
                    pause
                    continue
                fi

                echo -e "\n${RED}${BOLD}SELECT A TOKEN TO DELETE:${NC}\n"
                local idx=1
                while IFS='=' read -r alias token; do
                    [[ -z "$alias" ]] && continue
                    printf "  ${RED}[%d]${NC} ${BOLD}%-25s${NC}\n" "$idx" "$alias"
                    idx=$((idx+1))
                done < "$VAULT_FILE"

                echo ""
                read -e -p "Enter token number to delete (or ENTER to cancel): " DEL_NUM

                if [[ -n "$DEL_NUM" ]]; then
                    local current_idx=1
                    local temp_file=$(mktemp)
                    local deleted_alias=""
                    local deleted_token=""

                    while IFS='=' read -r alias token; do
                        if [[ "$current_idx" -ne "$DEL_NUM" ]]; then
                            echo "${alias}=${token}" >> "$temp_file"
                        else
                            deleted_alias="$alias"
                            deleted_token="$token"
                        fi
                        current_idx=$((current_idx+1))
                    done < "$VAULT_FILE"

                    echo ""
                    echo -e "${YELLOW}[?] How do you want to delete '${deleted_alias}'?${NC}"
                    echo -e "  ${GREEN}[L]${NC} Local vault only (Token stays active on GitHub)"
                    echo -e "  ${RED}[B]${NC} Both Local + GitHub (Revoke from GitHub account)"
                    read -e -p "    Choose [L/B] (Default: L): " DEL_SCOPE

                    if [[ "$DEL_SCOPE" =~ ^[Bb]$ ]]; then
                        echo -e "\n${CYAN}--> Searching GitHub for a token named '${deleted_alias}'...${NC}"

                        # GH_PAGER=cat prevents the blank 'less' pager screen on errors
                        local gh_token_id
                        gh_token_id=$(GH_PAGER=cat gh api user/personal-access-tokens --jq ".[] | select(.name == \"${deleted_alias}\") | .id" 2>/dev/null)

                        if [[ -n "$gh_token_id" ]]; then
                            echo -e "${CYAN}--> Found on GitHub (ID: ${gh_token_id}). Revoking...${NC}"
                            if GH_PAGER=cat gh api -X DELETE "user/personal-access-tokens/${gh_token_id}" 2>/dev/null; then
                                echo -e "${GREEN}[✔] Successfully revoked from GitHub!${NC}"
                                log_action "Revoked GitHub token: ${deleted_alias} (ID: ${gh_token_id})"
                            else
                                echo -e "${RED}[!] API failed to revoke. Opening browser to do it manually...${NC}"
                                xdg-open "https://github.com/settings/personal-access-tokens" 2>/dev/null &
                            fi
                        else
                            echo -e "${YELLOW}[i] Could not auto-find '${deleted_alias}' on GitHub.${NC}"
                            echo -e "${CYAN}    (This usually means it's a Classic token, or named differently on GitHub).${NC}"
                            echo -e "${RED}    ⚠️  OPENING BROWSER TO REVOKE MANUALLY...${NC}"
                        fi

                        # ALWAYS print the manual URLs so headless/SSH users aren't left stranded
                        echo -e "\n${CYAN}${BOLD}──────── MANUAL REVOKE URLS ────────${NC}"
                        echo -e "${GREEN}    Fine-Grained Tokens: https://github.com/settings/personal-access-tokens${NC}"
                        echo -e "${GREEN}    Classic Tokens:      https://github.com/settings/tokens${NC}"
                        echo -e "${CYAN}${BOLD}─────────────────────────────────────${NC}\n"

                        # Try to open the browser automatically to the most likely page (Fine-grained)
                        if command -v xdg-open &>/dev/null; then
                            xdg-open "https://github.com/settings/personal-access-tokens" 2>/dev/null &
                        elif command -v open &>/dev/null; then
                            open "https://github.com/settings/personal-access-tokens" 2>/dev/null &
                        fi
                        echo ""
                    fi

                    # Remove from local vault
                    mv "$temp_file" "$VAULT_FILE"
                    chmod 600 "$VAULT_FILE"
                    echo -e "${GREEN}[✔] Removed '${deleted_alias}' from local vault.${NC}"
                    log_action "Deleted PAT from local vault: ${deleted_alias}"
                fi
                pause
                ;;

            4)
                # SECURITY FIX: Ask for vault password before allowing access to security settings
                if ! _prompt_vault_access; then continue; fi

                _manage_vault_security_settings
                ;;

            0) break ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}
# ==============================================================================
# MODULE 1: Identity & Remote URL Manager
# ==============================================================================
manage_identity() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}[+] Module 1: Identity & Remote URL Manager${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Check / Set Global Git User & Email"
        echo -e "  ${GREEN}[2]${NC} 📡 SSH Manager (Keys, Services & GitHub Integration)"
        echo -e "  ${GREEN}[3]${NC} 🔑 Personal Access Token (PAT) Vault Manager"
        echo -e "  ${GREEN}[4]${NC} Inspect & Manage Remote Repository URLs"
        echo -e "  ${GREEN}[0]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-4]: " ID_CHOICE

        case $ID_CHOICE in
            1)
                echo -e "\n${CYAN}Current Configuration:${NC}"
                echo "  Name:  $(git config --global user.name || echo 'Not set')"
                echo "  Email: $(git config --global user.email || echo 'Not set')"
                read -e -p "Enter new global user.name (ENTER to skip): " NEW_NAME
                read -e -p "Enter new global user.email (ENTER to skip): " NEW_EMAIL
                if [[ -n "$NEW_NAME" ]]; then
                    git config --global user.name "$NEW_NAME"
                    log_action "user.name set to ${NEW_NAME}"
                fi
                if [[ -n "$NEW_EMAIL" ]]; then
                    git config --global user.email "$NEW_EMAIL"
                    log_action "user.email updated"
                fi
                pause
                ;;
            2)
                manage_ssh_menu
                ;;
            3)
                manage_pat_vault
                ;;
            4)
                while true; do
                    show_header
                    echo -e "${YELLOW}${BOLD}📌 REMOTE REPOSITORY URL MANAGER${NC}\n"
                    GIT_PAGER=cat git remote -v 2>/dev/null || echo "No remotes set."
                    echo -e "\n  ${GREEN}[1]${NC} Change / Set New Remote URL"
                    echo -e "  ${GREEN}[2]${NC} Toggle Protocol (HTTPS/SSH)"
                    echo -e "  ${GREEN}[0]${NC} Back"
                    read -e -p "Select choice [0-2]: " REMOTE_CHOICE
                    case $REMOTE_CHOICE in
                        1)
                            read -e -p "Enter fresh GitHub Remote URL: " RAW_URL
                            NEW_URL=$(clean_remote_url "$RAW_URL")
                            if [[ -n "$NEW_URL" ]]; then
                                git remote remove origin 2>/dev/null || true
                                run_git remote add origin "$NEW_URL"
                                echo -e "${GREEN}[✔] Remote 'origin' updated.${NC}"
                            fi
                            pause
                            ;;
                        2)
                            CURRENT_URL=$(clean_remote_url "$(git remote get-url origin 2>/dev/null || echo "")")
                            if [[ "$CURRENT_URL" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
                                run_git remote set-url origin "git@github.com:${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}.git"
                            elif [[ "$CURRENT_URL" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)?$ ]]; then
                                run_git remote set-url origin "https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}.git"
                            fi
                            pause
                            ;;
                        0) break ;;
                    esac
                done
                ;;
            0) break ;;
        esac
    done
}

# ==============================================================================
# SMART CONFLICT RESOLVER — with Force Push / Force Pull ROLLBACK
# State files live in ~/.git-wizard/rollback/ (one pair per repo, last op only)
# ==============================================================================
ROLLBACK_DIR="${CONFIG_DIR}/rollback"

_gw_rb_file() {   # $1 = push | pull
    mkdir -p "$ROLLBACK_DIR"
    local key
    key=$(printf '%s' "$TARGET_REPO_DIR" | cksum | awk '{print $1}')
    echo "${ROLLBACK_DIR}/${key}.$1"
}

smart_force_push() {
    local BRANCH="$1" TS REMOTE_SHA="" LOCAL_SHA
    if ! confirm_destructive "Force push '${BRANCH}' — overwrites the remote branch"; then
        echo -e "${YELLOW}[i] Cancelled.${NC}"; return
    fi
    create_safety_backup "pre-force-push"
    TS=$(date '+%Y%m%d-%H%M%S')
    LOCAL_SHA=$(git rev-parse HEAD 2>/dev/null)

    if [[ "$DRY_RUN" != "true" ]]; then
        echo -e "${CYAN}--> Recording current remote state (for rollback)...${NC}"
        if ! git fetch origin 2>/dev/null; then
            echo -e "${RED}[!] Fetch failed — rollback point can't be recorded. Aborting, nothing pushed.${NC}"
            return
        fi
        REMOTE_SHA=$(git rev-parse --verify -q "origin/${BRANCH}")
    fi

    if [[ -n "$REMOTE_SHA" ]]; then
        local RTAG="backup/remote-${BRANCH//\//-}-${TS}"
        git tag "$RTAG" "$REMOTE_SHA"
        cat > "$(_gw_rb_file push)" <<EOF
RB_BRANCH="${BRANCH}"
RB_REMOTE_SHA="${REMOTE_SHA}"
RB_PUSHED_SHA="${LOCAL_SHA}"
RB_TAG="${RTAG}"
RB_TIME="${TS}"
EOF
        echo -e "${GREEN}[✔] Rollback point saved: ${CYAN}${RTAG}${NC} ${GREEN}(${REMOTE_SHA:0:8})${NC}"
        log_action "Force-push rollback point saved: ${RTAG}"
    elif [[ "$DRY_RUN" != "true" ]]; then
        echo -e "${YELLOW}[i] origin/${BRANCH} doesn't exist yet — nothing to roll back to.${NC}"
        rm -f "$(_gw_rb_file push)"
    fi

    # --force-with-lease also protects you if someone pushed between fetch and push
    local push_args=(push origin "$BRANCH")
    if [[ -n "$REMOTE_SHA" ]]; then
        push_args+=("--force-with-lease=${BRANCH}:${REMOTE_SHA}")
    else
        push_args+=(--force)
    fi
    if run_git "${push_args[@]}"; then
        echo -e "${GREEN}[✔] Force push done. Undo it anytime via 'Rollback Last Force Push'.${NC}"
    else
        echo -e "${RED}[!] Force push failed (branch protection? someone pushed meanwhile?).${NC}"
        rm -f "$(_gw_rb_file push)"
    fi
}

rollback_force_push() {
    local f; f="$(_gw_rb_file push)"
    if [[ ! -f "$f" ]]; then
        echo -e "${YELLOW}[i] No force push recorded for this repo — nothing to roll back.${NC}"; return
    fi
    local RB_BRANCH RB_REMOTE_SHA RB_PUSHED_SHA RB_TAG RB_TIME
    source "$f"

    echo -e "${CYAN}Last force push:${NC} branch ${BOLD}${RB_BRANCH}${NC} at ${RB_TIME}"
    echo -e "${CYAN}Remote was at:${NC}   ${RB_REMOTE_SHA:0:8}  (tag ${RB_TAG})"

    if ! git cat-file -e "${RB_REMOTE_SHA}^{commit}" 2>/dev/null; then
        echo -e "${RED}[!] The old commit no longer exists locally (tag deleted / repo re-cloned). Can't roll back.${NC}"; return
    fi
    git fetch origin 2>/dev/null
    local CURRENT
    CURRENT=$(git rev-parse --verify -q "origin/${RB_BRANCH}")
    if [[ -z "$CURRENT" ]]; then
        echo -e "${RED}[!] origin/${RB_BRANCH} no longer exists on the remote.${NC}"; return
    fi
    if [[ "$CURRENT" != "$RB_PUSHED_SHA" ]]; then
        echo -e "${YELLOW}[!] WARNING: the remote has changed since your force push (now ${CURRENT:0:8}).${NC}"
        echo -e "${YELLOW}    Rolling back will also discard those newer remote commits.${NC}"
    fi

    if ! confirm_destructive "Roll remote '${RB_BRANCH}' back to ${RB_REMOTE_SHA:0:8} (undo your force push)"; then
        echo -e "${YELLOW}[i] Cancelled.${NC}"; return
    fi

    # Make the rollback itself reversible
    [[ "$DRY_RUN" != "true" ]] && git tag "backup/pre-rollback-push-$(date '+%Y%m%d-%H%M%S')" "$CURRENT"

    if run_git push origin "${RB_REMOTE_SHA}:refs/heads/${RB_BRANCH}" \
            "--force-with-lease=refs/heads/${RB_BRANCH}:${CURRENT}"; then
        [[ "$DRY_RUN" != "true" ]] && rm -f "$f"
        echo -e "${GREEN}[✔] Remote '${RB_BRANCH}' restored to ${RB_REMOTE_SHA:0:8}.${NC}"
        echo -e "${CYAN}    Your LOCAL branch still has the new commits — use 'Force Pull' if you want local to match GitHub again.${NC}"
        log_action "Force-push ROLLED BACK: ${RB_BRANCH} -> ${RB_REMOTE_SHA}"
    else
        echo -e "${RED}[!] Rollback push failed (branch protection or remote changed again).${NC}"
    fi
}

smart_force_pull() {
    local BRANCH="$1" TS HEAD_SHA STASH_MSG=""
    if ! confirm_destructive "Force pull — overwrites local '${BRANCH}' with origin/${BRANCH}"; then
        echo -e "${YELLOW}[i] Cancelled.${NC}"; return
    fi
    echo -e "${CYAN}--> Fetching...${NC}"
    if ! run_git fetch origin; then
        echo -e "${RED}[!] Fetch failed. Nothing was changed.${NC}"; return
    fi
    if [[ "$DRY_RUN" != "true" ]] && ! git rev-parse --verify -q "origin/${BRANCH}" >/dev/null; then
        echo -e "${RED}[!] origin/${BRANCH} doesn't exist. Nothing was changed.${NC}"; return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        run_git reset --hard "origin/${BRANCH}"; run_git clean -fd; return
    fi

    TS=$(date '+%Y%m%d-%H%M%S')
    HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
    local PTAG="backup/pre-force-pull-${BRANCH//\//-}-${TS}"
    [[ -n "$HEAD_SHA" ]] && git tag "$PTAG" "$HEAD_SHA"

    # Save uncommitted + untracked files too (reset --hard / clean -fd would destroy them)
    if [[ -n "$(git status --porcelain)" ]]; then
        STASH_MSG="gw-force-pull-${TS}"
        if ! git stash push -u -m "$STASH_MSG" >/dev/null 2>&1; then
            echo -e "${RED}[!] Couldn't stash your local changes — aborting so nothing is lost.${NC}"; return
        fi
        echo -e "${GREEN}[✔] Uncommitted/untracked files saved in stash '${STASH_MSG}'.${NC}"
    fi

    cat > "$(_gw_rb_file pull)" <<EOF
RB_BRANCH="${BRANCH}"
RB_HEAD_SHA="${HEAD_SHA}"
RB_TAG="${PTAG}"
RB_STASH_MSG="${STASH_MSG}"
RB_TIME="${TS}"
EOF
    echo -e "${GREEN}[✔] Rollback point saved: ${CYAN}${PTAG}${NC}"
    log_action "Force-pull rollback point saved: ${PTAG} (stash: ${STASH_MSG:-none})"

    run_git reset --hard "origin/${BRANCH}"
    run_git clean -fd
    echo -e "${GREEN}[✔] Local '${BRANCH}' now matches origin/${BRANCH}. Undo via 'Rollback Last Force Pull'.${NC}"
}

rollback_force_pull() {
    local f; f="$(_gw_rb_file pull)"
    if [[ ! -f "$f" ]]; then
        echo -e "${YELLOW}[i] No force pull recorded for this repo — nothing to roll back.${NC}"; return
    fi
    local RB_BRANCH RB_HEAD_SHA RB_TAG RB_STASH_MSG RB_TIME
    source "$f"

    echo -e "${CYAN}Last force pull:${NC} branch ${BOLD}${RB_BRANCH}${NC} at ${RB_TIME}"
    echo -e "${CYAN}Local was at:${NC}    ${RB_HEAD_SHA:0:8}  (tag ${RB_TAG})"
    [[ -n "$RB_STASH_MSG" ]] && echo -e "${CYAN}Uncommitted files:${NC} saved in stash '${RB_STASH_MSG}' (will be restored)"

    if [[ -z "$RB_HEAD_SHA" ]] || ! git cat-file -e "${RB_HEAD_SHA}^{commit}" 2>/dev/null; then
        echo -e "${RED}[!] The old commit no longer exists locally. Can't roll back.${NC}"; return
    fi
    if ! confirm_destructive "Restore local '${RB_BRANCH}' to ${RB_HEAD_SHA:0:8} (undo your force pull)"; then
        echo -e "${YELLOW}[i] Cancelled.${NC}"; return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        run_git checkout "$RB_BRANCH"; run_git reset --hard "$RB_HEAD_SHA"
        [[ -n "$RB_STASH_MSG" ]] && echo -e "${YELLOW}[DRY-RUN] Would pop stash '${RB_STASH_MSG}'${NC}"
        return
    fi

    # Anything done since the force pull is saved first, so this is reversible too
    local NOW; NOW=$(date '+%Y%m%d-%H%M%S')
    git tag "backup/pre-rollback-pull-${NOW}" HEAD 2>/dev/null
    if [[ -n "$(git status --porcelain)" ]]; then
        git stash push -u -m "gw-pre-rollback-${NOW}" >/dev/null 2>&1
        echo -e "${YELLOW}[i] Your current uncommitted changes were stashed as 'gw-pre-rollback-${NOW}'.${NC}"
    fi

    local cur; cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    [[ "$cur" != "$RB_BRANCH" ]] && git checkout "$RB_BRANCH"

    if ! git reset --hard "$RB_HEAD_SHA"; then
        echo -e "${RED}[!] Reset failed.${NC}"; return
    fi
    echo -e "${GREEN}[✔] Branch '${RB_BRANCH}' restored to ${RB_HEAD_SHA:0:8}.${NC}"

    if [[ -n "$RB_STASH_MSG" ]]; then
        local ref
        ref=$(git stash list | grep -F "$RB_STASH_MSG" | head -1 | cut -d: -f1)
        if [[ -n "$ref" ]] && git stash pop "$ref" >/dev/null 2>&1; then
            echo -e "${GREEN}[✔] Your uncommitted/untracked files are back.${NC}"
        else
            echo -e "${YELLOW}[!] Couldn't auto-restore the stash. Check 'git stash list' for '${RB_STASH_MSG}'.${NC}"
        fi
    fi
    rm -f "$f"
    log_action "Force-pull ROLLED BACK: ${RB_BRANCH} -> ${RB_HEAD_SHA}"
}

smart_conflict_resolver() {
    while true; do
        show_header
        local BRANCH
        BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        local push_note="" pull_note=""
        [[ -f "$(_gw_rb_file push)" ]] && push_note=" ${GREEN}(available)${NC}"
        [[ -f "$(_gw_rb_file pull)" ]] && pull_note=" ${GREEN}(available)${NC}"

        echo -e "${YELLOW}${BOLD}🛠️  SMART CONFLICT PUSH RESOLVER${NC}  ${CYAN}(branch: ${BRANCH})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Safe Pull & Rebase"
        echo -e "  ${GREEN}[2]${NC} Safe Pull & Merge"
        echo -e "  ${RED}[3]${NC} Force Push ${RED}(Overwrites remote!)${NC}"
        echo -e "  ${RED}[4]${NC} Force Pull ${RED}(Overwrites local!)${NC}"
        echo -e "  ${GREEN}[5]${NC} ⏪ Rollback Last Force Push${push_note}"
        echo -e "  ${GREEN}[6]${NC} ⏪ Rollback Last Force Pull${pull_note}"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select strategy [0-6]: " STRAT
        case $STRAT in
            1)
                if run_git pull origin "$BRANCH" --rebase; then
                    run_git push origin "$BRANCH" || echo -e "${YELLOW}[!] Pull succeeded but push failed.${NC}"
                else
                    echo -e "${RED}[!] Pull/rebase failed — resolve conflicts manually.${NC}"
                fi
                pause ;;
            2)
                if run_git pull origin "$BRANCH" --rebase=false --allow-unrelated-histories; then
                    run_git push origin "$BRANCH" || echo -e "${YELLOW}[!] Pull succeeded but push failed.${NC}"
                else
                    echo -e "${RED}[!] Pull/merge failed — resolve conflicts manually.${NC}"
                fi
                pause ;;
            3) smart_force_push "$BRANCH"; pause ;;
            4) smart_force_pull "$BRANCH"; pause ;;
            5) rollback_force_push; pause ;;
            6) rollback_force_pull; pause ;;
            0) break ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# MODULE 2: Repository Setup, Status & Reset Engine
# ==============================================================================
manage_repo() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}[+] Module 2: Repository Setup, Status & Reset Engine${NC}\n"
        echo -e "  ${GREEN}[1]${NC} 1-Click Complete Repo Setup"
        echo -e "  ${RED}[2]${NC} 1-Click Complete Repo Destroy"
        echo -e "  ${GREEN}[3]${NC} Quick Push (Add -> Commit -> Push)"
        echo -e "  ${GREEN}[4]${NC} Inspect Working Directory Status"
        echo -e "  ${GREEN}[5]${NC} Interactive Git Reset & Undo Utility"
        echo -e "  ${GREEN}[6]${NC} Smart Conflict Push Resolver"
        echo -e "  ${GREEN}[7]${NC} Generate Tailored .gitignore File"
        echo -e "  ${GREEN}[8]${NC} Repo History Viewer"
        echo -e "      ${CYAN}Shows commit graph across all branches (uses 'delta' for prettier diffs if installed).${NC}"
        echo -e "  ${GREEN}[9]${NC} Repository Pre-Commit Hook"
        echo -e "      ${CYAN}Enable or disable pre-commit hooks for this repo.${NC}"
        echo -e "  ${GREEN}[0]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-9]: " REPO_CHOICE

        case $REPO_CHOICE in
            1) one_click_repo_setup ;;
            2) one_click_repo_destroy ;;
            3)
                run_git add .
                if [[ -z "$(git status --porcelain)" ]]; then
                    show_uptodate_celebration
                else
                    read -e -p "Enter commit message: " MSG
                    if [[ -z "$MSG" ]]; then
                        echo -e "${RED}Message required!${NC}"
                        pause
                        continue
                    fi

                    if commit_with_hook_retry "$MSG"; then
                        BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
                        run_git push origin "$BRANCH" || echo -e "${YELLOW}[!] Push rejected. Use Option [6].${NC}"
                    fi
                fi
                pause
                ;;
            4)
                show_header
                STATUS_OUT=$(git status --porcelain)
                [[ -z "$STATUS_OUT" ]] && show_uptodate_celebration || GIT_PAGER=cat git status
                pause
                ;;
            5)
                while true; do
                    show_header
                    echo -e "${YELLOW}${BOLD}📌 INTERACTIVE GIT RESET & UNDO UTILITY${NC}\n"
                    echo -e "  ${GREEN}[1]${NC} Unstage All Files"
                    echo -e "  ${GREEN}[2]${NC} Discard All Uncommitted Local Changes"
                    echo -e "  ${GREEN}[3]${NC} Soft Rollback Last Commit"
                    echo -e "  ${RED}[4]${NC} Hard Rollback Last Commit ${RED}(DESTROYS work!)${NC}"
                    echo -e "  ${RED}${BOLD}[5]${NC} ${RED}${BOLD}Force Sync with Origin${NC} ${RED}(Nuclear reset — matches GitHub exactly, DESTROYS local divergence!)${NC}"
                    echo -e "      ${CYAN}Use this when your local branch is badly tangled/diverged and you just want it to match origin/main exactly.${NC}"
                    echo -e "  ${GREEN}[0]${NC} Back"
                    read -e -p "Select choice [0-5]: " RESET_CHOICE
                    case $RESET_CHOICE in
                        1) run_git reset HEAD; pause ;;
                        2)
                            if confirm_destructive "Discard all uncommitted local changes"; then
                                create_safety_backup "pre-discard"
                                run_git checkout -- . 2>/dev/null || true
                                run_git clean -fd 2>/dev/null || true
                            fi
                            pause
                            ;;
                        3) run_git reset --soft HEAD~1; pause ;;
                        4)
                            if confirm_destructive "Hard rollback last commit — PERMANENT data loss risk"; then
                                create_safety_backup "pre-hard-reset"
                                run_git reset --hard HEAD~1
                            fi
                            pause
                            ;;
                        5) force_sync_with_origin ;;
                        0) break ;;
                    esac
                done
                ;;
            6) smart_conflict_resolver ;;
            7)
                echo -e "  [1] Python  [2] Node.js  [3] Go/Linux"
                read -e -p "Choice [1-3]: " GI_CHOICE
                case $GI_CHOICE in
                    1) printf '__pycache__/\n*.py[cod]\nvenv/\n.env\n.pytest_cache/\n' > .gitignore ;;
                    2) printf 'node_modules/\nbuild/\ndist/\n.env\n.env.local\nnpm-debug.log*\n' > .gitignore ;;
                    3) printf '*.exe\n*.o\n*.so\nbin/\n.env\n*.tar.gz\n' > .gitignore ;;
                esac
                echo -e "${GREEN}[✔] .gitignore created!${NC}"
                log_action ".gitignore generated"
                pause
                ;;
            8) repo_history_viewer ;;
            9) repo_precommit_hook_menu ;;
            0) break ;;
        esac
    done
}

one_click_repo_setup() {
    show_header
    echo -e "${YELLOW}${BOLD}🚀 1-CLICK COMPLETE REPO SETUP${NC}\n"

    local folder_name
    folder_name="$(basename "$TARGET_REPO_DIR")"
    echo -e "${CYAN}Folder detected: ${BOLD}${folder_name}${NC}"
    echo -e "${CYAN}This repo will be created on your Git host using this exact name,${NC}"
    echo -e "${CYAN}so the push always matches — no manual remote-URL headaches.${NC}\n"

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        run_git init
        run_git branch -M main 2>/dev/null || true
    fi

    if ! ensure_vcs_ready; then
        echo -e "${YELLOW}[i] Couldn't set up ${VCS_PROVIDER:-a Git host} CLI. Falling back to manual remote-URL entry.${NC}"
        run_git add .
        if [[ -n "$(git status --porcelain)" ]]; then
            read -e -p "Commit message [default: Initial commit]: " MSG
            commit_with_hook_retry "${MSG:-Initial commit}"
        fi
        read -e -p "Enter Remote URL (or ENTER to keep current): " RAW_URL
        REMOTE_URL=$(clean_remote_url "$RAW_URL")
        if [[ -n "$REMOTE_URL" ]]; then
            git remote remove origin 2>/dev/null || true
            run_git remote add origin "$REMOTE_URL"
        fi
        run_git push -u origin main || echo -e "${YELLOW}[!] Push rejected. Use Option [5] to resolve.${NC}"
        pause
        return
    fi

    read -e -p "Repo name [ENTER to use folder name '${folder_name}']: " CUSTOM_NAME
    local repo_name="${CUSTOM_NAME:-$folder_name}"
    echo -e "  [1] Public  [2] Private"
    read -e -p "Visibility [1-2, default 1]: " VIS_CHOICE
    local vis="public"
    [[ "$VIS_CHOICE" == "2" ]] && vis="private"

    echo -e "\n${CYAN}--> Creating '${repo_name}' (${vis}) on ${VCS_PROVIDER^}...${NC}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would create ${VCS_PROVIDER} repo: ${repo_name} (${vis})${NC}"
    else
        if ! vcs_create_repo "$repo_name" "$vis"; then
            echo -e "${RED}[!] Repo creation failed (name may already exist, or a permissions issue).${NC}"
            echo -e "${YELLOW}[i] If it already exists, that's fine — continuing to link/push to it.${NC}"
        fi
        log_action "Created ${VCS_PROVIDER} repo: ${repo_name} (${vis}) via 1-click setup"
    fi

    run_git add .
    if [[ -z "$(git status --porcelain)" ]]; then
        echo -e "${YELLOW}[i] Nothing to commit.${NC}"
    else
        read -e -p "Commit message [default: Initial commit]: " MSG
        commit_with_hook_retry "${MSG:-Initial commit}"
    fi

    local uname full_name urlpair ssh_url https_url chosen_url
    uname=$(vcs_my_username)
    if [[ -n "$uname" ]]; then
        full_name="${uname}/${repo_name}"
        urlpair=$(vcs_get_repo_url "$full_name")
        ssh_url="${urlpair%%|*}"
        https_url="${urlpair##*|}"
        if [[ -n "$ssh_url" ]]; then
            echo -e "\n${CYAN}Which URL protocol would you like to push with?${NC}"
            echo -e "  [1] SSH   ${CYAN}(git@${VCS_PROVIDER}.com:...)${NC}"
            echo -e "  [2] HTTPS ${CYAN}(https://${VCS_PROVIDER}.com/...)${NC}"
            read -e -p "Choice [1-2, default 1]: " PROTO_CHOICE
            if [[ "$PROTO_CHOICE" == "2" ]]; then
                chosen_url="$https_url"
            else
                chosen_url="$ssh_url"
            fi
            git remote remove origin 2>/dev/null || true
            run_git remote add origin "$chosen_url"
        fi
    fi

    if ! git remote get-url origin &>/dev/null; then
        echo -e "${YELLOW}[i] Couldn't auto-detect the new repo's URL.${NC}"
        read -e -p "Paste the Remote URL manually: " RAW_URL
        REMOTE_URL=$(clean_remote_url "$RAW_URL")
        if [[ -n "$REMOTE_URL" ]]; then
            git remote remove origin 2>/dev/null || true
            run_git remote add origin "$REMOTE_URL"
        fi
    fi

    run_git branch -M main 2>/dev/null || true
    if run_git push -u origin main; then
        echo -e "\n${GREEN}${BOLD}[✔] 1-Click Repo Setup complete!${NC}"
        local final_url
        final_url=$(git remote get-url origin 2>/dev/null || echo "")
        [[ -n "$final_url" ]] && echo -e "${GREEN}${BOLD}Remote URL to share:${NC} ${CYAN}${final_url}${NC}"
    else
        echo -e "${YELLOW}[!] Push rejected. Use Module 2 > Option [5] Smart Conflict Push Resolver.${NC}"
    fi
    pause
}

# Extracts "owner/repo" from an origin URL, GitHub or GitLab, SSH or HTTPS.
parse_owner_repo_from_url() {
    local url="$1"
    if [[ "$url" =~ ^git@[^:]+:([^/]+)/(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
    elif [[ "$url" =~ ^https?://[^/]+/([^/]+)/(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
    else
        echo ""
    fi
}

one_click_repo_destroy() {
    show_header
    echo -e "${RED}${BOLD}💣 1-CLICK COMPLETE REPO DESTROY${NC}\n"

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}[!] '${TARGET_REPO_DIR}' is not a Git repository — nothing to detect here.${NC}"
        pause
        return
    fi
    if ! git remote get-url origin &>/dev/null; then
        echo -e "${RED}[!] No 'origin' remote set on this folder — can't tell which remote repo to destroy.${NC}"
        pause
        return
    fi

    local origin_url full_name
    origin_url=$(git remote get-url origin)
    detect_vcs_provider
    if [[ -z "$VCS_PROVIDER" ]]; then
        echo -e "${YELLOW}[i] Couldn't auto-detect GitHub vs GitLab from: ${origin_url}${NC}"
        if ! ensure_vcs_provider; then pause; return; fi
    fi

    full_name=$(parse_owner_repo_from_url "$origin_url")
    if [[ -z "$full_name" ]]; then
        echo -e "${RED}[!] Couldn't parse an owner/repo out of: ${origin_url}${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Detected remote repo: ${BOLD}${full_name}${NC} ${CYAN}(${VCS_PROVIDER^})${NC}"
    echo -e "${CYAN}Local folder: ${TARGET_REPO_DIR}${NC}\n"

    if ! ensure_vcs_ready; then
        pause
        return
    fi

    if ! confirm_destructive "PERMANENTLY DELETE '${full_name}' from ${VCS_PROVIDER^} — this cannot be undone"; then
        echo -e "${YELLOW}[i] Cancelled — nothing was destroyed.${NC}"
        pause
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would delete remote repo: ${full_name}${NC}"
    else
        local del_out del_code
        del_out=$(vcs_delete_repo "$full_name" 2>&1)
        del_code=$?
        if [[ $del_code -ne 0 ]]; then
            echo -e "${RED}${BOLD}⚠️  Delete failed:${NC}\n${YELLOW}${del_out}${NC}"
            if echo "$del_out" | grep -qi "delete_repo\|scope\|403\|permission"; then
                if [[ "$VCS_PROVIDER" == "github" ]]; then
                    echo -e "${CYAN}Fix: ${GREEN}gh auth refresh -h github.com -s delete_repo${NC}"
                else
                    echo -e "${CYAN}Fix: ${GREEN}glab auth login --scopes api,delete_repo${NC}"
                fi
            fi
            pause
            return
        fi
        echo -e "${GREEN}[✔] Deleted '${full_name}' from ${VCS_PROVIDER^}.${NC}"
        log_action "DESTROYED remote repo: ${full_name} (${VCS_PROVIDER}) via 1-click destroy"
    fi

    read -e -p "Also remove the local 'origin' remote link here (keeps your local files/history)? (y/N): " RMORIGIN
    if [[ "$RMORIGIN" =~ ^[Yy]$ ]]; then
        git remote remove origin 2>/dev/null || true
        echo -e "${GREEN}[✔] Local 'origin' remote removed.${NC}"
    fi
    pause
}

# ==============================================================================
# MODULE 3: Advanced Branch Manager
# ==============================================================================
select_branch_interactive() {
    local prompt="$1"
    local branch_list
    branch_list=$(GIT_PAGER=cat git branch --format="%(refname:short)")
    if [[ -z "$branch_list" ]]; then
        echo -e "${RED}[!] No local branches found.${NC}"
        return 1
    fi
    local branches=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            branches+=("$line")
        fi
    done <<< "$branch_list"
    local selected=0 key=""
    tput civis 2>/dev/null || true
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}$prompt${NC}\n"
        for i in "${!branches[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}${BOLD}  ➔  ${branches[$i]} (Selected)${NC}"
            else
                echo -e "     ${branches[$i]}"
            fi
        done
        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            if [[ $key == "[A" ]]; then
                ((selected--)) || true
                if [[ $selected -lt 0 ]]; then selected=$((${#branches[@]} - 1)); fi
            elif [[ $key == "[B" ]]; then
                ((selected++)) || true
                if [[ $selected -ge ${#branches[@]} ]]; then selected=0; fi
            fi
        elif [[ $key == "" ]]; then
            tput cnorm 2>/dev/null || true
            SELECTED_BRANCH="${branches[$selected]}"
            return 0
        fi
    done
}

# --- Arrow-key selector for REMOTE branches, with author/date/message shown per row ---
select_remote_branch_interactive() {
    local prompt="$1"
    local raw_branches=()
    while IFS= read -r b; do
        local short="${b#origin/}"
        if [[ "$short" == "main" || "$short" == "master" || "$short" == "HEAD" ]]; then
            continue
        fi
        raw_branches+=("$short")
    done < <(git for-each-ref --format='%(refname:short)' refs/remotes/origin)

    if [[ ${#raw_branches[@]} -eq 0 ]]; then
        echo -e "${RED}[!] No remote branches available for review (besides main).${NC}"
        return 1
    fi

    local selected=0 key=""
    tput civis 2>/dev/null || true
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}$prompt${NC}\n"
        for i in "${!raw_branches[@]}"; do
            local info
            info=$(git log -1 --format='%an | %ar | %s' "origin/${raw_branches[$i]}" 2>/dev/null || echo "unknown")
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}${BOLD}  ➔  ${raw_branches[$i]}${NC}  ${CYAN}(${info})${NC}"
            else
                echo -e "     ${raw_branches[$i]}  ${CYAN}(${info})${NC}"
            fi
        done
        echo -e "\n${CYAN}[UP/DOWN to navigate, ENTER to review this branch, Q to cancel]${NC}"
        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            if [[ $key == "[A" ]]; then
                ((selected--)) || true
                if [[ $selected -lt 0 ]]; then selected=$((${#raw_branches[@]} - 1)); fi
            elif [[ $key == "[B" ]]; then
                ((selected++)) || true
                if [[ $selected -ge ${#raw_branches[@]} ]]; then selected=0; fi
            fi
        elif [[ $key == "" ]]; then
            tput cnorm 2>/dev/null || true
            SELECTED_BRANCH="${raw_branches[$selected]}"
            return 0
        elif [[ $key == "q" || $key == "Q" ]]; then
            tput cnorm 2>/dev/null || true
            return 1
        fi
    done
}

manage_branches() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}[+] Module 3: Advanced Branch & Remote Manager${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List All Branches"
        echo -e "  ${GREEN}[2]${NC} Create New Branch & Publish"
        echo -e "  ${GREEN}[3]${NC} Switch Branch"
        echo -e "  ${GREEN}[4]${NC} Delete Branch ${RED}(Local & Remote)${NC}"
        echo -e "  ${GREEN}[0]${NC} Back to Main Menu"
        read -e -p "Select choice [0-4]: " B_CHOICE
        case $B_CHOICE in
            1) show_header; GIT_PAGER=cat git branch -vv; echo; GIT_PAGER=cat git branch -r; pause ;;
            2)
                read -e -p "Enter new branch name: " NEW_B
                if [[ -n "$NEW_B" ]]; then
                    run_git checkout -b "$NEW_B"
                    run_git push -u origin "$NEW_B" || echo -e "${YELLOW}[!] Branch created locally but push failed. Check your remote/connection.${NC}"
                fi
                pause
                ;;
            3)
                if select_branch_interactive "📌 SELECT BRANCH TO SWITCH"; then
                    run_git checkout "$SELECTED_BRANCH"
                fi
                pause
                ;;
            4)
                if select_branch_interactive "📌 SELECT BRANCH TO PURGE"; then
                    CURRENT_B=$(git rev-parse --abbrev-ref HEAD)
                    if [[ "$SELECTED_BRANCH" == "$CURRENT_B" ]]; then
                        echo -e "${RED}[!] Cannot delete active branch.${NC}"
                    elif confirm_destructive "Delete branch '${SELECTED_BRANCH}' locally and remotely"; then
                        create_safety_backup "pre-branch-delete-${SELECTED_BRANCH}"
                        run_git branch -D "$SELECTED_BRANCH" 2>/dev/null || true
                        run_git push origin --delete "$SELECTED_BRANCH" 2>/dev/null || true
                    fi
                fi
                pause
                ;;
            0) break ;;
        esac
    done
}

# ==============================================================================
# MODULE 4: Conventional Commit Assistant
# ==============================================================================
commit_assistant() {
    show_header
    echo -e "${YELLOW}${BOLD}[+] Module 4: Conventional Commit Crafting Assistant${NC}\n"
    echo -e "  [1] feat:  [2] fix:  [3] docs:  [4] refactor:  [5] chore:"
    read -e -p "Select choice [1-5]: " C_TYPE
    local PREFIX=""
    case $C_TYPE in
        1) PREFIX="feat" ;; 2) PREFIX="fix" ;; 3) PREFIX="docs" ;;
        4) PREFIX="refactor" ;; 5) PREFIX="chore" ;;
        *) echo "Cancelled."; return ;;
    esac
    read -e -p "Enter short scope (optional): " SCOPE
    read -e -p "Enter clear commit description: " DESC
    if [[ -z "$DESC" ]]; then
        echo -e "${RED}Description required!${NC}"
        pause
        return
    fi
    local FINAL_MSG
    if [[ -n "$SCOPE" ]]; then
        FINAL_MSG="${PREFIX}(${SCOPE}): ${DESC}"
    else
        FINAL_MSG="${PREFIX}: ${DESC}"
    fi
    echo -e "\n${CYAN}Crafted Commit Message:${NC} ${BOLD}$FINAL_MSG${NC}"
    read -e -p "Execute commit now? (y/N): " DO_COMMIT
    if [[ "$DO_COMMIT" =~ ^[Yy]$ ]]; then
        run_git add .
        commit_with_hook_retry "$FINAL_MSG"
    fi
    pause
}

# ==============================================================================
# MODULE 5: TEAM & OPEN-SOURCE COLLABORATION
# ==============================================================================

# --- 5.1 Linear Workflow ---
linear_workflow() {
    show_header
    echo -e "${YELLOW}${BOLD}📐 LINEAR WORKFLOW (Solo / Sequential)${NC}\n"
    echo -e "${CYAN}Guideline: only one person works at a time. Always pull before you push.${NC}\n"
    local BRANCH
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    echo -e "${CYAN}--> Checking if local is behind remote before allowing push...${NC}"
    git fetch --quiet 2>/dev/null || true
    local behind
    behind=$(git rev-list --count "${BRANCH}..origin/${BRANCH}" 2>/dev/null || echo 0)
    if [[ "$behind" -gt 0 ]]; then
        echo -e "${RED}[!] Your branch is ${behind} commit(s) behind origin/${BRANCH}.${NC}"
        echo -e "${YELLOW}--> Pulling first (required in Linear Mode)...${NC}"
        run_git pull origin "$BRANCH" --rebase
    fi
    run_git add .
    if [[ -n "$(git status --porcelain)" ]]; then
        read -e -p "Enter commit message: " MSG
        if [[ -n "$MSG" ]]; then
            commit_with_hook_retry "$MSG"
        fi
    fi
    run_git push origin "$BRANCH" || echo -e "${YELLOW}[!] Push failed. Check your remote/connection, then retry.${NC}"
    echo -e "${GREEN}[✔] Linear workflow complete.${NC}"
    pause
}

# --- 5.2 Team Mode ---
team_mode_start_task() {
    show_header
    echo -e "${YELLOW}${BOLD}👥 TEAM MODE — Start My Task${NC}\n"
    echo -e "  [1] feature  [2] fix  [3] hotfix"
    read -e -p "Select branch type [1-3]: " TTYPE
    local PREFIX=""
    case $TTYPE in 1) PREFIX="feature" ;; 2) PREFIX="fix" ;; 3) PREFIX="hotfix" ;; *) echo "Cancelled."; pause; return ;; esac
    read -e -p "Short name for your task (e.g. login-bug): " TNAME
    if [[ -z "$TNAME" ]]; then
        echo -e "${RED}Name required.${NC}"
        pause
        return
    fi
    local BRANCH_NAME="${PREFIX}/${TNAME}"

    run_git checkout -b "$BRANCH_NAME"
    echo -e "${GREEN}[✔] Branch '${BRANCH_NAME}' created.${NC}"

    echo -e "\n${CYAN}--> Staging your changes on this branch...${NC}"
    run_git add .
    if [[ -z "$(git status --porcelain)" ]]; then
        echo -e "${YELLOW}[i] No changes to commit yet — branch created and published empty.${NC}"
    else
        read -e -p "Enter commit message describing your ${PREFIX}: " CMSG
        if [[ -z "$CMSG" ]]; then
            CMSG="${PREFIX}: ${TNAME}"
        fi
        commit_with_hook_retry "$CMSG"
    fi

    run_git push -u origin "$BRANCH_NAME" || { echo -e "${RED}[!] Push failed. Your branch and commit exist locally — check your remote/connection, then push manually.${NC}"; pause; return; }
    echo -e "${GREEN}[✔] Branch '${BRANCH_NAME}' published with your changes to GitHub. Never commit directly to main — the admin will review and merge this branch.${NC}"
    pause
}

team_mode_admin_dashboard() {
    show_header
    echo -e "${YELLOW}${BOLD}👥 TEAM MODE — Admin Dashboard${NC}\n"
    echo -e "${CYAN}--> Fetching latest branch info from GitHub...${NC}"
    git fetch --all --quiet 2>/dev/null || true

    if ! select_remote_branch_interactive "📌 SELECT A BRANCH TO REVIEW (author | date | last message)"; then
        pause
        return
    fi
    local REVIEW_BRANCH="$SELECTED_BRANCH"

    show_header
    echo -e "${CYAN}--- Diff vs main for origin/${REVIEW_BRANCH} ---${NC}\n"
    GIT_PAGER=cat git diff "main...origin/${REVIEW_BRANCH}" || true
    echo -e "\n  [1] Merge into main   [2] Reject (skip, no changes)   [3] Cancel"
    read -e -p "Choice [1-3]: " MCHOICE
    case $MCHOICE in
        1)
            create_safety_backup "pre-merge-${REVIEW_BRANCH}"
            run_git checkout main
            run_git merge --no-ff "origin/${REVIEW_BRANCH}" -m "Merge branch '${REVIEW_BRANCH}' via git-wizard Team Mode"
            run_git push origin main || echo -e "${YELLOW}[!] Merge succeeded locally but push failed. Check your remote/connection, then push manually.${NC}"
            echo -e "${GREEN}[✔] Merged and pushed.${NC}"
            ;;
        2) echo -e "${YELLOW}[i] Skipped, no changes made.${NC}" ;;
        *) echo "Cancelled." ;;
    esac
    pause
}

team_mode() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}👥 TEAM MODE (Private repo, collaborators have write access)${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Start My Task"
        echo -e "      ${CYAN}You're a contributor: creates your branch, commits your changes, pushes it. Never touches main.${NC}"
        echo -e "  ${GREEN}[2]${NC} Admin Dashboard"
        echo -e "      ${CYAN}You're the repo owner: pick a teammate's branch (arrow keys), view its diff, merge or reject it.${NC}"
        echo -e "  ${GREEN}[3]${NC} Guidelines"
        echo -e "      ${CYAN}Quick rules for how Team Mode is meant to be used.${NC}"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-3]: " TCHOICE
        case $TCHOICE in
            1) team_mode_start_task ;;
            2) team_mode_admin_dashboard ;;
            3)
                show_header
                echo -e "${CYAN}${BOLD}TEAM MODE GUIDELINES${NC}\n"
                echo -e "- Never commit directly to main."
                echo -e "- Always create a feature/fix/hotfix branch for your work."
                echo -e "- The repo admin reviews and merges via the Admin Dashboard."
                echo -e "- This requires you to be added as a Collaborator on the repo."
                pause
                ;;
            0) break ;;
        esac
    done
}

# --- 5.3 Open-Source Contributor Mode ---
oss_setup_fork() {
    show_header
    echo -e "${YELLOW}${BOLD}🍴 Detect / Setup Fork${NC}\n"
    if git remote get-url upstream &>/dev/null; then
        echo -e "${GREEN}[✔] 'upstream' remote already configured: $(git remote get-url upstream)${NC}"
    else
        echo -e "${CYAN}No 'upstream' remote found.${NC}"
        read -e -p "Enter the ORIGINAL repo URL you forked from: " UP_URL
        UP_URL=$(clean_remote_url "$UP_URL")
        if [[ -n "$UP_URL" ]]; then
            run_git remote add upstream "$UP_URL"
            echo -e "${GREEN}[✔] 'upstream' remote added.${NC}"
        fi
    fi
    pause
}

oss_sync_fork() {
    show_header
    echo -e "${YELLOW}${BOLD}🔄 Sync Fork with Upstream${NC}\n"
    if ! git remote get-url upstream &>/dev/null; then
        echo -e "${RED}[!] No 'upstream' remote set. Use option [1] first.${NC}"
        pause
        return
    fi
    local BRANCH
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    run_git fetch upstream || { echo -e "${RED}[!] Could not reach 'upstream' remote. Check the URL/connection.${NC}"; pause; return; }
    run_git merge "upstream/${BRANCH}" || echo -e "${YELLOW}[!] Merge conflicts — resolve manually.${NC}"
    run_git push origin "$BRANCH" || echo -e "${YELLOW}[!] Push to your fork failed. Check your remote/connection.${NC}"
    echo -e "${GREEN}[✔] Fork synced with upstream.${NC}"
    pause
}

oss_create_pr() {
    show_header
    local label="Pull Request"
    if ! ensure_vcs_ready; then pause; return; fi
    [[ "$VCS_PROVIDER" == "gitlab" ]] && label="Merge Request"
    echo -e "${YELLOW}${BOLD}📬 Create ${label} (${VCS_PROVIDER^})${NC}\n"
    read -e -p "${label} Title: " PR_TITLE
    read -e -p "${label} Body (short description): " PR_BODY
    if [[ -z "$PR_TITLE" ]]; then
        echo -e "${RED}Title required.${NC}"
        pause
        return
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would create ${label}: ${PR_TITLE}${NC}"
        log_action "DRY-RUN (not executed): create ${label} \"$PR_TITLE\""
    else
        safe_run "Create ${label}" vcs_create_change_request "$PR_TITLE" "$PR_BODY"
        log_action "EXECUTED: create ${label} \"$PR_TITLE\" (${VCS_PROVIDER})"
    fi
    pause
}

oss_view_prs() {
    show_header
    if ! ensure_vcs_ready; then pause; return; fi
    local label="Pull Requests"
    [[ "$VCS_PROVIDER" == "gitlab" ]] && label="Merge Requests"
    echo -e "${YELLOW}${BOLD}📬 My Open ${label} (${VCS_PROVIDER^})${NC}\n"
    case "$VCS_PROVIDER" in
        github) safe_run "List ${label}" gh pr list --author "@me" ;;
        gitlab) safe_run "List ${label}" glab mr list --mine ;;
    esac
    pause
}

# ==============================================================================
# SAFE COMMAND RUNNER — captures output/exit code, shows failures as an
# in-tool warning (not a raw crash-to-terminal). Use for any gh/glab/docker
# call that might legitimately fail (permissions, missing scope, 404, etc.)
# ==============================================================================
safe_run() {
    local desc="$1"; shift
    local out
    out=$("$@" 2>&1)
    local code=$?
    if [[ $code -ne 0 ]]; then
        echo -e "${RED}${BOLD}⚠️  ${desc} — failed (exit code ${code})${NC}"
        echo -e "${YELLOW}$(echo "$out" | head -10)${NC}"
        echo -e "${CYAN}This is shown as a warning — git-wizard is still running normally.${NC}"
    else
        echo -e "${GREEN}[✔] ${desc} — done.${NC}"
        [[ -n "$out" ]] && echo "$out"
    fi
}


# One dispatcher per action — menus call vcs_* functions, never gh/glab directly.
# ==============================================================================
detect_vcs_provider() {
    local url
    url=$(git -C "$TARGET_REPO_DIR" remote get-url origin 2>/dev/null || echo "")
    if [[ "$url" == *"github.com"* ]]; then
        VCS_PROVIDER="github"
    elif [[ "$url" == *"gitlab.com"* || "$url" == *"gitlab"* ]]; then
        VCS_PROVIDER="gitlab"
    else
        VCS_PROVIDER=""
    fi
}

ensure_vcs_provider() {
    detect_vcs_provider
    if [[ -n "$VCS_PROVIDER" ]]; then
        return 0
    fi
    show_header
    echo -e "${YELLOW}${BOLD}🌐 COULD NOT AUTO-DETECT YOUR GIT HOST${NC}\n"
    echo -e "${CYAN}Your 'origin' remote doesn't clearly point to github.com or gitlab.com.${NC}\n"
    echo -e "  ${GREEN}[1]${NC} GitHub"
    echo -e "  ${GREEN}[2]${NC} GitLab"
    echo -e "  ${GREEN}[3]${NC} Cancel"
    read -e -p "Select choice [1-3]: " VCS_CHOICE
    case $VCS_CHOICE in
        1) VCS_PROVIDER="github" ;;
        2) VCS_PROVIDER="gitlab" ;;
        *) VCS_PROVIDER=""; return 1 ;;
    esac
    return 0
}

vcs_cli_installed() {
    case "$VCS_PROVIDER" in
        github) command -v gh &>/dev/null ;;
        gitlab) command -v glab &>/dev/null ;;
        *) return 1 ;;
    esac
}

vcs_binary_name() {
    case "$VCS_PROVIDER" in
        github) echo "gh" ;;
        gitlab) echo "glab" ;;
    esac
}

ensure_vcs_ready() {
    if ! ensure_vcs_provider; then return 1; fi
    local bin
    bin=$(vcs_binary_name)

    if ! vcs_cli_installed; then
        echo -e "${YELLOW}[i] This needs '${bin}' (${VCS_PROVIDER^} CLI) — it's what actually talks to ${VCS_PROVIDER^}'s API.${NC}"
        offer_install "$bin"
        if ! vcs_cli_installed; then
            return 1
        fi
        echo ""
    fi

    local auth_ok="false"
    case "$VCS_PROVIDER" in
        github) gh auth status &>/dev/null && auth_ok="true" ;;
        gitlab) glab auth status &>/dev/null && auth_ok="true" ;;
    esac

    if [[ "$auth_ok" != "true" ]]; then
        echo -e "${YELLOW}[i] Not logged in to ${VCS_PROVIDER^} yet.${NC}"
        read -e -p "Run '${bin} auth login' now? (y/N): " DOLOGIN
        if [[ "$DOLOGIN" =~ ^[Yy]$ ]]; then
            "$bin" auth login
        else
            echo -e "${YELLOW}[i] Skipped.${NC}"
            return 1
        fi
    fi

    case "$VCS_PROVIDER" in
        github) gh auth status &>/dev/null || { echo -e "${RED}[!] Still not authenticated.${NC}"; return 1; } ;;
        gitlab) glab auth status &>/dev/null || { echo -e "${RED}[!] Still not authenticated.${NC}"; return 1; } ;;
    esac
    return 0
}

# ==============================================================================
# ENSURE GH IS INSTALLED + AUTHENTICATED (self-healing, no manual detour)
# Returns 0 if gh is installed AND authenticated after this call.
# ==============================================================================
ensure_gh_ready() {
    if ! command -v gh &>/dev/null; then
        echo -e "${YELLOW}[i] 'gh' (GitHub CLI) is required — installing automatically...${NC}"
        offer_install "gh"          # tries repo package manager, then binary pull fallback
        hash -r 2>/dev/null || true
        if ! command -v gh &>/dev/null; then
            echo -e "${RED}[!] Could not install 'gh' automatically. Check your network/package manager.${NC}"
            return 1
        fi
        echo -e "${GREEN}[✔] 'gh' installed.${NC}"
        log_action "Auto-installed gh"
    fi

    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}[i] 'gh' is not logged in yet — launching 'gh auth login' now.${NC}"
        echo -e "${CYAN}    Follow the browser/device-code prompts that appear.${NC}\n"
        gh auth login
        if ! gh auth status &>/dev/null; then
            echo -e "${RED}[!] Still not authenticated after 'gh auth login'. Aborting this operation.${NC}"
            return 1
        fi
        log_action "Authenticated gh via ensure_gh_ready"
    fi

    return 0
}

# ==============================================================================
# ENSURE JQ IS INSTALLED (self-healing)
# ==============================================================================
ensure_jq_ready() {
    if command -v jq &>/dev/null; then
        return 0
    fi
    echo -e "${YELLOW}[i] 'jq' is required — installing automatically...${NC}"
    offer_install "jq"
    hash -r 2>/dev/null || true
    if ! command -v jq &>/dev/null; then
        echo -e "${RED}[!] Could not install 'jq' automatically. Check your network/package manager.${NC}"
        return 1
    fi
    echo -e "${GREEN}[✔] 'jq' installed.${NC}"
    log_action "Auto-installed jq"
    return 0
}

# --- Dispatchers: one call site per action, routed by provider ---
vcs_list_issues() {
    case "$VCS_PROVIDER" in
        github) gh issue list "$@" ;;
        gitlab) glab issue list "$@" ;;
    esac
}
vcs_create_issue() {
    case "$VCS_PROVIDER" in
        github) gh issue create "$@" ;;
        gitlab) glab issue create "$@" ;;
    esac
}
vcs_close_issue() {
    local num="$1"
    case "$VCS_PROVIDER" in
        github) gh issue close "$num" ;;
        gitlab) glab issue close "$num" ;;
    esac
}
vcs_view_issue() {
    local num="$1"
    case "$VCS_PROVIDER" in
        github) gh issue view "$num" ;;
        gitlab) glab issue view "$num" ;;
    esac
}
vcs_comment_issue() {
    local num="$1" body="$2"
    case "$VCS_PROVIDER" in
        github) gh issue comment "$num" --body "$body" ;;
        gitlab) glab issue note "$num" --message "$body" ;;
    esac
}
vcs_list_change_requests() {
    # PRs (GitHub) or MRs (GitLab)
    case "$VCS_PROVIDER" in
        github) gh pr list "$@" ;;
        gitlab) glab mr list "$@" ;;
    esac
}
vcs_checkout_change_request() {
    local num="$1"
    case "$VCS_PROVIDER" in
        github) gh pr checkout "$num" ;;
        gitlab) glab mr checkout "$num" ;;
    esac
}
vcs_diff_change_request() {
    local num="$1"
    case "$VCS_PROVIDER" in
        github) gh pr diff "$num" ;;
        gitlab) glab mr diff "$num" ;;
    esac
}
vcs_merge_change_request() {
    local num="$1"
    case "$VCS_PROVIDER" in
        github) gh pr merge "$num" ;;
        gitlab) glab mr merge "$num" ;;
    esac
}
vcs_create_change_request() {
    local title="$1" body="$2"
    case "$VCS_PROVIDER" in
        github) gh pr create --title "$title" --body "$body" ;;
        gitlab) glab mr create --title "$title" --description "$body" ;;
    esac
}
vcs_list_releases() {
    case "$VCS_PROVIDER" in
        github) gh release list "$@" ;;
        gitlab) glab release list "$@" ;;
    esac
}
vcs_create_release() {
    local tag="$1" title="$2"
    case "$VCS_PROVIDER" in
        github) gh release create "$tag" --title "$title" --generate-notes ;;
        gitlab) glab release create "$tag" --name "$title" ;;
    esac
}
vcs_view_latest_release() {
    case "$VCS_PROVIDER" in
        github) gh release view --json tagName,name,publishedAt 2>/dev/null || gh release view ;;
        gitlab) glab release view "$(glab release list --per-page 1 2>/dev/null | head -1 | awk '{print $1}')" ;;
    esac
}
vcs_delete_release() {
    local tag="$1"
    case "$VCS_PROVIDER" in
        github) gh release delete "$tag" ;;
        gitlab) glab release delete "$tag" ;;
    esac
}
vcs_list_runs() {
    # Actions (GitHub) or Pipelines (GitLab)
    case "$VCS_PROVIDER" in
        github) gh run list "$@" ;;
        gitlab) glab ci list "$@" ;;
    esac
}
vcs_watch_run() {
    case "$VCS_PROVIDER" in
        github) gh run watch ;;
        gitlab) glab ci status ;;
    esac
}
vcs_trigger_run() {
    case "$VCS_PROVIDER" in
        github) gh workflow run "$@" ;;
        gitlab) glab ci run ;;
    esac
}
vcs_view_run_logs() {
    local id="$1"
    case "$VCS_PROVIDER" in
        github) gh run view "$id" --log ;;
        gitlab) glab ci trace "$id" ;;
    esac
}
vcs_list_snippets() {
    case "$VCS_PROVIDER" in
        github) gh gist list "$@" ;;
        gitlab) glab snippet list "$@" ;;
    esac
}
vcs_create_snippet() {
    local file="$1"
    case "$VCS_PROVIDER" in
        github) gh gist create "$file" ;;
        gitlab) glab snippet create "$file" ;;
    esac
}
vcs_list_repos() {
    case "$VCS_PROVIDER" in
        github) gh repo list --limit 100 ;;
        gitlab) glab repo list --per-page 100 ;;
    esac
}
vcs_create_repo() {
    local name="$1" visibility="$2"
    case "$VCS_PROVIDER" in
        github) gh repo create "$name" "--${visibility}" ;;
        gitlab) glab repo create "$name" "--${visibility}" ;;
    esac
}
vcs_get_repo_url() {
    # Returns "ssh_url|https_url" for a given repo (owner/repo or namespace/project)
    local repo="$1"
    case "$VCS_PROVIDER" in
        github) gh api "repos/${repo}" --jq '(.ssh_url) + "|" + (.clone_url)' 2>/dev/null ;;
        gitlab) glab api "projects/$(url_encode "$repo")" --jq '(.ssh_url_to_repo) + "|" + (.http_url_to_repo)' 2>/dev/null ;;
    esac
}
vcs_my_username() {
    case "$VCS_PROVIDER" in
        github) gh api user --jq '.login' 2>/dev/null ;;
        gitlab) glab api user --jq '.username' 2>/dev/null ;;
    esac
}
vcs_add_collaborator() {
    # $1=repo (owner/repo)  $2=username  $3=permission level
    local repo="$1" username="$2" permission="$3"
    case "$VCS_PROVIDER" in
        github)
            # permission: pull, triage, push, maintain, admin
            gh api "repos/${repo}/collaborators/${username}" -X PUT -f "permission=${permission}"
            ;;
        gitlab)
            # access_level: 10=Guest 20=Reporter 30=Developer 40=Maintainer 50=Owner
            local uid
            uid=$(glab api "users?username=${username}" --jq '.[0].id' 2>/dev/null)
            if [[ -z "$uid" ]]; then
                echo -e "${RED}[!] Couldn't find a GitLab user named '${username}'.${NC}"
                return 1
            fi
            glab api "projects/$(url_encode "$repo")/members" -X POST -f "user_id=${uid}" -f "access_level=${permission}"
            ;;
    esac
}
vcs_rename_repo() {
    local newname="$1"
    case "$VCS_PROVIDER" in
        github) gh repo rename "$newname" ;;
        gitlab) echo -e "${YELLOW}[i] glab has no direct rename subcommand — rename via GitLab web UI (Settings > General).${NC}" ;;
    esac
}
vcs_delete_repo() {
    local name="$1"
    case "$VCS_PROVIDER" in
        github) gh repo delete "$name" --yes ;;
        gitlab) glab repo delete "$name" --yes ;;
    esac
}
vcs_api() {
    case "$VCS_PROVIDER" in
        github) gh api "$@" ;;
        gitlab) glab api "$@" ;;
    esac
}
vcs_version() {
    case "$VCS_PROVIDER" in
        github) gh --version 2>/dev/null | head -1 ;;
        gitlab) glab --version 2>/dev/null | head -1 ;;
    esac
}

# ==============================================================================
# GIT CLI HUB (Module 5 top-level) — list repos, browse full file/folder
# structure (not just README), manage auth. Provider-routed (GitHub via 'gh',
# GitLab via 'glab') through the ensure_vcs_ready dispatcher defined above.
# ==============================================================================

url_encode() {
    local string="$1" strlen encoded c i hex
    strlen=${#string}
    for (( i=0; i<strlen; i++ )); do
        c="${string:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            *) printf -v hex '%%%02X' "'$c"
               encoded+="$hex" ;;
        esac
    done
    echo "$encoded"
}

vcs_repo_list_full() {
    # One "owner/repo" (or "namespace/project") per line
    case "$VCS_PROVIDER" in
        github) gh repo list --limit 200 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null ;;
        gitlab) glab api "projects?membership=true&per_page=100" --jq '.[].path_with_namespace' 2>/dev/null ;;
    esac
}

vcs_default_branch() {
    local repo="$1"
    case "$VCS_PROVIDER" in
        github) gh api "repos/${repo}" --jq '.default_branch' 2>/dev/null ;;
        gitlab) glab api "projects/$(url_encode "$repo")" --jq '.default_branch' 2>/dev/null ;;
    esac
}

vcs_list_dir() {
    # Emits "dir\tname" or "file\tname" lines for the given repo/path
    local repo="$1" path="$2"
    case "$VCS_PROVIDER" in
        github)
            local api_path="repos/${repo}/contents"
            [[ -n "$path" ]] && api_path="${api_path}/${path}"
            gh api "$api_path" --jq '.[] | .type + "\t" + .name' 2>/dev/null
            ;;
        gitlab)
            local qpath=""
            [[ -n "$path" ]] && qpath="&path=$(url_encode "$path")"
            glab api "projects/$(url_encode "$repo")/repository/tree?per_page=100${qpath}" --jq '.[] | .type + "\t" + .name' 2>/dev/null \
                | sed 's/^tree\t/dir\t/; s/^blob\t/file\t/'
            ;;
    esac
}

vcs_file_raw() {
    local repo="$1" path="$2" branch="$3"
    case "$VCS_PROVIDER" in
        github)
            gh api "repos/${repo}/contents/${path}" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null
            ;;
        gitlab)
            glab api "projects/$(url_encode "$repo")/repository/files/$(url_encode "$path")/raw?ref=${branch}" 2>/dev/null
            ;;
    esac
}


print_repo_table() {
    printf "${CYAN}${BOLD}%-45s %-10s %-20s${NC}\n" "REPOSITORY" "VISIBILITY" "LAST UPDATED"
    printf "${CYAN}%s${NC}\n" "--------------------------------------------------------------------------"
    local name vis upd
    while IFS=$'\t' read -r name vis upd; do
        [[ -z "$name" ]] && continue
        local vcolor="$GREEN"
        [[ "$vis" == "private" ]] && vcolor="$YELLOW"
        printf "${BOLD}%-45s${NC} ${vcolor}%-10s${NC} ${CYAN}%-20s${NC}\n" "$name" "$vis" "$upd"
    done
}

vcs_repo_list_rich() {
    case "$VCS_PROVIDER" in
        github)
            gh repo list --limit 1000 --json nameWithOwner,visibility,updatedAt \
                --jq '.[] | [.nameWithOwner, (.visibility|ascii_downcase), .updatedAt] | @tsv' 2>/dev/null
            ;;
        gitlab)
            local page=1 out
            while :; do
                out=$(glab api "projects?membership=true&per_page=100&page=${page}" \
                    --jq '.[] | [.path_with_namespace, .visibility, .last_activity_at] | @tsv' 2>/dev/null)
                [[ -z "$out" ]] && break
                echo "$out"
                (( $(echo "$out" | wc -l) < 100 )) && break
                ((page++))
            done
            ;;
    esac
}


# Reads TSV lines from stdin: name\tvisibility\tstars\tupdated\tisfork
render_repo_table() {
    local name vis stars updated isfork
    local max_name=4
    local rows=()
    while IFS=$'\t' read -r name vis stars updated isfork; do
        [[ -z "$name" ]] && continue
        rows+=("${name}"$'\t'"${vis}"$'\t'"${stars}"$'\t'"${updated}"$'\t'"${isfork}")
        (( ${#name} > max_name )) && max_name=${#name}
    done
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo -e "${YELLOW}[i] No repositories returned.${NC}"
        return
    fi
    echo -e "${GREEN}${BOLD}Total repositories found: ${#rows[@]}${NC}\n"
    printf "  ${BOLD}%-${max_name}s  %-10s  %-8s  %-20s${NC}\n" "NAME" "VISIBILITY" "STARS" "LAST UPDATED"
    printf "  %s\n" "$(printf -- '-%.0s' $(seq 1 $((max_name + 46))))"
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r name vis stars updated isfork <<< "$row"
        local vis_color="$GREEN"
        [[ "$vis" == "private" ]] && vis_color="$RED"
        local fork_tag=""
        [[ "$isfork" == "true" ]] && fork_tag="${CYAN} [fork]${NC}"
        local short_date="${updated%%T*}"
        printf "  ${CYAN}%-${max_name}s${NC}  ${vis_color}%-10s${NC}  ${YELLOW}%-8s${NC}  %-20s%s\n" \
            "$name" "$vis" "★${stars:-0}" "$short_date" "$fork_tag"
    done
}

vcs_list_my_repos() {
    show_header
    echo -e "${YELLOW}${BOLD}📂 YOUR ${VCS_PROVIDER^^} REPOSITORIES${NC}\n"
    if ! ensure_vcs_ready; then pause; return; fi

    echo -e "${CYAN}--> Fetching your repositories from ${VCS_PROVIDER^}...${NC}\n"
    case "$VCS_PROVIDER" in
        github)
            # No --source flag here on purpose — --source silently drops
            # forks. We include everything and tag forks in the table
            # instead of hiding them.
            gh repo list --limit 200 \
                --json name,visibility,updatedAt,isFork,stargazerCount \
                --jq '.[] | [.name, (.visibility | ascii_downcase), (.stargazerCount|tostring), .updatedAt, (.isFork|tostring)] | @tsv' 2>/dev/null \
                | render_repo_table
            log_action "Listed GitHub repos via gh CLI"
            ;;
        gitlab)
            glab api "projects?membership=true&per_page=100&order_by=last_activity_at" \
                --jq '.[] | [.path_with_namespace, .visibility, (.star_count|tostring), .last_activity_at, (.forked_from_project != null | tostring)] | @tsv' 2>/dev/null \
                | render_repo_table
            log_action "Listed GitLab projects via glab CLI"
            ;;
    esac
    pause
}


# Arrow-key selector over a dynamic list of "TYPE\tNAME" lines (used for repo browsing)
select_from_lines_interactive() {
    local prompt="$1"
    shift
    local -a lines=("$@")
    if [[ ${#lines[@]} -eq 0 ]]; then
        return 1
    fi

    local selected=0 key=""
    tput civis 2>/dev/null || true
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}$prompt${NC}\n"
        for i in "${!lines[@]}"; do
            local type_part="${lines[$i]%%$'\t'*}"
            local name_part="${lines[$i]#*$'\t'}"
            local icon="📄"
            [[ "$type_part" == "dir" ]] && icon="📁"
            [[ "$type_part" == "up" ]] && icon="⬆️"
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}${BOLD}  ➔  ${icon} ${name_part}${NC}"
            else
                echo -e "     ${icon} ${name_part}"
            fi
        done
        echo -e "\n${CYAN}[UP/DOWN navigate, ENTER open, Q back/quit]${NC}"
        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            if [[ $key == "[A" ]]; then
                ((selected--)) || true
                if [[ $selected -lt 0 ]]; then selected=$((${#lines[@]} - 1)); fi
            elif [[ $key == "[B" ]]; then
                ((selected++)) || true
                if [[ $selected -ge ${#lines[@]} ]]; then selected=0; fi
            fi
        elif [[ $key == "" ]]; then
            tput cnorm 2>/dev/null || true
            SELECTED_LINE="${lines[$selected]}"
            return 0
        elif [[ $key == "q" || $key == "Q" ]]; then
            tput cnorm 2>/dev/null || true
            return 2
        fi
    done
}

vcs_browse_repo_files() {
    show_header
    echo -e "${YELLOW}${BOLD}🗂️  BROWSE REPOSITORY FILES & FOLDERS (${VCS_PROVIDER^})${NC}\n"
    if ! ensure_vcs_ready; then pause; return; fi

    echo -e "${CYAN}--> Fetching your repositories...${NC}"
    local repo_lines=()
    while IFS= read -r r; do
        [[ -n "$r" ]] && repo_lines+=("repo"$'\t'"$r")
    done < <(vcs_repo_list_full)

    if [[ ${#repo_lines[@]} -eq 0 ]]; then
        echo -e "${RED}[!] No repositories found (or couldn't fetch the list).${NC}"
        pause
        return
    fi

    if ! select_from_lines_interactive "SELECT A REPOSITORY TO BROWSE" "${repo_lines[@]}"; then
        pause
        return
    fi
    local repo_full="${SELECTED_LINE#*$'\t'}"
    local branch
    branch=$(vcs_default_branch "$repo_full")

    local current_path=""
    while true; do
        local raw_entries
        raw_entries=$(vcs_list_dir "$repo_full" "$current_path")
        if [[ -z "$raw_entries" ]]; then
            echo -e "${RED}[!] Could not list contents at '${current_path:-/}' (empty, or an API error — check auth/permissions).${NC}"
            pause
            break
        fi

        local entry_lines=()
        [[ -n "$current_path" ]] && entry_lines+=("up"$'\t'".. (up one level)")
        while IFS= read -r line; do
            [[ -n "$line" ]] && entry_lines+=("$line")
        done <<< "$raw_entries"

        local selresult
        select_from_lines_interactive "${repo_full} : /${current_path}   [Q to change repo]" "${entry_lines[@]}"
        selresult=$?
        if [[ $selresult -eq 2 ]]; then
            break
        fi

        local sel_type="${SELECTED_LINE%%$'\t'*}"
        local sel_name="${SELECTED_LINE#*$'\t'}"

        case "$sel_type" in
            up)
                current_path="${current_path%/*}"
                [[ "$current_path" == "$SELECTED_LINE" ]] && current_path=""
                ;;
            dir)
                if [[ -n "$current_path" ]]; then
                    current_path="${current_path}/${sel_name}"
                else
                    current_path="$sel_name"
                fi
                ;;
            file)
                show_header
                echo -e "${YELLOW}${BOLD}📄 ${sel_name}${NC} ${CYAN}(${repo_full}:${current_path:+$current_path/}${sel_name})${NC}\n"
                local file_path="${current_path:+$current_path/}${sel_name}"
                if command -v bat &>/dev/null; then
                    vcs_file_raw "$repo_full" "$file_path" "$branch" | bat --paging=always --style=numbers -l "${sel_name##*.}"
                else
                    vcs_file_raw "$repo_full" "$file_path" "$branch" | GIT_PAGER=cat less -R 2>/dev/null || \
                    vcs_file_raw "$repo_full" "$file_path" "$branch"
                fi
                pause
                ;;
        esac
    done
}

vcs_cli_hub_menu() {
    if ! ensure_vcs_provider; then return; fi
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🐙 Git CLI Hub — ${VCS_PROVIDER^^}${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List My Repositories"
        echo -e "      ${CYAN}Every repo on your account, with visibility and last-updated info.${NC}"
        echo -e "  ${GREEN}[2]${NC} Browse Repository Files & Folders"
        echo -e "      ${CYAN}Full file/folder tree for any of your repos — not just the README.${NC}"
        echo -e "  ${GREEN}[3]${NC} Repo History Viewer"
        echo -e "      ${CYAN}Shows commit graph across all branches (uses 'delta' for prettier diffs if installed).${NC}"
        echo -e "  ${GREEN}[4]${NC} Check / Setup Authentication"
        echo -e "  ${GREEN}[5]${NC} Switch Provider (currently: ${VCS_PROVIDER^})"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-5]: " GHCHOICE
        case $GHCHOICE in
            1) vcs_list_my_repos ;;
            2) vcs_browse_repo_files ;;
            3) repo_history_viewer ;;
            4)
                show_header
                local bin
                bin=$(vcs_binary_name)
                if vcs_cli_installed; then
                    local auth_ok="false"
                    case "$VCS_PROVIDER" in
                        github) gh auth status &>/dev/null && auth_ok="true" ;;
                        gitlab) glab auth status &>/dev/null && auth_ok="true" ;;
                    esac
                    if [[ "$auth_ok" == "true" ]]; then
                        echo -e "${GREEN}[✔] ${bin} is installed and authenticated.${NC}"
                        "$bin" auth status
                    else
                        echo -e "${YELLOW}[i] ${bin} is installed but not logged in.${NC}"
                        read -e -p "Run '${bin} auth login' now? (y/N): " DL
                        [[ "$DL" =~ ^[Yy]$ ]] && "$bin" auth login
                    fi
                else
                    suggest_install "$bin"
                fi
                pause
                ;;
            5)
                echo -e "  [1] GitHub  [2] GitLab"
                read -e -p "Choice [1-2]: " SW
                case $SW in
                    1) VCS_PROVIDER="github" ;;
                    2) VCS_PROVIDER="gitlab" ;;
                esac
                ;;
            0) return ;;
        esac
    done
}

oss_contributor_mode() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🌍 OPEN-SOURCE CONTRIBUTOR MODE (Fork + PR, powered by gh CLI)${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Detect / Setup Fork (upstream remote)"
        echo -e "      ${CYAN}Links this local repo to the ORIGINAL project you forked from.${NC}"
        echo -e "  ${GREEN}[2]${NC} Sync Fork with Upstream"
        echo -e "      ${CYAN}Pulls the latest changes from the original repo into your fork.${NC}"
        echo -e "  ${GREEN}[3]${NC} Create PR from Current Branch"
        echo -e "      ${CYAN}Opens a Pull Request asking the original repo's owner to merge your branch.${NC}"
        echo -e "  ${GREEN}[4]${NC} View My Open PRs"
        echo -e "      ${CYAN}Lists Pull Requests you've submitted that are still awaiting review.${NC}"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-4]: " OCHOICE
        case $OCHOICE in
            1) oss_setup_fork ;;
            2) oss_sync_fork ;;
            3) oss_create_pr ;;
            4) oss_view_prs ;;
            0) break ;;
        esac
    done
}

# --- 5.4 Safe Update Sync ---
safe_update_sync() {
    show_header
    echo -e "${YELLOW}${BOLD}🛡️ SAFE UPDATE SYNC${NC}\n"
    local BRANCH
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    local dirty="false"
    if [[ -n "$(git status --porcelain)" ]]; then
        dirty="true"
    fi

    if [[ "$dirty" == "true" ]]; then
        local STASH_MSG="auto-sync-$(date '+%Y%m%d-%H%M%S')"
        echo -e "${CYAN}--> Uncommitted changes detected. Stashing as '${STASH_MSG}'...${NC}"
        run_git stash push -m "$STASH_MSG"
    fi

    echo -e "${CYAN}--> Pulling latest changes...${NC}"
    if ! run_git pull origin "$BRANCH" --rebase; then
        echo -e "${RED}[!] Pull failed or conflicts occurred. Resolve manually, then run: git stash pop${NC}"
        pause
        return
    fi

    if [[ "$dirty" == "true" && "$DRY_RUN" != "true" ]]; then
        echo -e "${CYAN}--> Restoring your local changes...${NC}"
        if ! git stash pop; then
            echo -e "${RED}[!] Conflict restoring your changes. They remain safe in 'git stash list'.${NC}"
        else
            echo -e "${GREEN}[✔] Your local work is safe and up to date with remote.${NC}"
        fi
    fi
    pause
}

# ==============================================================================
# DELTA DIFF SUITE — provider-agnostic, pure git + delta. Main Menu > option 6.
# ==============================================================================
delta_view() {
    # Pipes a diff through delta if available, else falls back to a plain pager.
    if command -v delta &>/dev/null; then
        delta --paging=always
    else
        echo -e "${YELLOW}[i] 'delta' not installed — showing plain diff. Install via Settings > Cross-Distro Package Verification.${NC}"
        GIT_PAGER="less -R" cat
    fi
}

delta_view_uncommitted() {
    show_header
    echo -e "${YELLOW}${BOLD}📝 UNCOMMITTED CHANGES (working directory)${NC}\n"
    local d
    d=$(git -C "$TARGET_REPO_DIR" diff)
    if [[ -z "$d" ]]; then
        echo -e "${GREEN}[✔] No uncommitted changes.${NC}"
        pause
        return
    fi
    echo "$d" | delta_view
}

delta_view_staged() {
    show_header
    echo -e "${YELLOW}${BOLD}📦 STAGED CHANGES (diff --cached)${NC}\n"
    local d
    d=$(git -C "$TARGET_REPO_DIR" diff --cached)
    if [[ -z "$d" ]]; then
        echo -e "${GREEN}[✔] Nothing staged.${NC}"
        pause
        return
    fi
    echo "$d" | delta_view
}

delta_compare_branches() {
    show_header
    echo -e "${YELLOW}${BOLD}🔀 COMPARE TWO BRANCHES${NC}\n"
    echo -e "${CYAN}Select the FIRST branch...${NC}"
    sleep 1
    if ! select_branch_interactive "📌 SELECT FIRST BRANCH"; then pause; return; fi
    local B1="$SELECTED_BRANCH"
    if ! select_branch_interactive "📌 SELECT SECOND BRANCH (compared against ${B1})"; then pause; return; fi
    local B2="$SELECTED_BRANCH"
    show_header
    echo -e "${CYAN}--- Diff: ${B1}...${B2} ---${NC}\n"
    git -C "$TARGET_REPO_DIR" diff "${B1}...${B2}" | delta_view
}

delta_compare_commits() {
    show_header
    echo -e "${YELLOW}${BOLD}🔀 COMPARE TWO COMMITS${NC}\n"
    read -e -p "Enter FIRST commit hash: " C1
    read -e -p "Enter SECOND commit hash: " C2
    if [[ -z "$C1" || -z "$C2" ]]; then
        echo -e "${RED}Both commit hashes required.${NC}"
        pause
        return
    fi
    git -C "$TARGET_REPO_DIR" diff "$C1" "$C2" | delta_view
}

delta_view_single_commit() {
    show_header
    echo -e "${YELLOW}${BOLD}📖 VIEW A SINGLE COMMIT'S DIFF${NC}\n"
    GIT_PAGER=cat git -C "$TARGET_REPO_DIR" log --oneline -15
    echo ""
    read -e -p "Enter commit hash to view: " CH
    if [[ -z "$CH" ]]; then
        pause
        return
    fi
    git -C "$TARGET_REPO_DIR" show "$CH" | delta_view
}

delta_display_settings() {
    show_header
    echo -e "${YELLOW}${BOLD}⚙️ DELTA DISPLAY SETTINGS${NC}\n"
    if ! command -v delta &>/dev/null; then
        echo -e "${RED}[!] delta is not installed.${NC}"
        offer_install "delta"
        pause
        return
    fi
    echo -e "${CYAN}Current git-configured delta options:${NC}"
    git -C "$TARGET_REPO_DIR" config --get-regexp '^delta\.' 2>/dev/null || echo "  (none set — using delta defaults)"
    echo ""
    echo -e "  ${GREEN}[1]${NC} Toggle Side-by-Side View"
    echo -e "  ${GREEN}[2]${NC} Toggle Line Numbers"
    echo -e "  ${GREEN}[3]${NC} Set Syntax Theme"
    echo -e "  ${GREEN}[0]${NC} Back"
    read -e -p "Select choice [0-3]: " DCHOICE
    case $DCHOICE in
        1)
            local cur
            cur=$(git config --get delta.side-by-side 2>/dev/null || echo "false")
            if [[ "$cur" == "true" ]]; then
                git config --global delta.side-by-side false
            else
                git config --global delta.side-by-side true
            fi
            echo -e "${GREEN}[✔] Side-by-side toggled.${NC}"
            log_action "delta.side-by-side toggled"
            ;;
        2)
            local cur
            cur=$(git config --get delta.line-numbers 2>/dev/null || echo "false")
            if [[ "$cur" == "true" ]]; then
                git config --global delta.line-numbers false
            else
                git config --global delta.line-numbers true
            fi
            echo -e "${GREEN}[✔] Line numbers toggled.${NC}"
            log_action "delta.line-numbers toggled"
            ;;
        3)
            local theme_list=()
            if delta --list-syntax-themes &>/dev/null; then
                while IFS= read -r th; do
                    [[ -n "$th" && "$th" != *":"* ]] && theme_list+=("$th"$'\t'"$th")
                done < <(delta --list-syntax-themes 2>/dev/null)
            fi
            if [[ ${#theme_list[@]} -eq 0 ]]; then
                echo -e "${YELLOW}[i] Couldn't list themes from delta — falling back to manual entry.${NC}"
                read -e -p "Enter a delta/bat syntax theme name (e.g. 'Dracula', 'Monokai Extended'): " THEME
            else
                if select_from_lines_interactive "📌 SELECT SYNTAX THEME" "${theme_list[@]}"; then
                    THEME="${SELECTED_LINE%%$'\t'*}"
                else
                    THEME=""
                fi
            fi
            if [[ -n "$THEME" ]]; then
                git config --global delta.syntax-theme "$THEME"
                echo -e "${GREEN}[✔] Theme set to: ${THEME}${NC}"
                log_action "delta.syntax-theme set to ${THEME}"
            fi
            ;;
        0) return ;;
    esac
    pause
}

delta_diff_suite_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🎨 DELTA DIFF SUITE${NC}\n"
        echo -e "${CYAN}Provider-agnostic — works identically on GitHub, GitLab, or any git remote.${NC}\n"
        echo -e "  ${GREEN}[1]${NC} View Uncommitted Changes"
        echo -e "  ${GREEN}[2]${NC} View Staged Changes"
        echo -e "  ${GREEN}[3]${NC} Compare Two Branches"
        echo -e "  ${GREEN}[4]${NC} Compare Two Commits"
        echo -e "  ${GREEN}[5]${NC} View a Single Commit's Diff"
        echo -e "  ${GREEN}[6]${NC} Delta Display Settings"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-6]: " DDCHOICE
        case $DDCHOICE in
            1) delta_view_uncommitted ;;
            2) delta_view_staged ;;
            3) delta_compare_branches ;;
            4) delta_compare_commits ;;
            5) delta_view_single_commit ;;
            6) delta_display_settings ;;
            0) break ;;
        esac
    done
}

# ==============================================================================
# GH/GLAB COMMAND CENTER — Main Menu > option 6. Provider-routed via vcs_* dispatchers.
# ==============================================================================
cc_issues_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🐛 ISSUES (${VCS_PROVIDER^})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List Issues"
        echo -e "  ${GREEN}[2]${NC} View an Issue"
        echo -e "  ${GREEN}[3]${NC} Create Issue"
        echo -e "  ${GREEN}[4]${NC} Comment on Issue"
        echo -e "  ${GREEN}[5]${NC} Close Issue"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-5]: " ICHOICE
        case $ICHOICE in
            1) show_header; vcs_list_issues; pause ;;
            2) read -e -p "Issue number: " N; [[ -n "$N" ]] && { show_header; vcs_view_issue "$N"; }; pause ;;
            3)
                read -e -p "Title: " T
                read -e -p "Body: " B
                if [[ -n "$T" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo -e "${YELLOW}[DRY-RUN] Would create issue: ${T}${NC}"
                    else
                        vcs_create_issue --title "$T" --body "$B"
                        log_action "Created issue: ${T}"
                    fi
                fi
                pause
                ;;
            4)
                read -e -p "Issue number: " N
                read -e -p "Comment: " C
                if [[ -n "$N" && -n "$C" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo -e "${YELLOW}[DRY-RUN] Would comment on issue #${N}${NC}"
                    else
                        vcs_comment_issue "$N" "$C"
                        log_action "Commented on issue #${N}"
                    fi
                fi
                pause
                ;;
            5)
                read -e -p "Issue number to close: " N
                if [[ -n "$N" ]] && confirm_destructive "Close issue #${N}"; then
                    vcs_close_issue "$N"
                    log_action "Closed issue #${N}"
                fi
                pause
                ;;
            0) break ;;
        esac
    done
}

cc_change_requests_menu() {
    local label="Pull Requests"
    [[ "$VCS_PROVIDER" == "gitlab" ]] && label="Merge Requests"
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🔃 ${label^^} (${VCS_PROVIDER^})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List ${label}"
        echo -e "  ${GREEN}[2]${NC} Checkout a ${label%s} Locally (test someone else's changes)"
        echo -e "  ${GREEN}[3]${NC} View Diff"
        echo -e "  ${GREEN}[4]${NC} Merge"
        echo -e "  ${GREEN}[5]${NC} Create from Current Branch"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-5]: " PCHOICE
        case $PCHOICE in
            1) show_header; vcs_list_change_requests; pause ;;
            2) read -e -p "${label%s} number: " N; [[ -n "$N" ]] && vcs_checkout_change_request "$N"; pause ;;
            3) read -e -p "${label%s} number: " N; [[ -n "$N" ]] && { show_header; vcs_diff_change_request "$N" | delta_view; }; pause ;;
            4)
                read -e -p "${label%s} number to merge: " N
                if [[ -n "$N" ]] && confirm_destructive "Merge ${label%s} #${N}"; then
                    vcs_merge_change_request "$N"
                    log_action "Merged ${label%s} #${N}"
                fi
                pause
                ;;
            5)
                read -e -p "Title: " T
                read -e -p "Description: " B
                if [[ -n "$T" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo -e "${YELLOW}[DRY-RUN] Would create ${label%s}: ${T}${NC}"
                    else
                        vcs_create_change_request "$T" "$B"
                        log_action "Created ${label%s}: ${T}"
                    fi
                fi
                pause
                ;;
            0) break ;;
        esac
    done
}

cc_releases_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🏷️  RELEASES (${VCS_PROVIDER^})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List Releases"
        echo -e "  ${GREEN}[2]${NC} View Latest Release"
        echo -e "  ${GREEN}[3]${NC} Create Release"
        echo -e "  ${GREEN}[4]${NC} Delete Release"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-4]: " RCHOICE
        case $RCHOICE in
            1) show_header; vcs_list_releases; pause ;;
            2) show_header; vcs_view_latest_release; pause ;;
            3)
                read -e -p "Tag (e.g. v1.0.0): " TAG
                read -e -p "Title: " TITLE
                if [[ -n "$TAG" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo -e "${YELLOW}[DRY-RUN] Would create release ${TAG}${NC}"
                    else
                        vcs_create_release "$TAG" "${TITLE:-$TAG}"
                        log_action "Created release ${TAG}"
                    fi
                fi
                pause
                ;;
            4)
                read -e -p "Tag to delete: " TAG
                if [[ -n "$TAG" ]] && confirm_destructive "Delete release ${TAG}"; then
                    vcs_delete_release "$TAG"
                    log_action "Deleted release ${TAG}"
                fi
                pause
                ;;
            0) break ;;
        esac
    done
}

cc_runs_menu() {
    local label="Actions"
    [[ "$VCS_PROVIDER" == "gitlab" ]] && label="Pipelines"
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}⚙️  ${label^^} / CI (${VCS_PROVIDER^})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List Recent Runs"
        echo -e "  ${GREEN}[2]${NC} Watch a Live Run"
        echo -e "  ${GREEN}[3]${NC} Trigger a Run Manually"
        echo -e "  ${GREEN}[4]${NC} View Run Logs"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-4]: " RUCHOICE
        case $RUCHOICE in
            1) show_header; safe_run "List runs" vcs_list_runs; pause ;;
            2) show_header; safe_run "Watch live run" vcs_watch_run; pause ;;
            3) show_header; safe_run "Trigger run" vcs_trigger_run; pause ;;
            4) read -e -p "Run/Job ID: " N; [[ -n "$N" ]] && { show_header; safe_run "View run logs" vcs_view_run_logs "$N"; }; pause ;;
            0) break ;;
        esac
    done
}

cc_snippets_menu() {
    local label="Gists"
    [[ "$VCS_PROVIDER" == "gitlab" ]] && label="Snippets"
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}📋 ${label^^} (${VCS_PROVIDER^})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List ${label}"
        echo -e "  ${GREEN}[2]${NC} Create from a File"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-2]: " GCHOICE
        case $GCHOICE in
            1) show_header; vcs_list_snippets; pause ;;
            2)
                read -e -p "Path to file: " F
                if [[ -f "$F" ]]; then
                    vcs_create_snippet "$F"
                    log_action "Created ${label%s} from ${F}"
                else
                    echo -e "${RED}[!] File not found.${NC}"
                fi
                pause
                ;;
            0) break ;;
        esac
    done
}

cc_codespaces_menu() {
    show_header
    echo -e "${YELLOW}${BOLD}💻 CODESPACES${NC}\n"
    if [[ "$VCS_PROVIDER" != "github" ]]; then
        echo -e "${YELLOW}[i] Codespaces is a GitHub-only feature — no direct GitLab equivalent exists.${NC}"
        pause
        return
    fi
    echo -e "  ${GREEN}[1]${NC} List Codespaces"
    echo -e "  ${GREEN}[2]${NC} Create Codespace"
    echo -e "  ${GREEN}[3]${NC} Open (SSH into) a Codespace"
    echo -e "  ${GREEN}[4]${NC} Stop a Codespace"
    echo -e "  ${GREEN}[0]${NC} Back"
    read -e -p "Select choice [0-4]: " CSCHOICE
    case $CSCHOICE in
        1) safe_run "List codespaces" gh codespace list ;;
        2) safe_run "Create codespace" gh codespace create ;;
        3) read -e -p "Codespace name: " N; [[ -n "$N" ]] && safe_run "SSH into codespace" gh codespace ssh -c "$N" ;;
        4) read -e -p "Codespace name: " N; [[ -n "$N" ]] && safe_run "Stop codespace" gh codespace stop -c "$N" ;;
        0) return ;;
    esac
    pause
}

cc_repo_admin_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🛠️  REPO / PROJECT ADMIN (${VCS_PROVIDER^})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List My Repos"
        echo -e "  ${GREEN}[2]${NC} Create New Repo"
        echo -e "  ${GREEN}[3]${NC} Get Remote URL for a Repo"
        echo -e "  ${GREEN}[4]${NC} Add a Collaborator / Team Member"
        echo -e "  ${GREEN}[5]${NC} Rename Current Repo"
        echo -e "  ${RED}[6]${NC} Delete a Repo ${RED}(PERMANENT!)${NC}"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-6]: " ACHOICE
        case $ACHOICE in
            1) vcs_list_my_repos ;;
            2)
                read -e -p "New repo name: " N
                echo -e "  [1] Public  [2] Private"
                read -e -p "Visibility [1-2]: " V
                local vis="public"
                [[ "$V" == "2" ]] && vis="private"
                if [[ -n "$N" ]]; then
                    vcs_create_repo "$N" "$vis"
                    log_action "Created ${VCS_PROVIDER} repo: ${N} (${vis})"

                    # Fetch and show the remote URL immediately — this is what
                    # you actually need to push anything to the new repo.
                    local uname full_name urlpair ssh_url https_url
                    uname=$(vcs_my_username)
                    if [[ -n "$uname" ]]; then
                        full_name="${uname}/${N}"
                        echo -e "\n${CYAN}--> Fetching remote URL for ${full_name}...${NC}"
                        urlpair=$(vcs_get_repo_url "$full_name")
                        ssh_url="${urlpair%%|*}"
                        https_url="${urlpair##*|}"
                        if [[ -n "$ssh_url" ]]; then
                            echo -e "${GREEN}${BOLD}Repo created!${NC}"
                            echo -e "  SSH:   ${CYAN}${ssh_url}${NC}"
                            echo -e "  HTTPS: ${CYAN}${https_url}${NC}"
                            read -e -p "Set this as 'origin' for the current directory (${TARGET_REPO_DIR})? (y/N): " DOORIGIN
                            if [[ "$DOORIGIN" =~ ^[Yy]$ ]]; then
                                echo -e "  [1] Use SSH  [2] Use HTTPS"
                                read -e -p "  Choice [1-2]: " PROTO
                                local chosen_url="$ssh_url"
                                [[ "$PROTO" == "2" ]] && chosen_url="$https_url"
                                git remote remove origin 2>/dev/null || true
                                run_git remote add origin "$chosen_url"
                                echo -e "${GREEN}[✔] 'origin' set to ${chosen_url}${NC}"
                            fi
                        else
                            echo -e "${YELLOW}[i] Repo created, but couldn't auto-fetch its URL — check ${VCS_PROVIDER}'s website directly.${NC}"
                        fi
                    fi
                fi
                pause
                ;;
            3)
                read -e -p "Full repo name (owner/repo or namespace/project): " N
                if [[ -n "$N" ]]; then
                    show_header
                    local urlpair ssh_url https_url
                    urlpair=$(vcs_get_repo_url "$N")
                    ssh_url="${urlpair%%|*}"
                    https_url="${urlpair##*|}"
                    if [[ -n "$ssh_url" ]]; then
                        echo -e "${GREEN}${BOLD}${N}${NC}"
                        echo -e "  SSH:   ${CYAN}${ssh_url}${NC}"
                        echo -e "  HTTPS: ${CYAN}${https_url}${NC}"
                        read -e -p "Set this as 'origin' for the current directory? (y/N): " DOORIGIN
                        if [[ "$DOORIGIN" =~ ^[Yy]$ ]]; then
                            echo -e "  [1] Use SSH  [2] Use HTTPS"
                            read -e -p "  Choice [1-2]: " PROTO
                            local chosen_url="$ssh_url"
                            [[ "$PROTO" == "2" ]] && chosen_url="$https_url"
                            git remote remove origin 2>/dev/null || true
                            run_git remote add origin "$chosen_url"
                            echo -e "${GREEN}[✔] 'origin' set to ${chosen_url}${NC}"
                        fi
                    else
                        echo -e "${RED}[!] Couldn't fetch that repo's URL — check the name and your access.${NC}"
                    fi
                fi
                pause
                ;;
            4)
                read -e -p "Full repo name (owner/repo or namespace/project): " N
                read -e -p "Their username: " UN
                if [[ "$VCS_PROVIDER" == "github" ]]; then
                    echo -e "  [1] Read (pull)  [2] Write (push)  [3] Maintain  [4] Admin"
                    read -e -p "Permission level [1-4]: " PL
                    local perm="pull"
                    case $PL in 2) perm="push" ;; 3) perm="maintain" ;; 4) perm="admin" ;; esac
                else
                    echo -e "  [1] Reporter  [2] Developer  [3] Maintainer  [4] Owner"
                    read -e -p "Permission level [1-4]: " PL
                    local perm="20"
                    case $PL in 2) perm="30" ;; 3) perm="40" ;; 4) perm="50" ;; esac
                fi
                if [[ -n "$N" && -n "$UN" ]] && confirm_destructive "Grant '${UN}' access to '${N}'"; then
                    safe_run "Add collaborator ${UN}" vcs_add_collaborator "$N" "$UN" "$perm"
                    log_action "Added collaborator ${UN} to ${N} (${VCS_PROVIDER})"
                fi
                pause
                ;;
            5)
                read -e -p "New name for THIS repo: " N
                if [[ -n "$N" ]] && confirm_destructive "Rename this repo to '${N}'"; then
                    vcs_rename_repo "$N"
                    log_action "Renamed repo to ${N}"
                fi
                pause
                ;;
            6)
                read -e -p "Full name of repo to DELETE (owner/repo): " N
                if [[ -n "$N" ]] && confirm_destructive "PERMANENTLY DELETE '${N}' — this cannot be undone"; then
                    local del_out
                    del_out=$(vcs_delete_repo "$N" 2>&1)
                    local del_code=$?
                    if [[ $del_code -ne 0 ]]; then
                        echo -e "${RED}${BOLD}⚠️  Delete failed:${NC}"
                        echo -e "${YELLOW}${del_out}${NC}\n"
                        if echo "$del_out" | grep -qi "delete_repo\|scope\|403\|permission"; then
                            echo -e "${CYAN}This is almost always a missing OAuth scope — your login token was never granted delete permission (GitHub keeps this scope separate from everything else on purpose, as a safety measure).${NC}"
                            if [[ "$VCS_PROVIDER" == "github" ]]; then
                                echo -e "${CYAN}Fix: run this once, then retry:${NC} ${GREEN}gh auth refresh -h github.com -s delete_repo${NC}"
                                read -e -p "Run that now? (y/N): " DOREFRESH
                                if [[ "$DOREFRESH" =~ ^[Yy]$ ]]; then
                                    gh auth refresh -h github.com -s delete_repo
                                    echo -e "${CYAN}Re-run Delete once you've confirmed the browser auth step.${NC}"
                                fi
                            else
                                echo -e "${CYAN}Fix: run:${NC} ${GREEN}glab auth login --scopes api,delete_repo${NC} ${CYAN}(or add the 'api' scope to your GitLab token, which covers delete)${NC}"
                            fi
                        fi
                    else
                        echo -e "${GREEN}[✔] Deleted.${NC}"
                        log_action "DELETED repo: ${N}"
                    fi
                fi
                pause
                ;;
            0) break ;;
        esac
    done
}

cc_api_explorer() {
    show_header
    echo -e "${YELLOW}${BOLD}🔬 RAW API EXPLORER (${VCS_PROVIDER^}) — Advanced${NC}\n"
    echo -e "${CYAN}Enter a raw API path, e.g.: repos/OWNER/REPO/contents  (GitHub) or projects/ID/issues (GitLab)${NC}\n"
    read -e -p "API path: " PATH_IN
    if [[ -n "$PATH_IN" ]]; then
        vcs_api "$PATH_IN"
    fi
    pause
}

github_power_tools_menu() {
    if ! ensure_vcs_provider; then
        return
    fi
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}⚡ GIT HOSTING POWER TOOLS — ${VCS_PROVIDER^^}${NC}\n"
        if ! vcs_cli_installed; then
            echo -e "${RED}[!] $(vcs_binary_name) is not installed yet — most options below will prompt to install it.${NC}\n"
        fi
        local pr_label="Pull Requests"
        [[ "$VCS_PROVIDER" == "gitlab" ]] && pr_label="Merge Requests"
        local ci_label="Actions"
        [[ "$VCS_PROVIDER" == "gitlab" ]] && ci_label="Pipelines"
        local gist_label="Gists"
        [[ "$VCS_PROVIDER" == "gitlab" ]] && gist_label="Snippets"

        echo -e "  ${GREEN}[1]${NC} Switch Provider (currently: ${VCS_PROVIDER^})"
        echo -e "  ${GREEN}[2]${NC} Issues"
        echo -e "  ${GREEN}[3]${NC} ${pr_label}"
        echo -e "  ${GREEN}[4]${NC} Releases"
        echo -e "  ${GREEN}[5]${NC} ${ci_label} / CI"
        echo -e "  ${GREEN}[6]${NC} ${gist_label}"
        echo -e "  ${GREEN}[7]${NC} Codespaces ${CYAN}$([[ "$VCS_PROVIDER" != "github" ]] && echo '(GitHub only)')${NC}"
        echo -e "  ${GREEN}[8]${NC} Repo / Project Admin"
        echo -e "  ${GREEN}[9]${NC} Raw API Explorer (advanced)"
        echo -e "  ${GREEN}[10]${NC} Delta Diff Suite"
        echo -e "  ${GREEN}[0]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-10]: " GPCHOICE
        case $GPCHOICE in
            1)
                echo -e "  [1] GitHub  [2] GitLab"
                read -e -p "Choice [1-2]: " SW
                case $SW in
                    1) VCS_PROVIDER="github" ;;
                    2) VCS_PROVIDER="gitlab" ;;
                esac
                ;;
            2) ensure_vcs_ready && cc_issues_menu ;;
            3) ensure_vcs_ready && cc_change_requests_menu ;;
            4) ensure_vcs_ready && cc_releases_menu ;;
            5) ensure_vcs_ready && cc_runs_menu ;;
            6) ensure_vcs_ready && cc_snippets_menu ;;
            7) ensure_vcs_ready && cc_codespaces_menu ;;
            8) ensure_vcs_ready && cc_repo_admin_menu ;;
            9) ensure_vcs_ready && cc_api_explorer ;;
            10) delta_diff_suite_menu ;;
            0) break ;;
        esac
    done
}


repo_history_viewer() {
    show_header
    echo -e "${YELLOW}${BOLD}📖 REPO HISTORY VIEWER${NC}\n"
    git fetch --quiet 2>/dev/null || true
    if command -v delta &>/dev/null; then
        git log --oneline --graph --all --decorate --color | delta --paging=always || \
            GIT_PAGER=cat git log --oneline --graph --all --decorate --color
    else
        GIT_PAGER="less -R" git log --oneline --graph --all --decorate --color
    fi
}

module_5_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}[+] Module 5: Team & Open-Source Collaboration${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Linear Workflow (Solo/Sequential)"
        echo -e "      ${CYAN}You're the only one working — even across multiple machines. Pulls before every push.${NC}"
        echo -e "  ${GREEN}[2]${NC} Team Mode (private repo, collaborators)"
        echo -e "      ${CYAN}Others have write access to YOUR repo. Everyone branches, you review & merge.${NC}"
        echo -e "  ${GREEN}[3]${NC} Admin Dashboard"
        echo -e "      ${CYAN}Review a teammate's pushed branch (diff), then merge or reject it — no need to enter Team Mode first.${NC}"
        if [[ "$WIZARD_MODE" == "advanced" ]]; then
            echo -e "  ${GREEN}[4]${NC} Open-Source Contributor Mode (fork + PR)"
            echo -e "      ${CYAN}You're contributing to someone ELSE'S repo (or accepting outside PRs on yours).${NC}"
        else
            echo -e "  ${CYAN}[4]${NC} Open-Source Contributor Mode ${YELLOW}(switch to Advanced Mode to unlock)${NC}"
            echo -e "      ${CYAN}Fork/upstream/PR workflow for contributing to repos you don't own.${NC}"
        fi
        echo -e "  ${GREEN}[5]${NC} Git CLI Hub ${CYAN}(GitHub + GitLab${NC} — list repos, browse full file/folder tree, history, auth)"
        echo -e "      ${CYAN}Everything gh/glab-powered — including the file/folder browser and commit history, not just README.${NC}"
        echo -e "  ${GREEN}[6]${NC} Safe Update Sync (protects local work while pulling)"
        echo -e "      ${CYAN}Stashes your uncommitted work, pulls latest, restores your work on top.${NC}"
        echo -e "  ${GREEN}[0]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-6]: " M5_CHOICE
        case $M5_CHOICE in
            1) linear_workflow ;;
            2) team_mode ;;
            3) team_mode_admin_dashboard ;;
            4)
                if [[ "$WIZARD_MODE" == "advanced" ]]; then
                    oss_contributor_mode
                else
                    echo -e "${YELLOW}[i] This feature is hidden in Beginner Mode. Switch modes from the Main Menu.${NC}"
                    sleep 2
                fi
                ;;
            5) vcs_cli_hub_menu ;;
            6) safe_update_sync ;;
            0) break ;;
        esac
    done
}

# git-absorb installs as a git SUBCOMMAND (/usr/lib/git-core/git-absorb on
# Debian/Kali), invoked as "git absorb" — NOT a standalone "git-absorb" binary
# on PATH. `command -v git-absorb` will never find it even when correctly
# installed; this checks the way git itself actually resolves subcommands.
git_absorb_available() {
    git absorb -h &>/dev/null
    [[ $? -ne 127 ]]
}

# ==============================================================================
# BONUS TOOLS — lazygit, git-absorb, ghq (provider-agnostic), act / gitlab-ci-local
# ==============================================================================
bonus_tools_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🎁 BONUS TOOLS${NC}\n"
        echo -e "  ${GREEN}[1]${NC} lazygit — full terminal UI for git (stage/branch/stash visually)"
        echo -e "  ${GREEN}[2]${NC} git-absorb — auto-squash fixups into the right earlier commit"
        echo -e "  ${GREEN}[3]${NC} ghq — organized local clone manager (works for GitHub AND GitLab repos)"
        echo -e "  ${GREEN}[4]${NC} Local CI Testing (act for GitHub Actions / gitlab-ci-local for GitLab CI)"
        echo -e "  ${GREEN}[0]${NC} Back"
        read -e -p "Select choice [0-4]: " BCHOICE
        case $BCHOICE in
            1)
                show_header
                if command -v lazygit &>/dev/null; then
                    echo -e "${CYAN}--> Launching lazygit...${NC}"
                    echo -e "${YELLOW}    (Inside lazygit: press 'q' to quit and return here — NOT Ctrl+C, that can interrupt mid-operation.)${NC}"
                    sleep 2
                    (cd "$TARGET_REPO_DIR" && lazygit)
                else
                    echo -e "${YELLOW}[i] 'lazygit' is not installed.${NC}"
                    offer_install "lazygit"
                    pause
                fi
                ;;
            2)
                show_header
                if ! git_absorb_available; then
                    echo -e "${YELLOW}[i] 'git-absorb' is not installed.${NC}"
                    offer_install "git-absorb"
                    hash -r 2>/dev/null || true
                    if ! git_absorb_available; then
                        echo -e "${RED}[!] Still not available as 'git absorb' after install attempt.${NC}"
                        echo -e "${CYAN}--> Running diagnostics...${NC}\n"

                        local dpkg_status dpkg_files core_path found_path
                        dpkg_status=$(dpkg -l git-absorb 2>/dev/null | tail -1)
                        dpkg_files=$(dpkg -L git-absorb 2>/dev/null)
                        core_path=$(git --exec-path 2>/dev/null)
                        found_path=""
                        for p in "${core_path}/git-absorb" /usr/lib/git-core/git-absorb /usr/bin/git-absorb /usr/local/bin/git-absorb "$HOME/.local/bin/git-absorb" "$HOME/.cargo/bin/git-absorb"; do
                            [[ -x "$p" ]] && found_path="$p" && break
                        done

                        echo -e "${CYAN}  dpkg status line:${NC} ${dpkg_status:-<no dpkg record found>}"
                        if [[ -n "$dpkg_files" ]]; then
                            echo -e "${CYAN}  dpkg -L git-absorb lists:${NC}"
                            echo "$dpkg_files" | sed 's/^/    /'
                        fi

                        if [[ -n "$found_path" ]]; then
                            echo -e "\n${GREEN}[✔] Found the binary at: ${found_path}${NC}"
                            echo -e "${CYAN}    NOTE: git-absorb installs as a git SUBCOMMAND, not a standalone command.${NC}"
                            echo -e "${CYAN}    Call it as '${GREEN}git absorb${CYAN}' (with a space) — NOT '${GREEN}git-absorb${CYAN}' as one word.${NC}"
                            echo -e "${CYAN}    Try: ${GREEN}git --exec-path${NC} ${CYAN}— if it doesn't match the path above, git's exec-path is misconfigured; otherwise this is just a stale check, retry this menu now.${NC}"
                        else
                            echo -e "\n${RED}[!] No git-absorb binary found anywhere on disk, despite apt reporting it installed.${NC}"
                            echo -e "${CYAN}    Try the reliable Rust-native install instead:${NC}"
                            if command -v cargo &>/dev/null; then
                                read -e -p "    Install via cargo now? (y/N): " DOCARGO
                                if [[ "$DOCARGO" =~ ^[Yy]$ ]]; then
                                    cargo install git-absorb
                                    hash -r 2>/dev/null || true
                                fi
                            else
                                echo -e "${GREEN}      sudo apt install cargo && cargo install git-absorb${NC}"
                            fi
                        fi
                        pause
                        continue
                    fi
                    echo -e "${GREEN}[✔] git-absorb is now available (as 'git absorb').${NC}"
                fi
                echo -e "${CYAN}--> Running git-absorb (dry run first)...${NC}"
                (cd "$TARGET_REPO_DIR" && git absorb --dry-run)
                read -e -p "Apply for real? (y/N): " DOABSORB
                if [[ "$DOABSORB" =~ ^[Yy]$ ]]; then
                    (cd "$TARGET_REPO_DIR" && git absorb --and-rebase)
                    log_action "Ran git-absorb --and-rebase"
                fi
                pause
                ;;
            3)
                if command -v ghq &>/dev/null; then
                    while true; do
                        show_header
                        echo -e "${YELLOW}${BOLD}📁 GHQ — MANAGED CLONES${NC}\n"
                        local ghq_lines=()
                        while IFS= read -r r; do
                            [[ -n "$r" ]] && ghq_lines+=("repo"$'\t'"$r")
                        done < <(ghq list)

                        echo -e "  ${GREEN}[1]${NC} Clone a New Repo via ghq"
                        echo -e "  ${GREEN}[2]${NC} Push Updates for a Cloned Repo"
                        echo -e "  ${RED}[3]${NC} Delete a Cloned Repo Locally ${RED}(local folder only, NOT the remote)${NC}"
                        echo -e "  ${GREEN}[0]${NC} Back"
                        read -e -p "Choice [0-3]: " GQ
                        case $GQ in
                            1)
                                read -e -p "Repo URL: " GURL
                                [[ -n "$GURL" ]] && ghq get "$GURL"
                                pause
                                ;;
                            2)
                                if [[ ${#ghq_lines[@]} -eq 0 ]]; then
                                    echo -e "${YELLOW}[i] No ghq-managed repos yet.${NC}"
                                    pause
                                    continue
                                fi
                                if select_from_lines_interactive "SELECT A REPO TO PUSH" "${ghq_lines[@]}"; then
                                    local ghq_root repo_path
                                    ghq_root=$(ghq root)
                                    repo_path="${ghq_root}/${SELECTED_LINE#*$'\t'}"
                                    if [[ -d "$repo_path" ]]; then
                                        show_header
                                        echo -e "${CYAN}--> ${repo_path}${NC}\n"
                                        (cd "$repo_path" && git status --porcelain)

                                        # git rev-parse --abbrev-ref HEAD returns the literal
                                        # string "HEAD" on a repo with zero commits (unborn
                                        # branch) — that's what caused "src refspec HEAD does
                                        # not match any". symbolic-ref reads the INTENDED
                                        # branch name regardless of whether it has commits yet.
                                        local br has_commits
                                        br=$(cd "$repo_path" && git symbolic-ref --short HEAD 2>/dev/null)
                                        has_commits="true"
                                        (cd "$repo_path" && git rev-parse HEAD &>/dev/null) || has_commits="false"

                                        if [[ -z "$br" ]]; then
                                            echo -e "${RED}[!] Couldn't determine a branch name (detached HEAD?). Skipping push.${NC}"
                                        elif [[ "$has_commits" == "false" ]]; then
                                            echo -e "${YELLOW}[i] This repo has no commits yet — nothing to push.${NC}"
                                            if [[ -n "$(cd "$repo_path" && git status --porcelain)" ]]; then
                                                read -e -p "Stage and make an initial commit now? (y/N): " DOINIT
                                                if [[ "$DOINIT" =~ ^[Yy]$ ]]; then
                                                    (cd "$repo_path" && git add . && read -e -p "Commit message: " CM && git commit -m "$CM")
                                                    safe_run "Push ${br}" bash -c "cd '$repo_path' && git push -u origin '$br'"
                                                fi
                                            else
                                                echo -e "${CYAN}    Add some files first, then come back to push.${NC}"
                                            fi
                                        else
                                            if [[ -n "$(cd "$repo_path" && git status --porcelain)" ]]; then
                                                (cd "$repo_path" && git add . && read -e -p "Commit message: " CM && git commit -m "$CM")
                                            fi
                                            safe_run "Push ${br}" bash -c "cd '$repo_path' && git push origin '$br'"
                                        fi
                                    fi
                                fi
                                pause
                                ;;
                            3)
                                if [[ ${#ghq_lines[@]} -eq 0 ]]; then
                                    echo -e "${YELLOW}[i] No ghq-managed repos yet.${NC}"
                                    pause
                                    continue
                                fi
                                if select_from_lines_interactive "SELECT A REPO TO DELETE LOCALLY" "${ghq_lines[@]}"; then
                                    local ghq_root repo_path
                                    ghq_root=$(ghq root)
                                    repo_path="${ghq_root}/${SELECTED_LINE#*$'\t'}"
                                    if confirm_destructive "Delete local clone at ${repo_path} (remote on GitHub/GitLab is NOT touched)"; then
                                        rm -rf "$repo_path"
                                        echo -e "${GREEN}[✔] Local clone removed.${NC}"
                                        log_action "Removed ghq clone: ${repo_path}"
                                    fi
                                fi
                                pause
                                ;;
                            0) break ;;
                        esac
                    done
                else
                    show_header
                    echo -e "${YELLOW}[i] 'ghq' is not installed.${NC}"
                    offer_install "ghq"
                    hash -r 2>/dev/null || true
                    if command -v ghq &>/dev/null; then
                        echo -e "${GREEN}[✔] ghq is now available — reopen this menu to use it.${NC}"
                    fi
                fi
                pause
                ;;
            4)
                show_header
                echo -e "${YELLOW}${BOLD}🧪 LOCAL CI TESTING${NC}\n"
                echo -e "${CYAN}Runs your CI pipeline locally in Docker BEFORE you push — needs Docker installed & running.${NC}\n"
                if command -v docker &>/dev/null; then
                    if docker info &>/dev/null; then
                        echo -e "${GREEN}[✔] Docker is installed and the daemon is running.${NC}\n"
                    else
                        echo -e "${RED}[!] Docker is installed but the daemon isn't running (or you lack permission).${NC}"
                        echo -e "${CYAN}    Try: sudo systemctl start docker   (or restart Docker Desktop if that's what you use)${NC}\n"
                    fi
                else
                    echo -e "${RED}[!] Docker is not installed. Local CI testing needs it — install Docker first.${NC}\n"
                fi
                if [[ -f "${TARGET_REPO_DIR}/.github/workflows" || -d "${TARGET_REPO_DIR}/.github/workflows" ]]; then
                    echo -e "${GREEN}[✔] Detected .github/workflows — this repo uses GitHub Actions.${NC}"
                    if command -v act &>/dev/null; then
                        echo -e "${CYAN}--> Running 'act'...${NC}"
                        (cd "$TARGET_REPO_DIR" && act)
                    else
                        echo -e "${YELLOW}[i] 'act' is not installed.${NC}"
                        offer_install "act"
                    fi
                elif [[ -f "${TARGET_REPO_DIR}/.gitlab-ci.yml" ]]; then
                    echo -e "${GREEN}[✔] Detected .gitlab-ci.yml — this repo uses GitLab CI.${NC}"
                    if command -v gitlab-ci-local &>/dev/null; then
                        echo -e "${CYAN}--> Running 'gitlab-ci-local'...${NC}"
                        (cd "$TARGET_REPO_DIR" && gitlab-ci-local)
                    else
                        echo -e "${YELLOW}[i] 'gitlab-ci-local' is not installed (npm package).${NC}"
                        echo -e "    Install with: ${GREEN}npm install -g gitlab-ci-local${NC}"
                        read -e -p "  Install now? (y/N): " DOGCL
                        if [[ "$DOGCL" =~ ^[Yy]$ ]] && command -v npm &>/dev/null; then
                            npm install -g gitlab-ci-local
                        elif [[ "$DOGCL" =~ ^[Yy]$ ]]; then
                            echo -e "${RED}[!] npm not found — install Node.js/npm first.${NC}"
                        fi
                    fi
                else
                    echo -e "${YELLOW}[i] No .github/workflows or .gitlab-ci.yml found in this repo.${NC}"
                fi
                pause
                ;;
            0) break ;;
        esac
    done
}

check_tool_stack_versions() {
    show_header
    echo -e "${YELLOW}${BOLD}🔎 TOOL STACK VERSIONS${NC}\n"
    local tools=("git" "gh" "glab" "delta" "chafa" "lazygit" "git-absorb" "ghq" "act" "pre-commit")
    for t in "${tools[@]}"; do
        if [[ "$t" == "git-absorb" ]]; then
            if git_absorb_available; then
                local v
                v=$(git absorb --version 2>/dev/null | head -1)
                echo -e "  ${GREEN}[✔]${NC} ${BOLD}${t}${NC}: ${v:-installed} ${CYAN}(called as 'git absorb')${NC}"
            else
                echo -e "  ${RED}[✘]${NC} ${BOLD}${t}${NC}: not installed"
            fi
        elif command -v "$t" &>/dev/null; then
            local v
            v=$("$t" --version 2>/dev/null | head -1)
            echo -e "  ${GREEN}[✔]${NC} ${BOLD}${t}${NC}: ${v}"
        else
            echo -e "  ${RED}[✘]${NC} ${BOLD}${t}${NC}: not installed"
        fi
    done
    echo -e "\n${CYAN}[i] Want to check these against the latest releases? Use 'Check for Updates' from Settings.${NC}"
    pause
}

# --- Maps a tool name to its GitHub repo + local version-extraction command,
#     for binary-only update checks/installs (never via apt/dnf/pacman) ---
_tool_update_repo() {
    case "$1" in
        gh) echo "cli/cli" ;;
        delta) echo "dandavison/delta" ;;
        glab) echo "" ;;  # glab uses its own GitLab API lookup, see _tool_latest_tag
        git-absorb) echo "tummychow/git-absorb" ;;
        ghq) echo "x-motemen/ghq" ;;
        *) echo "" ;;
    esac
}

_tool_latest_tag() {
    # glab's canonical releases live on GitLab, not the stale GitHub mirror —
    # everything else is fetched from GitHub's API as usual.
    local t="$1"
    if [[ "$t" == "glab" ]]; then
        curl -fsSL --max-time 8 "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases?per_page=1&order_by=released_at&sort=desc" 2>/dev/null \
            | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"v?([^"]+)".*/\1/'
    else
        local repo
        repo=$(_tool_update_repo "$t")
        [[ -z "$repo" ]] && return
        curl -fsSL --max-time 8 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
            | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"v?([^"]+)".*/\1/'
    fi
}

_tool_installed_version() {
    local t="$1" raw
    raw=$("$t" --version 2>/dev/null | head -1)
    echo "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

check_tool_stack_updates() {
    show_header
    echo -e "${YELLOW}${BOLD}🔄 CHECK FOR TOOL UPDATES${NC}\n"
    echo -e "${CYAN}Checking installed binaries against their latest releases (GitHub or GitLab API, per tool)...${NC}\n"

    local checkable=("gh" "delta" "glab" "git-absorb" "ghq")
    local -a outdated=()
    local -a uptodate=()
    local -a notinstalled=()

    for t in "${checkable[@]}"; do
        if [[ "$t" == "git-absorb" ]]; then
            if ! git_absorb_available; then
                notinstalled+=("$t")
                continue
            fi
        elif ! command -v "$t" &>/dev/null; then
            notinstalled+=("$t")
            continue
        fi
        local installed_v latest_v
        if [[ "$t" == "git-absorb" ]]; then
            installed_v=$(git absorb --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        else
            installed_v=$(_tool_installed_version "$t")
        fi
        latest_v=$(_tool_latest_tag "$t")

        if [[ -z "$latest_v" ]]; then
            echo -e "  ${YELLOW}[i] ${t}: could not reach the release API to check (offline/rate-limited)${NC}"
            continue
        fi

        if [[ "$installed_v" == "$latest_v" ]]; then
            echo -e "  ${GREEN}[✔] ${t}: up to date (${installed_v})${NC}"
            uptodate+=("$t")
        else
            echo -e "  ${YELLOW}[⬆] ${t}: ${installed_v:-unknown} -> ${latest_v} available${NC}"
            outdated+=("$t")
        fi
    done

    if [[ ${#notinstalled[@]} -gt 0 ]]; then
        echo -e "\n${CYAN}Not installed (skipped): ${notinstalled[*]}${NC}"
    fi

    if [[ ${#outdated[@]} -eq 0 ]]; then
        echo -e "\n${GREEN}[✔] Everything checkable is up to date.${NC}"
        pause
        return
    fi

    echo ""
    local lines=("all"$'\t'"Update ALL outdated tools (${outdated[*]})")
    for t in "${outdated[@]}"; do
        lines+=("$t"$'\t'"Update just: ${t}")
    done
    lines+=("cancel"$'\t'"Cancel — don't update anything")

    if ! select_from_lines_interactive "📌 SELECT WHAT TO UPDATE (binary install only, not apt/dnf/pacman)" "${lines[@]}"; then
        return
    fi
    local pick="${SELECTED_LINE%%$'\t'*}"

    if [[ "$pick" == "cancel" ]]; then
        echo -e "${YELLOW}[i] Cancelled.${NC}"
        pause
        return
    fi

    show_header
    if [[ "$pick" == "all" ]]; then
        for t in "${outdated[@]}"; do
            echo -e "${CYAN}--> Updating ${t} via binary pull...${NC}"
            install_from_binary "$t"
            echo ""
        done
    else
        echo -e "${CYAN}--> Updating ${pick} via binary pull...${NC}"
        install_from_binary "$pick"
    fi
    hash -r 2>/dev/null || true
    echo -e "\n${GREEN}[✔] Update pass complete.${NC}"
    pause
}

tool_stack_manager_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🧰 TOOL STACK MANAGER${NC}\n"
        echo -e "${CYAN}Everything about the external tools git-wizard depends on or extends — lives here now.${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Cross-Distro Package Verification (gh, glab, delta, chafa)"
        echo -e "  ${GREEN}[2]${NC} Check Tool Stack Versions"
        echo -e "  ${GREEN}[3]${NC} Check for Tool Updates (binary-only)"
        echo -e "  ${GREEN}[4]${NC} Bonus Tools (lazygit, git-absorb, ghq, local CI runners)"
        echo -e "  ${GREEN}[0]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -e -p "Select choice [0-4]: " TSCHOICE
        case $TSCHOICE in
            1) check_optional_tools ;;
            2) check_tool_stack_versions ;;
            3) check_tool_stack_updates ;;
            4) bonus_tools_menu ;;
            0) break ;;
        esac
    done
}

if ! ensure_git_installed; then
    exit 1
fi

load_config
if [[ -z "$WIZARD_MODE" ]]; then
    mode_selection_wrapper
fi
ensure_global_cli_persisted
maybe_auto_check_updates

while true; do
    check_git_repo
    show_header
    echo -e "Main Capabilities Suite:\n"
    echo -e "  ${GREEN}[1]${NC} Identity & SSH Manager"
    echo -e "      ${CYAN}Your Git name/email, SSH keys, and the remote URL this repo points to.${NC}"
    echo -e "  ${GREEN}[2]${NC} Repository & Smart Push Engine"
    echo -e "      ${CYAN}Init, status, quick push, reset/undo, and conflict resolution for THIS repo.${NC}"
    echo -e "  ${GREEN}[3]${NC} Advanced Branch Manager"
    echo -e "      ${CYAN}Create, switch, list, and delete branches.${NC}"
    echo -e "  ${GREEN}[4]${NC} Conventional Commit Assistant"
    echo -e "      ${CYAN}Builds a properly formatted commit message (feat/fix/docs/etc).${NC}"
    echo -e "  ${YELLOW}${BOLD}[5] ⚡ Team & Open-Source Collaboration${NC}"
    echo -e "      ${CYAN}Solo, private-team, fork-based, and Git CLI Hub workflows.${NC}"
    echo -e "  ${YELLOW}${BOLD}[6] ⚡ Git Hosting Power Tools (GitHub/GitLab)${NC}"
    echo -e "      ${CYAN}Issues, PRs/MRs, Releases, Actions/Pipelines, Gists/Snippets, Repo Admin, Delta Diff Suite.${NC}"
    echo -e "  ${GREEN}[7]${NC} Universal Global CLI: currently ${BOLD}${GLOBAL_CLI_ENABLED^^}${NC}"
    echo -e "      ${CYAN}Lets you run 'git-wizard' from any folder, any terminal, permanently — until you disable it.${NC}"
    echo -e "  ${YELLOW}${BOLD}[8] 🧰 Tool Stack Manager${NC}"
    echo -e "      ${CYAN}Cross-distro checks, versions, updates, and bonus tools (lazygit, git-absorb, ghq, local CI).${NC}"
    echo -e "  ${GREEN}[9]${NC} Settings ${CYAN}(Mode / Dry-Run / Sync Panel / Updates / Action History)${NC}"
    echo -e "  ${GREEN}[0]${NC} Exit"
    echo -e "\n===================================================================="
    read -e -p "Enter choice [0-9]: " MAIN_CHOICE

    case $MAIN_CHOICE in
        1) manage_identity ;;
        2) manage_repo ;;
        3) manage_branches ;;
        4) commit_assistant ;;
        5) module_5_menu ;;
        6) github_power_tools_menu ;;
        7)
            if [[ "$GLOBAL_CLI_ENABLED" == "true" ]]; then
                echo -e "\n${CYAN}Global CLI is already enabled.${NC}"
                echo -e "  [1] Re-run setup (repair symlink/PATH)   [2] Disable it   [3] Cancel"
                read -e -p "Choice [1-3]: " GC
                case $GC in
                    1) enable_global_cli ;;
                    2) disable_global_cli ;;
                    *) ;;
                esac
            else
                enable_global_cli
            fi
            ;;
        8) tool_stack_manager_menu ;;
        9)
            while true; do
                show_header
                echo -e "${YELLOW}${BOLD}⚙️ SETTINGS${NC}\n"
                echo -e "  ${GREEN}[1]${NC} Switch Mode (current: ${WIZARD_MODE})"
                echo -e "  ${GREEN}[2]${NC} Toggle Dry-Run (current: ${DRY_RUN})"
                echo -e "  ${GREEN}[3]${NC} GitHub Sync Panel Settings (on/off, detail level)"
                echo -e "  ${GREEN}[4]${NC} View Tool Action History"
                echo -e "  ${GREEN}[5]${NC} Check for git-wizard Updates ${CYAN}(source: ${UPDATE_REPO:-not set})${NC}"
                echo -e "  ${GREEN}[6]${NC} Set Update Source Repo"
                echo -e "  ${GREEN}[7]${NC} Create git-wizard Checkpoint Now (manual backup point)"
                echo -e "  ${GREEN}[8]${NC} Update git-wizard Now"
                echo -e "  ${GREEN}[9]${NC} Rollback git-wizard to Previous Version"
                echo -e "  ${GREEN}[10]${NC} Enable Universal Global CLI Permanently (current: ${GLOBAL_CLI_ENABLED})"
                echo -e "  ${GREEN}[11]${NC} Disable Universal Global CLI Permanently"
                echo -e "  ${GREEN}[0]${NC} Back"
                read -e -p "Select choice [0-11]: " S_CHOICE
                case $S_CHOICE in
                    1) select_wizard_mode ;;
                    2) select_dry_run_state ;;
                    3) github_sync_menu ;;
                    4) show_action_history ;;
                    5) show_header; check_for_updates; pause ;;
                    6) configure_update_repo ;;
                    7) create_tool_checkpoint ;;
                    8) update_git_wizard ;;
                    9) rollback_git_wizard ;;
                    10) enable_global_cli ;;
                    11) disable_global_cli ;;
                    0) break ;;
                esac
            done
            ;;
        0) echo -e "\n${GREEN}Keep building amazing open-source software! Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
    esac
done

