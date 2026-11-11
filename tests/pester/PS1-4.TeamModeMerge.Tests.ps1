BeforeAll {
    . (Join-Path $PSScriptRoot "TestHelpers.ps1")
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot "modules/team-engine.ps1")
    $Global:DryRun = $false
    $Global:WizardMode = "advanced"
}

Describe "PS1-4: Team Mode 'Merge into main' requires confirmation before merging and pushing" {
    BeforeEach {
        $script:repo = New-GwTestRepo
        Push-Location $script:repo
        Mock Write-Host {}
        Mock Select-RemoteBranchInteractive { return "feature" }
        Mock Read-Host { return "1" }
    }

    AfterEach {
        Pop-Location
        Remove-GwTestRepo -Path $script:repo
    }

    It "does not take a backup or run any git command when the user declines confirmation" {
        Mock Confirm-DestructiveAction { return $false }
        Mock New-SafetyBackup {}
        Mock Invoke-GitWizard {}

        Invoke-TeamModeAdminDashboard

        Should -Not -Invoke New-SafetyBackup
        Should -Not -Invoke Invoke-GitWizard
    }

    It "takes a backup and merges/pushes when the user confirms" {
        Mock Confirm-DestructiveAction { return $true }
        Mock New-SafetyBackup {}
        Mock Invoke-GitWizard { return $true }

        Invoke-TeamModeAdminDashboard

        Should -Invoke New-SafetyBackup -Times 1
        Should -Invoke Invoke-GitWizard -ParameterFilter { $args[0] -eq "checkout" }
        Should -Invoke Invoke-GitWizard -ParameterFilter { $args[0] -eq "merge" }
        Should -Invoke Invoke-GitWizard -ParameterFilter { $args[0] -eq "push" }
    }
}
