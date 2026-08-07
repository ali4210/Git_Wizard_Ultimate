# ==============================================================================
# ENGINE NAME: repo-engine.ps1 (PowerShell 5.1 Clean Edition - V2.0 Gold Standard)
# NEW IN V2.0: Force Sync with Origin (nuclear reset recovery), destructive
#              operations routed through Invoke-GitWizard/New-SafetyBackup/
#              Confirm-DestructiveAction from git-wizard.ps1 for Dry-Run and
#              automatic safety-backup support.
# ==============================================================================

function Manage-Repo {
    while ($true) {
        Show-Header
        Write-Host "  [+] Module 2: Repository Setup, Status and Reset Engine`n" -ForegroundColor Yellow
        Write-Host "  [1] 1-Click Complete Repo Setup (Init, Main Branch, Commit, Remote, Push)" -ForegroundColor Green
        Write-Host "  [2] Quick Push (Add All -> Commit -> Push)" -ForegroundColor Green
        Write-Host "  [3] Inspect Working Directory Status (git status)" -ForegroundColor Green
        Write-Host "  [4] Interactive Git Reset and Undo Utility" -ForegroundColor Green
        Write-Host "  [5] Smart Conflict Push Resolver" -ForegroundColor Green
        Write-Host "  [6] Generate Tailored .gitignore File" -ForegroundColor Green
        Write-Host "  [7] Back to Main Menu" -ForegroundColor Green
        Write-Host "`n====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [1-7]"

        switch ($choice) {
            "1" {
                Write-Host "`n--> Initializing Git repository..." -ForegroundColor Green
                Invoke-GitWizard init | Out-Null
                Invoke-GitWizard branch -M main | Out-Null
                Invoke-GitWizard add . | Out-Null
                $status = git status --porcelain
                if (-not $status) {
                    Write-Host "[i] Working tree clean (nothing new to commit)." -ForegroundColor Yellow
                } else {
                    $msg = Read-Host "Enter initial commit message [default: Initial commit]"
                    if (-not $msg) { $msg = "Initial commit" }
                    Invoke-GitWizard commit -m "$msg" | Out-Null
                }

                $existing = git remote get-url origin 2>$null
                Write-Host "`nGITHUB REMOTE URL SETUP" -ForegroundColor Cyan
                if ($existing) {
                    Write-Host "[+] Existing Remote Detected: $existing" -ForegroundColor Green
                    $rawUrl = Read-Host "Enter Remote URL (press ENTER to keep current)"
                } else {
                    $rawUrl = Read-Host "Enter GitHub Remote URL (HTTPS or SSH)"
                }

                $remoteUrl = Clean-RemoteUrl -url $rawUrl
                if ($remoteUrl) {
                    git remote remove origin 2>$null
                    git remote add origin "$remoteUrl"
                    Write-Host "[+] Remote attached: $remoteUrl" -ForegroundColor Green
                } elseif ($existing) {
                    $remoteUrl = $existing
                }

                if ($remoteUrl) {
                    Write-Host "--> Pushing to origin main..." -ForegroundColor Green
                    if (-not (Invoke-GitWizard push -u origin main)) {
                        Write-Host "[!] Push rejected or failed. Use Option [5] (Smart Conflict Push Resolver) to sync!" -ForegroundColor Yellow
                    }
                }
                Pause-Console
            }
            "2" {
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
                    Invoke-GitWizard commit -m "$msg" | Out-Null
                    $branch = git rev-parse --abbrev-ref HEAD 2>$null
                    if (-not $branch) { $branch = "main" }
                    if (-not (Invoke-GitWizard push origin "$branch")) {
                        Write-Host "[!] Push rejected. Use Option [5] to resolve." -ForegroundColor Yellow
                    }
                }
                Pause-Console
            }
            "3" {
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
            "4" {
                while ($true) {
                    Show-Header
                    Write-Host "INTERACTIVE GIT RESET AND UNDO UTILITY`n" -ForegroundColor Yellow
                    Write-Host "  [1] Unstage All Files" -ForegroundColor Green
                    Write-Host "  [2] Discard All Uncommitted Local Changes" -ForegroundColor Red
                    Write-Host "  [3] Soft Rollback Last Commit" -ForegroundColor Green
                    Write-Host "  [4] Hard Rollback Last Commit (DESTROY last commit)" -ForegroundColor Red
                    Write-Host "  [5] Force Sync with Origin (Nuclear reset - matches GitHub exactly!)" -ForegroundColor Red
                    Write-Host "      Use this when your local branch is badly tangled/diverged and you just want it to match origin/main exactly." -ForegroundColor Cyan
                    Write-Host "  [6] Back to Module 2 Menu" -ForegroundColor Green

                    $resetChoice = Read-Host "Select choice [1-6]"
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
                    } elseif ($resetChoice -eq "6") { return }
                }
            }
            "5" {
                Show-Header
                Write-Host "SMART CONFLICT PUSH RESOLVER`n" -ForegroundColor Yellow
                $branch = git rev-parse --abbrev-ref HEAD 2>$null
                Write-Host "Current Branch: $branch" -ForegroundColor Cyan
                Write-Host "  [1] Safe Pull and Rebase" -ForegroundColor Green
                Write-Host "  [2] Safe Pull and Merge" -ForegroundColor Green
                Write-Host "  [3] Force Push" -ForegroundColor Red
                Write-Host "  [4] Cancel" -ForegroundColor Green

                $strat = Read-Host "Select strategy [1-4]"
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
                }
                Pause-Console
            }
            "6" {
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
            "7" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
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