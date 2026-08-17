# ==============================================================================
# TOOL NAME:    git-wizard.ps1 (Windows Master Orchestrator V2.1 - Gold Standard)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master orchestrator loading Git-Wizard Windows modules with
#               global scope dot-sourcing and verbose import debugging.
# NEW IN V2.0:  Beginner/Advanced modes, Module 5 (Team & OSS Collaboration),
#               Dry-Run Mode, Safety/Backup Engine, Tool Verification,
#               Tool Action History, Live Sync Status Indicator.
# NEW IN V2.1:  Terminal hygiene (alternate screen buffer, guaranteed restore
#               on exit/Ctrl+C — matches the Linux side's fix for scrollback
#               pollution), "0" = Back/Cancel convention across every menu.
# ==============================================================================

# Force GIT_PAGER=cat globally in session to prevent pager prompts
$env:GIT_PAGER = "cat"

# ==============================================================================
# TERMINAL HYGIENE — scrollback clearing + guaranteed cursor restoration
# ------------------------------------------------------------------------------
# NOTE (V2.2): earlier versions tried using the true alternate screen buffer
# (ESC[?1049h/l), matching the Linux side. On Windows this turned out to
# conflict with Write-Host -ForegroundColor: once an app takes manual VT
# control of the screen via the alt-buffer, ConPTY/Windows Terminal stops
# reliably forwarding the legacy SetConsoleTextAttribute-based color calls
# into it, so everything rendered in default white/gray. The alt-buffer
# approach and this script's coloring model don't mix reliably on Windows,
# so it's dropped. Instead: Clear-Host (as before) + ESC[3J to also wipe
# the terminal's scrollback history, without ever leaving the main buffer —
# this keeps legacy color rendering intact while still stopping old menu
# frames from stacking up when you scroll back.
# ==============================================================================
$Global:ESC = [char]27   # Use [char]27 instead of `e — `e is only recognized in PowerShell 6+ (pwsh.exe).
                         # On Windows PowerShell 5.1 (powershell.exe), `e is dropped and prints as literal text.

function Enter-AltScreen {
    # Kept for compatibility with existing calls elsewhere in the script.
    # No longer switches buffers — see note above. Just clears scrollback.
    try { [Console]::Out.Write("$ESC[3J") } catch { }
    Clear-Host
}
function Restore-Terminal {
    try { [Console]::CursorVisible = $true } catch { }
    try { [Console]::ResetColor() } catch { }
}

Enter-AltScreen

# Locate Script Directory & File Path strictly
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = Get-Location }

$TargetPs1Path = Join-Path $ScriptDir "git-wizard.ps1"
$TargetRepoDir = (Get-Location).Path

# --- Config / Action Log Paths ---
$ConfigDir  = Join-Path $env:USERPROFILE ".git-wizard"
$ConfigFile = Join-Path $ConfigDir "config.json"
$ActionLog  = Join-Path $ConfigDir "actions.log"
if (-not (Test-Path $ConfigDir)) { New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $ActionLog)) { New-Item -Path $ActionLog -ItemType File -Force | Out-Null }

# --- Global Runtime State (loaded from config, can be toggled in-session) ---
$Global:WizardMode      = ""       # "beginner" | "advanced"
$Global:DryRun          = $false
$Global:AutoSyncCheck   = $false
$Global:SyncDetailLevel = "standard"  # minimal | standard | full
$Global:GlobalCliEnabled = $false

# --- Global Function Registration & Debugging ---
$SubModules = @("identity-engine.ps1", "repo-engine.ps1", "branch-engine.ps1", "commit-engine.ps1", "team-engine.ps1", "vcs-engine.ps1", "toolstack-engine.ps1")
$LoadErrors = @()

foreach ($Mod in $SubModules) {
    # Check current directory
    $Path1 = Join-Path $ScriptDir $Mod
    # Check parent directory (if running from root vs /modules)
    $Path2 = Join-Path (Join-Path $ScriptDir "modules") $Mod

    $ResolvedPath = $null
    if (Test-Path $Path1) { $ResolvedPath = $Path1 }
    elseif (Test-Path $Path2) { $ResolvedPath = $Path2 }

    if ($ResolvedPath) {
        try {
            Unblock-File -Path $ResolvedPath -ErrorAction SilentlyContinue
            # Dot-source into Global Scope explicitly
            . $ResolvedPath
        } catch {
            $LoadErrors += "Failed to dot-source $ResolvedPath : $_"
        }
    } else {
        $LoadErrors += "Could not locate '$Mod' at '$Path1' or '$Path2'"
    }
}

