# ==============================================================================
# ENGINE NAME: repo-engine.ps1 (PowerShell 5.1 Clean Edition - V2.1 Gold Standard)
# NEW IN V2.0: Force Sync with Origin (nuclear reset recovery), destructive
#              operations routed through Invoke-GitWizard/New-SafetyBackup/
#              Confirm-DestructiveAction from git-wizard.ps1 for Dry-Run and
#              automatic safety-backup support.
# NEW IN V2.1: Back=0 convention.
# ==============================================================================

function Manage-Repo {
    while ($true) {
        Show-Header
        Write-Host "  [+] Module 2: Repository Setup, Status and Reset Engine`n" -ForegroundColor Yellow
        Write-Host "  [1] 1-Click Complete Repo Setup (Init, Main Branch, Commit, Remote, Push)" -ForegroundColor Green
        Write-Host "  [2] 1-Click Complete Repo Destroy" -ForegroundColor Red
        Write-Host "  [3] Quick Push (Add All -> Commit -> Push)" -ForegroundColor Green
        Write-Host "  [4] Inspect Working Directory Status (git status)" -ForegroundColor Green
        Write-Host "  [5] Interactive Git Reset and Undo Utility" -ForegroundColor Green
        Write-Host "  [6] Smart Conflict Push Resolver" -ForegroundColor Green
        Write-Host "  [7] Generate Tailored .gitignore File" -ForegroundColor Green
        Write-Host "  [8] Repository Pre-Commit Hook" -ForegroundColor Green
        Write-Host "  [0] Back to Main Menu" -ForegroundColor Green
        Write-Host "`n====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [0-8]"

        switch ($choice) {
            "1" { Invoke-OneClickRepoSetup }
            "2" { Invoke-OneClickRepoDestroy }
            "3" {
                Invoke-GitWizard add . | Out-Null
                $status = git status --porcelain
                if (-not $status) {
                    Write-Host "[i] Working tree clean." -ForegroundColor Yellow
                    Show-UpToDateCelebration
                } else {
                    $msg = Read-Host "Enter commit message"
                    if (-not $msg) {
                        Write-Host "[!] Commit message cannot be empty!" -ForegroundColor Red
                        Pause-Console
                        continue
                    }
                    if (Invoke-CommitWithHookRetry -Message "$msg") {
                        $branch = git rev-parse --abbrev-ref HEAD 2>$null
                        if (-not $branch) { $branch = "main" }
                        if (-not (Invoke-GitWizard push origin "$branch")) {
                            Write-Host "[!] Push rejected. Use Option [6] to resolve." -ForegroundColor Yellow
                        }
                    }
                }
                Pause-Console
            }
            "4" {
                Show-Header
                Write-Host "WORKING DIRECTORY AND STAGING STATUS`n" -ForegroundColor Yellow
                $branch = git rev-parse --abbrev-ref HEAD 2>$null
                Write-Host "Current Active Branch: $branch`n" -ForegroundColor Cyan
                $status = git status --porcelain
                if (-not $status) {
                    Show-UpToDateCelebration
                } else {
                    git status
                }
                Pause-Console
            }
            "5" {
                while ($true) {
                    Show-Header
                    Write-Host "INTERACTIVE GIT RESET AND UNDO UTILITY`n" -ForegroundColor Yellow
                    Write-Host "  [1] Unstage All Files" -ForegroundColor Green
                    Write-Host "  [2] Discard All Uncommitted Local Changes" -ForegroundColor Red
                    Write-Host "  [3] Soft Rollback Last Commit" -ForegroundColor Green
                    Write-Host "  [4] Hard Rollback Last Commit (DESTROY last commit)" -ForegroundColor Red
                    Write-Host "  [5] Force Sync with Origin (Nuclear reset - matches GitHub exactly!)" -ForegroundColor Red
                    Write-Host "      Use this when your local branch is badly tangled/diverged and you just want it to match origin/main exactly." -ForegroundColor Cyan
                    Write-Host "  [0] Back to Module 2 Menu" -ForegroundColor Green

                    $resetChoice = Read-Host "Select choice [0-5]"
                    if ($resetChoice -eq "1") {
                        Invoke-GitWizard reset HEAD | Out-Null
                        Write-Host "[+] All staged files reverted to unstaged!" -ForegroundColor Green
                        Pause-Console
                    } elseif ($resetChoice -eq "2") {
                        if (Confirm-DestructiveAction "Discard all uncommitted local changes") {
                            New-SafetyBackup "pre-discard"
                            Invoke-GitWizard checkout -- . | Out-Null
                            Invoke-GitWizard clean -fd | Out-Null
                            Write-Host "[+] Local working tree wiped clean!" -ForegroundColor Green
                        }
                        Pause-Console
                    } elseif ($resetChoice -eq "3") {
                        Invoke-GitWizard reset --soft HEAD~1 | Out-Null
                        Write-Host "[+] Commit undone! Files remain staged." -ForegroundColor Green
                        Pause-Console
                    } elseif ($resetChoice -eq "4") {
                        if (Confirm-DestructiveAction "Hard rollback last commit - PERMANENT data loss risk") {
                            New-SafetyBackup "pre-hard-reset"
                            Invoke-GitWizard reset --hard HEAD~1 | Out-Null
                            Write-Host "[+] Hard reset complete." -ForegroundColor Green
                        }
                        Pause-Console
                    } elseif ($resetChoice -eq "5") {
                        Invoke-ForceSyncWithOrigin
                    } elseif ($resetChoice -eq "0") { return }
                }
            }
            "6" {
                Show-Header
                Write-Host "SMART CONFLICT PUSH RESOLVER`n" -ForegroundColor Yellow
                $branch = git rev-parse --abbrev-ref HEAD 2>$null
                Write-Host "Current Branch: $branch" -ForegroundColor Cyan
                Write-Host "  [1] Safe Pull and Rebase" -ForegroundColor Green
                Write-Host "  [2] Safe Pull and Merge" -ForegroundColor Green
                Write-Host "  [3] Force Push (Overwrites remote!)" -ForegroundColor Red
                Write-Host "  [4] Force Pull (Overwrites local!)" -ForegroundColor Red
                Write-Host "  [0] Cancel" -ForegroundColor Green

                $strat = Read-Host "Select strategy [0-4]"
                if ($strat -eq "1") {
                    if (Invoke-GitWizard pull origin "$branch" --rebase) {
                        if (Invoke-GitWizard push origin "$branch") {
                            Write-Host "[+] Synced and pushed!" -ForegroundColor Green
                        } else {
                            Write-Host "[!] Pull succeeded but push failed." -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "[!] Pull/rebase failed - resolve conflicts manually." -ForegroundColor Red
                    }
                } elseif ($strat -eq "2") {
                    if (Invoke-GitWizard pull origin "$branch" --rebase=$false --allow-unrelated-histories) {
                        if (Invoke-GitWizard push origin "$branch") {
                            Write-Host "[+] Merged and pushed!" -ForegroundColor Green
                        } else {
                            Write-Host "[!] Pull succeeded but push failed." -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "[!] Pull/merge failed - resolve conflicts manually." -ForegroundColor Red
                    }
                } elseif ($strat -eq "3") {
                    if (Confirm-DestructiveAction "Force push - can overwrite remote history") {
                        New-SafetyBackup "pre-force-push"
                        if (Invoke-GitWizard push origin "$branch" --force) {
                            Write-Host "[+] Force push complete!" -ForegroundColor Green
                        } else {
                            Write-Host "[!] Force push failed. Check your remote/connection." -ForegroundColor Red
                        }
                    }
                } elseif ($strat -eq "4") {
                    if (Confirm-DestructiveAction "Force pull - overwrites local branch '$branch' with origin/$branch") {
                        New-SafetyBackup "pre-force-pull"
                        if (Invoke-GitWizard fetch origin) {
                            Invoke-GitWizard reset --hard "origin/$branch" | Out-Null
                            Invoke-GitWizard clean -fd | Out-Null
                            Write-Host "[+] Local branch now matches origin/$branch." -ForegroundColor Green
                        } else {
                            Write-Host "[!] Fetch failed. Aborting - nothing was reset." -ForegroundColor Red
                        }
                    }
                }
                Pause-Console
            }
            "7" {
                Write-Host "Select template for .gitignore:"
                Write-Host "  [1] Python / Django / Flask"
                Write-Host "  [2] Node.js / React / Next.js"
                Write-Host "  [3] Go / Docker / Linux"
                $giChoice = Read-Host "Choice [1-3]"
                if ($giChoice -eq "1") {
                    Set-Content -Path .gitignore -Value "__pycache__/`n*.py[cod]`nvenv/`n.env"
                    Write-Host "[+] Python .gitignore created!" -ForegroundColor Green
                } elseif ($giChoice -eq "2") {
                    Set-Content -Path .gitignore -Value "node_modules/`nbuild/`ndist/`n.env"
                    Write-Host "[+] Node.js .gitignore created!" -ForegroundColor Green
                } elseif ($giChoice -eq "3") {
                    Set-Content -Path .gitignore -Value "*.exe`n*.o`nbin/`n.env"
                    Write-Host "[+] Go/Linux .gitignore created!" -ForegroundColor Green
                }
                if (Get-Command Write-WizardActionLog -ErrorAction SilentlyContinue) {
                    Write-WizardActionLog ".gitignore generated"
                }
                Pause-Console
            }
            "8" { Show-RepoPrecommitHookMenu }
            "0" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ==============================================================================
# REPOSITORY PRE-COMMIT HOOK — Enable / Disable (moved here from Tool Stack
# Manager). Install-PrecommitHooks itself still lives in toolstack-engine.ps1.
# ==============================================================================
function Disable-PrecommitHooks {
    Show-Header
    Write-Host "DISABLE PRE-COMMIT HOOKS`n" -ForegroundColor Yellow

    $isRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($isRepo -ne "true") {
        Write-Host "[!] Not inside a Git repository. cd into one first." -ForegroundColor Red
        Pause-Console
        return
    }

    $hookPath = Join-Path (Get-Location) ".git\hooks\pre-commit"
    if (Test-Path $hookPath) {
        Remove-Item -Path $hookPath -Force
        Write-Host "[+] Pre-commit hook disabled for this repo." -ForegroundColor Green
        Write-Host "    (.pre-commit-config.yaml is left untouched - re-enable anytime.)" -ForegroundColor Cyan
        if (Get-Command Write-WizardActionLog -ErrorAction SilentlyContinue) {
            Write-WizardActionLog "pre-commit hooks disabled for $(Get-Location)"
        }
    } else {
        Write-Host "[i] No active pre-commit hook found for this repo." -ForegroundColor Yellow
    }
    Pause-Console
}

function Show-RepoPrecommitHookMenu {
    while ($true) {
        Show-Header
        Write-Host "REPOSITORY PRE-COMMIT HOOK`n" -ForegroundColor Yellow
        Write-Host "  [1] Enable Pre-Commit Hook for This Repo" -ForegroundColor Green
        Write-Host "  [2] Disable Pre-Commit Hook for This Repo" -ForegroundColor Red
        Write-Host "  [0] Back" -ForegroundColor Green
        Write-Host "`n===================================================================="
        $c = Read-Host "Select choice [0-2]"
        switch ($c) {
            "1" {
                if (Get-Command Install-PrecommitHooks -ErrorAction SilentlyContinue) {
                    Install-PrecommitHooks
                } else {
                    Write-Host "[!] toolstack-engine.ps1 not loaded - Install-PrecommitHooks unavailable." -ForegroundColor Red
                    Pause-Console
                }
            }
            "2" { Disable-PrecommitHooks }
            "0" { return }
        }
    }
}
# ==============================================================================
# 1-CLICK COMPLETE REPO SETUP
# Creates the repo on the Git host itself (GitHub/GitLab) using the folder
# name by default, so the push always matches. Falls back to manual remote
# entry if the host CLI isn't available/authenticated.
# Relies on globals from git-wizard.ps1 (Invoke-GitWizard, Pause-Console,
# Show-Header) and vcs-engine.ps1 (Confirm-VcsReady, Vcs-CreateRepo,
# Vcs-GetRepoUrl, Vcs-MyUsername, $Global:VcsProvider, $Global:DryRun).
# ==============================================================================
function Invoke-OneClickRepoSetup {
    Show-Header
    Write-Host "1-CLICK COMPLETE REPO SETUP`n" -ForegroundColor Yellow

    $folderName = Split-Path -Leaf (Get-Location)
    Write-Host "Folder detected: $folderName" -ForegroundColor Cyan
    Write-Host "This repo will be created on your Git host using this exact name," -ForegroundColor Cyan
    Write-Host "so the push always matches.`n" -ForegroundColor Cyan

    if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
        Invoke-GitWizard init | Out-Null
        Invoke-GitWizard branch -M main | Out-Null
    }

    if (-not (Confirm-VcsReady)) {
        Write-Host "[i] Couldn't set up the Git host CLI. Falling back to manual remote entry." -ForegroundColor Yellow
        Invoke-GitWizard add . | Out-Null
        if (git status --porcelain) {
            $msg = Read-Host "Commit message [default: Initial commit]"
            if (-not $msg) { $msg = "Initial commit" }
            Invoke-CommitWithHookRetry -Message "$msg" | Out-Null
        }
        $rawUrl = Read-Host "Enter Remote URL (or ENTER to keep current)"
        $remoteUrl = Clean-RemoteUrl -url $rawUrl
        if ($remoteUrl) {
            git remote remove origin 2>$null
            git remote add origin "$remoteUrl"
        }
        if (-not (Invoke-GitWizard push -u origin main)) {
            Write-Host "[!] Push rejected. Use Option [6] to resolve." -ForegroundColor Yellow
        }
        Pause-Console
        return
    }

    $customName = Read-Host "Repo name [ENTER to use folder name '$folderName']"
    $repoName = if ($customName) { $customName } else { $folderName }
    Write-Host "  [1] Public  [2] Private"
    $visChoice = Read-Host "Visibility [1-2, default 1]"
    $vis = if ($visChoice -eq "2") { "private" } else { "public" }

    Write-Host "`n--> Creating '$repoName' ($vis) on $Global:VcsProvider..." -ForegroundColor Cyan
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would create $Global:VcsProvider repo: $repoName ($vis)" -ForegroundColor Yellow
    } else {
        Vcs-CreateRepo -name $repoName -visibility $vis
    }

    Invoke-GitWizard add . | Out-Null
    if (git status --porcelain) {
        $msg = Read-Host "Commit message [default: Initial commit]"
        if (-not $msg) { $msg = "Initial commit" }
        Invoke-CommitWithHookRetry -Message "$msg" | Out-Null
    } else {
        Write-Host "[i] Nothing to commit." -ForegroundColor Yellow
    }

    # =========================================================================
    # AUTO-DETECT REMOTE URL — two methods, then manual fallback as last resort
    # =========================================================================
    $sshUrl   = $null
    $httpsUrl = $null
    $detectedUser = $null

    # --- Method 1: Try the VCS abstraction functions (vcs-engine.ps1) ---
    $unameResult = Vcs-MyUsername
    if ($unameResult) {
        $detectedUser = $unameResult
        $fullName = "$unameResult/$repoName"
        $urlPair = Vcs-GetRepoUrl -repo $fullName
        if ($urlPair) {
            $sshUrl   = ($urlPair -split '\|')[0]
            $httpsUrl = ($urlPair -split '\|')[1]
        }
    }

        # --- Method 2: Direct API call if VCS functions returned nothing ---
    if (-not $sshUrl -and -not $httpsUrl) {
        if ($Global:VcsProvider -eq "github") {
            $directUser = & gh api user --jq '.login' 2>$null
            if ($directUser) {
                $detectedUser = $directUser
                $sshUrl   = "git@github.com:${directUser}/${repoName}.git"
                $httpsUrl = "https://github.com/${directUser}/${repoName}.git"
            }
        } elseif ($Global:VcsProvider -eq "gitlab") {
            $directUser = & glab api user --jq '.username' 2>$null
            if ($directUser) {
                $detectedUser = $directUser
                $sshUrl   = "git@gitlab.com:${directUser}/${repoName}.git"
                $httpsUrl = "https://gitlab.com/${directUser}/${repoName}.git"
            }
        }
    }
    # --- If either method worked, let user pick SSH vs HTTPS ---
    if ($sshUrl -or $httpsUrl) {
        Write-Host "`nWhich URL protocol would you like to push with?" -ForegroundColor Cyan
        Write-Host "  [1] SSH   ($sshUrl)" -ForegroundColor Green
        Write-Host "  [2] HTTPS ($httpsUrl)" -ForegroundColor Green
        $protoChoice = Read-Host "Choice [1-2, default 1]"
        $chosenUrl = if ($protoChoice -eq "2") { $httpsUrl } else { $sshUrl }
        git remote remove origin 2>$null
        git remote add origin "$chosenUrl"
        Write-Host "[+] Remote origin set to: $chosenUrl" -ForegroundColor Green
    }

    # --- Absolute last resort: manual paste (only fires if BOTH methods failed) ---
    if (-not (git remote get-url origin 2>$null)) {
        Write-Host ""
        $rawUrl = Read-Host "Couldn't auto-detect the new repo's URL. Paste it manually"
        $remoteUrl = Clean-RemoteUrl -url $rawUrl
        if ($remoteUrl) {
            git remote remove origin 2>$null
            git remote add origin "$remoteUrl"
        }
    }

    Invoke-GitWizard branch -M main | Out-Null
    if (Invoke-GitWizard push -u origin main) {
        Write-Host ""
        Write-Host "====================================================================" -ForegroundColor Green
        Write-Host "  [OK] 1-CLICK REPO SETUP COMPLETE!" -ForegroundColor Green
        Write-Host "====================================================================" -ForegroundColor Green
        $finalUrl = git remote get-url origin 2>$null
        if ($finalUrl) { Write-Host "  Remote : $finalUrl" -ForegroundColor Cyan }
        if ($detectedUser) {
            $browseUrl = "https://$($Global:VcsProvider).com/${detectedUser}/${repoName}"
            Write-Host "  Browse : $browseUrl" -ForegroundColor Cyan
        }
        Write-Host "====================================================================" -ForegroundColor Green
    } else {
        Write-Host "[!] Push rejected. Use Option [6] Smart Conflict Push Resolver." -ForegroundColor Yellow
    }
    Pause-Console
}
# ==============================================================================
# 1-CLICK COMPLETE REPO DESTROY
# Detects the remote repo from THIS folder's 'origin' (works from any folder
# that has a git-wizard-initialized repo, GitHub or GitLab, SSH or HTTPS),
# then deletes it on the host via Vcs-DeleteRepo. Mirrors the Linux
# one_click_repo_destroy function.
# ==============================================================================
function Get-OwnerRepoFromUrl {
    param([string]$Url)
    if (-not $Url) { return "" }
    if ($Url -match '^git@[^:]+:([^/]+)/(.+?)(\.git)?$') {
        return "$($Matches[1])/$($Matches[2])"
    }
    if ($Url -match '^https?://[^/]+/([^/]+)/(.+?)(\.git)?$') {
        return "$($Matches[1])/$($Matches[2])"
    }
    return ""
}
function Invoke-OneClickRepoDestroy {
    Show-Header
    Write-Host "1-CLICK COMPLETE REPO DESTROY`n" -ForegroundColor Red

    $IsRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($IsRepo -ne "true") {
        Write-Host "[!] '$TargetRepoDir' is not a Git repository - nothing to detect here." -ForegroundColor Red
        Pause-Console
        return
    }
    $originUrl = git remote get-url origin 2>$null
    if (-not $originUrl) {
        Write-Host "[!] No 'origin' remote set on this folder - can't tell which remote repo to destroy." -ForegroundColor Red
        Pause-Console
        return
    }

    if (-not (Confirm-VcsProvider)) {
        Pause-Console
        return
    }

    $fullName = Get-OwnerRepoFromUrl -Url $originUrl
    if (-not $fullName) {
        Write-Host "[!] Couldn't parse an owner/repo out of: $originUrl" -ForegroundColor Red
        Pause-Console
        return
    }

    Write-Host "Detected remote repo: $fullName ($($Global:VcsProvider))" -ForegroundColor Cyan
    Write-Host "Local folder: $TargetRepoDir`n" -ForegroundColor Cyan

    if (-not (Confirm-VcsReady)) {
        Pause-Console
        return
    }

    if (-not (Confirm-DestructiveAction "PERMANENTLY DELETE '$fullName' from $($Global:VcsProvider) - this cannot be undone")) {
        Write-Host "[i] Cancelled - nothing was destroyed." -ForegroundColor Yellow
        Pause-Console
        return
    }

    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would delete remote repo: $fullName" -ForegroundColor Yellow
    } else {
        # -----------------------------------------------------------------
        # Attempt 1: Delete the repo
        # -----------------------------------------------------------------
        $delOut = Vcs-DeleteRepo $fullName 2>&1
        $delCode = $LASTEXITCODE
        $delStr  = "$delOut"

        # -----------------------------------------------------------------
        # Auto-fix: If 403 + missing delete_repo scope, refresh auth & retry
        # -----------------------------------------------------------------
        if (($delCode -ne 0 -and $null -ne $delCode) -and
            ($delStr -match "delete_repo|scope|403|admin rights")) {

            Write-Host ""
            Write-Host "[!] Permission denied — your 'gh' login is missing the 'delete_repo' scope." -ForegroundColor Yellow
            Write-Host "    This is normal; GitHub doesn't request it by default." -ForegroundColor Yellow
            $fixIt = Read-Host "    Run 'gh auth refresh -s delete_repo' now to fix it? (Y/n)"
            if ($fixIt -notmatch '^[Nn]') {
                Write-Host "`n[+] Requesting delete_repo scope from GitHub..." -ForegroundColor Cyan
                & gh auth refresh -h github.com -s delete_repo 2>&1 | ForEach-Object { Write-Host "    $_" }
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[+] Scope granted! Retrying delete..." -ForegroundColor Green
                    # Small breather so the token update propagates
                    Start-Sleep -Seconds 2
                    $delOut = Vcs-DeleteRepo $fullName 2>&1
                    $delCode = $LASTEXITCODE
                    $delStr  = "$delOut"
                } else {
                    Write-Host "[!] Auth refresh failed — cannot delete." -ForegroundColor Red
                    Pause-Console
                    return
                }
            } else {
                Write-Host "[i] Cancelled. Run this manually when ready:" -ForegroundColor Yellow
                Write-Host "    gh auth refresh -h github.com -s delete_repo" -ForegroundColor Cyan
                Pause-Console
                return
            }
        }

        # -----------------------------------------------------------------
        # Final result check (covers both first-attempt and retry)
        # -----------------------------------------------------------------
        if ($delCode -ne 0 -and $null -ne $delCode) {
            Write-Host "[!] Delete failed:" -ForegroundColor Red
            $delOut | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
            Pause-Console
            return
        }

        Write-Host "[+] Deleted '$fullName' from $($Global:VcsProvider)." -ForegroundColor Green
        if (Get-Command Write-WizardActionLog -ErrorAction SilentlyContinue) {
            Write-WizardActionLog "DESTROYED remote repo: $fullName ($($Global:VcsProvider)) via 1-click destroy"
        }
    }

    $rmOrigin = Read-Host "Also remove the local 'origin' remote link here (keeps your local files/history)? (y/N)"
    if ($rmOrigin -match '^[Yy]$') {
        git remote remove origin 2>$null
        Write-Host "[+] Local 'origin' remote removed." -ForegroundColor Green
    }
    Pause-Console
}

# ==============================================================================
# FORCE SYNC WITH ORIGIN - Nuclear recovery when a local machine has badly
# diverged/tangled and you just want local to match GitHub exactly.
# Steps: detect branch/remote -> backup -> fetch -> hard reset -> clean debris.
# Relies on Invoke-GitWizard, New-SafetyBackup, Confirm-DestructiveAction,
# Show-Header, Pause-Console from git-wizard.ps1 (already loaded globally).
# ==============================================================================
function Invoke-ForceSyncWithOrigin {
    Show-Header
    Write-Host "FORCE SYNC WITH ORIGIN (Nuclear Reset)`n" -ForegroundColor Red
    Write-Host "This makes your LOCAL branch identical to GitHub's version." -ForegroundColor Yellow
    Write-Host "Any local commits or changes not already on origin will be LOST (a backup tag is created first).`n" -ForegroundColor Yellow

    $IsRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($IsRepo -ne "true") {
        Write-Host "[!] Not inside a Git repository." -ForegroundColor Red
        Pause-Console
        return
    }

    # --- Step 1: Detect active branch & remote origin ---
    Write-Host "[1/5] Detecting active branch and remote origin..." -ForegroundColor Cyan
    $Branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $Branch -or $Branch -eq "HEAD") {
        Write-Host "[!] Could not determine active branch (possibly detached HEAD)." -ForegroundColor Red
        Pause-Console
        return
    }
    $OriginUrl = git remote get-url origin 2>$null
    if (-not $OriginUrl) {
        Write-Host "[!] No 'origin' remote configured. Set one via Identity and SSH Manager first." -ForegroundColor Red
        Pause-Console
        return
    }
    Write-Host "    Branch: $Branch" -ForegroundColor Green
    Write-Host "    Origin: $OriginUrl" -ForegroundColor Green

    if (-not (Confirm-DestructiveAction "Force-sync local branch '$Branch' to match origin/$Branch exactly")) {
        Write-Host "[i] Cancelled - no changes made." -ForegroundColor Yellow
        Pause-Console
        return
    }

    # --- Step 2: Create automated safety backup tag/branch ---
    Write-Host "`n[2/5] Creating automated safety backup..." -ForegroundColor Cyan
    New-SafetyBackup "pre-force-sync-$Branch"

    # --- Step 3: Fetch fresh refspec from origin ---
    Write-Host "`n[3/5] Fetching fresh refs from origin..." -ForegroundColor Cyan
    if (-not (Invoke-GitWizard fetch origin)) {
        Write-Host "[!] Fetch failed. Check your connection/remote. Aborting - nothing was reset." -ForegroundColor Red
        Pause-Console
        return
    }

    $RemoteBranchExists = git rev-parse --verify "origin/$Branch" 2>$null
    if (-not $RemoteBranchExists) {
        Write-Host "[!] 'origin/$Branch' does not exist on the remote. Aborting - nothing was reset." -ForegroundColor Red
        Write-Host "    (Check the branch name, or that it's actually pushed to GitHub.)" -ForegroundColor Yellow
        Pause-Console
        return
    }

    # --- Step 4: Hard reset local branch to origin/<branch> ---
    Write-Host "`n[4/5] Hard resetting local '$Branch' to 'origin/$Branch'..." -ForegroundColor Cyan
    Invoke-GitWizard reset --hard "origin/$Branch" | Out-Null

    # --- Step 5: Clean untracked/leftover merge debris ---
    Write-Host "`n[5/5] Cleaning untracked files and leftover merge debris (-fd)..." -ForegroundColor Cyan
    Invoke-GitWizard clean -fd | Out-Null

    Write-Host "`n[+] Force sync complete. Local '$Branch' now matches origin/$Branch exactly." -ForegroundColor Green
    Write-Host "    Recover anything lost with: git reset --hard <backup-tag-name-shown-above>" -ForegroundColor Green
    Pause-Console
}
