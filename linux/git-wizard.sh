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

set -e

SCRIPT_VERSION="2.1.0"

# --- Paths ---
TARGET_REPO_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
        read -p "Type EXACTLY 'yes i understand' to proceed: " CONF
        [[ "$CONF" == "yes i understand" ]]
    else
        read -p "Proceed? (y/N): " CONF
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
        apt)    echo "sudo apt install -y ${pkg}" ;;
        dnf)    echo "sudo dnf install -y ${pkg}" ;;
        pacman) echo "sudo pacman -S --noconfirm ${pkg}" ;;
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
        read -p "      Install '${tool}' from the repository now? (y/N): " DOINSTALL
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
        gh|delta)
            read -p "      Try pulling a prebuilt binary from GitHub releases instead? (y/N): " DOBINARY
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

install_from_binary() {
    local tool="$1"
    local install_dir="${HOME}/.local/bin"
    mkdir -p "$install_dir"

    local os
    os=$(uname -s)
    if [[ "$os" != "Linux" ]]; then
        echo -e "  ${YELLOW}[i] Binary auto-install currently supports Linux only. On macOS, use: brew install ${tool}${NC}"
        return
    fi

    local tmpdir
    tmpdir=$(mktemp -d)

    case "$tool" in
        gh)
            local arch tag ver url
            arch=$(detect_binary_arch "gh_style")
            if [[ -z "$arch" ]]; then
                echo -e "  ${RED}[!] Unsupported CPU architecture for gh binary pull.${NC}"
                rm -rf "$tmpdir"; return
            fi
            tag=$(fetch_latest_release_tag "cli/cli" "v2.63.0")
            ver="${tag#v}"
            url="https://github.com/cli/cli/releases/download/${tag}/gh_${ver}_linux_${arch}.tar.gz"
            echo -e "  ${CYAN}--> Downloading: ${url}${NC}"
            if curl -fsSL --max-time 60 "$url" -o "${tmpdir}/gh.tar.gz"; then
                tar -xzf "${tmpdir}/gh.tar.gz" -C "$tmpdir"
                local binpath
                binpath=$(find "$tmpdir" -type f -name "gh" -path "*/bin/*" | head -1)
                if [[ -n "$binpath" ]]; then
                    cp "$binpath" "${install_dir}/gh"
                    chmod +x "${install_dir}/gh"
                    echo -e "  ${GREEN}[✔] gh installed to ${install_dir}/gh${NC}"
                    log_action "Installed gh via binary pull (${tag})"
                else
                    echo -e "  ${RED}[!] Downloaded archive but couldn't locate the 'gh' binary inside it.${NC}"
                fi
            else
                echo -e "  ${RED}[!] Download failed. Check your connection or try the repository install instead.${NC}"
            fi
            ;;
        delta)
            local target tag ver url
            target=$(detect_binary_arch "gnu_target")
            if [[ -z "$target" ]]; then
                echo -e "  ${RED}[!] Unsupported CPU architecture for delta binary pull.${NC}"
                rm -rf "$tmpdir"; return
            fi
            tag=$(fetch_latest_release_tag "dandavison/delta" "0.18.2")
            ver="${tag#v}"
            url="https://github.com/dandavison/delta/releases/download/${tag}/delta-${ver}-${target}.tar.gz"
            echo -e "  ${CYAN}--> Downloading: ${url}${NC}"
            if curl -fsSL --max-time 60 "$url" -o "${tmpdir}/delta.tar.gz"; then
                tar -xzf "${tmpdir}/delta.tar.gz" -C "$tmpdir"
                local binpath
                binpath=$(find "$tmpdir" -type f -name "delta" | head -1)
                if [[ -n "$binpath" ]]; then
                    cp "$binpath" "${install_dir}/delta"
                    chmod +x "${install_dir}/delta"
                    echo -e "  ${GREEN}[✔] delta installed to ${install_dir}/delta${NC}"
                    log_action "Installed delta via binary pull (${tag})"
                else
                    echo -e "  ${RED}[!] Downloaded archive but couldn't locate the 'delta' binary inside it.${NC}"
                fi
            else
                echo -e "  ${RED}[!] Download failed. Check your connection or try the repository install instead.${NC}"
            fi
            ;;
    esac

    rm -rf "$tmpdir"

    if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
        echo -e "  ${YELLOW}[i] Note: ${install_dir} is not on your PATH yet.${NC}"
        echo -e "      Add this to your ~/.bashrc or ~/.zshrc: ${GREEN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
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
    read -p "Repo (ENTER to leave unchanged): " NEWREPO
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
            read -p "  Install now via pipx? (y/N): " DOPIPX
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
            read -p "  Install now? (y/N): " DOPIP
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
        echo -e "${YELLOW}🔄 ${branch}: ⬆️ ${ahead} ahead  ⬇️ ${behind} behind  (${upstream})${NC}"
    fi
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
    read -p "Press [ENTER] to return to menu..."
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
    read -p "Select mode [1-2]: " MODE_CHOICE
    case $MODE_CHOICE in
        1) WIZARD_MODE="beginner"; DRY_RUN="true" ;;
        2) WIZARD_MODE="advanced"; DRY_RUN="false" ;;
        *) WIZARD_MODE="beginner"; DRY_RUN="true" ;;
    esac
    save_config
    log_action "Mode set to: ${WIZARD_MODE}"
}

