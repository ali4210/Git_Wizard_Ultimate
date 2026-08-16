# ==============================================================================
# ENGINE NAME: vcs-engine.ps1 (Windows Edition) — NEW
# DESCRIPTION: Provider-agnostic GitHub/GitLab dispatch layer (mirrors the
#              Linux vcs_* functions), Git Hosting Power Tools (Issues, PRs/MRs,
#              Releases, Actions/Pipelines, Gists/Snippets, Codespaces, Repo
#              Admin, Raw API Explorer) and the Delta Diff Suite.
# NOTE:        Relies on globals from git-wizard.ps1: Invoke-GitWizard,
#              Confirm-DestructiveAction, New-SafetyBackup, Show-Header,
#              Pause-Console, Write-WizardActionLog, $Global:DryRun.
# ==============================================================================

$Global:VcsProvider = ""   # "github" | "gitlab"

function Get-VcsBinary {
    if ($Global:VcsProvider -eq "gitlab") { return "glab" }
    return "gh"
}

function Invoke-SafeRun {
    param([string]$Description, [scriptblock]$Action)
    try {
        $out = & $Action 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0 -and $null -ne $code) {
            Write-Host "[!] $Description - failed (exit code $code)" -ForegroundColor Red
            $out | Select-Object -First 10 | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
            Write-Host "This is shown as a warning - git-wizard is still running normally." -ForegroundColor Cyan
        } else {
            Write-Host "[+] $Description - done." -ForegroundColor Green
            if ($out) { $out | ForEach-Object { Write-Host $_ } }
        }
    } catch {
        Write-Host "[!] $Description - failed: $_" -ForegroundColor Red
    }
}

function Get-VcsProviderFromRemote {
    $url = git remote get-url origin 2>$null
    if ($url -match "github\.com") { return "github" }
    if ($url -match "gitlab") { return "gitlab" }
    return ""
}

function Confirm-VcsProvider {
    $detected = Get-VcsProviderFromRemote
    if ($detected) { $Global:VcsProvider = $detected; return $true }

    Show-Header
    Write-Host "COULD NOT AUTO-DETECT YOUR GIT HOST`n" -ForegroundColor Yellow
    Write-Host "Your 'origin' remote doesn't clearly point to github.com or gitlab.com.`n" -ForegroundColor Cyan
    Write-Host "  [1] GitHub" -ForegroundColor Green
    Write-Host "  [2] GitLab" -ForegroundColor Green
    Write-Host "  [0] Cancel" -ForegroundColor Green
    $choice = Read-Host "Select choice [0-2]"
    switch ($choice) {
        "1" { $Global:VcsProvider = "github"; return $true }
        "2" { $Global:VcsProvider = "gitlab"; return $true }
        default { $Global:VcsProvider = ""; return $false }
    }
}

function Test-VcsCliInstalled {
    $bin = Get-VcsBinary
    return [bool](Get-Command $bin -ErrorAction SilentlyContinue)
}

function Install-VcsCliPrompt {
    $bin = Get-VcsBinary
    $wingetId = if ($bin -eq "gh") { "GitHub.cli" } else { "GLab.glab" }
    Write-Host "[i] This needs '$bin' - it's what actually talks to the API." -ForegroundColor Yellow
    Write-Host "    Install with: winget install --id $wingetId" -ForegroundColor Green
    $doInstall = Read-Host "Install now via winget? (y/N)"
    if ($doInstall -match '^[Yy]$') {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id $wingetId -e
        } else {
            Write-Host "[!] winget not found on this system. Install '$bin' manually." -ForegroundColor Red
        }
    }
}

function Confirm-VcsReady {
    if (-not (Confirm-VcsProvider)) { return $false }
    $bin = Get-VcsBinary

    if (-not (Test-VcsCliInstalled)) {
        Install-VcsCliPrompt
        if (-not (Test-VcsCliInstalled)) { return $false }
    }

    $authOk = $false
    try {
        & $bin auth status 2>$null | Out-Null
        $authOk = ($LASTEXITCODE -eq 0)
    } catch { $authOk = $false }

    if (-not $authOk) {
        Write-Host "[i] Not logged in to $($Global:VcsProvider). " -ForegroundColor Yellow -NoNewline
        $doLogin = Read-Host "Run '$bin auth login' now? (y/N)"
        if ($doLogin -match '^[Yy]$') {
            & $bin auth login
        } else {
            return $false
        }
    }
    return $true
}

