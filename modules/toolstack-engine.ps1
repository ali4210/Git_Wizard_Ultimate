# ==============================================================================
# ENGINE NAME: toolstack-engine.ps1 (Windows Edition) — NEW
# DESCRIPTION: Windows equivalent of the Linux Tool Stack Manager: winget-based
#              install offers, version checks against latest releases, the
#              git-wizard self-update/checkpoint/rollback system, and bonus
#              tools (lazygit).
# NOTE:        Relies on globals from git-wizard.ps1.
# ==============================================================================

$Global:UpdateRepo        = ""
$Global:LastUpdateCheck   = $null
$Global:UpdateNotice      = ""

function Get-WingetId {
    param([string]$Tool)
    switch ($Tool) {
        "gh"      { return "GitHub.cli" }
        "glab"    { return "GLab.glab" }
        "delta"   { return "dandavison.delta" }
        "lazygit" { return "JesseDuffield.lazygit" }
        default   { return $Tool }
    }
}

function Test-WingetAvailable { return [bool](Get-Command winget -ErrorAction SilentlyContinue) }

function Install-ToolViaWinget {
    param([string]$Tool)
    if (-not (Test-WingetAvailable)) {
        Write-Host "  [!] winget not found on this system. Install '$Tool' manually, or via Windows App Installer." -ForegroundColor Red
        return
    }
    $id = Get-WingetId -Tool $Tool
    Write-Host "  Detected package manager: winget" -ForegroundColor Cyan
    Write-Host "  Install with: winget install --id $id -e" -ForegroundColor Green
    $doInstall = Read-Host "  Install '$Tool' now? (y/N)"
    if ($doInstall -match '^[Yy]$') {
        winget install --id $id -e
        if (Get-Command $Tool -ErrorAction SilentlyContinue) {
            Write-Host "  [+] '$Tool' installed successfully." -ForegroundColor Green
            if (Get-Command Write-WizardActionLog -ErrorAction SilentlyContinue) {
                Write-WizardActionLog "Installed optional tool: $Tool (via winget)"
            }
        } else {
            Write-Host "  [!] Install ran, but '$Tool' still isn't on PATH. You may need to restart your terminal." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [i] Skipped." -ForegroundColor Yellow
    }
}

function Test-OptionalToolsFull {
    Show-Header
    Write-Host "TOOL VERIFICATION (winget-based)`n" -ForegroundColor Yellow
    $tools = @("gh", "glab", "delta", "lazygit")
    foreach ($t in $tools) {
        if (Get-Command $t -ErrorAction SilentlyContinue) {
            Write-Host "  [+] $t - installed" -ForegroundColor Green
        } else {
            Write-Host "  [x] $t - missing" -ForegroundColor Red
            Install-ToolViaWinget -Tool $t
            Write-Host ""
        }
    }
    Pause-Console
}

function Show-ToolStackVersions {
    Show-Header
    Write-Host "TOOL STACK VERSIONS`n" -ForegroundColor Yellow
    $tools = @("git", "gh", "glab", "delta", "lazygit")
    foreach ($t in $tools) {
        if (Get-Command $t -ErrorAction SilentlyContinue) {
            $v = & $t --version 2>$null | Select-Object -First 1
            Write-Host "  [+] $t`: $v" -ForegroundColor Green
        } else {
            Write-Host "  [x] $t`: not installed" -ForegroundColor Red
        }
    }
    Write-Host "`n[i] Update installed tools any time via 'winget upgrade' or Tool Stack Manager > Verify/Install." -ForegroundColor Cyan
    Pause-Console
}

function Show-ToolStackUpdates {
    Show-Header
    Write-Host "CHECK FOR TOOL UPDATES (winget)`n" -ForegroundColor Yellow
    if (-not (Test-WingetAvailable)) {
        Write-Host "[!] winget not found on this system - cannot check for updates automatically." -ForegroundColor Red
        Pause-Console
        return
    }
    Write-Host "--> Checking winget upgrade list...`n" -ForegroundColor Cyan
    winget upgrade
    Write-Host "`n[i] Run 'winget upgrade --id <PackageId>' to update a specific tool, or 'winget upgrade --all' for everything." -ForegroundColor Cyan
    $doAll = Read-Host "Run 'winget upgrade --all' now? (y/N)"
    if ($doAll -match '^[Yy]$') {
        winget upgrade --all
        if (Get-Command Write-WizardActionLog -ErrorAction SilentlyContinue) {
            Write-WizardActionLog "Ran winget upgrade --all"
        }
    }
    Pause-Console
}

# ==============================================================================
# SELF-UPDATE / ROLLBACK — updates git-wizard's OWN installation (module
# directory), never touches the user's other project repos.
# ==============================================================================
function Set-UpdateRepo {
    Show-Header
    Write-Host "SELF-UPDATE SOURCE`n" -ForegroundColor Yellow
    Write-Host "Current: $(if ($Global:UpdateRepo) { $Global:UpdateRepo } else { 'not set' })`n" -ForegroundColor Cyan
    Write-Host "Enter your GitHub repo in the form username/repo-name (the one this tool lives in)." -ForegroundColor Cyan
    $newRepo = Read-Host "Repo (ENTER to leave unchanged)"
    if ($newRepo) {
        $Global:UpdateRepo = $newRepo
        Save-WizardConfig
        Write-Host "[+] Update source set to: $Global:UpdateRepo" -ForegroundColor Green
    }
    Pause-Console
}

function Get-LatestReleaseTag {
    param([string]$Repo)
    try {
        $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 8 -ErrorAction Stop
        return $resp.tag_name
    } catch {
        return $null
    }
}

function Test-VersionIsNewer {
    param([string]$a, [string]$b)
    try {
        $av = [version]($a.TrimStart('v'))
        $bv = [version]($b.TrimStart('v'))
        return ($av -gt $bv)
    } catch {
        return ($a -ne $b)
    }
}

function Test-ForUpdates {
    param([switch]$Silent)
    if (-not $Global:UpdateRepo) {
        if (-not $Silent) {
            Write-Host "[i] No update source configured yet." -ForegroundColor Yellow
            Set-UpdateRepo
        }
        return
    }
    $latest = Get-LatestReleaseTag -Repo $Global:UpdateRepo
    $Global:LastUpdateCheck = Get-Date
    Save-WizardConfig

    if (-not $latest) {
        if (-not $Silent) { Write-Host "[i] Could not reach GitHub, or no Releases published yet for $Global:UpdateRepo." -ForegroundColor Yellow }
        return
    }

    if (Test-VersionIsNewer -a $latest -b "v2.1.0") {
        $Global:UpdateNotice = "Update available: $latest - https://github.com/$Global:UpdateRepo/releases/latest"
        if (-not $Silent) { Write-Host $Global:UpdateNotice -ForegroundColor Green }
    } else {
        $Global:UpdateNotice = ""
        if (-not $Silent) { Write-Host "[+] You're up to date." -ForegroundColor Green }
    }
}

function New-ToolCheckpoint {
    Show-Header
    Write-Host "CREATE A GIT-WIZARD CHECKPOINT`n" -ForegroundColor Yellow

    $isRepo = git -C $ScriptDir rev-parse --is-inside-work-tree 2>$null
    if ($isRepo -ne "true") {
        Write-Host "[!] $ScriptDir isn't a git repository - checkpoints need it to be a git clone." -ForegroundColor Red
        Pause-Console
        return
    }

    Write-Host "This saves the CURRENT state of git-wizard itself as a rollback point -" -ForegroundColor Cyan
    Write-Host "useful before you manually edit the modules, even if you're not updating right now.`n" -ForegroundColor Cyan

    $tag = "tool-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    git -C $ScriptDir tag $tag HEAD
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] Checkpoint created: $tag" -ForegroundColor Green
        Write-Host "    Roll back to it anytime via Settings > Rollback git-wizard." -ForegroundColor Cyan
        Write-WizardActionLog "Manual tool checkpoint created: $tag"
    } else {
        Write-Host "[!] Couldn't create the checkpoint tag." -ForegroundColor Red
    }
    Pause-Console
}

