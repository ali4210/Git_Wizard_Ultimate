<div align="center">

# 🧙‍♂️ Git-Wizard Ultimate

**A cross-platform, safety-first CLI suite that turns Git, GitHub and GitLab workflows into guided, reversible, one-click operations.**

![Version](https://img.shields.io/badge/version-2.1.0-blue)
![Linux](https://img.shields.io/badge/Linux-Bash%204%2B-black?logo=gnubash&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-PowerShell%205.1-5391FE?logo=powershell&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-supported-lightgrey?logo=apple)
![Platforms](https://img.shields.io/badge/GitHub%20%2B%20GitLab-supported-orange)
![License](https://img.shields.io/badge/license-MIT-green)

*Built for beginners who fear `git push --force`, and for DevOps/DevSecOps engineers who want their workflow automated and auditable.*

</div>

---

## 📖 Table of Contents

- [Why Git-Wizard?](#-why-git-wizard)
- [Feature Highlights](#-feature-highlights)
- [Safety Engine](#-safety-engine-the-core-idea)
- [Force Push and Force Pull with Rollback](#-force-push--force-pull-with-rollback)
- [Full Feature Map](#-full-feature-map)
- [Installation](#-installation)
- [Usage](#-usage)
- [Configuration and Local Data](#-configuration-and-local-data)
- [Architecture and Engineering Notes](#-architecture--engineering-notes)
- [Linux vs Windows Parity](#-linux-vs-windows-parity)
- [Security Notes](#-security-notes)
- [Repository Structure](#-repository-structure)
- [Roadmap](#-roadmap)
- [Contributing](#-contributing)
- [Author](#-author)
- [License](#-license)

---

## 🎯 Why Git-Wizard?

Everyday Git work is full of sharp edges: a rejected push, a tangled local branch, a force push that overwrote the wrong commit, an SSH key that will not authenticate. Most tools either hide Git completely or leave you alone with the raw commands.

Git-Wizard sits in between. It gives you **menu-driven workflows** for the whole lifecycle (identity, SSH, repo setup, branching, commits, collaboration, hosting-platform administration) and puts a **safety net under every destructive action**: dry-run mode, automatic backup tags, typed confirmations for beginners, and real rollback for force operations.

It runs on **Linux, macOS and Windows** from one repository: a Bash engine for Unix-like systems and a modular PowerShell engine for Windows.

---

## ✨ Feature Highlights

| Area | What you get |
|---|---|
| 🔐 **Identity and SSH** | Global Git identity, ED25519 key generation, **end-to-end SSH setup** (generate → agent → upload to GitHub via API → connection test), GitHub SSH key manager with table view and purge |
| 🔑 **PAT Vault** | Local token vault with optional password lock, guided creation of fine-grained or classic tokens, local or local + GitHub revoke |
| 📦 **Repo Engine** | 1-click repo setup (creates the remote on GitHub/GitLab, sets origin, pushes), 1-click destroy, quick push, status inspector, reset and undo utility, **Force Sync with Origin**, `.gitignore` generator, pre-commit hook manager |
| 🛠️ **Smart Conflict Resolver** | Safe pull and rebase, safe pull and merge, **Force Push and Force Pull, each with a real Rollback** |
| 🌿 **Branch Manager** | Arrow-key branch selection, publish new branches, dual purge (local and remote) with backup |
| ✍️ **Conventional Commits** | Guided `feat / fix / docs / refactor / chore` messages with optional scope; auto-retry when pre-commit hooks reformat files |
| 👥 **Team and OSS Workflows** | Linear (solo) workflow, Team Mode with admin review dashboard, fork and upstream sync, PR creation, Safe Update Sync (stash → pull → restore) |
| ⚡ **Hosting Power Tools** | Issues, PRs/MRs, Releases, Actions/Pipelines, Gists/Snippets, Codespaces, collaborators, repo admin, raw API explorer, all through one provider-agnostic layer |
| 🎨 **Delta Diff Suite** | Syntax-highlighted diffs for working tree, staged changes, branches and commits (via `delta`) |
| 🧰 **Tool Stack Manager** | Detects, installs, version-checks and updates `gh`, `glab`, `delta`, `chafa`, `lazygit`, `git-absorb`, `ghq`, `act` |
| 📡 **Live Sync Panel** | Optional header showing ahead/behind counts, dirty files, stashes and conflict risk, in three detail levels |
| ♻️ **Self-Update** | Update the tool from its own GitHub Releases, with checkpoint tags and one-click rollback of the tool itself |

---

## 🛡️ Safety Engine (the core idea)

Every destructive path in Git-Wizard goes through the same layers:

1. **Dry-Run mode.** Every Git command is routed through a wrapper (`run_git` / `Invoke-GitWizard`). With Dry-Run on, commands are printed and logged but **never executed**.
2. **Automatic backup tags.** Before resets, discards, force operations, branch deletes and merges, a recovery tag such as `backup/pre-hard-reset-20260920-135001` is created, and the recovery command is shown on screen.
3. **Mode-aware confirmation.**
   - *Beginner mode* requires typing an exact phrase (`yes i understand`) before any destructive action.
   - *Advanced mode* uses a fast `y/N` prompt.
4. **Action history.** Every executed or dry-run action is written to a local log you can review from Settings.
5. **Commit hook retry.** If a pre-commit hook auto-fixes files (whitespace, EOF newline) and exits non-zero, the tool re-stages and retries once. A genuine hook failure still stops with the real error.

---

## ⏪ Force Push / Force Pull with Rollback

Force operations are where most Git disasters happen. Git-Wizard makes both of them reversible.

### Force Push

```text
Select strategy → [3] Force Push
  ├─ Confirms the destructive action
  ├─ Verifies an 'origin' remote exists          (nothing is changed if not)
  ├─ Shows uncommitted files and asks for a commit message
  │     → stages everything, commits (with hook retry)
  ├─ Fetches, then records the remote's current commit
  │     → tags it locally as backup/remote-<branch>-<timestamp>
  └─ Pushes with --force-with-lease pinned to that recorded commit
```

- `--force-with-lease` protects you if a teammate pushes between your fetch and your push.
- **`[5] Rollback Last Force Push`** pushes the recorded commit back to the remote. It warns you if the remote changed since your push, and tags the pre-rollback state so the rollback itself is reversible.

### Force Pull

```text
Select strategy → [4] Force Pull
  ├─ Fetches and verifies origin/<branch> exists
  ├─ Tags your current commit           (backup/pre-force-pull-...)
  ├─ Stashes uncommitted AND untracked files (git stash push -u)
  └─ reset --hard origin/<branch>  +  clean -fd
```

- **`[6] Rollback Last Force Pull`** resets to your previous commit and pops the stash, so committed work, uncommitted edits and untracked files all come back.

Rollback state is stored per repository, for the **most recent** force push and force pull, and the menu shows **(available)** next to a rollback option when one exists.

---

## 🗺️ Full Feature Map

<details>
<summary><b>Main menu overview</b></summary>

```text
[1] Identity & SSH Manager            [6] Git Hosting Power Tools (GitHub/GitLab)
[2] Repository & Smart Push Engine    [7] Universal Global CLI
[3] Advanced Branch Manager           [8] Tool Stack Manager
[4] Conventional Commit Assistant     [9] Settings
[5] Team & Open-Source Collaboration  [0] Exit
```

Every submenu uses **`0` = Back**, consistently on both platforms.

</details>

<details>
<summary><b>1️⃣ Identity, SSH and Tokens</b></summary>

- Check and set global `user.name` / `user.email`
- **SSH Manager:** install and start the SSH service, generate an ED25519 key and show the public key
- **SSH GitHub Manager:**
  - end-to-end pipeline: detect existing keys → generate with a custom title → start `ssh-agent` → check whether the key is already on GitHub (by fingerprint) → upload via `gh` → test `ssh -T git@github.com`
  - interactive key table (ID, title, fingerprint, date), delete one key, or purge all
- **PAT Vault:** create tokens (opens the right GitHub page), save with an alias, view, delete locally or locally and on GitHub, optional master-password lock
- **Remote URL Manager:** inspect remotes, set a new origin (auto-strips pasted `git remote add origin` prefixes), toggle HTTPS ⇄ SSH
- Windows adds a **GitHub CLI login / logout / status** manager

</details>

<details>
<summary><b>2️⃣ Repository and Smart Push Engine</b></summary>

- **1-Click Complete Repo Setup:** init, `main` branch, commit, create the repo on GitHub/GitLab (public or private), choose SSH or HTTPS, set origin, push
- **1-Click Repo Destroy:** detects the remote from `origin`, deletes it on the host, and auto-fixes the missing `delete_repo` scope
- **Quick Push:** add → commit → push
- **Reset and Undo Utility:** unstage, discard changes, soft or hard rollback of the last commit, **Force Sync with Origin** (5-step nuclear reset with backup)
- **Smart Conflict Resolver:** see [above](#-force-push--force-pull-with-rollback)
- **`.gitignore` generator** (Python, Node.js, Go/Linux)
- **Pre-commit hook manager:** installs the `pre-commit` framework, writes a sensible default config, enables or disables the hook
- **Repo history viewer:** commit graph across all branches, rendered through `delta` when available

</details>

<details>
<summary><b>3️⃣ Branches and 4️⃣ Commits</b></summary>

- List local and remote branches with no pager
- Create and publish, switch and delete (local and remote) using **arrow-key selection**
- Refuses to delete the active branch; backs up before deleting
- Conventional Commit builder with scope support and a preview before committing

</details>

<details>
<summary><b>5️⃣ Team and Open-Source Collaboration</b></summary>

- **Linear Workflow:** checks whether you are behind the remote and pulls (rebase) before every push
- **Team Mode:** contributors create `feature/`, `fix/` or `hotfix/` branches and never touch `main`
- **Admin Dashboard:** browse teammates' branches (author, date, last message), view the diff against `main`, then merge with `--no-ff` or reject
- **Open-Source Contributor Mode** (Advanced mode): detect or set the `upstream` remote, sync a fork, create PRs, list your open PRs
- **Safe Update Sync:** stash local work → `pull --rebase` → restore the stash
- **Git CLI Hub** (Linux): list all repos with visibility, stars and fork tags; browse any repo's full file tree from the terminal

</details>

<details>
<summary><b>6️⃣ Git Hosting Power Tools (GitHub and GitLab)</b></summary>

One menu, two providers. The provider is auto-detected from your `origin` URL, and the same actions map to the right CLI:

| Feature | GitHub | GitLab |
|---|---|---|
| Issues | ✅ | ✅ |
| Pull / Merge Requests | PRs | MRs |
| Releases | ✅ | ✅ |
| CI | Actions | Pipelines |
| Snippets | Gists | Snippets |
| Codespaces | ✅ | n/a |
| Repo admin (create, rename, delete, collaborators) | ✅ | ✅ (rename via web UI) |
| Raw API explorer | `gh api` | `glab api` |

Plus the **Delta Diff Suite** for uncommitted, staged, branch and commit comparisons.

</details>

<details>
<summary><b>7️⃣ 8️⃣ 9️⃣ Global CLI, Tool Stack and Settings</b></summary>

- **Universal Global CLI:** run `git-wizard` from any folder. Linux uses a `/usr/local/bin` symlink that re-heals on launch; Windows adds a PowerShell profile function and/or a CMD wrapper on the user `PATH`.
- **Tool Stack Manager:** verify and install tools with the native package manager first, then a **prebuilt-binary fallback** (no sudo needed); version and update checks; bonus tools (`lazygit`, `git-absorb`, `ghq`, and local CI with `act` / `gitlab-ci-local` on Linux)
- **Settings:** switch Beginner/Advanced mode, toggle Dry-Run, configure the sync panel, view action history, set the update source, create checkpoints, self-update, roll the tool back, enable or disable the global CLI

</details>

<details>
<summary><b>📡 Live Sync Panel</b></summary>

When enabled, every screen header shows the state of your branch against its upstream:

- ✅ Fully synced · 🟡 Ahead or uncommitted changes · 🟠 Behind · 🔴 Uncommitted work **and** remote has moved on
- Fetch reachability, modified vs untracked counts, warning when working directly on `main`/`master`
- **Standard** level adds stash count and last-commit age; **Full** level adds a conflict-risk preview before you pull

</details>

---

## 🛠️ Installation

### Requirements

| Platform | Requirements |
|---|---|
| **Linux** | Bash 4+, Git (auto-installed if missing), `curl`. Optional: `gh`, `glab`, `delta`, `chafa`, `jq` |
| **macOS** | Bash 4+ (`brew install bash`; the system Bash 3.2 is too old), Git via Xcode Command Line Tools or Homebrew (auto-handled) |
| **Windows** | Windows 10/11, **Windows PowerShell 5.1**, Git (auto-installed via `winget` or the official installer if missing) |

Tested on Kali Linux and Windows. The Bash engine is written for Debian, Ubuntu, Kali, RHEL/CentOS/Fedora, Arch and macOS package managers (`apt`, `dnf`, `pacman`, `brew`).

### 🐧 Linux / macOS

```bash
git clone https://github.com/ali4210/Git_Wizard_Ultimate.git
cd Git_Wizard_Ultimate
chmod +x autorun.sh
./autorun.sh
```

To install globally (adds `git-wizard` to `/usr/local/bin` and offers the optional tool stack):

```bash
./install.sh
```

Launcher flags:

| Flag | Effect |
|---|---|
| `./autorun.sh -f` | Flush the launcher cache (asks about `chafa` again) |
| `./autorun.sh --hard` | Reset Git-Wizard's own settings, history and launcher cache (asks for confirmation; installed tools and the PAT vault are never touched) |

### 🪟 Windows

```powershell
git clone https://github.com/ali4210/Git_Wizard_Ultimate.git
cd Git_Wizard_Ultimate
```

Then double-click **`autorun.bat`** (it launches PowerShell with `-ExecutionPolicy Bypass`), or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\git-wizard.ps1
```

> 💡 **Clone the repository rather than downloading a ZIP.** A ZIP has no Git history, which breaks self-update and the force-push rollback features.

---

## ▶️ Usage

1. `cd` into any Git repository (or an empty folder; Git-Wizard offers to `git init` it).
2. Run `git-wizard` (after enabling the Global CLI), or `./autorun.sh` / `autorun.bat`.
3. On first launch, choose **Beginner** (typed confirmations, Dry-Run on) or **Advanced** (fast confirmations, all workflows unlocked). You can switch any time in Settings.

**Typical first session**

```text
Main Menu → 1 → 3 → 3     SSH GitHub Manager → Setup End-to-End
Main Menu → 2 → 1         1-Click Complete Repo Setup
Main Menu → 4             Craft a conventional commit
Main Menu → 2 → 6         Smart Conflict Resolver (with rollback safety net)
```

---

## 🗂️ Configuration and Local Data

Everything Git-Wizard stores lives in one folder: `~/.git-wizard/` on Linux/macOS, `%USERPROFILE%\.git-wizard\` on Windows.

| Item | Purpose |
|---|---|
| `config` / `config.json` | Mode, Dry-Run, sync panel settings, update source, global CLI flag |
| `actions.log` | Timestamped history of executed and dry-run actions |
| `rollback/` | Per-repository state for the last force push and force pull |
| `pat_vault.env` | Local PAT vault (see [Security Notes](#-security-notes)) |

Backup and rollback points are ordinary Git tags (`backup/...`, `tool-backup-...`), so you can also inspect or restore them with plain Git.

---

## 🏗️ Architecture & Engineering Notes

- **Two native engines, one UX.** The Linux engine is a single Bash orchestrator; the Windows engine is a PowerShell orchestrator that dot-sources focused modules (`identity`, `repo`, `branch`, `commit`, `team`, `vcs`, `toolstack`, `conflict`), with import diagnostics shown in the header if a module fails to load.
- **Provider abstraction.** All hosting actions go through `vcs_*` / `Vcs-*` dispatchers, so GitHub and GitLab share the same menus while calling `gh` or `glab` underneath.
- **Self-healing dependencies.** Missing `git`, `gh`, `jq` and other tools are detected and installed on demand: native package manager first, prebuilt release binary second, with `PATH` refreshed in-process so no terminal restart is needed.
- **Failure isolation.** Commands that can legitimately fail (missing scope, 403, rate limit) run through a safe runner that reports the problem without crashing the tool. Global `errexit` was deliberately removed for this reason.
- **Terminal hygiene.** The Linux engine uses the alternate screen buffer and traps `INT`/`TERM`/`EXIT` to restore the cursor and terminal state; the Windows engine clears scrollback without leaving the main buffer to keep colour rendering reliable.
- **Idempotent, reversible changes.** PATH edits, symlinks and profile functions are added once and removed cleanly when the feature is disabled.
- **Windows encoding.** PowerShell 5.1 reads BOM-less files as ANSI, which breaks strings containing characters such as `—`. The `.ps1` modules are saved as **UTF-8 with BOM**.

---

## ⚖️ Linux vs Windows Parity

Core workflows behave the same on both platforms. A few extras are currently Linux-only:

| Feature | Linux | Windows |
|---|:---:|:---:|
| Identity, SSH, PAT vault, repo, branch, commit, team, hosting tools, delta suite | ✅ | ✅ |
| Force push / force pull rollback | ✅ | ✅ |
| Self-update, checkpoints, tool rollback | ✅ | ✅ |
| Live sync panel | ✅ | ✅ |
| Git CLI Hub (repo list and remote file browser) | ✅ | ➖ |
| `git-absorb`, `ghq`, local CI (`act` / `gitlab-ci-local`) | ✅ | ➖ |
| `lazygit` | ✅ | ✅ |
| Package installer | apt / dnf / pacman / brew + binary fallback | winget + binary fallback |

---

## 🔒 Security Notes

- **PAT vault:** tokens are stored in a local file (`pat_vault.env`) restricted to your user (`chmod 600` on Linux). The optional master password (SHA-256 hashed) gates access **inside the tool**; it does **not** encrypt the file. Treat the file like any other credential store, and prefer fine-grained tokens with minimal scope.
- **SSH keys** are generated as ED25519 with restrictive file permissions; uploads use the authenticated `gh` session.
- Git-Wizard never sends your credentials anywhere except to GitHub/GitLab through their official CLIs and APIs.
- Review destructive prompts carefully; backup tags reduce risk but are local to your machine.

---

## 📁 Repository Structure

```text
Git_Wizard_Ultimate/
├── autorun.sh                 # Linux/macOS launcher (+ optional chafa install, -f / --hard flags)
├── autorun.bat                # Windows launcher
├── install.sh                 # Global installer + optional tool stack
├── README.md
├── assets/
│   └── octocat.png            # Header image (rendered with chafa when available)
├── linux/
│   └── git-wizard.sh          # Bash engine (all modules)
└── modules/                   # Windows PowerShell engine
    ├── git-wizard.ps1         # Orchestrator, config, safety/backup engine, main menu
    ├── identity-engine.ps1    # Module 1: identity, SSH, PAT vault, gh auth
    ├── repo-engine.ps1        # Module 2: repo setup/destroy, reset, force sync
    ├── conflict-engine.ps1    # Smart Conflict Resolver + force push/pull rollback
    ├── branch-engine.ps1      # Module 3: arrow-key branch manager
    ├── commit-engine.ps1      # Module 4: conventional commits
    ├── team-engine.ps1        # Module 5: team and open-source workflows
    ├── vcs-engine.ps1         # Module 6: GitHub/GitLab layer, delta suite
    └── toolstack-engine.ps1   # Module 8: tool stack, self-update, pre-commit
```

---

## 🧭 Roadmap

- [ ] Add a `LICENSE` file and tagged GitHub Releases (enables the built-in update checker)
- [ ] CI: ShellCheck for the Bash engine and PSScriptAnalyzer for the PowerShell modules
- [ ] Windows parity for the Git CLI Hub and remaining bonus tools
- [ ] Multi-step rollback history (currently the most recent force push/pull per repo)
- [ ] Optional encrypted PAT storage

---

## 🤝 Contributing

Contributions, bug reports and feature requests are welcome.

1. Fork the repository and create a branch (`feature/your-idea` or `fix/your-bug`).
2. Keep Linux and Windows behaviour aligned where possible, and route destructive operations through the safety layer (`run_git` / `Invoke-GitWizard`, backup tags, confirmation prompts).
3. Open a Pull Request describing what changed and how you tested it.

---

## 👤 Author

**Saleem Ali**: DevOps / DevSecOps enthusiast and AIOps student, building practical automation tools.

- 🐙 GitHub: [github.com/ali4210](https://github.com/ali4210)
- 💼 LinkedIn: [linkedin.com/in/saleem-ali-189719325](https://www.linkedin.com/in/saleem-ali-189719325/)

If Git-Wizard saved you time (or a force push), consider giving the repo a ⭐.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for details.