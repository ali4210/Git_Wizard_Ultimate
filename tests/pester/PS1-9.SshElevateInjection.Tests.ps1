BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:identityEnginePath = Join-Path $script:repoRoot "modules/identity-engine.ps1"
    $script:identityEngineSource = Get-Content -Path $script:identityEnginePath -Raw
    # The real code elevates via 'powershell' (Windows PowerShell); fall back to pwsh so this
    # still runs on a dev machine without Windows PowerShell installed.
    $script:shellExe = if (Get-Command powershell -ErrorAction SilentlyContinue) { "powershell" } else { "pwsh" }
}

Describe "PS1-9: elevated SSH-setup helper no longer lets a quoted path break out of its literal" {

    It "no longer interpolates the raw, unescaped script path into the executed literal" {
        $script:identityEngineSource | Should -Not -Match 'Import-Module ''\$selfScript'' -Force'
    }

    It "escapes embedded single quotes before interpolating the path" {
        $script:identityEngineSource | Should -Match 'selfScript\s*-replace\s*"''",\s*"''''"'
    }

    It "the escaping itself defeats a crafted path that previously broke out of the literal" {
        # Mirrors modules/identity-engine.ps1's Manage-SshMenu option "1" helper-script
        # construction - keep in sync with that code if it changes.
        $maliciousPath = "C:\Users\test'; Set-Content -Path `$env:GW_MARKER_FILE -Value 'INJECTED' #.ps1"
        $selfScriptEscaped = $maliciousPath -replace "'", "''"

        $helperCode = @"
Import-Module '$selfScriptEscaped' -Force -ErrorAction SilentlyContinue
"@

        $markerFile = Join-Path ([System.IO.Path]::GetTempPath()) "gw-pester-marker-$([guid]::NewGuid()).txt"
        $helperPath = Join-Path ([System.IO.Path]::GetTempPath()) "gw-pester-helper-$([guid]::NewGuid()).ps1"
        try {
            Set-Content -Path $helperPath -Value $helperCode -Encoding UTF8
            $env:GW_MARKER_FILE = $markerFile
            & $script:shellExe -NoProfile -File $helperPath 2>$null | Out-Null

            Test-Path $markerFile | Should -BeFalse
        } finally {
            Remove-Item $helperPath -Force -ErrorAction SilentlyContinue
            Remove-Item $markerFile -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\GW_MARKER_FILE -ErrorAction SilentlyContinue
        }
    }

    It "confirms the same crafted path WOULD have injected code before the fix (proves the test can catch a regression)" {
        $maliciousPath = "C:\Users\test'; Set-Content -Path `$env:GW_MARKER_FILE -Value 'INJECTED' #.ps1"
        # Deliberately UNescaped, reproducing the original vulnerable construction.
        $helperCode = @"
Import-Module '$maliciousPath' -Force -ErrorAction SilentlyContinue
"@

        $markerFile = Join-Path ([System.IO.Path]::GetTempPath()) "gw-pester-marker-$([guid]::NewGuid()).txt"
        $helperPath = Join-Path ([System.IO.Path]::GetTempPath()) "gw-pester-helper-$([guid]::NewGuid()).ps1"
        try {
            Set-Content -Path $helperPath -Value $helperCode -Encoding UTF8
            $env:GW_MARKER_FILE = $markerFile
            & $script:shellExe -NoProfile -File $helperPath 2>$null | Out-Null

            Test-Path $markerFile | Should -BeTrue
        } finally {
            Remove-Item $helperPath -Force -ErrorAction SilentlyContinue
            Remove-Item $markerFile -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\GW_MARKER_FILE -ErrorAction SilentlyContinue
        }
    }
}
