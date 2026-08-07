#!/usr/bin/env bash
# ==============================================================================
# TOOL NAME:    git-wizard.sh (Universal Global CLI Gold Standard Edition V2.0)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Enterprise-Grade Git Orchestrator, Multi-Mode Workflow Suite, 
#               Fork-Aware Upstream Sync Engine, and PR Release Center.
# COMPATIBILITY: Linux (Debian, Kali, Ubuntu, RHEL, CentOS, Arch), macOS, WSL
# ==============================================================================

set -e

# Target repository context
TARGET_REPO_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${HOME}/.git_wizard"
STATE_FILE="${STATE_DIR}/state.json"

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Ensure State Directory Exists
mkdir -p "$STATE_DIR"

# State Variables Initialization
if [ ! -f "$STATE_FILE" ]; then
    cat <<EOF > "$STATE_FILE"
{
  "mode": "Enterprise",
  "dry_run": false,
  "sync_watcher": true
}
EOF
fi

# Load State Settings
GW_MODE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('mode','Enterprise'))" 2>/dev/null || echo "Enterprise")
GW_DRY_RUN=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('dry_run',False))" 2>/dev/null || echo "false")
GW_WATCHER=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('sync_watcher',True))" 2>/dev/null || echo "true")

save_state() {
    cat <<EOF > "$STATE_FILE"
{
  "mode": "$GW_MODE",
  "dry_run": $GW_DRY_RUN,
  "sync_watcher": $GW_WATCHER
}
EOF
}

# --- Pager Helper (Delta or Native Git) ---
get_pager() {
    if command -v delta &>/dev/null; then
        echo "delta"
    else
        echo "cat"
    fi
}