toggle_mode() {
    if [[ "$WIZARD_MODE" == "beginner" ]]; then
        WIZARD_MODE="advanced"
    else
        WIZARD_MODE="beginner"
    fi
    save_config
    log_action "Mode switched to: ${WIZARD_MODE}"
    echo -e "${GREEN}[✔] Switched to ${WIZARD_MODE} mode.${NC}"
    sleep 1
}

toggle_dry_run() {
    if [[ "$DRY_RUN" == "true" ]]; then DRY_RUN="false"; else DRY_RUN="true"; fi
    save_config
    log_action "Dry-Run toggled to: ${DRY_RUN}"
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
    log_action "Auto-Sync indicator toggled to: ${AUTO_SYNC_CHECK}"
}

# --- Non-Git Repository Verification & Setup ---
check_git_repo() {
    if ! git -C "$TARGET_REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        show_header
        echo -e "${RED}[!] WARNING: '${TARGET_REPO_DIR}' is NOT a Git repository!${NC}\n"
        echo -e "${CYAN}Available Actions:${NC}"
        echo -e "  ${GREEN}[1]${NC} Initialize a new Git Repository here (${BOLD}git init${NC})"
        echo -e "  ${YELLOW}${BOLD}[2] ⚡ Enable Universal Global CLI${NC}"
        echo -e "  ${GREEN}[3]${NC} Exit"
        echo -e "\n===================================================================="
        read -p "Select choice [1-3]: " NON_REPO_CHOICE

        case $NON_REPO_CHOICE in
            1)
                run_git init
                run_git branch -M main 2>/dev/null || true
                echo -e "${GREEN}[✔] Initialized empty Git repository in ${TARGET_REPO_DIR}!${NC}"
                pause
                ;;
            2) enable_global_cli ;;
            3) exit 0 ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    fi
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
    echo -e "${GREEN}${BOLD}[✔] GIT-WIZARD IS NOW INSTALLED GLOBALLY!${NC}"
    log_action "Global CLI installed/linked"
    pause
}

