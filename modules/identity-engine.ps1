# ==============================================================================
# ENGINE NAME: identity-engine.ps1 (PowerShell 5.1 Clean Edition)
# ==============================================================================

function Clean-RemoteUrl ($url) {
    if (-not $url) { return "" }
    $clean = $url -replace '(?i)^git remote (add|set-url) origin ', ''
    return $clean.Trim()
}

function Manage-Identity {
    while ($true) {
        Show-Header
        Write-Host "  [+] Module 1: Identity, SSH and Remote URL Manager`n" -ForegroundColor Yellow
        Write-Host "  [1] Check / Set Global Git User and Email" -ForegroundColor Green
        Write-Host "  [2] Generate New SSH Key (ED25519) and Show Public Key" -ForegroundColor Green
        Write-Host "  [3] Test SSH Connection to GitHub" -ForegroundColor Green
        Write-Host "  [4] Inspect and Manage Remote Repository URLs" -ForegroundColor Green
        Write-Host "  [5] Back to Main Menu" -ForegroundColor Green
        Write-Host "`n====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [1-5]"

        switch ($choice) {
            "1" {
                $curName = git config --global user.name 2>$null
                $curEmail = git config --global user.email 2>$null
                if (-not $curName) { $curName = "Not set" }
                if (-not $curEmail) { $curEmail = "Not set" }

                Write-Host "`nCurrent Configuration:" -ForegroundColor Cyan
                Write-Host "  Name:  $curName"
                Write-Host "  Email: $curEmail`n"

                $newName = Read-Host "Enter new global user.name (press ENTER to skip)"
                $newEmail = Read-Host "Enter new global user.email (press ENTER to skip)"

                if ($newName) {
                    git config --global user.name "$newName"
                    Write-Host "[+] user.name updated to: $newName" -ForegroundColor Green
                }
                if ($newEmail) {
                    git config --global user.email "$newEmail"
                    Write-Host "[+] user.email updated to: $newEmail" -ForegroundColor Green
                }
                Pause-Console
            }
            "2" {
                $sshPath = "$env:USERPROFILE\.ssh\id_ed25519"
                if (Test-Path $sshPath) {
                    Write-Host "`n[!] An ED25519 SSH key already exists at $sshPath" -ForegroundColor Yellow
                } else {
                    Write-Host "`n--> Generating ED25519 SSH Key..." -ForegroundColor Green
                    $email = git config --global user.email 2>$null
                    if (-not $email) { $email = "user@github.com" }
                    ssh-keygen -t ed25519 -C "$email" -f "$sshPath" -N '""'
                    Write-Host "[+] SSH Key created!" -ForegroundColor Green
                }
                $pubPath = "$sshPath.pub"
                if (Test-Path $pubPath) {
                    Write-Host "`nYour Public Key (Add this to GitHub -> Settings -> SSH Keys):" -ForegroundColor Cyan
                    Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
                    Get-Content $pubPath
                    Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
                }
                Pause-Console
            }
            "3" {
                Write-Host "`n--> Testing SSH connection to GitHub..." -ForegroundColor Green
                ssh -T git@github.com 2>&1 | Out-String | Write-Host
                Write-Host "[i] Note: 'does not provide shell access' indicates successful authentication!" -ForegroundColor Green
                Pause-Console
            }
            "4" {
                while ($true) {
                    Show-Header
                    Write-Host "REMOTE REPOSITORY URL MANAGER`n" -ForegroundColor Yellow
                    Write-Host "--- Current Configured Remotes (git remote -v) ---" -ForegroundColor Cyan
                    $remotes = git remote -v 2>$null
                    if ($remotes) { Write-Host $remotes } else { Write-Host "No remotes set." }
                    Write-Host "-----------------------------------------------------`n" -ForegroundColor Cyan
                    Write-Host "  [1] Change / Set New Remote URL (Overwrite Existing)" -ForegroundColor Green
                    Write-Host "  [2] Toggle Protocol (Switch between HTTPS and SSH)" -ForegroundColor Green
                    Write-Host "  [3] Back to Module 1 Menu" -ForegroundColor Green

                    $remoteChoice = Read-Host "Select choice [1-3]"
                    if ($remoteChoice -eq "1") {
                        $rawUrl = Read-Host "Enter fresh GitHub Remote URL (HTTPS or SSH)"
                        $newUrl = Clean-RemoteUrl -url $rawUrl
                        if ($newUrl) {
                            git remote remove origin 2>$null
                            git remote add origin "$newUrl"
                            Write-Host "[+] Remote 'origin' updated to: $newUrl" -ForegroundColor Green
                        } else {
                            Write-Host "[!] URL cannot be empty!" -ForegroundColor Red
                        }
                        Pause-Console
                    } elseif ($remoteChoice -eq "2") {
                        $curUrl = git remote get-url origin 2>$null
                        $curUrl = Clean-RemoteUrl -url $curUrl
                        if (-not $curUrl) {
                            Write-Host "`n[!] No 'origin' remote set yet. Use Option [1] first." -ForegroundColor Red
                            Pause-Console
                            continue
                        }
                        if ($curUrl -like "https://github.com/*") {
                            $parts = $curUrl -replace 'https://github.com/', '' -replace '\.git$', ''
                            $converted = "git@github.com:$parts.git"
                            git remote set-url origin "$converted"
                            Write-Host "[+] Switched from HTTPS to SSH: $converted" -ForegroundColor Green
                        } elseif ($curUrl -like "git@github.com:*") {
                            $parts = $curUrl -replace 'git@github.com:', '' -replace '\.git$', ''
                            $converted = "https://github.com/$parts.git"
                            git remote set-url origin "$converted"
                            Write-Host "[+] Switched from SSH to HTTPS: $converted" -ForegroundColor Green
                        } else {
                            Write-Host "[!] Unrecognized URL format." -ForegroundColor Red
                        }
                        Pause-Console
                    } elseif ($remoteChoice -eq "3") {
                        break
                    }
                }
            }
            "5" { break }
            default { Write-Host "Invalid selection!" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}