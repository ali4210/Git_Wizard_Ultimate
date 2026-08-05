# ==============================================================================
# MODULE:       repo-engine.ps1
# DESCRIPTION:  Handles Repo Setup, Status Inspection, Reset, and Smart Push.
# ==============================================================================


function Show-UpToDateCelebration {
    Write-Host @"
          ,~-.
         (   ' )-.          ,~'`-.
      ,~' `   ' ) )        _(    _) )
     ( ( .--.===.--.    (   `    ' )
      `.%%.;::|888.#`.   `-'`~~=~'
      /%%/::::|8888\##\
     |%%/:::::|88888\##|
     |%%|:::::|88888|##|.,-.
     \%%|:::::|88888|##/    )_
      \%\:::::|88888/#/ ( `'   )
       \%\::::|8888/#/(  ,  -'`-.
   ,~-. `%\:::|888/#'(  (      ') )
  (   ) )_ `\__|__/'    `~-~=--~~='
 ( ` ')  ) [VVVVV]
(_(_.~~~'   \|_|/   hjw
            [XXX]
            `"""'
"@ -ForegroundColor Green
    Write-Host "Everything up-to-date! Code is safe and synced on GitHub!" -ForegroundColor Green
}

function Manage-GitRepo {
    # Ensure GIT_PAGER=cat is enforced for clean output
    $env:GIT_PAGER = "cat"

    while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [+] Module 2: Repository Setup, Status & Reset Engine (Windows)  " -ForegroundColor Yellow
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host "  [1] 1-Click Complete Repo Setup (Init, Main Branch, Commit, Remote, Push)"
        Write-Host "  [2] Quick Push (Add All -> Commit -> Push)"
        Write-Host "  [3] Inspect Working Directory Status (git status)"
        Write-Host "  [4] Interactive Git Reset & Undo Utility (Unstage, Revert, Rollback)"
        Write-Host "  [5] Smart Conflict Push Resolver (Fixes Refused Pushes!)"
        Write-Host "  [6] Generate Tailored .gitignore File"
        Write-Host "  [7] Back to Main Menu"
        Write-Host "====================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Select choice [1-7]"

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
            Clear-Host
            Write-Host "====================================================================" -ForegroundColor Cyan
            Write-Host "  📌 WORKING DIRECTORY & STAGING STATUS                             " -ForegroundColor Yellow
            Write-Host "====================================================================" -ForegroundColor Cyan
            $insideRepo = git rev-parse --is-inside-work-tree 2>$null
            if ($insideRepo -ne "true") {
                Write-Host "[!] Not inside a Git repository!" -ForegroundColor Red
            } else {
                $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
                Write-Host "Current Active Branch: $branch`n" -ForegroundColor Green
                git status
            }
            Pause-Console
        }
        elseif ($choice -eq "4") {
            while ($true) {
                Clear-Host
                Write-Host "====================================================================" -ForegroundColor Cyan
                Write-Host "  📌 INTERACTIVE GIT RESET & UNDO UTILITY                           " -ForegroundColor Yellow
                Write-Host "====================================================================" -ForegroundColor Cyan
                Write-Host "  [1] Unstage All Files (Keep modified changes, remove from staging)"
                Write-Host "  [2] Discard All Uncommitted Local Changes (Revert files to last commit)"
                Write-Host "  [3] Soft Rollback Last Commit (Undo commit, KEEP changes staged)"
                Write-Host "  [4] Hard Rollback Last Commit (DESTROY last commit & all changes!)"
                Write-Host "  [5] Back to Module 2 Menu"
                Write-Host "====================================================================" -ForegroundColor Cyan

                $resetChoice = Read-Host "Select choice [1-5]"

                if ($resetChoice -eq "1") {
                    Write-Host "`n--> Unstaging all files..." -ForegroundColor Green
                    git reset HEAD
                    Write-Host "[✔] All staged files reverted to unstaged!" -ForegroundColor Green
                    Pause-Console
                }
                elseif ($resetChoice -eq "2") {
                    $conf = Read-Host "`n[!] ARE YOU SURE? This will DISCARD all uncommitted work! (y/N)"
                    if ($conf -eq "y" -or $conf -eq "Y") {
                        git checkout -- . 2>$null
                        git clean -fd 2>$null
                        Write-Host "[✔] Local working tree wiped clean to last commit state!" -ForegroundColor Green
                    }
                    Pause-Console
                }
                elseif ($resetChoice -eq "3") {
                    Write-Host "`n--> Soft rolling back last commit..." -ForegroundColor Green
                    git reset --soft HEAD~1
                    Write-Host "[✔] Commit undone! Your files remain intact in the staging area." -ForegroundColor Green
                    Pause-Console
                }
                elseif ($resetChoice -eq "4") {
                    $conf = Read-Host "`n[!] CRITICAL WARNING: This will PERMANENTLY ERASE your last commit and work! (y/N)"
                    if ($conf -eq "y" -or $conf -eq "Y") {
                        git reset --hard HEAD~1
                        Write-Host "[✔] Hard reset complete. Last commit and work removed." -ForegroundColor Green
                    }
                    Pause-Console
                }
                elseif ($resetChoice -eq "5") { break }
            }
        }
        elseif ($choice -eq "5") {
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
        elseif ($choice -eq "6") {
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
        elseif ($choice -eq "7") { break }
    }
}