# ==============================================================================
# CONFIG PERSISTENCE
# ==============================================================================
function Load-WizardConfig {
    if (Test-Path $ConfigFile) {
        try {
            $cfg = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
            if ($cfg.WizardMode)    { $Global:WizardMode    = $cfg.WizardMode }
            if ($null -ne $cfg.DryRun)        { $Global:DryRun        = [bool]$cfg.DryRun }
            if ($null -ne $cfg.AutoSyncCheck) { $Global:AutoSyncCheck = [bool]$cfg.AutoSyncCheck }
            if ($cfg.SyncDetailLevel) { $Global:SyncDetailLevel = $cfg.SyncDetailLevel }
            if ($cfg.UpdateRepo)      { $Global:UpdateRepo      = $cfg.UpdateRepo }
            if ($cfg.LastUpdateCheck) { $Global:LastUpdateCheck = $cfg.LastUpdateCheck }
            if ($null -ne $cfg.GlobalCliEnabled) { $Global:GlobalCliEnabled = [bool]$cfg.GlobalCliEnabled }
        } catch {
            # Corrupt config - ignore and fall back to defaults, will be rewritten on next save
        }
    }
}

function Save-WizardConfig {
    $cfg = [PSCustomObject]@{
        WizardMode       = $Global:WizardMode
        DryRun           = $Global:DryRun
        AutoSyncCheck    = $Global:AutoSyncCheck
        SyncDetailLevel  = $Global:SyncDetailLevel
        UpdateRepo       = $Global:UpdateRepo
        LastUpdateCheck  = $Global:LastUpdateCheck
        GlobalCliEnabled = $Global:GlobalCliEnabled
    }
    $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8
}

# ==============================================================================
# TOOL ACTION LOG (this is git-wizard's own history, NOT git's commit history)
# ==============================================================================
function Write-WizardActionLog {
    param([string]$Message)
    $line = "{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $ActionLog -Value $line
}

function Show-ActionHistory {
    Show-Header
    Write-Host "GIT-WIZARD ACTION HISTORY (Last 25 Actions)`n" -ForegroundColor Yellow
    if (-not (Test-Path $ActionLog) -or (Get-Item $ActionLog).Length -eq 0) {
        Write-Host "No actions recorded yet." -ForegroundColor Cyan
    } else {
        Get-Content -Path $ActionLog -Tail 25 | ForEach-Object {
            Write-Host "  - $_" -ForegroundColor Green
        }
    }
    Pause-Console
}

# ==============================================================================
# DRY-RUN WRAPPER
# Every destructive/network git command should be routed through this.
# Usage: Invoke-GitWizard push origin main --force
# ==============================================================================
function Invoke-GitWizard {
    $GitArgs = $args
    $ArgString = ($GitArgs -join ' ')
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would execute: git $ArgString" -ForegroundColor Yellow
        Write-WizardActionLog "DRY-RUN (not executed): git $ArgString"
        return $true
    } else {
        Write-WizardActionLog "EXECUTED: git $ArgString"
        & git @GitArgs
        return ($LASTEXITCODE -eq 0)
    }
}

# ==============================================================================
# SAFETY & BACKUP ENGINE
# Creates a lightweight recovery point before destructive operations.
# ==============================================================================
function New-SafetyBackup {
    param([string]$Reason)

    $IsRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($IsRepo -ne "true") { return }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $TagName = "backup/$Reason-$ts"

    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would create safety backup tag: $TagName" -ForegroundColor Yellow
        return
    }

    $headExists = git rev-parse HEAD 2>$null
    if ($headExists) {
        git tag $TagName HEAD 2>$null | Out-Null
        Write-Host "[+] Safety backup created: $TagName (recover with: git reset --hard $TagName)" -ForegroundColor Green
        Write-WizardActionLog "BACKUP created: $TagName (reason: $Reason)"
    }
}

function Confirm-DestructiveAction {
    param([string]$ActionDesc)

    Write-Host "`n[!] DESTRUCTIVE ACTION: $ActionDesc" -ForegroundColor Red
    if ($Global:WizardMode -eq "beginner") {
        Write-Host "Beginner Mode requires typed confirmation." -ForegroundColor Yellow
        $conf = Read-Host "Type EXACTLY 'yes i understand' to proceed"
        return ($conf -eq "yes i understand")
    } else {
        $conf = Read-Host "Proceed? (y/N)"
        return ($conf -match '^[Yy]$')
    }
}

# ==============================================================================
# NOTE: Tool verification moved to toolstack-engine.ps1 (Test-OptionalToolsFull)
# which offers to install via winget, matching the Linux cross-distro package
# check + offer-to-install flow. This is kept as a thin alias for anything
# still calling the old name.
# ==============================================================================
function Test-OptionalTools {
    if (Get-Command Test-OptionalToolsFull -ErrorAction SilentlyContinue) {
        Test-OptionalToolsFull
    } else {
        Write-Host "[!] toolstack-engine.ps1 not loaded." -ForegroundColor Red
        Pause-Console
    }
}