# --- Dispatchers (mirror Linux vcs_* functions) ---
function Vcs-ListIssues        { param($args1) if ($Global:VcsProvider -eq "gitlab") { glab issue list @args1 } else { gh issue list @args1 } }
function Vcs-CreateIssue       { param($args1) if ($Global:VcsProvider -eq "gitlab") { glab issue create @args1 } else { gh issue create @args1 } }
function Vcs-CloseIssue        { param($num)   if ($Global:VcsProvider -eq "gitlab") { glab issue close $num } else { gh issue close $num } }
function Vcs-ViewIssue         { param($num)   if ($Global:VcsProvider -eq "gitlab") { glab issue view $num } else { gh issue view $num } }
function Vcs-CommentIssue      { param($num,$body) if ($Global:VcsProvider -eq "gitlab") { glab issue note $num --message $body } else { gh issue comment $num --body $body } }
function Vcs-ListChangeRequests { param($args1) if ($Global:VcsProvider -eq "gitlab") { glab mr list @args1 } else { gh pr list @args1 } }
function Vcs-CheckoutChangeRequest { param($num) if ($Global:VcsProvider -eq "gitlab") { glab mr checkout $num } else { gh pr checkout $num } }
function Vcs-DiffChangeRequest { param($num)   if ($Global:VcsProvider -eq "gitlab") { glab mr diff $num } else { gh pr diff $num } }
function Vcs-MergeChangeRequest { param($num)  if ($Global:VcsProvider -eq "gitlab") { glab mr merge $num } else { gh pr merge $num } }
function Vcs-CreateChangeRequest { param($title,$body) if ($Global:VcsProvider -eq "gitlab") { glab mr create --title $title --description $body } else { gh pr create --title $title --body $body } }
function Vcs-ListReleases      { param($args1) if ($Global:VcsProvider -eq "gitlab") { glab release list @args1 } else { gh release list @args1 } }
function Vcs-CreateRelease     { param($tag,$title) if ($Global:VcsProvider -eq "gitlab") { glab release create $tag --name $title } else { gh release create $tag --title $title --generate-notes } }
function Vcs-DeleteRelease     { param($tag)   if ($Global:VcsProvider -eq "gitlab") { glab release delete $tag } else { gh release delete $tag } }
function Vcs-ListRuns          { param($args1) if ($Global:VcsProvider -eq "gitlab") { glab ci list @args1 } else { gh run list @args1 } }
function Vcs-WatchRun          { if ($Global:VcsProvider -eq "gitlab") { glab ci status } else { gh run watch } }
function Vcs-TriggerRun        { param($args1) if ($Global:VcsProvider -eq "gitlab") { glab ci run } else { gh workflow run @args1 } }
function Vcs-ViewRunLogs       { param($id)    if ($Global:VcsProvider -eq "gitlab") { glab ci trace $id } else { gh run view $id --log } }
function Vcs-ListSnippets      { param($args1) if ($Global:VcsProvider -eq "gitlab") { glab snippet list @args1 } else { gh gist list @args1 } }
function Vcs-CreateSnippet     { param($file)  if ($Global:VcsProvider -eq "gitlab") { glab snippet create $file } else { gh gist create $file } }
function Format-RepoTable {
    param([array]$Rows)   # each row: @{Name=;Visibility=;Stars=;Updated=;IsFork=}
    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Host "[i] No repositories returned." -ForegroundColor Yellow
        return
    }
    Write-Host "Total repositories found: $($Rows.Count)`n" -ForegroundColor Green
    "{0,-35} {1,-10} {2,-6} {3,-12}" -f "NAME","VISIBILITY","STARS","UPDATED" | Write-Host -ForegroundColor White
    Write-Host ("-" * 70)
    foreach ($r in $Rows) {
        $visColor = if ($r.Visibility -eq "private") { "Red" } else { "Green" }
        $forkTag  = if ($r.IsFork -eq "true") { " [fork]" } else { "" }
        $shortDate = ($r.Updated -split "T")[0]
        Write-Host -NoNewline ("{0,-35} " -f $r.Name) -ForegroundColor Cyan
        Write-Host -NoNewline ("{0,-10} " -f $r.Visibility) -ForegroundColor $visColor
        Write-Host -NoNewline ("*{0,-5} " -f $r.Stars) -ForegroundColor Yellow
        Write-Host ("{0}{1}" -f $shortDate, $forkTag)
    }
}

