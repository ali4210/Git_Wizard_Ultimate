BeforeAll {
    . (Join-Path $PSScriptRoot "TestHelpers.ps1")
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot "modules/commit-engine.ps1")
    $Global:DryRun = $false
    $Global:WizardMode = "advanced"
}

Describe "PS1-1: Craft-Commit only reports success when a commit was actually created" {
    BeforeEach {
        $script:repo = New-GwTestRepo
        Push-Location $script:repo
        Mock Write-Host {}
    }

    AfterEach {
        Pop-Location
        Remove-GwTestRepo -Path $script:repo
    }

    It "reports failure, not success, when the tree is clean (nothing to commit)" {
        $responses = @("2", "", "test description", "y")
        $script:i = 0
        # Note: the counter must be $script:-scoped. Pester invokes this mock body as a
        # scriptblock, and PowerShell closures give that scriptblock read access to outer
        # variables but NOT write access - an unscoped "$i++" here would silently create a
        # new local $i each call (always starting at 0) instead of advancing the real one,
        # so every Read-Host call would return $responses[0] forever.
        Mock Read-Host { $v = $responses[$script:i]; $script:i++; return $v }

        $beforeSha = (git rev-parse HEAD)
        Craft-Commit

        (git rev-parse HEAD) | Should -Be $beforeSha
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*not created*" }
        Should -Not -Invoke Write-Host -ParameterFilter { $Object -like "*Conventional commit created*" }
    }

    It "reports success and creates the commit when there is something to commit" {
        "new content" | Set-Content -Path "file1.txt"
        git add file1.txt | Out-Null

        $responses = @("2", "", "test description", "y")
        $script:i = 0
        # Note: the counter must be $script:-scoped. Pester invokes this mock body as a
        # scriptblock, and PowerShell closures give that scriptblock read access to outer
        # variables but NOT write access - an unscoped "$i++" here would silently create a
        # new local $i each call (always starting at 0) instead of advancing the real one,
        # so every Read-Host call would return $responses[0] forever.
        Mock Read-Host { $v = $responses[$script:i]; $script:i++; return $v }

        $beforeSha = (git rev-parse HEAD)
        Craft-Commit

        (git rev-parse HEAD) | Should -Not -Be $beforeSha
        (git log --oneline -1) | Should -Match "fix: test description"
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Conventional commit created*" }
    }
}