# ==============================================================================
# HEADER / SYNC STATUS BAR
# ==============================================================================
function Get-SyncStatusLine {
    $IsRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($IsRepo -ne "true") { return "" }

    $Branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $Branch -or $Branch -eq "HEAD") { return "" }

    $FetchOk = $true
    git fetch --quiet 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $FetchOk = $false }

    $Upstream = git rev-parse --abbrev-ref "$Branch@{upstream}" 2>$null
    if (-not $Upstream) {
        return "Sync: $Branch -> no upstream tracking set"
    }

    $Ahead  = (git rev-list --count "$Upstream..$Branch" 2>$null)
    $Behind = (git rev-list --count "$Branch..$Upstream" 2>$null)
    if (-not $Ahead)  { $Ahead = 0 }
    if (-not $Behind) { $Behind = 0 }

    $StatusOut = git status --porcelain 2>$null
    $Modified  = @($StatusOut | Where-Object { $_ -notmatch '^\?\?' }).Count
    $Untracked = @($StatusOut | Where-Object { $_ -match '^\?\?' }).Count
    $Dirty     = $Modified + $Untracked

    if ($Dirty -gt 0 -and [int]$Behind -gt 0) {
        $icon = "[RED]"; $statusText = "High risk - uncommitted work AND remote has moved on"
    } elseif ([int]$Behind -gt 0) {
        $icon = "[ORANGE]"; $statusText = "Behind - pull recommended"
    } elseif ([int]$Ahead -gt 0) {
        $icon = "[YELLOW]"; $statusText = "Ahead - push when ready"
    } elseif ($Dirty -gt 0) {
        $icon = "[YELLOW]"; $statusText = "Uncommitted local changes"
    } else {
        $icon = "[OK]"; $statusText = "Fully synced"
    }

    $lines = @()
    $lines += "Sync $Branch`: $icon $statusText  (ahead $Ahead / behind $Behind, $Upstream)"
    $lines += $(if ($FetchOk) { "Remote reachable - data is current" } else { "Last fetch failed - numbers above may be stale (check network)" })

    if ($Dirty -gt 0) {
        $lines += "Modified: $Modified   Untracked: $Untracked - not yet committed or pushed"
    }
    if (($Branch -eq "main" -or $Branch -eq "master") -and ($Dirty -gt 0 -or [int]$Ahead -gt 0)) {
        $lines += "Uncommitted/unpushed work directly on '$Branch' - consider a feature branch (Module 5)"
    }

    if ($Global:SyncDetailLevel -eq "standard" -or $Global:SyncDetailLevel -eq "full") {
        $StashCount = @(git stash list 2>$null).Count
        if ($StashCount -gt 0) { $lines += "$StashCount stash(es) saved - don't forget these" }
        $LastCommitRel = git log -1 --format='%cr' 2>$null
        if ($LastCommitRel) { $lines += "Last commit: $LastCommitRel" }
    }

    if ($Global:SyncDetailLevel -eq "full" -and [int]$Behind -gt 0) {
        $mergeBase = git merge-base $Branch $Upstream 2>$null
        $treeCheck = git merge-tree $mergeBase $Branch $Upstream 2>$null
        if ($treeCheck -match "^<{7} ") {
            $lines += "Pulling may CONFLICT - review before Safe Update Sync"
        } else {
            $lines += "Pull will likely be clean (no conflict markers detected)"
        }
    }

    $lines += "Detail Level: $Global:SyncDetailLevel  (Settings > option 3 to change)"
    return ($lines -join "`n")
}

function Show-Header {
    Clear-Host
    Write-Host @"
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
"@ -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "         GIT-WIZARD ULTIMATE - GITHUB WORKFLOW ENGINE               " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "GitHub  : https://github.com/ali4210" -ForegroundColor Yellow
    Write-Host "Active Repository Context: $TargetRepoDir" -ForegroundColor Yellow
    Write-Host "Mode: $Global:WizardMode   Dry-Run: $Global:DryRun   Auto-Sync: $Global:AutoSyncCheck  [Settings > option 3 to toggle]" -ForegroundColor Yellow
    if ($Global:UpdateNotice) { Write-Host $Global:UpdateNotice -ForegroundColor Green }

    if ($Global:AutoSyncCheck) {
        $statusLine = Get-SyncStatusLine
        if ($statusLine) {
            Write-Host $statusLine -ForegroundColor Green
        }
    }
    Write-Host ""

    # Print Debug Messages if sub-module loading failed
    if ($LoadErrors.Count -gt 0) {
        Write-Host "DEBUG / IMPORT WARNINGS:" -ForegroundColor Red
        foreach ($Err in $LoadErrors) {
            Write-Host "  [!] $Err" -ForegroundColor Red
        }
        Write-Host ""
    }
}
function Pause-Console {
    Write-Host ""
    Read-Host "Press [ENTER] to return to menu..."
}