# --- Dynamic Remote Sync Status Header ---
get_sync_status() {
    if ! git -C "$TARGET_REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}[NOT A GIT REPO]${NC}"
        return
    fi

    if [ "$GW_WATCHER" = "true" ]; then
        git -C "$TARGET_REPO_DIR" fetch origin --quiet 2>/dev/null || true
    fi

    local branch
    branch=$(git -C "$TARGET_REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
    
    local ahead behind
    ahead=$(git -C "$TARGET_REPO_DIR" rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo "0")
    behind=$(git -C "$TARGET_REPO_DIR" rev-list --count "HEAD..origin/${branch}" 2>/dev/null || echo "0")

    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
        echo -e "${GREEN}🟢 100% SYNCED WITH GITHUB${NC} (Branch: ${CYAN}${branch}${NC})"
    elif [ "$ahead" -gt 0 ] && [ "$behind" -eq 0 ]; then
        echo -e "${YELLOW}🟡 LOCAL AHEAD BY $ahead COMMIT(S)${NC} (Needs Push)"
    elif [ "$ahead" -eq 0 ] && [ "$behind" -gt 0 ]; then
        echo -e "${RED}🔴 LOCAL BEHIND BY $behind COMMIT(S)${NC} (Needs Safe Sync)"
    else
        echo -e "${RED}⚠️ DIVERGED (Ahead: $ahead | Behind: $behind)${NC} (Conflict Resolver Needed)"
    fi
}

show_header() {
    clear
    IMAGE_PATH="${SCRIPT_DIR}/assets/octocat.png"

    if command -v chafa &>/dev/null && [[ -f "$IMAGE_PATH" ]]; then
        chafa --size=35x12 "$IMAGE_PATH" 2>/dev/null || true
        echo ""
    else
        echo -e "${CYAN}${BOLD}"
        cat << "EOF"
  ██████╗ ██╗████████╗    ██╗██╗    ██╗██╗███████╗██████╗  ██████╗ 
 ██╔════╝ ██║╚══██╔══╝    ██║██║    ██║██║██╔════╝██╔══██╗██╔════╝ 
 ██║  ███╗██║   ██║  ███████║██║ █╗ ██║██║███████╗██████╔╝██║  ███╗
 ██║   ██║██║   ██║  ╚════██║██║███╗██║██║╚════██║██╔══██╗██║   ██║
 ╚██████╔╝██║   ██║       ██║╚███╔███╔╝██║███████║██║  ██║╚██████╔╝
  ╚═════╝ ╚═╝   ╚═╝       ╚═╝ ╚══╝╚══╝ ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ 
EOF
        echo -e "${NC}"
    fi

    local remote_url
    remote_url=$(git -C "$TARGET_REPO_DIR" remote get-url origin 2>/dev/null || echo "No Remote Configured")
    local upstream_url
    upstream_url=$(git -C "$TARGET_REPO_DIR" remote get-url upstream 2>/dev/null || echo "None")

    local dry_run_text
    dry_run_text=$( [ "$GW_DRY_RUN" = "true" ] && echo -e "${YELLOW}[ON - PREVIEW MODE]${NC}" || echo -e "${CYAN}[OFF - LIVE WRITES]${NC}" )
    local watcher_text
    watcher_text=$( [ "$GW_WATCHER" = "true" ] && echo -e "${GREEN}[ENABLED]${NC}" || echo -e "${RED}[DISABLED]${NC}" )

    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${CYAN}${BOLD}        🧙‍♂️ GIT-WIZARD ULTIMATE - ENTERPRISE GITHUB ENGINE           ${NC}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${YELLOW}Active Repo Path:${NC} ${BOLD}${TARGET_REPO_DIR}${NC}"
    echo -e "${YELLOW}Origin Remote   :${NC} ${CYAN}${remote_url}${NC}"
    if [ "$upstream_url" != "None" ]; then
        echo -e "${YELLOW}Upstream Remote :${NC} ${CYAN}${upstream_url}${NC}"
    fi
    echo -e "${YELLOW}Sync Status     :${NC} $(get_sync_status)"
    echo -e "${YELLOW}Engine Mode     :${NC} ${GREEN}${GW_MODE}${NC} | ${YELLOW}Dry-Run:${NC} ${dry_run_text} | ${YELLOW}Watcher:${NC} ${watcher_text}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}\n"
}

pause() {
    echo ""
    read -rp "Press [ENTER] to return to menu..."
}

show_uptodate_celebration() {
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"
          ,~-.
         (   ' )-.          ,~'`-.
      ,~' `   ' ) )        _(    _) )
     ( ( .--.===.--.    (    `    ' )
      `.%%.;::|888.#`.   `-'`~~=~'
      /%%/::::|8888\##\
     |%%/:::::|88888\##|
EOF
    echo -e "${NC}"
    echo -e "${GREEN}${BOLD}Everything up-to-date! Code is safe and synced on GitHub!${NC}"
}

clean_remote_url() {
    local input_url="$1"
    input_url=$(echo "$input_url" | sed -E 's/^git remote (add|set-url) origin //I' | xargs)
    echo "$input_url"
}

check_git_repo() {
    if ! git -C "$TARGET_REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        show_header
        echo -e "${RED}[!] WARNING: '${TARGET_REPO_DIR}' is NOT a Git repository!${NC}\n"
        echo -e "${CYAN}Available Actions:${NC}"
        echo -e "  ${GREEN}[1]${NC} Initialize a new Git Repository here (${BOLD}git init${NC})"
        echo -e "  ${YELLOW}${BOLD}[2] ⚡ Enable Universal Global CLI (Install 'git-wizard' system-wide)${NC}"
        echo -e "  ${GREEN}[3]${NC} Exit"
        echo -e "\n===================================================================="
        read -rp "Select choice [1-3]: " NON_REPO_CHOICE

        case $NON_REPO_CHOICE in
            1)
                git -C "$TARGET_REPO_DIR" init
                git -C "$TARGET_REPO_DIR" branch -M main 2>/dev/null || true
                echo -e "${GREEN}[✔] Initialized empty Git repository in ${TARGET_REPO_DIR}!${NC}"
                pause
                ;;
            2) enable_global_cli ;;
            3) exit 0 ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    fi
}

# --- Module: Global CLI & Profile Block Installer ---
enable_global_cli() {
    show_header
    echo -e "${YELLOW}${BOLD}⚡ MODULE: UNIVERSAL GLOBAL CLI & MANAGED BLOCK INSTALLER${NC}\n"
    
    local TARGET_BIN="/usr/local/bin/git-wizard"
    local SCRIPT_PATH="${SCRIPT_DIR}/git-wizard.sh"
    chmod +x "$SCRIPT_PATH" 2>/dev/null || true

    if [ "$GW_DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Would create symlink from $SCRIPT_PATH to $TARGET_BIN${NC}"
        pause
        return
    fi

    echo -e "${CYAN}--> Creating global symlink at $TARGET_BIN...${NC}"
    if [ -w "/usr/local/bin" ]; then
        ln -sf "$SCRIPT_PATH" "$TARGET_BIN"
    else
        sudo ln -sf "$SCRIPT_PATH" "$TARGET_BIN"
    fi

    local SHELL_RC=""
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
    fi

    if [ -n "$SHELL_RC" ]; then
        echo -e "${CYAN}--> Injecting Managed Profile Block into $SHELL_RC...${NC}"
        
        BLOCK_START="# >>> GIT-WIZARD MANAGED BLOCK >>>"
        BLOCK_END="# <<< GIT-WIZARD MANAGED BLOCK <<<"
        ALIAS_LINE="alias gw='git-wizard'"

        if grep -q "$BLOCK_START" "$SHELL_RC"; then
            echo -e "${GREEN}[OK] Managed profile block already exists in $SHELL_RC${NC}"
        else
            echo -e "\n$BLOCK_START\n$ALIAS_LINE\n$BLOCK_END" >> "$SHELL_RC"
            echo -e "${GREEN}[✔] Added 'gw' alias cleanly inside Managed Profile Block!${NC}"
        fi
    fi

    echo -e "\n===================================================================="
    echo -e "${GREEN}${BOLD}[✔] GIT-WIZARD IS NOW INSTALLED GLOBALLY ON YOUR SYSTEM!${NC}"
    echo -e "===================================================================="
    echo -e "${CYAN}📌 You can now open ANY terminal and type: ${GREEN}${BOLD}git-wizard${NC} or ${GREEN}${BOLD}gw${NC}"
    echo -e "====================================================================\n"
    pause
}

# --- Module 1: Linear Solo Mode ---
linear_solo_mode() {
    show_header
    echo -e "${YELLOW}${BOLD}🔄 LINEAR SOLO MODE (1-PERSON SEQUENTIAL WORKFLOW)${NC}\n"
    
    if [ "$GW_MODE" = "Beginner" ]; then
        echo -e "${CYAN}💡 BEGINNER GUIDE:${NC}"
        echo -e "Use this mode when you are working alone on 'main'."
        echo -e "Always pull before pushing to keep your timeline clean.\n"
    fi

    git add .
    if [ -z "$(git status --porcelain)" ]; then
        echo -e "${YELLOW}[i] Working tree clean (no new changes to commit).${NC}\n"
        show_uptodate_celebration
        pause
        return
    fi

    read -rp "Enter commit message: " MSG
    if [ -z "$MSG" ]; then
        echo -e "${RED}Commit message cannot be empty!${NC}"
        pause
        return
    fi

    if [ "$GW_DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Would run: git commit -m \"$MSG\" && git push origin main${NC}"
        pause
        return
    fi

    git commit -m "$MSG"
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    
    echo -e "${GREEN}--> Pushing changes to origin $branch...${NC}"
    git push origin "$branch" || echo -e "${YELLOW}[!] Push rejected. Use Module [5] (Smart Conflict Push Resolver) to sync!${NC}"
    pause
}

# --- Module 2: Enterprise Team Mode ---
enterprise_team_mode() {
    show_header
    echo -e "${YELLOW}${BOLD}🌿 ENTERPRISE TEAM MODE (FEATURE BRANCH & PULL REQUEST FLOW)${NC}\n"

    if [ "$GW_MODE" = "Beginner" ]; then
        echo -e "${CYAN}💡 BEGINNER GUIDE:${NC}"
        echo -e "Use this mode when working with teammates."
        echo -e "Create a new branch so your changes stay isolated without breaking 'main'!\n"
    fi

    echo -e "Select branch classification:"
    echo -e "  ${GREEN}[1] feature/${NC}  New feature or capability"
    echo -e "  ${GREEN}[2] bugfix/${NC}   Bug fix / resolution"
    echo -e "  ${GREEN}[3] hotfix/${NC}   Urgent production fix"
    echo -e "  ${GREEN}[4] docs/${NC}     Documentation update"
    read -rp "Select type [1-4]: " B_TYPE

    local prefix=""
    case $B_TYPE in
        1) prefix="feature/" ;;
        2) prefix="bugfix/" ;;
        3) prefix="hotfix/" ;;
        4) prefix="docs/" ;;
        *) echo "Cancelled."; pause; return ;;
    esac

    read -rp "Enter short branch description (e.g., powershell-fix): " B_DESC
    if [ -z "$B_DESC" ]; then
        echo -e "${RED}Description required!${NC}"
        pause
        return
    fi

    local FULL_BRANCH="${prefix}${B_DESC}"

    if [ "$GW_DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Would create branch '$FULL_BRANCH' and push to GitHub.${NC}"
        pause
        return
    fi

    git checkout -b "$FULL_BRANCH"
    echo -e "${GREEN}[✔] Switched to new branch: $FULL_BRANCH${NC}"

    read -rp "Do you want to stage, commit, and push changes now? (y/N): " DO_PUSH
    if [[ "$DO_PUSH" =~ ^[Yy]$ ]]; then
        git add .
        read -rp "Enter commit message: " C_MSG
        C_MSG=${C_MSG:-"Work on $FULL_BRANCH"}
        git commit -m "$C_MSG"
        git push -u origin "$FULL_BRANCH"

        echo -e "\n${GREEN}[✔] Branch '$FULL_BRANCH' published to GitHub!${NC}"
        local remote_url
        remote_url=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//')
        echo -e "${CYAN}--> Open Pull Request URL: ${remote_url}/pull/new/${FULL_BRANCH}${NC}"
    fi
    pause
}

