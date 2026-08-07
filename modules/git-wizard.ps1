# ==============================================================================
# TOOL NAME:    git-wizard.ps1 (Windows Master Orchestrator V2.0 - Gold Standard)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master orchestrator loading Git-Wizard Windows modules with
#               global scope dot-sourcing and verbose import debugging.
# NEW IN V2.0:  Beginner/Advanced modes, Module 5 (Team & OSS Collaboration),
#               Dry-Run Mode, Safety/Backup Engine, Tool Verification,
#               Tool Action History, Live Sync Status Indicator.
# ==============================================================================

# Force GIT_PAGER=cat globally in session to prevent pager prompts
$env:GIT_PAGER = "cat"

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
$Global:WizardMode    = ""       # "beginner" | "advanced"
$Global:DryRun        = $false
$Global:AutoSyncCheck = $false

# --- Global Function Registration & Debugging ---
$SubModules = @("identity-engine.ps1", "repo-engine.ps1", "branch-engine.ps1", "commit-engine.ps1", "team-engine.ps1")
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
        } catch {
            # Corrupt config - ignore and fall back to defaults, will be rewritten on next save
        }
    }
}

function Save-WizardConfig {
    $cfg = [PSCustomObject]@{
        WizardMode    = $Global:WizardMode
        DryRun        = $Global:DryRun
        AutoSyncCheck = $Global:AutoSyncCheck
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
# TOOL VERIFICATION (Windows equivalent of the cross-distro package check)
# ==============================================================================
function Test-OptionalTools {
    Show-Header
    Write-Host "OPTIONAL TOOL VERIFICATION`n" -ForegroundColor Yellow
    $tools = @(
        @{ Name = "gh";    Hint = "winget install --id GitHub.cli"; Purpose = "GitHub CLI - required for Open-Source Contributor Mode (PRs)" },
        @{ Name = "delta"; Hint = "winget install --id dandavison.delta"; Purpose = "Prettier diffs in Repo History Viewer" }
    )
    foreach ($t in $tools) {
        $found = Get-Command $t.Name -ErrorAction SilentlyContinue
        if ($found) {
            Write-Host "  [+] $($t.Name) - installed" -ForegroundColor Green
        } else {
            Write-Host "  [x] $($t.Name) - missing" -ForegroundColor Red
            Write-Host "      Purpose: $($t.Purpose)" -ForegroundColor Cyan
            Write-Host "      Install: $($t.Hint)" -ForegroundColor Green
        }
    }
    Pause-Console
}

# ==============================================================================
# HEADER / SYNC STATUS BAR
# ==============================================================================
function Get-SyncStatusLine {
    $IsRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($IsRepo -ne "true") { return "" }

    $Branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $Branch -or $Branch -eq "HEAD") { return "" }

    git fetch --quiet 2>$null | Out-Null

    $Upstream = git rev-parse --abbrev-ref "$Branch@{upstream}" 2>$null
    if (-not $Upstream) {
        return "Sync: $Branch -> no upstream tracking set"
    }

    $Ahead  = (git rev-list --count "$Upstream..$Branch" 2>$null)
    $Behind = (git rev-list --count "$Branch..$Upstream" 2>$null)
    if (-not $Ahead)  { $Ahead = 0 }
    if (-not $Behind) { $Behind = 0 }

    if ([int]$Ahead -eq 0 -and [int]$Behind -eq 0) {
        return "Sync: $Branch -> Fully synced with $Upstream"
    } else {
        return "Sync: $Branch -> $Ahead ahead / $Behind behind ($Upstream)"
    }
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
    Write-Host "Mode: $Global:WizardMode   Dry-Run: $Global:DryRun   Auto-Sync: $Global:AutoSyncCheck  [Module 5 > option 6 to toggle]" -ForegroundColor Yellow

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

function Toggle-WizardMode {
    if ($Global:WizardMode -eq "beginner") { $Global:WizardMode = "advanced" }
    else { $Global:WizardMode = "beginner" }
    Save-WizardConfig
    Write-WizardActionLog "Mode switched to: $Global:WizardMode"
    Write-Host "[+] Switched to $Global:WizardMode mode." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Toggle-DryRun {
    $Global:DryRun = -not $Global:DryRun
    Save-WizardConfig
    Write-WizardActionLog "Dry-Run toggled to: $Global:DryRun"
    Write-Host "[+] Dry-Run mode is now: $Global:DryRun" -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Toggle-AutoSync {
    $Global:AutoSyncCheck = -not $Global:AutoSyncCheck
    Save-WizardConfig
    Write-WizardActionLog "Auto-Sync indicator toggled to: $Global:AutoSyncCheck"
}

# --- Non-Git Repository Verification & Setup ---
function Test-GitRepository {
    $IsRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($IsRepo -ne "true") {
        Show-Header
        Write-Host "[!] WARNING: '$TargetRepoDir' is NOT a Git repository!`n" -ForegroundColor Red
        Write-Host "Available Actions:" -ForegroundColor Cyan
        Write-Host "  [1] Initialize a new Git Repository here (git init)" -ForegroundColor Green
        Write-Host "  [2] Enable Universal Global CLI (Install 'git-wizard' system-wide)" -ForegroundColor Yellow
        Write-Host "  [3] Exit" -ForegroundColor Green
        Write-Host "`n====================================================================" -ForegroundColor Cyan
        
        $NonRepoChoice = Read-Host "Select choice [1-3]"
        switch ($NonRepoChoice) {
            "1" {
                Invoke-GitWizard init
                Invoke-GitWizard branch -M main
                Write-Host "`n[+] Initialized empty Git repository in $TargetRepoDir!" -ForegroundColor Green
                Pause-Console
            }
			"2" { Enable-GlobalCLI }
            "3" { exit 0 }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
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
    Write-Host "  [4] Back" -ForegroundColor Green
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $OsChoice = Read-Host "Select choice [1-4]"
    switch ($OsChoice) {
        "1" { Enable-GlobalCLI-Windows }
        "2" {
			Write-Host "`n[i] Linux installation must be run from within Linux itself." -ForegroundColor Yellow
			Write-Host "    On your Linux machine, run:  ./autorun.sh  (from the repo root)" -ForegroundColor White
			Write-Host "    Then select Option [5] -> Enable Universal Global CLI -> choose Linux.`n" -ForegroundColor White
			Pause-Console
		}
		"3" {
			Write-Host "`n[i] macOS installation must be run from within macOS itself." -ForegroundColor Yellow
			Write-Host "    On your Mac, run:  ./autorun.sh  (from the repo root)" -ForegroundColor White
			Write-Host "    Then select Option [5] -> Enable Universal Global CLI -> choose macOS.`n" -ForegroundColor White
			Pause-Console
		}
        "4" { return }
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
    Write-Host "  [4] Back" -ForegroundColor Green
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $TermChoice = Read-Host "Select choice [1-4]"
    switch ($TermChoice) {
        "1" { Enable-GlobalPowerShellCLI }
        "2" { Enable-GlobalCmdCLI }
        "3" { Enable-GlobalPowerShellCLI; Enable-GlobalCmdCLI }
        "4" { return }
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
    Pause-Console
}

# --- Settings Menu ---
function Show-SettingsMenu {
    while ($true) {
        Show-Header
        Write-Host "SETTINGS`n" -ForegroundColor Yellow
        Write-Host "  [1] Switch Mode (current: $Global:WizardMode)" -ForegroundColor Green
        Write-Host "  [2] Toggle Dry-Run (current: $Global:DryRun)" -ForegroundColor Green
        Write-Host "  [3] Toggle Auto-Sync Indicator (current: $Global:AutoSyncCheck)" -ForegroundColor Green
        Write-Host "  [4] Verify Optional Tools (gh, delta)" -ForegroundColor Green
        Write-Host "  [5] View Tool Action History" -ForegroundColor Green
        Write-Host "  [6] Back" -ForegroundColor Green
        $SChoice = Read-Host "Select choice [1-6]"
        switch ($SChoice) {
            "1" { Toggle-WizardMode }
            "2" { Toggle-DryRun }
            "3" { Toggle-AutoSync }
            "4" { Test-OptionalTools }
            "5" { Show-ActionHistory }
            "6" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# --- Load config & run first-time mode wrapper if needed ---
Load-WizardConfig
if (-not $Global:WizardMode) {
    Select-WizardMode
}

# --- Main Master Loop ---
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
    Write-Host "  [6] Enable Universal Global CLI (Run 'git-wizard' from ANY Windows Folder)" -ForegroundColor Yellow
    Write-Host "  [7] Settings (Mode / Dry-Run / Tool Check / Action History)" -ForegroundColor Green
    Write-Host "  [8] Exit" -ForegroundColor Green
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $mainChoice = Read-Host "Enter choice [1-8]"

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
		"6" { Enable-GlobalCLI }
        "7" { Show-SettingsMenu }
        "8" { 
            Write-Host "`nKeep building amazing open-source software! Goodbye!" -ForegroundColor Green
            exit 0 
        }
        default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}