function Update-GitWizardSelf {
    Show-Header
    Write-Host "UPDATE GIT-WIZARD`n" -ForegroundColor Yellow

    $isRepo = git -C $ScriptDir rev-parse --is-inside-work-tree 2>$null
    if ($isRepo -ne "true") {
        Write-Host "[!] $ScriptDir isn't a git repository - git-wizard wasn't installed via 'git clone'." -ForegroundColor Red
        Write-Host "    Re-download the latest version manually from your GitHub repo instead." -ForegroundColor Cyan
        Pause-Console
        return
    }

    if (-not $Global:UpdateRepo) {
        Write-Host "[i] No update source configured yet." -ForegroundColor Yellow
        Set-UpdateRepo
        if (-not $Global:UpdateRepo) { Pause-Console; return }
    }

    $branch = git -C $ScriptDir rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch) { $branch = "main" }

    $dirty = git -C $ScriptDir status --porcelain
    if ($dirty) {
        Write-Host "[!] You have uncommitted local changes in the git-wizard install directory itself." -ForegroundColor Red
        Write-Host "    Commit or discard those first, or updating could conflict." -ForegroundColor Cyan
        Pause-Console
        return
    }

    $backupTag = "tool-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    git -C $ScriptDir tag $backupTag HEAD
    Write-Host "[+] Safety tag created: $backupTag (this is how you'll roll back if the update has a bug)`n" -ForegroundColor Green
    Write-WizardActionLog "Tool self-update: created backup tag $backupTag"

    Write-Host "--> Fetching latest from $Global:UpdateRepo..." -ForegroundColor Cyan
    git -C $ScriptDir fetch origin $branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Fetch failed. Check your connection. No changes were made." -ForegroundColor Red
        Pause-Console
        return
    }

    Write-Host "--> Pulling latest changes into $ScriptDir..." -ForegroundColor Cyan
    git -C $ScriptDir pull origin $branch 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[+] git-wizard updated successfully." -ForegroundColor Green
        Write-Host "    Restart git-wizard to use the new version." -ForegroundColor Cyan
        Write-Host "    If this update causes a problem, use Settings > Rollback git-wizard - pick '$backupTag'." -ForegroundColor Cyan
        Write-WizardActionLog "Tool self-update: pulled latest (backup: $backupTag)"
    } else {
        Write-Host "`n[!] Pull failed (possibly a conflict). Nothing was lost - roll back with:" -ForegroundColor Red
        Write-Host "    git -C `"$ScriptDir`" reset --hard $backupTag" -ForegroundColor Green
    }
    Pause-Console
}

function Restore-GitWizardRollback {
    Show-Header
    Write-Host "ROLLBACK GIT-WIZARD TO A PREVIOUS VERSION`n" -ForegroundColor Yellow

    $isRepo = git -C $ScriptDir rev-parse --is-inside-work-tree 2>$null
    if ($isRepo -ne "true") {
        Write-Host "[!] $ScriptDir isn't a git repository - nothing to roll back." -ForegroundColor Red
        Pause-Console
        return
    }

    $tags = @(git -C $ScriptDir tag -l "tool-backup-*" --sort=-creatordate)
    if ($tags.Count -eq 0) {
        Write-Host "[i] No backup tags found yet - rollback points are only created when you run 'Update git-wizard'." -ForegroundColor Yellow
        Pause-Console
        return
    }

    $tag = Select-FromOptions -Prompt "SELECT A BACKUP TO ROLL BACK TO" -Labels $tags -Values $tags
    if (-not $tag) { Pause-Console; return }

    Show-Header
    Write-Host "ROLLBACK TO: $tag`n" -ForegroundColor Yellow
    Write-Host "This only affects the git-wizard TOOL itself ($ScriptDir)." -ForegroundColor Cyan
    Write-Host "It does NOT touch any of your other project repos or their local files.`n" -ForegroundColor Cyan

    if (Confirm-DestructiveAction "Roll back git-wizard to $tag - any changes made to the tool since then are discarded") {
        git -C $ScriptDir reset --hard $tag
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n[+] Rolled back to $tag." -ForegroundColor Green
            Write-Host "    Restart git-wizard to use this version." -ForegroundColor Cyan
            Write-WizardActionLog "Tool rolled back to $tag"
        } else {
            Write-Host "[!] Rollback failed." -ForegroundColor Red
        }
    }
    Pause-Console
}

