# ==============================================================================
# ENGINE NAME:  workspace-engine.ps1 (Workspace Explorer - Windows Engine)
# DESCRIPTION:  One keyboard-driven explorer over "git status" + diff + file
#               history + project history, with guided, reversible reverts.
#               Dot-sourced by git-wizard.ps1 (added to $SubModules). Depends
#               on helpers already defined there: Invoke-GitWizard,
#               New-SafetyBackup, Confirm-DestructiveAction,
#               Write-WizardActionLog, Show-Header, Pause-Console.
#
# STAGE 1 OF 6: Git data-layer functions only (no UI yet). Mirrors
# linux/workspace-explorer.sh function-for-function so both platforms behave
# identically. Unlike the Bash side (which uses global parallel arrays to
# dodge subshell variable loss), PowerShell functions can return objects
# directly, so Get-WsStatus returns an array of PSCustomObject instead.
# ==============================================================================

# NUL-device path usable by `git diff --no-index` on both PowerShell 5.1 and
# 7+, on Windows (git for Windows special-cases the literal string "/dev/null"
# in its diff machinery rather than opening it as a real path) and Linux.
$Global:NullDevice = "/dev/null"

# Raw ANSI SGR codes (via [char]27, never the PS6+-only `e escape -- see the
# note on $Global:ESC in git-wizard.ps1) for per-badge colored text embedded
# directly in a string, e.g. a status row. This mirrors how the rest of the
# tool already handles colored diff text (vcs-engine.ps1's Out-DeltaView
# writes `git diff --color=always` output straight to the console and lets
# the terminal interpret the embedded codes) rather than Write-Host
# -ForegroundColor, which can only color one whole Write-Host call at a time.
$Global:WsEsc = [char]27
$Global:WsRed = "$($Global:WsEsc)[0;31m"
$Global:WsGreen = "$($Global:WsEsc)[0;32m"
$Global:WsYellow = "$($Global:WsEsc)[1;33m"
$Global:WsCyan = "$($Global:WsEsc)[0;36m"
$Global:WsBold = "$($Global:WsEsc)[1m"
$Global:WsReset = "$($Global:WsEsc)[0m"

# ------------------------------------------------------------------------------
# Get-WsStatus — parsed `git status --porcelain=v1 -z` entries.
# Returns an array of objects: X, Y, Path, OrigPath ('' unless rename/copy),
# Badge ('modified'|'staged'|'deleted'|'untracked'|'renamed'|'added'|'conflict')
#
# NOTE: unlike Bash, a .NET string can hold embedded NUL (0x00) characters
# without truncation (it isn't a C null-terminated buffer), so capturing the
# whole -z stream into one string and splitting on "`0" is safe here - the
# Bash side needs a streaming read instead for exactly that reason.
# ------------------------------------------------------------------------------
function Get-WsStatus {
    $isRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($isRepo -ne "true") { return @() }

    $rawLines = & git status --porcelain=v1 -z 2>$null
    if (-not $rawLines) { return @() }
    $raw = ($rawLines -join "")
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($t in $raw.Split([char]0)) { $tokens.Add($t) }

    $results = @()
    $i = 0
    while ($i -lt $tokens.Count) {
        $entry = $tokens[$i]
        if ([string]::IsNullOrEmpty($entry)) { $i++; continue }

        $x = $entry.Substring(0, 1)
        $y = $entry.Substring(1, 1)
        $path = $entry.Substring(3)
        $orig = ""

        if ($x -eq "R" -or $x -eq "C") {
            $i++
            if ($i -lt $tokens.Count) { $orig = $tokens[$i] }
        }

        if ($x -eq "U" -or $y -eq "U" -or ($x -eq "A" -and $y -eq "A") -or ($x -eq "D" -and $y -eq "D")) {
            $badge = "conflict"
        } elseif ($x -eq "?" -and $y -eq "?") {
            $badge = "untracked"
        } elseif ($x -eq "R") {
            $badge = "renamed"
        } elseif ($x -eq "A") {
            $badge = "added"
        } elseif ($y -eq "D") {
            $badge = "deleted"
        } elseif ($x -ne " " -and $x -ne "?") {
            $badge = "staged"
        } else {
            $badge = "modified"
        }

        $results += [PSCustomObject]@{
            X        = $x
            Y        = $y
            Path     = $path
            OrigPath = $orig
            Badge    = $badge
        }
        $i++
    }
    return $results
}

# ------------------------------------------------------------------------------
# Get-WsFileDiff -Path <path> [-Staged] [-StatusEntries <array from Get-WsStatus>]
# Returns the diff text for one file. Handles untracked (no-index), staged
# vs unstaged, and deleted files. $StatusEntries avoids re-running git status
# just to check "is this untracked" when the caller already has it cached.
# ------------------------------------------------------------------------------
function Get-WsFileDiff {
    param(
        [string]$Path,
        [switch]$Staged,
        [array]$StatusEntries = $null
    )

    if (-not $StatusEntries) { $StatusEntries = Get-WsStatus }
    $isUntracked = $false
    foreach ($e in $StatusEntries) {
        if ($e.Path -eq $Path -and $e.Badge -eq "untracked") { $isUntracked = $true; break }
    }

    if ($isUntracked) {
        return (git diff --no-index --color=always -- /dev/null "$Path" 2>$null) -join "`n"
    }

    if ($Staged) {
        return (git diff --cached --color=always -- "$Path") -join "`n"
    } else {
        $unstagedPart = (git diff --color=always -- "$Path") -join "`n"
        $stagedPart = (git diff --cached --color=always -- "$Path") -join "`n"
        if ($stagedPart) {
            # [char]27, not `e -- `e is only recognized on PowerShell 6+; on
            # Windows PowerShell 5.1 it prints as a literal "e" (see the same
            # note on $Global:ESC in git-wizard.ps1).
            $esc = [char]27
            $header = "`n$esc[36m$esc[1m--- Also staged for commit ---$esc[0m"
            return "$unstagedPart$header`n$stagedPart"
        }
        return $unstagedPart
    }
}

# ------------------------------------------------------------------------------
# Revert action 1: restore to HEAD (last commit).
# ------------------------------------------------------------------------------
function Invoke-WsRevertToLastCommit {
    param([string]$Path)
    New-SafetyBackup "pre-revert-lastcommit"
    Invoke-GitWizard restore --source=HEAD --staged --worktree "--" "$Path"
}

# ------------------------------------------------------------------------------
# Get-WsHashBeforeLastChange -Path <path>
# Second entry of `git log -n 2 --format=%H -- path` - "the version before
# the file's last change". Empty if fewer than 2 commits touch the file.
# ------------------------------------------------------------------------------
function Get-WsHashBeforeLastChange {
    param([string]$Path)
    $hashes = git log -n 2 --format=%H -- "$Path" 2>$null
    if (-not $hashes -or $hashes.Count -lt 2) { return "" }
    return $hashes[1]
}

function Invoke-WsRevertToBeforeLastChange {
    param([string]$Path)
    $hash = Get-WsHashBeforeLastChange -Path $Path
    if (-not $hash) { return $false }
    New-SafetyBackup "pre-revert-prior-version"
    Invoke-GitWizard restore --source=$hash --worktree "--" "$Path"
    Invoke-GitWizard add "--" "$Path"
    return $true
}

# ------------------------------------------------------------------------------
# Get-WsHashOriginalAdd -Path <path>
# Commit that first added this exact path (matches a rename's "add" event
# for the new name, per spec), via `git log --diff-filter=A`.
# ------------------------------------------------------------------------------
function Get-WsHashOriginalAdd {
    param([string]$Path)
    $hashes = git log --diff-filter=A --format=%H -- "$Path" 2>$null
    if (-not $hashes) { return "" }
    if ($hashes -is [array]) { return $hashes[-1] }
    return $hashes
}

function Invoke-WsRevertToOriginalState {
    param([string]$Path)
    $hash = Get-WsHashOriginalAdd -Path $Path
    if (-not $hash) { return $false }
    New-SafetyBackup "pre-revert-original"
    Invoke-GitWizard restore --source=$hash --worktree "--" "$Path"
    Invoke-GitWizard add "--" "$Path"
    return $true
}

# ------------------------------------------------------------------------------
# Invoke-WsDeleteUntracked -Path <path>
# Untracked files have no commit to fall back to, so this is intentionally
# its OWN action (never folded into "revert"), with its own stricter confirm
# at the call site. No backup tag is possible here - caller must warn the
# user this is NOT like the other revert actions.
# ------------------------------------------------------------------------------
function Invoke-WsDeleteUntracked {
    param([string]$Path)
    Invoke-GitWizard clean -f "--" "$Path"
}

# ------------------------------------------------------------------------------
# Get-WsFileLog -Path <path> [-Limit n] [-Skip n]
# All commits touching this path across renames (--follow), newest first.
# Returns objects: Hash, Author, Date, Subject.
# ------------------------------------------------------------------------------
function Get-WsFileLog {
    param([string]$Path, [int]$Limit = 50, [int]$Skip = 0)
    $lines = git log --follow --format='%H%x1f%an%x1f%ar%x1f%s' --skip=$Skip -n $Limit -- "$Path" 2>$null
    return (ConvertTo-WsLogObjects $lines)
}

function Get-WsFileLogCount {
    param([string]$Path)
    $lines = git log --follow --format='%H' -- "$Path" 2>$null
    if (-not $lines) { return 0 }
    if ($lines -is [array]) { return $lines.Count }
    return 1
}

# ------------------------------------------------------------------------------
# Get-WsProjectLog [-Limit n] [-Skip n] — all repo commits, newest first.
# ------------------------------------------------------------------------------
function Get-WsProjectLog {
    param([int]$Limit = 50, [int]$Skip = 0)
    $lines = git log --format='%H%x1f%an%x1f%ar%x1f%s' --skip=$Skip -n $Limit 2>$null
    return (ConvertTo-WsLogObjects $lines)
}

function Get-WsProjectLogCount {
    $count = git rev-list --count HEAD 2>$null
    if (-not $count) { return 0 }
    return [int]$count
}

# Shared helper: %x1f (unit separator) delimited log lines -> objects.
function ConvertTo-WsLogObjects {
    param($Lines)
    $out = @()
    if (-not $Lines) { return $out }
    $sep = [string][char]0x1F
    foreach ($line in $Lines) {
        $parts = $line -split [regex]::Escape($sep)
        if ($parts.Count -ge 4) {
            $out += [PSCustomObject]@{
                Hash    = $parts[0]
                Author  = $parts[1]
                Date    = $parts[2]
                Subject = $parts[3]
            }
        }
    }
    return $out
}

