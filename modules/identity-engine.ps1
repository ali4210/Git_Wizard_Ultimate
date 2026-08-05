# ==============================================================================
# MODULE:       identity-engine.ps1
# DESCRIPTION:  Handles Git Global Identity, SSH Keys, and Remote Protocols.
# ==============================================================================

function Manage-GitIdentity {
    while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [+] Module 1: Identity & SSH Connection Manager (Windows)         " -ForegroundColor Yellow
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [1] Check / Set Global Git User & Email"
        Write-Host "  [2] Generate New SSH Key (ED25519) & Display Public Key"
        Write-Host "  [3] Test SSH Connection to GitHub"
        Write-Host "  [4] Convert Remote URL between HTTPS and SSH"
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
            Pause-Console
        }
        elseif ($choice -eq "4") {
            $currentUrl = git remote get-url origin 2>$null
            if (-not $currentUrl) {
                Write-Host "`n[!] No 'origin' remote URL configured in this repository." -ForegroundColor Red
                Pause-Console
                continue
            }
            Write-Host "`nCurrent Remote URL: $currentUrl" -ForegroundColor Cyan
            if ($currentUrl -match "https://github\.com/([^/]+)/([^/]+)\.git") {
                $userRepo = "$($Matches[1])/$($Matches[2])"
                $newUrl = "git@github.com:${userRepo}.git"
                git remote set-url origin $newUrl
                Write-Host "[✔] Switched remote to SSH: $newUrl" -ForegroundColor Green
            }
            elseif ($currentUrl -match "git@github\.com:([^/]+)/([^/]+)\.git") {
                $userRepo = "$($Matches[1])/$($Matches[2])"
                $newUrl = "https://github.com/${userRepo}.git"
                git remote set-url origin $newUrl
                Write-Host "[✔] Switched remote to HTTPS: $newUrl" -ForegroundColor Green
            }
            else {
                Write-Host "[!] Unrecognized remote URL format." -ForegroundColor Red
            }
            Pause-Console
        }
        elseif ($choice -eq "5") { break }
    }
}