function Vcs-ListRepos {
    if ($Global:VcsProvider -eq "gitlab") {
        $json = glab api "projects?membership=true&per_page=100&order_by=last_activity_at" | ConvertFrom-Json
        $rows = $json | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.path_with_namespace
                Visibility = $_.visibility
                Stars      = $_.star_count
                Updated    = $_.last_activity_at
                IsFork     = if ($_.forked_from_project) { "true" } else { "false" }
            }
        }
    } else {
        # No --source flag - includes forks too, tagged instead of hidden
        $json = gh repo list --limit 200 --json name,visibility,updatedAt,isFork,stargazerCount | ConvertFrom-Json
        $rows = $json | ForEach-Object {
            [PSCustomObject]@{
                Name       = $_.name
                Visibility = $_.visibility.ToLower()
                Stars      = $_.stargazerCount
                Updated    = $_.updatedAt
                IsFork     = $_.isFork.ToString().ToLower()
            }
        }
    }
    Format-RepoTable -Rows $rows
}
function Vcs-CreateRepo        { param($name,$visibility) if ($Global:VcsProvider -eq "gitlab") { glab repo create $name "--$visibility" } else { gh repo create $name "--$visibility" } }
function Vcs-MyUsername        {
    if ($Global:VcsProvider -eq "gitlab") { return (glab api user --jq '.username' 2>$null) }
    return (gh api user --jq '.login' 2>$null)
}
function Vcs-GetRepoUrl {
    param($repo)
    if ($Global:VcsProvider -eq "gitlab") {
        $enc = [uri]::EscapeDataString($repo)
        return (glab api "projects/$enc" --jq '(.ssh_url_to_repo) + "|" + (.http_url_to_repo)' 2>$null)
    }
    return (gh api "repos/$repo" --jq '(.ssh_url) + "|" + (.clone_url)' 2>$null)
}
function Vcs-RenameRepo {
    param($newname)
    if ($Global:VcsProvider -eq "gitlab") {
        Write-Host "[i] glab has no direct rename subcommand - rename via GitLab web UI (Settings > General)." -ForegroundColor Yellow
    } else {
        gh repo rename $newname
    }
}
function Vcs-DeleteRepo        { param($name)  if ($Global:VcsProvider -eq "gitlab") { glab repo delete $name --yes } else { gh repo delete $name --yes } }
function Vcs-Api               { param($args1) if ($Global:VcsProvider -eq "gitlab") { glab api @args1 } else { gh api @args1 } }
function Vcs-AddCollaborator {
    param($repo, $username, $permission)
    if ($Global:VcsProvider -eq "github") {
        gh api "repos/$repo/collaborators/$username" -X PUT -f "permission=$permission"
    } else {
        $uid = glab api "users?username=$username" --jq '.[0].id' 2>$null
        if (-not $uid) { Write-Host "[!] Couldn't find a GitLab user named '$username'." -ForegroundColor Red; return }
        $enc = [uri]::EscapeDataString($repo)
        glab api "projects/$enc/members" -X POST -f "user_id=$uid" -f "access_level=$permission"
    }
}