# --- Module 3: Safe Upstream Sync ---
safe_upstream_sync() {
    show_header
    echo -e "${YELLOW}${BOLD}⚡ SAFE UPSTREAM SYNC ENGINE (STASH & POP PROTECTION)${NC}\n"

    local has_upstream=false
    if git remote | grep -q "upstream"; then
        has_upstream=true
    fi

    echo -e "Target Remote Sync Strategy:"
    echo -e "  ${GREEN}[1]${NC} Sync from ${CYAN}origin/main${NC} (Standard Teammate Sync)"
    if [ "$has_upstream" = "true" ]; then
        echo -e "  ${GREEN}[2]${NC} Sync from ${CYAN}upstream/main${NC} (Fork-Aware Parent Repo Sync)"
    else
        echo -e "  ${YELLOW}[2]${NC} Configure ${CYAN}upstream${NC} Remote URL (Link Original Fork Parent)"
    fi
    read -rp "Select choice [1-2]: " SYNC_CHOICE

    local target_remote="origin"
    if [ "$SYNC_CHOICE" = "2" ]; then
        if [ "$has_upstream" = "false" ]; then
            read -rp "Enter Upstream Repository URL: " UP_URL
            UP_URL=$(clean_remote_url "$UP_URL")
            if [ -n "$UP_URL" ]; then
                git remote add upstream "$UP_URL"
                echo -e "${GREEN}[✔] Added upstream remote: $UP_URL${NC}"
            fi
            target_remote="upstream"
        else
            target_remote="upstream"
        fi
    fi

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    if [ "$GW_DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Would stash work, fetch $target_remote main, rebase $current_branch, and pop stash.${NC}"
        pause
        return
    fi

    echo -e "\n${GREEN}--> Stashing uncommitted local changes...${NC}"
    git stash save "Git-Wizard Safe Sync Auto-Stash" 2>/dev/null || true

    echo -e "${GREEN}--> Fetching latest code from $target_remote...${NC}"
    git fetch "$target_remote"

    echo -e "${GREEN}--> Rebasing $current_branch onto $target_remote/main...${NC}"
    if git rebase "$target_remote/main"; then
        echo -e "${GREEN}[✔] Rebase successful!${NC}"
    else
        echo -e "${RED}[!] Rebase conflict encountered! Aborting rebase to protect working tree...${NC}"
        git rebase --abort
    fi

    echo -e "${GREEN}--> Restoring stashed local changes...${NC}"
    git stash pop 2>/dev/null || true

    echo -e "\n${GREEN}[✔] SAFE UPSTREAM SYNC COMPLETE!${NC}"
    pause
}

# --- Module 4: Admin Merge & PR Release Center ---
admin_merge_center() {
    show_header
    echo -e "${YELLOW}${BOLD}🔀 ADMIN MERGE & PR RELEASE CENTER${NC}\n"

    echo -e "Fetching latest remote branches from GitHub..."
    git fetch origin --prune

    echo -e "\n${CYAN}--- Active Remote Contributor Branches ---${NC}"
    git branch -r | grep -v 'HEAD' | grep 'origin/' || echo "No remote feature branches found."
    echo -e "-----------------------------------------------------\n"

    echo -e "  ${GREEN}[1]${NC} Inspect Diff of a Contributor Branch"
    echo -e "  ${GREEN}[2]${NC} Merge Branch into ${CYAN}main${NC} & Push Release"
    echo -e "  ${GREEN}[3]${NC} Use GitHub CLI (${CYAN}gh${NC}) PR Review Dashboard"
    echo -e "  ${GREEN}[4]${NC} Back to Main Menu"
    read -rp "Select choice [1-4]: " MERGE_CHOICE

    case $MERGE_CHOICE in
        1)
            read -rp "Enter branch name to inspect (e.g., origin/feature/x): " TARGET_B
            if [ -n "$TARGET_B" ]; then
                show_header
                echo -e "${YELLOW}--- Line Diff for $TARGET_B vs main ---${NC}\n"
                git diff "main..$TARGET_B" | $(get_pager)
            fi
            pause
            ;;
        2)
            read -rp "Enter branch name to merge into main (e.g., feature/x): " TARGET_B
            TARGET_B=$(echo "$TARGET_B" | sed 's#^origin/##')

            if [ -n "$TARGET_B" ]; then
                if [ "$GW_DRY_RUN" = "true" ]; then
                    echo -e "${YELLOW}[DRY-RUN] Would checkout main, merge $TARGET_B, and push to origin main.${NC}"
                    pause
                    return
                fi

                git checkout main
                git pull origin main
                echo -e "${GREEN}--> Merging $TARGET_B into main...${NC}"
                git merge "origin/$TARGET_B" --no-ff -m "Merge branch '$TARGET_B' into main"
                git push origin main
                echo -e "${GREEN}[✔] Branch '$TARGET_B' merged and pushed to production main!${NC}"
            fi
            pause
            ;;
        3)
            if command -v gh &>/dev/null; then
                gh pr list
                echo ""
                read -rp "Enter PR number to review/merge (or press ENTER to exit): " PR_NUM
                if [ -n "$PR_NUM" ]; then
                    gh pr merge "$PR_NUM" --merge --delete-branch
                fi
            else
                echo -e "${RED}[!] GitHub CLI ('gh') is not installed.${NC}"
                read -rp "Would you like to install 'gh' via system package manager? (y/N): " INST_GH
                if [[ "$INST_GH" =~ ^[Yy]$ ]]; then
                    if command -v apt &>/dev/null; then sudo apt install -y gh
                    elif command -v dnf &>/dev/null; then sudo dnf install -y gh
                    elif command -v pacman &>/dev/null; then sudo pacman -S --noconfirm github-cli
                    fi
                fi
            fi
            pause
            ;;
        4) return ;;
        *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
    esac
}

