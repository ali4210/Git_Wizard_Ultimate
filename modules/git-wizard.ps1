# ==============================================================================
# TOOL NAME:    git-wizard.ps1 (V1.0 Master PowerShell Orchestrator)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  Master orchestrator loading Git-Wizard Windows modules.
# ==============================================================================

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

# Import Modules
. (Join-Path $ScriptDir "identity-engine.ps1")
. (Join-Path $ScriptDir "repo-engine.ps1")
. (Join-Path $ScriptDir "branch-engine.ps1")
. (Join-Path $ScriptDir "commit-engine.ps1")

function Show-Header {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "         🧙‍♂️ GIT-WIZARD ULTIMATE - GITHUB WORKFLOW ENGINE           " -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
}

function Pause-Console {
    Write-Host ""
    Read-Host "Press [ENTER] to return to menu..."
}

while ($true) {
    Show-Header
    Write-Host "Main Capabilities Suite:`n" -ForegroundColor Yellow
    Write-Host "  [1] Identity & SSH Manager (Config, Keys, Connections)"
    Write-Host "  [2] Repository & Smart Push Engine (Init, Conflict Resolver, .gitignore)"
    Write-Host "  [3] Advanced Branch Manager (Local/Remote Sync & Dual Delete)"
    Write-Host "  [4] Conventional Commit Assistant (Professional Formatting)"
    Write-Host "  [5] Exit"
    Write-Host "`n====================================================================" -ForegroundColor Cyan

    $mainChoice = Read-Host "Enter choice [1-5]"

    switch ($mainChoice) {
        "1" { Manage-GitIdentity }
        "2" { Manage-GitRepo }
        "3" { Manage-GitBranches }
        "4" { Manage-ConventionalCommits }
        "5" { Write-Host "`nKeep building amazing open-source software! Goodbye!" -ForegroundColor Green; break }
        default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}