# ==============================================================================
# ISSUES MENU
# ==============================================================================
function Show-VcsIssuesMenu {
    while ($true) {
        Show-Header
        Write-Host "ISSUES ($($Global:VcsProvider))`n" -ForegroundColor Yellow
        Write-Host "  [1] List Issues" -ForegroundColor Green
        Write-Host "  [2] View an Issue" -ForegroundColor Green
        Write-Host "  [3] Create Issue" -ForegroundColor Green
        Write-Host "  [4] Comment on Issue" -ForegroundColor Green
        Write-Host "  [5] Close Issue" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-5]"
        switch ($c) {
            "1" { Show-Header; Vcs-ListIssues @(); Pause-Console }
            "2" { $n = Read-Host "Issue number"; if ($n) { Show-Header; Vcs-ViewIssue $n }; Pause-Console }
            "3" {
                $t = Read-Host "Title"; $b = Read-Host "Body"
                if ($t) {
                    if ($Global:DryRun) {
                        Write-Host "[DRY-RUN] Would create issue: $t" -ForegroundColor Yellow
                    } else {
                        Vcs-CreateIssue @("--title", $t, "--body", $b)
                        Write-WizardActionLog "Created issue: $t"
                    }
                }
                Pause-Console
            }
            "4" {
                $n = Read-Host "Issue number"; $cm = Read-Host "Comment"
                if ($n -and $cm) {
                    if ($Global:DryRun) { Write-Host "[DRY-RUN] Would comment on issue #$n" -ForegroundColor Yellow }
                    else { Vcs-CommentIssue $n $cm; Write-WizardActionLog "Commented on issue #$n" }
                }
                Pause-Console
            }
            "5" {
                $n = Read-Host "Issue number to close"
                if ($n -and (Confirm-DestructiveAction "Close issue #$n")) {
                    Vcs-CloseIssue $n
                    Write-WizardActionLog "Closed issue #$n"
                }
                Pause-Console
            }
            "0" { return }
        }
    }
}

# ==============================================================================
# PR/MR MENU
# ==============================================================================
function Show-VcsChangeRequestsMenu {
    $label = if ($Global:VcsProvider -eq "gitlab") { "Merge Requests" } else { "Pull Requests" }
    while ($true) {
        Show-Header
        Write-Host "$label ($($Global:VcsProvider))`n" -ForegroundColor Yellow
        Write-Host "  [1] List $label" -ForegroundColor Green
        Write-Host "  [2] Checkout Locally (test someone else's changes)" -ForegroundColor Green
        Write-Host "  [3] View Diff" -ForegroundColor Green
        Write-Host "  [4] Merge" -ForegroundColor Green
        Write-Host "  [5] Create from Current Branch" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-5]"
        switch ($c) {
            "1" { Show-Header; Vcs-ListChangeRequests @(); Pause-Console }
            "2" { $n = Read-Host "Number"; if ($n) { Vcs-CheckoutChangeRequest $n }; Pause-Console }
            "3" { $n = Read-Host "Number"; if ($n) { Show-Header; Vcs-DiffChangeRequest $n | Out-DeltaView }; Pause-Console }
            "4" {
                $n = Read-Host "Number to merge"
                if ($n -and (Confirm-DestructiveAction "Merge #$n")) {
                    Vcs-MergeChangeRequest $n
                    Write-WizardActionLog "Merged $label #$n"
                }
                Pause-Console
            }
            "5" {
                $t = Read-Host "Title"; $b = Read-Host "Description"
                if ($t) {
                    if ($Global:DryRun) { Write-Host "[DRY-RUN] Would create: $t" -ForegroundColor Yellow }
                    else { Vcs-CreateChangeRequest $t $b; Write-WizardActionLog "Created $label`: $t" }
                }
                Pause-Console
            }
            "0" { return }
        }
    }
}

# ==============================================================================
# RELEASES MENU
# ==============================================================================
function Show-VcsReleasesMenu {
    while ($true) {
        Show-Header
        Write-Host "RELEASES ($($Global:VcsProvider))`n" -ForegroundColor Yellow
        Write-Host "  [1] List Releases" -ForegroundColor Green
        Write-Host "  [2] Create Release" -ForegroundColor Green
        Write-Host "  [3] Delete Release" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-3]"
        switch ($c) {
            "1" { Show-Header; Vcs-ListReleases @(); Pause-Console }
            "2" {
                $tag = Read-Host "Tag (e.g. v1.0.0)"; $title = Read-Host "Title"
                if ($tag) {
                    if ($Global:DryRun) { Write-Host "[DRY-RUN] Would create release $tag" -ForegroundColor Yellow }
                    else { Vcs-CreateRelease $tag ($(if ($title) { $title } else { $tag })); Write-WizardActionLog "Created release $tag" }
                }
                Pause-Console
            }
            "3" {
                $tag = Read-Host "Tag to delete"
                if ($tag -and (Confirm-DestructiveAction "Delete release $tag")) {
                    Vcs-DeleteRelease $tag
                    Write-WizardActionLog "Deleted release $tag"
                }
                Pause-Console
            }
            "0" { return }
        }
    }
}

