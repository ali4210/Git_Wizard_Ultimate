# ==============================================================================
# ENGINE NAME: commit-engine.ps1 (PowerShell 5.1 Clean Edition)
# ==============================================================================

function Craft-Commit {
    Show-Header
    Write-Host "  [+] Module 4: Conventional Commit Crafting Assistant`n" -ForegroundColor Yellow
    Write-Host "Select commit classification:"
    Write-Host "  [1] feat:     A new feature for users" -ForegroundColor Green
    Write-Host "  [2] fix:      A bug fix" -ForegroundColor Green
    Write-Host "  [3] docs:     Documentation changes only" -ForegroundColor Green
    Write-Host "  [4] refactor: Code restructuring without logic change" -ForegroundColor Green
    Write-Host "  [5] chore:    Build process or dependency updates" -ForegroundColor Green

    $cType = Read-Host "Select choice [1-5]"
    $prefix = ""
    switch ($cType) {
        "1" { $prefix = "feat" }
        "2" { $prefix = "fix" }
        "3" { $prefix = "docs" }
        "4" { $prefix = "refactor" }
        "5" { $prefix = "chore" }
        default { Write-Host "Cancelled."; Pause-Console; return }
    }

    $scope = Read-Host "Enter short scope (optional, e.g. auth, api)"
    $desc = Read-Host "Enter clear commit description"

    if (-not $desc) {
        Write-Host "[!] Description required!" -ForegroundColor Red
        Pause-Console
        return
    }

    if ($scope) {
        $finalMsg = "${prefix}(${scope}): ${desc}"
    } else {
        $finalMsg = "${prefix}: ${desc}"
    }

    Write-Host "`nCrafted Commit Message: $finalMsg" -ForegroundColor Cyan
    $doCommit = Read-Host "Execute commit now? (y/N)"
    if ($doCommit -eq "y" -or $doCommit -eq "Y") {
        git add .
        git commit -m "$finalMsg"
        Write-Host "[+] Conventional commit created!" -ForegroundColor Green
    }
    Pause-Console
}