# ==============================================================================
# ENGINE NAME: branch-engine.ps1 (PowerShell 5.1 Interactive Arrow-Key Edition - Back=0)
# ==============================================================================

function Select-BranchInteractive ($menuTitle) {
    # Get clean local branch list
    $rawBranches = git branch --format="%(refname:short)" 2>$null
    if (-not $rawBranches) {
        Write-Host "[!] No local branches found in this repository." -ForegroundColor Red
        return $null
    }

    $branches = @($rawBranches)
    if ($branches.Count -eq 0) {
        Write-Host "[!] No local branches found." -ForegroundColor Red
        return $null
    }

    $selectedIndex = 0
    $running = $true

    while ($running) {
        Show-Header
        Write-Host "  $menuTitle`n" -ForegroundColor Yellow
        Write-Host "Use UP/DOWN Arrow keys to navigate, press [ENTER] to select, [Q] to cancel:`n" -ForegroundColor Cyan

        for ($i = 0; $i -lt $branches.Count; $i++) {
            if ($i -eq $selectedIndex) {
                Write-Host "  ->  $($branches[$i]) (Selected)" -ForegroundColor Green
            } else {
                Write-Host "      $($branches[$i])" -ForegroundColor Gray
            }
        }
        Write-Host "`n====================================================================" -ForegroundColor Cyan

        # Capture single keypress
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            "UpArrow" {
                $selectedIndex--
                if ($selectedIndex -lt 0) { $selectedIndex = $branches.Count - 1 }
            }
            "DownArrow" {
                $selectedIndex++
                if ($selectedIndex -ge $branches.Count) { $selectedIndex = 0 }
            }
            "Enter" {
                return $branches[$selectedIndex]
            }
            "Escape" {
                return $null
            }
            "Q" {
                return $null
            }
        }
    }
}

function Manage-Branches {
    while ($true) {
        Show-Header
        Write-Host "  [+] Module 3: Advanced Branch and Remote Manager`n" -ForegroundColor Yellow
        Write-Host "  [1] List All Branches (Local and Remote)" -ForegroundColor Green
        Write-Host "  [2] Create New Branch and Publish to GitHub" -ForegroundColor Green
        Write-Host "  [3] Switch Branch (Interactive Arrow-Key Selection)" -ForegroundColor Green
        Write-Host "  [4] Delete Branch (Interactive Arrow-Key Selection and Purge)" -ForegroundColor Green
        Write-Host "  [0] Back to Main Menu" -ForegroundColor Green
        Write-Host "`n====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [0-4]"

        switch ($choice) {
            "1" {
                Show-Header
                Write-Host "--- Local Branches ---" -ForegroundColor Cyan
                git branch -vv
                Write-Host "`n--- Remote Branches ---" -ForegroundColor Cyan
                git branch -r
                Pause-Console
            }
            "2" {
                $newB = Read-Host "Enter new branch name"
                if ($newB) {
                    if (Invoke-GitWizard checkout -b $newB) {
                        Write-Host "--> Publishing '$newB' to GitHub..." -ForegroundColor Green
                        if (Invoke-GitWizard push -u origin $newB) {
                            Write-Host "[+] Branch created and tracked on GitHub!" -ForegroundColor Green
                        } else {
                            Write-Host "[!] Branch created locally but push failed. Check your remote/connection." -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "[!] Could not create branch '$newB' (may already exist)." -ForegroundColor Red
                    }
                }
                Pause-Console
            }
            "3" {
                $selectedBranch = Select-BranchInteractive "SELECT BRANCH TO SWITCH"
                if ($selectedBranch) {
                    Write-Host "`n--> Switching to branch '$selectedBranch'..." -ForegroundColor Green
                    git checkout "$selectedBranch"
                } else {
                    Write-Host "`nBranch selection cancelled." -ForegroundColor Yellow
                }
                Pause-Console
            }
            "4" {
                $selectedBranch = Select-BranchInteractive "SELECT BRANCH TO PURGE (LOCAL AND REMOTE)"
                if ($selectedBranch) {
                    $curB = git rev-parse --abbrev-ref HEAD 2>$null
                    if ($selectedBranch -eq $curB) {
                        Write-Host "`n[!] Cannot delete active branch '$curB'! Switch to another branch first." -ForegroundColor Red
                    } elseif (Confirm-DestructiveAction "Delete branch '$selectedBranch' locally and remotely") {
                        New-SafetyBackup "pre-branch-delete-$selectedBranch"
                        Invoke-GitWizard branch -D $selectedBranch | Out-Null
                        Invoke-GitWizard push origin --delete $selectedBranch | Out-Null
                        Write-Host "[+] Branch '$selectedBranch' purged successfully!" -ForegroundColor Green
                    }
                } else {
                    Write-Host "`nBranch deletion cancelled." -ForegroundColor Yellow
                }
                Pause-Console
            }
            "0" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

function Manage-GitBranches {
    Manage-Branches
}
