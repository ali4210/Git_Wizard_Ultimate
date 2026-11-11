# Git-Wizard Ultimate — Full Production-Readiness Audit

Audit branch: `audit/full-review` (created from `main` @ `ffa8505`). Read-only phase — no code was changed while producing this report. Every finding below was either read directly in the source, or additionally reproduced in a throwaway repo under `/tmp` (never against real system state, real GitHub/GitLab accounts, or this project's own working tree). Anything that could not be independently verified is explicitly marked **UNVERIFIED**.

## Executive summary

Git-Wizard Ultimate is a mature, large (~14,000 lines across a Bash engine and a 10-module PowerShell port), carefully-built tool with a real safety philosophy (backup tags, confirmation prompts, an action log, dry-run mode) that is **mostly, but not uniformly, applied**. The two most serious problems found are:

1. **The tool's central safety promise has a hole in both engines.** `New-SafetyBackup`/`create_safety_backup` only tags the current *commit* — it does nothing for uncommitted or untracked files. Two Windows flows (Discard, Force Sync) and one Linux flow (Force Sync) run a hard reset + `clean -fd` right after taking that commit-only backup, while telling the user their changes are protected. They are not. This is reproducible, permanent data loss with a misleading on-screen recovery instruction. (Finding **D4**, Critical.)
2. **PowerShell's shared git-invocation helper can silently convert failures into reported successes.** `Invoke-GitWizard`'s bare, unsuppressed `& git @GitArgs` call means that whenever the underlying git subcommand writes to stdout on failure (merge conflicts, rebase conflicts, "nothing to commit"), PowerShell's array-truthiness rules make `if (Invoke-GitWizard ...)` report success anyway. This is the exact bug class the project already found and fixed once, locally, inside `workspace-engine.ps1` during earlier development — but the fix was never applied to the shared primitive, so it is still live at 19+ call sites across 5 files. (Finding **PS1-3**, Critical.)

Beyond these two, the audit found a plaintext-secrets issue (GitHub PATs stored unencrypted despite a "LOCKED"/"securely saved" UI), one real elevated-code-execution path via unescaped string interpolation, a handful of genuine logic bugs (an SSH-key picker that goes out of bounds, a rollback that can reset the wrong branch, an installer that can die silently and invisibly), five dead functions, a license that's claimed in the README but doesn't exist in the repo, one real cross-platform menu-numbering divergence, and zero automated test coverage anywhere in the project. No category produced an overwhelming number of findings — the codebase is not sloppy — but the few Critical/High items are the kind that matter precisely because this tool's whole pitch is "destructive git operations, but safely."

### Findings by severity

| Severity | Count |
|---|---|
| Critical | 3 |
| High | 8 |
| Medium | 10 |
| Low | 12 |
| **Total** | **33** |

(Plus one informational, non-defect note — DOC-5 — and a grouped static-analysis style-debt summary that is intentionally not broken into individual findings, per the instruction not to pad this report with style nitpicks.)

### Top 10 fixes (highest impact first)

1. **D4** — Safety-backup tag doesn't protect uncommitted/untracked work before Discard/Force-Sync (both engines) — permanent, misleadingly-"safe" data loss.
2. **PS1-3** — `Invoke-GitWizard`'s stdout-swallows-into-return-array bug reports merge/rebase/commit failures as success at 19+ sites — one-line root-cause fix.
3. **D5** — PAT vault stores GitHub tokens in plaintext on both platforms; the "LOCKED"/"securely saved" UI claims are false on both.
4. **PS1-9** — Unescaped path interpolation into an elevated (UAC) helper script is a real code-injection path.
5. **MAIN-6** — `install.sh`'s `set -e` plus an unguarded `sudo ln -sf` can kill the entire installer with zero error message.
6. **PS1-6** — Rollback-force-pull resets whatever branch happens to be checked out if the intended branch's checkout fails.
7. **PS1-1** — Craft-Commit prints "commit created!" even when nothing was committed.
8. **PS1-4** — "Merge into main" in the Team Mode admin dashboard is the one destructive action that skips `Confirm-DestructiveAction`.
9. **D3** — README asserts an MIT `LICENSE` file exists; it does not, and the README's own Roadmap admits it.
10. **D1** — SSH-key delete picker's arrow-navigation has a missing `$` (`-ge count` vs `-ge $count`) that lets selection run out of bounds; shellcheck independently flags this exact line as a hard error (`SC2170`).

---

## 1. Broken / dead code

### BASH-1 — Dead function `detect_binary_arch`
- **Severity:** Low
- **Location:** `linux/git-wizard.sh:560`
- **What's wrong:** Defined, never called anywhere. `install_from_binary()` (the function that needs arch detection) computes `gnu_target`/`gh_arch`/`x86_arch` inline instead (lines ~655-676) — this is leftover code from before that refactor.
- **Why it matters:** Dead code adds maintenance burden and can mislead a future reader into thinking it's the live path.
- **Verification:** `grep -n "detect_binary_arch" linux/git-wizard.sh` returns only the definition line.
- **Proposed fix:** Delete the function (~lines 560-578).
- **Effort:** small

### BASH-2 — Dead function `vcs_list_repos`
- **Severity:** Low
- **Location:** `linux/git-wizard.sh:4090`
- **What's wrong:** Superseded by `vcs_list_my_repos()` (line 4293), which is the one actually wired into menu dispatch (lines 4464, 4958). Zero callers of the old one.
- **Verification:** `grep -n "vcs_list_repos\b"` returns only the definition.
- **Proposed fix:** Delete the function.
- **Effort:** small

### BASH-3 — Dead function `vcs_version`
- **Severity:** Low
- **Location:** `linux/git-wizard.sh:4157`
- **What's wrong:** No call sites; `check_tool_stack_versions`/`_tool_installed_version` (lines 5452/5506) does version lookups independently.
- **Verification:** `grep -n "vcs_version\b"` returns only the definition.
- **Proposed fix:** Delete the function.
- **Effort:** small

### BASH-4 — Dead function `print_repo_table`
- **Severity:** Low
- **Location:** `linux/git-wizard.sh:4231`
- **What's wrong:** Superseded by `render_repo_table()` (line 4265), which is what's actually piped into (lines 4307, 4313).
- **Verification:** `grep -n "print_repo_table\b"` returns only the definition.
- **Proposed fix:** Delete the function.
- **Effort:** small

### BASH-5 — Dead function `vcs_repo_list_rich`
- **Severity:** Low
- **Location:** `linux/git-wizard.sh:4243`
- **What's wrong:** Superseded by `vcs_repo_list_full()` (line 4184), called at line 4378 feeding `render_repo_table`. Together with BASH-4, this is the second pair of functions from an older "rich table" pass that was replaced but never deleted.
- **Verification:** `grep -n "vcs_repo_list_rich\b"` returns only the definition.
- **Proposed fix:** Delete the function.
- **Effort:** small

### PS1-2 — Three dead `elseif` fallback branches in the main menu dispatch
- **Severity:** Low
- **Location:** `modules/git-wizard.ps1:1015, 1020, 1030`
- **What's wrong:** Main-menu dispatch for options 1/2/4 checks `Get-Command Manage-Identity`/`Manage-Repo`/`Craft-Commit` first, then falls back via `elseif` to `Manage-GitIdentity`/`Manage-GitRepo`/`Craft-ConventionalCommit`. None of those three fallback names are defined anywhere in `modules/*.ps1` (confirmed by grep). Option 3's fallback, `Manage-GitBranches`, does exist (`branch-engine.ps1:132`) but is a 1-line alias in the same file as its primary — so if the module fails to load, neither name is available anyway, making even that fallback unreachable in practice.
- **Why it matters:** Not functionally broken (the primary path always works when the module loads), but it misrepresents what happens on a load failure — the real-world outcome is always the final `else`'s "module function missing" message.
- **Verification:** `grep -rn 'function Manage-GitIdentity\|function Manage-GitRepo\|function Craft-ConventionalCommit' modules/*.ps1` → zero matches.
- **Proposed fix:** Remove the three dead `elseif` branches (and optionally the harmless `Manage-GitBranches` alias), keeping just `if (Get-Command X) { X } else { <missing message> }` for all four dispatch entries.
- **Effort:** small

---

## 2. Incomplete work

### PS1-7 — Rename-repo logs a false "renamed" action for GitLab (and for GitHub regardless of success)
- **Severity:** Medium
- **Location:** `modules/vcs-engine.ps1:189-196` (`Vcs-RenameRepo`) and `:503-509` (menu option "5" in `Show-VcsRepoAdminMenu`)
- **What's wrong:** For GitLab, `Vcs-RenameRepo` makes no API call at all — it only tells the user renaming must be done via the GitLab web UI (since `glab` has no rename subcommand). The caller never checks what happened; it unconditionally runs `Write-WizardActionLog "Renamed repo to $n"` right after calling it. For GitLab this logs a rename that never occurred. On the GitHub branch (`gh repo rename $newname`), the exit code is also never checked, so the same false log line is written even when the rename fails (name taken, no permission, not authenticated).
- **Why it matters:** The action log exists specifically as an audit trail of what git-wizard actually did. This writes a provably false entry for every GitLab user of this feature, and a false entry for GitHub users whenever the rename fails.
- **Verification:** Read `modules/vcs-engine.ps1` in full; traced the call path from menu choice "5" through both provider branches of `Vcs-RenameRepo`; confirmed neither branch's result is checked before the unconditional log write.
- **Proposed fix:** Have `Vcs-RenameRepo` return a boolean (`$false` for the GitLab no-op branch, `$LASTEXITCODE -eq 0` for the GitHub branch), and only call `Write-WizardActionLog` at the call site when it returns `$true`.
- **Effort:** small

*(DOC-5, listed in the Documentation section below, is a related but non-defect note: self-update is fully implemented on both platforms but currently has nothing to update to, since no GitHub Release has ever been tagged. The README's own Roadmap already discloses this, so it is not treated as a finding here.)*

---

## 3. Bugs and logic errors

### D1 — SSH-key delete picker's arrow navigation goes out of bounds (missing `$` on a variable) *(merges MAIN-1 + BASH-9)*
- **Severity:** Medium
- **Location:** `linux/git-wizard.sh:2078`, inside `manage_github_ssh_keys()`'s `_arrow_select_key()`
- **What's wrong:** `[ $selected -ge count ] && selected=0` is missing the `$` before `count` — it compares `$selected` against the literal string `"count"`, not the variable's value.
- **Why it matters:** `[ N -ge count ]` makes bash's `[` fail with `[: count: integer expected` (printed to the screen during navigation), so the wrap-to-0 never fires. Pressing Down past the last SSH key leaves `$selected` pointing past the end of the `ids`/`titles`/`fps` arrays. Pressing Enter then calls `_arrow_confirm_delete` with all three arguments empty; if the user confirms "Yes" anyway, it calls `gh api -X DELETE "/user/keys/"` with an empty ID. Independently confirmed: **shellcheck flags this exact line as a hard error**, `SC2170 (error): Invalid number for -ge`.
- **Verification:** Reproduced directly: `bash -c 'count=3; selected=2; ((selected++)); [ $selected -ge count ] && selected=0; echo $selected'` prints the bash error and leaves `selected=3` (out of bounds for indices 0-2); the corrected form wraps to 0 as intended. The downstream `gh api -X DELETE "/user/keys/"` (empty ID) behavior was traced but not live-fired against a real GitHub session — **UNVERIFIED** whether GitHub's API rejects it cleanly or does something unexpected; recommend a defensive `[[ -z "$id" ]] && return 1` guard regardless.
- **Proposed fix:** Change line 2078 to `'[B') ((selected++)); [ $selected -ge $count ] && selected=0 ;;` (add the missing `$`). Optionally also add `[[ -z "$id" ]] && { echo "[!] No key selected."; return 1; }` in `_arrow_confirm_delete` as a belt-and-suspenders check.
- **Effort:** small

### BASH-7 — `clean_remote_url` silently returns an empty string for a URL containing a quote character
- **Severity:** Medium
- **Location:** `linux/git-wizard.sh:1368-1372`
- **What's wrong:** The function trims the pasted URL via `... | xargs`. `xargs` with no command argument interprets shell-style quoting in its input by default, so a URL/path containing an unmatched quote (e.g. a self-hosted GitLab group name with an apostrophe) makes `xargs` fail with "unmatched quote" and the function returns an empty string.
- **Why it matters:** Every caller (one-click repo setup's manual-URL fallback, the Remote URL Manager) treats an empty result as "no URL entered" and may skip setting the remote or set an empty origin — a confusing silent failure, with the real `xargs` error going to uncolored stderr that's easy to miss in the tool's styled UI.
- **Verification:** `echo "https://github.com/user/repo's-weird-name.git" | sed -E 's/^git remote (add|set-url) origin //I' | xargs` reproduces the exact `xargs: unmatched single quote` error and empty result.
- **Proposed fix:**
  ```bash
  clean_remote_url() {
      local input_url="$1"
      input_url=$(echo "$input_url" | sed -E 's/^git remote (add|set-url) origin //I')
      input_url="${input_url#"${input_url%%[![:space:]]*}"}"
      input_url="${input_url%"${input_url##*[![:space:]]}"}"
      echo "$input_url"
  }
  ```
- **Effort:** small

### PS1-1 — Craft-Commit always claims success even when no commit was created
- **Severity:** High
- **Location:** `modules/commit-engine.ps1:44-46`
- **What's wrong:** `Invoke-GitWizard add . | Out-Null` and `Invoke-GitWizard commit -m "$finalMsg" | Out-Null` both discard their return value. The next line unconditionally prints `[+] Conventional commit created!`.
- **Why it matters:** Any commit failure — clean tree ("nothing to commit"), a pre-commit hook rejecting the commit, a conflict in progress, no staged changes — is completely silent. The user sees success and believes their change is saved when it isn't.
- **Verification:** Ran via `pwsh` against a throwaway `/tmp` repo with a clean working tree. Output printed "[+] Conventional commit created!" but `git log --oneline` showed no new commit.
- **Proposed fix:** Route through the existing `Invoke-CommitWithHookRetry -Message $finalMsg` helper (already used elsewhere, e.g. repo-engine.ps1's Quick Push) and only print success if it returns `$true`. Bash's `commit_assistant()` should be checked for the same parity gap.
- **Effort:** small — but re-verify alongside **PS1-3** below, since fixing the root cause there may change what this function observes.

### PS1-3 — `Invoke-GitWizard`'s return value is unreliable whenever git writes to stdout — masks merge/rebase/commit failures as success at 19+ call sites
- **Severity:** Critical
- **Location:** Root cause at `modules/git-wizard.ps1:237-249`. Affected call sites: `modules/team-engine.ps1:86,100,128,146,172,173,174,232,252,257,260,354`; `modules/repo-engine.ps1:49,228,318,512`; `modules/branch-engine.ps1:86,88`; and `Invoke-CommitWithHookRetry` (`git-wizard.ps1:265`, itself used from repo-engine.ps1, conflict-engine.ps1, and elsewhere).
- **What's wrong:** The non-dry-run branch of `Invoke-GitWizard` is a bare, unsuppressed `& git @GitArgs` followed by `return ($LASTEXITCODE -eq 0)`. When a caller uses the result directly in a boolean context (`if (Invoke-GitWizard ...)` or `if (-not (Invoke-GitWizard ...))` — both patterns are used) and the underlying `git` subcommand writes anything to **stdout** on the failing path, PowerShell bundles that stdout text with the trailing boolean into one array. A non-empty array is always truthy in `if`, and `-not` on it is `$false` — so both patterns end up on the "success" branch regardless of the real exit code.
- **Why it matters (concrete, verified scenarios):**
  - `git merge` writes its conflict text to **stdout** even on failure. `Invoke-TeamModeAdminDashboard`'s "Merge into main" (`team-engine.ps1:173`) does `if (Invoke-GitWizard merge --no-ff ...)`: a real conflict is reported as "[+] Merged and pushed." while the repo is left mid-conflict.
  - `git pull --rebase` also writes conflict text to stdout on failure. `Invoke-LinearWorkflow` (`team-engine.ps1:86`) and `Invoke-SafeUpdateSync` (`team-engine.ps1:354`) use `if (-not (Invoke-GitWizard pull ... --rebase))`: a rebase conflict is silently treated as success, and execution proceeds to push/stash-pop on top of a repo stuck mid-rebase.
  - `git commit` writes "nothing to commit, working tree clean" to stdout on failure (exit 1). `Invoke-CommitWithHookRetry` (the shared helper used by Quick Push, Smart Force Push, etc.) checks `if (Invoke-GitWizard commit -m "$Message")` first — a no-op commit is reported as immediate success (same underlying mechanism as **PS1-1**, but hit through the shared helper this time).
  - By contrast, `git push` (remote errors) and `git checkout -b` write to **stderr**, so those specific call sites are *not* affected by this mechanism — but every stdout-producing git subcommand reached through `Invoke-GitWizard` in a direct boolean context is at risk, and not every one of the 19+ sites was individually re-verified stream-by-stream.
- **Verification:** Reproduced with `pwsh` against real throwaway `/tmp` repos: (1) built a genuine two-branch merge conflict, confirmed `git merge --no-ff` writes "CONFLICT..." to stdout, then ran the exact `Invoke-GitWizard` code against it and observed `RESULT: TRUTHY` even though `git status` showed an unresolved conflict; (2) confirmed the same stdout-on-failure behavior for `git commit` (nothing to commit) and `git pull --rebase` (conflict); (3) confirmed `git push`/`git checkout -b` write to stderr instead and are correctly detected as failing; (4) re-ran the merge-conflict scenario with the proposed fix in place and confirmed `if (...)` now correctly returns falsy while git's own messages still print unchanged.
- **Proposed fix:** In `Invoke-GitWizard` (`modules/git-wizard.ps1:246`), change `& git @GitArgs` to `& git @GitArgs | ForEach-Object { Write-Host $_ }`. `Write-Host` writes directly to the console host rather than PowerShell's success/output stream, so git's stdout no longer becomes part of the function's return value — visible output is unchanged, but `return ($LASTEXITCODE -eq 0)` becomes the function's only output, making every boolean call site reliable without touching any of them individually. STDERR is untouched and was already safe.
- **Effort:** small for the root-cause fix, but **high-value verification afterward**: spot-test each of the 19+ call sites post-fix (a conflicting merge, a conflicting rebase, a no-op commit).

### PS1-6 — Rollback-force-pull resets the wrong branch if checkout to the recorded branch fails
- **Severity:** High
- **Location:** `modules/conflict-engine.ps1:213-217` (`Invoke-RollbackForcePull`)
- **What's wrong:** `$cur = git rev-parse --abbrev-ref HEAD; if ($cur -ne $rb.Branch) { git checkout $rb.Branch }` never checks whether the checkout succeeded. If `$rb.Branch` no longer exists locally (deleted/renamed/never fetched since the recorded force-pull), `git checkout` fails but execution falls straight through to the unconditional `git reset --hard $rb.HeadSha`, which now resets whatever branch is **currently** checked out — not `$rb.Branch` — to the recorded SHA.
- **Why it matters:** This silently discards commits on a branch the user never asked to touch, via the exact rollback feature meant to be the tool's safety net.
- **Verification:** Reproduced in a throwaway repo at `/tmp/audit-rollbacktest` (two branches diverged by one commit each): confirmed `git checkout` of a missing branch exits 1 while HEAD stays on the original branch, and the subsequent `git reset --hard` then resets that original (wrong) branch, discarding its unique commit.
- **Proposed fix:** `git checkout $rb.Branch; if ($LASTEXITCODE -ne 0) { Write-Host "[!] Could not check out '$($rb.Branch)' - rollback aborted, nothing was changed." -ForegroundColor Red; return }` before proceeding.
- **Effort:** small

### PS1-12 — Force Sync declares success without checking the hard-reset's exit status
- **Severity:** Medium
- **Location:** `modules/repo-engine.ps1:528` (`Invoke-ForceSyncWithOrigin`)
- **What's wrong:** `Invoke-GitWizard reset --hard "origin/$Branch" | Out-Null` discards the result entirely — unlike the `fetch` check two lines earlier (line 512), nothing checks whether the reset succeeded before running `clean -fd` and printing "[+] Force sync complete."
- **Why it matters:** In a flow explicitly built around safety messaging, claiming the reset "complete[d]" when it may have failed (locked files, permissions, a corrupted ref) is misleading, and the subsequent unconditional `clean -fd` still runs and deletes untracked files even if the reset didn't happen.
- **Verification:** Read `modules/repo-engine.ps1:510-536`; confirmed the reset's result is piped to `Out-Null` in contrast to the checked `fetch` three lines above.
- **Proposed fix:** `if (-not (Invoke-GitWizard reset --hard "origin/$Branch")) { Write-Host "[!] Hard reset failed. Nothing further was changed." -ForegroundColor Red; Pause-Console; return }` before the clean step. (Also affected by **PS1-3**'s array-truthiness bug once that's fixed.)
- **Effort:** small

### MAIN-9 — Workspace Explorer's `.git/wizard-backups/` directory grows unbounded, forever, per repo
- **Severity:** Medium
- **Location:** `linux/workspace-explorer.sh` (every `backup_dir="$(ws_git_dir)/wizard-backups/<reason>-${ts}"` call site, e.g. lines ~1198, 1256, 1461, 1605) and the matching pattern in `modules/workspace-engine.ps1` (e.g. lines ~1143, 1201, 1396)
- **What's wrong:** Every file-level revert/apply/restore/undo action creates a brand-new, uniquely timestamped backup subfolder. Nothing ever deletes an old one — the undo journal only ever tracks the single most recent action's backup directory by design.
- **Why it matters:** Regular use of the Explorer leaves a permanently growing folder of file copies inside `.git/`, with no documented cleanup path other than manually deleting `.git/wizard-backups/`. Not a correctness/safety risk (undo is correctly scoped to the latest action only) — a legitimate resource-growth concern for a feature advertised as polished and safe.
- **Verification:** Read every call site constructing a `wizard-backups/<reason>-<timestamp>` path in both files; confirmed `ws_undo_last_action`/`Invoke-WsUndoLastAction` only ever reference the single most-recently-recorded path; nothing prunes the directory as a whole.
- **Proposed fix:** Smallest fix: at Explorer-session startup, prune `wizard-backups/*` subfolders older than N days (e.g. 7) except the one referenced by the live undo journal, with a one-line log entry. Alternatively: document the folder (see **DOC-3**) and leave pruning as manual/`rm -rf` for now.
- **Effort:** medium (pruning logic needs to avoid racing the live undo journal, tested on both engines)

---

## 4. Destructive-action safety

### D4 — "Safety backup" tag does not protect uncommitted/untracked changes before Discard/Force-Sync — recovery message is misleading, in **both engines** *(merges BASH-6 + PS1-11)*
- **Severity:** Critical
- **Location:**
  - Linux: `force_sync_with_origin` (`linux/git-wizard.sh:212-279`), reached via Module 2 → Reset & Undo → "Force Sync with Origin."
  - Windows: `Manage-Repo`'s "Discard All Uncommitted Local Changes" (`modules/repo-engine.ps1:86-93`) **and** `Invoke-ForceSyncWithOrigin` (`modules/repo-engine.ps1:470-537`).
  - Both routed through `create_safety_backup`/`New-SafetyBackup` (PowerShell helper at `modules/git-wizard.ps1:288-308`), which only runs `git tag $TagName HEAD`.
- **What's wrong:** A git tag on HEAD captures the current *commit* — nothing else. It cannot and does not contain uncommitted edits to tracked files or untracked files, since that content was never part of any commit. All three call sites above run a hard reset (`reset --hard`) plus `clean -fd` right after taking this commit-only backup, and the on-screen message explicitly claims local changes are protected (Linux: "Any local commits **or changes** not already on origin will be LOST (a backup tag is created first)"; Windows: "[+] Safety backup created: ... (recover with: `git reset --hard $TagName`)"). Neither claim is true for dirty/untracked content. The codebase already knows the correct fix: `smart_force_pull()` (bash, line 2979) and `Invoke-SmartForcePull` (`conflict-engine.ps1:164-173`) both explicitly `git stash push -u` before their own `reset --hard`/`clean -fd`, specifically because, per that function's own comment, "reset --hard / clean -fd would destroy them." That stash step is simply missing from all three locations flagged here.
- **Why it matters:** This is exactly the scenario these menu options exist for — syncing/discarding a dirty working tree. A user who follows the tool's own on-screen recovery instructions after Discard or Force Sync will find their changes are permanently gone.
- **Verification:**
  - Linux: reproduced in `/tmp/audit-bash-test-1` — committed one file, added an untracked `uncommitted.txt`, ran the exact sequence `force_sync_with_origin` executes. `uncommitted.txt` was deleted by `clean -fd` and does not appear in `git show backup/pre-force-sync-test --stat` (shows only the prior commit). No way to recover it.
  - Windows: reproduced in `/tmp/audit-discardtest` — committed a file, made an uncommitted edit plus an untracked file, created the identical `backup/pre-discard-<ts>` tag at HEAD, ran `git checkout -- .` + `git clean -fd` (identical to the Discard option), then ran the tool's own suggested recovery command `git reset --hard <tag>`. The tracked file's edit was gone and the untracked file was not restored — the "recovery" did nothing for either.
- **Proposed fix:** Add the same dirty-tree-stash guard `smart_force_pull`/`Invoke-SmartForcePull` already use, at all three sites (or inside `create_safety_backup`/`New-SafetyBackup` itself):
  ```bash
  if [[ -n "$(git status --porcelain)" ]]; then
      local STASH_MSG="gw-force-sync-${BRANCH}-$(date '+%Y%m%d-%H%M%S')"
      if ! git stash push -u -m "$STASH_MSG" >/dev/null 2>&1; then
          echo -e "${RED}[!] Couldn't stash your local changes — aborting so nothing is lost.${NC}"
          pause; return
      fi
      echo -e "${GREEN}[✔] Uncommitted/untracked files saved in stash '${STASH_MSG}'.${NC}"
  fi
  ```
  ```powershell
  if (git status --porcelain) {
      $stashMsg = "gw-$Reason-$ts"
      if (-not (Invoke-GitWizard stash push -u -m $stashMsg)) {
          Write-Host "[!] Couldn't stash your local changes - aborting so nothing is lost." -ForegroundColor Red
          return
      }
  }
  ```
  and surface the stash name alongside the tag name in the recovery message (`git stash pop` / `git stash list`) on both platforms. Also soften the pre-action warning text so it doesn't overstate what the tag alone protects.
- **Effort:** medium (small fix, but needs testing against commit-only / dirty-tree / untracked-only scenarios, and updated recovery messaging, on both engines)

### PS1-4 — Merge-into-main in Team Mode admin dashboard skips `Confirm-DestructiveAction`
- **Severity:** High
- **Location:** `modules/team-engine.ps1:170-183`
- **What's wrong:** "Merge into main" inside `Invoke-TeamModeAdminDashboard` calls `New-SafetyBackup`, then immediately runs `checkout main` → `merge --no-ff origin/$ReviewBranch` → `push origin main`, with no call to `Confirm-DestructiveAction` anywhere in the path. Every other destructive action in the codebase (branch delete, reset --hard, force-push, rollback) gates on `Confirm-DestructiveAction` in addition to a backup; this path takes the backup but skips the confirmation.
- **Why it matters:** A stray keypress on this menu choice merges and pushes to the shared remote — a hard-to-reverse, team-visible action — with zero chance to back out, unlike every comparable destructive path in the tool.
- **Verification:** Read `modules/team-engine.ps1:154-188` in full; confirmed `Confirm-DestructiveAction` does not appear in `Invoke-TeamModeAdminDashboard`, while other state-changing actions in the same file do use it. (Also independently affected by **PS1-3**'s array-truthiness bug, which can mask a merge-conflict failure here too.)
- **Proposed fix:** `if (-not (Confirm-DestructiveAction "Merge '$ReviewBranch' into main and push to origin")) { return }` before the backup/checkout/merge sequence, matching the pattern in `Restore-GitWizardRollback` (`toolstack-engine.ps1:401`).
- **Effort:** small

### PS1-13 — Generating a `.gitignore` silently overwrites an existing one
- **Severity:** Medium
- **Location:** `modules/repo-engine.ps1:111-130` (`Manage-Repo`, option "7")
- **What's wrong:** `Set-Content -Path .gitignore -Value "..."` runs unconditionally for whichever template is picked — no `Test-Path` check, no diff/preview, no confirmation, no backup.
- **Why it matters:** A hand-customized `.gitignore` is clobbered with a single accidental keystroke; unlike every other file-destroying action in this module, there's no `Confirm-DestructiveAction` gate or safety backup at all here.
- **Verification:** Read `modules/repo-engine.ps1:111-130`; confirmed no `Test-Path`, confirmation, or backup anywhere before `Set-Content`.
- **Proposed fix:** Check `Test-Path .gitignore` first; if present, warn and require `Confirm-DestructiveAction "Overwrite existing .gitignore"` before `Set-Content`, or append missing template lines instead of replacing the whole file.
- **Effort:** small

*(MAIN-9's unbounded `wizard-backups/` growth is listed under Bugs/logic errors above since it's a resource-leak rather than an unsafe-action concern — the underlying undo mechanism itself is correctly scoped.)*

---

## 5. Security

### D5 — PAT "vault" stores tokens in plaintext on **both** platforms — the password/lock protects nothing on disk *(expands PS1-8 after confirming the identical flaw exists in the Linux engine too — not caught by the original per-engine review split)*
- **Severity:** Critical
- **Location:**
  - Windows: `modules/identity-engine.ps1:237-349` (`Manage-PatVault`), save at line 281, plaintext read at lines 292-297.
  - Linux: `linux/git-wizard.sh:2563-2654` (`manage_pat_vault`), save at line 2648 (`echo "${TOKEN_ALIAS}=${NEW_TOKEN}" >> "$VAULT_FILE"`), plaintext read/display at lines 2663-2673. The password gate (`_hash_pass` at line 2408, `_prompt_vault_access` at 2429-2465) is a plain unsalted `sha256sum` of the password, used only to gate the in-tool menu — structurally identical to the Windows flaw.
- **What's wrong:** On both engines, PATs are written to `pat_vault.env` as plain `alias=token` lines with zero encryption. The "vault lock" only gates whether the tool's own menu will let you view/add/delete entries — it never touches how the file is stored on disk. The master password is an unsalted single-pass SHA256 hash used only to gate that in-tool prompt, never to derive an encryption key. `chmod 600` (Linux only) restricts other *local users*, but does nothing against malware running as the same user, a backup/sync tool copying the config folder, or anyone who later reads the file directly. Anyone with that level of access can open `pat_vault.env` and read every token in cleartext — bypassing both the "lock" and the UI's explicit claims ("securely saved to vault", "[LOCKED] Password required to view" on Windows; "Token securely saved to vault" on Linux).
- **Why it matters:** GitHub PATs typically carry repo/org write access. The vault is explicitly designed to accumulate multiple long-lived tokens over time, so a single filesystem-level compromise exposes every token ever saved on either platform, while the UI on both actively misrepresents the protection provided.
- **Verification:** Windows — read `modules/identity-engine.ps1:237-349` and `:87-157` in full; confirmed no `ConvertTo-SecureString`, `Protect-CmsMessage`, DPAPI, or AES anywhere. Linux — read `linux/git-wizard.sh:2405-2654` in full; confirmed `_hash_pass` is a bare `sha256sum`, used only inside `_prompt_vault_access`'s comparison, never to encrypt `$NEW_TOKEN` before the `echo ... >> "$VAULT_FILE"` write.
- **Proposed fix:** See the design-options discussion below (Phase 2 consent requires presenting options before implementing this one) — broadly: encrypt each token at rest per-platform (Windows DPAPI; a Linux-side equivalent such as a `gpg`/`age`-encrypted vault file or an OS-keyring integration) before writing, decrypting only in-memory when displaying/using a token, and stop claiming the storage itself is secure in the UI text on both engines until that lands.
- **Effort:** medium-large (now covers two engines with no shared crypto primitive between them)

### PS1-9 — Single quote in the install path leads to arbitrary code execution in an elevated process
- **Severity:** High
- **Location:** `modules/identity-engine.ps1:657-679` (`Manage-SshMenu`, option "1", server-side SSH setup)
- **What's wrong:** `$selfScript` (the running script's own path) is interpolated directly into a single-quoted literal inside an expandable here-string (`Import-Module '$selfScript' -Force`) that's written to a temp `.ps1` file and executed via `Start-Process powershell -Verb RunAs` (a UAC elevation prompt). A single quote in the path breaks the literal early, and everything after it is parsed as separate, real PowerShell statements inside the elevated script.
- **Why it matters:** Windows allows apostrophes in usernames/paths (e.g. "O'Brien"), and anywhere an attacker can place or rename a folder in the path to this script to include a quote followed by code, the next time any user runs this SSH-setup option and accepts the UAC prompt, the injected code runs elevated.
- **Verification:** Reproduced with `pwsh` 7.6.6 outside the project directory: built the identical here-string construction with `$selfScript = "C:\Users\test'; Write-Host 'INJECTED-CODE-RAN' #.ps1"`, wrote and ran the generated helper file, and confirmed the injected `Write-Host` statement executed while the intended `Import-Module` call was truncated/failed.
- **Proposed fix:** Never interpolate a filesystem path into a quoted PowerShell string literal that will be executed. Escape embedded single quotes by doubling them (`$selfScript.Replace("'", "''")`), or better, avoid the string-based helper script entirely and pass the module path as a parameter (`-EncodedCommand`, or a parameterized script reading `$args[0]`).
- **Effort:** small

### PS1-5 — Binary-pull fallback installs unverified executables onto PATH
- **Severity:** Medium
- **Location:** `modules/toolstack-engine.ps1:48-128` (`Install-ToolBinaryFallback`)
- **What's wrong:** When `winget` is unavailable or fails, this downloads a release zip for gh/delta/glab/lazygit via `Invoke-WebRequest`, expands it, copies the `.exe` into `%USERPROFILE%\.git-wizard\bin`, and adds that to PATH — with no checksum or signature verification anywhere.
- **Why it matters:** Anything on PATH runs with the user's full privileges the next time that tool's name is typed (including by this script itself). A tampered download (TLS compromise, or a compromised upstream release asset) has no secondary check before landing on PATH and running. `winget` performs its own verification; this fallback exists precisely for when that path isn't available, so it currently has no equivalent safety net.
- **Verification:** Read `modules/toolstack-engine.ps1:48-128` in full; confirmed no `Get-FileHash`, `Get-AuthenticodeSignature`, or checksum comparison anywhere before the `Copy-Item`/PATH mutation.
- **Proposed fix:** Verify the Authenticode signature of the extracted `.exe` with `Get-AuthenticodeSignature` where the vendor ships signed binaries (gh, lazygit do), rejecting/warning on anything not `Valid`. Where signed binaries aren't available, at minimum warn explicitly that this path performs no integrity verification.
- **Effort:** medium

### PS1-10 — Auto-generated SSH keys always use an empty passphrase, with no option or warning
- **Severity:** Low
- **Location:** `modules/identity-engine.ps1:407` (`Invoke-SshGithubSetupE2E`) and `:719` (`Manage-SshMenu` option "2")
- **What's wrong:** Both key-generation call sites hardcode `ssh-keygen ... -N '""'`, forcing an empty passphrase with no prompt and no warning that the resulting private key is unprotected if the disk/account is compromised.
- **Why it matters:** A reasonable default for a fully automated flow, but doing it silently removes a real defense-in-depth layer without ever telling the user.
- **Verification:** Read both call sites; confirmed `-N '""'` is hardcoded in both with no accompanying passphrase prompt or warning.
- **Proposed fix:** Either prompt "Protect this key with a passphrase? (y/N)" and pass it through `-N` when chosen, or at minimum print a one-line warning that the generated key has no passphrase.
- **Effort:** small

### D2 — `eval "$cmd"` used for package-install commands *(merges MAIN-3 + BASH-8; not currently exploitable)*
- **Severity:** Low
- **Location:** `linux/git-wizard.sh:504` (`offer_install`), `:2280`, and `install.sh:112`
- **What's wrong:** These build a shell command string via `get_install_command "$tool" "$pm"` (a fixed `case` over a closed set of package-manager names and a package name) and run it with `eval`.
- **Why it matters:** `eval` on a built string is a classic injection smell, but every traced call site of `offer_install`/`suggest_install`/`get_install_command` (11 sites) passes `$tool` as a literal constant or the output of `vcs_binary_name()` (which only ever returns `"gh"` or `"glab"`) — never raw user input. **There is no currently-reachable injection path.** This is a defensive-hardening recommendation, not a confirmed vulnerability.
- **Verification:** Grepped every call site of `offer_install`, `suggest_install`, and `get_install_command`; confirmed each passes a literal or a closed-set function return.
- **Proposed fix:** Replace `eval "$cmd"` with array-based invocation (`cmd=(sudo apt install -y "$pkg"); "${cmd[@]}"`) to remove the class of risk entirely, even though it isn't exploitable today.
- **Effort:** small (cheap hardening); medium if also touching `install.sh`'s equivalent and re-testing install flows.

### MAIN-5 — `curl`-via-`bash -c` pattern to bootstrap Homebrew on macOS
- **Severity:** Low
- **Location:** `autorun.sh:125`
- **What's wrong:** Downloads and executes a remote script from GitHub with no integrity check, only after an explicit "y" confirmation to install `chafa` on a Mac without Homebrew.
- **Why it matters:** Functionally the `curl | bash` pattern this audit was asked to flag, even though it's byte-for-byte Homebrew's own officially-documented install command (not a project-introduced risk beyond what every Homebrew user already accepts).
- **Verification:** Confirmed the line matches Homebrew's published install instructions at brew.sh; only reachable after explicit confirmation.
- **Proposed fix:** No code change recommended — it's the standard, user-confirmed way to get Homebrew, and pinning a commit would make the installer go stale. If hardening is wanted anyway, print the URL before running it so an attentive user can audit it.
- **Effort:** small

---

## 6. Linux vs Windows parity

A 25-row parity table covering the Main Menu through the Workspace Explorer was built by reading the actual menu-printing code on both engines. Full detail in the appendix below; the two real divergences are:

### PARITY-1 — Module 1 (Identity) menu numbering diverges between platforms
- **Severity:** High
- **Location:** `linux/git-wizard.sh:2784-2788` (`manage_identity`) vs `modules/identity-engine.ps1:835-840` (`Manage-Identity`)
- **What's wrong:** Windows' Identity menu has a `[1] GitHub CLI (gh) Login/Logout/Status` entry Linux's Identity menu doesn't have, shifting every other item down one slot on Windows: Git user/email is `[1]` on Linux, `[2]` on Windows; SSH Manager is `[2]`/`[3]`; PAT Vault is `[3]`/`[4]`; Remote URLs is `[4]`/`[5]`. This directly contradicts README.md:625 ("the same menus ... on both platforms").
- **Why it matters:** A user following a "press 1 then 3" style instruction — exactly what the README's own Recipes table does (see **DOC-1**) — lands on a different feature depending on platform.
- **Verification:** Read both menu definitions directly.
- **Proposed fix:** Either (a) add the same `gh Auth Manager` entry to Linux's Identity menu as a new, additive `[5]` (keeps existing Linux numbers stable, gives both platforms the feature with documented platform-specific numbering), or (b) the smaller/safer fix: explicitly document that Module 1's numbering differs by platform and switch step-numbered recipes touching Module 1 to named destinations instead of digits. (b) is a docs-only fix; (a) is a feature-parity decision that should be confirmed separately.
- **Effort:** small (doc fix) or medium (feature-parity fix)

### MAIN-2 — "Repo History Viewer" lives in a different module on Windows than on Linux
- **Severity:** Medium
- **Location:** `linux/git-wizard.sh:3140` (Module 2, option `[8]`) vs `modules/team-engine.ps1:409` (Module 5, option `[6]`, dispatched at line 432)
- **What's wrong:** The same feature (commit graph across all branches, via `delta`) is reachable from Module 2 on Linux but Module 5 on Windows. Confirmed Windows-reachable (resolving an earlier open question from two independent reviewers) — it's relocated, not missing.
- **Why it matters:** A user following the README's module-grouping, or switching machines, will look in Module 2 on Windows and not find it.
- **Verification:** Read both menu definitions; confirmed via grep that `Show-RepoHistoryViewer` is defined and dispatched only in `team-engine.ps1`, and confirmed it IS wired into `Show-Module5Menu`'s dispatch on Windows (`team-engine.ps1:390-435`).
- **Proposed fix:** Either (a) move the menu entry into `Manage-Repo` to match Linux's placement, renumbering Windows Module 2/5 and updating README references, or (b) the smaller/safer fix: leave the function where it is, cross-link it from both menus, and document the Windows-specific location in the README's parity table. Given "keep menu numbering identical" is a stated project goal, (a) is more correct but touches more call sites — recommend discussing before picking.
- **Effort:** medium

Other parity notes (non-defects, already correctly documented or low-impact — see **DOC-4** below for the one undocumented asymmetry): Git CLI Hub and the git-absorb/ghq/local-CI bonus tools are confirmed Linux-only, matching the README's existing claims exactly; the Workspace Explorer is a near-1:1 function-for-function port (58 Bash `ws_*` functions vs 62 PS1 functions, all key bindings verified present on both).

---

## 7. Static analysis (summarized, not raw-dumped)

**shellcheck** (`-x`, all 5 `.sh` files): 1 error, 27 warnings, 154 notes/info.
- The 1 **error** (`SC2170`, invalid number for `-ge`) is `linux/git-wizard.sh:2078` — this is **D1** above, independently confirmed by the tool.
- `SC2162` (140 occurrences, by far the largest group): `read` used without `-r` throughout both the main engine and the explorer. Pure style/robustness (backslashes in pasted input could misbehave); not individually itemized per the "no style nitpicks" instruction, but worth a project-wide pass if the team wants to clean it up.
- `SC2209` (11): `VAR=value command args...` patterns (e.g. `GH_PAGER=cat gh api ...`) — shellcheck's heuristic flags these as "did you mean to assign output", but all 11 sampled are legitimate temporary-env-var-prefixed commands, not actual bugs. False positives.
- `SC2181` (5), `SC1090` (5), `SC2155` (4), `SC2119`/`SC2120` (4 combined), `SC2034` (3), `SC2206` (2), `SC2170` (2 more beyond the error above — in different files), `SC2016` (2), `SC2086` (1), `SC2015` (1), `SC2001` (1): all reviewed by sampling; all are style-level (indirect `$?` checks that work correctly, functions that could accept `$@` but don't need to, an unused `deleted_token` variable, an unquoted array split on a version string that never contains spaces in practice, a non-if-then-else `&&`/`||` chain that's logically fine as written). None rose to the level of a correctness finding beyond what's already captured as **D1**.

**PSScriptAnalyzer** (all 11 `.ps1` files, default rule set): 1265 warnings, 1 informational, 0 errors.
- `PSAvoidUsingWriteHost` (806) and `PSAvoidGlobalVars` (358): both are the project's own deliberate, consistent style (console-driven menu UI; globals used intentionally for cross-module state) — not findings.
- `PSUseApprovedVerbs` (42) and `PSUseSingularNouns` (28): naming-convention noise from domain-specific function names (`Craft-Commit`, `Vcs-RenameRepo`, etc.) — not findings.
- `PSAvoidUsingEmptyCatchBlock` (15): sampled at `git-wizard.ps1:113,117,118,191`, `identity-engine.ps1:68,104,324-331`, and others. Every sampled instance wraps a cosmetic/best-effort operation (resetting console color, an optional `gh auth status` probe, opening a browser as a convenience) where silent failure is intentional and harmless. Not itemized as findings.
- `PSUseShouldProcessForStateChangingFunctions` (9): PowerShell-idiom advice (use `-WhatIf`/`-Confirm` plumbing) that doesn't fit this project's existing `Confirm-DestructiveAction` confirmation pattern — not a correctness gap.
- `PSPossibleIncorrectUsageOfRedirectionOperator` (7): all 7 manually verified as legitimate `2>$null` redirects (`try-explorer.ps1:68`, `conflict-engine.ps1:22`, `identity-engine.ps1:327,560,593`, `repo-engine.ps1:209,307`) — false positives from the analyzer misreading `2>` as a possible typo for `-gt`.
- `PSAvoidUsingPositionalParameters` (1): `vcs-engine.ps1:498`, `Vcs-AddCollaborator` — minor, not itemized.

No PS7-only syntax (`` `e ``, `` `u{} ``, ternary `?:`, `??`/`??=`, `&&`/`||` pipeline chaining, `$PSStyle`, `ForEach-Object -Parallel`, multi-arg `-AdditionalChildPath`) was found anywhere in `modules/*.ps1` or `dev-tools/*.ps1` — confirmed by targeted grep across the whole PowerShell codebase.

---

## 8. Compatibility

### MAIN-7 — No `.gitattributes` — a Windows contributor's default Git config will corrupt the `.sh` files with CRLF on checkout
- **Severity:** Medium
- **Location:** Repo root (confirmed absent from the entire git history)
- **What's wrong:** Committed `.sh` blobs are pure LF today (confirmed via `xxd`: no `0x0d` bytes). With no `.gitattributes` pinning `*.sh` to `text eol=lf`, a checkout on Windows with Git's common `core.autocrlf=true` (the default suggested choice during Git for Windows setup) will rewrite every `.sh` file to CRLF on disk after cloning.
- **Why it matters:** A CRLF shebang (`#!/usr/bin/env bash\r\n`) fails outright under Linux/WSL/macOS, and embedded `\r` elsewhere would misbehave even if the shebang were worked around. This specifically bites a Windows-based contributor cloning the repo to edit/test the Bash engine via WSL — exactly the audience most likely to hit it, since Windows end-users of the shipped tool use the PS1 engine and wouldn't touch the `.sh` files.
- **Verification:** Confirmed the committed blob is pure LF; confirmed via `git log --all --oneline -- .gitattributes` that no `.gitattributes` has ever existed.
- **Proposed fix:**
  ```
  *.sh text eol=lf
  *.ps1 text eol=crlf
  *.bat text eol=crlf
  assets/* -text
  ```
- **Effort:** small

### MAIN-8 — `dev-tools/try-explorer.ps1` is the one `.ps1` file without a UTF-8 BOM
- **Severity:** Low
- **Location:** `dev-tools/try-explorer.ps1` (first 3 bytes `23 20 53` — no `EF BB BF`)
- **What's wrong:** Every file under `modules/*.ps1` has the required BOM (verified, all 10); this one tester script doesn't.
- **Why it matters:** Currently harmless — the file contains zero non-ASCII bytes (verified), so PS 5.1's ANSI-fallback misreading can't corrupt anything yet. Purely a consistency gap that would bite the moment someone adds an em-dash or similar.
- **Verification:** `xxd`'d the first 3 bytes directly; grepped the file for non-ASCII bytes (zero found).
- **Proposed fix:** Re-save with a UTF-8 BOM, matching every file under `modules/`.
- **Effort:** small

No other compatibility issues were found: no PS7-only syntax anywhere (see Section 7), no CRLF already present in any committed file, BOM present and correct on all 10 `modules/*.ps1` files, and dependency-availability checks for git/gh/glab/delta/chafa all have graceful fallback/offer-to-install paths on both engines (traced directly, no gaps found beyond the already-flagged **PS1-5** integrity-verification gap).

---

## 9. Error handling and UX

### BASH-10 — `repo_history_viewer`'s delta-failure fallback has no trailing `pause`
- **Severity:** Low
- **Location:** `linux/git-wizard.sh:5155-5165` (fallback path when `delta --paging=always` is installed but exits non-zero)
- **What's wrong:** The fallback (`GIT_PAGER=cat git log ...`, no pager) has no trailing `pause` call, so the menu redraws immediately on a long history before the user can read it. (The delta-success and `less -R` paths are both real interactive pagers that block for input, so they're unaffected.)
- **Why it matters:** Minor — only triggers when delta is installed but broken; consequence is just a too-fast redraw, not data loss or a crash.
- **Verification:** Read all three branches directly; confirmed only the delta-failure fallback lacks a pause/pager.
- **Proposed fix:** Add a trailing `pause` call after the if/else block.
- **Effort:** small

Scenarios checked directly and found to behave correctly (no finding): empty repo (zero commits) + Repo History Viewer exits cleanly with no raw error leak; detached HEAD + Force Sync bails with a clear message before anything destructive; missing `origin` remote + Force Sync / repo-destroy both bail cleanly with a clear message. Main Menu, Settings submenu, and Module 2's numbered prompts were manually cross-checked against their `case` arms and found consistent; the remaining ~40 smaller sub-menu prompts in the Bash engine were **not** exhaustively hand-verified (an automated cross-reference script was attempted but produced unreliable false positives against this file's mixed single-line/multi-line `case` style) — flagged here as **UNVERIFIED** rather than silently assumed correct.

(**PS1-12**'s missing exit-status check on Force Sync's hard reset is listed under Bugs/logic errors in Section 3, since its root issue is a logic gap rather than a UX-only concern.)

---

## 10. Documentation

### D3 — README claims an MIT `LICENSE` file that does not exist in the repo *(merges MAIN-4 + DOC-2)*
- **Severity:** High
- **Location:** README.md:12 (MIT badge), README.md:833-835 ("## License ... Distributed under the MIT License. See `LICENSE` for details.") vs README.md:792 (Roadmap: "- [ ] Add a `LICENSE` file...") and the repo root (`ls LICENSE*` → no matches, confirmed again at the time of writing this report)
- **What's wrong:** The README's own Roadmap admits no LICENSE file exists yet, while the License section a few hundred lines later states it as settled fact and tells readers to "see LICENSE for details" — self-contradictory within the same document, and legally meaningful (anyone relying on the MIT claim has nothing to point to).
- **Why it matters:** A contributor, packager, or company evaluating the tool has no actual license grant despite the explicit, present-tense claim.
- **Verification:** `ls -la LICENSE* CONTRIBUTING*` at repo root returns no matches (re-confirmed just before writing this report); both contradictory README lines read directly.
- **Proposed fix:** Add an actual `LICENSE` file (plain MIT text matching the README's claim) and remove the Roadmap checklist item — the obviously correct fix given the README already asserts MIT. (Softening the claim instead is a fallback if the user doesn't want to commit to MIT right now.)
- **Effort:** small

### DOC-1 — SSH-setup Recipe path is wrong on both platforms
- **Severity:** High
- **Location:** README.md:286 (Recipes table: "Connect this machine to GitHub over SSH" → `1` → `3` → `3` → Setup End-to-End) vs `linux/git-wizard.sh:2784` (`manage_identity`), `:2327` (`manage_ssh_menu`), `:2371` (`manage_ssh_github_menu`)
- **What's wrong:** The real Linux path is `1` (Identity) → `2` (SSH Manager — not `3`; `3` is PAT Vault) → `3` (SSH GitHub Manager) → `1` (Setup End-to-End): four hops, not three, with the second hop's digit wrong. On Windows the second hop (`3`) coincidentally lands on SSH Manager (due to **PARITY-1**'s shift), but the recipe still stops one hop short of the actual destination.
- **Why it matters:** This is the README's own worked example for the tool's flagship onboarding flow; following it literally does not reach the stated destination on either platform.
- **Verification:** Traced the actual menu numbers at each of the three function definitions.
- **Proposed fix:** Change the Recipes row to `1 → 2 → 3 → 1 (Linux)` with a note that the Windows path is `1 → 3 → 3 → 1`, or — the more robust fix given **PARITY-1** — write named steps instead of digits: `1 (Identity) → SSH Manager → SSH GitHub Manager → Setup End-to-End`.
- **Effort:** small

### DOC-3 — "Everything lives in one folder" omits the Workspace Explorer's per-repo backup directory
- **Severity:** Medium
- **Location:** README.md:567 ("Everything Git-Wizard stores lives in **one folder**: `~/.git-wizard/`...") and the Configuration table at README.md:569-574
- **What's wrong:** The Workspace Explorer's file-content backups live under `<target-repo>/.git/wizard-backups/`, not `~/.git-wizard/` — confirmed via `linux/workspace-explorer.sh:1198,1256,1461,1605` and `modules/workspace-engine.ps1:1143,1201,1396` (all built from the target repo's own `.git` dir). The "one folder" claim and the Configuration table are both incomplete. (See also **MAIN-9**: this folder is also never pruned — a related but distinct code-behavior concern, not re-filed here.)
- **Verification:** Read every call site constructing a `wizard-backups/<reason>-<timestamp>` path in both files.
- **Proposed fix:** Add a Configuration-table row: `<repo>/.git/wizard-backups/` — "Per-repo file-content backups for the Workspace Explorer's revert/undo actions (not pruned automatically)"; adjust the "one folder" sentence accordingly.
- **Effort:** small

### DOC-4 — Settings' Global-CLI Enable/Disable asymmetry is undocumented
- **Severity:** Low
- **Location:** README.md's parity table — no mention; actual code at `linux/git-wizard.sh:5691-5692` vs `modules/git-wizard.ps1:942`
- **What's wrong:** Linux Settings offers both Enable and Disable for the Global CLI; Windows Settings offers only Disable (Enable is reachable only via Main Menu `[7]` there). Not a missing feature, just undocumented.
- **Verification:** Read both Settings-menu definitions.
- **Proposed fix:** Add one parity-table line/footnote: "Settings → Enable Global CLI is Linux-only; on Windows, enable via Main Menu `[7]`."
- **Effort:** small

### DOC-5 — Informational note, not a defect: self-update has nothing to update to yet
- **Severity:** n/a (informational)
- **Location:** README.md's Settings section documents `[5]`/`[8]` update-check/update-now, both fully implemented in code; the Roadmap (README.md:791) separately notes tagged GitHub Releases don't exist yet.
- **What's wrong:** Nothing code-wise — `update_git_wizard`/`Update-GitWizardSelf` are fully implemented and wired on both platforms. This is purely a heads-up that the feature has nothing to update *to* until a release is tagged, which the README's own Roadmap already discloses.
- **Proposed fix:** None required.

---

## 11. Tests

### Current state
**There is no automated test suite anywhere in this repository.** Confirmed: no `tests/`, `test/`, `*.bats`, or `*.Tests.ps1` (Pester) files exist; no `.github/workflows/` (no CI at all); the only CI-adjacent file, `.pre-commit-config.yaml`, runs only generic hygiene hooks (trailing-whitespace, end-of-file-fixer, check-yaml, check-added-large-files, check-merge-conflict) — none of which exercise the tool's actual logic.

`dev-tools/try-explorer.sh` and `dev-tools/try-explorer.ps1` are manual interactive testers, not automated tests: they stub the safety helpers with real-ish behavior and hand control to a human at a keyboard, with no assertions and no pass/fail output. Useful for exploratory manual testing of the Workspace Explorer specifically; they don't cover Modules 1, 3-9, and can't run unattended.

Everything else (~14,000 combined lines across both engines) has zero automated coverage today.

### Recommended tests, ranked by risk (highest first)

1. **Force-push rollback round-trip** — force-push, verify rollback-state is recorded, run Rollback, assert the remote ref is restored. Highest risk: this is the tool's flagship safety claim.
2. **Force-pull rollback with untracked files** — force-pull against dirty+untracked state, confirm both are stashed before the reset and fully restored by Rollback. High risk: untracked-file restoration is easy to silently regress.
3. **Workspace Explorer undo-journal, both kinds** (worktree-level revert-then-undo; commit-level undo-then-undo). This exact scenario already caught two real bugs during this project's own development — the single highest-value regression guard available, since the underlying bug class (silent success/failure mis-detection — see **PS1-3**) can easily reappear elsewhere.
4. **Hard reset / discard safety backups** — assert a backup tag exists before every destructive reset/discard/branch-delete path on both engines, and that `git reset --hard <tag>` actually recovers prior state. Would have caught **D4** directly.
5. **Dry-Run mode never executes** — with Dry-Run on, run each destructive action and assert repo state is byte-for-byte unchanged while the action log still records a "DRY-RUN (not executed)" line.
6. **Cross-platform parity smoke test** — one shared fixture, driven through the same scripted keystrokes on both engines, asserting identical resulting repo state. Would have caught **PARITY-1** before it shipped.
7. **`_arrow_select_key` wrap-around** (once **D1** is fixed) — regression test that navigating Down past the last item wraps to index 0.
8. **Pre-commit hook retry logic** — a hook that fails once then succeeds should retry exactly once; a hook that always fails should stop with the real error, not loop silently.
9. **Not-a-git-repo / empty-repo / detached-HEAD guards** — for Module 2's menu, the Workspace Explorer's three screens, and Module 3 Branches, assert a friendly message and no crash against a non-git directory, a fresh empty repo, and a detached HEAD.
10. **PAT Vault round-trip** — save/lock/unlock (correct and incorrect password)/delete (local vs local+remote); assert file permissions and that the plaintext token is never written to the action log. Directly relevant to **D5**.

**Framework recommendation:** `bats-core` for the Bash engine (trivial to add via the package-manager detection the tool already has) and **Pester 5** for PowerShell (same install pattern as `PSScriptAnalyzer`, already proven in this environment). Both suites should share the same throwaway-repo fixtures so they stay honestly comparable rather than drifting into testing different things.

---

## Appendix: full parity table

| Module | Feature | Linux | Windows | Notes |
|---|---|:-:|:-:|---|
| Main Menu | 9 modules, `0`=Exit | ✅ | ✅ | Identical numbering (`git-wizard.sh:5635-5652` vs `git-wizard.ps1:991-1007`). |
| 1 — Identity | Git user/email | ⚠️ | ⚠️ | Different slot — see **PARITY-1**. |
| 1 — Identity | SSH Manager | ⚠️ | ⚠️ | Linux `[2]`, Windows `[3]`; sub-menu itself identical once inside. |
| 1 — Identity | PAT Vault Manager | ⚠️ | ⚠️ | Linux `[3]`, Windows `[4]`. |
| 1 — Identity | Remote URL Manager | ⚠️ | ⚠️ | Linux `[4]`, Windows `[5]`. |
| 1 — Identity | gh Auth Manager | ➖ | ✅ `[1]` | Windows-only, documented in README's feature table; the numbering side-effect is not. |
| 1 — SSH submenu | Setup E2E / Manage keys / Test connection | ✅ | ✅ | Identical once inside. |
| 2 — Repo | `[W]` Workspace Explorer | ✅ | ✅ | Confirmed first/highlighted entry on both. |
| 2 — Repo | Reset/Undo incl. Force Sync | ✅ | ✅ | `[1]`-`[5]` identical. |
| 2 — Repo | Repo History Viewer | ✅ `[8]` | ⚠️ | See **MAIN-2** — relocated to Module 5 on Windows, confirmed reachable there. |
| 3 — Branches | List/Create/Switch/Delete | ✅ | ✅ | Identical. |
| 4 — Commits | feat/fix/docs/refactor/chore | ✅ | ✅ | Identical. |
| 5 — Team | Linear / Team Mode / Admin / OSS Contributor | ✅ | ✅ | Identical; OSS gated to Advanced mode on both. |
| 5 — Team | Git CLI Hub | ✅ | ➖ | Confirmed Linux-only, matches README's existing claim. |
| 6 — Hosting | Issues/PRs/Releases/CI/Snippets/Codespaces/Admin/API | ✅ | ✅ | Provider-routed identically. |
| 6 — Hosting | Delta Diff Suite | ✅ | ✅ | Same 6-item suite on both. |
| 7 — Global CLI | Enable/disable, re-run setup | ✅ | ✅ | Identical. |
| 8 — Tool Stack | Verify/install/version-check/update | ✅ | ✅ | Binary-fallback (Linux) vs winget (Windows) — documented difference. |
| 8 — Tool Stack | Bonus: lazygit | ✅ | ✅ | Both. |
| 8 — Tool Stack | Bonus: git-absorb / ghq / local CI | ✅ | ➖ | Confirmed Linux-only, matches README. |
| 9 — Settings | Mode / Dry-Run / Sync / History / Updates | ✅ | ✅ | Identical. |
| 9 — Settings | Checkpoint / Self-update / Tool-rollback | ✅ | ✅ | Identical. |
| 9 — Settings | Enable Global CLI | ✅ `[10]` | ➖ | See **DOC-4**. |
| Workspace Explorer | Changes / File Timeline / Project Timeline | ✅ | ✅ | Near-1:1 port, all key bindings verified present on both. |
| Package installer | apt/dnf/pacman/brew+binary vs winget+binary | ✅ | ✅ | Documented difference, not a gap. |

---

*This report was written during a read-only audit. Nothing in the working tree was modified while producing it, and this file itself is intentionally left uncommitted per the audit instructions.*