# ==============================================================================
# CI / RUNS MENU
# ==============================================================================
function Show-VcsRunsMenu {
    $label = if ($Global:VcsProvider -eq "gitlab") { "Pipelines" } else { "Actions" }
    while ($true) {
        Show-Header
        Write-Host "$label / CI ($($Global:VcsProvider))`n" -ForegroundColor Yellow
        Write-Host "  [1] List Recent Runs" -ForegroundColor Green
        Write-Host "  [2] Watch a Live Run" -ForegroundColor Green
        Write-Host "  [3] Trigger a Run Manually" -ForegroundColor Green
        Write-Host "  [4] View Run Logs" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-4]"
        switch ($c) {
            "1" { Show-Header; Invoke-SafeRun "List runs" { Vcs-ListRuns @() }; Pause-Console }
            "2" { Show-Header; Invoke-SafeRun "Watch live run" { Vcs-WatchRun }; Pause-Console }
            "3" { Show-Header; Invoke-SafeRun "Trigger run" { Vcs-TriggerRun @() }; Pause-Console }
            "4" { $n = Read-Host "Run/Job ID"; if ($n) { Show-Header; Invoke-SafeRun "View run logs" { Vcs-ViewRunLogs $n } }; Pause-Console }
            "0" { return }
        }
    }
}

# ==============================================================================
# GISTS / SNIPPETS MENU
# ==============================================================================
function Show-VcsSnippetsMenu {
    $label = if ($Global:VcsProvider -eq "gitlab") { "Snippets" } else { "Gists" }
    while ($true) {
        Show-Header
        Write-Host "$label ($($Global:VcsProvider))`n" -ForegroundColor Yellow
        Write-Host "  [1] List $label" -ForegroundColor Green
        Write-Host "  [2] Create from a File" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-2]"
        switch ($c) {
            "1" { Show-Header; Vcs-ListSnippets @(); Pause-Console }
            "2" {
                $f = Read-Host "Path to file"
                if (Test-Path $f) { Vcs-CreateSnippet $f; Write-WizardActionLog "Created $label from $f" }
                else { Write-Host "[!] File not found." -ForegroundColor Red }
                Pause-Console
            }
            "0" { return }
        }
    }
}

# ==============================================================================
# CODESPACES (GitHub only)
# ==============================================================================
function Show-VcsCodespacesMenu {
    Show-Header
    Write-Host "CODESPACES`n" -ForegroundColor Yellow
    if ($Global:VcsProvider -ne "github") {
        Write-Host "[i] Codespaces is a GitHub-only feature - no direct GitLab equivalent exists." -ForegroundColor Yellow
        Pause-Console
        return
    }
    Write-Host "  [1] List Codespaces" -ForegroundColor Green
    Write-Host "  [2] Create Codespace" -ForegroundColor Green
    Write-Host "  [3] Open (SSH into) a Codespace" -ForegroundColor Green
    Write-Host "  [4] Stop a Codespace" -ForegroundColor Green
    Write-Host "  [0] Back" -ForegroundColor Green
    $c = Read-Host "Select choice [0-4]"
    switch ($c) {
        "1" { Invoke-SafeRun "List codespaces" { gh codespace list } }
        "2" { Invoke-SafeRun "Create codespace" { gh codespace create } }
        "3" { $n = Read-Host "Codespace name"; if ($n) { Invoke-SafeRun "SSH into codespace" { gh codespace ssh -c $n } } }
        "4" { $n = Read-Host "Codespace name"; if ($n) { Invoke-SafeRun "Stop codespace" { gh codespace stop -c $n } } }
    }
    Pause-Console
}

