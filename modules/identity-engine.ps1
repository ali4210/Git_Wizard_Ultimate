# ==============================================================================
# MODULE:       identity-engine.ps1
# DESCRIPTION:  Handles Git Global Identity, SSH Keys, and Remote URLs.
# ==============================================================================

function Clean-RemoteUrl ($url) {
    if (-not $url) { return "" }
    # Strip leading 'git remote add origin' or 'git remote set-url origin' if pasted
    $cleaned = $url -replace "^(?i)git\s+remote\s+(add|set-url)\s+origin\s+", ""
    return $cleaned.Trim()
}

function Manage-GitIdentity {
    while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [+] Module 1: Identity, SSH & Remote URL Manager (Windows)        " -ForegroundColor Yellow
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [1] Check / Set Global Git User & Email"
        Write-Host "  [2] Generate New SSH Key (ED25519) & Display Public Key"
        Write-Host "  [3] Test SSH Connection to GitHub"
        Write-Host "  [4] Inspect & Manage Remote Repository URLs (View, Change, Switch)"
        Write-Host "  [5] Back to Main Menu"
        Write-Host "====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [1-5]"

        if ($choice -eq "1") {
            $name = git config --global user.name
            $email = git config --global user.email
            Write-Host ""
            Write-Host "Current Configuration:" -ForegroundColor Cyan
            Write-Host "  Name:  $($name ?? 'Not set')"
            Write-Host "  Email: $($email ?? 'Not set')"
            Write-Host ""
            $newName = Read-Host "Enter new global user.name (press ENTER to skip)"
            $newEmail = Read-Host "Enter new global user.email (press ENTER to skip)"

            if ($newName) { git config --global user.name "$newName"; Write-Host "[✔] user.name updated!" -ForegroundColor Green }
            if ($newEmail) { git config --global user.email "$newEmail"; Write-Host "[✔] user.email updated!" -ForegroundColor Green }
            Pause-Console
        }
        elseif ($choice -eq "2") {
            $sshPath = Join-Path -Path $env:USERPROFILE -ChildPath ".ssh\id_ed25519"
            if (Test-Path -Path $sshPath) {
                Write-Host "`n[!] An ED25519 SSH key already exists at $sshPath" -ForegroundColor Yellow
            } else {
                Write-Host "`n--> Generating ED25519 SSH Key..." -ForegroundColor Green
                $email = git config --global user.email
                if (-not $email) { $email = "user@github.com" }
                ssh-keygen -t ed25519 -C "$email" -f "$sshPath" -N '""'
                Write-Host "[✔] SSH Key created!" -ForegroundColor Green
            }
            $pubKeyPath = "$sshPath.pub"
            if (Test-Path -Path $pubKeyPath) {
                Write-Host "`nYour Public Key (Add this to GitHub -> Settings -> SSH Keys):" -ForegroundColor Cyan
                Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
                Get-Content -Path $pubKeyPath
                Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
            }
            Pause-Console
        }
        elseif ($choice -eq "3") {
            Write-Host "`n--> Testing SSH connection to GitHub..." -ForegroundColor Green
            ssh -T git@github.com
            Write-Host "`n[i] Note: 'does not provide shell access' is standard and indicates successful authentication!" -ForegroundColor Green
            Pause-Console
        }
        elseif ($choice -eq "4") {
            $insideRepo = git rev-parse --is-inside-work-tree 2>$null
            if ($insideRepo -ne "true") {
                Write-Host "`n[!] Not inside a Git repository! Run Option 1 in Module 2 first." -ForegroundColor Red
                Pause-Console
                continue
            }

            while ($true) {
                Clear-Host
                Write-Host "====================================================================" -ForegroundColor Cyan
                Write-Host "  📌 REMOTE REPOSITORY URL MANAGER (Windows)                        " -ForegroundColor Yellow
                Write-Host "====================================================================" -ForegroundColor Cyan
                Write-Host "--- Current Configured Remotes (git remote -v) ---" -ForegroundColor Cyan
                git remote -v
                Write-Host "-----------------------------------------------------`n" -ForegroundColor Cyan
                Write-Host "  [1] Change / Set New Remote URL (Overwrite Existing)"
                Write-Host "  [2] Toggle Protocol (Switch between HTTPS and SSH)"
                Write-Host "  [3] Back to Module 1 Menu"
                Write-Host "====================================================================" -ForegroundColor Cyan

                $remoteChoice = Read-Host "Select choice [1-3]"

                if ($remoteChoice -eq "1") {
                    $rawUrl = Read-Host "`nEnter fresh GitHub Remote URL (HTTPS or SSH)"
                    $newUrl = Clean-RemoteUrl $rawUrl
                    if ($newUrl) {
                        git remote remove origin 2>$null
                        git remote add origin "$newUrl"
                        Write-Host "[✔] Remote 'origin' updated to: $newUrl" -ForegroundColor Green
                    } else {
                        Write-Host "[!] URL cannot be empty!" -ForegroundColor Red
                    }
                    Pause-Console
                }
                elseif ($remoteChoice -eq "2") {
                    $currentUrl = git remote get-url origin 2>$null
                    $currentUrl = Clean-RemoteUrl $currentUrl

                    if (-not $currentUrl) {
                        Write-Host "`n[!] No 'origin' remote set yet. Use Option [1] to set one first." -ForegroundColor Red
                        Pause-Console
                        continue
                    }

                    git remote set-url origin "$currentUrl" 2>$null

                    if ($currentUrl -match "https://github\.com/([^/]+)/([^/]+)(\.git)?") {
                        $userRepo = "$($Matches[1])/$($Matches[2] -replace '\.git$','')"
                        $convertedUrl = "git@github.com:${userRepo}.git"
                        git remote set-url origin $convertedUrl
                        Write-Host "[✔] Switched from HTTPS to SSH: $convertedUrl" -ForegroundColor Green
                    }
                    elseif ($currentUrl -match "git@github\.com:([^/]+)/([^/]+)(\.git)?") {
                        $userRepo = "$($Matches[1])/$($Matches[2] -replace '\.git$','')"
                        $convertedUrl = "https://github.com/${userRepo}.git"
                        git remote set-url origin $convertedUrl
                        Write-Host "[✔] Switched from SSH to HTTPS: $convertedUrl" -ForegroundColor Green
                    }
                    else {
                        Write-Host "[!] Unrecognized URL format. Use Option [1] to re-enter a fresh URL." -ForegroundColor Red
                    }
                    Pause-Console
                }
                elseif ($remoteChoice -eq "3") { break }
            }
        }
        elseif ($choice -eq "5") { break }
    }
}