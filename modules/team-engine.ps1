# ==============================================================================
# MODULE:       team-engine.ps1
# PART OF:      git-wizard.ps1 (Windows Edition)
# DESCRIPTION:  Module 5 - Team & Open-Source Collaboration
#               Linear Workflow, Team Mode, Open-Source Contributor Mode,
#               Safe Update Sync, Repo History Viewer.
# NOTE:         Relies on functions from git-wizard.ps1 (already dot-sourced
#               into global scope before this file loads): Invoke-GitWizard,
#               New-SafetyBackup, Confirm-DestructiveAction, Show-Header,
#               Pause-Console, Write-WizardActionLog.
# ==============================================================================

# ------------------------------------------------------------------------------
# Arrow-key selector for LOCAL branches
# ------------------------------------------------------------------------------
function Select-BranchInteractive {
    param([string]$Prompt)

    $Branches = @(git branch --format="%(refname:short)")
    if (-not $Branches -or $Branches.Count -eq 0) {
        Write-Host "[!] No local branches found." -ForegroundColor Red
        return $null
    }

    $Selected = 0
    while ($true) {
        Show-Header
        Write-Host "$Prompt`n" -ForegroundColor Yellow
        for ($i = 0; $i -lt $Branches.Count; $i++) {
            if ($i -eq $Selected) {
                Write-Host "  >  $($Branches[$i]) (Selected)" -ForegroundColor Green
            } else {
                Write-Host "     $($Branches[$i])"
            }
        }
        Write-Host "`n[UP/DOWN to navigate, ENTER to select, Q to cancel]" -ForegroundColor Cyan

        $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($Key.VirtualKeyCode) {
            38 { if ($Selected -gt 0) { $Selected-- } else { $Selected = $Branches.Count - 1 } } # Up
            40 { if ($Selected -lt ($Branches.Count - 1)) { $Selected++ } else { $Selected = 0 } } # Down
            13 { return $Branches[$Selected] } # Enter
            81 { return $null } # Q
        }
    }
}

# ------------------------------------------------------------------------------
# Arrow-key selector for REMOTE branches, with author/date/message per row
# ------------------------------------------------------------------------------
function Select-RemoteBranchInteractive {
    param([string]$Prompt)

    $RawRefs = @(git for-each-ref --format="%(refname:short)" refs/remotes/origin)
    $Candidates = @()
    foreach ($r in $RawRefs) {
        $short = $r -replace '^origin/', ''
        if ($short -eq "main" -or $short -eq "master" -or $short -eq "HEAD") { continue }
        $Candidates += $short
    }

    if ($Candidates.Count -eq 0) {
        Write-Host "[!] No remote branches available for review (besides main)." -ForegroundColor Red
        return $null
    }

    $Selected = 0
    while ($true) {
        Show-Header
        Write-Host "$Prompt`n" -ForegroundColor Yellow
        for ($i = 0; $i -lt $Candidates.Count; $i++) {
            $info = git log -1 --format="%an | %ar | %s" "origin/$($Candidates[$i])" 2>$null
            if (-not $info) { $info = "unknown" }
            if ($i -eq $Selected) {
                Write-Host "  >  $($Candidates[$i])  ($info)" -ForegroundColor Green
            } else {
                Write-Host "     $($Candidates[$i])  ($info)" -ForegroundColor White
            }
        }
        Write-Host "`n[UP/DOWN to navigate, ENTER to review this branch, Q to cancel]" -ForegroundColor Cyan

        $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($Key.VirtualKeyCode) {
            38 { if ($Selected -gt 0) { $Selected-- } else { $Selected = $Candidates.Count - 1 } }
            40 { if ($Selected -lt ($Candidates.Count - 1)) { $Selected++ } else { $Selected = 0 } }
            13 { return $Candidates[$Selected] }
            81 { return $null }
        }
    }
}

