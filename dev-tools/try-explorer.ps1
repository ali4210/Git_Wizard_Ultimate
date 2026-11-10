# Standalone tester for the Workspace Explorer -- lets you drive it without
# going through the real main menu. Real confirm/backup/log behavior.
#
# Usage:
#   pwsh ./try-explorer.ps1 -RepoDir C:\path\to\any\git\repo
param(
    [string]$RepoDir = (Get-Location).Path,
    [string]$ModulePath = (Join-Path $PSScriptRoot "../modules/workspace-engine.ps1")
)

$Global:WizardMode = "advanced"   # advanced = y/N confirm; "beginner" = typed "yes i understand"
$Global:DryRun = $false
$ConfigDir = Join-Path $env:TEMP "gw-explorer-tester-config"
if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }
$ActionLog = Join-Path $ConfigDir "actions.log"

function Write-WizardActionLog {
    param([string]$Message)
    "{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message | Add-Content -Path $ActionLog
}
function Invoke-GitWizard {
    $GitArgs = $args
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would execute: git $($GitArgs -join ' ')" -ForegroundColor Yellow
        Write-WizardActionLog "DRY-RUN (not executed): git $($GitArgs -join ' ')"
        return $true
    }
    Write-WizardActionLog "EXECUTED: git $($GitArgs -join ' ')"
    & git @GitArgs
    return ($LASTEXITCODE -eq 0)
}
function New-SafetyBackup {
    param([string]$Reason)
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would create safety backup tag: backup/$Reason-..." -ForegroundColor Yellow
        return
    }
    $headExists = git rev-parse HEAD 2>$null
    if ($headExists) {
        $ts = Get-Date -Format "yyyyMMdd-HHmmss"
        $tag = "backup/$Reason-$ts"
        git tag $tag HEAD 2>$null | Out-Null
        Write-Host "[+] Safety backup created: $tag (recover with: git reset --hard $tag)" -ForegroundColor Green
        Write-WizardActionLog "BACKUP created: $tag (reason: $Reason)"
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

if (-not (Test-Path -LiteralPath $ModulePath)) {
    Write-Host "Can't find workspace-engine.ps1 at: $ModulePath" -ForegroundColor Red
    Write-Host "Run this from the Git_Wizard_Ultimate checkout root, or pass -ModulePath." -ForegroundColor Yellow
    exit 1
}
. $ModulePath

Set-Location $RepoDir
if ((git rev-parse --is-inside-work-tree 2>$null) -ne "true") {
    Write-Host "Not a git repository: $RepoDir" -ForegroundColor Red
    exit 1
}

Show-WsWorkspaceExplorer | Out-Null
Write-Host "`nExited the Workspace Explorer. Action log: $ActionLog" -ForegroundColor Cyan