# ------------------------------------------------------------------------------
# Get-WsCommitSummary -Hash <hash> — stats + message for the Project Timeline
# detail screen.
# ------------------------------------------------------------------------------
function Get-WsCommitSummary {
    param([string]$Hash)
    return (git show --stat --format='%H%n%an <%ae>%n%ad%n%n%s%n%n%b' --date=relative "$Hash" 2>$null) -join "`n"
}

# ------------------------------------------------------------------------------
# Get-WsCommitFiles -Hash <hash> — files touched by a commit.
# ------------------------------------------------------------------------------
function Get-WsCommitFiles {
    param([string]$Hash)
    $files = git diff-tree --no-commit-id --name-only -r "$Hash" 2>$null
    if (-not $files) { return @() }
    if ($files -is [array]) { return $files }
    return @($files)
}

# ------------------------------------------------------------------------------
# Get-WsCommitFileDiff -Hash <hash> -Path <path> — that commit's change to
# one file.
# ------------------------------------------------------------------------------
function Get-WsCommitFileDiff {
    param([string]$Hash, [string]$Path)
    return (git show --color=always "$Hash" -- "$Path" 2>$null) -join "`n"
}

# ------------------------------------------------------------------------------
# Commit-level actions (File Timeline / Project Timeline screens). All go
# through Invoke-GitWizard / New-SafetyBackup for dry-run + backup parity.
# ------------------------------------------------------------------------------
function Invoke-WsApplyCommitFileToCurrent {
    param([string]$Hash, [string]$Path)
    New-SafetyBackup "pre-apply-commit-file"
    $patch = git show "$Hash" -- "$Path"
    $patch | git apply --3way 2>&1
}

function Invoke-WsRestoreFileToCommit {
    param([string]$Hash, [string]$Path)
    New-SafetyBackup "pre-restore-file-to-commit"
    Invoke-GitWizard restore --source=$Hash --worktree "--" "$Path"
    Invoke-GitWizard add "--" "$Path"
}

function Invoke-WsUndoFileChangeInCommit {
    param([string]$Hash, [string]$Path)
    New-SafetyBackup "pre-undo-file-change"
    $patch = git show "$Hash" -- "$Path"
    $patch | git apply -R --3way 2>&1
}

function Invoke-WsRevertCommitSafe {
    param([string]$Hash)
    New-SafetyBackup "pre-revert-commit"
    Invoke-GitWizard revert --no-edit $Hash
}

# ------------------------------------------------------------------------------
# Test-WsIsBinaryFile -Path <path>
# True if git's own binary heuristic (NUL byte present) says this content is
# binary. For a path that still exists on disk, diff it against /dev/null's
# Windows-safe equivalent via `git diff --no-index --numstat`; for a path
# that's gone from disk but tracked (e.g. deleted-but-not-yet-committed),
# fall back to `git diff --numstat` against the index/HEAD, whose "-	-"
# column marks binary content the same way.
# ------------------------------------------------------------------------------
function Test-WsIsBinaryFile {
    param([string]$Path)
    $numstatLine = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $numstatLine = (git diff --no-index --numstat -- $NullDevice $Path 2>$null) | Select-Object -First 1
    } else {
        $numstatLine = (git diff --numstat -- "$Path" 2>$null) | Select-Object -First 1
    }
    if (-not $numstatLine) { return $false }
    return ($numstatLine -match '^-\s+-\s')
}

# ==============================================================================
# STAGE 2 OF 6: NAVIGATION ENGINE — the shared key-reader, breadcrumb, action
# bar, and generic list browser used by every Workspace Explorer screen
# (Changes list, File Timeline list, Project Timeline list). Mirrors
# linux/workspace-explorer.sh's Stage 2 function-for-function.
# ==============================================================================

# ------------------------------------------------------------------------------
# Show-WsHeader — lightweight header for the Explorer, same reasoning as the
# Bash side's ws_show_header: redraws every keystroke, so no big ASCII banner.
# ------------------------------------------------------------------------------
function Show-WsHeader {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "  Workspace Explorer   Mode: $Global:WizardMode   Dry-Run: $Global:DryRun" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
}

function Write-WsBreadcrumb {
    param([string[]]$Breadcrumb)
    Write-Host (($Breadcrumb) -join " > ") -ForegroundColor Yellow
    Write-Host ""
}

function Write-WsActionBar {
    param([string]$Text)
    Write-Host ""
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
}

# ------------------------------------------------------------------------------
# Get-WsRawKey — the ONLY place that touches real console input. Kept as its
# own one-line function (rather than inlined) so tests can override it: a
# test passes -RawKeyReader to Invoke-WsListNavigate with a scriptblock that
# pops pre-built fake key objects instead of touching a real console, since
# $Host.UI.RawUI.ReadKey() has no console to read from in a non-interactive
# test run.
# ------------------------------------------------------------------------------
function Get-WsRawKey {
    return $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ------------------------------------------------------------------------------
# ConvertTo-WsNormalizedKey <rawKey> — pure mapping from a raw key-info object
# (anything with .VirtualKeyCode / .Character, real or mocked) to one of:
# UP DOWN LEFT RIGHT ENTER ESC SPACE SLASH QMARK Q CHAR:<c>
# ------------------------------------------------------------------------------
function ConvertTo-WsNormalizedKey {
    param($RawKey)
    switch ($RawKey.VirtualKeyCode) {
        38 { return "UP" }
        40 { return "DOWN" }
        37 { return "LEFT" }
        39 { return "RIGHT" }
        13 { return "ENTER" }
        27 { return "ESC" }
        32 { return "SPACE" }
        33 { return "PGUP" }
        34 { return "PGDN" }
        36 { return "HOME" }
        35 { return "END" }
    }
    switch ($RawKey.Character) {
        '/' { return "SLASH" }
        '?' { return "QMARK" }
        'q' { return "Q" }
        'Q' { return "Q" }
    }
    return "CHAR:$($RawKey.Character)"
}

# ------------------------------------------------------------------------------
# Get-WsVisibleIndices <items> <filterText> — indices of $items whose text
# contains $filterText (case-insensitive substring match), or all indices if
# $filterText is empty. Pure helper, split out so it's unit-testable on its
# own without going through the full navigator loop.
# ------------------------------------------------------------------------------
function Get-WsVisibleIndices {
    param([string[]]$Items, [string]$FilterText)
    $result = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ([string]::IsNullOrEmpty($FilterText) -or $Items[$i].ToLowerInvariant().Contains($FilterText.ToLowerInvariant())) {
            $result.Add($i)
        }
    }
    return $result
}

