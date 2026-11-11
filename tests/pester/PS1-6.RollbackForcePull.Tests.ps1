BeforeAll {
    . (Join-Path $PSScriptRoot "TestHelpers.ps1")
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot "modules/conflict-engine.ps1")
    $Global:DryRun = $false
    $Global:WizardMode = "advanced"
}

Describe "PS1-6: Rollback-force-pull aborts instead of resetting the wrong branch" {
    BeforeEach {
        $script:repo = New-GwTestRepo
        Push-Location $script:repo
        $script:initialSha = (git rev-parse HEAD)

        git checkout -b current --quiet | Out-Null
        "unique change on current" | Set-Content -Path "current-only.txt"
        git add current-only.txt | Out-Null
        git commit --quiet -m "unique commit on current" | Out-Null
        $script:currentSha = (git rev-parse HEAD)

        $global:ConfigDir = Join-Path $script:repo ".gwconfig"
        New-Item -ItemType Directory -Path $global:ConfigDir -Force | Out-Null
        $global:TargetRepoDir = $script:repo

        # Simulated recorded rollback state: the branch it points to ('ghost-branch') no
        # longer exists locally, but the recorded commit (the repo's real initial commit)
        # still does - this is exactly the scenario that used to reset the wrong branch.
        $rbFile = Get-RollbackFile pull
        $rb = [PSCustomObject]@{
            Branch   = "ghost-branch"
            Time     = (Get-Date).ToString("o")
            HeadSha  = $script:initialSha
            Tag      = "backup/does-not-matter"
            StashMsg = $null
        }
        $rb | ConvertTo-Json | Set-Content -Path $rbFile

        Mock Write-Host {}
        Mock Confirm-DestructiveAction { return $true }
    }

    AfterEach {
        Pop-Location
        Remove-GwTestRepo -Path $script:repo
    }

    It "leaves the currently-checked-out branch untouched when the recorded branch no longer exists" {
        Invoke-RollbackForcePull

        (git rev-parse --abbrev-ref HEAD) | Should -Be "current"
        (git rev-parse HEAD) | Should -Be $script:currentSha
        Test-Path "current-only.txt" | Should -BeTrue
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*rollback aborted*" }
    }
}
