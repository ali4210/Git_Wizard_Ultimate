# ==============================================================================
# ENGINE NAME: identity-engine.ps1 (PowerShell 5.1 Clean Edition - Back=0)
# MIRRORS LINUX git-wizard.sh MODULE 1 STRUCTURE
# ==============================================================================

function Clean-RemoteUrl ($url) {
    if (-not $url) { return "" }
    $clean = $url -replace '(?i)^git remote (add|set-url) origin ', ''
    return $clean.Trim()
}

# ==============================================================================
# VAULT SECURITY HELPERS (Uses .NET Cryptography)
# ==============================================================================
function Get-HashedPass {
    param([string]$PlainText)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $hash = $sha256.ComputeHash($bytes)
    return -join ($hash | ForEach-Object { $_.ToString("x2") })
}

function Get-VaultConfig {
    $vaultConfigPath = Join-Path $Global:ConfigDir ".vault_config.json"
    $vaultPassHash = ""
    $vaultLockStatus = "unlocked"
    if (Test-Path $vaultConfigPath) {
        try {
            $cfg = Get-Content -Path $vaultConfigPath -Raw | ConvertFrom-Json
            if ($cfg.PassHash) { $vaultPassHash = $cfg.PassHash }
            if ($cfg.LockStatus) { $vaultLockStatus = $cfg.LockStatus }
        } catch {}
    }
    return @{ Hash = $vaultPassHash; Status = $vaultLockStatus }
}

function Set-VaultConfig {
    param([string]$Hash, [string]$Status)
    $vaultConfigPath = Join-Path $Global:ConfigDir ".vault_config.json"
    $cfg = [PSCustomObject]@{ PassHash = $Hash; LockStatus = $Status }
    $cfg | ConvertTo-Json | Set-Content -Path $vaultConfigPath -Encoding UTF8
}

function Request-VaultAccess {
    $vCfg = Get-VaultConfig
    if ([string]::IsNullOrEmpty($vCfg.Hash)) {
        Write-Host "[i] First time using the vault. Please create a master password." -ForegroundColor Yellow
        Write-Host "    (You can toggle the lock on/off later in Vault Security Settings)" -ForegroundColor Cyan
        while ($true) {
            $p1 = Read-Host "    Create vault password" -AsSecureString
            $p2 = Read-Host "    Confirm vault password" -AsSecureString
            $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
            $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
            if ($plain1 -eq $plain2 -and -not [string]::IsNullOrEmpty($plain1)) {
                $newHash = Get-HashedPass -PlainText $plain1
                Set-VaultConfig -Hash $newHash -Status "unlocked"
                Write-Host "[+] Vault password created. Vault is UNLOCKED for easy access." -ForegroundColor Green
                return $true
            } else {
                Write-Host "[!] Passwords did not match or were empty. Try again." -ForegroundColor Red
            }
        }
    }
    if ($vCfg.Status -eq "unlocked") { return $true }
    if ($vCfg.Status -eq "locked") {
        Write-Host "[LOCKED] Vault is LOCKED. Enter master password to proceed." -ForegroundColor Yellow
        $attempts = 3
        while ($attempts -gt 0) {
            $pInput = Read-Host "    Password" -AsSecureString
            $plainInput = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pInput))
            $inputHash = Get-HashedPass -PlainText $plainInput
            if ($inputHash -eq $vCfg.Hash) {
                Write-Host "[+] Access granted." -ForegroundColor Green
                return $true
            } else {
                $attempts--
                Write-Host "[!] Incorrect password. $attempts attempts remaining." -ForegroundColor Red
            }
        }
        Write-Host "[!] Access denied. Returning to menu." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $false
    }
    return $false
}