# ==============================================================================
# MODULE 1: Identity & SSH Manager  (unchanged logic, routed through run_git where relevant)
# ==============================================================================
manage_identity() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}[+] Module 1: Identity, SSH & Remote URL Manager${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Check / Set Global Git User & Email"
        echo -e "  ${GREEN}[2]${NC} Generate New SSH Key (ED25519) & Show Public Key"
        echo -e "  ${GREEN}[3]${NC} Test SSH Connection to GitHub"
        echo -e "  ${GREEN}[4]${NC} Inspect & Manage Remote Repository URLs"
        echo -e "  ${GREEN}[5]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -p "Select choice [1-5]: " ID_CHOICE

        case $ID_CHOICE in
            1)
                echo -e "\n${CYAN}Current Configuration:${NC}"
                echo "  Name:  $(git config --global user.name || echo 'Not set')"
                echo "  Email: $(git config --global user.email || echo 'Not set')"
                read -p "Enter new global user.name (ENTER to skip): " NEW_NAME
                read -p "Enter new global user.email (ENTER to skip): " NEW_EMAIL
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
                if [[ -f ~/.ssh/id_ed25519 ]]; then
                    echo -e "\n${YELLOW}[!] SSH key already exists.${NC}"
                else
                    EMAIL=$(git config --global user.email || echo "user@github.com")
                    ssh-keygen -t ed25519 -C "$EMAIL" -f ~/.ssh/id_ed25519 -N ""
                    log_action "New SSH keypair generated"
                fi
                cat ~/.ssh/id_ed25519.pub
                pause
                ;;
            3) ssh -T git@github.com || true; pause ;;
            4)
                while true; do
                    show_header
                    echo -e "${YELLOW}${BOLD}📌 REMOTE REPOSITORY URL MANAGER${NC}\n"
                    GIT_PAGER=cat git remote -v 2>/dev/null || echo "No remotes set."
                    echo -e "\n  ${GREEN}[1]${NC} Change / Set New Remote URL"
                    echo -e "  ${GREEN}[2]${NC} Toggle Protocol (HTTPS/SSH)"
                    echo -e "  ${GREEN}[3]${NC} Back"
                    read -p "Select choice [1-3]: " REMOTE_CHOICE
                    case $REMOTE_CHOICE in
                        1)
                            read -p "Enter fresh GitHub Remote URL: " RAW_URL
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
                        3) break ;;
                    esac
                done
                ;;
            5) break ;;
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
        echo -e "  ${GREEN}[2]${NC} Quick Push (Add -> Commit -> Push)"
        echo -e "  ${GREEN}[3]${NC} Inspect Working Directory Status"
        echo -e "  ${GREEN}[4]${NC} Interactive Git Reset & Undo Utility"
        echo -e "  ${GREEN}[5]${NC} Smart Conflict Push Resolver"
        echo -e "  ${GREEN}[6]${NC} Generate Tailored .gitignore File"
        echo -e "  ${GREEN}[7]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -p "Select choice [1-7]: " REPO_CHOICE

        case $REPO_CHOICE in
            1)
                run_git init
                run_git branch -M main
                run_git add .
                if [[ -z "$(git status --porcelain)" ]]; then
                    echo -e "${YELLOW}[i] Nothing to commit.${NC}"
                else
                    read -p "Commit message [default: Initial commit]: " MSG
                    run_git commit -m "${MSG:-Initial commit}"
                fi
                read -p "Enter Remote URL (or ENTER to keep current): " RAW_URL
                REMOTE_URL=$(clean_remote_url "$RAW_URL")
                if [[ -n "$REMOTE_URL" ]]; then
                    git remote remove origin 2>/dev/null || true
                    run_git remote add origin "$REMOTE_URL"
                fi
                run_git push -u origin main || echo -e "${YELLOW}[!] Push rejected. Use Option [5] to resolve.${NC}"
                pause
                ;;
            2)
                run_git add .
                if [[ -z "$(git status --porcelain)" ]]; then
                    show_uptodate_celebration
                else
                    read -p "Enter commit message: " MSG
                    if [[ -z "$MSG" ]]; then
                        echo -e "${RED}Message required!${NC}"
                        pause
                        continue
                    fi
                    run_git commit -m "$MSG"
                    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
                    run_git push origin "$BRANCH" || echo -e "${YELLOW}[!] Push rejected. Use Option [5].${NC}"
                fi
                pause
                ;;
            3)
                show_header
                STATUS_OUT=$(git status --porcelain)
                [[ -z "$STATUS_OUT" ]] && show_uptodate_celebration || GIT_PAGER=cat git status
                pause
                ;;
            4)
                while true; do
                    show_header
                    echo -e "${YELLOW}${BOLD}📌 INTERACTIVE GIT RESET & UNDO UTILITY${NC}\n"
                    echo -e "  ${GREEN}[1]${NC} Unstage All Files"
                    echo -e "  ${GREEN}[2]${NC} Discard All Uncommitted Local Changes"
                    echo -e "  ${GREEN}[3]${NC} Soft Rollback Last Commit"
                    echo -e "  ${RED}[4]${NC} Hard Rollback Last Commit ${RED}(DESTROYS work!)${NC}"
                    echo -e "  ${RED}${BOLD}[5]${NC} ${RED}${BOLD}Force Sync with Origin${NC} ${RED}(Nuclear reset — matches GitHub exactly, DESTROYS local divergence!)${NC}"
                    echo -e "      ${CYAN}Use this when your local branch is badly tangled/diverged and you just want it to match origin/main exactly.${NC}"
                    echo -e "  ${GREEN}[6]${NC} Back"
                    read -p "Select choice [1-6]: " RESET_CHOICE
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
                        6) break ;;
                    esac
                done
                ;;
            5)
                show_header
                BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
                echo -e "  ${GREEN}[1]${NC} Safe Pull & Rebase"
                echo -e "  ${GREEN}[2]${NC} Safe Pull & Merge"
                echo -e "  ${RED}[3]${NC} Force Push ${RED}(Overwrites remote!)${NC}"
                echo -e "  ${GREEN}[4]${NC} Cancel"
                read -p "Select strategy [1-4]: " STRAT
                case $STRAT in
                    1)
                        if run_git pull origin "$BRANCH" --rebase; then
                            run_git push origin "$BRANCH" || echo -e "${YELLOW}[!] Pull succeeded but push failed.${NC}"
                        else
                            echo -e "${RED}[!] Pull/rebase failed — resolve conflicts manually.${NC}"
                        fi
                        ;;
                    2)
                        if run_git pull origin "$BRANCH" --rebase=false --allow-unrelated-histories; then
                            run_git push origin "$BRANCH" || echo -e "${YELLOW}[!] Pull succeeded but push failed.${NC}"
                        else
                            echo -e "${RED}[!] Pull/merge failed — resolve conflicts manually.${NC}"
                        fi
                        ;;
                    3)
                        if confirm_destructive "Force push — can overwrite remote history"; then
                            create_safety_backup "pre-force-push"
                            run_git push origin "$BRANCH" --force
                        fi
                        ;;
                    *) echo "Cancelled." ;;
                esac
                pause
                ;;
            6)
                echo -e "  [1] Python  [2] Node.js  [3] Go/Linux"
                read -p "Choice [1-3]: " GI_CHOICE
                case $GI_CHOICE in
                    1) printf '__pycache__/\n*.py[cod]\nvenv/\n.env\n.pytest_cache/\n' > .gitignore ;;
                    2) printf 'node_modules/\nbuild/\ndist/\n.env\n.env.local\nnpm-debug.log*\n' > .gitignore ;;
                    3) printf '*.exe\n*.o\n*.so\nbin/\n.env\n*.tar.gz\n' > .gitignore ;;
                esac
                echo -e "${GREEN}[✔] .gitignore created!${NC}"
                log_action ".gitignore generated"
                pause
                ;;
            7) break ;;
        esac
    done
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
        echo -e "  ${GREEN}[5]${NC} Back to Main Menu"
        read -p "Select choice [1-5]: " B_CHOICE
        case $B_CHOICE in
            1) show_header; GIT_PAGER=cat git branch -vv; echo; GIT_PAGER=cat git branch -r; pause ;;
            2)
                read -p "Enter new branch name: " NEW_B
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
            5) break ;;
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
    read -p "Select choice [1-5]: " C_TYPE
    local PREFIX=""
    case $C_TYPE in
        1) PREFIX="feat" ;; 2) PREFIX="fix" ;; 3) PREFIX="docs" ;;
        4) PREFIX="refactor" ;; 5) PREFIX="chore" ;;
        *) echo "Cancelled."; return ;;
    esac
    read -p "Enter short scope (optional): " SCOPE
    read -p "Enter clear commit description: " DESC
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
    read -p "Execute commit now? (y/N): " DO_COMMIT
    if [[ "$DO_COMMIT" =~ ^[Yy]$ ]]; then
        run_git add .
        run_git commit -m "$FINAL_MSG"
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
        read -p "Enter commit message: " MSG
        if [[ -n "$MSG" ]]; then
            run_git commit -m "$MSG"
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
    read -p "Select branch type [1-3]: " TTYPE
    local PREFIX=""
    case $TTYPE in 1) PREFIX="feature" ;; 2) PREFIX="fix" ;; 3) PREFIX="hotfix" ;; *) echo "Cancelled."; pause; return ;; esac
    read -p "Short name for your task (e.g. login-bug): " TNAME
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
        read -p "Enter commit message describing your ${PREFIX}: " CMSG
        if [[ -z "$CMSG" ]]; then
            CMSG="${PREFIX}: ${TNAME}"
        fi
        run_git commit -m "$CMSG"
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
    read -p "Choice [1-3]: " MCHOICE
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
        echo -e "  ${GREEN}[4]${NC} Back"
        read -p "Select choice [1-4]: " TCHOICE
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
            4) break ;;
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
        read -p "Enter the ORIGINAL repo URL you forked from: " UP_URL
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
    echo -e "${YELLOW}${BOLD}📬 Create Pull Request${NC}\n"
    if ! command -v gh &>/dev/null; then
        suggest_install "gh"
        pause
        return
    fi
    read -p "PR Title: " PR_TITLE
    read -p "PR Body (short description): " PR_BODY
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute:${NC} gh pr create --title \"$PR_TITLE\" --body \"$PR_BODY\""
        log_action "DRY-RUN (not executed): gh pr create --title \"$PR_TITLE\""
    else
        gh pr create --title "$PR_TITLE" --body "$PR_BODY"
        log_action "EXECUTED: gh pr create --title \"$PR_TITLE\""
    fi
    pause
}

