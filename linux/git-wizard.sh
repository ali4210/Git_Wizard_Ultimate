#!/usr/bin/env bash
# ==============================================================================
# TOOL NAME:    git-wizard.sh (V1.1 Enhanced Release)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Interactive CLI Suite for Git/GitHub Onboarding & Workflows.
# COMPATIBILITY: Debian, Ubuntu, Kali Linux, RHEL, CentOS, Fedora, Arch
# ==============================================================================

set -e

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_header() {
    clear
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    IMAGE_PATH="${SCRIPT_DIR}/assets/octocat.png"

    # Render high-res PNG via chafa if available
    if command -v chafa &>/dev/null && [[ -f "$IMAGE_PATH" ]]; then
        chafa --size=35x15 "$IMAGE_PATH"
        echo ""
    else
        # Fallback ASCII Logo (Custom High-Density Block Art)
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

# --- Clean URL Helper ---
clean_remote_url() {
    local input_url="$1"
    # Strip leading 'git remote add/set-url origin' if user pasted entire command
    input_url=$(echo "$input_url" | sed -E 's/^git remote (add|set-url) origin //I' | xargs)
    echo "$input_url"
}

# --- Module 1: Identity & SSH Manager ---
manage_identity() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}[+] Module 1: Identity, SSH & Remote URL Manager${NC}\n"
        echo -e "  ${GREEN}[1]${NC} Check / Set Global Git User & Email"
        echo -e "  ${GREEN}[2]${NC} Generate New SSH Key (ED25519) & Show Public Key"
        echo -e "  ${GREEN}[3]${NC} Test SSH Connection to GitHub"
        echo -e "  ${GREEN}[4]${NC} ${BOLD}Inspect & Manage Remote Repository URLs${NC} ${CYAN}(View, Change, Switch HTTPS/SSH)${NC}"
        echo -e "  ${GREEN}[5]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -p "Select choice [1-5]: " ID_CHOICE

        case $ID_CHOICE in
            1)
                echo -e "\n${CYAN}Current Configuration:${NC}"
                echo "  Name:  $(git config --global user.name || echo 'Not set')"
                echo "  Email: $(git config --global user.email || echo 'Not set')"
                echo ""
                read -p "Enter new global user.name (press ENTER to skip): " NEW_NAME
                read -p "Enter new global user.email (press ENTER to skip): " NEW_EMAIL

                if [[ -n "$NEW_NAME" ]]; then
                    git config --global user.name "$NEW_NAME"
                    echo -e "${GREEN}[✔] user.name updated to: $NEW_NAME${NC}"
                fi
                if [[ -n "$NEW_EMAIL" ]]; then
                    git config --global user.email "$NEW_EMAIL"
                    echo -e "${GREEN}[✔] user.email updated to: $NEW_EMAIL${NC}"
                fi
                pause
                ;;
            2)
                if [[ -f ~/.ssh/id_ed25519 ]]; then
                    echo -e "\n${YELLOW}[!] An ED25519 SSH key already exists at ~/.ssh/id_ed25519${NC}"
                else
                    echo -e "\n${GREEN}--> Generating ED25519 SSH Key...${NC}"
                    EMAIL=$(git config --global user.email || echo "user@github.com")
                    ssh-keygen -t ed25519 -C "$EMAIL" -f ~/.ssh/id_ed25519 -N ""
                    echo -e "${GREEN}[✔] SSH Key created!${NC}"
                fi
                echo -e "\n${CYAN}Your Public Key (Add this to GitHub -> Settings -> SSH Keys):${NC}"
                echo -e "${YELLOW}--------------------------------------------------------------------${NC}"
                cat ~/.ssh/id_ed25519.pub
                echo -e "${YELLOW}--------------------------------------------------------------------${NC}"
                pause
                ;;
            3)
                echo -e "\n${GREEN}--> Testing SSH connection to GitHub...${NC}"
                ssh -T git@github.com || true
                echo -e "\n${GREEN}[i] Note: 'does not provide shell access' is standard and indicates successful authentication!${NC}"
                pause
                ;;
            4)
                if ! git rev-parse --is-inside-work-tree &>/dev/null; then
                    echo -e "\n${RED}[!] Not inside a Git repository! Run Option 1 in Module 2 first.${NC}"
                    pause
                    continue
                fi

                while true; do
                    show_header
                    echo -e "${YELLOW}${BOLD}📌 REMOTE REPOSITORY URL MANAGER${NC}\n"
                    echo -e "${CYAN}--- Current Configured Remotes (git remote -v) ---${NC}"
                    GIT_PAGER=cat git remote -v 2>/dev/null || echo "No remotes set."
                    echo -e "-----------------------------------------------------\n"
                    echo -e "  ${GREEN}[1]${NC} Change / Set New Remote URL (Overwrite Existing)"
                    echo -e "  ${GREEN}[2]${NC} Toggle Protocol (Switch between HTTPS and SSH)"
                    echo -e "  ${GREEN}[3]${NC} Back to Module 1 Menu"
                    read -p "Select choice [1-3]: " REMOTE_CHOICE

                    case $REMOTE_CHOICE in
                        1)
                            echo ""
                            read -p "Enter fresh GitHub Remote URL (HTTPS or SSH): " RAW_URL
                            NEW_URL=$(clean_remote_url "$RAW_URL")
                            if [[ -n "$NEW_URL" ]]; then
                                git remote remove origin 2>/dev/null || true
                                git remote add origin "$NEW_URL"
                                echo -e "${GREEN}[✔] Remote 'origin' updated to: $NEW_URL${NC}"
                            else
                                echo -e "${RED}[!] URL cannot be empty!${NC}"
                            fi
                            pause
                            ;;
                        2)
                            CURRENT_URL=$(git remote get-url origin 2>/dev/null || echo "")
                            CURRENT_URL=$(clean_remote_url "$CURRENT_URL")

                            if [[ -z "$CURRENT_URL" ]]; then
                                echo -e "\n${RED}[!] No 'origin' remote set yet. Use Option [1] to set one first.${NC}"
                                pause
                                continue
                            fi

                            git remote set-url origin "$CURRENT_URL" 2>/dev/null || true

                            if [[ "$CURRENT_URL" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
                                USER_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
                                CONVERTED_URL="git@github.com:${USER_REPO}.git"
                                git remote set-url origin "$CONVERTED_URL"
                                echo -e "${GREEN}[✔] Switched from HTTPS to SSH: $CONVERTED_URL${NC}"
                            elif [[ "$CURRENT_URL" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)?$ ]]; then
                                USER_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
                                CONVERTED_URL="https://github.com/${USER_REPO}.git"
                                git remote set-url origin "$CONVERTED_URL"
                                echo -e "${GREEN}[✔] Switched from SSH to HTTPS: $CONVERTED_URL${NC}"
                            else
                                echo -e "${RED}[!] Unrecognized URL format. Use Option [1] to re-enter a fresh URL.${NC}"
                            fi
                            pause
                            ;;
                        3) break ;;
                        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
                    esac
                done
                ;;
            5) break ;;
            *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
        esac
    done
}

