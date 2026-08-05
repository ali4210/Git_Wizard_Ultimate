# ==============================================================================
# MODULE:       branch-engine.ps1
# DESCRIPTION:  Handles Local & Remote Branch Management.
# ==============================================================================

function Manage-GitBranches {
    while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [+] Module 3: Advanced Branch & Remote Manager (Windows)         " -ForegroundColor Yellow
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [1] List All Branches (Local & Remote)"
        Write-Host "  [2] Create New Branch & Publish to GitHub"
        Write-Host "  [3] Switch Branch"
        Write-Host "  [4] Delete Branch (Locally AND from GitHub)"
        Write-Host "  [5] Back to Main Menu"
        Write-Host "====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [1-5]"

        if ($choice -eq "1") {
            Write-Host "`n--- Local Branches ---" -ForegroundColor Cyan
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
            Write-Host "`nAvailable Local Branches:" -ForegroundColor Cyan
            git branch --format="%(refname:short)"
            Write-Host ""
            $targetB = Read-Host "Enter target branch name to switch"
            if ($targetB) {
                git checkout "$targetB"
            }
            Pause-Console
        }
        elseif ($choice -eq "4") {
            $delB = Read-Host "Enter branch name to PURGE (Delete locally & online)"
            if ($delB) {$currentB = (git rev-parse --abbrev-ref HEAD).Trim()
                if ($delB -eq$currentB) {
                    Write-Host "[!] Cannot delete active branch. Switch to another branch first!" -ForegroundColor Red
                } else {
                    $conf = Read-Host "Are you SURE you want to delete '$delB' everywhere? (y/N)"
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