# ==============================================================================
# REPO / PROJECT ADMIN MENU
# ==============================================================================
function Show-VcsRepoAdminMenu {
    while ($true) {
        Show-Header
        Write-Host "REPO / PROJECT ADMIN ($($Global:VcsProvider))`n" -ForegroundColor Yellow
        Write-Host "  [1] List My Repos" -ForegroundColor Green
        Write-Host "  [2] Create New Repo" -ForegroundColor Green
        Write-Host "  [3] Get Remote URL for a Repo" -ForegroundColor Green
        Write-Host "  [4] Add a Collaborator / Team Member" -ForegroundColor Green
        Write-Host "  [5] Rename Current Repo" -ForegroundColor Green
        Write-Host "  [6] Delete a Repo (PERMANENT!)" -ForegroundColor Red
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-6]"
        switch ($c) {
            "1" { Show-Header; Invoke-SafeRun "List repos" { Vcs-ListRepos }; Pause-Console }
            "2" {
                $n = Read-Host "New repo name"
                Write-Host "  [1] Public  [2] Private"
                $v = Read-Host "Visibility [1-2]"
                $vis = if ($v -eq "2") { "private" } else { "public" }
                if ($n) {
                    Vcs-CreateRepo $n $vis
                    Write-WizardActionLog "Created $($Global:VcsProvider) repo: $n ($vis)"
                    $uname = Vcs-MyUsername
                    if ($uname) {
                        $full = "$uname/$n"
                        Write-Host "`n--> Fetching remote URL for $full..." -ForegroundColor Cyan
                        $pair = Vcs-GetRepoUrl $full
                        if ($pair) {
                            $ssh = $pair.Split('|')[0]; $https = $pair.Split('|')[1]
                            Write-Host "Repo created!" -ForegroundColor Green
                            Write-Host "  SSH:   $ssh" -ForegroundColor Cyan
                            Write-Host "  HTTPS: $https" -ForegroundColor Cyan
                            $doOrigin = Read-Host "Set this as 'origin' for the current directory? (y/N)"
                            if ($doOrigin -match '^[Yy]$') {
                                Write-Host "  [1] Use SSH  [2] Use HTTPS"
                                $proto = Read-Host "  Choice [1-2]"
                                $chosen = if ($proto -eq "2") { $https } else { $ssh }
                                git remote remove origin 2>$null
                                Invoke-GitWizard remote add origin $chosen | Out-Null
                                Write-Host "[+] 'origin' set to $chosen" -ForegroundColor Green
                            }
                        }
                    }
                }
                Pause-Console
            }
            "3" {
                $n = Read-Host "Full repo name (owner/repo or namespace/project)"
                if ($n) {
                    Show-Header
                    $pair = Vcs-GetRepoUrl $n
                    if ($pair) {
                        $ssh = $pair.Split('|')[0]; $https = $pair.Split('|')[1]
                        Write-Host "$n" -ForegroundColor Green
                        Write-Host "  SSH:   $ssh" -ForegroundColor Cyan
                        Write-Host "  HTTPS: $https" -ForegroundColor Cyan
                        $doOrigin = Read-Host "Set this as 'origin'? (y/N)"
                        if ($doOrigin -match '^[Yy]$') {
                            Write-Host "  [1] Use SSH  [2] Use HTTPS"
                            $proto = Read-Host "  Choice [1-2]"
                            $chosen = if ($proto -eq "2") { $https } else { $ssh }
                            git remote remove origin 2>$null
                            Invoke-GitWizard remote add origin $chosen | Out-Null
                            Write-Host "[+] 'origin' set to $chosen" -ForegroundColor Green
                        }
                    } else {
                        Write-Host "[!] Couldn't fetch that repo's URL - check the name and your access." -ForegroundColor Red
                    }
                }
                Pause-Console
            }
            "4" {
                $n = Read-Host "Full repo name"; $un = Read-Host "Their username"
                $perm = ""
                if ($Global:VcsProvider -eq "github") {
                    Write-Host "  [1] Read  [2] Write  [3] Maintain  [4] Admin"
                    $pl = Read-Host "Permission [1-4]"
                    $perm = switch ($pl) { "2" { "push" } "3" { "maintain" } "4" { "admin" } default { "pull" } }
                } else {
                    Write-Host "  [1] Reporter  [2] Developer  [3] Maintainer  [4] Owner"
                    $pl = Read-Host "Permission [1-4]"
                    $perm = switch ($pl) { "2" { "30" } "3" { "40" } "4" { "50" } default { "20" } }
                }
                if ($n -and $un -and (Confirm-DestructiveAction "Grant '$un' access to '$n'")) {
                    Invoke-SafeRun "Add collaborator $un" { Vcs-AddCollaborator $n $un $perm }
                    Write-WizardActionLog "Added collaborator $un to $n ($($Global:VcsProvider))"
                }
                Pause-Console
            }
            "5" {
                $n = Read-Host "New name for THIS repo"
                if ($n -and (Confirm-DestructiveAction "Rename this repo to '$n'")) {
                    Vcs-RenameRepo $n
                    Write-WizardActionLog "Renamed repo to $n"
                }
                Pause-Console
            }
            "6" {
                $n = Read-Host "Full name of repo to DELETE (owner/repo)"
                if ($n -and (Confirm-DestructiveAction "PERMANENTLY DELETE '$n' - this cannot be undone")) {
                    Invoke-SafeRun "Delete $n" { Vcs-DeleteRepo $n }
                    Write-WizardActionLog "DELETED repo: $n"
                }
                Pause-Console
            }
            "0" { return }
        }
    }
}

