BeforeAll {
    . (Join-Path $PSScriptRoot "TestHelpers.ps1")
    $Global:DryRun = $false
    $Global:WizardMode = "advanced"
}

Describe "PS1-3: Invoke-GitWizard reports real git failures instead of stdout-masked false success" {
    BeforeEach {
        $script:repo = New-GwTestRepo
        Push-Location $script:repo
    }

    AfterEach {
        git merge --abort 2>$null | Out-Null
        git rebase --abort 2>$null | Out-Null
        Pop-Location
        Remove-GwTestRepo -Path $script:repo
    }

    It "returns `$false on a real merge conflict (git merge writes CONFLICT text to stdout)" {
        git checkout -b feature --quiet | Out-Null
        "feature version" | Set-Content -Path "file0.txt"
        git commit -am "feature change" --quiet | Out-Null
        git checkout main --quiet | Out-Null
        "main version" | Set-Content -Path "file0.txt"
        git commit -am "main change" --quiet | Out-Null

        $result = Invoke-GitWizard merge --no-ff feature -m "merge"

        $result | Should -BeFalse
        (git status --porcelain) | Should -Match "UU"
    }

    It "returns `$false on a real rebase conflict (git pull --rebase writes conflict text to stdout)" {
        git checkout -b feature --quiet | Out-Null
        "feature version" | Set-Content -Path "file0.txt"
        git commit -am "feature change" --quiet | Out-Null
        git checkout main --quiet | Out-Null
        "main version" | Set-Content -Path "file0.txt"
        git commit -am "main change" --quiet | Out-Null
        git checkout feature --quiet | Out-Null

        $result = Invoke-GitWizard rebase main

        $result | Should -BeFalse
    }

    It "returns `$false on a no-op commit (git commit writes 'nothing to commit' to stdout on exit 1)" {
        $result = Invoke-GitWizard commit -m "nothing to commit"

        $result | Should -BeFalse
    }

    It "still returns `$true on a real successful commit (sanity check against over-correction)" {
        "new content" | Set-Content -Path "file1.txt"
        git add file1.txt | Out-Null

        $result = Invoke-GitWizard commit -m "add file1"

        $result | Should -BeTrue
        (git log --oneline -1) | Should -Match "add file1"
    }
}