# ------------------------------------------------------------------------------
# 5.1 Linear Workflow (Solo / Sequential - even across multiple machines)
# ------------------------------------------------------------------------------
function Invoke-LinearWorkflow {
    Show-Header
    Write-Host "LINEAR WORKFLOW (Solo / Sequential)`n" -ForegroundColor Yellow
    Write-Host "Guideline: only one person works at a time. Always pull before you push.`n" -ForegroundColor Cyan

    $Branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $Branch) { $Branch = "main" }

    Write-Host "--> Checking if local is behind remote before allowing push..." -ForegroundColor Cyan
    git fetch --quiet 2>$null | Out-Null
    $Behind = git rev-list --count "$Branch..origin/$Branch" 2>$null
    if (-not $Behind) { $Behind = 0 }

    if ([int]$Behind -gt 0) {
        Write-Host "[!] Your branch is $Behind commit(s) behind origin/$Branch." -ForegroundColor Red
        Write-Host "--> Pulling first (required in Linear Mode)..." -ForegroundColor Yellow
        if (-not (Invoke-GitWizard pull origin $Branch --rebase)) {
            Write-Host "[!] Pull/rebase failed - resolve conflicts manually before pushing." -ForegroundColor Red
            Pause-Console
            return
        }
    }

    Invoke-GitWizard add . | Out-Null
    $StatusOut = git status --porcelain
    if ($StatusOut) {
        $Msg = Read-Host "Enter commit message"
        if ($Msg) { Invoke-GitWizard commit -m $Msg | Out-Null }
    }

    if (Invoke-GitWizard push origin $Branch) {
        Write-Host "[+] Linear workflow complete." -ForegroundColor Green
    } else {
        Write-Host "[!] Push failed. Check your remote/connection, then retry." -ForegroundColor Yellow
    }
    Pause-Console
}

# ------------------------------------------------------------------------------
# 5.2 Team Mode
# ------------------------------------------------------------------------------
function Invoke-TeamModeStartTask {
    Show-Header
    Write-Host "TEAM MODE - Start My Task`n" -ForegroundColor Yellow
    Write-Host "  [1] feature  [2] fix  [3] hotfix"
    $TType = Read-Host "Select branch type [1-3]"
    $Prefix = switch ($TType) {
        "1" { "feature" }
        "2" { "fix" }
        "3" { "hotfix" }
        default { $null }
    }
    if (-not $Prefix) { Write-Host "Cancelled." -ForegroundColor Yellow; Pause-Console; return }

    $TName = Read-Host "Short name for your task (e.g. login-bug)"
    if (-not $TName) { Write-Host "Name required." -ForegroundColor Red; Pause-Console; return }

    $BranchName = "$Prefix/$TName"
    if (-not (Invoke-GitWizard checkout -b $BranchName)) {
        Write-Host "[!] Could not create branch '$BranchName' (may already exist)." -ForegroundColor Red
        Pause-Console
        return
    }
    Write-Host "[+] Branch '$BranchName' created." -ForegroundColor Green

    Write-Host "`n--> Staging your changes on this branch..." -ForegroundColor Cyan
    Invoke-GitWizard add . | Out-Null
    $StatusOut = git status --porcelain
    if (-not $StatusOut) {
        Write-Host "[i] No changes to commit yet - branch created and will be published empty." -ForegroundColor Yellow
    } else {
        $CMsg = Read-Host "Enter commit message describing your $Prefix"
        if (-not $CMsg) { $CMsg = "$Prefix`: $TName" }
        Invoke-GitWizard commit -m $CMsg | Out-Null
    }

    if (Invoke-GitWizard push -u origin $BranchName) {
        Write-Host "[+] Branch '$BranchName' published with your changes to GitHub. Never commit directly to main - the admin will review and merge this branch." -ForegroundColor Green
    } else {
        Write-Host "[!] Push failed. Your branch and commit exist locally - check your remote/connection, then push manually." -ForegroundColor Red
    }
    Pause-Console
}