# --- Module 2: Repository Setup, Status & Reset Engine ---
manage_repo() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}[+] Module 2: Repository Setup, Status & Reset Engine${NC}"
        echo -e "${CYAN}💡 Hint: Use Module 1 first if you need to configure your SSH keys or global user info.${NC}\n"
        echo -e "  ${GREEN}[1]${NC} 1-Click Complete Repo Setup (Init, Main Branch, Commit, Remote, Push)"
        echo -e "  ${GREEN}[2]${NC} Quick Push (Add All -> Commit -> Push)"
        echo -e "  ${GREEN}[3]${NC} ${BOLD}Inspect Working Directory Status${NC} ${CYAN}(git status)${NC}"
        echo -e "  ${GREEN}[4]${NC} ${BOLD}Interactive Git Reset & Undo Utility${NC} ${CYAN}(Unstage, Revert, Rollback)${NC}"
        echo -e "  ${GREEN}[5]${NC} ${BOLD}Smart Conflict Push Resolver${NC} ${RED}(Fixes Rejected Pushes!)${NC}"
        echo -e "  ${GREEN}[6]${NC} Generate Tailored .gitignore File"
        echo -e "  ${GREEN}[7]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -p "Select choice [1-7]: " REPO_CHOICE

        case $REPO_CHOICE in
            1)
                echo -e "\n${GREEN}--> Initializing Git repository...${NC}"
                git init
                git branch -M main
                git add .
                
                if [[ -z "$(git status --porcelain)" ]]; then
                    echo -e "${YELLOW}[i] Working tree clean (nothing new to commit).${NC}"
                else
                    read -p "Enter initial commit message [default: Initial commit]: " MSG
                    MSG=${MSG:-"Initial commit"}
                    git commit -m "$MSG"
                fi

                # --- Guideline & Remote Detection Banner ---
                EXISTING_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
                echo -e "\n${CYAN}====================================================================${NC}"
                echo -e "${CYAN}${BOLD}📌 GITHUB REMOTE URL SETUP GUIDELINE${NC}"
                echo -e "${CYAN}====================================================================${NC}"
                
                if [[ -n "$EXISTING_REMOTE" ]]; then
                    echo -e "${GREEN}[✔] Existing Remote Detected:${NC} $EXISTING_REMOTE"
                    echo -e "${YELLOW}--> Press [ENTER] to keep this remote and push immediately!${NC}"
                    echo -e "--> Or paste a NEW URL below to overwrite it.\n"
                else
                    echo -e "Enter your GitHub repository URL."
                    echo -e "Example formats:"
                    echo -e "  • ${GREEN}SSH (Recommended):${NC}   git@github.com:username/repository.git"
                    echo -e "  • ${GREEN}HTTPS:${NC}              https://github.com/username/repository.git\n"
                fi

                read -p "Enter Remote URL (or press ENTER to keep current): " RAW_URL
                REMOTE_URL=$(clean_remote_url "$RAW_URL")

                if [[ -n "$REMOTE_URL" ]]; then
                    git remote remove origin 2>/dev/null || true
                    git remote add origin "$REMOTE_URL"
                    echo -e "${GREEN}[✔] Remote attached: $REMOTE_URL${NC}"
                elif [[ -n "$EXISTING_REMOTE" ]]; then
                    REMOTE_URL="$EXISTING_REMOTE"
                    echo -e "${GREEN}[✔] Using existing remote: $REMOTE_URL${NC}"
                fi

                if [[ -n "$REMOTE_URL" ]]; then
                    echo -e "${GREEN}--> Pushing to origin main...${NC}"
                    git push -u origin main || echo -e "${YELLOW}[!] Push rejected or refused. Use Option [5] (Smart Conflict Push Resolver) to sync!${NC}"
                else
                    echo -e "${YELLOW}[!] No remote URL configured. Add one using Module 1 Option [4] or rerun this option.${NC}"
                fi
                pause
                ;;
            2)
                git add .
                if [[ -z "$(git status --porcelain)" ]]; then
                    echo -e "${YELLOW}[i] Working tree clean (no new changes to commit).${NC}\n"
                    show_uptodate_celebration
                else
                    read -p "Enter commit message: " MSG
                    if [[ -z "$MSG" ]]; then
                        echo -e "${RED}Commit message cannot be empty!${NC}"
                        pause
                        continue
                    fi
                    git commit -m "$MSG"
                    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
                    git push origin "$BRANCH" || echo -e "${YELLOW}[!] Push rejected. Use Option [5] to resolve conflicts!${NC}"
                fi
                pause
                ;;
            3)
                show_header
                echo -e "${YELLOW}${BOLD}📌 WORKING DIRECTORY & STAGING STATUS${NC}\n"
                if ! git rev-parse --is-inside-work-tree &>/dev/null; then
                    echo -e "${RED}[!] Not inside a Git repository! Run Option [1] first.${NC}"
                else
                    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
                    echo -e "Current Active Branch: ${CYAN}$BRANCH${NC}\n"
                    
                    STATUS_OUT=$(git status --porcelain)
                    if [[ -z "$STATUS_OUT" ]]; then
                        show_uptodate_celebration
                    else
                        GIT_PAGER=cat git status
                    fi
                fi
                pause
                ;;
            4)
                while true; do
                    show_header
                    echo -e "${YELLOW}${BOLD}📌 INTERACTIVE GIT RESET & UNDO UTILITY${NC}\n"
                    echo -e "  ${GREEN}[1]${NC} Unstage All Files ${CYAN}(Keep modified changes, remove from staging)${NC}"
                    echo -e "  ${GREEN}[2]${NC} Discard All Uncommitted Local Changes ${RED}(Revert files to last commit)${NC}"
                    echo -e "  ${GREEN}[3]${NC} Soft Rollback Last Commit ${CYAN}(Undo commit, KEEP changes staged)${NC}"
                    echo -e "  ${RED}[4]${NC} Hard Rollback Last Commit ${RED}(DESTROY last commit & all changes!)${NC}"
                    echo -e "  ${GREEN}[5]${NC} Back to Module 2 Menu"
                    echo -e "\n===================================================================="
                    read -p "Select choice [1-5]: " RESET_CHOICE

                    case $RESET_CHOICE in
                        1)
                            echo -e "\n${GREEN}--> Unstaging all files...${NC}"
                            git reset HEAD
                            echo -e "${GREEN}[✔] All staged files reverted to unstaged!${NC}"
                            pause
                            ;;
                        2)
                            read -p "ARE YOU SURE? This will DISCARD all uncommitted work! (y/N): " CONF
                            if [[ "$CONF" =~ ^[Yy]$ ]]; then
                                git checkout -- . 2>/dev/null || true
                                git clean -fd 2>/dev/null || true
                                echo -e "${GREEN}[✔] Local working tree wiped clean to last commit state!${NC}"
                            fi
                            pause
                            ;;
                        3)
                            echo -e "\n${GREEN}--> Soft rolling back last commit...${NC}"
                            git reset --soft HEAD~1
                            echo -e "${GREEN}[✔] Commit undone! Your files remain intact in the staging area.${NC}"
                            pause
                            ;;
                        4)
                            read -p "CRITICAL WARNING: This will PERMANENTLY ERASE your last commit and work! (y/N): " CONF
                            if [[ "$CONF" =~ ^[Yy]$ ]]; then
                                git reset --hard HEAD~1
                                echo -e "${GREEN}[✔] Hard reset complete. Last commit and work removed.${NC}"
                            fi
                            pause
                            ;;
                        5) break ;;
                        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
                    esac
                done
                ;;
            5)
                show_header
                echo -e "${YELLOW}${BOLD}📌 SMART CONFLICT PUSH RESOLVER Engine${NC}\n"
                BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
                echo -e "Current Branch: ${CYAN}$BRANCH${NC}"
                echo -e "Choose resolution strategy for remote refusal:\n"
                echo -e "  ${GREEN}[1]${NC} Safe Pull & Rebase ${CYAN}(Recommended: Appends your commits cleanly)${NC}"
                echo -e "  ${GREEN}[2]${NC} Safe Pull & Merge ${CYAN}(Allows unrelated histories merge)${NC}"
                echo -e "  ${RED}[3]${NC} Force Push ${RED}(Overwrites remote with your local code)${NC}"
                echo -e "  ${GREEN}[4]${NC} Cancel"
                read -p "Select strategy [1-4]: " STRAT

                case $STRAT in
                    1)
                        echo -e "\n${GREEN}--> Pulling remote changes with Rebase...${NC}"
                        git pull origin "$BRANCH" --rebase
                        git push origin "$BRANCH"
                        echo -e "${GREEN}[✔] Successfully synced and pushed!${NC}"
                        ;;
                    2)
                        echo -e "\n${GREEN}--> Pulling remote changes with Merge...${NC}"
                        git pull origin "$BRANCH" --rebase=false --allow-unrelated-histories
                        git push origin "$BRANCH"
                        echo -e "${GREEN}[✔] Successfully merged and pushed!${NC}"
                        ;;
                    3)
                        echo -e "\n${RED}--> Force pushing to remote...${NC}"
                        git push origin "$BRANCH" --force
                        echo -e "${GREEN}[✔] Force push complete!${NC}"
                        ;;
                    *) echo "Cancelled." ;;
                esac
                pause
                ;;
            6)
                echo -e "\nSelect template type for .gitignore:"
                echo -e "  [1] Python / Django / Flask"
                echo -e "  [2] Node.js / React / Next.js"
                echo -e "  [3] Go / Docker / Linux"
                read -p "Choice [1-3]: " GI_CHOICE
                case $GI_CHOICE in
                    1)
                        cat <<EOF > .gitignore
