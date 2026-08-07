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

suggest_install() {
    local tool="$1"
    local pm
    pm=$(detect_pkg_manager)
    echo -e "${YELLOW}[i] '${tool}' is not installed.${NC}"
    case $pm in
        apt)     echo -e "    Install with: ${GREEN}sudo apt install ${tool}${NC}" ;;
        dnf)     echo -e "    Install with: ${GREEN}sudo dnf install ${tool}${NC}" ;;
        pacman)  echo -e "    Install with: ${GREEN}sudo pacman -S ${tool}${NC}" ;;
        brew)    echo -e "    Install with: ${GREEN}brew install ${tool}${NC}" ;;
        *)       echo -e "    Please install '${tool}' using your system's package manager." ;;
    esac
}

check_optional_tools() {
    show_header
    echo -e "${YELLOW}${BOLD}🔎 CROSS-DISTRO TOOL VERIFICATION${NC}\n"
    for tool in gh delta chafa; do
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}[✔] ${tool} — installed${NC}"
        else
            echo -e "  ${RED}[✘] ${tool} — missing${NC}"
            suggest_install "$tool"
        fi
    done
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

    git -C "$TARGET_REPO_DIR" fetch --quiet 2>/dev/null || true

    local upstream
    upstream=$(git -C "$TARGET_REPO_DIR" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null || echo "")
    if [[ -z "$upstream" ]]; then
        echo -e "${YELLOW}🔄 ${branch}: no upstream tracking set${NC}"
        return
    fi

    local ahead behind
    ahead=$(git -C "$TARGET_REPO_DIR" rev-list --count "${upstream}..${branch}" 2>/dev/null || echo 0)
    behind=$(git -C "$TARGET_REPO_DIR" rev-list --count "${branch}..${upstream}" 2>/dev/null || echo 0)

    if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
        echo -e "${GREEN}🔄 ${branch}: ✅ Fully synced with ${upstream}${NC}"
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
    echo -e "${YELLOW}GitHub  :${NC} ${BOLD}https://github.com/ali4210${NC}\n"
    echo -e "${YELLOW}Active Repository Context:${NC} ${BOLD}${TARGET_REPO_DIR}${NC}"
    echo -e "${YELLOW}Mode:${NC} ${BOLD}${WIZARD_MODE^}${NC}   ${YELLOW}Dry-Run:${NC} ${BOLD}${DRY_RUN}${NC}   ${YELLOW}Auto-Sync:${NC} ${BOLD}${AUTO_SYNC_CHECK}${NC} ${CYAN}[Module 5 > option 6 to toggle]${NC}"

    if [[ "$AUTO_SYNC_CHECK" == "true" ]]; then
        local status_line
        status_line=$(get_sync_status)
        if [[ -n "$status_line" ]]; then
            echo -e "$status_line"
        fi
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

toggle_auto_sync() {
    if [[ "$AUTO_SYNC_CHECK" == "true" ]]; then AUTO_SYNC_CHECK="false"; else AUTO_SYNC_CHECK="true"; fi
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
        echo -e "  ${GREEN}[5]${NC} Check gh CLI Installed"
        echo -e "      ${CYAN}Verifies GitHub's official CLI is present (required for PR options above).${NC}"
        echo -e "  ${GREEN}[6]${NC} Back"
        read -p "Select choice [1-6]: " OCHOICE
        case $OCHOICE in
            1) oss_setup_fork ;;
            2) oss_sync_fork ;;
            3) oss_create_pr ;;
            4) oss_view_prs ;;
            5)
                if command -v gh &>/dev/null; then
                    echo -e "${GREEN}[✔] gh CLI is installed: $(gh --version | head -1)${NC}"
                else
                    suggest_install "gh"
                fi
                pause
                ;;
            6) break ;;
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

# --- 5.5 Repo History Viewer ---
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
        echo -e "  ${GREEN}[4]${NC} Safe Update Sync (protects local work while pulling)"
        echo -e "      ${CYAN}Stashes your uncommitted work, pulls latest, restores your work on top.${NC}"
        echo -e "  ${GREEN}[5]${NC} Repo History Viewer"
        echo -e "      ${CYAN}Shows commit graph across all branches (uses 'delta' for prettier diffs if installed).${NC}"
        echo -e "  ${GREEN}[6]${NC} Toggle Auto-Sync Indicator (currently: ${AUTO_SYNC_CHECK})"
        echo -e "      ${CYAN}Shows a live ahead/behind status vs GitHub at the top of every screen.${NC}"
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
            4) safe_update_sync ;;
            5) repo_history_viewer ;;
            6) toggle_auto_sync ;;
            7) break ;;
        esac
    done
}

# ==============================================================================
# MAIN MASTER LOOP
# ==============================================================================
load_config
if [[ -z "$WIZARD_MODE" ]]; then
    mode_selection_wrapper
fi

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
    echo -e "      ${CYAN}Solo, private-team, and fork-based contribution workflows.${NC}"
    echo -e "  ${GREEN}[6]${NC} Enable Universal Global CLI"
    echo -e "      ${CYAN}Lets you run 'git-wizard' from any folder on this machine.${NC}"
    echo -e "  ${GREEN}[7]${NC} Settings ${CYAN}(Mode / Dry-Run / Package Check / Action History)${NC}"
    echo -e "  ${GREEN}[8]${NC} Exit"
    echo -e "\n===================================================================="
    read -p "Enter choice [1-8]: " MAIN_CHOICE

    case $MAIN_CHOICE in
        1) manage_identity ;;
        2) manage_repo ;;
        3) manage_branches ;;
        4) commit_assistant ;;
        5) module_5_menu ;;
        6) enable_global_cli ;;
        7)
            while true; do
                show_header
                echo -e "${YELLOW}${BOLD}⚙️ SETTINGS${NC}\n"
                echo -e "  ${GREEN}[1]${NC} Switch Mode (current: ${WIZARD_MODE})"
                echo -e "  ${GREEN}[2]${NC} Toggle Dry-Run (current: ${DRY_RUN})"
                echo -e "  ${GREEN}[3]${NC} Toggle Auto-Sync Indicator (current: ${AUTO_SYNC_CHECK})"
                echo -e "  ${GREEN}[4]${NC} Cross-Distro Package Verification (gh, delta, chafa)"
                echo -e "  ${GREEN}[5]${NC} View Tool Action History"
                echo -e "  ${GREEN}[6]${NC} Back"
                read -p "Select choice [1-6]: " S_CHOICE
                case $S_CHOICE in
                    1) toggle_mode ;;
                    2) toggle_dry_run ;;
                    3) toggle_auto_sync ;;
                    4) check_optional_tools ;;
                    5) show_action_history ;;
                    6) break ;;
                esac
            done
            ;;
        8) echo -e "\n${GREEN}Keep building amazing open-source software! Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
    esac
done