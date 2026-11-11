# Bash regression tests (bats-core)

Focused regression tests for the Critical/High findings fixed on this branch
(D1, D4, D5, MAIN-6 from `AUDIT_REPORT.md`). This is not the full test suite
recommended in the audit report — just coverage for what changed here.

## Running

```sh
sudo apt install bats   # or: https://github.com/bats-core/bats-core
bats tests/bats/
```

## How these tests work

Each test pulls the real function(s) under test directly out of
`linux/git-wizard.sh` (or the relevant snippet out of `install.sh`) via
`tests/bats/helpers/extract_func.bash`, rather than reimplementing the logic
being tested — a regression in the real file is what actually fails these
tests. Git operations run against disposable repos created under
`$BATS_TEST_TMPDIR`; nothing touches the real system, a real GitHub account,
or this project's own working tree.

- `ssh-key-picker.bats` — D1: the arrow-key picker's missing `$` on `count`.
- `force-sync-stash.bats` — D4: Force Sync must stash dirty/untracked work
  before the hard reset, not just tag the current commit.
- `pat-vault-encryption.bats` — D5: the PAT vault must encrypt tokens at
  rest, fail closed without openssl, and migrate a legacy plaintext vault
  safely.
- `install-symlink.bats` — MAIN-6: a failing `sudo ln -sf` must not kill the
  installer silently.