__pycache__/
*.py[cod]
*$py.class
venv/
.env
.pytest_cache/
EOF
                        echo -e "${GREEN}[✔] Python .gitignore created!${NC}"
                        ;;
                    2)
                        cat <<EOF > .gitignore
node_modules/
build/
dist/
.env
.env.local
npm-debug.log*
EOF
                        echo -e "${GREEN}[✔] Node.js .gitignore created!${NC}"
                        ;;
                    3)
                        cat <<EOF > .gitignore
*.exe
*.o
*.so
bin/
.env
*.tar.gz
EOF
                        echo -e "${GREEN}[✔] Go/Linux .gitignore created!${NC}"
                        ;;
                esac
                pause
                ;;
            7) break ;;
            *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
        esac
    done
}

# --- Module 3: Advanced Branch Manager ---
select_branch_interactive() {
    local prompt="$1"
    local branch_list=$(GIT_PAGER=cat git branch --format="%(refname:short)")
    
    if [[ -z "$branch_list" ]]; then
        echo -e "${RED}[!] No local branches found.${NC}"
        return 1
    fi

    local branches=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && branches+=("$line")
    done <<< "$branch_list"

    local selected=0
    local key=""

    tput civis 2>/dev/null || true

    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}$prompt${NC}\n"
        echo -e "${CYAN}Use UP/DOWN arrow keys to navigate, press [ENTER] to select:${NC}\n"

        for i in "${!branches[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}${BOLD}  ➔  ${branches[$i]} (Selected)${NC}"
            else
                echo -e "     ${branches[$i]}"
            fi
        done
        echo -e "\n===================================================================="

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            if [[ $key == "[A" ]]; then
                ((selected--))
                if [[ $selected -lt 0 ]]; then selected=$((${#branches[@]} - 1)); fi
            elif [[ $key == "[B" ]]; then
                ((selected++))
                if [[ $selected -ge ${#branches[@]} ]]; then selected=0; fi
            fi
        elif [[ $key == "" ]]; then
            tput cnorm 2>/dev/null || true
            SELECTED_BRANCH="${branches[$selected]}"
            return 0
        fi
    done
}

manage_branches() {
    while true; do
        show_header
        echo -e "${YELLOW}${BOLD}[+] Module 3: Advanced Branch & Remote Manager${NC}\n"
        echo -e "  ${GREEN}[1]${NC} List All Branches (Local & Remote)"
        echo -e "  ${GREEN}[2]${NC} Create New Branch & Publish to GitHub"
        echo -e "  ${GREEN}[3]${NC} Switch Branch ${CYAN}(Interactive Arrow-Key Selection)${NC}"
        echo -e "  ${GREEN}[4]${NC} Delete Branch ${RED}(Interactive Arrow-Key Selection & Purge)${NC}"
        echo -e "  ${GREEN}[5]${NC} Back to Main Menu"
        echo -e "\n===================================================================="
        read -p "Select choice [1-5]: " B_CHOICE

        case $B_CHOICE in
            1)
                show_header
                echo -e "${CYAN}${BOLD}--- Local Branches ---${NC}"
                GIT_PAGER=cat git branch -vv
                echo -e "\n${CYAN}${BOLD}--- Remote Branches ---${NC}"
                GIT_PAGER=cat git branch -r
                pause
                ;;
            2)
                read -p "Enter new branch name: " NEW_B
                if [[ -n "$NEW_B" ]]; then
                    git checkout -b "$NEW_B"
                    echo -e "${GREEN}--> Publishing '$NEW_B' to GitHub...${NC}"
                    git push -u origin "$NEW_B"
                    echo -e "${GREEN}[✔] Branch created and tracked on GitHub!${NC}"
                fi
                pause
                ;;
            3)
                if select_branch_interactive "📌 SELECT BRANCH TO SWITCH"; then
                    echo -e "\n${GREEN}--> Switching to branch '$SELECTED_BRANCH'...${NC}"
                    git checkout "$SELECTED_BRANCH"
                fi
                pause
                ;;
            4)
                if select_branch_interactive "📌 SELECT BRANCH TO PURGE (LOCAL & REMOTE)"; then
                    CURRENT_B=$(git rev-parse --abbrev-ref HEAD)
                    if [[ "$SELECTED_BRANCH" == "$CURRENT_B" ]]; then
                        echo -e "\n${RED}[!] Cannot delete active branch '$CURRENT_B'. Switch to another branch first!${NC}"
                    else
                        echo ""
                        read -p "Are you SURE you want to delete '$SELECTED_BRANCH' everywhere? (y/N): " CONF
                        if [[ "$CONF" =~ ^[Yy]$ ]]; then
                            git branch -D "$SELECTED_BRANCH" 2>/dev/null || true
                            git push origin --delete "$SELECTED_BRANCH" 2>/dev/null || true
                            echo -e "${GREEN}[✔] Branch '$SELECTED_BRANCH' purged successfully!${NC}"
                        fi
                    fi
                fi
                pause
                ;;
            5) break ;;
            *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
        esac
    done
}

