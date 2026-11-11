#!/usr/bin/env bash
# Pulls one top-level bash function's source out of a larger script, from
# its "name() {" line up to (but not including) the next top-level
# "word() {" definition or "# ====" banner comment. Printed to stdout.
#
# This lets the bats tests exercise the REAL functions from linux/git-wizard.sh
# directly (with a few of their own real helper dependencies, like create_safety_backup
# and run_git, also extracted and sourced) instead of reimplementing the
# logic under test — so a regression in the real file is what actually
# fails these tests.
extract_func() {
    local file="$1" name="$2"
    local start end last
    start=$(grep -n "^${name}() {" "$file" | head -1 | cut -d: -f1)
    if [[ -z "$start" ]]; then
        echo "extract_func: '${name}' not found in ${file}" >&2
        return 1
    fi
    end=$(tail -n +"$((start + 1))" "$file" | grep -n -m1 -E '^[A-Za-z_][A-Za-z0-9_]*\(\) \{|^# =+' | cut -d: -f1)
    if [[ -z "$end" ]]; then
        sed -n "${start},\$p" "$file"
    else
        last=$((start + end - 1))
        sed -n "${start},${last}p" "$file"
    fi
}