oss_view_prs() {
    show_header
    if ! command -v gh &>/dev/null; then
        suggest_install "gh"
        pause
        return
    fi
    gh pr list --author "@me" || echo -e "${YELLOW}[i] No PRs found or not authenticated (run: gh auth login).${NC}"
    pause
}

# ==============================================================================
# PROVIDER ABSTRACTION LAYER (GitHub via 'gh' / GitLab via 'glab')
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
    read -p "Select choice [1-3]: " VCS_CHOICE
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
        read -p "Run '${bin} auth login' now? (y/N): " DOLOGIN
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
vcs_create_repo() {
    local name="$1" visibility="$2"
    case "$VCS_PROVIDER" in
        github) gh repo create "$name" "--${visibility}" ;;
        gitlab) glab repo create "$name" "--${visibility}" ;;
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
# GITHUB CLI HUB (Module 5 top-level) — list repos, browse full file/folder
# structure (not just README), view PRs, manage auth. All via 'gh api',
# no extra dependency beyond gh itself.
# ==============================================================================
ensure_gh_ready() {
    # Returns 0 if gh is installed AND authenticated, else guides the user and returns 1.
    if ! command -v gh &>/dev/null; then
        echo -e "${YELLOW}[i] This needs 'gh' (GitHub CLI) — it's what actually talks to your GitHub account.${NC}"
        offer_install "gh"
        if ! command -v gh &>/dev/null; then
            return 1
        fi
        echo ""
    fi

    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}[i] Not logged in yet. Your git config (name/email) is just commit metadata —${NC}"
        echo -e "${YELLOW}    it doesn't authenticate you to GitHub's API. A real login is needed.${NC}"
        read -p "Run 'gh auth login' now? (y/N): " DOLOGIN
        if [[ "$DOLOGIN" =~ ^[Yy]$ ]]; then
            gh auth login
        else
            echo -e "${YELLOW}[i] Skipped.${NC}"
            return 1
        fi
    fi

    if ! gh auth status &>/dev/null; then
        echo -e "${RED}[!] Still not authenticated. Try 'gh auth login' again.${NC}"
        return 1
    fi
    return 0
}