# --- Module 5: Conventional Commit Assistant ---
commit_assistant() {
    show_header
    echo -e "${YELLOW}${BOLD}📝 CONVENTIONAL COMMIT CRAFTING ASSISTANT${NC}\n"
    echo -e "Select commit classification:"
    echo -e "  ${GREEN}[1] feat:${NC}     A new feature for users"
    echo -e "  ${GREEN}[2] fix:${NC}      A bug fix"
    echo -e "  ${GREEN}[3] docs:${NC}     Documentation changes only"
    echo -e "  ${GREEN}[4] refactor:${NC} Code restructuring without logic change"
    echo -e "  ${GREEN}[5] chore:${NC}    Build process or dependency updates"
    read -rp "Select choice [1-5]: " C_TYPE

    local prefix=""
    case $C_TYPE in
        1) prefix="feat" ;;
        2) prefix="fix" ;;
        3) prefix="docs" ;;
        4) prefix="refactor" ;;
        5) prefix="chore" ;;
        *) echo "Cancelled."; return ;;
    esac

    read -rp "Enter short scope (optional, e.g. auth, api): " SCOPE
    read -rp "Enter clear commit description: " DESC

    if [ -z "$DESC" ]; then
        echo -e "${RED}Description required!${NC}"
        pause
        return
    fi

    local final_msg=""
    if [ -n "$SCOPE" ]; then
        final_msg="${prefix}(${SCOPE}): ${DESC}"
    else
        final_msg="${prefix}: ${DESC}"
    fi

    echo -e "\n${CYAN}Crafted Commit Message:${NC} ${BOLD}$final_msg${NC}"
    read -rp "Execute commit now? (y/N): " DO_COMMIT
    if [[ "$DO_COMMIT" =~ ^[Yy]$ ]]; then
        if [ "$GW_DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN] Would run: git add . && git commit -m \"$final_msg\"${NC}"
        else
            git add .
            git commit -m "$final_msg"
            echo -e "${GREEN}[✔] Conventional commit created!${NC}"
        fi
    fi
    pause
}