function Show-VcsApiExplorer {
    Show-Header
    Write-Host "RAW API EXPLORER ($($Global:VcsProvider)) - Advanced`n" -ForegroundColor Yellow
    Write-Host "Enter a raw API path, e.g.: repos/OWNER/REPO/contents (GitHub) or projects/ID/issues (GitLab)`n" -ForegroundColor Cyan
    $p = Read-Host "API path"
    if ($p) { Vcs-Api @($p) }
    Pause-Console
}

# ==============================================================================
# DELTA DIFF SUITE — provider-agnostic
# ==============================================================================
function Out-DeltaView {
    if (Get-Command delta -ErrorAction SilentlyContinue) {
        $input | delta --paging=always
    } else {
        Write-Host "[i] 'delta' not installed - showing plain diff. Install via Tool Stack Manager." -ForegroundColor Yellow
        $input | Out-Host -Paging
    }
}

function Show-DeltaViewUncommitted {
    Show-Header
    Write-Host "UNCOMMITTED CHANGES (working directory)`n" -ForegroundColor Yellow
    $d = git diff
    if (-not $d) { Write-Host "[+] No uncommitted changes." -ForegroundColor Green; Pause-Console; return }
    $d | Out-DeltaView
    Pause-Console
}

function Show-DeltaViewStaged {
    Show-Header
    Write-Host "STAGED CHANGES (diff --cached)`n" -ForegroundColor Yellow
    $d = git diff --cached
    if (-not $d) { Write-Host "[+] Nothing staged." -ForegroundColor Green; Pause-Console; return }
    $d | Out-DeltaView
    Pause-Console
}

function Show-DeltaCompareBranches {
    Show-Header
    Write-Host "COMPARE TWO BRANCHES`n" -ForegroundColor Yellow
    $b1 = Select-BranchInteractive "SELECT FIRST BRANCH"
    if (-not $b1) { Pause-Console; return }
    $b2 = Select-BranchInteractive "SELECT SECOND BRANCH (compared against $b1)"
    if (-not $b2) { Pause-Console; return }
    Show-Header
    Write-Host "--- Diff: $b1...$b2 ---`n" -ForegroundColor Cyan
    git diff "$b1...$b2" | Out-DeltaView
    Pause-Console
}

function Show-DeltaCompareCommits {
    Show-Header
    Write-Host "COMPARE TWO COMMITS`n" -ForegroundColor Yellow
    $c1 = Read-Host "Enter FIRST commit hash"
    $c2 = Read-Host "Enter SECOND commit hash"
    if (-not $c1 -or -not $c2) { Write-Host "Both commit hashes required." -ForegroundColor Red; Pause-Console; return }
    git diff $c1 $c2 | Out-DeltaView
    Pause-Console
}

function Show-DeltaViewSingleCommit {
    Show-Header
    Write-Host "VIEW A SINGLE COMMIT'S DIFF`n" -ForegroundColor Yellow
    git --no-pager log --oneline -15
    $ch = Read-Host "`nEnter commit hash to view"
    if (-not $ch) { Pause-Console; return }
    git show $ch | Out-DeltaView
    Pause-Console
}