github_list_my_repos() {
    show_header
    echo -e "${YELLOW}${BOLD}📂 YOUR GITHUB REPOSITORIES${NC}\n"
    if ! ensure_gh_ready; then pause; return; fi

    echo -e "${CYAN}--> Fetching your repositories from GitHub...${NC}\n"
    local repo_count
    repo_count=$(gh repo list --limit 200 --json name 2>/dev/null | grep -c '"name"')
    echo -e "${GREEN}${BOLD}Total repositories found: ${repo_count}${NC}\n"
    gh repo list --limit 200 --source \
        --json name,visibility,updatedAt,isFork \
        --template '{{range .}}{{tablerow (printf "%s" .name) .visibility (timeago .updatedAt) (printf "%v" .isFork)}}{{end}}' \
        2>/dev/null || gh repo list --limit 200

    log_action "Listed GitHub repos via gh CLI (count: ${repo_count})"
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

github_browse_repo_files() {
    show_header
    echo -e "${YELLOW}${BOLD}🗂️  BROWSE REPOSITORY FILES & FOLDERS${NC}\n"
    if ! ensure_gh_ready; then pause; return; fi

    echo -e "${CYAN}--> Fetching your repositories...${NC}"
    local repo_lines=()
    while IFS= read -r r; do
        [[ -n "$r" ]] && repo_lines+=("repo"$'\t'"$r")
    done < <(gh repo list --limit 200 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null)

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

    local current_path=""
    while true; do
        local api_path="repos/${repo_full}/contents"
        [[ -n "$current_path" ]] && api_path="${api_path}/${current_path}"

        local raw_entries
        raw_entries=$(gh api "$api_path" --jq '.[] | .type + "\t" + .name' 2>/dev/null)
        if [[ -z "$raw_entries" ]]; then
            # Might be a file at this path (shouldn't happen via our own navigation), or an empty/broken dir
            echo -e "${RED}[!] Could not list contents at '${current_path:-/}' (empty, or a 'gh api' error).${NC}"
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
                    gh api "repos/${repo_full}/contents/${file_path}" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | bat --paging=always --style=numbers -l "${sel_name##*.}"
                else
                    gh api "repos/${repo_full}/contents/${file_path}" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | GIT_PAGER=cat less -R 2>/dev/null || \
                    gh api "repos/${repo_full}/contents/${file_path}" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null
                fi
                pause
                ;;
        esac
    done
}

github_cli_hub_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🐙 GitHub CLI Hub${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List My Repositories"
        echo -e "      ${CYAN}Every repo on your account, with visibility and last-updated info.${NC}"
        echo -e "  ${GREEN}[2]${NC} Browse Repository Files & Folders"
        echo -e "      ${CYAN}Full file/folder tree for any of your repos — not just the README.${NC}"
        echo -e "  ${GREEN}[3]${NC} Check / Setup gh Authentication"
        echo -e "  ${GREEN}[4]${NC} Back"
        read -p "Select choice [1-4]: " GHCHOICE
        case $GHCHOICE in
            1) github_list_my_repos ;;
            2) github_browse_repo_files ;;
            3)
                show_header
                if command -v gh &>/dev/null; then
                    if gh auth status &>/dev/null; then
                        echo -e "${GREEN}[✔] gh is installed and authenticated.${NC}"
                        gh auth status
                    else
                        echo -e "${YELLOW}[i] gh is installed but not logged in.${NC}"
                        read -p "Run 'gh auth login' now? (y/N): " DL
                        [[ "$DL" =~ ^[Yy]$ ]] && gh auth login
                    fi
                else
                    suggest_install "gh"
                fi
                pause
                ;;
            4) return ;;
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
        echo -e "  ${GREEN}[5]${NC} Back"
        read -p "Select choice [1-5]: " OCHOICE
        case $OCHOICE in
            1) oss_setup_fork ;;
            2) oss_sync_fork ;;
            3) oss_create_pr ;;
            4) oss_view_prs ;;
            5) break ;;
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
# DELTA DIFF SUITE — provider-agnostic, pure git + delta. Module 7.
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
    read -p "Enter FIRST commit hash: " C1
    read -p "Enter SECOND commit hash: " C2
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
    read -p "Enter commit hash to view: " CH
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
    echo -e "  ${GREEN}[4]${NC} Back"
    read -p "Select choice [1-4]: " DCHOICE
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
            read -p "Enter a delta/bat syntax theme name (e.g. 'Dracula', 'Monokai Extended'): " THEME
            if [[ -n "$THEME" ]]; then
                git config --global delta.syntax-theme "$THEME"
                echo -e "${GREEN}[✔] Theme set to: ${THEME}${NC}"
                log_action "delta.syntax-theme set to ${THEME}"
            fi
            ;;
        4) return ;;
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
        echo -e "  ${GREEN}[7]${NC} Back"
        read -p "Select choice [1-7]: " DDCHOICE
        case $DDCHOICE in
            1) delta_view_uncommitted ;;
            2) delta_view_staged ;;
            3) delta_compare_branches ;;
            4) delta_compare_commits ;;
            5) delta_view_single_commit ;;
            6) delta_display_settings ;;
            7) break ;;
        esac
    done
}

