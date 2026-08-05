# ==============================================================================
# TOOL NAME:    git-wizard.ps1 (Windows Master Orchestrator V1.2 Global Edition)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master orchestrator loading Git-Wizard Windows modules with 
#               dynamic repository binding and 1-click Global CLI installer.
# ==============================================================================

# Force GIT_PAGER=cat globally in session to prevent pager prompts (less/more)
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
    Write-Host "         🧙‍♂️ GIT-WIZARD ULTIMATE - GITHUB WORKFLOW ENGINE           " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "Active Repository Context: $TargetRepoDir`n" -ForegroundColor Yellow
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

# --- Non-Git Repository Verification & Setup ---
function Test-GitRepository {
    $IsRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($IsRepo -ne "true") {
        Show-Header
        Write-Host "[!] WARNING: '$TargetRepoDir' is NOT a Git repository!`n" -ForegroundColor Red
        Write-Host "Available Actions:" -ForegroundColor Cyan
        Write-Host "  [1] Initialize a new Git Repository here (git init)" -ForegroundColor Green
        Write-Host "  [2] ⚡ Enable Universal Global CLI (Install 'git-wizard' system-wide)" -ForegroundColor Yellow
        Write-Host "  [3] Exit" -ForegroundColor Green
        Write-Host "`n====================================================================" -ForegroundColor Cyan
        
        $NonRepoChoice = Read-Host "Select choice [1-3]"
        switch ($NonRepoChoice) {
            "1" {
                git init
                git branch -M main 2>$null
                Write-Host "`n[✔] Initialized empty Git repository in $TargetRepoDir!" -ForegroundColor Green
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
    Write-Host "⚡ UNIVERSAL GLOBAL CLI INSTALLER FOR WINDOWS`n" -ForegroundColor Yellow
    Write-Host "--> Configuring PowerShell Profile for global 'git-wizard' execution..." -ForegroundColor Cyan

    # Ensure Profile exists
    if (-not (Test-Path $PROFILE)) {
        New-Item -Path $PROFILE -Type File -Force | Out-Null
    }

    $GlobalFunctionConfig = @"

# --- Git-Wizard Ultimate Global Shortcut ---
function git-wizard {
    powershell.exe -ExecutionPolicy Bypass -File "$TargetPs1Path"
}
"@

    if (-not (Get-Content $PROFILE -ErrorAction SilentlyContinue | Select-String "function git-wizard")) {
        Add-Content -Path $PROFILE -Value $GlobalFunctionConfig
        Write-Host "`n[✔] 'git-wizard' function added to your PowerShell `$PROFILE!" -ForegroundColor Green
    } else {
        Write-Host "`n[✔] 'git-wizard' is already configured in your PowerShell `$PROFILE." -ForegroundColor Green
    }

    Write-Host "`n====================================================================" -ForegroundColor Cyan
    Write-Host "[✔] GIT-WIZARD IS NOW INSTALLED GLOBALLY ON YOUR WINDOWS SYSTEM!" -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "📌 HOW TO USE FROM ANY WINDOWS FOLDER:" -ForegroundColor Cyan
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
    Write-Host "  [1] Identity & SSH Manager (Config, Keys, Connections, Remotes)" -ForegroundColor Green
    Write-Host "  [2] Repository & Smart Push Engine (Init, Status, Reset, Conflict Resolver)" -ForegroundColor Green
    Write-Host "  [3] Advanced Branch Manager (Local/Remote Sync & Dual Delete)" -ForegroundColor Green
    Write-Host "  [4] Conventional Commit Assistant (Professional Formatting)" -ForegroundColor Green
    Write-Host "  [5] ⚡ Enable Universal Global CLI (Run 'git-wizard' from ANY Windows Folder)" -ForegroundColor Yellow
    Write-Host "  [6] Exit" -ForegroundColor Green
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $mainChoice = Read-Host "Enter choice [1-6]"

    switch ($mainChoice) {
        "1" { if (Get-Command Manage-GitIdentity -ErrorAction SilentlyContinue) { Manage-GitIdentity } else { Write-Host "[!] Module function Manage-GitIdentity missing." -ForegroundColor Red; Pause-Console } }
        "2" { if (Get-Command Manage-GitRepo -ErrorAction SilentlyContinue) { Manage-GitRepo } else { Write-Host "[!] Module function Manage-GitRepo missing." -ForegroundColor Red; Pause-Console } }
        "3" { if (Get-Command Manage-GitBranches -ErrorAction SilentlyContinue) { Manage-GitBranches } else { Write-Host "[!] Module function Manage-GitBranches missing." -ForegroundColor Red; Pause-Console } }
        "4" { if (Get-Command Craft-ConventionalCommit -ErrorAction SilentlyContinue) { Craft-ConventionalCommit } else { Write-Host "[!] Module function Craft-ConventionalCommit missing." -ForegroundColor Red; Pause-Console } }
        "5" { Enable-GlobalPowerShellCLI }
        "6" { 
            Write-Host "`nKeep building amazing open-source software! Goodbye!" -ForegroundColor Green
            exit 0 
        }
        default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}