# ------------------------------------------------------------------------------
# Invoke-WsListNavigate — generic interactive list browser.
#
# PARAMETERS:
#   -Items           array of pre-formatted display strings (one per row)
#   -Title            header text shown above the list
#   -Breadcrumb       string[] path segments, e.g. @("Changes","src/app.py")
#   -Markable         enables Space-to-mark
#   -Filterable       enables "/" filtering
#   -HelpText         multi-line help text shown on "?"
#   -ExtraBar         extra "[key] label" text appended to the action bar,
#                     or "" for none
#   -MarkedIndices    a [List[int]] the CALLER owns and passes back in on the
#                     next call, so marks persist across repeated visits to
#                     the same screen (it's a reference type, so this function
#                     mutates it in place; initialize with
#                     [System.Collections.Generic.List[int]]::new() the first
#                     time)
#   -RawKeyReader     scriptblock returning one raw key object; defaults to
#                     { Get-WsRawKey }. Tests override this to drive the
#                     navigator without a real console.
#   -ExtraKeys        string of extra single characters the caller wants
#                     surfaced (e.g. "RMU" for per-screen batch actions like
#                     Revert-all/Revert-Marked/Undo); any other unrecognized
#                     character is silently ignored.
#   -Viewport         $true to clip rendering to the console height and
#                     scroll (Up/Down/PgUp/PgDn/Home/End move a viewport
#                     window) instead of printing every item every redraw.
#                     Default $false: every item is printed unconditionally,
#                     exactly as before this was added -- needed for large
#                     lists (hundreds-thousands of files), overkill and
#                     visually unchanged for the short lists every existing
#                     screen uses.
#   -InitialCursor    an ORIGINAL index to start the cursor on, or -1 (the
#                     default) for the top of the list.
#   -InitialFilter    filter text to pre-apply on entry, or "" (the default)
#                     for none. Lets a caller restore where the user was
#                     after a round trip into a sub-screen.
#
# RETURNS: [PSCustomObject]@{ Result = "open"|"back"|"quit"|"key:<c>"; Selected = <int>; LastFilter = <string> }
# Selected is the ORIGINAL (unfiltered) index into -Items, or -1 for back/quit/key.
# LastFilter is the filter text in effect when the screen was left, for a
# caller that wants to pass it back in as -InitialFilter next time.
# ------------------------------------------------------------------------------
function Invoke-WsListNavigate {
    param(
        [string[]]$Items,
        [string]$Title,
        [string[]]$Breadcrumb,
        [bool]$Markable = $false,
        [bool]$Filterable = $false,
        [string]$HelpText = "",
        [string]$ExtraBar = "",
        [System.Collections.Generic.List[int]]$MarkedIndices,
        [scriptblock]$RawKeyReader = { Get-WsRawKey },
        [string]$ExtraKeys = "",
        [bool]$Viewport = $false,
        [int]$InitialCursor = -1,
        [string]$InitialFilter = "",
        [string]$ItemNoun = "items"
    )

    # Explicit $null check, NOT "-not $MarkedIndices": an empty (but real,
    # caller-owned) List[int] is falsy in PowerShell's boolean context same
    # as an empty array, so "-not" would silently swap the caller's list for
    # a disconnected new one and break the whole point of passing it by
    # reference (marks would render during this call, then vanish on return).
    if ($null -eq $MarkedIndices) { $MarkedIndices = [System.Collections.Generic.List[int]]::new() }

    $cursor = 0
    $filterText = $InitialFilter
    $filterMode = $false
    $viewOffset = 0
    $visibleIdx = Get-WsVisibleIndices -Items $Items -FilterText $filterText

    if ($InitialCursor -ge 0) {
        for ($row = 0; $row -lt $visibleIdx.Count; $row++) {
            if ($visibleIdx[$row] -eq $InitialCursor) { $cursor = $row; break }
        }
    }

    while ($true) {
        if ($visibleIdx.Count -eq 0) {
            $cursor = 0
        } elseif ($cursor -ge $visibleIdx.Count) {
            $cursor = $visibleIdx.Count - 1
        } elseif ($cursor -lt 0) {
            $cursor = 0
        }

        $consoleRows = 24
        try { $consoleRows = $Host.UI.RawUI.WindowSize.Height } catch { }
        $visibleRows = $consoleRows - 10
        if ($visibleRows -lt 3) { $visibleRows = 3 }

        Show-WsHeader
        Write-WsBreadcrumb -Breadcrumb $Breadcrumb
        Write-Host "$Title`n" -ForegroundColor Yellow

        if ($visibleIdx.Count -eq 0) {
            if ($filterText) {
                Write-Host "(no items matching `"$filterText`")" -ForegroundColor Cyan
            } else {
                Write-Host "(nothing here)" -ForegroundColor Cyan
            }
        } elseif ($Viewport) {
            # Opt-in only (see header note) -- clip rendering to the console
            # height and keep the cursor in view, instead of printing every
            # item every redraw. Skipped entirely for existing callers
            # (Changes, File/Project Timeline), which never pass -Viewport,
            # so their rendering is unchanged from before this was added.
            $total = $visibleIdx.Count
            if ($cursor -lt $viewOffset) { $viewOffset = $cursor }
            if ($cursor -ge ($viewOffset + $visibleRows)) { $viewOffset = $cursor - $visibleRows + 1 }
            if ($viewOffset -lt 0) { $viewOffset = 0 }
            if (($viewOffset + $visibleRows) -gt $total) {
                $viewOffset = $total - $visibleRows
                if ($viewOffset -lt 0) { $viewOffset = 0 }
            }

            $shown = 0
            for ($row = $viewOffset; $row -lt $total -and $shown -lt $visibleRows; $row++) {
                $vi = $visibleIdx[$row]
                $marker = "  "
                if ($MarkedIndices.Contains($vi)) { $marker = "* " }
                if ($row -eq $cursor) {
                    Write-Host "$marker  " -NoNewline
                    Write-Host "->" -NoNewline -ForegroundColor Green
                    Write-Host " $($Items[$vi])"
                } else {
                    Write-Host "$marker     $($Items[$vi])"
                }
                $shown++
            }
            $noun = if ($ItemNoun) { $ItemNoun } else { "items" }
            $unfilteredTotal = $Items.Count
            if ($total -ne $unfilteredTotal) {
                $countText = "$total of $unfilteredTotal $noun"
            } else {
                $countText = "$total $noun"
            }
            if ($total -gt $visibleRows) {
                $countText += "  (showing $($viewOffset + 1)-$($viewOffset + $shown))"
            }
            Write-Host "`n$countText" -ForegroundColor Cyan
        } else {
            for ($row = 0; $row -lt $visibleIdx.Count; $row++) {
                $vi = $visibleIdx[$row]
                $marker = "  "
                if ($MarkedIndices.Contains($vi)) { $marker = "* " }
                if ($row -eq $cursor) {
                    # Colors the arrow itself via -ForegroundColor, then lets the
                    # item's own embedded ANSI color codes (if any -- e.g. a
                    # per-badge colored status row) render normally afterward,
                    # rather than forcing the whole line green and clobbering
                    # them. Matches the Bash side, where the same thing happens
                    # naturally because its item string's own color codes
                    # reassert themselves right after the arrow.
                    Write-Host "$marker  " -NoNewline
                    Write-Host "->" -NoNewline -ForegroundColor Green
                    Write-Host " $($Items[$vi])"
                } else {
                    Write-Host "$marker     $($Items[$vi])"
                }
            }
        }

        if ($filterMode) {
            Write-Host ""
            Write-Host "Filter: ${filterText}_  (Enter to apply, Esc to cancel)" -ForegroundColor Yellow
        }

        $bar = "[Up/Down] Move  [Enter/Right] Open  [Esc/Left] Back"
        if ($Markable) { $bar += "  [Space] Mark" }
        if ($Filterable) { $bar += "  [/] Filter" }
        if ($Viewport) { $bar += "  [PgUp/PgDn/Home/End] Scroll" }
        $bar += "  [?] Help  [q] Quit"
        if ($ExtraBar) { $bar += "`n$ExtraBar" }
        Write-WsActionBar -Text $bar

        $raw = & $RawKeyReader

        if ($filterMode) {
            if ($raw.VirtualKeyCode -eq 13) {
                $filterMode = $false
            } elseif ($raw.VirtualKeyCode -eq 27) {
                $filterText = ""
                $filterMode = $false
                $visibleIdx = Get-WsVisibleIndices -Items $Items -FilterText $filterText
            } elseif ($raw.VirtualKeyCode -eq 8) {
                if ($filterText.Length -gt 0) { $filterText = $filterText.Substring(0, $filterText.Length - 1) }
                $visibleIdx = Get-WsVisibleIndices -Items $Items -FilterText $filterText
            } elseif ($raw.Character -and [int][char]$raw.Character -ge 32) {
                $filterText += $raw.Character
                $visibleIdx = Get-WsVisibleIndices -Items $Items -FilterText $filterText
            }
            continue
        }

        $key = ConvertTo-WsNormalizedKey -RawKey $raw
        switch ($key) {
            "UP" {
                if ($visibleIdx.Count -gt 0) {
                    $cursor--
                    if ($cursor -lt 0) { $cursor = $visibleIdx.Count - 1 }
                }
            }
            "DOWN" {
                if ($visibleIdx.Count -gt 0) {
                    $cursor++
                    if ($cursor -ge $visibleIdx.Count) { $cursor = 0 }
                }
            }
            "HOME" {
                $cursor = 0
            }
            "END" {
                if ($visibleIdx.Count -gt 0) { $cursor = $visibleIdx.Count - 1 }
            }
            "PGUP" {
                $cursor -= $visibleRows
                if ($cursor -lt 0) { $cursor = 0 }
            }
            "PGDN" {
                $cursor += $visibleRows
                if ($visibleIdx.Count -gt 0 -and $cursor -ge $visibleIdx.Count) { $cursor = $visibleIdx.Count - 1 }
            }
            "ENTER" {
                if ($visibleIdx.Count -gt 0) {
                    return [PSCustomObject]@{ Result = "open"; Selected = $visibleIdx[$cursor]; LastFilter = $filterText }
                }
            }
            "RIGHT" {
                if ($visibleIdx.Count -gt 0) {
                    return [PSCustomObject]@{ Result = "open"; Selected = $visibleIdx[$cursor]; LastFilter = $filterText }
                }
            }
            "ESC" {
                return [PSCustomObject]@{ Result = "back"; Selected = -1; LastFilter = $filterText }
            }
            "LEFT" {
                return [PSCustomObject]@{ Result = "back"; Selected = -1; LastFilter = $filterText }
            }
            "SPACE" {
                if ($Markable -and $visibleIdx.Count -gt 0) {
                    $target = $visibleIdx[$cursor]
                    if ($MarkedIndices.Contains($target)) {
                        [void]$MarkedIndices.Remove($target)
                    } else {
                        $MarkedIndices.Add($target)
                    }
                }
            }
            "SLASH" {
                if ($Filterable) { $filterMode = $true }
            }
            "QMARK" {
                Show-WsHeader
                Write-Host "HELP`n" -ForegroundColor Yellow
                Write-Host $HelpText
                Write-Host ""
                Write-Host "Press any key to continue..." -NoNewline
                [void](& $RawKeyReader)
                Write-Host ""
            }
            "Q" {
                return [PSCustomObject]@{ Result = "quit"; Selected = -1; LastFilter = $filterText }
            }
            default {
                if ($key.StartsWith("CHAR:")) {
                    $c = $key.Substring(5)
                    if ($c -and $ExtraKeys.Contains($c)) {
                        # Also expose the row under the cursor at the moment
                        # the extra key was pressed, same as "open" does, so
                        # a per-row extra action knows which row it applies to.
                        $sel = -1
                        if ($visibleIdx.Count -gt 0) { $sel = $visibleIdx[$cursor] }
                        return [PSCustomObject]@{ Result = "key:$c"; Selected = $sel; LastFilter = $filterText }
                    }
                }
            }
        }
    }
}

# ==============================================================================
# STAGE 3 OF 6: CHANGES SCREEN - diff viewing + the three revert actions,
# wired through the existing safety layer (Invoke-GitWizard, New-SafetyBackup,
# Confirm-DestructiveAction, Write-WizardActionLog). Mirrors
# linux/workspace-explorer.sh's Stage 3 function-for-function -- see that
# file's header comment for why every revert action ALSO does a plain
# file-content backup under .git/wizard-backups/ alongside the usual HEAD
# tag: New-SafetyBackup only tags a commit, which protects nothing about the
# uncommitted working-tree/index content these actions actually discard.
# ==============================================================================

$Global:WsLastActionKind = ""     # "files" | "commit"
$Global:WsLastActionDesc = ""
$Global:WsLastActionBackupDir = ""
$Global:WsLastActionFiles = @()   # "sanitized|original_path" strings -- kind=files
$Global:WsLastActionTag = ""      # backup tag to reset --hard to -- kind=commit

function Get-WsGitDir {
    return (git rev-parse --git-dir 2>$null)
}

function ConvertTo-WsSanitizedPath {
    param([string]$Path)
    return ($Path -replace '/', '__')
}

# ------------------------------------------------------------------------------
# Save-WsBlobBytes <sha> <outFile> -- writes a git blob's raw bytes to a file
# without going through PowerShell's text pipeline (which would risk
# mangling binary content via encoding/newline translation). $Sha is always a
# bare hex object id with no special characters, so it can be interpolated
# straight into ProcessStartInfo.Arguments with no quoting/escaping concerns
# -- the one thing that string-based Arguments property can't safely handle
# is an argument containing spaces or quotes, which a SHA never does.
# ------------------------------------------------------------------------------
function Save-WsBlobBytes {
    param([string]$Sha, [string]$OutFile)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.Arguments = "cat-file -p $Sha"
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = (Get-Location).Path
    $proc = [System.Diagnostics.Process]::Start($psi)
    $fs = [System.IO.File]::Create($OutFile)
    $proc.StandardOutput.BaseStream.CopyTo($fs)
    $fs.Close()
    $proc.WaitForExit()
}

# ------------------------------------------------------------------------------
# Backup-WsFileContent <path> <backupDir>
# Copies the file's CURRENT on-disk (worktree) content via Copy-Item (a plain
# filesystem copy -- byte-safe for binary content with no encoding risk),
# and, ONLY if the index genuinely differs from HEAD for this path (not
# merely because the path happens to be tracked -- see the bug note below),
# its staged blob content via Save-WsBlobBytes.
# ------------------------------------------------------------------------------
function Backup-WsFileContent {
    param([string]$Path, [string]$BackupDir)
    $sanitized = ConvertTo-WsSanitizedPath -Path $Path
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $BackupDir "$sanitized.worktree") -Force
    }

    # `git diff --cached --quiet` is silent either way; only its exit code
    # matters. Checking this (rather than "is the path in the index at all",
    # which is true for virtually every tracked file all the time) is what
    # keeps Restore-WsFileContent from unconditionally re-staging files that
    # were never staged to begin with.
    git diff --cached --quiet -- "$Path" 2>$null
    $hasStagedDiff = ($LASTEXITCODE -ne 0)
    if ($hasStagedDiff) {
        $sha = (git rev-parse ":$Path" 2>$null)
        if ($sha) {
            Save-WsBlobBytes -Sha $sha -OutFile (Join-Path $BackupDir "$sanitized.staged")
        }
    }
    return $sanitized
}