# ==============================================================================
# GH/GLAB COMMAND CENTER — Module 7. Provider-routed via vcs_* dispatchers.
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
        echo -e "  ${GREEN}[6]${NC} Back"
        read -p "Select choice [1-6]: " ICHOICE
        case $ICHOICE in
            1) show_header; vcs_list_issues; pause ;;
            2) read -p "Issue number: " N; [[ -n "$N" ]] && { show_header; vcs_view_issue "$N"; }; pause ;;
            3)
                read -p "Title: " T
                read -p "Body: " B
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
                read -p "Issue number: " N
                read -p "Comment: " C
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
                read -p "Issue number to close: " N
                if [[ -n "$N" ]] && confirm_destructive "Close issue #${N}"; then
                    vcs_close_issue "$N"
                    log_action "Closed issue #${N}"
                fi
                pause
                ;;
            6) break ;;
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
        echo -e "  ${GREEN}[6]${NC} Back"
        read -p "Select choice [1-6]: " PCHOICE
        case $PCHOICE in
            1) show_header; vcs_list_change_requests; pause ;;
            2) read -p "${label%s} number: " N; [[ -n "$N" ]] && vcs_checkout_change_request "$N"; pause ;;
            3) read -p "${label%s} number: " N; [[ -n "$N" ]] && { show_header; vcs_diff_change_request "$N" | delta_view; }; pause ;;
            4)
                read -p "${label%s} number to merge: " N
                if [[ -n "$N" ]] && confirm_destructive "Merge ${label%s} #${N}"; then
                    vcs_merge_change_request "$N"
                    log_action "Merged ${label%s} #${N}"
                fi
                pause
                ;;
            5)
                read -p "Title: " T
                read -p "Description: " B
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
            6) break ;;
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
        echo -e "  ${GREEN}[5]${NC} Back"
        read -p "Select choice [1-5]: " RCHOICE
        case $RCHOICE in
            1) show_header; vcs_list_releases; pause ;;
            2) show_header; vcs_view_latest_release; pause ;;
            3)
                read -p "Tag (e.g. v1.0.0): " TAG
                read -p "Title: " TITLE
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
                read -p "Tag to delete: " TAG
                if [[ -n "$TAG" ]] && confirm_destructive "Delete release ${TAG}"; then
                    vcs_delete_release "$TAG"
                    log_action "Deleted release ${TAG}"
                fi
                pause
                ;;
            5) break ;;
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
        echo -e "  ${GREEN}[5]${NC} Back"
        read -p "Select choice [1-5]: " RUCHOICE
        case $RUCHOICE in
            1) show_header; vcs_list_runs; pause ;;
            2) show_header; vcs_watch_run ;;
            3) show_header; vcs_trigger_run; pause ;;
            4) read -p "Run/Job ID: " N; [[ -n "$N" ]] && { show_header; vcs_view_run_logs "$N"; }; pause ;;
            5) break ;;
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
        echo -e "  ${GREEN}[3]${NC} Back"
        read -p "Select choice [1-3]: " GCHOICE
        case $GCHOICE in
            1) show_header; vcs_list_snippets; pause ;;
            2)
                read -p "Path to file: " F
                if [[ -f "$F" ]]; then
                    vcs_create_snippet "$F"
                    log_action "Created ${label%s} from ${F}"
                else
                    echo -e "${RED}[!] File not found.${NC}"
                fi
                pause
                ;;
            3) break ;;
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
    echo -e "  ${GREEN}[5]${NC} Back"
    read -p "Select choice [1-5]: " CSCHOICE
    case $CSCHOICE in
        1) gh codespace list ;;
        2) gh codespace create ;;
        3) read -p "Codespace name: " N; [[ -n "$N" ]] && gh codespace ssh -c "$N" ;;
        4) read -p "Codespace name: " N; [[ -n "$N" ]] && gh codespace stop -c "$N" ;;
        5) return ;;
    esac
    pause
}

cc_repo_admin_menu() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}🛠️  REPO / PROJECT ADMIN (${VCS_PROVIDER^})${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Create New Repo"
        echo -e "  ${GREEN}[2]${NC} Rename Current Repo"
        echo -e "  ${RED}[3]${NC} Delete a Repo ${RED}(PERMANENT!)${NC}"
        echo -e "  ${GREEN}[4]${NC} Back"
        read -p "Select choice [1-4]: " ACHOICE
        case $ACHOICE in
            1)
                read -p "New repo name: " N
                echo -e "  [1] Public  [2] Private"
                read -p "Visibility [1-2]: " V
                local vis="public"
                [[ "$V" == "2" ]] && vis="private"
                if [[ -n "$N" ]]; then
                    vcs_create_repo "$N" "$vis"
                    log_action "Created ${VCS_PROVIDER} repo: ${N} (${vis})"
                fi
                pause
                ;;
            2)
                read -p "New name for THIS repo: " N
                if [[ -n "$N" ]] && confirm_destructive "Rename this repo to '${N}'"; then
                    vcs_rename_repo "$N"
                    log_action "Renamed repo to ${N}"
                fi
                pause
                ;;
            3)
                read -p "Full name of repo to DELETE (owner/repo): " N
                if [[ -n "$N" ]] && confirm_destructive "PERMANENTLY DELETE '${N}' — this cannot be undone"; then
                    vcs_delete_repo "$N"
                    log_action "DELETED repo: ${N}"
                fi
                pause
                ;;
            4) break ;;
        esac
    done
}

