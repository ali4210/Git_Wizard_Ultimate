# ==============================================================================
# TOOL NAME:    git-wizard.ps1 (Windows Master Orchestrator V1.7 - Debug Edition)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master orchestrator loading Git-Wizard Windows modules with 
#               global scope dot-sourcing and verbose import debugging.
# ==============================================================================

# Force GIT_PAGER=cat globally in session to prevent pager prompts
$env:GIT_PAGER = "cat"

# Locate Script Directory & File Path strictly
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = Get-Location }

$TargetPs1Path = Join-Path $ScriptDir "git-wizard.ps1"
$TargetRepoDir = (Get-Location).Path

# --- Global Function Registration & Debugging ---
$SubModules = @("identity-engine.ps1", "repo-engine.ps1", "branch-engine.ps1", "commit-engine.ps1")
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
"@ -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "         GIT-WIZARD ULTIMATE - GITHUB WORKFLOW ENGINE               " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "GitHub  : https://github.com/ali4210" -ForegroundColor Yellow
    Write-Host "Active Repository Context: $TargetRepoDir`n" -ForegroundColor Yellow
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
                git init
                git branch -M main 2>$null
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

# --- Main Master Loop ---
while ($true) {
    Test-GitRepository
    Show-Header
    Write-Host "Main Capabilities Suite:`n" -ForegroundColor Yellow
    Write-Host "  [1] Identity and SSH Manager (Config, Keys, Connections, Remotes)" -ForegroundColor Green
    Write-Host "  [2] Repository and Smart Push Engine (Init, Status, Reset, Conflict Resolver)" -ForegroundColor Green
    Write-Host "  [3] Advanced Branch Manager (Local/Remote Sync and Dual Delete)" -ForegroundColor Green
    Write-Host "  [4] Conventional Commit Assistant (Professional Formatting)" -ForegroundColor Green
    Write-Host "  [5] Enable Universal Global CLI (Run 'git-wizard' from ANY Windows Folder)" -ForegroundColor Yellow
    Write-Host "  [6] Exit" -ForegroundColor Green
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $mainChoice = Read-Host "Enter choice [1-6]"

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
		"5" { Enable-GlobalCLI }
        "6" { 
            Write-Host "`nKeep building amazing open-source software! Goodbye!" -ForegroundColor Green
            exit 0 
        }
        default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}