# --- Module 6: History & Diff Inspector ---
history_inspector() {
    show_header
    echo -e "${YELLOW}${BOLD}📊 VISUAL COMMIT HISTORY & DIFF INSPECTOR${NC}\n"
    echo -e "  ${GREEN}[1]${NC} View Visual Commit Graph Tree"
    echo -e "  ${GREEN}[2]${NC} View Working Directory Changes (${BOLD}git diff${NC})"
    echo -e "  ${GREEN}[3]${NC} View Last Commit Detailed Summary"
    read -rp "Select choice [1-3]: " H_CHOICE

    case $H_CHOICE in
        1)
            show_header
            git log --graph --oneline --decorate --all -n 20 | $(get_pager)
            pause
            ;;
        2)
            show_header
            git diff | $(get_pager)
            pause
            ;;
        3)
            show_header
            git show HEAD | $(get_pager)
            pause
            ;;
        *) echo "Cancelled."; pause ;;
    esac
}

# --- Module 7: Settings & Toggles Suite ---
settings_suite() {
    show_header
    echo -e "${YELLOW}${BOLD}⚙️ GIT-WIZARD SETTINGS & TOGGLES SUITE${NC}\n"
    echo -e "  ${GREEN}[1]${NC} Toggle Mode (${CYAN}Beginner${NC} vs ${CYAN}Enterprise${NC}) [Current: $GW_MODE]"
    echo -e "  ${GREEN}[2]${NC} Toggle Dry-Run Mode [Current: $GW_DRY_RUN]"
    echo -e "  ${GREEN}[3]${NC} Toggle Live Background Sync Watcher [Current: $GW_WATCHER]"
    echo -e "  ${GREEN}[4]${NC} Back to Main Menu"
    read -rp "Select choice [1-4]: " S_CHOICE

    case $S_CHOICE in
        1)
            if [ "$GW_MODE" = "Enterprise" ]; then GW_MODE="Beginner"; else GW_MODE="Enterprise"; fi
            ;;
        2)
            if [ "$GW_DRY_RUN" = "true" ]; then GW_DRY_RUN=false; else GW_DRY_RUN=true; fi
            ;;
        3)
            if [ "$GW_WATCHER" = "true" ]; then GW_WATCHER=false; else GW_WATCHER=true; fi
            ;;
        4) return ;;
    esac
    save_state
    echo -e "${GREEN}[✔] Settings updated successfully!${NC}"
    sleep 1
}