cc_api_explorer() {
    show_header
    echo -e "${YELLOW}${BOLD}🔬 RAW API EXPLORER (${VCS_PROVIDER^}) — Advanced${NC}\n"
    echo -e "${CYAN}Enter a raw API path, e.g.: repos/OWNER/REPO/contents  (GitHub) or projects/ID/issues (GitLab)${NC}\n"
    read -p "API path: " PATH_IN
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

        echo -e "  ${GREEN}[1]${NC} Issues"
        echo -e "  ${GREEN}[2]${NC} ${pr_label}"
        echo -e "  ${GREEN}[3]${NC} Releases"
        echo -e "  ${GREEN}[4]${NC} ${ci_label} / CI"
        echo -e "  ${GREEN}[5]${NC} ${gist_label}"
        echo -e "  ${GREEN}[6]${NC} Codespaces ${CYAN}$([[ "$VCS_PROVIDER" != "github" ]] && echo '(GitHub only)')${NC}"
        echo -e "  ${GREEN}[7]${NC} Repo / Project Admin"
        echo -e "  ${GREEN}[8]${NC} Raw API Explorer (advanced)"
        echo -e "  ${GREEN}[9]${NC} Delta Diff Suite"
        echo -e "  ${GREEN}[10]${NC} Switch Provider (currently: ${VCS_PROVIDER^})"
        echo -e "  ${GREEN}[11]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -p "Select choice [1-11]: " GPCHOICE
        case $GPCHOICE in
            1) ensure_vcs_ready && cc_issues_menu ;;
            2) ensure_vcs_ready && cc_change_requests_menu ;;
            3) ensure_vcs_ready && cc_releases_menu ;;
            4) ensure_vcs_ready && cc_runs_menu ;;
            5) ensure_vcs_ready && cc_snippets_menu ;;
            6) ensure_vcs_ready && cc_codespaces_menu ;;
            7) ensure_vcs_ready && cc_repo_admin_menu ;;
            8) ensure_vcs_ready && cc_api_explorer ;;
            9) delta_diff_suite_menu ;;
            10)
                echo -e "  [1] GitHub  [2] GitLab"
                read -p "Choice [1-2]: " SW
                case $SW in
                    1) VCS_PROVIDER="github" ;;
                    2) VCS_PROVIDER="gitlab" ;;
                esac
                ;;
            11) break ;;
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
        if [[ "$WIZARD_MODE" == "advanced" ]]; then
            echo -e "  ${GREEN}[3]${NC} Open-Source Contributor Mode (fork + PR)"
            echo -e "      ${CYAN}You're contributing to someone ELSE'S repo (or accepting outside PRs on yours).${NC}"
        else
            echo -e "  ${CYAN}[3]${NC} Open-Source Contributor Mode ${YELLOW}(switch to Advanced Mode to unlock)${NC}"
            echo -e "      ${CYAN}Fork/upstream/PR workflow for contributing to repos you don't own.${NC}"
        fi
        echo -e "  ${GREEN}[4]${NC} GitHub CLI Hub (list repos, browse full file/folder tree, PRs, auth)"
        echo -e "      ${CYAN}Everything gh-powered — including the file/folder browser, not just README.${NC}"
        echo -e "  ${GREEN}[5]${NC} Safe Update Sync (protects local work while pulling)"
        echo -e "      ${CYAN}Stashes your uncommitted work, pulls latest, restores your work on top.${NC}"
        echo -e "  ${GREEN}[6]${NC} Repo History Viewer"
        echo -e "      ${CYAN}Shows commit graph across all branches (uses 'delta' for prettier diffs if installed).${NC}"
        echo -e "  ${GREEN}[7]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -p "Select choice [1-7]: " M5_CHOICE
        case $M5_CHOICE in
            1) linear_workflow ;;
            2) team_mode ;;
            3)
                if [[ "$WIZARD_MODE" == "advanced" ]]; then
                    oss_contributor_mode
                else
                    echo -e "${YELLOW}[i] This feature is hidden in Beginner Mode. Switch modes from the Main Menu.${NC}"
                    sleep 2
                fi
                ;;
            4) github_cli_hub_menu ;;
            5) safe_update_sync ;;
            6) repo_history_viewer ;;
            7) break ;;
        esac
    done
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
        echo -e "  ${GREEN}[5]${NC} Back"
        read -p "Select choice [1-5]: " BCHOICE
        case $BCHOICE in
            1)
                show_header
                if command -v lazygit &>/dev/null; then
                    echo -e "${CYAN}--> Launching lazygit...${NC}"
                    (cd "$TARGET_REPO_DIR" && lazygit)
                else
                    echo -e "${YELLOW}[i] 'lazygit' is not installed.${NC}"
                    offer_install "lazygit"
                    pause
                fi
                ;;
            2)
                show_header
                if command -v git-absorb &>/dev/null; then
                    echo -e "${CYAN}--> Running git-absorb (dry run first)...${NC}"
                    (cd "$TARGET_REPO_DIR" && git absorb --dry-run)
                    read -p "Apply for real? (y/N): " DOABSORB
                    if [[ "$DOABSORB" =~ ^[Yy]$ ]]; then
                        (cd "$TARGET_REPO_DIR" && git absorb --and-rebase)
                        log_action "Ran git-absorb --and-rebase"
                    fi
                else
                    echo -e "${YELLOW}[i] 'git-absorb' is not installed.${NC}"
                    offer_install "git-absorb"
                fi
                pause
                ;;
            3)
                show_header
                if command -v ghq &>/dev/null; then
                    echo -e "${CYAN}Your ghq-managed repos:${NC}\n"
                    ghq list
                    echo -e "\n  [1] Clone a new repo via ghq   [2] Back"
                    read -p "Choice [1-2]: " GQ
                    if [[ "$GQ" == "1" ]]; then
                        read -p "Repo URL: " GURL
                        [[ -n "$GURL" ]] && ghq get "$GURL"
                    fi
                else
                    echo -e "${YELLOW}[i] 'ghq' is not installed.${NC}"
                    offer_install "ghq"
                fi
                pause
                ;;
            4)
                show_header
                echo -e "${YELLOW}${BOLD}🧪 LOCAL CI TESTING${NC}\n"
                echo -e "${CYAN}Runs your CI pipeline locally in Docker BEFORE you push — needs Docker installed & running.${NC}\n"
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
                        read -p "  Install now? (y/N): " DOGCL
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
            5) break ;;
        esac
    done
}