# ------------------------------------------------------------------------------
# Restore-WsFileContent <path> <backupDir>
# Reverses Backup-WsFileContent: restores the worktree file from the backed
# up copy (removing it if it didn't exist at backup time), and restores the
# INDEX to its exact prior blob if a .staged copy was captured -- via
# hash-object + update-index directly, NOT `git add` on the just-restored
# worktree file, because a file that was staged and then edited again before
# being reverted ("MM" in porcelain) has different staged-vs-worktree
# content, and `git add` would stage the worktree copy, collapsing that
# split instead of reproducing it.
# ------------------------------------------------------------------------------
function Restore-WsFileContent {
    param([string]$Path, [string]$BackupDir)
    $sanitized = ConvertTo-WsSanitizedPath -Path $Path
    $wt = Join-Path $BackupDir "$sanitized.worktree"
    $staged = Join-Path $BackupDir "$sanitized.staged"

    if (Test-Path -LiteralPath $wt) {
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $wt -Destination $Path -Force
    } else {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $staged) {
        $blobSha = (git hash-object -w $staged)
        $mode = "100644"
        Invoke-GitWizard update-index --add --cacheinfo "$mode,$blobSha,$Path"
    } else {
        Invoke-GitWizard reset "--" $Path 2>$null
    }
}

# For worktree/index-level actions (the three revert options, revert-all,
# revert-marked, apply/restore/undo-file) -- undo restores file CONTENT from
# the backup dir, since a commit tag alone captures nothing about
# uncommitted content (see this file's header note on the safety layer).
function Set-WsLastActionFiles {
    param([string]$Desc, [string]$BackupDir, [string[]]$Files)
    $Global:WsLastActionKind = "files"
    $Global:WsLastActionDesc = $Desc
    $Global:WsLastActionBackupDir = $BackupDir
    $Global:WsLastActionFiles = $Files
    $Global:WsLastActionTag = ""
    Write-WizardActionLog "WORKSPACE EXPLORER: $Desc"
}

# For commit-level actions ("Undo this commit (safe)" / git revert) -- undo
# is a plain `git reset --hard` to the tag New-SafetyBackup already made,
# which IS the correct and sufficient recovery for a commit-level change.
function Set-WsLastActionCommit {
    param([string]$Desc, [string]$Tag)
    $Global:WsLastActionKind = "commit"
    $Global:WsLastActionDesc = $Desc
    $Global:WsLastActionTag = $Tag
    $Global:WsLastActionBackupDir = ""
    $Global:WsLastActionFiles = @()
    Write-WizardActionLog "WORKSPACE EXPLORER: $Desc"
}

function Invoke-WsUndoLastAction {
    if (-not $Global:WsLastActionKind) {
        Write-Host "[i] Nothing to undo yet." -ForegroundColor Yellow
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
        return
    }
    if ($Global:WsLastActionKind -eq "files" -and -not (Test-Path -LiteralPath $Global:WsLastActionBackupDir)) {
        Write-Host "[!] Backup for the last action is missing - cannot undo." -ForegroundColor Red
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
        return
    }
    if ($Global:WsLastActionKind -eq "commit") {
        git rev-parse -q --verify $Global:WsLastActionTag 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] Backup tag for the last action is missing - cannot undo." -ForegroundColor Red
            Write-Host "Press any key to continue..." -NoNewline
            [void](Get-WsRawKey)
            Write-Host ""
            return
        }
    }
    if (Confirm-DestructiveAction "Undo: $($Global:WsLastActionDesc)") {
        New-SafetyBackup "pre-undo"
        if ($Global:WsLastActionKind -eq "commit") {
            Invoke-GitWizard reset --hard $Global:WsLastActionTag
        } else {
            foreach ($entry in $Global:WsLastActionFiles) {
                $parts = $entry -split '\|', 2
                $path = $parts[1]
                Restore-WsFileContent -Path $path -BackupDir $Global:WsLastActionBackupDir
            }
        }
        Write-WizardActionLog "UNDO: $($Global:WsLastActionDesc)"
        Write-Host "[+] Undone: $($Global:WsLastActionDesc)" -ForegroundColor Green
        $Global:WsLastActionKind = ""
        $Global:WsLastActionDesc = ""
        $Global:WsLastActionBackupDir = ""
        $Global:WsLastActionFiles = @()
        $Global:WsLastActionTag = ""
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
    }
}

# ------------------------------------------------------------------------------
# In-progress-operation detection, for the conflict screen's Abort action.
# ------------------------------------------------------------------------------
function Get-WsInProgressOperation {
    $gd = Get-WsGitDir
    if (-not $gd) { return "" }
    if (Test-Path -LiteralPath (Join-Path $gd "MERGE_HEAD")) { return "merge" }
    if (Test-Path -LiteralPath (Join-Path $gd "CHERRY_PICK_HEAD")) { return "cherry-pick" }
    if (Test-Path -LiteralPath (Join-Path $gd "REVERT_HEAD")) { return "revert" }
    if ((Test-Path -LiteralPath (Join-Path $gd "rebase-merge")) -or (Test-Path -LiteralPath (Join-Path $gd "rebase-apply"))) { return "rebase" }
    return ""
}

function Invoke-WsAbortInProgressOperation {
    $kind = Get-WsInProgressOperation
    switch ($kind) {
        "merge" { Invoke-GitWizard merge --abort; return $true }
        "cherry-pick" { Invoke-GitWizard cherry-pick --abort; return $true }
        "revert" { Invoke-GitWizard revert --abort; return $true }
        "rebase" { Invoke-GitWizard rebase --abort; return $true }
        default {
            Write-Host "[i] No merge, rebase, revert, or cherry-pick currently in progress." -ForegroundColor Yellow
            return $false
        }
    }
}

# ------------------------------------------------------------------------------
# Format-WsDiffWithDelta <rawDiff> -- pipes through delta as a FORMATTER only
# (--paging=never: the Explorer does its own scrolling via Show-WsScrollView,
# so delta must not hand off to its own pager), matching the Delta Diff
# Suite's "use delta when installed" convention. Falls back to the plain
# colored diff untouched.
# ------------------------------------------------------------------------------
function Format-WsDiffWithDelta {
    param([string]$RawDiff)
    if (Get-Command delta -ErrorAction SilentlyContinue) {
        return (($RawDiff | delta --paging=never 2>$null) -join "`n")
    }
    return $RawDiff
}

