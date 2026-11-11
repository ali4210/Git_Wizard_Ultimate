# Shared Pester test helpers for the audit regression tests in this folder.
#
# These tests dot-source the real *-engine.ps1 module files directly (so they exercise the
# actual fixed code), but deliberately do NOT dot-source modules/git-wizard.ps1 itself: that
# file's top level calls Enter-AltScreen/Ensure-GitInstalled and auto-loads every submodule,
# which is unsafe/unpredictable to run from an automated, non-interactive test host.
#
# Invoke-GitWizard, Confirm-DestructiveAction, New-SafetyBackup and Write-WizardActionLog below
# are faithful copies of the real definitions in modules/git-wizard.ps1 as of this fix round.
# If those functions change there, update the copies here too so the tests keep exercising the
# real current behavior.

function Show-Header { }
function Pause-Console { }

function Write-WizardActionLog {
    param([string]$Message)
    if (-not $Global:ActionLog) { return }
    $line = "{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $Global:ActionLog -Value $line
}

function Invoke-GitWizard {
    $GitArgs = $args
    $ArgString = ($GitArgs -join ' ')
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would execute: git $ArgString" -ForegroundColor Yellow
        Write-WizardActionLog "DRY-RUN (not executed): git $ArgString"
        return $true
    } else {
        Write-WizardActionLog "EXECUTED: git $ArgString"
        & git @GitArgs | ForEach-Object { Write-Host $_ }
        return ($LASTEXITCODE -eq 0)
    }
}

function Confirm-DestructiveAction {
    param([string]$ActionDesc)
    Write-Host "`n[!] DESTRUCTIVE ACTION: $ActionDesc" -ForegroundColor Red
    if ($Global:WizardMode -eq "beginner") {
        $conf = Read-Host "Type EXACTLY 'yes i understand' to proceed"
        return ($conf -eq "yes i understand")
    } else {
        $conf = Read-Host "Proceed? (y/N)"
        return ($conf -match '^[Yy]$')
    }
}

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

function Invoke-CommitWithHookRetry {
    param([string]$Message)
    $retried = $false
    while ($true) {
        if (Invoke-GitWizard commit -m "$Message") { return $true }
        $stillDirty = git status --porcelain
        if (-not $retried -and $stillDirty) {
            Invoke-GitWizard add . | Out-Null
            $retried = $true
            continue
        }
        return $false
    }
}

# Creates a fresh throwaway git repo under the OS temp dir with one initial commit
# (file0.txt) on branch 'main', and returns its path. Caller is responsible for
# Push-Location/Pop-Location around any Invoke-GitWizard/engine-function calls.
function New-GwTestRepo {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "gw-pester-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Push-Location $path
    try {
        git init --quiet -b main 2>$null | Out-Null
        git config user.email "pester@test.local" | Out-Null
        git config user.name "Pester" | Out-Null
        "file0" | Set-Content -Path "file0.txt"
        git add file0.txt | Out-Null
        git commit --quiet -m "init" | Out-Null
    } finally {
        Pop-Location
    }
    return $path
}

function Remove-GwTestRepo {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}