function Invoke-TeamModeAdminDashboard {
    Show-Header
    Write-Host "TEAM MODE - Admin Dashboard`n" -ForegroundColor Yellow
    Write-Host "--> Fetching latest branch info from GitHub..." -ForegroundColor Cyan
    git fetch --all --quiet 2>$null | Out-Null

    $ReviewBranch = Select-RemoteBranchInteractive "SELECT A BRANCH TO REVIEW (author | date | last message)"
    if (-not $ReviewBranch) { Pause-Console; return }

    Show-Header
    Write-Host "--- Diff vs main for origin/$ReviewBranch ---`n" -ForegroundColor Cyan
    git diff "main...origin/$ReviewBranch"

    Write-Host "`n  [1] Merge into main   [2] Reject (skip, no changes)   [3] Cancel"
    $MChoice = Read-Host "Choice [1-3]"
    switch ($MChoice) {
        "1" {
            New-SafetyBackup "pre-merge-$ReviewBranch"
            if (Invoke-GitWizard checkout main) {
                if (Invoke-GitWizard merge --no-ff "origin/$ReviewBranch" -m "Merge branch '$ReviewBranch' via git-wizard Team Mode") {
                    if (Invoke-GitWizard push origin main) {
                        Write-Host "[+] Merged and pushed." -ForegroundColor Green
                    } else {
                        Write-Host "[!] Merge succeeded locally but push failed. Check your remote/connection, then push manually." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "[!] Merge failed - likely conflicts. Resolve manually on 'main'." -ForegroundColor Red
                }
            }
        }
        "2" { Write-Host "[i] Skipped, no changes made." -ForegroundColor Yellow }
        default { Write-Host "Cancelled." }
    }
    Pause-Console
}

function Show-TeamModeMenu {
    while ($true) {
        Show-Header
        Write-Host "TEAM MODE (Private repo, collaborators have write access)`n" -ForegroundColor Yellow
        Write-Host "  [1] Start My Task" -ForegroundColor Green
        Write-Host "      You're a contributor: creates your branch, commits your changes, pushes it. Never touches main." -ForegroundColor Cyan
        Write-Host "  [2] Admin Dashboard" -ForegroundColor Green
        Write-Host "      You're the repo owner: pick a teammate's branch (arrow keys), view its diff, merge or reject it." -ForegroundColor Cyan
        Write-Host "  [3] Guidelines" -ForegroundColor Green
        Write-Host "  [4] Back" -ForegroundColor Green
        $TChoice = Read-Host "Select choice [1-4]"
        switch ($TChoice) {
            "1" { Invoke-TeamModeStartTask }
            "2" { Invoke-TeamModeAdminDashboard }
            "3" {
                Show-Header
                Write-Host "TEAM MODE GUIDELINES`n" -ForegroundColor Cyan
                Write-Host "- Never commit directly to main."
                Write-Host "- Always create a feature/fix/hotfix branch for your work."
                Write-Host "- The repo admin reviews and merges via the Admin Dashboard."
                Write-Host "- This requires you to be added as a Collaborator on the repo."
                Pause-Console
            }
            "4" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ------------------------------------------------------------------------------
# 5.3 Open-Source Contributor Mode (fork + PR, powered by gh CLI)
# ------------------------------------------------------------------------------
function Invoke-OssSetupFork {
    Show-Header
    Write-Host "Detect / Setup Fork`n" -ForegroundColor Yellow
    $UpstreamUrl = git remote get-url upstream 2>$null
    if ($UpstreamUrl) {
        Write-Host "[+] 'upstream' remote already configured: $UpstreamUrl" -ForegroundColor Green
    } else {
        Write-Host "No 'upstream' remote found." -ForegroundColor Cyan
        $UpUrl = Read-Host "Enter the ORIGINAL repo URL you forked from"
        if ($UpUrl) {
            if (Invoke-GitWizard remote add upstream $UpUrl) {
                Write-Host "[+] 'upstream' remote added." -ForegroundColor Green
            }
        }
    }
    Pause-Console
}

function Invoke-OssSyncFork {
    Show-Header
    Write-Host "Sync Fork with Upstream`n" -ForegroundColor Yellow
    $UpstreamUrl = git remote get-url upstream 2>$null
    if (-not $UpstreamUrl) {
        Write-Host "[!] No 'upstream' remote set. Use option [1] first." -ForegroundColor Red
        Pause-Console
        return
    }
    $Branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $Branch) { $Branch = "main" }

    if (-not (Invoke-GitWizard fetch upstream)) {
        Write-Host "[!] Could not reach 'upstream' remote. Check the URL/connection." -ForegroundColor Red
        Pause-Console
        return
    }
    if (-not (Invoke-GitWizard merge "upstream/$Branch")) {
        Write-Host "[!] Merge conflicts - resolve manually." -ForegroundColor Yellow
    }
    if (Invoke-GitWizard push origin $Branch) {
        Write-Host "[+] Fork synced with upstream." -ForegroundColor Green
    } else {
        Write-Host "[!] Push to your fork failed. Check your remote/connection." -ForegroundColor Yellow
    }
    Pause-Console
}

function Invoke-OssCreatePR {
    Show-Header
    Write-Host "Create Pull Request`n" -ForegroundColor Yellow
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "[i] 'gh' (GitHub CLI) is not installed." -ForegroundColor Yellow
        Write-Host "    Install with: winget install --id GitHub.cli" -ForegroundColor Green
        Pause-Console
        return
    }
    $PrTitle = Read-Host "PR Title"
    $PrBody  = Read-Host "PR Body (short description)"
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would execute: gh pr create --title `"$PrTitle`" --body `"$PrBody`"" -ForegroundColor Yellow
        Write-WizardActionLog "DRY-RUN (not executed): gh pr create --title `"$PrTitle`""
    } else {
        gh pr create --title $PrTitle --body $PrBody
        Write-WizardActionLog "EXECUTED: gh pr create --title `"$PrTitle`""
    }
    Pause-Console
}

function Invoke-OssViewPRs {
    Show-Header
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "[i] 'gh' (GitHub CLI) is not installed." -ForegroundColor Yellow
        Write-Host "    Install with: winget install --id GitHub.cli" -ForegroundColor Green
        Pause-Console
        return
    }
    gh pr list --author "@me"
    Pause-Console
}

function Show-OssContributorMenu {
    while ($true) {
        Show-Header
        Write-Host "OPEN-SOURCE CONTRIBUTOR MODE (Fork + PR, powered by gh CLI)`n" -ForegroundColor Yellow
        Write-Host "  [1] Detect / Setup Fork (upstream remote)" -ForegroundColor Green
        Write-Host "      Links this local repo to the ORIGINAL project you forked from." -ForegroundColor Cyan
        Write-Host "  [2] Sync Fork with Upstream" -ForegroundColor Green
        Write-Host "      Pulls the latest changes from the original repo into your fork." -ForegroundColor Cyan
        Write-Host "  [3] Create PR from Current Branch" -ForegroundColor Green
        Write-Host "      Opens a Pull Request asking the original repo's owner to merge your branch." -ForegroundColor Cyan
        Write-Host "  [4] View My Open PRs" -ForegroundColor Green
        Write-Host "      Lists Pull Requests you've submitted that are still awaiting review." -ForegroundColor Cyan
        Write-Host "  [5] Check gh CLI Installed" -ForegroundColor Green
        Write-Host "  [6] Back" -ForegroundColor Green
        $OChoice = Read-Host "Select choice [1-6]"
        switch ($OChoice) {
            "1" { Invoke-OssSetupFork }
            "2" { Invoke-OssSyncFork }
            "3" { Invoke-OssCreatePR }
            "4" { Invoke-OssViewPRs }
            "5" {
                if (Get-Command gh -ErrorAction SilentlyContinue) {
                    $v = gh --version | Select-Object -First 1
                    Write-Host "[+] gh CLI is installed: $v" -ForegroundColor Green
                } else {
                    Write-Host "[i] 'gh' is not installed. Install with: winget install --id GitHub.cli" -ForegroundColor Yellow
                }
                Pause-Console
            }
            "6" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ------------------------------------------------------------------------------
# 5.4 Safe Update Sync (stash -> pull --rebase -> pop)
# ------------------------------------------------------------------------------
function Invoke-SafeUpdateSync {
    Show-Header
    Write-Host "SAFE UPDATE SYNC`n" -ForegroundColor Yellow

    $Branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $Branch) { $Branch = "main" }

    $StatusOut = git status --porcelain
    $Dirty = [bool]$StatusOut

    if ($Dirty) {
        $StashMsg = "auto-sync-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Write-Host "--> Uncommitted changes detected. Stashing as '$StashMsg'..." -ForegroundColor Cyan
        Invoke-GitWizard stash push -m $StashMsg | Out-Null
    }

    Write-Host "--> Pulling latest changes..." -ForegroundColor Cyan
    if (-not (Invoke-GitWizard pull origin $Branch --rebase)) {
        Write-Host "[!] Pull failed or conflicts occurred. Resolve manually, then run: git stash pop" -ForegroundColor Red
        Pause-Console
        return
    }

    if ($Dirty -and -not $Global:DryRun) {
        Write-Host "--> Restoring your local changes..." -ForegroundColor Cyan
        git stash pop
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] Conflict restoring your changes. They remain safe in 'git stash list'." -ForegroundColor Red
        } else {
            Write-Host "[+] Your local work is safe and up to date with remote." -ForegroundColor Green
        }
    }
    Pause-Console
}

# ------------------------------------------------------------------------------
# 5.5 Repo History Viewer
# ------------------------------------------------------------------------------
function Show-RepoHistoryViewer {
    Show-Header
    Write-Host "REPO HISTORY VIEWER`n" -ForegroundColor Yellow
    git fetch --quiet 2>$null | Out-Null

    if (Get-Command delta -ErrorAction SilentlyContinue) {
        git log --oneline --graph --all --decorate --color | delta --paging=always
    } else {
        git --no-pager log --oneline --graph --all --decorate --color | Out-Host -Paging
    }
}

# ------------------------------------------------------------------------------
# MODULE 5 MENU
# ------------------------------------------------------------------------------
function Show-Module5Menu {
    while ($true) {
        Show-Header
        Write-Host "Module 5: Team and Open-Source Collaboration`n" -ForegroundColor Yellow
        Write-Host "  [1] Linear Workflow (Solo/Sequential)" -ForegroundColor Green
        Write-Host "      You're the only one working - even across multiple machines. Pulls before every push." -ForegroundColor Cyan
        Write-Host "  [2] Team Mode (private repo, collaborators)" -ForegroundColor Green
        Write-Host "      Others have write access to YOUR repo. Everyone branches, you review and merge." -ForegroundColor Cyan
        if ($Global:WizardMode -eq "advanced") {
            Write-Host "  [3] Open-Source Contributor Mode (fork + PR)" -ForegroundColor Green
            Write-Host "      You're contributing to someone ELSE'S repo (or accepting outside PRs on yours)." -ForegroundColor Cyan
        } else {
            Write-Host "  [3] Open-Source Contributor Mode (switch to Advanced Mode to unlock)" -ForegroundColor DarkGray
            Write-Host "      Fork/upstream/PR workflow for contributing to repos you don't own." -ForegroundColor Cyan
        }
        Write-Host "  [4] Safe Update Sync (protects local work while pulling)" -ForegroundColor Green
        Write-Host "      Stashes your uncommitted work, pulls latest, restores your work on top." -ForegroundColor Cyan
        Write-Host "  [5] Repo History Viewer" -ForegroundColor Green
        Write-Host "      Shows commit graph across all branches (uses 'delta' for prettier diffs if installed)." -ForegroundColor Cyan
        Write-Host "  [6] Toggle Auto-Sync Indicator (currently: $Global:AutoSyncCheck)" -ForegroundColor Green
        Write-Host "      Shows a live ahead/behind status vs GitHub at the top of every screen." -ForegroundColor Cyan
        Write-Host "  [7] Back to Main Menu" -ForegroundColor Green
        Write-Host "`n===================================================================="
        $M5Choice = Read-Host "Select choice [1-7]"
        switch ($M5Choice) {
            "1" { Invoke-LinearWorkflow }
            "2" { Show-TeamModeMenu }
            "3" {
                if ($Global:WizardMode -eq "advanced") {
                    Show-OssContributorMenu
                } else {
                    Write-Host "[i] This feature is hidden in Beginner Mode. Switch modes from Settings." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
            "4" { Invoke-SafeUpdateSync }
            "5" { Show-RepoHistoryViewer }
            "6" { Toggle-AutoSync }
            "7" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}