function Show-UpToDateCelebration {
    Write-Host @"
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
"@ -ForegroundColor Green

    Write-Host "Everything up-to-date! Code is safe and synced on GitHub!" -ForegroundColor Green
}

# ==============================================================================
# FIRST-RUN MODE WRAPPER
# ==============================================================================
function Select-WizardMode {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "         WELCOME TO GIT-WIZARD - CHOOSE YOUR MODE                   " -ForegroundColor Cyan
    Write-Host "====================================================================`n" -ForegroundColor Cyan
    Write-Host "  [1] Beginner Mode" -ForegroundColor Green
    Write-Host "      - Simplified menus, extra typed confirmations on destructive actions"
    Write-Host "      - Dry-Run suggested by default, automatic safety backups`n"
    Write-Host "  [2] Advanced Mode" -ForegroundColor Green
    Write-Host "      - Full menu access, faster confirmations, all Module 5 workflows visible"
    Write-Host "      - Safety backups still run automatically (cheap insurance)`n"
    Write-Host "You can change this anytime from the Main Menu (Settings)." -ForegroundColor Cyan
    Write-Host "====================================================================`n" -ForegroundColor Cyan

    $ModeChoice = Read-Host "Select mode [1-2]"
    switch ($ModeChoice) {
        "1" { $Global:WizardMode = "beginner"; $Global:DryRun = $true }
        "2" { $Global:WizardMode = "advanced"; $Global:DryRun = $false }
        default { $Global:WizardMode = "beginner"; $Global:DryRun = $true }
    }
    Save-WizardConfig
    Write-WizardActionLog "Mode set to: $Global:WizardMode"
}

# ------------------------------------------------------------------------------
# Arrow-key single-choice selector — used so "toggles" require explicit
# selection instead of taking effect the instant the menu option is clicked
# (matches the Linux-side fix for the same complaint).
# ------------------------------------------------------------------------------
function Select-FromOptions {
    param(
        [string]$Prompt,
        [string[]]$Labels,   # display text per option
        [string[]]$Values    # underlying value returned per option (same order)
    )
    $Selected = 0
    while ($true) {
        Show-Header
        Write-Host "$Prompt`n" -ForegroundColor Yellow
        for ($i = 0; $i -lt $Labels.Count; $i++) {
            if ($i -eq $Selected) {
                Write-Host "  ->  $($Labels[$i])" -ForegroundColor Green
            } else {
                Write-Host "      $($Labels[$i])" -ForegroundColor Gray
            }
        }
        Write-Host "`n[UP/DOWN to navigate, ENTER to select, Q to cancel]" -ForegroundColor Cyan
        $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($Key.VirtualKeyCode) {
            38 { if ($Selected -gt 0) { $Selected-- } else { $Selected = $Labels.Count - 1 } }
            40 { if ($Selected -lt ($Labels.Count - 1)) { $Selected++ } else { $Selected = 0 } }
            13 { return $Values[$Selected] }
            81 { return $null }
        }
    }
}

