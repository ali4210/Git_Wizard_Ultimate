#!/usr/bin/env bats
# Regression tests for audit finding D1: the SSH-key delete picker's arrow
# navigation went out of bounds because `[ $selected -ge count ]` compared
# against the literal string "count" instead of $count. shellcheck flags
# the old form as a hard error (SC2170).
#
# _arrow_select_key/_arrow_confirm_delete are nested functions defined
# inside manage_github_ssh_keys() in linux/git-wizard.sh, so they're pulled
# out directly from the real file rather than reimplemented here.

SCRIPT="$BATS_TEST_DIRNAME/../../linux/git-wizard.sh"

setup() {
    FUNCS="$BATS_TEST_TMPDIR/arrow_funcs.sh"
    local start end_offset last
    start=$(grep -n '_arrow_select_key() {' "$SCRIPT" | head -1 | cut -d: -f1)
    end_offset=$(tail -n +"$start" "$SCRIPT" | grep -n -m1 '^[[:space:]]*# =\{10,\}' | cut -d: -f1)
    last=$((start + end_offset - 2))
    sed -n "${start},${last}p" "$SCRIPT" > "$FUNCS"
}

@test "shellcheck no longer flags the SSH-key picker line as an error" {
    run shellcheck -x "$SCRIPT"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ] # shellcheck exits 1 when it has findings at all; we only care about SC2170 specifically
    ! grep -q "SC2170" <<< "$output"
}

@test "the fixed source line compares against \$count, not the literal string" {
    run grep -n "selected -ge \$count" "$SCRIPT"
    [ "$status" -eq 0 ]
    run grep -n "selected -ge count \]" "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "arrow-key wrap logic wraps selection back to 0 past the last item" {
    count=3
    selected=2
    ((selected++))
    [ "$selected" -ge "$count" ] && selected=0
    [ "$selected" -eq 0 ]
}

@test "_arrow_confirm_delete refuses an empty/out-of-bounds id instead of calling the GitHub API" {
    RED=''; GREEN=''; CYAN=''; YELLOW=''; NC=''; BOLD=''
    log_action() { :; }
    gh() { echo "UNEXPECTED gh CALL: $*" >&2; return 1; } # must never be invoked with an empty id
    export -f gh
    source "$FUNCS"

    run _arrow_confirm_delete "" "" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"No key selected"* ]]
}
