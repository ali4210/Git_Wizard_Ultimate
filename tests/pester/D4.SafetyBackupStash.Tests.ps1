BeforeAll {
    . (Join-Path $PSScriptRoot "TestHelpers.ps1")
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot "modules/repo-engine.ps1")
    $Global:DryRun = $false
    $Global:WizardMode = "advanced"
}

Describe "D4: Discard and Force Sync stash dirty/untracked state instead of destroying it" {
    BeforeEach {
        $script:repo = New-GwTestRepo
        Push-Location $script:repo

        # A dirty edit to a TRACKED file, and a brand new UNTRACKED file - both must survive.
        "dirty tracked edit" | Set-Content -Path "file0.txt"
        "untracked content" | Set-Content -Path "untracked.txt"

        Mock Write-Host {}
        Mock Confirm-DestructiveAction { return $true }
    }

    AfterEach {
        Pop-Location
        Remove-GwTestRepo -Path $script:repo
    }

    It "Discard: stashes the dirty tracked edit AND the untracked file, and both are recoverable via git stash pop" {
        $stashCountBefore = (git stash list | Measure-Object).Count

        # Drive the REAL Manage-Repo menu: "5" Reset/Undo utility -> "2" Discard -> "0" exit
        # the reset submenu -> "0" exit Manage-Repo.
        $responses = @("5", "2", "0", "0")
        $script:i = 0
        # $script: scope is required on the counter - see PS1-1's test for why an unscoped
        # "$i++" inside this scriptblock would silently never advance.
        Mock Read-Host { $v = $responses[$script:i]; $script:i++; return $v }

        Manage-Repo

        # Working tree should now be clean (discard did its job)...
        (git status --porcelain) | Should -BeNullOrEmpty
        Get-Content "file0.txt" | Should -Be "file0"
        Test-Path "untracked.txt" | Should -BeFalse

        # ...but a stash should have been created, and popping it must restore BOTH files.
        $stashCountAfter = (git stash list | Measure-Object).Count
        $stashCountAfter | Should -Be ($stashCountBefore + 1)

        git stash pop --quiet | Out-Null
        Get-Content "file0.txt" | Should -Be "dirty tracked edit"
        Test-Path "untracked.txt" | Should -BeTrue
        Get-Content "untracked.txt" | Should -Be "untracked content"
    }

    It "Force Sync: stashes the dirty tracked edit AND the untracked file before resetting to origin" {
        $bareOriginPath = Join-Path ([System.IO.Path]::GetTempPath()) "gw-pester-origin-$([guid]::NewGuid()).git"
        git init --quiet --bare $bareOriginPath | Out-Null
        git remote add origin $bareOriginPath | Out-Null
        git push --quiet -u origin main 2>$null | Out-Null

        try {
            Invoke-ForceSyncWithOrigin

            (git status --porcelain) | Should -BeNullOrEmpty
            Test-Path "untracked.txt" | Should -BeFalse

            $stashes = git stash list
            $stashes | Should -Not -BeNullOrEmpty

            git stash pop --quiet | Out-Null
            Get-Content "file0.txt" | Should -Be "dirty tracked edit"
            Test-Path "untracked.txt" | Should -BeTrue
        } finally {
            Remove-Item -Path $bareOriginPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