check_tool_stack_versions() {
    show_header
    echo -e "${YELLOW}${BOLD}🔎 TOOL STACK VERSIONS${NC}\n"
    local tools=("git" "gh" "glab" "delta" "chafa" "lazygit" "git-absorb" "ghq" "act" "pre-commit")
    for t in "${tools[@]}"; do
        if command -v "$t" &>/dev/null; then
            local v
            v=$("$t" --version 2>/dev/null | head -1)
            echo -e "  ${GREEN}[✔]${NC} ${BOLD}${t}${NC}: ${v}"
        else
            echo -e "  ${RED}[✘]${NC} ${BOLD}${t}${NC}: not installed"
        fi
    done
    echo -e "\n${CYAN}[i] This tool doesn't auto-check upstream latest versions to avoid extra network calls on every check.${NC}"
    echo -e "${CYAN}    Compare against release pages manually if you suspect something's outdated.${NC}"
    pause
}


load_config
if [[ -z "$WIZARD_MODE" ]]; then
    mode_selection_wrapper
fi
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
    echo -e "      ${CYAN}Solo, private-team, fork-based, and GitHub CLI Hub workflows.${NC}"
    echo -e "  ${GREEN}[6]${NC} Enable Universal Global CLI"
    echo -e "      ${CYAN}Lets you run 'git-wizard' from any folder on this machine.${NC}"
    echo -e "  ${YELLOW}${BOLD}[7] ⚡ Git Hosting Power Tools (GitHub/GitLab)${NC}"
    echo -e "      ${CYAN}Issues, PRs/MRs, Releases, Actions/Pipelines, Gists/Snippets, Repo Admin, Delta Diff Suite.${NC}"
    echo -e "  ${GREEN}[8]${NC} Settings ${CYAN}(Mode / Dry-Run / Package Check / Updates / Action History)${NC}"
    echo -e "  ${GREEN}[9]${NC} Exit"
    echo -e "\n===================================================================="
    read -p "Enter choice [1-9]: " MAIN_CHOICE

    case $MAIN_CHOICE in
        1) manage_identity ;;
        2) manage_repo ;;
        3) manage_branches ;;
        4) commit_assistant ;;
        5) module_5_menu ;;
        6) enable_global_cli ;;
        7) github_power_tools_menu ;;
        8)
            while true; do
                show_header
                echo -e "${YELLOW}${BOLD}⚙️ SETTINGS${NC}\n"
                echo -e "  ${GREEN}[1]${NC} Switch Mode (current: ${WIZARD_MODE})"
                echo -e "  ${GREEN}[2]${NC} Toggle Dry-Run (current: ${DRY_RUN})"
                echo -e "  ${GREEN}[3]${NC} GitHub Sync Panel Settings (on/off, detail level)"
                echo -e "  ${GREEN}[4]${NC} Cross-Distro Package Verification (gh, glab, delta, chafa)"
                echo -e "  ${GREEN}[5]${NC} View Tool Action History"
                echo -e "  ${GREEN}[6]${NC} Check for git-wizard Updates ${CYAN}(source: ${UPDATE_REPO:-not set})${NC}"
                echo -e "  ${GREEN}[7]${NC} Set Update Source Repo"
                echo -e "  ${GREEN}[8]${NC} Setup Pre-Commit Hooks for THIS repo"
                echo -e "  ${GREEN}[9]${NC} Bonus Tools (lazygit, git-absorb, ghq, local CI runners)"
                echo -e "  ${GREEN}[10]${NC} Check Tool Stack Versions"
                echo -e "  ${GREEN}[11]${NC} Back"
                read -p "Select choice [1-11]: " S_CHOICE
                case $S_CHOICE in
                    1) toggle_mode ;;
                    2) toggle_dry_run ;;
                    3) github_sync_menu ;;
                    4) check_optional_tools ;;
                    5) show_action_history ;;
                    6) show_header; check_for_updates; pause ;;
                    7) configure_update_repo ;;
                    8) setup_precommit_hooks ;;
                    9) bonus_tools_menu ;;
                    10) check_tool_stack_versions ;;
                    11) break ;;
                esac
            done
            ;;
        9) echo -e "\n${GREEN}Keep building amazing open-source software! Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
    esac
done