# ------------------------------------------------------------------------------
# Show-WsScrollView -- generic scrollable text viewer (diff / commit detail).
# Returns [PSCustomObject]@{ Result = "back"|"quit"|"key:<c>" }
# ------------------------------------------------------------------------------
function Show-WsScrollView {
    param(
        [string]$Content,
        [string[]]$Breadcrumb,
        [string]$ExtraBar = "",
        [string]$ExtraKeys = "",
        [string]$HelpText = "",
        [scriptblock]$RawKeyReader = { Get-WsRawKey }
    )
    $lines = $Content -split "`n"
    $total = $lines.Count
    $offset = 0

    while ($true) {
        $rows = 24
        try { $rows = $Host.UI.RawUI.WindowSize.Height } catch { }
        $visibleRows = $rows - 10
        if ($visibleRows -lt 3) { $visibleRows = 3 }

        if ($offset -gt ($total - $visibleRows)) { $offset = $total - $visibleRows }
        if ($offset -lt 0) { $offset = 0 }

        Show-WsHeader
        Write-WsBreadcrumb -Breadcrumb $Breadcrumb

        $shown = 0
        for ($i = $offset; $i -lt $total -and $shown -lt $visibleRows; $i++) {
            Write-Host $lines[$i]
            $shown++
        }
        if ($total -eq 0) { Write-Host "(empty)" -ForegroundColor Cyan }

        Write-Host ""
        if ($total -gt $visibleRows) {
            Write-Host "-- line $($offset + 1)-$($offset + $shown) of $total --" -ForegroundColor Cyan
        }

        $bar = "[Up/Down] Scroll  [Esc/Left] Back  [?] Help  [q] Quit"
        if ($ExtraBar) { $bar += "`n$ExtraBar" }
        Write-WsActionBar -Text $bar

        $raw = & $RawKeyReader
        $key = ConvertTo-WsNormalizedKey -RawKey $raw
        switch ($key) {
            "UP" {
                $offset--
                if ($offset -lt 0) { $offset = 0 }
            }
            "DOWN" {
                $offset++
            }
            "ESC" { return [PSCustomObject]@{ Result = "back" } }
            "LEFT" { return [PSCustomObject]@{ Result = "back" } }
            "Q" { return [PSCustomObject]@{ Result = "quit" } }
            "QMARK" {
                Show-WsHeader
                Write-Host "HELP`n" -ForegroundColor Yellow
                Write-Host $HelpText
                Write-Host ""
                Write-Host "Press any key to continue..." -NoNewline
                [void](& $RawKeyReader)
                Write-Host ""
            }
            default {
                if ($key.StartsWith("CHAR:")) {
                    $c = $key.Substring(5)
                    if ($c -and $ExtraKeys.Contains($c)) {
                        return [PSCustomObject]@{ Result = "key:$c" }
                    }
                }
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Format-WsStatusRow <entry> -- one display row for the Changes list.
# ------------------------------------------------------------------------------
function Format-WsStatusRow {
    param($Entry)
    $color = $Global:WsYellow
    $label = "modified "
    switch ($Entry.Badge) {
        "conflict"  { $color = $Global:WsRed;    $label = "CONFLICT" }
        "untracked" { $color = $Global:WsCyan;   $label = "untracked" }
        "renamed"   { $color = $Global:WsYellow; $label = "renamed  " }
        "added"     { $color = $Global:WsGreen;  $label = "added    " }
        "deleted"   { $color = $Global:WsRed;    $label = "deleted  " }
        "staged"    { $color = $Global:WsGreen;  $label = "staged   " }
    }
    if ($Entry.OrigPath) {
        return "$color$($Global:WsBold)[$label]$($Global:WsReset) $($Entry.OrigPath) $($Global:WsCyan)->$($Global:WsReset) $($Global:WsBold)$($Entry.Path)$($Global:WsReset)"
    }
    return "$color$($Global:WsBold)[$label]$($Global:WsReset) $($Global:WsBold)$($Entry.Path)$($Global:WsReset)"
}

$Global:WsChangesHelpText = @"
Up/Down - move    Enter or Right - open diff for the selected file
Esc or Left - leave the Workspace Explorer    Space - mark a file
/ - filter the list by typing part of a filename    q - quit the Explorer
R - revert ALL tracked changes to last commit (untracked files are never touched)
M - revert only the MARKED files to last commit
U - undo the last Explorer action (restores the files it changed)
H - this file's full commit history (File Timeline)
"@

# ------------------------------------------------------------------------------
# Show-WsChangesScreen -- Screen 1: the git-status view, and entry point for
# the whole Workspace Explorer.
# ------------------------------------------------------------------------------
function Show-WsChangesScreen {
    $navMarked = [System.Collections.Generic.List[int]]::new()
    while ($true) {
        $status = Get-WsStatus

        $items = @()
        foreach ($e in $status) { $items += (Format-WsStatusRow -Entry $e) }

        $undoHint = ""
        if ($Global:WsLastActionKind) {
            $undoHint = "  $($Global:WsCyan)[U]$($Global:WsReset) Undo: $($Global:WsLastActionDesc)"
        }
        $extraBar = "$($Global:WsCyan)[R]$($Global:WsReset) Revert all  $($Global:WsCyan)[M]$($Global:WsReset) Revert marked  $($Global:WsCyan)[H]$($Global:WsReset) File Timeline$undoHint"

        $result = Invoke-WsListNavigate -Items $items -Title "CHANGES  ($($status.Count) file(s))" `
            -Breadcrumb @("Changes") -Markable $true -Filterable $true `
            -HelpText $Global:WsChangesHelpText -ExtraBar $extraBar `
            -MarkedIndices $navMarked -ExtraKeys "RMUH"

        switch ($result.Result) {
            "open" {
                $sel = $status[$result.Selected]
                if ($sel.Badge -eq "conflict") {
                    $r = Show-WsConflictScreen -Path $sel.Path
                    if (-not $r) { return }
                } else {
                    $r = Show-WsFileDiffScreen -Path $sel.Path -Badge $sel.Badge
                    if (-not $r) { return }
                }
            }
            "key:R" {
                Invoke-WsChangesRevertAll -Status $status
            }
            "key:M" {
                Invoke-WsChangesRevertMarked -Status $status -Marked $navMarked
                $navMarked.Clear()
            }
            "key:U" {
                Invoke-WsUndoLastAction
            }
            "key:H" {
                if ($result.Selected -ge 0) {
                    $r = Show-WsFileTimelineScreen -Path $status[$result.Selected].Path
                    if (-not $r) { return }
                }
            }
            default {
                return
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Invoke-WsChangesRevertAll -- "R" on the Changes list. Tracked files only.
# ------------------------------------------------------------------------------
function Invoke-WsChangesRevertAll {
    param($Status)
    $targets = @($Status | Where-Object { $_.Badge -ne "untracked" })
    if ($targets.Count -eq 0) {
        Write-Host "[i] No tracked changes to revert." -ForegroundColor Yellow
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
        return
    }
    Show-WsHeader
    Write-WsBreadcrumb -Breadcrumb @("Changes")
    Write-Host "REVERT ALL TRACKED CHANGES ($($targets.Count) file(s))`n" -ForegroundColor Yellow
    foreach ($t in $targets) { Write-Host "  $(Format-WsStatusRow -Entry $t)" }
    Write-Host ""
    if (-not (Confirm-DestructiveAction "Revert $($targets.Count) tracked file(s) to their last commit - untracked files are left alone")) {
        return
    }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path (Get-WsGitDir) "wizard-backups/revert-all-$ts"
    New-SafetyBackup "pre-revert-all"

    $filesForJournal = @()
    foreach ($t in $targets) {
        $sanitized = Backup-WsFileContent -Path $t.Path -BackupDir $backupDir
        $filesForJournal += "$sanitized|$($t.Path)"
        Invoke-GitWizard restore --source=HEAD --staged --worktree "--" $t.Path
    }
    Set-WsLastActionFiles -Desc "Revert all ($($targets.Count) file(s)) to last commit" -BackupDir $backupDir -Files $filesForJournal
    Write-Host "[+] Reverted $($targets.Count) file(s)." -ForegroundColor Green
    Write-Host "Press any key to continue..." -NoNewline
    [void](Get-WsRawKey)
    Write-Host ""
}

# ------------------------------------------------------------------------------
# Invoke-WsChangesRevertMarked -- "M" on the Changes list.
# ------------------------------------------------------------------------------
function Invoke-WsChangesRevertMarked {
    param($Status, [System.Collections.Generic.List[int]]$Marked)
    if ($Marked.Count -eq 0) {
        Write-Host "[i] No files marked. Press Space on a file first." -ForegroundColor Yellow
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
        return
    }
    $targets = @()
    $skippedUntracked = @()
    foreach ($m in $Marked) {
        if ($Status[$m].Badge -eq "untracked") {
            $skippedUntracked += $Status[$m].Path
        } else {
            $targets += $Status[$m]
        }
    }

    Show-WsHeader
    Write-WsBreadcrumb -Breadcrumb @("Changes")
    Write-Host "REVERT MARKED FILES ($($targets.Count) file(s))`n" -ForegroundColor Yellow
    foreach ($t in $targets) { Write-Host "  $(Format-WsStatusRow -Entry $t)" }
    if ($skippedUntracked.Count -gt 0) {
        Write-Host "`n[i] Skipping untracked (no commit to revert to): $($skippedUntracked -join ', ')" -ForegroundColor Yellow
    }
    Write-Host ""
    if ($targets.Count -eq 0) {
        Write-Host "Nothing to revert." -ForegroundColor Yellow
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
        return
    }
    if (-not (Confirm-DestructiveAction "Revert $($targets.Count) marked file(s) to their last commit")) {
        return
    }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path (Get-WsGitDir) "wizard-backups/revert-marked-$ts"
    New-SafetyBackup "pre-revert-marked"

    $filesForJournal = @()
    foreach ($t in $targets) {
        $sanitized = Backup-WsFileContent -Path $t.Path -BackupDir $backupDir
        $filesForJournal += "$sanitized|$($t.Path)"
        Invoke-GitWizard restore --source=HEAD --staged --worktree "--" $t.Path
    }
    Set-WsLastActionFiles -Desc "Revert marked ($($targets.Count) file(s)) to last commit" -BackupDir $backupDir -Files $filesForJournal
    Write-Host "[+] Reverted $($targets.Count) marked file(s)." -ForegroundColor Green
    Write-Host "Press any key to continue..." -NoNewline
    [void](Get-WsRawKey)
    Write-Host ""
}

# ------------------------------------------------------------------------------
# Show-WsConflictScreen <path> -- raw conflicted file + Abort.
# Returns $false if the user quit the whole Explorer from here, $true otherwise.
# ------------------------------------------------------------------------------
function Show-WsConflictScreen {
    param([string]$Path)
    while ($true) {
        $content = "(file not present on disk)"
        if (Test-Path -LiteralPath $Path) { $content = Get-Content -LiteralPath $Path -Raw }
        $kind = Get-WsInProgressOperation
        $kindLabel = if ($kind) { $kind } else { "merge" }

        $scrollContent = "$($Global:WsRed)$($Global:WsBold)This file has unresolved merge conflict markers (<<<<<<<, =======, >>>>>>>).$($Global:WsReset)`n" +
            "$($Global:WsYellow)Resolve it in an editor, or abort the in-progress operation below.$($Global:WsReset)`n`n$content"

        $extraBar = "$($Global:WsRed)[A]$($Global:WsReset) Abort $kindLabel (discards ALL conflict-resolution progress)"
        $helpText = "Up/Down - scroll    Esc/Left - back to Changes    A - abort the in-progress $kindLabel"

        $result = Show-WsScrollView -Content $scrollContent -Breadcrumb @("Changes", "$Path (CONFLICT)") `
            -ExtraBar $extraBar -ExtraKeys "A" -HelpText $helpText

        switch ($result.Result) {
            "key:A" {
                Show-WsHeader
                Write-WsBreadcrumb -Breadcrumb @("Changes", "$Path (CONFLICT)")
                if (Confirm-DestructiveAction "Abort the in-progress $kindLabel - discards ALL conflict-resolution progress") {
                    New-SafetyBackup "pre-$kindLabel-abort"
                    # Checks actual state afterward rather than trusting
                    # Invoke-WsAbortInProgressOperation's return value: its
                    # last statement is a bare Invoke-GitWizard call, whose
                    # unsuppressed native-command output (git's own "Aborting"
                    # style messages) becomes part of the function's own
                    # return array, which -- just like the note on this same
                    # pattern in Invoke-WsPerformCommitRevertSafe -- is always
                    # truthy in an `if` regardless of its trailing boolean.
                    [void](Invoke-WsAbortInProgressOperation)
                    if (-not (Get-WsInProgressOperation)) {
                        Write-Host "[+] Aborted." -ForegroundColor Green
                        Write-Host "Press any key to continue..." -NoNewline
                        [void](Get-WsRawKey)
                        Write-Host ""
                        return $true
                    }
                    Write-Host "Press any key to continue..." -NoNewline
                    [void](Get-WsRawKey)
                    Write-Host ""
                }
            }
            "quit" { return $false }
            default { return $true }
        }
    }
}

# ------------------------------------------------------------------------------
# Show-WsFileDiffScreen <path> <badge> -- Screen 1's diff/detail view.
# Returns $false if the user quit the whole Explorer from here, $true otherwise.
# ------------------------------------------------------------------------------
function Show-WsFileDiffScreen {
    param([string]$Path, [string]$Badge)

    while ($true) {
        $status = Get-WsStatus
        $entry = $status | Where-Object { $_.Path -eq $Path } | Select-Object -First 1
        if (-not $entry) {
            Write-Host "[+] '$Path' no longer has pending changes." -ForegroundColor Green
            Write-Host "Press any key to continue..." -NoNewline
            [void](Get-WsRawKey)
            Write-Host ""
            return $true
        }
        $badge = $entry.Badge
        $y = $entry.Y

        $diffMode = ($y -ne " ")   # $true = unstaged-mode (also shows any staged part); $false = --staged only

        if (Test-WsIsBinaryFile -Path $Path) {
            $statOutput = (git diff --stat -- "$Path" 2>$null) -join "`n"
            $body = "$($Global:WsYellow)(binary file - showing size change only)$($Global:WsReset)`n`n$statOutput"
        } else {
            if ($diffMode) {
                $body = Get-WsFileDiff -Path $Path -StatusEntries $status
            } else {
                $body = Get-WsFileDiff -Path $Path -Staged -StatusEntries $status
            }
            $body = Format-WsDiffWithDelta -RawDiff $body
            if (-not $body) { $body = "$($Global:WsCyan)(no textual diff available)$($Global:WsReset)" }
        }

        $barParts = @()
        $extraKeys = "T"
        $hash2 = ""
        $hash3 = ""
        if ($badge -eq "untracked") {
            $barParts += "$($Global:WsRed)[D]$($Global:WsReset) Delete this untracked file (no backup tag possible - not a revert)"
            $extraKeys = "DT"
        } else {
            git cat-file -e "HEAD:$Path" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $barParts += "$($Global:WsCyan)[1]$($Global:WsReset) Revert to last commit"
                $extraKeys = "1T"
            }
            $hash2 = Get-WsHashBeforeLastChange -Path $Path
            if ($hash2) {
                $barParts += "$($Global:WsCyan)[2]$($Global:WsReset) Revert to version before last change"
                $extraKeys += "2"
            }
            $hash3 = Get-WsHashOriginalAdd -Path $Path
            if ($hash3 -and $hash3 -ne $hash2) {
                $barParts += "$($Global:WsCyan)[3]$($Global:WsReset) Revert to original state"
                $extraKeys += "3"
            }
        }
        $barParts += "$($Global:WsCyan)[T]$($Global:WsReset) File Timeline"
        $extraBar = $barParts -join "  "

        $helpExtra = if ($badge -eq "untracked") { "D - delete this untracked file" } else { "1/2/3 - revert to an earlier version of this file, as shown above" }
        $helpText = "Up/Down - scroll the diff    Esc/Left - back to Changes`nT - this file's full commit history (File Timeline)`n$helpExtra"

        $result = Show-WsScrollView -Content $body -Breadcrumb @("Changes", $Path) -ExtraBar $extraBar -ExtraKeys $extraKeys -HelpText $helpText

        switch ($result.Result) {
            "key:T" {
                if (Get-Command Show-WsFileTimelineScreen -ErrorAction SilentlyContinue) {
                    $r = Show-WsFileTimelineScreen -Path $Path
                    if (-not $r) { return $false }
                } else {
                    Write-Host "[i] File Timeline arrives in Stage 4." -ForegroundColor Yellow
                    Write-Host "Press any key to continue..." -NoNewline
                    [void](Get-WsRawKey)
                    Write-Host ""
                }
            }
            "key:D" {
                Show-WsHeader
                Write-WsBreadcrumb -Breadcrumb @("Changes", $Path)
                Write-Host "DELETE UNTRACKED FILE`n" -ForegroundColor Red
                Write-Host "'$Path' has never been committed - there is no version to fall back to." -ForegroundColor Red
                Write-Host "This cannot be undone through the Explorer's backup system.`n" -ForegroundColor Red
                if (Confirm-DestructiveAction "Permanently delete the untracked file '$Path'") {
                    Invoke-WsDeleteUntracked -Path $Path
                    Write-WizardActionLog "WORKSPACE EXPLORER: deleted untracked file $Path"
                    Write-Host "[+] Deleted." -ForegroundColor Green
                    Write-Host "Press any key to continue..." -NoNewline
                    [void](Get-WsRawKey)
                    Write-Host ""
                    return $true
                }
            }
            "key:1" {
                if (Invoke-WsPerformSingleRevert -Path $Path -Label "last commit" -RevertFunction "Invoke-WsRevertToLastCommit") { return $true }
            }
            "key:2" {
                if (Invoke-WsPerformSingleRevert -Path $Path -Label "version before last change" -RevertFunction "Invoke-WsRevertToBeforeLastChange") { return $true }
            }
            "key:3" {
                if (Invoke-WsPerformSingleRevert -Path $Path -Label "original state" -RevertFunction "Invoke-WsRevertToOriginalState") { return $true }
            }
            "quit" { return $false }
            default { return $true }
        }
    }
}

# ------------------------------------------------------------------------------
# Invoke-WsPerformSingleRevert <path> <label> <revert function name>
# Shared confirm + file-content-backup + journal wrapper for options 1/2/3.
# ------------------------------------------------------------------------------
function Invoke-WsPerformSingleRevert {
    param([string]$Path, [string]$Label, [string]$RevertFunction)

    Show-WsHeader
    Write-WsBreadcrumb -Breadcrumb @("Changes", $Path)
    Write-Host "REVERT TO: $Label`n" -ForegroundColor Yellow
    if (-not (Confirm-DestructiveAction "Revert '$Path' to its $Label")) {
        return $false
    }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path (Get-WsGitDir) "wizard-backups/revert-$ts"
    $sanitized = Backup-WsFileContent -Path $Path -BackupDir $backupDir

    $ok = & $RevertFunction -Path $Path
    if ($ok -eq $false) {
        Write-Host "[i] Nothing to revert to (no earlier version found)." -ForegroundColor Yellow
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
        return $false
    }

    Set-WsLastActionFiles -Desc "Revert '$Path' to $Label" -BackupDir $backupDir -Files @("$sanitized|$Path")
    Write-Host "[+] Reverted." -ForegroundColor Green
    Write-Host "Press any key to continue..." -NoNewline
    [void](Get-WsRawKey)
    Write-Host ""
    return $true
}

# ==============================================================================
# STAGE 4 OF 6: FILE TIMELINE -- all commits touching one file (git log
# --follow), paged ~50 at a time; a commit's change to that file; and the
# four commit actions (Apply / Restore file / Undo file change / Undo
# commit safely). Mirrors linux/workspace-explorer.sh's Stage 4
# function-for-function. Screen 5 (Project Timeline) reuses
# Invoke-WsCommitListScreen below, per the original spec's "reusing the
# same commit-detail code" instruction.
# ==============================================================================

function Format-WsCommitRow {
    param([string]$Hash, [string]$Author, [string]$Date, [string]$Subject)
    $h = $Hash.Substring(0, [Math]::Min(8, $Hash.Length))
    return "$($Global:WsCyan)$($Global:WsBold)$h$($Global:WsReset)  $($Global:WsGreen)$Author$($Global:WsReset)  $($Global:WsYellow)$Date$($Global:WsReset)  $Subject"
}

# ------------------------------------------------------------------------------
# Invoke-WsCommitListScreen -- generic paged commit browser shared by File
# Timeline and Project Timeline.
#
# PARAMETERS:
#   -FetchFn     scriptblock taking (limit, skip) that returns commit objects
#                (.Hash/.Author/.Date/.Subject -- see Get-WsFileLog/Get-WsProjectLog)
#   -CountFn     scriptblock taking no args that returns the total commit count
#   -Title       title text (page/total appended automatically)
#   -Breadcrumb  string[]
#   -PageSize    commits per page (default 50)
#
# RETURNS: [PSCustomObject]@{ Result = "open"|"back"|"quit"; Commit = <obj> }
# ------------------------------------------------------------------------------
function Invoke-WsCommitListScreen {
    param(
        # "file" fetches via Get-WsFileLog/-Count for $Path; "project" fetches
        # via Get-WsProjectLog/-Count. Deliberately NOT a pair of injected
        # scriptblocks (e.g. via .GetNewClosure()) -- a closure created inside
        # a function that was itself brought in by dot-sourcing can lose the
        # ability to resolve sibling functions (confirmed: calling such a
        # closure from here raised "the term '...' is not recognized") when
        # the whole chain is invoked across a script-file boundary, which is
        # exactly how the real tool's modules get loaded. A plain mode switch
        # has no such risk.
        [ValidateSet("file", "project")][string]$Mode,
        [string]$Path = "",
        [string]$Title,
        [string[]]$Breadcrumb,
        [int]$PageSize = 50
    )

    $page = 0
    while ($true) {
        if ($Mode -eq "file") {
            $total = Get-WsFileLogCount -Path $Path
        } else {
            $total = Get-WsProjectLogCount
        }
        if (-not $total) { $total = 0 }

        $totalPages = [Math]::Max(1, [Math]::Ceiling($total / [double]$PageSize))
        if ($page -ge $totalPages) { $page = $totalPages - 1 }
        if ($page -lt 0) { $page = 0 }
        $skip = $page * $PageSize

        if ($Mode -eq "file") {
            $commits = @(Get-WsFileLog -Path $Path -Limit $PageSize -Skip $skip)
        } else {
            $commits = @(Get-WsProjectLog -Limit $PageSize -Skip $skip)
        }
        $items = @()
        foreach ($c in $commits) { $items += (Format-WsCommitRow -Hash $c.Hash -Author $c.Author -Date $c.Date -Subject $c.Subject) }

        $helpText = "Up/Down - move    Enter/Right - view this commit    Esc/Left - back`n/ - filter by author/date/message    N - next page    P - previous page    q - quit the Explorer"

        $extraKeys = ""
        $barParts = @()
        if (($page + 1) -lt $totalPages) { $extraKeys += "N"; $barParts += "$($Global:WsCyan)[N]$($Global:WsReset) Next page" }
        if ($page -gt 0) { $extraKeys += "P"; $barParts += "$($Global:WsCyan)[P]$($Global:WsReset) Previous page" }
        $extraBar = $barParts -join "  "

        $result = Invoke-WsListNavigate -Items $items -Title "$Title  (page $($page + 1)/$totalPages, $total commit(s) total)" `
            -Breadcrumb $Breadcrumb -Markable $false -Filterable $true `
            -HelpText $helpText -ExtraBar $extraBar -ExtraKeys $extraKeys

        switch ($result.Result) {
            "open" {
                return [PSCustomObject]@{ Result = "open"; Commit = $commits[$result.Selected] }
            }
            "key:N" { $page++ }
            "key:P" { $page--; if ($page -lt 0) { $page = 0 } }
            default {
                return [PSCustomObject]@{ Result = $result.Result; Commit = $null }
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Invoke-WsPerformCommitFileAction <path> <hash> <label> <action fn name>
# Shared confirm + file-content-backup + journal wrapper for the File
# Timeline's Apply / Restore file / Undo file change actions.
# ------------------------------------------------------------------------------
function Invoke-WsPerformCommitFileAction {
    param([string]$Path, [string]$Hash, [string]$Label, [string]$ActionFunction)

    Show-WsHeader
    Write-WsBreadcrumb -Breadcrumb @("Changes", $Path)
    Write-Host "$Label`n" -ForegroundColor Yellow
    $shortHash = $Hash.Substring(0, [Math]::Min(8, $Hash.Length))
    if (-not (Confirm-DestructiveAction "${Label}: '$Path' at commit $shortHash")) {
        return $false
    }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path (Get-WsGitDir) "wizard-backups/commit-action-$ts"
    $sanitized = Backup-WsFileContent -Path $Path -BackupDir $backupDir

    $out = & $ActionFunction -Hash $Hash -Path $Path 2>&1
    $outText = ($out | Out-String)

    Set-WsLastActionFiles -Desc "${Label}: '$Path' at $shortHash" -BackupDir $backupDir -Files @("$sanitized|$Path")

    if ($outText -match '(?m)^<{7}|^CONFLICT|with conflicts') {
        Write-Host "[!] This didn't apply cleanly - '$Path' may now contain conflict markers." -ForegroundColor Red
        Write-Host "    Use [U] Undo last action on the Changes screen to put it back exactly as it was." -ForegroundColor Yellow
        if ($outText) { Write-Host "`n$outText" }
    } else {
        Write-Host "[+] Done." -ForegroundColor Green
    }
    Write-Host "Press any key to continue..." -NoNewline
    [void](Get-WsRawKey)
    Write-Host ""
    return $true
}

# ------------------------------------------------------------------------------
# Invoke-WsPerformCommitRevertSafe <hash> <subject>
# "Undo this commit (safe)" -- a COMMIT-level action, so New-SafetyBackup's
# tag IS the correct and sufficient undo mechanism. Detects and offers to
# abort a revert conflict the same way the Changes screen handles merges.
# ------------------------------------------------------------------------------
function Invoke-WsPerformCommitRevertSafe {
    param([string]$Hash, [string]$Subject)

    $shortHash = $Hash.Substring(0, [Math]::Min(8, $Hash.Length))
    Show-WsHeader
    Write-WsBreadcrumb -Breadcrumb @("Changes")
    Write-Host "UNDO THIS COMMIT (safe revert)`n" -ForegroundColor Yellow
    Write-Host "Commit $shortHash`: $Subject`n"
    if (-not (Confirm-DestructiveAction "Create a new commit that undoes $shortHash (`"$Subject`")")) {
        return
    }

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $tag = "backup/pre-revert-commit-$ts"
    $headExists = git rev-parse HEAD 2>$null
    if ($headExists -and -not $Global:DryRun) {
        git tag $tag HEAD 2>$null | Out-Null
    }
    New-SafetyBackup "pre-revert-commit"

    # Deliberately NOT "if (Invoke-WsRevertCommitSafe ...)": that function's
    # last statement is a bare `Invoke-GitWizard revert ...` call, and on a
    # conflict `git revert` prints several lines of hints to its own
    # output -- unsuppressed native-command output inside a PowerShell
    # function becomes part of that function's own return stream, so the
    # caller receives an ARRAY of [...hint text..., $false], and a non-empty
    # array is ALWAYS truthy in an `if` regardless of what its last element
    # is. Checking actual repository state instead (did HEAD move; is a
    # revert now mid-conflict) is unaffected by that pollution.
    $headBefore = git rev-parse HEAD 2>$null
    Invoke-WsRevertCommitSafe -Hash $Hash | Out-Null
    $kind = Get-WsInProgressOperation
    $headAfter = git rev-parse HEAD 2>$null

    if ($kind -eq "revert") {
        Write-Host "[!] The revert hit a conflict and is still in progress." -ForegroundColor Red
        Write-Host "    Conflicted file(s):" -ForegroundColor Yellow
        git diff --name-only --diff-filter=U 2>$null | ForEach-Object { Write-Host "      $_" }
        Write-Host ""
        Write-Host "  [A] Abort the revert (discards it, returns to the pre-revert state)" -ForegroundColor Red
        Write-Host "  [Esc] Leave it - resolve the conflict manually, then commit" -ForegroundColor Yellow
        $kchoice = Read-Host "Choice"
        if ($kchoice -eq "a" -or $kchoice -eq "A") {
            if (Confirm-DestructiveAction "Abort the in-progress revert") {
                Invoke-GitWizard revert --abort
                Write-Host "[+] Aborted." -ForegroundColor Green
            }
        }
    } elseif ($headAfter -and $headAfter -ne $headBefore) {
        Set-WsLastActionCommit -Desc "Undo commit $shortHash (`"$Subject`")" -Tag $tag
        Write-Host "[+] Commit undone with a new revert commit." -ForegroundColor Green
    } else {
        Write-Host "[!] Revert failed - the working tree may have uncommitted changes to a file this commit touched." -ForegroundColor Red
    }
    Write-Host "Press any key to continue..." -NoNewline
    [void](Get-WsRawKey)
    Write-Host ""
}

# ------------------------------------------------------------------------------
# Show-WsFileTimelineScreen <path> -- Screen 2: all commits touching this
# file. Returns $false if the user quit the whole Explorer from here.
# ------------------------------------------------------------------------------
function Show-WsFileTimelineScreen {
    param([string]$Path)

    while ($true) {
        $result = Invoke-WsCommitListScreen -Mode "file" -Path $Path `
            -Title "FILE TIMELINE" -Breadcrumb @("Changes", $Path, "History") -PageSize 50

        switch ($result.Result) {
            "open" {
                $r = Show-WsFileTimelineCommitScreen -Path $Path -Hash $result.Commit.Hash -Subject $result.Commit.Subject
                if (-not $r) { return $false }
            }
            "quit" { return $false }
            default { return $true }
        }
    }
}

# ------------------------------------------------------------------------------
# Show-WsFileTimelineCommitScreen <path> <hash> <subject> -- that commit's
# change to this one file, plus the four File Timeline actions.
# ------------------------------------------------------------------------------
function Show-WsFileTimelineCommitScreen {
    param([string]$Path, [string]$Hash, [string]$Subject)

    while ($true) {
        $shortHash = $Hash.Substring(0, [Math]::Min(8, $Hash.Length))

        if (Test-WsIsBinaryFile -Path $Path) {
            $body = "$($Global:WsYellow)(binary file at this commit - diff not shown)$($Global:WsReset)"
        } else {
            $body = Format-WsDiffWithDelta -RawDiff (Get-WsCommitFileDiff -Hash $Hash -Path $Path)
            if (-not $body) { $body = "$($Global:WsCyan)(no change to this file in this commit)$($Global:WsReset)" }
        }

        $extraBar = "$($Global:WsCyan)[A]$($Global:WsReset) Apply to current  $($Global:WsCyan)[F]$($Global:WsReset) Restore file to this commit  $($Global:WsCyan)[U]$($Global:WsReset) Undo only this file's change  $($Global:WsCyan)[C]$($Global:WsReset) Undo this commit (safe)"
        $helpText = @"
Up/Down - scroll    Esc/Left - back to this file's timeline
A - apply this historical change to your current file
F - restore the file to exactly how it looked at this commit
U - undo only this commit's change to this one file (reverse-apply)
C - undo the WHOLE commit safely (git revert -- affects every file it touched)
"@

        $result = Show-WsScrollView -Content $body -Breadcrumb @("Changes", $Path, "History", $shortHash) `
            -ExtraBar $extraBar -ExtraKeys "AFUC" -HelpText $helpText

        switch ($result.Result) {
            "key:A" {
                [void](Invoke-WsPerformCommitFileAction -Path $Path -Hash $Hash -Label "Apply this change to current version" -ActionFunction "Invoke-WsApplyCommitFileToCurrent")
            }
            "key:F" {
                [void](Invoke-WsPerformCommitFileAction -Path $Path -Hash $Hash -Label "Restore file to how it was at this commit" -ActionFunction "Invoke-WsRestoreFileToCommit")
            }
            "key:U" {
                [void](Invoke-WsPerformCommitFileAction -Path $Path -Hash $Hash -Label "Undo only this file's change in this commit" -ActionFunction "Invoke-WsUndoFileChangeInCommit")
            }
            "key:C" {
                Invoke-WsPerformCommitRevertSafe -Hash $Hash -Subject $Subject
                return $true
            }
            "quit" { return $false }
            default { return $true }
        }
    }
}

# ==============================================================================
# STAGE 5 OF 6: PROJECT TIMELINE -- all repo commits, paged ~50 at a time.
# Enter shows message/stats/files touched; Enter on a file reuses
# Show-WsFileTimelineCommitScreen from Stage 4 verbatim (same actions, same
# code), per the original spec's "Same actions as the File Timeline, reusing
# the same commit-detail code" instruction. Mirrors
# linux/workspace-explorer.sh's Stage 5 function-for-function.
# ==============================================================================

# ------------------------------------------------------------------------------
# Show-WsProjectTimelineScreen -- Screen 3: all repo commits.
# Returns $false if the user quit the whole Explorer from here.
# ------------------------------------------------------------------------------
function Show-WsProjectTimelineScreen {
    while ($true) {
        $result = Invoke-WsCommitListScreen -Mode "project" `
            -Title "PROJECT TIMELINE" -Breadcrumb @("Project Timeline") -PageSize 50

        switch ($result.Result) {
            "open" {
                $r = Show-WsProjectCommitDetailScreen -Hash $result.Commit.Hash -Subject $result.Commit.Subject
                if (-not $r) { return $false }
            }
            "quit" { return $false }
            default { return $true }
        }
    }
}

# ------------------------------------------------------------------------------
# Show-WsProjectCommitDetailScreen <hash> <subject> -- message, stats, and
# the list of files this commit touched; Enter on a file reuses
# Show-WsFileTimelineCommitScreen (Stage 4) for that file's change in this
# commit, with the same Apply/Restore/Undo-file/Undo-commit actions.
# ------------------------------------------------------------------------------
function Show-WsProjectCommitDetailScreen {
    param([string]$Hash, [string]$Subject)

    while ($true) {
        $files = @(Get-WsCommitFiles -Hash $Hash)
        $items = @()
        foreach ($f in $files) { $items += "$($Global:WsCyan)$f$($Global:WsReset)" }

        $summary = Get-WsCommitSummary -Hash $Hash
        $title = "$summary`n`n$($Global:WsYellow)$($Global:WsBold)FILES TOUCHED ($($files.Count))$($Global:WsReset)"
        $helpText = "Up/Down - move    Enter/Right - view this file's change in this commit`nEsc/Left - back to Project Timeline    / - filter by filename    q - quit the Explorer"

        $result = Invoke-WsListNavigate -Items $items -Title $title -Breadcrumb @("Project Timeline", $Hash.Substring(0, [Math]::Min(8, $Hash.Length))) `
            -Markable $false -Filterable $true -HelpText $helpText -ExtraBar "" -ExtraKeys ""

        switch ($result.Result) {
            "open" {
                $r = Show-WsFileTimelineCommitScreen -Path $files[$result.Selected] -Hash $Hash -Subject $Subject
                if (-not $r) { return $false }
            }
            "quit" { return $false }
            default { return $true }
        }
    }
}

# ==============================================================================
# STAGE 6 OF 6: TOP-LEVEL ENTRY SCREEN -- the home screen the Module 2 menu
# entry opens. Changes, File Timeline (via a file you pick here), and
# Project Timeline are all reachable from it. Mirrors
# linux/workspace-explorer.sh's Stage 6 function-for-function -- see that
# file's header comment on this screen for why "quit" inside a sub-screen
# just returns here rather than exiting the whole tool.
# ==============================================================================
function Show-WsFileTimelineManualPathScreen {
    Show-WsHeader
    Write-WsBreadcrumb -Breadcrumb @("Workspace Explorer", "File Timeline")
    Write-Host "FILE TIMELINE - TYPE A PATH`n" -ForegroundColor Yellow
    Write-Host "Enter the path to a tracked file (relative to the repo root)." -ForegroundColor Cyan
    $filepath = Read-Host "File path (ENTER with nothing to cancel)"
    if (-not $filepath) { return }

    git ls-files --error-unmatch -- $filepath 2>$null | Out-Null
    $tracked = ($LASTEXITCODE -eq 0)
    if (-not $tracked -and -not (Test-Path -LiteralPath $filepath)) {
        Write-Host "[!] '$filepath' doesn't exist and isn't tracked by git." -ForegroundColor Red
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
        return
    }
    [void](Show-WsFileTimelineScreen -Path $filepath)
}

# ------------------------------------------------------------------------------
# Get-WsTrackedFiles -- NUL-safe list of every tracked file, relative to the
# repo root, regardless of the caller's current directory. A .NET string can
# hold embedded NUL characters without truncation (unlike a Bash variable),
# so capturing `git ls-files -z`'s whole output and splitting on "`0" is
# safe here -- this is the same technique Get-WsStatus already uses for
# `git status --porcelain -z`.
# ------------------------------------------------------------------------------
function Get-WsTrackedFiles {
    $rawLines = & git ls-files -z 2>$null
    if (-not $rawLines) { return @() }
    $raw = ($rawLines -join "")
    $result = @()
    foreach ($f in $raw.Split([char]0)) {
        if ($f) { $result += $f }
    }
    return $result
}

# ------------------------------------------------------------------------------
# Get-WsDeletedFiles -Tracked <array> -- paths deleted at some point in
# history that are NOT currently tracked (a file deleted and later re-added
# is correctly excluded -- it belongs in the tracked list instead).
# ------------------------------------------------------------------------------
function Get-WsDeletedFiles {
    param([string[]]$Tracked)
    $trackedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$Tracked)
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $result = @()
    $lines = git log --diff-filter=D --name-only --format="" 2>$null
    foreach ($f in $lines) {
        if (-not $f) { continue }
        if ($trackedSet.Contains($f)) { continue }
        if ($seen.Contains($f)) { continue }
        [void]$seen.Add($f)
        $result += $f
    }
    return $result
}

# ------------------------------------------------------------------------------
# Format-WsPickerRow -Path <path> -Badge <already-colored-or-empty>
# Truncates very long paths in the middle (keeping the start -- usually the
# most identifying directory -- and the end, usually the filename) so one
# absurdly long path can't push the badge off the end of the console.
# ------------------------------------------------------------------------------
function Format-WsPickerRow {
    param([string]$Path, [string]$Badge)
    $display = $Path
    $maxlen = 70
    if ($Path.Length -gt $maxlen) {
        $keep = [Math]::Floor(($maxlen - 1) / 2)
        $display = $Path.Substring(0, $keep) + [char]0x2026 + $Path.Substring($Path.Length - $keep)
    }
    return "$display$Badge"
}

$Global:WsFilePickerHelpText = @"
Up/Down - move    Enter/Right - open this file's History
Esc/Left - back    / - filter by typing part of a path (case-insensitive)
PgUp/PgDn/Home/End - scroll a long list    q - quit the Explorer
H - toggle showing files that were deleted but still have history
Badges: [M]=modified [A]=added [D]=deleted [R]=renamed [!]=conflict (current
working tree); [deleted] = no longer tracked, shown only when toggled on.
"@

# ------------------------------------------------------------------------------
# Show-WsFilePickerScreen -- interactive file picker for File Timeline.
# Loads the tracked-file list ONCE per visit (cheap to re-filter afterward,
# but `git ls-files`/`git log --diff-filter=D` over a huge repo is not
# something to redo on every keystroke), runs from the repo root so the
# whole repository is visible regardless of the caller's directory, and
# returns to itself (cursor and filter preserved) after a round trip into a
# file's History. Returns $false if the user quit the whole Explorer here.
# ------------------------------------------------------------------------------
function Show-WsFilePickerScreen {
    $repoRoot = (git rev-parse --show-toplevel 2>$null)
    if (-not $repoRoot) {
        Show-WsHeader
        Write-WsBreadcrumb -Breadcrumb @("Workspace Explorer", "File Timeline", "Browse")
        Write-Host "[!] Not a git repository - nothing to browse." -ForegroundColor Red
        Write-Host "Press any key to continue..." -NoNewline
        [void](Get-WsRawKey)
        Write-Host ""
        return $true
    }

    $origDir = (Get-Location).Path
    Set-Location $repoRoot
    $tracked = @(Get-WsTrackedFiles)

    $showDeleted = $false
    $lastSelectedPath = ""
    $lastFilter = ""

    try {
        while ($true) {
            if ($showDeleted) {
                $deleted = @(Get-WsDeletedFiles -Tracked $tracked)
            } else {
                $deleted = @()
            }
            $status = Get-WsStatus

            if ($tracked.Count -eq 0 -and $deleted.Count -eq 0) {
                Show-WsHeader
                Write-WsBreadcrumb -Breadcrumb @("Workspace Explorer", "File Timeline", "Browse")
                Write-Host "This repository has no tracked files yet - nothing to browse." -ForegroundColor Cyan
                Write-Host "Press any key to continue..." -NoNewline
                [void](Get-WsRawKey)
                Write-Host ""
                return $true
            }

            $paths = @()
            $items = @()
            $initialCursor = -1
            $idx = 0
            $deletedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$deleted)
            foreach ($p in ($tracked + $deleted)) {
                $paths += $p
                $badge = ""
                $entry = $status | Where-Object { $_.Path -eq $p } | Select-Object -First 1
                if ($entry) {
                    switch ($entry.Badge) {
                        "modified" { $badge = "  $($Global:WsYellow)[M]$($Global:WsReset)" }
                        "staged"   { $badge = "  $($Global:WsGreen)[M]$($Global:WsReset)" }
                        "added"    { $badge = "  $($Global:WsGreen)[A]$($Global:WsReset)" }
                        "deleted"  { $badge = "  $($Global:WsRed)[D]$($Global:WsReset)" }
                        "renamed"  { $badge = "  $($Global:WsYellow)[R]$($Global:WsReset)" }
                        "conflict" { $badge = "  $($Global:WsRed)[!]$($Global:WsReset)" }
                    }
                }
                if (-not $badge -and $deletedSet.Contains($p)) {
                    $badge = "  $($Global:WsRed)[deleted]$($Global:WsReset)"
                }
                $items += (Format-WsPickerRow -Path $p -Badge $badge)
                if ($p -eq $lastSelectedPath) { $initialCursor = $idx }
                $idx++
            }

            $hLabel = if ($showDeleted) { "Hide" } else { "Show" }
            $extraBar = "$($Global:WsCyan)[H]$($Global:WsReset) $hLabel deleted files"

            $result = Invoke-WsListNavigate -Items $items -Title "BROWSE FILES" `
                -Breadcrumb @("Workspace Explorer", "File Timeline", "Browse") `
                -Markable $false -Filterable $true -HelpText $Global:WsFilePickerHelpText `
                -ExtraBar $extraBar -ExtraKeys "H" -MarkedIndices ([System.Collections.Generic.List[int]]::new()) `
                -Viewport $true -InitialCursor $initialCursor -InitialFilter $lastFilter -ItemNoun "files"
            $lastFilter = $result.LastFilter

            switch ($result.Result) {
                "open" {
                    $lastSelectedPath = $paths[$result.Selected]
                    $r = Show-WsFileTimelineScreen -Path $paths[$result.Selected]
                    Set-Location $repoRoot
                    if (-not $r) { return $false }
                }
                "key:H" {
                    $showDeleted = -not $showDeleted
                    if ($result.Selected -ge 0) { $lastSelectedPath = $paths[$result.Selected] }
                }
                "quit" {
                    return $false
                }
                default {
                    return $true
                }
            }
        }
    } finally {
        Set-Location $origDir
    }
}

# ------------------------------------------------------------------------------
# Show-WsFileTimelineChooser -- shown when "File Timeline" is opened from the
# Explorer's top-level menu: browse interactively (the file picker above) or
# type a path manually (the pre-existing behavior, unchanged). Uses the same
# list navigator as everything else in the Explorer, so Esc/Left/q all back
# out exactly like every other screen.
# ------------------------------------------------------------------------------
function Show-WsFileTimelineChooser {
    $items = @(
        "$($Global:WsGreen)$($Global:WsBold)Browse files interactively$($Global:WsReset)  $($Global:WsCyan)(recommended)$($Global:WsReset)",
        "$($Global:WsGreen)$($Global:WsBold)Type a file path manually$($Global:WsReset)"
    )
    $helpText = "Up/Down - move    Enter/Right - open    Esc/Left or q - back"

    $result = Invoke-WsListNavigate -Items $items -Title "FILE TIMELINE" `
        -Breadcrumb @("Workspace Explorer", "File Timeline") `
        -Markable $false -Filterable $false -HelpText $helpText -ExtraBar "" -ExtraKeys ""

    if ($result.Result -eq "open") {
        switch ($result.Selected) {
            0 { [void](Show-WsFilePickerScreen) }
            1 { Show-WsFileTimelineManualPathScreen }
        }
    }
}

function Show-WsWorkspaceExplorer {
    while ($true) {
        $items = @(
            "$($Global:WsGreen)$($Global:WsBold)Changes$($Global:WsReset)  $($Global:WsCyan)- status, diff, revert$($Global:WsReset)",
            "$($Global:WsGreen)$($Global:WsBold)File Timeline$($Global:WsReset)  $($Global:WsCyan)- full history of one file$($Global:WsReset)",
            "$($Global:WsGreen)$($Global:WsBold)Project Timeline$($Global:WsReset)  $($Global:WsCyan)- every commit in this repo$($Global:WsReset)"
        )
        $helpText = "Up/Down - move    Enter/Right - open    Esc/Left or q - leave the Workspace Explorer"

        $result = Invoke-WsListNavigate -Items $items -Title "WORKSPACE EXPLORER" -Breadcrumb @("Workspace Explorer") `
            -Markable $false -Filterable $false -HelpText $helpText -ExtraBar "" -ExtraKeys ""

        switch ($result.Result) {
            "open" {
                switch ($result.Selected) {
                    0 { [void](Show-WsChangesScreen) }
                    1 { Show-WsFileTimelineChooser }
                    2 { [void](Show-WsProjectTimelineScreen) }
                }
            }
            default {
                return
            }
        }
    }
}
