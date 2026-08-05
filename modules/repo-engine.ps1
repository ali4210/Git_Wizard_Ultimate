# ==============================================================================
# MODULE:       repo-engine.ps1
# DESCRIPTION:  Handles 1-Click Repo Setup, Smart Push, and .gitignore.
# ==============================================================================

function Manage-GitRepo {
    while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [+] Module 2: Repository Setup & Smart Push Engine (Windows)     " -ForegroundColor Yellow
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [1] 1-Click Complete Repo Setup (Init, Main Branch, Commit, Remote, Push)"
        Write-Host "  [2] Quick Push (Add All -> Commit -> Push)"
        Write-Host "  [3] Smart Conflict Push Resolver (Fixes Refused Pushes!)"
        Write-Host "  [4] Generate Tailored .gitignore File"
        Write-Host "  [5] Back to Main Menu"
        Write-Host "====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [1-5]"

        if ($choice -eq "1") {
            Write-Host "`n--> Initializing Git repository..." -ForegroundColor Green
            git init
            git branch -M main
            git add .

            $status = git status --porcelain
            if (-not $status) {
                Write-Host "[i] Working tree clean (nothing new to commit)." -ForegroundColor Yellow
            } else {
                $msg = Read-Host "Enter initial commit message [default: Initial commit]"
                if (-not $msg) { $msg = "Initial commit" }
                git commit -m "$msg"
            }

            $existingRemote = git remote get-url origin 2>$null
            Write-Host "`n====================================================================" -ForegroundColor Cyan
            Write-Host "  📌 GITHUB REMOTE URL SETUP GUIDELINE                              " -ForegroundColor Yellow
            Write-Host "====================================================================" -ForegroundColor Cyan

            if ($existingRemote) {
                Write-Host "[✔] Existing Remote Detected: $existingRemote" -ForegroundColor Green
                Write-Host "--> Press [ENTER] to keep this remote and push immediately!" -ForegroundColor Yellow
                Write-Host "--> Or paste a NEW URL below to overwrite it.`n"
            } else {
                Write-Host "Enter your GitHub repository URL."
                Write-Host "Example formats:"
                Write-Host "  • SSH (Recommended):   git@github.com:username/repository.git" -ForegroundColor Green
                Write-Host "  • HTTPS:              https://github.com/username/repository.git`n" -ForegroundColor Green
            }

            $rawUrl = Read-Host "Enter Remote URL (or press ENTER to keep current)"
            $remoteUrl = Clean-RemoteUrl $rawUrl

            if ($remoteUrl) {
                git remote remove origin 2>$null
                git remote add origin "$remoteUrl"
                Write-Host "[✔] Remote attached: $remoteUrl" -ForegroundColor Green
            } elseif ($existingRemote) {
                $remoteUrl = $existingRemote
                Write-Host "[✔] Using existing remote: $remoteUrl" -ForegroundColor Green
            }

            if ($remoteUrl) {
                Write-Host "--> Pushing to origin main..." -ForegroundColor Green
                git push -u origin main
            } else {
                Write-Host "[!] No remote URL configured." -ForegroundColor Yellow
            }
            Pause-Console
        }
        elseif ($choice -eq "2") {
            git add .
            $status = git status --porcelain
            if (-not $status) {
                Write-Host "[i] Working tree clean (no new changes to commit). Pushing existing commits..." -ForegroundColor Yellow
            } else {
                $msg = Read-Host "Enter commit message"
                if (-not $msg) {
                    Write-Host "[!] Commit message cannot be empty!" -ForegroundColor Red
                    Pause-Console
                    continue
                }
                git commit -m "$msg"
            }
            $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
            if (-not $branch) { $branch = "main" }
            git push origin $branch
            Pause-Console
        }
        elseif ($choice -eq "3") {
            $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
            if (-not $branch) { $branch = "main" }

            Write-Host "`n====================================================================" -ForegroundColor Cyan
            Write-Host "  📌 SMART CONFLICT PUSH RESOLVER (Branch: $branch)                " -ForegroundColor Yellow
            Write-Host "====================================================================" -ForegroundColor Cyan
            Write-Host "  [1] Safe Pull & Rebase (Recommended: Clean history append)"
            Write-Host "  [2] Safe Pull & Merge (Allows unrelated histories merge)"
            Write-Host "  [3] Force Push (Overwrites remote with your local code)"
            Write-Host "  [4] Cancel"
            
            $strat = Read-Host "Select strategy [1-4]"
            if ($strat -eq "1") {
                Write-Host "`n--> Pulling remote changes with Rebase..." -ForegroundColor Green
                git pull origin $branch --rebase
                git push origin $branch
                Write-Host "[✔] Successfully synced and pushed!" -ForegroundColor Green
            }
            elseif ($strat -eq "2") {
                Write-Host "`n--> Pulling remote changes with Merge..." -ForegroundColor Green
                git pull origin $branch --rebase=false --allow-unrelated-histories
                git push origin $branch
                Write-Host "[✔] Successfully merged and pushed!" -ForegroundColor Green
            }
            elseif ($strat -eq "3") {
                Write-Host "`n--> Force pushing to remote..." -ForegroundColor Red
                git push origin $branch --force
                Write-Host "[✔] Force push complete!" -ForegroundColor Green
            }
            Pause-Console
        }
        elseif ($choice -eq "4") {
            Write-Host "`nSelect template type for .gitignore:" -ForegroundColor Yellow
            Write-Host "  [1] Node.js / React / Next.js"
            Write-Host "  [2] Python / Django / Flask"
            Write-Host "  [3] C# / .NET / Visual Studio"
            $giChoice = Read-Host "Choice [1-3]"

            if ($giChoice -eq "1") {
                @"
node_modules/
build/
dist/
.env
.env.local
npm-debug.log*
"@ | Out-File -FilePath .gitignore -Encoding utf8
                Write-Host "[✔] Node.js .gitignore created!" -ForegroundColor Green
            }
            elseif ($giChoice -eq "2") {
                @"
__pycache__/
*.py[cod]
*$py.class
venv/
.env
.pytest_cache/
"@ | Out-File -FilePath .gitignore -Encoding utf8
                Write-Host "[✔] Python .gitignore created!" -ForegroundColor Green
            }
            elseif ($giChoice -eq "3") {
                @"
.vs/
bin/
obj/
*.user
*.suo
"@ | Out-File -FilePath .gitignore -Encoding utf8
                Write-Host "[✔] .NET .gitignore created!" -ForegroundColor Green
            }
            Pause-Console
        }
        elseif ($choice -eq "5") { break }
    }
}