# ==============================================================================
# TOOL NAME:    git-wizard.ps1 (Windows Master Orchestrator V1.3 - Fixed Imports)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master orchestrator loading Git-Wizard Windows modules with 
#               dynamic repository binding and 1-click Global CLI installer.
# ==============================================================================

# Force GIT_PAGER=cat globally in session to prevent pager prompts
$env:GIT_PAGER = "cat"

# Locate Script Directory & File Path
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$TargetPs1Path = Join-Path $ScriptDir "git-wizard.ps1"

# Target repository is ALWAYS the current active working directory
$TargetRepoDir = (Get-Location).Path

# --- Import Sub-Module Engines ---
if (Test-Path (Join-Path $ScriptDir "identity-engine.ps1")) { . (Join-Path $ScriptDir "identity-engine.ps1") }
if (Test-Path (Join-Path $ScriptDir "repo-engine.ps1")) { . (Join-Path $ScriptDir "repo-engine.ps1") }
if (Test-Path (Join-Path $ScriptDir "branch-engine.ps1")) { . (Join-Path $ScriptDir "branch-engine.ps1") }
if (Test-Path (Join-Path $ScriptDir "commit-engine.ps1")) { . (Join-Path $ScriptDir "commit-engine.ps1") }

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
            "2" { Enable-GlobalPowerShellCLI }
            "3" { exit 0 }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# --- Enable Universal Global CLI for Windows ---
function Enable-GlobalPowerShellCLI {
    Show-Header
    Write-Host "UNIVERSAL GLOBAL CLI INSTALLER FOR WINDOWS`n" -ForegroundColor Yellow
    Write-Host "--> Configuring PowerShell Profile for global 'git-wizard' execution..." -ForegroundColor Cyan

    # Ensure Profile exists
    if (-not (Test-Path $PROFILE)) {
        New-Item -Path $PROFILE -Type File -Force | Out-Null
    }

    $ProfilePath = $PROFILE
    $GlobalFunctionConfig = "function git-wizard { powershell.exe -ExecutionPolicy Bypass -File '$TargetPs1Path' }"

    if (-not (Get-Content -Path $ProfilePath -ErrorAction SilentlyContinue | Select-String -Pattern "function git-wizard")) {
        Add-Content -Path $ProfilePath -Value "`n# --- Git-Wizard Ultimate Global Shortcut ---`n$GlobalFunctionConfig"
        Write-Host "`n[+] 'git-wizard' function added to your PowerShell Profile!" -ForegroundColor Green
    } else {
        Write-Host "`n[+] 'git-wizard' is already configured in your PowerShell Profile." -ForegroundColor Green
    }

    Write-Host "`n====================================================================" -ForegroundColor Cyan
    Write-Host "[+] GIT-WIZARD IS NOW INSTALLED GLOBALLY ON YOUR WINDOWS SYSTEM!" -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "HOW TO USE FROM ANY WINDOWS FOLDER:" -ForegroundColor Cyan
    Write-Host "  1. Open ANY PowerShell window or Windows Terminal." -ForegroundColor White
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
            if (Get-Command Manage-GitIdentity -ErrorAction SilentlyContinue) { Manage-GitIdentity }
            elseif (Get-Command Manage-Identity -ErrorAction SilentlyContinue) { Manage-Identity }
            else { Write-Host "[!] Module function for Identity missing." -ForegroundColor Red; Pause-Console }
        }
        "2" {
            if (Get-Command Manage-GitRepo -ErrorAction SilentlyContinue) { Manage-GitRepo }
            elseif (Get-Command Manage-Repo -ErrorAction SilentlyContinue) { Manage-Repo }
            else { Write-Host "[!] Module function for Repository missing." -ForegroundColor Red; Pause-Console }
        }
        "3" {
            if (Get-Command Manage-GitBranches -ErrorAction SilentlyContinue) { Manage-GitBranches }
            elseif (Get-Command Manage-Branches -ErrorAction SilentlyContinue) { Manage-Branches }
            else { Write-Host "[!] Module function for Branches missing." -ForegroundColor Red; Pause-Console }
        }
        "4" {
            if (Get-Command Craft-ConventionalCommit -ErrorAction SilentlyContinue) { Craft-ConventionalCommit }
            elseif (Get-Command Craft-Commit -ErrorAction SilentlyContinue) { Craft-Commit }
            else { Write-Host "[!] Module function for Commit Assistant missing." -ForegroundColor Red; Pause-Console }
        }
        "5" { Enable-GlobalPowerShellCLI }
        "6" { 
            Write-Host "`nKeep building amazing open-source software! Goodbye!" -ForegroundColor Green
            exit 0 
        }
        default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}