# ==============================================================================
# PRE-COMMIT HOOKS SETUP
# ==============================================================================
function Install-PrecommitHooks {
    Show-Header
    Write-Host "PRE-COMMIT HOOKS SETUP`n" -ForegroundColor Yellow

    $isRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($isRepo -ne "true") {
        Write-Host "[!] Not inside a Git repository. cd into one first." -ForegroundColor Red
        Pause-Console
        return
    }

    if (-not (Get-Command pre-commit -ErrorAction SilentlyContinue)) {
        Write-Host "[i] 'pre-commit' is not installed." -ForegroundColor Yellow
        if (Get-Command pip -ErrorAction SilentlyContinue) {
            Write-Host "  Install with: pip install --user pre-commit" -ForegroundColor Green
            $doPip = Read-Host "  Install now? (y/N)"
            if ($doPip -match '^[Yy]$') { pip install --user pre-commit }
        } elseif (Get-Command pipx -ErrorAction SilentlyContinue) {
            Write-Host "  Install with: pipx install pre-commit" -ForegroundColor Green
            $doPipx = Read-Host "  Install now via pipx? (y/N)"
            if ($doPipx -match '^[Yy]$') { pipx install pre-commit }
        } else {
            Write-Host "  [!] No pip/pipx found. Install Python first, or see: https://pre-commit.com/#install" -ForegroundColor Red
            Pause-Console
            return
        }
    }

    if (-not (Get-Command pre-commit -ErrorAction SilentlyContinue)) {
        Write-Host "[i] pre-commit installed but not on PATH yet. Restart your terminal and re-run this option." -ForegroundColor Yellow
        Pause-Console
        return
    }

    $configPath = Join-Path (Get-Location) ".pre-commit-config.yaml"
    if (Test-Path $configPath) {
        Write-Host "[+] .pre-commit-config.yaml already exists in this repo." -ForegroundColor Green
    } else {
        Write-Host "--> Writing a sensible default .pre-commit-config.yaml..." -ForegroundColor Cyan
        @"
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: check-merge-conflict
"@ | Set-Content -Path $configPath -Encoding UTF8
        Write-Host "[+] .pre-commit-config.yaml created." -ForegroundColor Green
        Write-WizardActionLog "Created .pre-commit-config.yaml"
    }

    Write-Host "--> Activating git hook (pre-commit install)..." -ForegroundColor Cyan
    pre-commit install
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] Pre-commit hooks are now active for this repo." -ForegroundColor Green
        Write-WizardActionLog "pre-commit hooks activated"
    } else {
        Write-Host "[!] Failed to activate hooks. Check the output above." -ForegroundColor Red
    }
    Pause-Console
}