# --- Module 4: Conventional Commit Assistant ---
commit_assistant() {
    show_header
    echo -e "${YELLOW}${BOLD}[+] Module 4: Conventional Commit Crafting Assistant${NC}\n"
    echo -e "Select commit classification:"
    echo -e "  ${GREEN}[1] feat:${NC}     A new feature for users"
    echo -e "  ${GREEN}[2] fix:${NC}      A bug fix"
    echo -e "  ${GREEN}[3] docs:${NC}     Documentation changes only"
    echo -e "  ${GREEN}[4] refactor:${NC} Code restructuring without logic change"
    echo -e "  ${GREEN}[5] chore:${NC}    Build process or dependency updates"
    read -p "Select choice [1-5]: " C_TYPE

    PREFIX=""
    case $C_TYPE in
        1) PREFIX="feat" ;;
        2) PREFIX="fix" ;;
        3) PREFIX="docs" ;;
        4) PREFIX="refactor" ;;
        5) PREFIX="chore" ;;
        *) echo "Cancelled."; return ;;
    esac

    read -p "Enter short scope (optional, e.g. auth, api): " SCOPE
    read -p "Enter clear commit description: " DESC

    if [[ -z "$DESC" ]]; then
        echo -e "${RED}Description required!${NC}"
        pause
        return
    fi

    if [[ -n "$SCOPE" ]]; then
        FINAL_MSG="${PREFIX}(${SCOPE}): ${DESC}"
    else
        FINAL_MSG="${PREFIX}: ${DESC}"
    fi

    echo -e "\n${CYAN}Crafted Commit Message:${NC} ${BOLD}$FINAL_MSG${NC}"
    read -p "Execute commit now? (y/N): " DO_COMMIT
    if [[ "$DO_COMMIT" =~ ^[Yy]$ ]]; then
        git add .
        git commit -m "$FINAL_MSG"
        echo -e "${GREEN}[✔] Conventional commit created!${NC}"
    fi
    pause
}

# --- Main Master Loop ---
while true; do
    show_header
    echo -e "Main Capabilities Suite:\n"
    echo -e "  ${GREEN}[1]${NC} Identity & SSH Manager ${CYAN}(Config, Keys, Connections, Remotes)${NC}"
    echo -e "  ${GREEN}[2]${NC} Repository & Smart Push Engine ${CYAN}(Init, Status, Reset, Conflict Resolver)${NC}"
    echo -e "  ${GREEN}[3]${NC} Advanced Branch Manager ${CYAN}(Local/Remote Sync & Dual Delete)${NC}"
    echo -e "  ${GREEN}[4]${NC} Conventional Commit Assistant ${CYAN}(Professional Formatting)${NC}"
    echo -e "  ${GREEN}[5]${NC} Exit"
    echo -e "\n===================================================================="
    read -p "Enter choice [1-5]: " MAIN_CHOICE

    case $MAIN_CHOICE in
        1) manage_identity ;;
        2) manage_repo ;;
        3) manage_branches ;;
        4) commit_assistant ;;
        5) echo -e "\n${GREEN}Keep building amazing open-source software! Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
    esac
done