function Show-DeltaDiffSuiteMenu {
    while ($true) {
        Show-Header
        Write-Host "DELTA DIFF SUITE`n" -ForegroundColor Yellow
        Write-Host "Provider-agnostic - works identically on GitHub, GitLab, or any git remote.`n" -ForegroundColor Cyan
        Write-Host "  [1] View Uncommitted Changes" -ForegroundColor Green
        Write-Host "  [2] View Staged Changes" -ForegroundColor Green
        Write-Host "  [3] Compare Two Branches" -ForegroundColor Green
        Write-Host "  [4] Compare Two Commits" -ForegroundColor Green
        Write-Host "  [5] View a Single Commit's Diff" -ForegroundColor Green
        Write-Host "  [0] Back" -ForegroundColor Green
        $c = Read-Host "Select choice [0-5]"
        switch ($c) {
            "1" { Show-DeltaViewUncommitted }
            "2" { Show-DeltaViewStaged }
            "3" { Show-DeltaCompareBranches }
            "4" { Show-DeltaCompareCommits }
            "5" { Show-DeltaViewSingleCommit }
            "0" { return }
        }
    }
}

# ==============================================================================
# POWER TOOLS TOP-LEVEL MENU
# ==============================================================================
function Show-GitHostingPowerToolsMenu {
    if (-not (Confirm-VcsProvider)) { return }
    while ($true) {
        Show-Header
        Write-Host "GIT HOSTING POWER TOOLS - $($Global:VcsProvider.ToUpper())`n" -ForegroundColor Yellow
        if (-not (Test-VcsCliInstalled)) {
            Write-Host "[!] $(Get-VcsBinary) is not installed yet - most options below will prompt to install it.`n" -ForegroundColor Red
        }
        $prLabel = if ($Global:VcsProvider -eq "gitlab") { "Merge Requests" } else { "Pull Requests" }
        $ciLabel = if ($Global:VcsProvider -eq "gitlab") { "Pipelines" } else { "Actions" }
        $gistLabel = if ($Global:VcsProvider -eq "gitlab") { "Snippets" } else { "Gists" }

        Write-Host "  [1] Switch Provider (currently: $($Global:VcsProvider))" -ForegroundColor Green
        Write-Host "  [2] Issues" -ForegroundColor Green
        Write-Host "  [3] $prLabel" -ForegroundColor Green
        Write-Host "  [4] Releases" -ForegroundColor Green
        Write-Host "  [5] $ciLabel / CI" -ForegroundColor Green
        Write-Host "  [6] $gistLabel" -ForegroundColor Green
        Write-Host "  [7] Codespaces $(if ($Global:VcsProvider -ne 'github') { '(GitHub only)' })" -ForegroundColor Green
        Write-Host "  [8] Repo / Project Admin" -ForegroundColor Green
        Write-Host "  [9] Raw API Explorer (advanced)" -ForegroundColor Green
        Write-Host "  [10] Delta Diff Suite" -ForegroundColor Green
        Write-Host "  [0] Back to Main Menu" -ForegroundColor Green
        Write-Host "`n===================================================================="
        $c = Read-Host "Select choice [0-10]"
        switch ($c) {
            "1" {
                Write-Host "  [1] GitHub  [2] GitLab"
                $sw = Read-Host "Choice [1-2]"
                if ($sw -eq "1") { $Global:VcsProvider = "github" } elseif ($sw -eq "2") { $Global:VcsProvider = "gitlab" }
            }
            "2" { if (Confirm-VcsReady) { Show-VcsIssuesMenu } }
            "3" { if (Confirm-VcsReady) { Show-VcsChangeRequestsMenu } }
            "4" { if (Confirm-VcsReady) { Show-VcsReleasesMenu } }
            "5" { if (Confirm-VcsReady) { Show-VcsRunsMenu } }
            "6" { if (Confirm-VcsReady) { Show-VcsSnippetsMenu } }
            "7" { if (Confirm-VcsReady) { Show-VcsCodespacesMenu } }
            "8" { if (Confirm-VcsReady) { Show-VcsRepoAdminMenu } }
            "9" { if (Confirm-VcsReady) { Show-VcsApiExplorer } }
            "10" { Show-DeltaDiffSuiteMenu }
            "0" { return }
        }
    }
}