function Show-VaultSecuritySettings {
    while ($true) {
        Show-Header
        $vCfg = Get-VaultConfig
        $statusColor = "Green"
        $statusText = "UNLOCKED (No password required to view)"
        if ($vCfg.Status -eq "locked") {
            $statusColor = "Red"
            $statusText = "LOCKED (Password required to view)"
        }
        if ([string]::IsNullOrEmpty($vCfg.Hash)) {
            $statusText = "NOT INITIALIZED (No password set yet)"
            $statusColor = "Yellow"
        }
        Write-Host "  VAULT SECURITY SETTINGS`n" -ForegroundColor Yellow
        Write-Host "  Current Status: " -NoNewline
        Write-Host $statusText -ForegroundColor $statusColor
        Write-Host "`n  [1] Set / Change Vault Password" -ForegroundColor Green
        Write-Host "  [2] Toggle Vault Lock (Currently: $($vCfg.Status.ToUpper()))" -ForegroundColor Green
        Write-Host "  [0] Back to Vault`n"
        Write-Host "====================================================================" -ForegroundColor Cyan
        $secChoice = Read-Host "Select choice [0-2]"
        switch ($secChoice) {
            "1" {
                Write-Host "`nSetting new vault password..." -ForegroundColor Cyan
                while ($true) {
                    $p1 = Read-Host "    Enter NEW vault password" -AsSecureString
                    $p2 = Read-Host "    Confirm NEW vault password" -AsSecureString
                    $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
                    $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
                    if ($plain1 -eq $plain2 -and -not [string]::IsNullOrEmpty($plain1)) {
                        $newHash = Get-HashedPass -PlainText $plain1
                        $currentStatus = if ($vCfg.Status) { $vCfg.Status } else { "unlocked" }
                        Set-VaultConfig -Hash $newHash -Status $currentStatus
                        Write-Host "[+] Vault password changed successfully!" -ForegroundColor Green
                        Write-WizardActionLog "Vault password changed"
                        Start-Sleep -Seconds 1
                        break
                    } else {
                        Write-Host "[!] Passwords did not match or were empty." -ForegroundColor Red
                    }
                }
                Pause-Console
            }
            "2" {
                if ([string]::IsNullOrEmpty($vCfg.Hash)) {
                    Write-Host "`n[!] Please set a password first (Option 1)." -ForegroundColor Red
                    Pause-Console
                    continue
                }
                if ($vCfg.Status -eq "unlocked") {
                    Write-Host "`n[i] Locking the vault will require a password to view/save/delete tokens." -ForegroundColor Yellow
                    $doLock = Read-Host "    Lock the vault now? (y/N)"
                    if ($doLock -match '^[Yy]') {
                        Set-VaultConfig -Hash $vCfg.Hash -Status "locked"
                        Write-Host "[+] Vault is now LOCKED." -ForegroundColor Red
                        Write-WizardActionLog "Vault locked"
                    }
                } else {
                    Write-Host "`n[i] Unlocking the vault will allow access WITHOUT a password." -ForegroundColor Cyan
                    $doUnlock = Read-Host "    Unlock the vault now? (y/N)"
                    if ($doUnlock -match '^[Yy]') {
                        Set-VaultConfig -Hash $vCfg.Hash -Status "unlocked"
                        Write-Host "[+] Vault is now UNLOCKED." -ForegroundColor Green
                        Write-WizardActionLog "Vault unlocked"
                    }
                }
                Pause-Console
            }
            "0" { return }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ==============================================================================
# PERSONAL ACCESS TOKEN (PAT) VAULT MANAGER
# ==============================================================================
function Manage-PatVault {
    $vaultFile = Join-Path $Global:ConfigDir "pat_vault.env"
    if (-not (Test-Path $vaultFile)) { New-Item -Path $vaultFile -ItemType File -Force | Out-Null }
    while ($true) {
        Show-Header
        $vCfg = Get-VaultConfig
        $lockIcon = if ($vCfg.Status -eq "locked") { "[LOCKED]" } else { "[UNLOCKED]" }
        Write-Host "  PERSONAL ACCESS TOKEN (PAT) VAULT $lockIcon`n" -ForegroundColor Yellow
        Write-Host "  GitHub only shows a PAT once. This vault securely stores it for reuse.`n" -ForegroundColor Cyan
        Write-Host "  [1] Create New Token (Opens browser + Save to Vault)" -ForegroundColor Green
        Write-Host "  [2] View Saved Tokens" -ForegroundColor Green
        Write-Host "  [3] Delete a Saved Token" -ForegroundColor Red
        Write-Host "  [4] Vault Security Settings (Password & Lock Toggle)" -ForegroundColor Cyan
        Write-Host "  [0] Back to Module 1`n"
        Write-Host "====================================================================" -ForegroundColor Cyan
        $patChoice = Read-Host "Select choice [0-4]"
        switch ($patChoice) {
            "1" {
                if (-not (Request-VaultAccess)) { continue }
                Write-Host "`nWhat type of token do you want to create?`n" -ForegroundColor Cyan
                Write-Host "  [1] Fine-grained token (Recommended)" -ForegroundColor Green
                Write-Host "  [2] Classic token (Legacy)" -ForegroundColor Green
                Write-Host "  [0] Cancel" -ForegroundColor Green
                $tokType = Read-Host "Select [0-2]"
                $tokenUrl = ""
                switch ($tokType) {
                    "1" { $tokenUrl = "https://github.com/settings/personal-access-tokens/new" }
                    "2" { $tokenUrl = "https://github.com/settings/tokens/new" }
                    default { continue }
                }
                Write-Host "`n[+] Attempting to open your browser to GitHub..." -ForegroundColor Green
                Write-Host "[i] If your browser didn't open, copy the URL below.`n" -ForegroundColor Yellow
                Write-Host "--------------------- GITHUB URL ---------------------" -ForegroundColor Cyan
                Write-Host $tokenUrl -ForegroundColor Green
                Write-Host "----------------------------------------------------`n" -ForegroundColor Cyan
                try { Start-Process $tokenUrl } catch {}
                $newToken = Read-Host "Paste your new token here (or press ENTER to cancel)"
                if ([string]::IsNullOrEmpty($newToken)) { Write-Host "[i] Cancelled." -ForegroundColor Yellow; Pause-Console; continue }
                if ($newToken -notmatch "^(ghp_|github_pat_)") { Write-Host "[!] Invalid token format." -ForegroundColor Red; Pause-Console; continue }
                Write-Host ""
                $tokenAlias = Read-Host "Enter a name/alias for this token (e.g., Windows-Jenkins)"
                if ([string]::IsNullOrEmpty($tokenAlias)) { $tokenAlias = "token-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
                $existingContent = ""; if (Test-Path $vaultFile) { $existingContent = Get-Content $vaultFile -Raw }
                if ($existingContent -match "^$tokenAlias=") { Write-Host "[!] Alias already exists." -ForegroundColor Red; Pause-Console; continue }
                Add-Content -Path $vaultFile -Value "$tokenAlias=$newToken"
                Write-Host "`n[+] Token securely saved to vault as '$tokenAlias'!" -ForegroundColor Green
                Write-WizardActionLog "Saved new PAT to vault: $tokenAlias"
                Pause-Console
            }
            "2" {
                if (-not (Request-VaultAccess)) { continue }
                Write-Host "`n======================= SAVED TOKENS =======================`n" -ForegroundColor Cyan
                if (-not (Test-Path $vaultFile) -or (Get-Item $vaultFile).Length -eq 0) {
                    Write-Host "[i] Vault is empty." -ForegroundColor Yellow
                } else {
                    Get-Content $vaultFile | ForEach-Object {
                        if ($_.Trim() -and $_ -match "^([^=]+)=(.*)$") {
                            Write-Host "  [$($matches[1])]" -ForegroundColor Green
                            Write-Host "      Token: $($matches[2])`n" -ForegroundColor Cyan
                        }
                    }
                }
                Pause-Console
            }
            "3" {
                if (-not (Request-VaultAccess)) { continue }
                if (-not (Test-Path $vaultFile) -or (Get-Item $vaultFile).Length -eq 0) { Write-Host "`n[i] Vault is empty." -ForegroundColor Yellow; Pause-Console; continue }
                Write-Host "`nSELECT A TOKEN TO DELETE:`n" -ForegroundColor Red
                $idx = 1; $lines = Get-Content $vaultFile
                foreach ($line in $lines) { if ($line.Trim() -and $line -match "^([^=]+)=") { Write-Host "  [$idx] $($matches[1])" -ForegroundColor Red; $idx++ } }
                Write-Host ""
                $delNum = Read-Host "Enter token number to delete (or ENTER to cancel)"
                if (-not [string]::IsNullOrEmpty($delNum)) {
                    $currentIdx = 1; $newContent = @(); $deletedAlias = ""
                    foreach ($line in $lines) {
                        if ($line.Trim() -and $line -match "^([^=]+)=(.*)$") {
                            if ($currentIdx -ne [int]$delNum) { $newContent += $line } else { $deletedAlias = $matches[1] }
                            $currentIdx++
                        } else { $newContent += $line }
                    }
                    Write-Host "`n[?] How do you want to delete '$deletedAlias'?" -ForegroundColor Yellow
                    Write-Host "  [L] Local vault only" -ForegroundColor Green
                    Write-Host "  [B] Both Local + GitHub" -ForegroundColor Red
                    $delScope = Read-Host "    Choose [L/B] (Default: L)"
                    if ($delScope -match '^[Bb]') {
                        Write-Host "`n--> Searching GitHub for '$deletedAlias'..." -ForegroundColor Cyan
                        $ghTokenId = $null
                        try { $ghTokenId = gh api user/personal-access-tokens --jq ".[] | select(.name == `"$deletedAlias`") | .id" 2>$null } catch {}
                        if ($ghTokenId) {
                            Write-Host "--> Found on GitHub. Revoking..." -ForegroundColor Cyan
                            if (gh api -X DELETE "user/personal-access-tokens/$ghTokenId" 2>$null) { Write-Host "[+] Revoked from GitHub!" -ForegroundColor Green }
                            else { Write-Host "[!] API failed." -ForegroundColor Red; try { Start-Process "https://github.com/settings/personal-access-tokens" } catch {} }
                        } else {
                            Write-Host "[i] Could not auto-find on GitHub. OPENING BROWSER..." -ForegroundColor Yellow
                            try { Start-Process "https://github.com/settings/personal-access-tokens" } catch {}
                        }
                        Write-Host "`n------------------- MANUAL REVOKE URLS -------------------" -ForegroundColor Cyan
                        Write-Host "    Fine-Grained: https://github.com/settings/personal-access-tokens" -ForegroundColor Green
                        Write-Host "    Classic:      https://github.com/settings/tokens" -ForegroundColor Green
                        Write-Host "------------------------------------------------------`n" -ForegroundColor Cyan
                    }
                    Set-Content -Path $vaultFile -Value $newContent
                    Write-Host "[+] Removed '$deletedAlias' from local vault." -ForegroundColor Green
                    Write-WizardActionLog "Deleted PAT from local vault: $deletedAlias"
                }
                Pause-Console
            }
            "4" { if (Request-VaultAccess) { Show-VaultSecuritySettings } }
            "0" { return }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}
# ==============================================================================
# SSH GITHUB SETUP END-TO-END
# ==============================================================================
function Invoke-SshGithubSetupE2E {
    Show-Header
    Write-Host "  SSH GITHUB SETUP END-TO-END`n" -ForegroundColor Yellow
    Write-Host "This will automatically:" -ForegroundColor Cyan
    Write-Host "  1. Check for existing SSH keys"
    Write-Host "  2. Generate a new ED25519 key (with your custom title) if needed"
    Write-Host "  3. Start ssh-agent & load the key"
    Write-Host "  4. Upload the public key to your GitHub account via API"
    Write-Host "  5. Test the SSH connection to GitHub`n"

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "[!] 'gh' CLI is required. Install via: winget install GitHub.cli" -ForegroundColor Red
        Pause-Console
        return
    }

    $authCheck = $null
    try { $authCheck = gh auth status 2>&1 } catch {}
    if ($authCheck -match "not logged in|error") {
        Write-Host "[!] 'gh' is not logged in. Run: gh auth login" -ForegroundColor Red
        Pause-Console
        return
    }

    # SAFELY extract the username using jq to prevent JSON injection
    $ghUser = $null
    try { $ghUser = gh api user --jq '.login' 2>$null } catch {}

    if (-not $ghUser -or $ghUser -match "message|error") {
        Write-Host "[!] Could not fetch GitHub username. GitHub might be down or your 'gh' token is invalid." -ForegroundColor Red
        Pause-Console
        return
    }

    Write-Host "[+] GitHub CLI authenticated as: $ghUser`n" -ForegroundColor Green
    $customTitle = ""
    $sshDir = "$env:USERPROFILE\.ssh"
    $keyPath = Join-Path $sshDir "id_ed25519"
    $pubPath = "$keyPath.pub"
    $keyExists = $false

    Write-Host "[1/5] Checking for existing SSH keys..." -ForegroundColor Cyan
    if ((Test-Path $keyPath) -and (Test-Path $pubPath)) {
        $keyExists = $true
        Write-Host "[i] Found existing key: $keyPath" -ForegroundColor Yellow
        $genNew = Read-Host "    Generate a NEW key instead? (y/N)"
        if ($genNew -match '^[Yy]') {
            $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
            $keyPath = Join-Path $sshDir "id_ed25519-gitwizard-$ts"
            $pubPath = "$keyPath.pub"
            $keyExists = $false
        }
    }

    if (-not $keyExists) {
        Write-Host "`n[2/5] Naming your new SSH key..." -ForegroundColor Cyan
        $customTitle = Read-Host "    Enter a title for this key (e.g., 'My-Windows-PC')"
        if ([string]::IsNullOrEmpty($customTitle)) { $customTitle = "git-wizard-auto-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
        Write-Host "`n    Generating ED25519 SSH key..." -ForegroundColor Cyan
        if (-not (Test-Path $sshDir)) { New-Item -Path $sshDir -ItemType Directory -Force | Out-Null }

        # Use plain string for comment to avoid parsing bugs
        $comment = "$ghUser@git-wizard"
        ssh-keygen -t ed25519 -C $comment -f $keyPath -N '""'

        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] ssh-keygen failed." -ForegroundColor Red
            Pause-Console
            return
        }
        Write-Host "[+] Key generated: $keyPath" -ForegroundColor Green
        Write-WizardActionLog "Generated new SSH key: $keyPath (Title: $customTitle)"
    } else {
        Write-Host "[+] Using existing key: $keyPath" -ForegroundColor Green
        Write-Host "[2/5] Skipped - key already exists." -ForegroundColor Cyan
    }

    Write-Host "`n[3/5] Starting ssh-agent & loading key..." -ForegroundColor Cyan
    try {
        if (-not (Get-Process ssh-agent -ErrorAction SilentlyContinue)) { Start-Process ssh-agent -ErrorAction SilentlyContinue }
        ssh-add $keyPath 2>$null
        Write-Host "[+] Key added to ssh-agent." -ForegroundColor Green
    } catch { Write-Host "[!] Could not start ssh-agent. Connection test will confirm." -ForegroundColor Yellow }

    Write-Host "`n[3.5/5] Checking if this key is already on your GitHub account..." -ForegroundColor Cyan
    $needsUpload = $true
    $localFp = $null
    if (Test-Path $pubPath) {
        $fpOutput = ssh-keygen -lf $pubPath 2>$null
        if ($fpOutput -match 'SHA256:(\S+)') { $localFp = "SHA256:$($matches[1])" }
    }
    if ($localFp) {
        $ghFingerprints = $null
        try { $ghFingerprints = gh api user/keys --jq '.[].fingerprint' 2>$null } catch {}
        if ($ghFingerprints -contains $localFp) {
            $needsUpload = $false
            Write-Host "[i] This exact key is ALREADY on your GitHub account." -ForegroundColor Yellow
        } else {
            Write-Host "[+] This key is NOT on GitHub yet - upload will proceed." -ForegroundColor Green
        }
    }

    Write-Host "`n[4/5] Uploading public key to GitHub account '$ghUser'..." -ForegroundColor Cyan
    if (-not $needsUpload) {
        Write-Host "    Skipped - key already present on GitHub." -ForegroundColor Cyan
    } else {
        $keyTitle = if ($customTitle) { $customTitle } else { "git-wizard-upload-$env:COMPUTERNAME" }
        $pubKeyContent = Get-Content $pubPath -Raw

        # Construct the JSON payload
        $body = @{
            title = $keyTitle
            key   = $pubKeyContent.Trim()
        } | ConvertTo-Json -Compress

        $uploadSuccess = $false
        try {
            # Write JSON to a temp file for 100% reliable Windows compatibility
            $tempFile = Join-Path $env:TEMP "gw_ssh_upload_$(Get-Random).json"
            Set-Content -Path $tempFile -Value $body -Encoding UTF8
            gh api -X POST "/user/keys" --input "$tempFile" 2>&1 | Out-Null
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Public key uploaded to GitHub via API! Title: $keyTitle" -ForegroundColor Green
                Write-WizardActionLog "Uploaded SSH key to GitHub via API: $keyTitle"
                $uploadSuccess = $true
            } else {
                Write-Host "[!] API Upload failed. Trying fallback method..." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[!] API Upload failed. Trying fallback method..." -ForegroundColor Yellow
        }

        if (-not $uploadSuccess) {
            $uploadOutput = gh ssh-key add $pubPath --title "$keyTitle" 2>&1
            if ($LASTEXITCODE -eq 0 -and $uploadOutput -notmatch 'error|fail|already') {
                Write-Host "[+] Public key uploaded via fallback! Title: $keyTitle" -ForegroundColor Green
                Write-WizardActionLog "Uploaded SSH key to GitHub via fallback: $keyTitle"
            } elseif ($uploadOutput -match 'already') {
                Write-Host "[i] This key is already on GitHub." -ForegroundColor Yellow
            } else {
                Write-Host "[!] All upload methods failed.`nFallback - copy manually:`n---- PUBLIC KEY ----" -ForegroundColor Red
                Get-Content $pubPath
                Write-Host "---- END KEY ----" -ForegroundColor Red
                Pause-Console
                return
            }
        }
    }

    Write-Host "`n[5/5] Testing SSH connection to GitHub..." -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    $testOutput = ssh -T git@github.com 2>&1 | Out-String
    if ($testOutput -match "successfully authenticated") { Write-Host "[+] SSH CONNECTION TO GITHUB IS WORKING!" -ForegroundColor Green }
    elseif ($testOutput -match "permission denied") { Write-Host "[!] Permission denied. Wait 30s and test manually." -ForegroundColor Red }
    else { Write-Host "[i] Unexpected response: $testOutput" -ForegroundColor Yellow }

    Write-Host "`n========================================================" -ForegroundColor Green
    Write-Host "  SSH-TO-GITHUB PIPELINE COMPLETE!" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  Key file:      $keyPath" -ForegroundColor Cyan
    Write-Host "  GitHub user:   $ghUser" -ForegroundColor Cyan
    Write-Host "  Upload Title:  $customTitle" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-WizardActionLog "One-click SSH-to-GitHub pipeline completed (key: $keyPath)"
    Pause-Console
}
# ==============================================================================
# MANAGE GITHUB SSH KEYS
# ==============================================================================
function Manage-GithubSshKeys {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host "[!] 'gh' CLI is required." -ForegroundColor Red; Pause-Console; return }
    $ghUser = gh api user --jq '.login' 2>$null
    while ($true) {
        Show-Header
        Write-Host "  GITHUB SSH KEY MANAGER ($ghUser)`n" -ForegroundColor Yellow
        Write-Host "  [1] List & Manage SSH Keys (Table)" -ForegroundColor Green
        Write-Host "  [2] PURGE ALL SSH KEYS" -ForegroundColor Red
        Write-Host "  [0] Back to SSH GitHub Manager`n"
        Write-Host "====================================================================" -ForegroundColor Cyan
        $keyMgrChoice = Read-Host "Select choice [0-2]"
        switch ($keyMgrChoice) {
            "1" {
                while ($true) {
                    $keysJson = gh api user/keys --paginate 2>$null
                    if (-not $keysJson) { Write-Host "[!] Failed to fetch keys." -ForegroundColor Red; Pause-Console; break }
                    try { $keysObj = $keysJson | ConvertFrom-Json; $keyCount = $keysObj.Count } catch { $keyCount = 0 }
                    Clear-Host
                    Write-Host "  GITHUB SSH KEY MANAGER ($ghUser)`n" -ForegroundColor Yellow
                    Write-Host "+------------+------------------------------+------------------------------------------+------------+" -ForegroundColor Cyan
                    Write-Host "| ID         | TITLE                        | FINGERPRINT                              | ADDED ON   |" -ForegroundColor White
                    Write-Host "+------------+------------------------------+------------------------------------------+------------+" -ForegroundColor Cyan
                    if ($keyCount -eq 0) { Write-Host "|            | No keys found                |                                          |            |" -ForegroundColor Cyan }
                    else {
                        foreach ($k in $keysObj) {
                            $id = "$($k.id)".PadRight(10)
                            $title = if ($k.title) { "$($k.title)".Substring(0, [math]::Min(28, $k.title.Length)).PadRight(28) } else { "Untitled".PadRight(28) }
                            $fp = if ($k.fingerprint) { "$($k.fingerprint)".Substring(0, [math]::Min(40, $k.fingerprint.Length)).PadRight(40) } else { "N/A".PadRight(40) }
                            $date = if ($k.created_at) { "$($k.created_at.Substring(0,10))".PadRight(10) } else { "Unknown".PadRight(10) }
                            Write-Host "| $id | $title | $fp | $date |" -ForegroundColor Cyan
                        }
                    }
                    Write-Host "+------------+------------------------------+------------------------------------------+------------+" -ForegroundColor Cyan
                    if ($keyCount -eq 0) { Write-Host "`n[i] No keys to manage." -ForegroundColor Yellow; Pause-Console; break }
                    Write-Host ""
                    $listAction = Read-Host "Press [D] to delete a key, or [ENTER] to go back"
                    if ($listAction -match '^[Dd]') {
                        Write-Host "`nSELECT A KEY TO DELETE:`n" -ForegroundColor Red
                        foreach ($k in $keysObj) { Write-Host "  [$($k.id)] $($k.title)" -ForegroundColor Red }
                        Write-Host ""
                        $delId = Read-Host "Enter the ID of the key to delete (or ENTER to cancel)"
                        if (-not [string]::IsNullOrEmpty($delId)) {
                            $delTitle = ($keysObj | Where-Object { $_.id -eq [int]$delId } | Select-Object -First 1).title
                            if (-not $delTitle) { Write-Host "[!] Invalid ID." -ForegroundColor Red; Pause-Console; continue }
                            if (Confirm-DestructiveAction "Permanently delete SSH key '$delTitle' (ID: $delId) from GitHub") {
                                if (gh api -X DELETE "/user/keys/$delId" 2>$null) { Write-Host "[+] Successfully deleted: $delTitle" -ForegroundColor Green; Write-WizardActionLog "Deleted GitHub SSH key: $delTitle" }
                                else { Write-Host "[!] Failed to delete." -ForegroundColor Red }
                            } else { Write-Host "`n[i] Cancelled." -ForegroundColor Yellow }
                        }
                        Pause-Console
                        continue
                    } else { break }
                }
            }
            "2" {
                Write-Host "`nFetching all SSH keys for purge preview...`n" -ForegroundColor Cyan
                $keysJson = gh api user/keys --paginate 2>$null
                if (-not $keysJson) { Write-Host "[!] Failed to fetch keys." -ForegroundColor Red; Pause-Console; continue }
                try { $keysObj = $keysJson | ConvertFrom-Json; $keyCount = $keysObj.Count } catch { $keyCount = 0 }
                if ($keyCount -eq 0) { Write-Host "[+] 0 keys. Nothing to purge." -ForegroundColor Green; Pause-Console; continue }
                Clear-Host
                Write-Host "  GITHUB SSH KEY MANAGER ($ghUser)`n" -ForegroundColor Yellow
                Write-Host "+------------+------------------------------+------------------------------------------+------------+" -ForegroundColor Cyan
                Write-Host "| ID         | TITLE                        | FINGERPRINT                              | ADDED ON   |" -ForegroundColor Red
                Write-Host "+------------+------------------------------+------------------------------------------+------------+" -ForegroundColor Cyan
                foreach ($k in $keysObj) {
                    $id = "$($k.id)".PadRight(10)
                    $title = if ($k.title) { "$($k.title)".Substring(0, [math]::Min(28, $k.title.Length)).PadRight(28) } else { "Untitled".PadRight(28) }
                    $fp = if ($k.fingerprint) { "$($k.fingerprint)".Substring(0, [math]::Min(40, $k.fingerprint.Length)).PadRight(40) } else { "N/A".PadRight(40) }
                    $date = if ($k.created_at) { "$($k.created_at.Substring(0,10))".PadRight(10) } else { "Unknown".PadRight(10) }
                    Write-Host "| $id | $title | $fp | $date |" -ForegroundColor Red
                }
                Write-Host "+------------+------------------------------+------------------------------------------+------------+" -ForegroundColor Cyan
                Write-Host "`n  WARNING: NO machine will be able to SSH until you add a new key.`n" -ForegroundColor Red
                if (Confirm-DestructiveAction "Purge ALL $keyCount SSH key(s) from your GitHub account") {
                    Write-Host "`n--> Purging all SSH keys..." -ForegroundColor Cyan
                    $successCount = 0; $failCount = 0
                    foreach ($k in $keysObj) {
                        if (gh api -X DELETE "/user/keys/$($k.id)" 2>$null) { Write-Host "  X Deleted: $($k.title)" -ForegroundColor Green; $successCount++ }
                        else { Write-Host "  X FAILED: $($k.title)" -ForegroundColor Red; $failCount++ }
                    }
                    Write-Host "`n========================================================" -ForegroundColor Green
                    Write-Host "  PURGE COMPLETE (Deleted: $successCount | Failed: $failCount)" -ForegroundColor Green
                    Write-Host "========================================================" -ForegroundColor Green
                    Write-WizardActionLog "PURGED all GitHub SSH keys"
                } else { Write-Host "`n[i] Purge cancelled." -ForegroundColor Yellow }
                Pause-Console
            }
            "0" { return }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ==============================================================================
# SSH GITHUB MANAGER (Sub-Hub)
# ==============================================================================
function Manage-SshGithubMenu {
    while ($true) {
        Show-Header
        Write-Host "  SSH GITHUB MANAGER`n" -ForegroundColor Yellow
        Write-Host "  [1] SSH GitHub Setup End-to-End (Auto-generate + Auto-upload + Test)" -ForegroundColor Green
        Write-Host "  [2] Manage GitHub SSH Keys (Interactive Table & Purge)" -ForegroundColor Green
        Write-Host "  [3] Test SSH Connection to GitHub" -ForegroundColor Green
        Write-Host "  [0] Back to SSH Manager`n"
        Write-Host "====================================================================" -ForegroundColor Cyan
        $ghSshChoice = Read-Host "Select choice [0-3]"
        switch ($ghSshChoice) {
            "1" { Invoke-SshGithubSetupE2E }
            "2" { Manage-GithubSshKeys }
            "3" { Write-Host "`n--> Testing SSH connection to GitHub..." -ForegroundColor Green; ssh -T git@github.com 2>&1 | Out-String | Write-Host; Write-Host "[i] 'does not provide shell access' indicates success!" -ForegroundColor Green; Pause-Console }
            "0" { return }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ==============================================================================
# SSH MANAGER HUB (Orchestrator)
# ==============================================================================
function Manage-SshMenu {
    while ($true) {
        Show-Header
        Write-Host "  SSH MANAGER (Keys, Services & GitHub Integration)`n" -ForegroundColor Yellow
        Write-Host "  [1] Install & Start SSH Client Service (For GitHub)" -ForegroundColor Green
        Write-Host "  [2] Generate New SSH Key (ED25519) & Show Public Key" -ForegroundColor Green
        Write-Host "  [3] SSH GitHub Manager (Setup End-to-End, List, Test & Purge)" -ForegroundColor Green
        Write-Host "  [0] Back to Module 1`n"
        Write-Host "====================================================================" -ForegroundColor Cyan
        $sshChoice = Read-Host "Select choice [0-3]"
        switch ($sshChoice) {
            "1" {
                Show-Header
                Write-Host "  SSH CLIENT & SERVER INSTALLER (Windows)`n" -ForegroundColor Yellow

                $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

                if (-not $isAdmin) {
                    Write-Host "[i] Server-side setup (sshd, firewall, service startup type) needs Administrator rights." -ForegroundColor Yellow
                    Write-Host "    A Windows permission prompt will appear now — click YES to continue.`n" -ForegroundColor Cyan
                    Start-Sleep -Milliseconds 800

                    $selfScript = $MyInvocation.MyCommand.Path
                    if (-not $selfScript) { $selfScript = $PSCommandPath }

                    try {
                        # Re-launch a NEW elevated PowerShell that just runs the server-setup helper function.
                        $helperCode = @"
Import-Module '$selfScript' -Force -ErrorAction SilentlyContinue
`$ErrorActionPreference = 'Continue'
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
if (Get-Service sshd -ErrorAction SilentlyContinue) {
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd
    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }
}
Start-Sleep -Seconds 2
"@
                        $helperPath = Join-Path $env:TEMP "gw_elevate_sshd_$(Get-Random).ps1"
                        Set-Content -Path $helperPath -Value $helperCode -Encoding UTF8

                        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$helperPath`""
                        Start-Process powershell -Verb RunAs -ArgumentList $argList -Wait

                        Remove-Item $helperPath -Force -ErrorAction SilentlyContinue
                        Write-Host "[+] Elevated server setup finished (check status below)." -ForegroundColor Green
                        Write-WizardActionLog "Elevated sshd install/enable via UAC prompt"
                    } catch {
                        Write-Host "[!] UAC prompt was cancelled or failed. Server-side steps will be skipped." -ForegroundColor Red
                    }
                }

                # ---------- CLIENT (runs in current, non-elevated session — doesn't need admin) ----------
                $sshInstalled = (Get-Command ssh -ErrorAction SilentlyContinue) -and (Get-Command ssh-keygen -ErrorAction SilentlyContinue)
                if (-not $sshInstalled) {
                    Write-Host "`n[i] Installing OpenSSH Client..." -ForegroundColor Cyan
                    try { Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 | Out-Null; Write-Host "[+] OpenSSH Client installed." -ForegroundColor Green }
                    catch { Write-Host "[!] Client install needs admin too — re-run this option and accept the prompt." -ForegroundColor Yellow }
                } else {
                    Write-Host "[+] OpenSSH Client already installed." -ForegroundColor Green
                }

                # ---------- STATUS CHECK (always runs, shows the real current state) ----------
                Write-Host "`n--- Current sshd status ---" -ForegroundColor Cyan
                $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
                if ($sshdSvc) {
                    Write-Host "  Status: $($sshdSvc.Status)   StartType: $($sshdSvc.StartType)" -ForegroundColor $(if ($sshdSvc.Status -eq 'Running') {'Green'} else {'Red'})
                } else {
                    Write-Host "  sshd service not found — capability may not be installed yet." -ForegroundColor Red
                }

                Write-Host "`n========================================================" -ForegroundColor Green
                Write-Host "  SSH CLIENT + SERVER SETUP COMPLETE" -ForegroundColor Green
                Write-Host "========================================================" -ForegroundColor Green
                Pause-Console
            }
            "2" {
                $sshPath = "$env:USERPROFILE\.ssh\id_ed25519"
                if (Test-Path $sshPath) { Write-Host "`n[!] SSH key already exists at $sshPath" -ForegroundColor Yellow }
                else {
                    $email = git config --global user.email 2>$null
                    if (-not $email) { $email = "user@github.com" }
                    ssh-keygen -t ed25519 -C "$email" -f "$sshPath" -N '""'
                    Write-WizardActionLog "New SSH keypair generated"
                    Write-Host "[+] New SSH key generated!" -ForegroundColor Green
                }
                $pubPath = "$sshPath.pub"
                if (Test-Path $pubPath) {
                    Write-Host "`n---- PUBLIC KEY ----" -ForegroundColor White
                    Get-Content $pubPath
                    Write-Host "---- END KEY ----" -ForegroundColor White
                }
                Pause-Console
            }
            "3" { Manage-SshGithubMenu }
            "0" { return }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ==============================================================================
# GITHUB CLI (gh) AUTHENTICATION MANAGER
# ==============================================================================
function Manage-GhAuth {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "`n[!] 'gh' CLI is not installed. Install it first: winget install GitHub.cli" -ForegroundColor Red
        Pause-Console
        return
    }
    while ($true) {
        Show-Header
        Write-Host "  GITHUB CLI (gh) AUTHENTICATION MANAGER`n" -ForegroundColor Yellow

        # Live status snapshot shown every time the menu draws
        $statusOutput = gh auth status 2>&1 | Out-String
        if ($statusOutput -match "Logged in to|Active account: true") {
            Write-Host "  Current Status: LOGGED IN" -ForegroundColor Green
        } elseif ($statusOutput -match "token.*invalid|Failed to log in") {
            Write-Host "  Current Status: TOKEN INVALID (needs re-login)" -ForegroundColor Red
        } else {
            Write-Host "  Current Status: NOT LOGGED IN" -ForegroundColor Red
        }
        Write-Host ""

        Write-Host "  [1] Login (gh auth login)" -ForegroundColor Green
        Write-Host "  [2] Logout (gh auth logout)" -ForegroundColor Red
        Write-Host "  [3] Show Full Auth Status (gh auth status)" -ForegroundColor Cyan
        Write-Host "  [4] Check GitHub API Reachability (gh api user)" -ForegroundColor Cyan
        Write-Host "  [0] Back to Module 1`n"
        Write-Host "====================================================================" -ForegroundColor Cyan
        $ghAuthChoice = Read-Host "Select choice [0-4]"

        switch ($ghAuthChoice) {
            "1" {
                Write-Host "`n[i] This will walk you through GitHub's interactive login." -ForegroundColor Cyan
                Write-Host "    Follow the prompts (browser or token-based)." -ForegroundColor Cyan
                Write-Host "--------------------------------------------------------------`n"
                gh auth login
                Write-Host "`n--------------------------------------------------------------" -ForegroundColor Cyan
                $postStatus = gh auth status 2>&1 | Out-String
                if ($postStatus -match "Logged in to") {
                    Write-Host "[+] Login successful!" -ForegroundColor Green
                    Write-WizardActionLog "gh auth login: success"
                } else {
                    Write-Host "[!] Login may not have completed successfully. Check output above." -ForegroundColor Yellow
                    Write-WizardActionLog "gh auth login: attempted, status unclear"
                }
                Pause-Console
            }
            "2" {
                $ghUserForLogout = $null
                try { $ghUserForLogout = gh api user --jq '.login' 2>$null } catch {}
                $confirmMsg = if ($ghUserForLogout) { "Log out of GitHub account '$ghUserForLogout'" } else { "Log out of GitHub CLI" }
                if (Confirm-DestructiveAction $confirmMsg) {
                    gh auth logout
                    Write-Host "[+] Logged out." -ForegroundColor Green
                    Write-WizardActionLog "gh auth logout: $ghUserForLogout"
                } else {
                    Write-Host "`n[i] Cancelled." -ForegroundColor Yellow
                }
                Pause-Console
            }
            "3" {
                Write-Host "`n--------------------- gh auth status ---------------------" -ForegroundColor Cyan
                gh auth status
                Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
                Pause-Console
            }
            "4" {
                Write-Host "`n--------------------- gh api user ---------------------" -ForegroundColor Cyan
                $apiOutput = gh api user 2>&1 | Out-String
                Write-Host $apiOutput
                if ($apiOutput -match '"login"') {
                    Write-Host "[+] API reachable and token valid." -ForegroundColor Green
                } elseif ($apiOutput -match "HTTP 503|No server is currently available") {
                    Write-Host "[!] GitHub's API is temporarily unavailable (503). This is on GitHub's side — try again shortly." -ForegroundColor Yellow
                } elseif ($apiOutput -match "HTTP 401|Bad credentials") {
                    Write-Host "[!] Token invalid/expired. Use option [1] to log in again." -ForegroundColor Red
                } else {
                    Write-Host "[!] Unexpected response. See output above." -ForegroundColor Yellow
                }
                Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
                Pause-Console
            }
            "0" { return }
            default { Write-Host "Invalid choice!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ==============================================================================
# MODULE 1: Identity & Remote URL Manager (Main Router)
# ==============================================================================
function Manage-Identity {
    while ($true) {
        Show-Header
        Write-Host "  [+] Module 1: Identity & Remote URL Manager`n" -ForegroundColor Yellow
        Write-Host "  [1] GitHub CLI (gh) Login / Logout / Status" -ForegroundColor Green
        Write-Host "  [2] Check / Set Global Git User and Email" -ForegroundColor Green
        Write-Host "  [3] SSH Manager (Keys, Services & GitHub Integration)" -ForegroundColor Green
        Write-Host "  [4] Personal Access Token (PAT) Vault Manager" -ForegroundColor Green
        Write-Host "  [5] Inspect and Manage Remote Repository URLs" -ForegroundColor Green
        Write-Host "  [0] Back to Main Menu" -ForegroundColor Green
        Write-Host "`n====================================================================" -ForegroundColor Cyan
        $choice = Read-Host "Select choice [0-5]"
        switch ($choice) {
            "1" { Manage-GhAuth }
            "2" {
                $curName = git config --global user.name 2>$null
                if (-not $curName) { $curName = "Not set" }
                $curEmail = git config --global user.email 2>$null
                if (-not $curEmail) { $curEmail = "Not set" }
                Write-Host "`nCurrent Configuration:" -ForegroundColor Cyan
                Write-Host "  Name:  $curName"
                Write-Host "  Email: $curEmail`n"
                $newName = Read-Host "Enter new global user.name (press ENTER to skip)"
                $newEmail = Read-Host "Enter new global user.email (press ENTER to skip)"
                if ($newName) { git config --global user.name "$newName"; Write-Host "[+] user.name updated." -ForegroundColor Green }
                if ($newEmail) { git config --global user.email "$newEmail"; Write-Host "[+] user.email updated." -ForegroundColor Green }
                Pause-Console
            }
            "3" { Manage-SshMenu }
            "4" { Manage-PatVault }
            "5" {
                while ($true) {
                    Show-Header
                    Write-Host "  REMOTE REPOSITORY URL MANAGER`n" -ForegroundColor Yellow
                    Write-Host "--- Current Configured Remotes (git remote -v) ---" -ForegroundColor Cyan
                    $remotes = git remote -v 2>$null
                    if ($remotes) { Write-Host $remotes } else { Write-Host "No remotes set." }
                    Write-Host "-----------------------------------------------------`n" -ForegroundColor Cyan
                    Write-Host "  [1] Change / Set New Remote URL" -ForegroundColor Green
                    Write-Host "  [2] Toggle Protocol (HTTPS / SSH)" -ForegroundColor Green
                    Write-Host "  [0] Back to Module 1" -ForegroundColor Green
                    $remoteChoice = Read-Host "Select choice [0-2]"
                    if ($remoteChoice -eq "1") {
                        $rawUrl = Read-Host "Enter fresh GitHub Remote URL"
                        $newUrl = Clean-RemoteUrl -url $rawUrl
                        if ($newUrl) {
                            git remote remove origin 2>$null
                            git remote add origin "$newUrl"
                            Write-Host "[+] Remote 'origin' updated." -ForegroundColor Green
                        } else { Write-Host "[!] URL cannot be empty!" -ForegroundColor Red }
                        Pause-Console
                    } elseif ($remoteChoice -eq "2") {
                        $curUrl = Clean-RemoteUrl -url (git remote get-url origin 2>$null)
                        if (-not $curUrl) { Write-Host "`n[!] No 'origin' remote set yet." -ForegroundColor Red; Pause-Console; continue }
                        if ($curUrl -like "https://github.com/*") {
                            $parts = $curUrl -replace 'https://github.com/', '' -replace '\.git$', ''
                            git remote set-url origin "git@github.com:$parts.git"
                            Write-Host "[+] Switched to SSH." -ForegroundColor Green
                        } elseif ($curUrl -like "git@github.com:*") {
                            $parts = $curUrl -replace 'git@github.com:', '' -replace '\.git$', ''
                            git remote set-url origin "https://github.com/$parts.git"
                            Write-Host "[+] Switched to HTTPS." -ForegroundColor Green
                        } else { Write-Host "[!] Unrecognized URL format." -ForegroundColor Red }
                        Pause-Console
                    } elseif ($remoteChoice -eq "0") { break }
                }
            }
            "0" { return }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}