function Select-WizardModeInteractive {
    $result = Select-FromOptions -Prompt "SELECT MODE (current: $Global:WizardMode)" `
        -Labels @("Beginner - simplified menus, typed confirmations", "Advanced - full menu access, faster confirmations") `
        -Values @("beginner", "advanced")
    if (-not $result) { return }
    $Global:WizardMode = $result
    Save-WizardConfig
    Write-WizardActionLog "Mode switched to: $Global:WizardMode"
    Write-Host "[+] Switched to $Global:WizardMode mode." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Select-DryRunInteractive {
    $result = Select-FromOptions -Prompt "DRY-RUN MODE (current: $Global:DryRun)" `
        -Labels @("Off - commands actually run", "On - commands are only PRINTED, nothing executes") `
        -Values @("false", "true")
    if (-not $result) { return }
    $Global:DryRun = [bool]::Parse($result)
    Save-WizardConfig
    Write-WizardActionLog "Dry-Run set to: $Global:DryRun"
    Write-Host "[+] Dry-Run mode is now: $Global:DryRun" -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Select-AutoSyncInteractive {
    $result = Select-FromOptions -Prompt "SYNC PANEL (current: $Global:AutoSyncCheck)" `
        -Labels @("Off - no sync panel shown in header", "On - sync panel shown on every screen") `
        -Values @("false", "true")
    if (-not $result) { return }
    $Global:AutoSyncCheck = [bool]::Parse($result)
    Save-WizardConfig
    Write-WizardActionLog "Auto-Sync panel set to: $Global:AutoSyncCheck"
    Write-Host "[+] Auto-Sync panel is now: $Global:AutoSyncCheck" -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Select-SyncDetailLevelInteractive {
    $result = Select-FromOptions -Prompt "SYNC PANEL DETAIL LEVEL (current: $Global:SyncDetailLevel)" `
        -Labels @(
            "Minimal - sync tier, fetch reachability, modified/untracked split",
            "Standard - adds stash count + last commit freshness",
            "Full - adds conflict-risk preview before pulling (slower)"
        ) `
        -Values @("minimal", "standard", "full")
    if (-not $result) { return }
    $Global:SyncDetailLevel = $result
    Save-WizardConfig
    Write-WizardActionLog "Sync Panel Detail Level set to: $Global:SyncDetailLevel"
    Write-Host "[+] Sync Panel Detail Level is now: $Global:SyncDetailLevel" -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Show-GitHubSyncMenu {
    while ($true) {
        Show-Header
        Write-Host "GITHUB SYNC - Panel Settings`n" -ForegroundColor Yellow
        Write-Host "  [1] Enable / Disable Sync Panel (current: $Global:AutoSyncCheck)" -ForegroundColor Green
        Write-Host "  [2] Set Detail Level (current: $Global:SyncDetailLevel)" -ForegroundColor Green
        Write-Host "  [3] Preview Panel Now" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-3]"
        switch ($c) {
            "1" { Select-AutoSyncInteractive }
            "2" { Select-SyncDetailLevelInteractive }
            "3" {
                Show-Header
                Write-Host "LIVE PREVIEW`n" -ForegroundColor Yellow
                if (-not $Global:AutoSyncCheck) {
                    Write-Host "[!] Panel is currently OFF (option 1)." -ForegroundColor Red
                } else {
                    $p = Get-SyncStatusLine
                    if ($p) { Write-Host $p } else { Write-Host "[i] Not inside a Git repository." -ForegroundColor Yellow }
                }
                Pause-Console
            }
            "0" { return }
        }
    }
}

# --- Non-Git Repository Verification & Setup ---
function Test-GitRepository {
    $IsRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($IsRepo -ne "true") {
        Clear-Host    # <── Just clear the screen, NO Show-Header here

        # ─── DEMO ASCII ART — Replace everything between INITART markers with yours ───
        Write-Host @'
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


'@ -ForegroundColor Cyan

        Write-Host "  Directory: $TargetRepoDir`n" -ForegroundColor Yellow
        Write-Host "  Available Actions:" -ForegroundColor Cyan
        Write-Host "  [1] Initialize a new Git Repository here (git init)" -ForegroundColor Green
        Write-Host "  [2] Enable Universal Global CLI (Install 'git-wizard' system-wide)" -ForegroundColor Yellow
        Write-Host "  [0] Exit" -ForegroundColor Green
        Write-Host "`n  ====================================================================" -ForegroundColor Cyan

        $NonRepoChoice = Read-Host "  Select choice [0-2]"
        switch ($NonRepoChoice) {
            "1" {
                Write-Host ""
                Write-Host "  -> Initializing Git repository..." -ForegroundColor Cyan
                Invoke-GitWizard init
                Invoke-GitWizard branch -M main
                Write-Host "  [+] Initialized empty Git repository in $TargetRepoDir!" -ForegroundColor Green
                Write-Host "  [+] Entering main menu now..." -ForegroundColor Green
                Write-WizardActionLog "Initialized new git repo at $TargetRepoDir"
                Pause-Console
            }
            "2" { Enable-GlobalCLI }
            "0" { exit 0 }
            default { Write-Host "  Invalid choice! Please enter 0, 1, or 2." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}
# --- Enable Universal Global CLI (OS Selector) ---
function Enable-GlobalCLI {
    Show-Header
    Write-Host "UNIVERSAL GLOBAL CLI INSTALLER`n" -ForegroundColor Yellow
    Write-Host "Which operating system do you want to enable 'git-wizard' for?`n" -ForegroundColor Cyan
    Write-Host "  [1] Windows (PowerShell / CMD)" -ForegroundColor Green
    Write-Host "  [2] Linux (Debian, RHEL, CentOS, etc.)" -ForegroundColor Green
    Write-Host "  [3] macOS" -ForegroundColor Green
    Write-Host "  [0] Back" -ForegroundColor Green
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $OsChoice = Read-Host "Select choice [0-3]"
    switch ($OsChoice) {
        "1" { Enable-GlobalCLI-Windows }
        "2" {
			Write-Host "`n[i] Linux installation must be run from within Linux itself." -ForegroundColor Yellow
			Write-Host "    On your Linux machine, run:  ./autorun.sh  (from the repo root)" -ForegroundColor White
			Write-Host "    Then select Module 6 -> Enable Universal Global CLI -> choose Linux.`n" -ForegroundColor White
			Pause-Console
		}
		"3" {
			Write-Host "`n[i] macOS installation must be run from within macOS itself." -ForegroundColor Yellow
			Write-Host "    On your Mac, run:  ./autorun.sh  (from the repo root)" -ForegroundColor White
			Write-Host "    Then select Module 6 -> Enable Universal Global CLI -> choose macOS.`n" -ForegroundColor White
			Pause-Console
		}
        "0" { return }
        default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}

# --- Windows Sub-Menu (PowerShell / CMD / Both) ---
function Enable-GlobalCLI-Windows {
    Show-Header
    Write-Host "WINDOWS GLOBAL CLI INSTALLER`n" -ForegroundColor Yellow
    Write-Host "Which terminal(s) do you want to enable 'git-wizard' for?`n" -ForegroundColor Cyan
    Write-Host "  [1] PowerShell only" -ForegroundColor Green
    Write-Host "  [2] CMD only" -ForegroundColor Green
    Write-Host "  [3] Both PowerShell and CMD" -ForegroundColor Green
    Write-Host "  [0] Back" -ForegroundColor Green
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $TermChoice = Read-Host "Select choice [0-3]"
    switch ($TermChoice) {
        "1" { Enable-GlobalPowerShellCLI }
        "2" { Enable-GlobalCmdCLI }
        "3" { Enable-GlobalPowerShellCLI; Enable-GlobalCmdCLI }
        "0" { return }
        default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}

# --- Enable Universal Global CLI for PowerShell ---
function Enable-GlobalPowerShellCLI {
    Write-Host "`n--> Configuring PowerShell Profile for global 'git-wizard' execution..." -ForegroundColor Cyan

    if (-not (Test-Path $PROFILE)) {
        New-Item -Path $PROFILE -Type File -Force | Out-Null
    }

    $ProfilePath = $PROFILE
    $GlobalFunctionConfig = "function git-wizard { powershell.exe -ExecutionPolicy Bypass -File '$TargetPs1Path' }"

    if (-not (Get-Content -Path $ProfilePath -ErrorAction SilentlyContinue | Select-String -Pattern "function git-wizard")) {
        Add-Content -Path $ProfilePath -Value "`n# --- Git-Wizard Ultimate Global Shortcut ---`n$GlobalFunctionConfig"
        Write-Host "[+] 'git-wizard' function added to your PowerShell Profile!" -ForegroundColor Green
    } else {
        Write-Host "[+] 'git-wizard' is already configured in your PowerShell Profile." -ForegroundColor Green
    }

    Write-Host "`n====================================================================" -ForegroundColor Cyan
    Write-Host "[+] GIT-WIZARD IS NOW INSTALLED GLOBALLY FOR POWERSHELL!" -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "HOW TO USE FROM ANY WINDOWS FOLDER (PowerShell):" -ForegroundColor Cyan
    Write-Host "  1. Open ANY PowerShell window or Windows Terminal." -ForegroundColor White
    Write-Host "  2. Simply type: git-wizard" -ForegroundColor Green
    Write-Host "====================================================================`n" -ForegroundColor Cyan
    $Global:GlobalCliEnabled = $true
    Save-WizardConfig
    Pause-Console
}

# --- Enable Universal Global CLI for CMD ---
function Enable-GlobalCmdCLI {
    Write-Host "`n--> Configuring CMD environment for global 'git-wizard' execution..." -ForegroundColor Cyan

    $GlobalDir = Join-Path $env:USERPROFILE ".git-wizard"
    $WrapperPath = Join-Path $GlobalDir "git-wizard.cmd"

    if (-not (Test-Path $GlobalDir)) {
        New-Item -Path $GlobalDir -ItemType Directory -Force | Out-Null
    }

    $WrapperContent = "@echo off`r`npowershell.exe -NoExit -ExecutionPolicy Bypass -File `"$TargetPs1Path`" %*"
    Set-Content -Path $WrapperPath -Value $WrapperContent -Encoding ASCII -Force
    Write-Host "[+] Wrapper created at $WrapperPath" -ForegroundColor Green

    # Add GlobalDir to User PATH permanently, without shelling out to setx
    $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($CurrentUserPath -notlike "*$GlobalDir*") {
        $NewUserPath = if ([string]::IsNullOrEmpty($CurrentUserPath)) { $GlobalDir } else { "$CurrentUserPath;$GlobalDir" }
        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
        Write-Host "[+] '$GlobalDir' added to your User PATH!" -ForegroundColor Green
    } else {
        Write-Host "[+] '$GlobalDir' is already present in your User PATH." -ForegroundColor Green
    }

    Write-Host "`n====================================================================" -ForegroundColor Cyan
    Write-Host "[+] GIT-WIZARD IS NOW INSTALLED GLOBALLY FOR CMD!" -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "HOW TO USE FROM ANY WINDOWS FOLDER (CMD):" -ForegroundColor Cyan
    Write-Host "  1. Close and reopen a NEW CMD window (PATH changes need a fresh session)." -ForegroundColor White
    Write-Host "  2. Simply type: git-wizard" -ForegroundColor Green
    Write-Host "====================================================================`n" -ForegroundColor Cyan
    $Global:GlobalCliEnabled = $true
    Save-WizardConfig
    Pause-Console
}

# --- Disable Universal Global CLI (removes PowerShell profile + CMD wrapper/PATH) ---
function Disable-GlobalCLI {
    Show-Header
    Write-Host "DISABLE UNIVERSAL GLOBAL CLI`n" -ForegroundColor Yellow

    if (Test-Path $PROFILE) {
        $content = Get-Content -Path $PROFILE
        $filtered = $content | Where-Object {
            $_ -notmatch 'function git-wizard' -and $_ -notmatch 'Git-Wizard Ultimate Global Shortcut'
        }
        Set-Content -Path $PROFILE -Value $filtered
        Write-Host "[+] Removed 'git-wizard' function from your PowerShell Profile." -ForegroundColor Green
    }

    $GlobalDir = Join-Path $env:USERPROFILE ".git-wizard"
    $WrapperPath = Join-Path $GlobalDir "git-wizard.cmd"
    if (Test-Path $WrapperPath) {
        Remove-Item -Path $WrapperPath -Force
        Write-Host "[+] Removed CMD wrapper at $WrapperPath" -ForegroundColor Green
    }

    $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($CurrentUserPath -like "*$GlobalDir*") {
        $NewUserPath = ($CurrentUserPath -split ';' | Where-Object { $_ -ne $GlobalDir }) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
        Write-Host "[+] Removed '$GlobalDir' from your User PATH." -ForegroundColor Green
    }

    $Global:GlobalCliEnabled = $false
    Save-WizardConfig
    Write-WizardActionLog "Global CLI disabled permanently"
    Write-Host "`n[+] Global CLI has been disabled. Existing terminal sessions may need a restart to fully clear it." -ForegroundColor Green
    Pause-Console
}

# --- Settings Menu ---
function Show-SettingsMenu {
    while ($true) {
        Show-Header
        Write-Host "SETTINGS`n" -ForegroundColor Yellow
        Write-Host "  [1] Switch Mode (current: $Global:WizardMode)" -ForegroundColor Green
        Write-Host "  [2] Toggle Dry-Run (current: $Global:DryRun)" -ForegroundColor Green
        Write-Host "  [3] GitHub/GitLab Sync Panel Settings (on/off, detail level)" -ForegroundColor Green
        Write-Host "  [4] View Tool Action History" -ForegroundColor Green
        Write-Host "  [5] Check for git-wizard Updates (source: $(if ($Global:UpdateRepo) { $Global:UpdateRepo } else { 'not set' }))" -ForegroundColor Green
        Write-Host "  [6] Set Update Source Repo" -ForegroundColor Green
        Write-Host "  [7] Create git-wizard Checkpoint Now (manual backup point)" -ForegroundColor Green
        Write-Host "  [8] Update git-wizard Now" -ForegroundColor Green
        Write-Host "  [9] Rollback git-wizard to Previous Version" -ForegroundColor Green
        Write-Host "  [10] Disable Universal Global CLI Permanently (current: $Global:GlobalCliEnabled)" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $SChoice = Read-Host "Select choice [0-10]"
        switch ($SChoice) {
            "1" { Select-WizardModeInteractive }
            "2" { Select-DryRunInteractive }
            "3" { Show-GitHubSyncMenu }
            "4" { Show-ActionHistory }
            "5" { Show-Header; Test-ForUpdates; Pause-Console }
            "6" { Set-UpdateRepo }
            "7" { New-ToolCheckpoint }
            "8" { Update-GitWizardSelf }
            "9" { Restore-GitWizardRollback }
            "10" { Disable-GlobalCLI }
            "0" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# --- Load config & run first-time mode wrapper if needed ---
Load-WizardConfig
if (-not $Global:WizardMode) {
    Select-WizardMode
}

# --- Non-blocking auto update check (cached for 24h) ---
if ($Global:UpdateRepo) {
    $needsCheck = $true
    if ($Global:LastUpdateCheck) {
        try {
            $elapsed = (Get-Date) - [datetime]$Global:LastUpdateCheck
            if ($elapsed.TotalSeconds -le 86400) { $needsCheck = $false }
        } catch { $needsCheck = $true }
    }
    if ($needsCheck -and (Get-Command Test-ForUpdates -ErrorAction SilentlyContinue)) {
        Test-ForUpdates -Silent
    }
}

# ==============================================================================
# MAIN MASTER LOOP — wrapped in try/finally so the terminal is ALWAYS restored
# (normal Exit, Ctrl+C, or an unhandled error all unwind through here).
# ==============================================================================
try {
    while ($true) {
        Test-GitRepository
        Show-Header
        Write-Host "Main Capabilities Suite:`n" -ForegroundColor Yellow
        Write-Host "  [1] Identity and SSH Manager" -ForegroundColor Green
        Write-Host "      Your Git name/email, SSH keys, and the remote URL this repo points to." -ForegroundColor Cyan
        Write-Host "  [2] Repository and Smart Push Engine" -ForegroundColor Green
        Write-Host "      Init, status, quick push, reset/undo (incl. Force Sync), and conflict resolution." -ForegroundColor Cyan
        Write-Host "  [3] Advanced Branch Manager" -ForegroundColor Green
        Write-Host "      Create, switch, list, and delete branches." -ForegroundColor Cyan
        Write-Host "  [4] Conventional Commit Assistant" -ForegroundColor Green
        Write-Host "      Builds a properly formatted commit message (feat/fix/docs/etc)." -ForegroundColor Cyan
        Write-Host "  [5] Team and Open-Source Collaboration" -ForegroundColor Yellow
        Write-Host "      Solo, private-team, and fork-based contribution workflows." -ForegroundColor Cyan
        Write-Host "  [6] Git Hosting Power Tools (GitHub/GitLab)" -ForegroundColor Yellow
        Write-Host "      Issues, PRs/MRs, Releases, Actions/Pipelines, Gists/Snippets, Repo Admin, Delta Diff Suite." -ForegroundColor Cyan
        Write-Host "  [7] Enable Universal Global CLI (Run 'git-wizard' from ANY Windows Folder)" -ForegroundColor Yellow
        Write-Host "  [8] Tool Stack Manager" -ForegroundColor Yellow
        Write-Host "      Verify/install tools, versions, updates, bonus tools, pre-commit hooks." -ForegroundColor Cyan
        Write-Host "  [9] Settings (Mode / Dry-Run / Sync Panel / Updates / Action History)" -ForegroundColor Green
        Write-Host "  [0] Exit" -ForegroundColor Green
        Write-Host "`n====================================================================" -ForegroundColor Cyan

        $mainChoice = Read-Host "Enter choice [0-9]"

        switch ($mainChoice) {
            "1" {
                if (Get-Command Manage-Identity -ErrorAction SilentlyContinue) { Manage-Identity }
                elseif (Get-Command Manage-GitIdentity -ErrorAction SilentlyContinue) { Manage-GitIdentity }
                else { Write-Host "[!] Module function for Identity missing." -ForegroundColor Red; Pause-Console }
            }
            "2" {
                if (Get-Command Manage-Repo -ErrorAction SilentlyContinue) { Manage-Repo }
                elseif (Get-Command Manage-GitRepo -ErrorAction SilentlyContinue) { Manage-GitRepo }
                else { Write-Host "[!] Module function for Repository missing." -ForegroundColor Red; Pause-Console }
            }
            "3" {
                if (Get-Command Manage-Branches -ErrorAction SilentlyContinue) { Manage-Branches }
                elseif (Get-Command Manage-GitBranches -ErrorAction SilentlyContinue) { Manage-GitBranches }
                else { Write-Host "[!] Module function for Branches missing." -ForegroundColor Red; Pause-Console }
            }
            "4" {
                if (Get-Command Craft-Commit -ErrorAction SilentlyContinue) { Craft-Commit }
                elseif (Get-Command Craft-ConventionalCommit -ErrorAction SilentlyContinue) { Craft-ConventionalCommit }
                else { Write-Host "[!] Module function for Commit Assistant missing." -ForegroundColor Red; Pause-Console }
            }
            "5" {
                if (Get-Command Show-Module5Menu -ErrorAction SilentlyContinue) { Show-Module5Menu }
                else { Write-Host "[!] team-engine.ps1 not found/loaded - Module 5 unavailable." -ForegroundColor Red; Pause-Console }
            }
            "6" {
                if (Get-Command Show-GitHostingPowerToolsMenu -ErrorAction SilentlyContinue) { Show-GitHostingPowerToolsMenu }
                else { Write-Host "[!] vcs-engine.ps1 not found/loaded - Power Tools unavailable." -ForegroundColor Red; Pause-Console }
            }
            "7" {
                if ($Global:GlobalCliEnabled) {
                    Write-Host "`nGlobal CLI is already enabled." -ForegroundColor Cyan
                    Write-Host "  [1] Re-run setup (repair profile/PATH)   [2] Disable it   [0] Cancel"
                    $gc = Read-Host "Choice [0-2]"
                    switch ($gc) {
                        "1" { Enable-GlobalCLI }
                        "2" { Disable-GlobalCLI }
                        default { }
                    }
                } else {
                    Enable-GlobalCLI
                }
            }
            "8" {
                if (Get-Command Show-ToolStackManagerMenu -ErrorAction SilentlyContinue) { Show-ToolStackManagerMenu }
                else { Write-Host "[!] toolstack-engine.ps1 not found/loaded - Tool Stack Manager unavailable." -ForegroundColor Red; Pause-Console }
            }
            "9" { Show-SettingsMenu }
            "0" {
                Write-Host "`nKeep building amazing open-source software! Goodbye!" -ForegroundColor Green
                exit 0
            }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}
finally {
    Restore-Terminal
}
