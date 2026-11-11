#!/usr/bin/env bats
# Regression tests for audit finding MAIN-6: install.sh kept `set -e` while
# the `sudo ln -sf` symlink step had no guard, so a sudo failure killed the
# whole installer silently before the optional tool-stack setup ever ran.
#
# The real symlink block is pulled directly out of install.sh (with
# /usr/local/bin textually redirected to a throwaway directory for test
# isolation — the control flow under test is unchanged) so this exercises
# the actual fix, not a reimplementation of it.

SCRIPT="$BATS_TEST_DIRNAME/../../install.sh"

setup() {
    TARGET_DIR="$BATS_TEST_TMPDIR/fake-usr-local-bin"
    mkdir -p "$TARGET_DIR"

    local start end_offset last
    start=$(grep -n '^# Symlink to /usr/local/bin' "$SCRIPT" | head -1 | cut -d: -f1)
    # The block is "if ... fi" (the symlink attempt) immediately followed by
    # "if [[ \"\$SYMLINK_OK\" != \"true\" ]]; then ... fi" (the error
    # message) — i.e. exactly two top-level "fi" lines.
    end_offset=$(tail -n +"$start" "$SCRIPT" | grep -n -m2 '^fi$' | tail -1 | cut -d: -f1)
    last=$((start + end_offset - 1))
    sed -n "${start},${last}p" "$SCRIPT" | sed "s#/usr/local/bin#${TARGET_DIR}#g" > "$BATS_TEST_TMPDIR/symlink_snippet.sh"
    bash -n "$BATS_TEST_TMPDIR/symlink_snippet.sh"

    STUBDIR="$BATS_TEST_TMPDIR/stubbin"
    mkdir -p "$STUBDIR"
}

@test "install.sh no longer sets -e" {
    ! grep -qE '^set -e' "$SCRIPT"
}

@test "a failing sudo prints a clear error and the script keeps going, instead of dying silently" {
    cat > "$STUBDIR/sudo" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$STUBDIR/sudo"
    chmod 555 "$TARGET_DIR" # not writable -> forces the sudo branch

    run env PATH="$STUBDIR:$PATH" SCRIPT_PATH="$BATS_TEST_TMPDIR/fake-git-wizard.sh" \
        bash -c '. "$1"; echo "REACHED_END"; echo "SYMLINK_OK=$SYMLINK_OK"' _ "$BATS_TEST_TMPDIR/symlink_snippet.sh"

    chmod 755 "$TARGET_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not create the global symlink"* ]]
    [[ "$output" == *"REACHED_END"* ]]
    [[ "$output" == *"SYMLINK_OK=false"* ]]
}

@test "a successful symlink still reports success and no error" {
    chmod 755 "$TARGET_DIR" # writable -> takes the direct ln -sf branch, no sudo involved
    touch "$BATS_TEST_TMPDIR/fake-git-wizard.sh"

    run env PATH="$STUBDIR:$PATH" SCRIPT_PATH="$BATS_TEST_TMPDIR/fake-git-wizard.sh" \
        bash -c '. "$1"; echo "REACHED_END"; echo "SYMLINK_OK=$SYMLINK_OK"' _ "$BATS_TEST_TMPDIR/symlink_snippet.sh"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Could not create the global symlink"* ]]
    [[ "$output" == *"SYMLINK_OK=true"* ]]
    [ -L "$TARGET_DIR/git-wizard" ]
}