# --- Main Master Loop ---
while true; do
    check_git_repo
    show_header
    echo -e "Main Capabilities Suite:\n"
    echo -e "  ${GREEN}[1]${NC} 🔄 Linear Solo Mode ${CYAN}(Stage, Commit & Push in 1-Click)${NC}"
    echo -e "  ${GREEN}[2]${NC} 🌿 Enterprise Team Mode ${CYAN}(Create Feature/Bugfix Branch & Push)${NC}"
    echo -e "  ${GREEN}[3]${NC} ⚡ Safe Upstream Sync ${CYAN}(Stash-Protected Pull & Rebase)${NC}"
    echo -e "  ${GREEN}[4]${NC} 🔀 Admin Merge & Release Center ${CYAN}(PR Review & Production Merge)${NC}"
    echo -e "  ${GREEN}[5]${NC} 📝 Conventional Commit Assistant ${CYAN}(Enterprise Formatting)${NC}"
    echo -e "  ${GREEN}[6]${NC} 📊 Visual History & Diff Inspector ${CYAN}(Graph Tree & Delta Pager)${NC}"
    echo -e "  ${GREEN}[7]${NC} ⚙️ Settings, Toggles & Dry-Run ${CYAN}([M] Mode / [D] Dry-Run / Watcher)${NC}"
    echo -e "  ${YELLOW}${BOLD}[8] ⚡ Enable Universal Global CLI (Install 'git-wizard' & Managed Block)${NC}"
    echo -e "  ${GREEN}[9]${NC} Exit"
    echo -e "\n===================================================================="
    read -rp "Enter choice [1-9]: " MAIN_CHOICE

    case $MAIN_CHOICE in
        1) linear_solo_mode ;;
        2) enterprise_team_mode ;;
        3) safe_upstream_sync ;;
        4) admin_merge_center ;;
        5) commit_assistant ;;
        6) history_inspector ;;
        7) settings_suite ;;
        8) enable_global_cli ;;
        9) echo -e "\n${GREEN}Make your repository a masterpiece! Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
    esac
done