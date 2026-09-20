# ==============================================================================
# ENGINE NAME: conflict-engine.ps1
# Smart Conflict Resolver with Force Push / Force Pull ROLLBACK
# Uses helpers from git-wizard.ps1: Show-Header, Pause-Console,
# Confirm-DestructiveAction, New-SafetyBackup, Write-WizardActionLog
# ==============================================================================

function Get-RollbackFile {
    param([ValidateSet("push","pull")][string]$Kind)
    $dir = Join-Path $ConfigDir "rollback"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($TargetRepoDir))).Replace("-","").Substring(0,12)
    return (Join-Path $dir "$hash.$Kind.json")
}

function Invoke-SmartForcePush {
    param([string]$Branch)
    if (-not (Confirm-DestructiveAction "Force push '$Branch' - overwrites the remote branch")) {
        Write-Host "[i] Cancelled." -ForegroundColor Yellow; return
    }
    # --- Auto stage + commit (asks for the message) so the push always has your latest work ---
    if (git status --porcelain) {
        Write-Host "--> Uncommitted changes detected:" -ForegroundColor Cyan
        git status --short
        Write-Host ""
        $fpMsg = Read-Host "Enter commit message (ENTER to cancel)"
        if (-not $fpMsg) {
            Write-Host "[i] Cancelled - nothing was changed." -ForegroundColor Yellow; return
        }
        New-SafetyBackup -Reason "pre-force-push"
        if ($Global:DryRun) {
            Write-Host "[DRY-RUN] Would execute: git add -A ; git commit -m `"$fpMsg`"" -ForegroundColor Yellow
        } else {
            git add -A
            git commit -m "$fpMsg"
            if ($LASTEXITCODE -ne 0) {
                # a pre-commit hook may have auto-fixed files: re-stage and retry once
                git add -A
                git commit -m "$fpMsg"
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "[!] Commit failed. Nothing was pushed." -ForegroundColor Red; return
                }
            }
        }
    } else {
        New-SafetyBackup -Reason "pre-force-push"
    }
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $localSha = git rev-parse HEAD 2>$null
    $remoteSha = $null

    if (-not $Global:DryRun) {
        Write-Host "--> Recording current remote state (for rollback)..." -ForegroundColor Cyan
        git fetch origin 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] Fetch failed - rollback point can't be recorded. Aborting, nothing pushed." -ForegroundColor Red
            return
        }
        $remoteSha = git rev-parse --verify -q "origin/$Branch" 2>$null
    }

    $rbFile = Get-RollbackFile push
    if ($remoteSha) {
        $tag = "backup/remote-$($Branch -replace '/','-')-$ts"
        git tag $tag $remoteSha 2>$null | Out-Null
        [PSCustomObject]@{
            Branch = $Branch; RemoteSha = $remoteSha; PushedSha = $localSha; Tag = $tag; Time = $ts
        } | ConvertTo-Json | Set-Content -Path $rbFile -Encoding UTF8
        Write-Host "[+] Rollback point saved: $tag ($($remoteSha.Substring(0,8)))" -ForegroundColor Green
        Write-WizardActionLog "Force-push rollback point saved: $tag"
    } elseif (-not $Global:DryRun) {
        Write-Host "[i] origin/$Branch doesn't exist yet - nothing to roll back to." -ForegroundColor Yellow
        Remove-Item $rbFile -Force -ErrorAction SilentlyContinue
    }

    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would execute: git push origin $Branch --force" -ForegroundColor Yellow
        Write-WizardActionLog "DRY-RUN (not executed): git push origin $Branch --force"
        return
    }

    # --force-with-lease also protects you if someone pushed between fetch and push
    if ($remoteSha) { git push origin $Branch "--force-with-lease=${Branch}:${remoteSha}" }
    else            { git push origin $Branch --force }

    if ($LASTEXITCODE -eq 0) {
        Write-WizardActionLog "EXECUTED: force push $Branch"
        Write-Host "[+] Force push done. Undo anytime via 'Rollback Last Force Push'." -ForegroundColor Green
    } else {
        Write-Host "[!] Force push failed (branch protection? someone pushed meanwhile?)." -ForegroundColor Red
        Remove-Item $rbFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-RollbackForcePush {
    $rbFile = Get-RollbackFile push
    if (-not (Test-Path $rbFile)) {
        Write-Host "[i] No force push recorded for this repo - nothing to roll back." -ForegroundColor Yellow; return
    }
    $rb = Get-Content $rbFile -Raw | ConvertFrom-Json
    Write-Host "Last force push: branch $($rb.Branch) at $($rb.Time)" -ForegroundColor Cyan
    Write-Host "Remote was at:   $($rb.RemoteSha.Substring(0,8))  (tag $($rb.Tag))" -ForegroundColor Cyan

    git cat-file -e "$($rb.RemoteSha)^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] The old commit no longer exists locally. Can't roll back." -ForegroundColor Red; return
    }
    git fetch origin 2>$null | Out-Null
    $current = git rev-parse --verify -q "origin/$($rb.Branch)" 2>$null
    if (-not $current) {
        Write-Host "[!] origin/$($rb.Branch) no longer exists on the remote." -ForegroundColor Red; return
    }
    if ($current -ne $rb.PushedSha) {
        Write-Host "[!] WARNING: the remote changed since your force push (now $($current.Substring(0,8)))." -ForegroundColor Yellow
        Write-Host "    Rolling back will also discard those newer remote commits." -ForegroundColor Yellow
    }
    if (-not (Confirm-DestructiveAction "Roll remote '$($rb.Branch)' back to $($rb.RemoteSha.Substring(0,8)) (undo your force push)")) {
        Write-Host "[i] Cancelled." -ForegroundColor Yellow; return
    }
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would push $($rb.RemoteSha) to $($rb.Branch) with lease" -ForegroundColor Yellow; return
    }
    # Make the rollback itself reversible
    git tag "backup/pre-rollback-push-$(Get-Date -Format 'yyyyMMdd-HHmmss')" $current 2>$null | Out-Null

    git push origin "$($rb.RemoteSha):refs/heads/$($rb.Branch)" "--force-with-lease=refs/heads/$($rb.Branch):${current}"
    if ($LASTEXITCODE -eq 0) {
        Remove-Item $rbFile -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Remote '$($rb.Branch)' restored to $($rb.RemoteSha.Substring(0,8))." -ForegroundColor Green
        Write-Host "    Your LOCAL branch still has the new commits - use Force Pull to match GitHub again." -ForegroundColor Cyan
        Write-WizardActionLog "Force-push ROLLED BACK: $($rb.Branch) -> $($rb.RemoteSha)"
    } else {
        Write-Host "[!] Rollback push failed (branch protection or remote changed again)." -ForegroundColor Red
    }
}

function Invoke-SmartForcePull {
    param([string]$Branch)
    if (-not (Confirm-DestructiveAction "Force pull - overwrites local '$Branch' with origin/$Branch")) {
        Write-Host "[i] Cancelled." -ForegroundColor Yellow; return
    }
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would execute: git fetch origin; git reset --hard origin/$Branch; git clean -fd" -ForegroundColor Yellow
        return
    }
    Write-Host "--> Fetching..." -ForegroundColor Cyan
    git fetch origin
    if ($LASTEXITCODE -ne 0) { Write-Host "[!] Fetch failed. Nothing was changed." -ForegroundColor Red; return }
    git rev-parse --verify -q "origin/$Branch" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "[!] origin/$Branch doesn't exist. Nothing was changed." -ForegroundColor Red; return }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $headSha = git rev-parse HEAD 2>$null
    $tag = "backup/pre-force-pull-$($Branch -replace '/','-')-$ts"
    if ($headSha) { git tag $tag $headSha 2>$null | Out-Null }

    # Save uncommitted + untracked files too (reset --hard / clean -fd would destroy them)
    $stashMsg = ""
    if (git status --porcelain) {
        $stashMsg = "gw-force-pull-$ts"
        git stash push -u -m $stashMsg 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] Couldn't stash your local changes - aborting so nothing is lost." -ForegroundColor Red; return
        }
        Write-Host "[+] Uncommitted/untracked files saved in stash '$stashMsg'." -ForegroundColor Green
    }

    [PSCustomObject]@{
        Branch = $Branch; HeadSha = $headSha; Tag = $tag; StashMsg = $stashMsg; Time = $ts
    } | ConvertTo-Json | Set-Content -Path (Get-RollbackFile pull) -Encoding UTF8
    Write-Host "[+] Rollback point saved: $tag" -ForegroundColor Green
    Write-WizardActionLog "Force-pull rollback point saved: $tag (stash: $stashMsg)"

    git reset --hard "origin/$Branch"
    git clean -fd
    Write-Host "[+] Local '$Branch' now matches origin/$Branch. Undo via 'Rollback Last Force Pull'." -ForegroundColor Green
}

function Invoke-RollbackForcePull {
    $rbFile = Get-RollbackFile pull
    if (-not (Test-Path $rbFile)) {
        Write-Host "[i] No force pull recorded for this repo - nothing to roll back." -ForegroundColor Yellow; return
    }
    $rb = Get-Content $rbFile -Raw | ConvertFrom-Json
    Write-Host "Last force pull: branch $($rb.Branch) at $($rb.Time)" -ForegroundColor Cyan
    Write-Host "Local was at:    $($rb.HeadSha.Substring(0,8))  (tag $($rb.Tag))" -ForegroundColor Cyan
    if ($rb.StashMsg) { Write-Host "Uncommitted files: saved in stash '$($rb.StashMsg)' (will be restored)" -ForegroundColor Cyan }

    git cat-file -e "$($rb.HeadSha)^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "[!] The old commit no longer exists locally. Can't roll back." -ForegroundColor Red; return }

    if (-not (Confirm-DestructiveAction "Restore local '$($rb.Branch)' to $($rb.HeadSha.Substring(0,8)) (undo your force pull)")) {
        Write-Host "[i] Cancelled." -ForegroundColor Yellow; return
    }
    if ($Global:DryRun) {
        Write-Host "[DRY-RUN] Would checkout $($rb.Branch), reset --hard $($rb.HeadSha), pop stash" -ForegroundColor Yellow; return
    }

    # Anything done since the force pull is saved first, so this is reversible too
    $now = Get-Date -Format "yyyyMMdd-HHmmss"
    git tag "backup/pre-rollback-pull-$now" HEAD 2>$null | Out-Null
    if (git status --porcelain) {
        git stash push -u -m "gw-pre-rollback-$now" 2>&1 | Out-Null
        Write-Host "[i] Your current uncommitted changes were stashed as 'gw-pre-rollback-$now'." -ForegroundColor Yellow
    }
    $cur = git rev-parse --abbrev-ref HEAD 2>$null
    if ($cur -ne $rb.Branch) { git checkout $rb.Branch }

    git reset --hard $rb.HeadSha
    if ($LASTEXITCODE -ne 0) { Write-Host "[!] Reset failed." -ForegroundColor Red; return }
    Write-Host "[+] Branch '$($rb.Branch)' restored to $($rb.HeadSha.Substring(0,8))." -ForegroundColor Green

    if ($rb.StashMsg) {
        $ref = (git stash list | Where-Object { $_ -like "*$($rb.StashMsg)*" } | Select-Object -First 1) -replace ':.*$',''
        if ($ref) {
            git stash pop $ref 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "[+] Your uncommitted/untracked files are back." -ForegroundColor Green }
            else { Write-Host "[!] Couldn't auto-restore the stash. Check 'git stash list'." -ForegroundColor Yellow }
        } else {
            Write-Host "[!] Stash '$($rb.StashMsg)' not found. Check 'git stash list'." -ForegroundColor Yellow
        }
    }
    Remove-Item $rbFile -Force -ErrorAction SilentlyContinue
    Write-WizardActionLog "Force-pull ROLLED BACK: $($rb.Branch) -> $($rb.HeadSha)"
}

function Show-ConflictResolverMenu {
    while ($true) {
        Show-Header
        $Branch = git rev-parse --abbrev-ref HEAD 2>$null
        if (-not $Branch) { $Branch = "main" }
        $pushNote = if (Test-Path (Get-RollbackFile push)) { " (available)" } else { "" }
        $pullNote = if (Test-Path (Get-RollbackFile pull)) { " (available)" } else { "" }

        Write-Host "SMART CONFLICT PUSH RESOLVER  (branch: $Branch)`n" -ForegroundColor Yellow
        Write-Host "  [1] Safe Pull & Rebase" -ForegroundColor Green
        Write-Host "  [2] Safe Pull & Merge" -ForegroundColor Green
        Write-Host "  [3] Force Push (Overwrites remote!)" -ForegroundColor Red
        Write-Host "  [4] Force Pull (Overwrites local!)" -ForegroundColor Red
        Write-Host "  [5] Rollback Last Force Push$pushNote" -ForegroundColor Green
        Write-Host "  [6] Rollback Last Force Pull$pullNote" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $s = Read-Host "Select strategy [0-6]"
        switch ($s) {
            "1" {
                git pull origin $Branch --rebase
                if ($LASTEXITCODE -eq 0) { git push origin $Branch }
                else { Write-Host "[!] Pull/rebase failed - resolve conflicts manually." -ForegroundColor Red }
                Pause-Console
            }
            "2" {
                git pull origin $Branch --no-rebase --allow-unrelated-histories
                if ($LASTEXITCODE -eq 0) { git push origin $Branch }
                else { Write-Host "[!] Pull/merge failed - resolve conflicts manually." -ForegroundColor Red }
                Pause-Console
            }
            "3" { Invoke-SmartForcePush -Branch $Branch; Pause-Console }
            "4" { Invoke-SmartForcePull -Branch $Branch; Pause-Console }
            "5" { Invoke-RollbackForcePush; Pause-Console }
            "6" { Invoke-RollbackForcePull; Pause-Console }
            "0" { return }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}
