#!/usr/bin/env bats
# Regression tests for audit finding D5: the PAT vault stored tokens as
# plain "alias=token" text on disk, with the password/lock protecting
# nothing but the tool's own menu. The fix encrypts the vault at rest with
# openssl, keyed from the vault's master password (kept only in memory).
#
# The real encryption helpers are pulled directly out of linux/git-wizard.sh
# so this test exercises the actual fix, not a reimplementation of it.

load helpers/extract_func

SCRIPT="$BATS_TEST_DIRNAME/../../linux/git-wizard.sh"

setup() {
    if ! command -v openssl &>/dev/null; then
        skip "openssl not available in this environment"
    fi
    FUNCS="$BATS_TEST_TMPDIR/vault_funcs.sh"
    # _VAULT_MARKER is a bare variable assignment sitting between functions,
    # not a function itself, so extract_func can't grab it — pull it from
    # the real file directly instead of hardcoding a possibly-stale copy.
    grep -m1 '^_VAULT_MARKER=' "$SCRIPT" >> "$FUNCS"
    for fn in _vault_file_is_encrypted _vault_encrypt_write _vault_decrypt_read _vault_migrate_if_needed; do
        extract_func "$SCRIPT" "$fn" >> "$FUNCS"
        echo "" >> "$FUNCS"
    done
    bash -n "$FUNCS"

    RED=''; GREEN=''; CYAN=''; YELLOW=''; NC=''; BOLD=''
    log_action() { :; }
    source "$FUNCS"

    VAULT_FILE="$BATS_TEST_TMPDIR/pat_vault.env"
    : > "$VAULT_FILE"
}

@test "saving a token round-trips: ciphertext on disk, correct plaintext on read" {
    VAULT_SESSION_KEY="correct-horse-battery-staple"
    run _vault_encrypt_write "myalias=ghp_realtoken123"
    [ "$status" -eq 0 ]

    # The on-disk file must start with openssl's "Salted__" header and must
    # NOT contain the plaintext token anywhere in it.
    run bash -c 'head -c 8 "$1"' _ "$VAULT_FILE"
    [ "$output" = "Salted__" ]
    ! grep -q "ghp_realtoken123" "$VAULT_FILE"

    run _vault_decrypt_read
    [ "$status" -eq 0 ]
    [ "$output" = "myalias=ghp_realtoken123" ]
}

@test "the wrong vault password does not leak the token back" {
    VAULT_SESSION_KEY="the-real-password"
    _vault_encrypt_write "myalias=ghp_realtoken123"

    VAULT_SESSION_KEY="a-wrong-guess"
    run _vault_decrypt_read
    # Must not return the real token under a wrong password, whether that
    # shows up as a clean failure or empty output.
    [[ "$output" != *"ghp_realtoken123"* ]]
}

@test "a legacy plaintext vault is transparently migrated to encrypted storage, with no data loss" {
    printf 'legacy1=ghp_legacytoken\nlegacy2=ghp_secondtoken\n' > "$VAULT_FILE"
    ! grep -q "Salted__" <(head -c 8 "$VAULT_FILE")

    VAULT_SESSION_KEY="new-session-password"
    run _vault_migrate_if_needed
    [ "$status" -eq 0 ]

    run bash -c 'head -c 8 "$1"' _ "$VAULT_FILE"
    [ "$output" = "Salted__" ]
    ! grep -q "ghp_legacytoken" "$VAULT_FILE"
    ! grep -q "ghp_secondtoken" "$VAULT_FILE"

    run _vault_decrypt_read
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy1=ghp_legacytoken"* ]]
    [[ "$output" == *"legacy2=ghp_secondtoken"* ]]
}

@test "migration never touches an already-encrypted vault file" {
    VAULT_SESSION_KEY="some-password"
    _vault_encrypt_write "alias=ghp_abc"
    before_sum=$(sha256sum "$VAULT_FILE" | awk '{print $1}')

    run _vault_migrate_if_needed
    [ "$status" -eq 0 ]
    after_sum=$(sha256sum "$VAULT_FILE" | awk '{print $1}')
    [ "$before_sum" = "$after_sum" ]
}

@test "saving a token fails closed (does not fall back to plaintext) when openssl is unavailable" {
    VAULT_SESSION_KEY="whatever"
    run bash -c '
        PATH="$2"
        . "$1"
        _vault_encrypt_write "alias=ghp_shouldnotpersist"
    ' _ "$FUNCS" "$BATS_TEST_TMPDIR/empty-path-stand-in"
    [ "$status" -ne 0 ]
    [ ! -s "$VAULT_FILE" ]
}
