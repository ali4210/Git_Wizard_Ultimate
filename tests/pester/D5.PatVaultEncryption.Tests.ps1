# NOTE ON PLATFORM: Protect-PatVaultToken/Unprotect-PatVaultToken use Windows DPAPI
# (ConvertTo-SecureString -AsPlainText / ConvertFrom-SecureString with no -Key), which is
# tied to the Windows user account. On non-Windows PowerShell these cmdlets either throw
# "Windows PowerShell is required" / PlatformNotSupportedException, or (on some PS 7 builds)
# fall back to behavior that is NOT the real DPAPI protection this fix relies on. These tests
# are only a meaningful verification of D5 when run on actual Windows PowerShell 5.1 - see the
# final report for exactly what could/couldn't be executed in this session's Linux sandbox.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot "modules/identity-engine.ps1")
    $script:IsWindowsPlatform = $env:OS -eq "Windows_NT" -or $PSVersionTable.Platform -eq "Win32NT" -or (-not $PSVersionTable.Platform)
}

Describe "D5: PAT vault entries are encrypted at rest (Windows DPAPI) instead of plaintext" {

    It "never writes the plaintext token to the encrypted blob" -Skip:(-not $script:IsWindowsPlatform) {
        $plainToken = "ghp_PESTERTESTTOKEN1234567890"
        $encrypted = Protect-PatVaultToken -PlainToken $plainToken

        $encrypted | Should -Not -Match [regex]::Escape($plainToken)
    }

    It "round-trips: Unprotect-PatVaultToken recovers exactly what was encrypted" -Skip:(-not $script:IsWindowsPlatform) {
        $plainToken = "ghp_PESTERTESTTOKEN1234567890"
        $encrypted = Protect-PatVaultToken -PlainToken $plainToken

        $decrypted = Unprotect-PatVaultToken -StoredValue $encrypted

        $decrypted | Should -Be $plainToken
    }

    It "passes a legacy plaintext entry through unchanged (so migration can detect it)" {
        $legacyPlainEntry = "github_pat_PESTERLEGACYTOKEN"

        $result = Unprotect-PatVaultToken -StoredValue $legacyPlainEntry

        $result | Should -Be $legacyPlainEntry
    }

    It "Invoke-PatVaultMigration re-encrypts legacy plaintext entries and leaves the file with no plaintext token" -Skip:(-not $script:IsWindowsPlatform) {
        $vaultFile = Join-Path ([System.IO.Path]::GetTempPath()) "gw-pester-vault-$([guid]::NewGuid()).env"
        $plainToken = "ghp_PESTERLEGACYMIGRATETOKEN"
        Set-Content -Path $vaultFile -Value "legacy-alias=$plainToken"

        try {
            Invoke-PatVaultMigration -VaultFile $vaultFile

            $rawContent = Get-Content -Path $vaultFile -Raw
            $rawContent | Should -Not -Match [regex]::Escape($plainToken)

            $storedLine = (Get-Content $vaultFile) | Where-Object { $_ -match "^legacy-alias=" }
            $storedValue = ($storedLine -split "=", 2)[1]
            (Unprotect-PatVaultToken -StoredValue $storedValue) | Should -Be $plainToken
        } finally {
            Remove-Item -Path $vaultFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not touch a vault file that already has no legacy plaintext entries" -Skip:(-not $script:IsWindowsPlatform) {
        $vaultFile = Join-Path ([System.IO.Path]::GetTempPath()) "gw-pester-vault-$([guid]::NewGuid()).env"
        $encrypted = Protect-PatVaultToken -PlainToken "ghp_ALREADYENCRYPTED"
        Set-Content -Path $vaultFile -Value "alias=$encrypted"
        $before = Get-Content -Path $vaultFile -Raw

        Invoke-PatVaultMigration -VaultFile $vaultFile

        (Get-Content -Path $vaultFile -Raw) | Should -Be $before
    }
}
