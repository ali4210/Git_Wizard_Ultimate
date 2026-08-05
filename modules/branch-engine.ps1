# ==============================================================================
# MODULE:       branch-engine.ps1
# DESCRIPTION:  Handles Local & Remote Branch Management.
# ==============================================================================

# Force environment variable to disable git pager globally in session
$env:GIT_PAGER = "cat"

function Select-BranchInteractive ($prompt) {
    $branches = git branch --format="%(refname:short)"
    if (-not $branches) {
        Write-Host "[!] No local branches found." -ForegroundColor Red
        return $null
    }

    # Ensure array format if single branch exists
    $branchArray = @($branches)

    $selected = 0
    while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  $prompt" -ForegroundColor Yellow
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "Use UP/DOWN arrow keys to navigate, press [ENTER] to select:`n" -ForegroundColor Cyan

        for ($i = 0; $i -lt $branchArray.Count; $i++) {
            if ($i -eq $selected) {
                Write-Host "  ➔  $($branchArray[$i]) (Selected)" -ForegroundColor Green
            } else {
                Write-Host "     $($branchArray[$i])"
            }
        }
        Write-Host "`n====================================================================" -ForegroundColor Cyan

        $key = [Console]::ReadKey($true)
        if ($key.Key -eq "UpArrow") {
            $selected--
            if ($selected -lt 0) { $selected = $branchArray.Count - 1 }
        }
        elseif ($key.Key -eq "DownArrow") {
            $selected++
            if ($selected -ge $branchArray.Count) { $selected = 0 }
        }
        elseif ($key.Key -eq "Enter") {
            return $branchArray[$selected].Trim()
        }
    }
}

function Manage-GitBranches {
    # Ensure GIT_PAGER=cat is enforced
    $env:GIT_PAGER = "cat"

    while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [+] Module 3: Advanced Branch & Remote Manager (Windows)         " -ForegroundColor Yellow
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [1] List All Branches (Local & Remote)"
        Write-Host "  [2] Create New Branch & Publish to GitHub"
        Write-Host "  [3] Switch Branch (Interactive Arrow-Key Selection)"
        Write-Host "  [4] Delete Branch (Interactive Arrow-Key Selection & Purge)"
        Write-Host "  [5] Back to Main Menu"
        Write-Host "====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [1-5]"

        if ($choice -eq "1") {
            Clear-Host
            Write-Host "--- Local Branches ---" -ForegroundColor Cyan
            git branch -vv
            Write-Host "`n--- Remote Branches ---" -ForegroundColor Cyan
            git branch -r
            Pause-Console
        }
        elseif ($choice -eq "2") {
            $newB = Read-Host "Enter new branch name"
            if ($newB) {
                git checkout -b "$newB"
                Write-Host "--> Publishing '$newB' to GitHub..." -ForegroundColor Green
                git push -u origin "$newB"
                Write-Host "[✔] Branch created and tracked on GitHub!" -ForegroundColor Green
            }
            Pause-Console
        }
        elseif ($choice -eq "3") {
            $targetB = Select-BranchInteractive "📌 SELECT BRANCH TO SWITCH"
            if ($targetB) {
                Write-Host "`n--> Switching to branch '$targetB'..." -ForegroundColor Green
                git checkout "$targetB"
            }
            Pause-Console
        }
        elseif ($choice -eq "4") {
            $delB = Select-BranchInteractive "📌 SELECT BRANCH TO PURGE (LOCAL & REMOTE)"
            if ($delB) {
                $currentB = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
                if ($delB -eq $currentB) {
                    Write-Host "`n[!] Cannot delete active branch '$currentB'. Switch to another branch first!" -ForegroundColor Red
                } else {
                    $conf = Read-Host "`nAre you SURE you want to delete '$delB' everywhere? (y/N)"
                    if ($conf -eq "y" -or $conf -eq "Y") {
                        git branch -D "$delB" 2>$null
                        git push origin --delete "$delB" 2>$null
                        Write-Host "[✔] Branch '$delB' purged successfully!" -ForegroundColor Green
                    }
                }
            }
            Pause-Console
        }
        elseif ($choice -eq "5") { break }
    }
}