# ==============================================================================
# BONUS TOOLS
# ==============================================================================
function Show-BonusToolsMenu {
    while ($true) {
        Show-Header
        Write-Host "BONUS TOOLS`n" -ForegroundColor Yellow
        Write-Host "  [1] lazygit - full terminal UI for git (stage/branch/stash visually)" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-1]"
        switch ($c) {
            "1" {
                Show-Header
                if (Get-Command lazygit -ErrorAction SilentlyContinue) {
                    Write-Host "--> Launching lazygit..." -ForegroundColor Cyan
                    Write-Host "    (Inside lazygit: press 'q' to quit and return here.)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    lazygit
                } else {
                    Write-Host "[i] 'lazygit' is not installed." -ForegroundColor Yellow
                    Install-ToolViaWinget -Tool "lazygit"
                    Pause-Console
                }
            }
            "0" { return }
        }
    }
}

function Show-ToolStackManagerMenu {
    while ($true) {
        Show-Header
        Write-Host "TOOL STACK MANAGER`n" -ForegroundColor Yellow
        Write-Host "Everything about the external tools git-wizard depends on or extends.`n" -ForegroundColor Cyan
        Write-Host "  [1] Verify / Install Tools (gh, glab, delta, lazygit via winget)" -ForegroundColor Green
        Write-Host "  [2] Check Tool Stack Versions" -ForegroundColor Green
        Write-Host "  [3] Check for Tool Updates (winget)" -ForegroundColor Green
        Write-Host "  [4] Bonus Tools (lazygit)" -ForegroundColor Green
        Write-Host "  [0] Back to Main Menu" -ForegroundColor Green
        Write-Host "`n===================================================================="
        $c = Read-Host "Select choice [0-4]"
        switch ($c) {
            "1" { Test-OptionalToolsFull }
            "2" { Show-ToolStackVersions }
            "3" { Show-ToolStackUpdates }
            "4" { Show-BonusToolsMenu }
            "0" { return }
        }
    }
}
