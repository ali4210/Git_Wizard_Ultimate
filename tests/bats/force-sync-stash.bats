#!/usr/bin/env bats
# Regression tests for audit finding D4: force_sync_with_origin used to
# create a backup TAG (commits only) and then run `reset --hard` + `clean
# -fd`, permanently destroying any uncommitted/untracked work with a
# misleading "a backup tag is created first" message. The fix stashes dirty
# state first. This test proves BOTH a dirty tracked-file edit AND an
# untracked file survive via the stash and are recoverable with
# `git stash pop` — not just one or the other.
#
# force_sync_with_origin and the real helpers it calls are pulled directly
# out of linux/git-wizard.sh so this test exercises the actual fix, not a
# reimplementation of it.

load helpers/extract_func

SCRIPT="$BATS_TEST_DIRNAME/../../linux/git-wizard.sh"

setup() {
    FUNCS="$BATS_TEST_TMPDIR/force_sync_funcs.sh"
    for fn in log_action run_git create_safety_backup confirm_destructive force_sync_with_origin; do
        extract_func "$SCRIPT" "$fn" >> "$FUNCS"
        echo "" >> "$FUNCS"
    done
    bash -n "$FUNCS"

    REPO="$BATS_TEST_TMPDIR/repo"
    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    mkdir -p "$REPO"
    git -C "$REPO" init -q -b main
    git -C "$REPO" config user.email t@t.com
    git -C "$REPO" config user.name t
    echo "committed" > "$REPO/f.txt"
    git -C "$REPO" add f.txt
    git -C "$REPO" commit -qm c1
    git clone -q --bare "$REPO" "$ORIGIN"
    git -C "$REPO" remote add origin "$ORIGIN"
    git -C "$REPO" fetch -q origin
}

@test "force_sync_with_origin stashes a dirty tracked edit AND an untracked file instead of destroying them" {
    cd "$REPO" || return 1
    echo "dirty edit" >> f.txt
    echo "new untracked" > untracked.txt

    run bash -c '
        RED=""; GREEN=""; CYAN=""; YELLOW=""; NC=""; BOLD=""
        DRY_RUN=false
        WIZARD_MODE=advanced
        ACTION_LOG="$2"
        : > "$ACTION_LOG"
        show_header() { :; }
        pause() { :; }
        . "$1"
        echo y | force_sync_with_origin
    ' _ "$FUNCS" "$BATS_TEST_TMPDIR/action.log"
    [[ "$output" == *"Uncommitted/untracked files saved in stash"* ]]

    # The destructive reset+clean still ran: f.txt is back to committed-only
    # content and the untracked file is gone from the working tree...
    [ "$(cat f.txt)" = "committed" ]
    [ ! -f untracked.txt ]

    # ...but both are recoverable from the stash the fix created.
    run git stash list
    [[ "$output" == *"gw-force-sync-main-"* ]]

    git stash pop
    [ -f untracked.txt ]
    grep -q "dirty edit" f.txt
}
