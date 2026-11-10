# shellcheck shell=bash
# This module communicates with its callers (and Stage 3+ screens in this
# same file) through global WS_* variables rather than return values, the
# same pattern linux/git-wizard.sh already uses (e.g. SELECTED_BRANCH from
# select_branch_interactive). shellcheck can't see those cross-function
# reads, so SC2034 ("appears unused") is a false positive throughout.
# shellcheck disable=SC2034
# ==============================================================================
# MODULE:       linux/workspace-explorer.sh (Workspace Explorer — Linux Engine)
# AUTHOR:       Saleem (Open Source DevOps/Sec Contributor)
# DESCRIPTION:  One keyboard-driven explorer over "git status" + diff + file
#               history + project history, with guided, reversible reverts.
#               Sourced by linux/git-wizard.sh. Depends on helpers already
#               defined there: run_git, create_safety_backup, confirm_destructive,
#               log_action, show_header, pause, and the color constants
#               (RED/GREEN/YELLOW/CYAN/BOLD/NC).
#
# STAGE 1 OF 6: Git data-layer functions only (no UI yet). Every function
# below reads repo state and returns it through global WS_* arrays/vars so
# callers avoid subshells (which would lose variable writes). Nothing here
# mutates the repo except the two WS_REVERT_* action helpers, and those always
# go through run_git / create_safety_backup like the rest of the tool.
# ==============================================================================

# ------------------------------------------------------------------------------
# WS_STATUS_* — parsed `git status --porcelain=v1 -z` entries.
# Parallel arrays indexed 0..WS_STATUS_COUNT-1:
#   WS_STATUS_X[i]      staged-side status letter (M/A/D/R/C/U/?/space)
#   WS_STATUS_Y[i]      worktree-side status letter
#   WS_STATUS_PATH[i]   current path (new path, for renames)
#   WS_STATUS_ORIG[i]   original path if this is a rename/copy, else ""
#   WS_STATUS_BADGE[i]  short human badge: "modified" | "staged" | "deleted" |
#                        "untracked" | "renamed" | "added" | "conflict"
# ------------------------------------------------------------------------------
ws_load_status() {
    WS_STATUS_X=()
    WS_STATUS_Y=()
    WS_STATUS_PATH=()
    WS_STATUS_ORIG=()
    WS_STATUS_BADGE=()

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        WS_STATUS_COUNT=0
        return 1
    fi

    # Stream NUL-delimited records straight off the pipe — do NOT buffer the
    # whole thing through a `var=$(...)` capture first: bash variables cannot
    # hold embedded NUL bytes, so a capture silently drops every record
    # boundary and the parse loop below would see one giant empty token.
    # A rename/copy record is followed by a second NUL-delimited field (the
    # original path), read here as a second `read` on the same stream.
    local entry xy x y path orig badge
    while IFS= read -r -d '' entry; do
        [[ -z "$entry" ]] && continue
        xy="${entry:0:2}"
        x="${xy:0:1}"
        y="${xy:1:1}"
        path="${entry:3}"
        orig=""

        if [[ "$x" == "R" || "$x" == "C" ]]; then
            IFS= read -r -d '' orig
        fi

        if [[ "$x" == "U" || "$y" == "U" || ( "$x" == "A" && "$y" == "A" ) || ( "$x" == "D" && "$y" == "D" ) ]]; then
            badge="conflict"
        elif [[ "$x" == "?" && "$y" == "?" ]]; then
            badge="untracked"
        elif [[ "$x" == "R" ]]; then
            badge="renamed"
        elif [[ "$x" == "A" ]]; then
            badge="added"
        elif [[ "$y" == "D" ]]; then
            badge="deleted"
        elif [[ "$x" != " " && "$x" != "?" ]]; then
            badge="staged"
        else
            badge="modified"
        fi

        WS_STATUS_X+=("$x")
        WS_STATUS_Y+=("$y")
        WS_STATUS_PATH+=("$path")
        WS_STATUS_ORIG+=("$orig")
        WS_STATUS_BADGE+=("$badge")
    done < <(git status --porcelain=v1 -z 2>/dev/null)
    # WS_STATUS_COUNT is read by the UI layer (Stage 2+), not within this file.
    # shellcheck disable=SC2034
    WS_STATUS_COUNT=${#WS_STATUS_PATH[@]}
    return 0
}

# ------------------------------------------------------------------------------
# ws_file_diff <path> [--staged]
# Prints a diff for one file to stdout. Handles untracked files (no-index),
# staged vs unstaged, and deleted files. Caller pipes this into delta_view.
# ------------------------------------------------------------------------------
ws_file_diff() {
    local path="$1"
    local mode="${2:-}"
    local is_untracked="false"
    local i
    for i in "${!WS_STATUS_PATH[@]}"; do
        if [[ "${WS_STATUS_PATH[$i]}" == "$path" && "${WS_STATUS_BADGE[$i]}" == "untracked" ]]; then
            is_untracked="true"
            break
        fi
    done

    if [[ "$is_untracked" == "true" ]]; then
        git diff --no-index --color=always -- /dev/null "$path" 2>/dev/null
        return 0
    fi

    if [[ "$mode" == "--staged" ]]; then
        git diff --cached --color=always -- "$path"
    else
        git diff --color=always -- "$path"
        # A file can be dirty in BOTH the index and the worktree at once
        # (e.g. staged a change, then edited again). Show the staged part
        # too so nothing is silently hidden from the viewer.
        local staged_part
        staged_part=$(git diff --cached --color=always -- "$path")
        if [[ -n "$staged_part" ]]; then
            echo ""
            echo -e "${CYAN}${BOLD}--- Also staged for commit ---${NC}"
            echo "$staged_part"
        fi
    fi
}

# ------------------------------------------------------------------------------
# ws_revert_target_last_commit <path>
# Echoes nothing; caller runs the restore directly (no hash needed — HEAD).
# Kept as a thin wrapper so the three revert actions have parallel call sites.
# ------------------------------------------------------------------------------
ws_revert_to_last_commit() {
    local path="$1"
    create_safety_backup "pre-revert-lastcommit"
    run_git restore --source=HEAD --staged --worktree -- "$path"
}

# ------------------------------------------------------------------------------
# ws_hash_before_last_change <path>
# Echoes the commit hash for "the version before the file's last change",
# i.e. the second entry of `git log -n 2 --format=%H -- path`. Empty if the
# file has fewer than 2 commits touching it (nothing "before" to go to).
# ------------------------------------------------------------------------------
ws_hash_before_last_change() {
    local path="$1"
    git log -n 2 --format=%H -- "$path" 2>/dev/null | sed -n '2p'
}

ws_revert_to_before_last_change() {
    local path="$1"
    local hash
    hash=$(ws_hash_before_last_change "$path")
    if [[ -z "$hash" ]]; then
        return 1
    fi
    create_safety_backup "pre-revert-prior-version"
    run_git restore --source="$hash" --worktree -- "$path"
    run_git add -- "$path"
}

# ------------------------------------------------------------------------------
# ws_hash_original_add <path>
# Echoes the commit hash that first added this exact path (git's --diff-filter=A
# on the current path — matches a rename's "add" event for the new name, per
# spec). Empty if not found (e.g. path never existed, or is itself uncommitted).
# ------------------------------------------------------------------------------
ws_hash_original_add() {
    local path="$1"
    git log --diff-filter=A --format=%H -- "$path" 2>/dev/null | tail -n 1
}

ws_revert_to_original_state() {
    local path="$1"
    local hash
    hash=$(ws_hash_original_add "$path")
    if [[ -z "$hash" ]]; then
        return 1
    fi
    create_safety_backup "pre-revert-original"
    run_git restore --source="$hash" --worktree -- "$path"
    run_git add -- "$path"
}

# ------------------------------------------------------------------------------
# ws_delete_untracked <path>
# Untracked files have no commit to fall back to, so this is intentionally
# its OWN action (never folded into "revert"), with its own stricter confirm
# at the call site. No backup tag is possible (nothing committed to tag), so
# the caller must warn the user this is NOT like the other revert actions.
# ------------------------------------------------------------------------------
ws_delete_untracked() {
    local path="$1"
    run_git clean -f -- "$path"
}

# ------------------------------------------------------------------------------
# ws_file_log <path> — all commits touching this path across renames, newest
# first. Each line: "<hash>\x1f<author>\x1f<relative-date>\x1f<subject>"
# Uses \x1f (unit separator) so subjects containing '|' don't break parsing.
# ------------------------------------------------------------------------------
ws_file_log() {
    local path="$1"
    local limit="${2:-50}"
    local skip="${3:-0}"
    git log --follow --format='%H%x1f%an%x1f%ar%x1f%s' --skip="$skip" -n "$limit" -- "$path" 2>/dev/null
}

ws_file_log_count() {
    local path="$1"
    git log --follow --format='%H' -- "$path" 2>/dev/null | wc -l | tr -d ' '
}

# ------------------------------------------------------------------------------
# ws_project_log — all repo commits, newest first, same field format as
# ws_file_log (no path filter).
# ------------------------------------------------------------------------------
ws_project_log() {
    local limit="${1:-50}"
    local skip="${2:-0}"
    git log --format='%H%x1f%an%x1f%ar%x1f%s' --skip="$skip" -n "$limit" 2>/dev/null
}

ws_project_log_count() {
    git rev-list --count HEAD 2>/dev/null
}

# ------------------------------------------------------------------------------
# ws_commit_summary <hash> — stats + message for the Project Timeline detail
# screen. Prints directly (caller shows it in a pager-like view).
# ------------------------------------------------------------------------------
ws_commit_summary() {
    local hash="$1"
    git show --stat --format='%H%n%an <%ae>%n%ad%n%n%s%n%n%b' --date=relative "$hash" 2>/dev/null
}

# ------------------------------------------------------------------------------
# ws_commit_files <hash> — list of files touched by a commit, one per line.
# ------------------------------------------------------------------------------
ws_commit_files() {
    local hash="$1"
    git diff-tree --no-commit-id --name-only -r "$hash" 2>/dev/null
}

# ------------------------------------------------------------------------------
# ws_commit_file_diff <hash> <path> — that commit's change to one file.
# ------------------------------------------------------------------------------
ws_commit_file_diff() {
    local hash="$1"
    local path="$2"
    git show --color=always "$hash" -- "$path" 2>/dev/null
}

# ------------------------------------------------------------------------------
# Commit-level actions (used by File Timeline and Project Timeline screens).
# All go through run_git / create_safety_backup for dry-run + backup parity.
# ------------------------------------------------------------------------------
ws_apply_commit_file_to_current() {
    local hash="$1"
    local path="$2"
    create_safety_backup "pre-apply-commit-file"
    git show "$hash" -- "$path" | git apply --3way 2>&1
}

ws_restore_file_to_commit() {
    local hash="$1"
    local path="$2"
    create_safety_backup "pre-restore-file-to-commit"
    run_git restore --source="$hash" --worktree -- "$path"
    run_git add -- "$path"
}

ws_undo_file_change_in_commit() {
    local hash="$1"
    local path="$2"
    create_safety_backup "pre-undo-file-change"
    git show "$hash" -- "$path" | git apply -R --3way 2>&1
}

ws_revert_commit_safe() {
    local hash="$1"
    create_safety_backup "pre-revert-commit"
    run_git revert --no-edit "$hash"
}

# ------------------------------------------------------------------------------
# ws_is_binary_file <path> — true if git thinks this path's content is binary
# (used to suppress diff rendering and show a placeholder instead).
# ------------------------------------------------------------------------------
ws_is_binary_file() {
    local path="$1"
    if [[ -f "$path" ]]; then
        if ! LC_ALL=C grep -Iq . "$path" 2>/dev/null; then
            return 0
        fi
        return 1
    fi
    # Deleted/not-on-disk: ask git's own binary detection via numstat ("-" columns).
    local numstat
    numstat=$(git diff --numstat -- "$path" 2>/dev/null | head -n1)
    if [[ "$numstat" == -$'\t'-* ]]; then
        return 0
    fi
    return 1
}

# ==============================================================================
# STAGE 2 OF 6: NAVIGATION ENGINE — the shared key-reader, breadcrumb, action
# bar, and generic list browser used by every Workspace Explorer screen
# (Changes list, File Timeline list, Project Timeline list).
# ==============================================================================

# ------------------------------------------------------------------------------
# ws_show_header — lightweight header for the Explorer. Deliberately NOT the
# full show_header() banner: the Explorer redraws on every keystroke and is
# data-dense (lists, diffs, commit logs), so a ~50-line ASCII banner on every
# frame would push content off most terminals. Mode/Dry-Run/repo context are
# still shown, in the same colors/format as show_header, so nothing is hidden.
# ------------------------------------------------------------------------------
ws_show_header() {
    clear
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
    echo -e "${CYAN}${BOLD}  🧙 WORKSPACE EXPLORER${NC}   ${YELLOW}Mode:${NC} ${WIZARD_MODE^}   ${YELLOW}Dry-Run:${NC} ${DRY_RUN}"
    echo -e "${CYAN}${BOLD}====================================================================${NC}"
}

# ws_draw_breadcrumb — WS_BREADCRUMB is a bash array of path segments set by
# the caller, e.g. WS_BREADCRUMB=("Changes" "src/app.py" "History").
ws_draw_breadcrumb() {
    local joined="" seg
    for seg in "${WS_BREADCRUMB[@]}"; do
        if [[ -z "$joined" ]]; then
            joined="$seg"
        else
            joined="${joined} ${CYAN}›${NC} ${BOLD}${seg}${NC}"
        fi
    done
    echo -e "${YELLOW}${BOLD}${joined}${NC}"
    echo ""
}

# ws_draw_action_bar <bar text, already formatted with "[key] label" pairs>
ws_draw_action_bar() {
    echo ""
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"
    echo -e "$1"
}

# ------------------------------------------------------------------------------
# ws_read_key — single normalized key read. Blocks until one logical key is
# read. Distinguishes a standalone Esc press from an Esc-prefixed arrow
# sequence via a short read timeout: a real escape sequence arrives from the
# terminal as a burst of bytes, while a lone Esc keypress has nothing
# following it, so a short timeout tells the two apart without ever hanging.
# Sets WS_LAST_KEY to one of: UP DOWN LEFT RIGHT ENTER ESC SPACE SLASH QMARK
# Q EOF CHAR:<c>. NOTE: sets a global rather than echoing a return value on
# purpose — callers must invoke it as a plain statement (`ws_read_key`, then
# read $WS_LAST_KEY), NEVER as `key=$(ws_read_key)`. Command substitution
# forks a subshell, and WS_KEY_PUSHBACK below (and the EOF/timeout reads)
# only works if mutations to it survive across calls in the SAME shell; a
# subshell would silently discard them every time, reintroducing the exact
# bug this buffer exists to fix.
#
# WS_KEY_PUSHBACK: a one-byte lookahead buffer. Telling a standalone Esc
# apart from an Esc-prefixed arrow sequence means peeking at the NEXT byte;
# when that byte turns out NOT to start a sequence ("[") it's a real,
# independent keypress of its own (commonly: the user pressed Esc twice in
# a row fast enough that both bytes were already waiting in the input
# buffer) and must be replayed on the next call, not discarded — otherwise
# two quick Esc presses silently collapse into one, and any keypress that
# happens to land right after an Esc can vanish entirely.
# ------------------------------------------------------------------------------
WS_KEY_PUSHBACK=""
WS_LAST_KEY=""

ws_read_key() {
    local k rest
    if [[ -n "$WS_KEY_PUSHBACK" ]]; then
        k="$WS_KEY_PUSHBACK"
        WS_KEY_PUSHBACK=""
    elif ! IFS= read -rsn1 k; then
        # stdin closed (EOF) rather than a real keypress -- e.g. the
        # process's input was piped and the pipe ended. `read` returns k=""
        # on EOF the same way it does for a real Enter keypress, so without
        # this check the navigator would misread EOF as an endless stream of
        # Enter presses and spin forever instead of exiting cleanly.
        WS_LAST_KEY="EOF"
        return 0
    fi
    if [[ "$k" == $'\x1b' ]]; then
        if IFS= read -rsn1 -t 0.05 rest; then
            if [[ "$rest" == "[" ]]; then
                # Arrow keys end in a single letter (A/B/C/D). Home/End/
                # PageUp/PageDown vary by terminal: either a single letter
                # (H/F) or one-or-more digits followed by '~' (xterm/vt220
                # style: 1~/7~=Home, 4~/8~=End, 5~=PageUp, 6~=PageDown).
                # Read until we hit a letter or '~', accumulating digits.
                local seq="" c
                while IFS= read -rsn1 -t 0.05 c; do
                    seq+="$c"
                    [[ "$c" == [A-Za-z~] ]] && break
                done
                case "$seq" in
                    A) WS_LAST_KEY="UP" ;;
                    B) WS_LAST_KEY="DOWN" ;;
                    C) WS_LAST_KEY="RIGHT" ;;
                    D) WS_LAST_KEY="LEFT" ;;
                    H) WS_LAST_KEY="HOME" ;;
                    F) WS_LAST_KEY="END" ;;
                    1~|7~) WS_LAST_KEY="HOME" ;;
                    4~|8~) WS_LAST_KEY="END" ;;
                    5~) WS_LAST_KEY="PGUP" ;;
                    6~) WS_LAST_KEY="PGDN" ;;
                    *) WS_LAST_KEY="ESC" ;;
                esac
            else
                WS_KEY_PUSHBACK="$rest"
                WS_LAST_KEY="ESC"
            fi
        else
            WS_LAST_KEY="ESC"
        fi
    elif [[ "$k" == "" ]]; then
        WS_LAST_KEY="ENTER"
    elif [[ "$k" == " " ]]; then
        WS_LAST_KEY="SPACE"
    elif [[ "$k" == "/" ]]; then
        WS_LAST_KEY="SLASH"
    elif [[ "$k" == "?" ]]; then
        WS_LAST_KEY="QMARK"
    elif [[ "$k" == "q" || "$k" == "Q" ]]; then
        WS_LAST_KEY="Q"
    else
        WS_LAST_KEY="CHAR:$k"
    fi
}

# ------------------------------------------------------------------------------
# ws_list_navigate — generic interactive list browser.
#
# INPUTS (set by caller before calling):
#   WS_NAV_ITEMS           array of pre-formatted display strings (one per
#                          row; ANSI color already applied by the caller)
#   WS_NAV_TITLE           header text shown above the list
#   WS_NAV_MARKABLE        "true"/"false" — enables Space-to-mark
#   WS_NAV_FILTERABLE      "true"/"false" — enables "/" filtering
#   WS_NAV_HELP_TEXT       multi-line help text shown on "?"
#   WS_NAV_EXTRA_BAR       extra "[key] label" text appended to the action
#                          bar (e.g. per-screen hints), or "" for none
#   WS_NAV_MARKED_INDICES  caller-owned array of already-marked ORIGINAL
#                          indices (persists marks across repeated calls on
#                          the same screen — initialize to () the first time)
#   WS_NAV_EXTRA_KEYS      string of extra single characters the caller wants
#                          surfaced (e.g. "RMU" for per-screen batch actions
#                          like Revert-all/Revert-Marked/Undo); any other
#                          unrecognized character is silently ignored
#
# OPTIONAL INPUTS (all default to the prior, unchanged behavior when a
# caller never sets them — existing screens need no changes):
#   WS_NAV_VIEWPORT          "true" to clip rendering to the terminal height
#                            and scroll (Up/Down/PgUp/PgDn/Home/End move a
#                            viewport window) instead of printing every item
#                            every redraw. Default "false": every item is
#                            printed unconditionally, exactly as before —
#                            needed for large lists (hundreds-thousands of
#                            files), overkill and visually unchanged for the
#                            short lists every existing screen uses.
#   WS_NAV_CASE_INSENSITIVE  "true" for a case-insensitive "/" filter.
#                            Default "false" (existing exact-match behavior).
#   WS_NAV_INITIAL_CURSOR    an ORIGINAL index to start the cursor on, or
#                            unset/-1 for the default (top of the list).
#   WS_NAV_INITIAL_FILTER    filter text to pre-apply on entry, or unset/""
#                            for none. Lets a caller restore where the user
#                            was after a round trip into a sub-screen.
#   WS_NAV_ITEM_NOUN         noun used in the viewport's live count line
#                            (e.g. "files"); default "items".
#
# OUTPUTS (set on return):
#   WS_NAV_RESULT          "open" | "back" | "quit" | "key:<c>" (one of
#                          WS_NAV_EXTRA_KEYS was pressed)
#   WS_NAV_SELECTED        index into WS_NAV_ITEMS (ORIGINAL, unfiltered)
#   WS_NAV_MARKED_INDICES  updated in place as the user presses Space
#   WS_NAV_LAST_FILTER     the filter text in effect when the screen was
#                          left (for a caller that wants to restore it via
#                          WS_NAV_INITIAL_FILTER on the next call)
# ------------------------------------------------------------------------------
ws_list_navigate() {
    local cursor=0
    local filter_text="${WS_NAV_INITIAL_FILTER:-}"
    local filter_mode="false"
    local -a visible_idx=()
    local i m row vi marker key
    local viewport="${WS_NAV_VIEWPORT:-false}"
    local ci="${WS_NAV_CASE_INSENSITIVE:-false}"
    local view_offset=0

    _ws_nav_rebuild_visible() {
        visible_idx=()
        local needle="$filter_text"
        [[ "$ci" == "true" ]] && needle="${needle,,}"
        for i in "${!WS_NAV_ITEMS[@]}"; do
            if [[ -z "$filter_text" ]]; then
                visible_idx+=("$i")
            elif [[ "$ci" == "true" ]]; then
                local hay="${WS_NAV_ITEMS[$i],,}"
                [[ "$hay" == *"$needle"* ]] && visible_idx+=("$i")
            elif [[ "${WS_NAV_ITEMS[$i]}" == *"$filter_text"* ]]; then
                visible_idx+=("$i")
            fi
        done
    }
    _ws_nav_rebuild_visible

    # Resolve an optional starting cursor (an ORIGINAL index) to its row in
    # the (possibly filtered) visible list, so a caller can restore where
    # the user was after a round trip into a sub-screen. Falls back to the
    # top of the list if that index is gone or wasn't requested.
    if [[ -n "${WS_NAV_INITIAL_CURSOR:-}" && "${WS_NAV_INITIAL_CURSOR}" -ge 0 ]] 2>/dev/null; then
        for row in "${!visible_idx[@]}"; do
            if [[ "${visible_idx[$row]}" == "$WS_NAV_INITIAL_CURSOR" ]]; then
                cursor=$row
                break
            fi
        done
    fi

    tput civis 2>/dev/null || true
    while true; do
        if [[ ${#visible_idx[@]} -eq 0 ]]; then
            cursor=0
        elif [[ $cursor -ge ${#visible_idx[@]} ]]; then
            cursor=$(( ${#visible_idx[@]} - 1 ))
        elif [[ $cursor -lt 0 ]]; then
            cursor=0
        fi

        local rows visible_rows
        rows=$(tput lines 2>/dev/null || echo 24)
        visible_rows=$((rows - 10))
        [[ $visible_rows -lt 3 ]] && visible_rows=3

        ws_show_header
        ws_draw_breadcrumb
        echo -e "${YELLOW}${BOLD}${WS_NAV_TITLE}${NC}\n"

        if [[ ${#visible_idx[@]} -eq 0 ]]; then
            if [[ -n "$filter_text" ]]; then
                echo -e "${CYAN}(no items matching \"${filter_text}\")${NC}"
            else
                echo -e "${CYAN}(nothing here)${NC}"
            fi
        elif [[ "$viewport" == "true" ]]; then
            # Opt-in only (see header note) — clip rendering to the terminal
            # height and keep the cursor in view, instead of printing every
            # item every redraw. Everything below is skipped entirely for
            # existing callers (Changes, File/Project Timeline), which never
            # set WS_NAV_VIEWPORT, so their rendering is byte-for-byte the
            # same as before this was added.
            local total=${#visible_idx[@]}
            if [[ $cursor -lt $view_offset ]]; then view_offset=$cursor; fi
            if [[ $cursor -ge $((view_offset + visible_rows)) ]]; then
                view_offset=$((cursor - visible_rows + 1))
            fi
            [[ $view_offset -lt 0 ]] && view_offset=0
            if [[ $((view_offset + visible_rows)) -gt $total ]]; then
                view_offset=$((total - visible_rows))
                [[ $view_offset -lt 0 ]] && view_offset=0
            fi

            local shown=0
            for ((row = view_offset; row < total && shown < visible_rows; row++)); do
                vi="${visible_idx[$row]}"
                marker="  "
                for m in "${WS_NAV_MARKED_INDICES[@]}"; do
                    [[ "$m" == "$vi" ]] && marker="${GREEN}${BOLD}*${NC} "
                done
                if [[ $row -eq $cursor ]]; then
                    echo -e "${marker}${GREEN}${BOLD}➔ ${WS_NAV_ITEMS[$vi]}${NC}"
                else
                    echo -e "${marker}  ${WS_NAV_ITEMS[$vi]}"
                fi
                ((shown++))
            done
            local noun="${WS_NAV_ITEM_NOUN:-items}"
            local unfiltered_total=${#WS_NAV_ITEMS[@]}
            local count_text
            if [[ $total -ne $unfiltered_total ]]; then
                count_text="${total} of ${unfiltered_total} ${noun}"
            else
                count_text="${total} ${noun}"
            fi
            if [[ $total -gt $visible_rows ]]; then
                count_text="${count_text}  (showing $((view_offset + 1))-$((view_offset + shown)))"
            fi
            echo -e "\n${CYAN}${count_text}${NC}"
        else
            for row in "${!visible_idx[@]}"; do
                vi="${visible_idx[$row]}"
                marker="  "
                for m in "${WS_NAV_MARKED_INDICES[@]}"; do
                    [[ "$m" == "$vi" ]] && marker="${GREEN}${BOLD}*${NC} "
                done
                if [[ $row -eq $cursor ]]; then
                    echo -e "${marker}${GREEN}${BOLD}➔ ${WS_NAV_ITEMS[$vi]}${NC}"
                else
                    echo -e "${marker}  ${WS_NAV_ITEMS[$vi]}"
                fi
            done
        fi

        if [[ "$filter_mode" == "true" ]]; then
            echo ""
            echo -e "${YELLOW}Filter:${NC} ${filter_text}${CYAN}_${NC}  ${CYAN}(Enter to apply, Esc to cancel)${NC}"
        fi

        local bar="${CYAN}[↑↓]${NC} Move  ${CYAN}[Enter/→]${NC} Open  ${CYAN}[Esc/←]${NC} Back"
        [[ "$WS_NAV_MARKABLE" == "true" ]] && bar="${bar}  ${CYAN}[Space]${NC} Mark"
        [[ "$WS_NAV_FILTERABLE" == "true" ]] && bar="${bar}  ${CYAN}[/]${NC} Filter"
        [[ "$viewport" == "true" ]] && bar="${bar}  ${CYAN}[PgUp/PgDn/Home/End]${NC} Scroll"
        bar="${bar}  ${CYAN}[?]${NC} Help  ${CYAN}[q]${NC} Quit"
        [[ -n "$WS_NAV_EXTRA_BAR" ]] && bar="${bar}\n${WS_NAV_EXTRA_BAR}"
        ws_draw_action_bar "$bar"

        if [[ "$filter_mode" == "true" ]]; then
            if ! IFS= read -rsn1 key; then
                tput cnorm 2>/dev/null || true
                WS_NAV_RESULT="quit"
                return 0
            fi
            if [[ "$key" == "" ]]; then
                filter_mode="false"
            elif [[ "$key" == $'\x1b' ]]; then
                filter_text=""
                filter_mode="false"
                _ws_nav_rebuild_visible
            elif [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
                filter_text="${filter_text%?}"
                _ws_nav_rebuild_visible
            else
                filter_text="${filter_text}${key}"
                _ws_nav_rebuild_visible
            fi
            continue
        fi

        ws_read_key
        key="$WS_LAST_KEY"
        case "$key" in
            UP)
                if [[ ${#visible_idx[@]} -gt 0 ]]; then
                    ((cursor--)) || true
                    [[ $cursor -lt 0 ]] && cursor=$(( ${#visible_idx[@]} - 1 ))
                fi
                ;;
            DOWN)
                if [[ ${#visible_idx[@]} -gt 0 ]]; then
                    ((cursor++)) || true
                    [[ $cursor -ge ${#visible_idx[@]} ]] && cursor=0
                fi
                ;;
            HOME)
                cursor=0
                ;;
            END)
                [[ ${#visible_idx[@]} -gt 0 ]] && cursor=$(( ${#visible_idx[@]} - 1 ))
                ;;
            PGUP)
                ((cursor -= visible_rows)) || true
                [[ $cursor -lt 0 ]] && cursor=0
                ;;
            PGDN)
                ((cursor += visible_rows)) || true
                if [[ ${#visible_idx[@]} -gt 0 && $cursor -ge ${#visible_idx[@]} ]]; then
                    cursor=$(( ${#visible_idx[@]} - 1 ))
                fi
                ;;
            ENTER|RIGHT)
                if [[ ${#visible_idx[@]} -gt 0 ]]; then
                    tput cnorm 2>/dev/null || true
                    WS_NAV_RESULT="open"
                    WS_NAV_SELECTED="${visible_idx[$cursor]}"
                    WS_NAV_LAST_FILTER="$filter_text"
                    return 0
                fi
                ;;
            ESC|LEFT)
                tput cnorm 2>/dev/null || true
                WS_NAV_RESULT="back"
                WS_NAV_LAST_FILTER="$filter_text"
                return 0
                ;;
            SPACE)
                if [[ "$WS_NAV_MARKABLE" == "true" && ${#visible_idx[@]} -gt 0 ]]; then
                    local target="${visible_idx[$cursor]}" found="false"
                    local -a newmarks=()
                    for m in "${WS_NAV_MARKED_INDICES[@]}"; do
                        if [[ "$m" == "$target" ]]; then found="true"; else newmarks+=("$m"); fi
                    done
                    [[ "$found" == "false" ]] && newmarks+=("$target")
                    WS_NAV_MARKED_INDICES=("${newmarks[@]}")
                fi
                ;;
            SLASH)
                [[ "$WS_NAV_FILTERABLE" == "true" ]] && filter_mode="true"
                ;;
            QMARK)
                ws_show_header
                echo -e "${YELLOW}${BOLD}HELP${NC}\n"
                echo -e "$WS_NAV_HELP_TEXT"
                echo ""
                read -rsn1 -p "Press any key to continue..."
                ;;
            Q)
                tput cnorm 2>/dev/null || true
                WS_NAV_RESULT="quit"
                WS_NAV_LAST_FILTER="$filter_text"
                return 0
                ;;
            CHAR:*)
                local c="${key#CHAR:}"
                if [[ -n "$c" && "$WS_NAV_EXTRA_KEYS" == *"$c"* ]]; then
                    tput cnorm 2>/dev/null || true
                    WS_NAV_RESULT="key:${c}"
                    # Also expose the row under the cursor (ORIGINAL index) at
                    # the moment the extra key was pressed, same as "open"
                    # does, so a per-row extra action (e.g. "jump to this
                    # file's History") knows which row it applies to.
                    if [[ ${#visible_idx[@]} -gt 0 ]]; then
                        WS_NAV_SELECTED="${visible_idx[$cursor]}"
                    else
                        WS_NAV_SELECTED=-1
                    fi
                    WS_NAV_LAST_FILTER="$filter_text"
                    return 0
                fi
                ;;
            EOF)
                tput cnorm 2>/dev/null || true
                WS_NAV_RESULT="quit"
                WS_NAV_LAST_FILTER="$filter_text"
                return 0
                ;;
            *) : ;;
        esac
    done
}

# ==============================================================================
# STAGE 3 OF 6: CHANGES SCREEN — diff viewing + the three revert actions,
# wired through the existing safety layer (run_git, create_safety_backup,
# confirm_destructive, log_action).
#
# A NOTE ON THE SAFETY LAYER FOR THIS SCREEN SPECIFICALLY: create_safety_backup
# only tags HEAD (a commit). That's exactly right for commit-level actions
# elsewhere in the tool (hard reset, branch delete), but every revert action
# on THIS screen rewrites a file's WORKING-TREE content, which was never
# committed — a HEAD tag captures nothing about it, so it alone would give a
# user no way back to what they just discarded. The original feature spec
# anticipated this ("automatic backup first: git stash create + store, or
# patch in .git/wizard-backups"). Every action below therefore does BOTH:
# create_safety_backup for the same visible "[OK] Safety backup created"
# message and git-tag landmark the rest of the tool already trains users to
# expect, AND a plain content copy under .git/wizard-backups/ (the actual
# recoverable payload for THIS kind of change) that "Undo last action" reads
# back from.
# ==============================================================================

WS_LAST_ACTION_KIND=""    # "files" | "commit"
WS_LAST_ACTION_DESC=""
WS_LAST_ACTION_BACKUP_DIR=""
# shellcheck disable=SC2034
WS_LAST_ACTION_FILES=()   # "sanitized_name|original_path" pairs — kind=files
WS_LAST_ACTION_TAG=""     # backup tag to reset --hard to — kind=commit

ws_git_dir() {
    git rev-parse --git-dir 2>/dev/null
}

ws_sanitize_path() {
    local p="$1"
    p="${p//\//__}"
    echo "$p"
}

# ------------------------------------------------------------------------------
# ws_backup_file_content <path> <backup_dir>
# Copies the file's CURRENT on-disk (worktree) content and, if it differs,
# its CURRENT staged (index) content into $backup_dir, so a later revert can
# be undone even though it only ever touches working-tree/index state that
# no commit or tag can capture. No-ops gracefully if the file doesn't exist
# on disk (e.g. backing up a "deleted" entry before restoring it).
# ------------------------------------------------------------------------------
ws_backup_file_content() {
    local path="$1"
    local backup_dir="$2"
    local sanitized
    sanitized=$(ws_sanitize_path "$path")
    mkdir -p "$backup_dir"
    if [[ -f "$path" ]]; then
        cp -p "$path" "${backup_dir}/${sanitized}.worktree" 2>/dev/null
    fi
    # Only snapshot the index content when it GENUINELY differs from HEAD —
    # `git ls-files --cached` would succeed for virtually every tracked file
    # all the time (it just checks the path is in the index at all), which
    # previously made restore unconditionally re-run `git add` afterward and
    # silently stage files that were never staged to begin with.
    if ! git diff --cached --quiet -- "$path" 2>/dev/null; then
        git show ":$path" > "${backup_dir}/${sanitized}.staged" 2>/dev/null \
            || rm -f "${backup_dir}/${sanitized}.staged"
    fi
    echo "$sanitized"
}

# ------------------------------------------------------------------------------
# ws_restore_file_content <path> <backup_dir>
# Reverses ws_backup_file_content: restores the worktree file from the
# backed-up copy (removing it if it didn't exist at backup time, i.e. the
# action had created it), and restores the INDEX to its exact prior blob if
# a .staged copy was captured.
#
# This writes the saved .staged bytes straight into the index via
# hash-object + update-index, rather than `git add` on the just-restored
# worktree file: a file that was staged and then edited AGAIN before being
# reverted ("MM" in porcelain) has different staged-vs-worktree content, and
# `git add` would stage the worktree copy, collapsing that split instead of
# reproducing it.
# ------------------------------------------------------------------------------
ws_restore_file_content() {
    local path="$1"
    local backup_dir="$2"
    local sanitized
    sanitized=$(ws_sanitize_path "$path")
    local wt="${backup_dir}/${sanitized}.worktree"
    local staged="${backup_dir}/${sanitized}.staged"

    if [[ -f "$wt" ]]; then
        mkdir -p "$(dirname "$path")" 2>/dev/null
        cp -p "$wt" "$path"
    else
        rm -f "$path" 2>/dev/null
    fi

    if [[ -f "$staged" ]]; then
        local blob_sha mode
        blob_sha=$(git hash-object -w "$staged")
        mode="100644"
        [[ -f "$wt" && -x "$wt" ]] && mode="100755"
        run_git update-index --add --cacheinfo "${mode},${blob_sha},${path}"
    else
        run_git reset -- "$path" 2>/dev/null || true
    fi
}

# ws_record_last_action_files <desc> <backup_dir> <"sanitized|path" ...>
# For worktree/index-level actions (the three revert options, revert-all,
# revert-marked, apply/restore/undo-file) — undo restores file CONTENT from
# the backup dir, since a commit tag alone captures nothing about
# uncommitted content (see the header note on this file's safety layer).
ws_record_last_action_files() {
    local desc="$1"
    local backup_dir="$2"
    shift 2
    WS_LAST_ACTION_KIND="files"
    WS_LAST_ACTION_DESC="$desc"
    WS_LAST_ACTION_BACKUP_DIR="$backup_dir"
    WS_LAST_ACTION_FILES=("$@")
    WS_LAST_ACTION_TAG=""
    log_action "WORKSPACE EXPLORER: ${desc}"
}

# ws_record_last_action_commit <desc> <backup_tag>
# For commit-level actions ("Undo this commit (safe)" / git revert) — undo
# is a plain `git reset --hard` to the tag create_safety_backup already made,
# which IS the correct and sufficient recovery for a commit-level change.
ws_record_last_action_commit() {
    local desc="$1"
    local tag="$2"
    WS_LAST_ACTION_KIND="commit"
    WS_LAST_ACTION_DESC="$desc"
    WS_LAST_ACTION_TAG="$tag"
    WS_LAST_ACTION_BACKUP_DIR=""
    WS_LAST_ACTION_FILES=()
    log_action "WORKSPACE EXPLORER: ${desc}"
}

ws_undo_last_action() {
    if [[ -z "$WS_LAST_ACTION_KIND" ]]; then
        echo -e "${YELLOW}[i] Nothing to undo yet.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return
    fi
    if [[ "$WS_LAST_ACTION_KIND" == "files" && ! -d "$WS_LAST_ACTION_BACKUP_DIR" ]]; then
        echo -e "${RED}[!] Backup for the last action is missing — cannot undo.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return
    fi
    if [[ "$WS_LAST_ACTION_KIND" == "commit" ]] && ! git rev-parse -q --verify "$WS_LAST_ACTION_TAG" &>/dev/null; then
        echo -e "${RED}[!] Backup tag for the last action is missing — cannot undo.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return
    fi
    if confirm_destructive "Undo: ${WS_LAST_ACTION_DESC}"; then
        create_safety_backup "pre-undo"
        if [[ "$WS_LAST_ACTION_KIND" == "commit" ]]; then
            run_git reset --hard "$WS_LAST_ACTION_TAG"
        else
            local entry sanitized path
            for entry in "${WS_LAST_ACTION_FILES[@]}"; do
                sanitized="${entry%%|*}"
                path="${entry#*|}"
                ws_restore_file_content "$path" "$WS_LAST_ACTION_BACKUP_DIR"
            done
        fi
        log_action "UNDO: ${WS_LAST_ACTION_DESC}"
        echo -e "${GREEN}[✔] Undone: ${WS_LAST_ACTION_DESC}${NC}"
        WS_LAST_ACTION_KIND=""
        WS_LAST_ACTION_DESC=""
        WS_LAST_ACTION_BACKUP_DIR=""
        WS_LAST_ACTION_FILES=()
        WS_LAST_ACTION_TAG=""
        read -rsn1 -p "Press any key to continue..."
    fi
}

# ------------------------------------------------------------------------------
# In-progress-operation detection, for the conflict screen's "Abort" action.
# A conflict can come from a merge, a rebase, or a cherry-pick, and each has
# its own abort command — running the wrong one either fails outright or
# (worse) leaves repo state half-unwound.
# ------------------------------------------------------------------------------
ws_detect_in_progress_operation() {
    local gd
    gd=$(ws_git_dir)
    [[ -z "$gd" ]] && { echo ""; return; }
    if [[ -f "${gd}/MERGE_HEAD" ]]; then
        echo "merge"
    elif [[ -f "${gd}/CHERRY_PICK_HEAD" ]]; then
        echo "cherry-pick"
    elif [[ -f "${gd}/REVERT_HEAD" ]]; then
        echo "revert"
    elif [[ -d "${gd}/rebase-merge" || -d "${gd}/rebase-apply" ]]; then
        echo "rebase"
    else
        echo ""
    fi
}

ws_abort_in_progress_operation() {
    local kind
    kind=$(ws_detect_in_progress_operation)
    case "$kind" in
        merge) run_git merge --abort ;;
        cherry-pick) run_git cherry-pick --abort ;;
        revert) run_git revert --abort ;;
        rebase) run_git rebase --abort ;;
        *)
            echo -e "${YELLOW}[i] No merge, rebase, revert, or cherry-pick currently in progress.${NC}"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# ws_render_diff <raw diff text already with --color=always>
# Pipes through delta as a FORMATTER only (--paging=never — the Explorer
# does its own scrolling via ws_scroll_view so delta must not try to hand
# off to its own pager), matching the Delta Diff Suite's "use delta when
# installed" convention. Falls back to the plain colored diff untouched.
# ------------------------------------------------------------------------------
ws_render_diff() {
    local raw="$1"
    if command -v delta &>/dev/null; then
        echo "$raw" | delta --paging=never 2>/dev/null
    else
        echo "$raw"
    fi
}

# ------------------------------------------------------------------------------
# ws_scroll_view — generic scrollable text viewer (diff / commit detail).
#
# INPUTS: WS_SCROLL_CONTENT (newline-joined text), WS_SCROLL_EXTRA_BAR,
#         WS_SCROLL_EXTRA_KEYS (string of extra single chars to surface)
# OUTPUT: WS_SCROLL_RESULT = "back" | "quit" | "key:<c>"
# ------------------------------------------------------------------------------
ws_scroll_view() {
    local -a lines=()
    while IFS= read -r line; do lines+=("$line"); done <<< "$WS_SCROLL_CONTENT"
    local total=${#lines[@]}
    local offset=0
    local rows cols visible_rows i key

    tput civis 2>/dev/null || true
    while true; do
        rows=$(tput lines 2>/dev/null || echo 24)
        cols=$(tput cols 2>/dev/null || echo 80)
        : "$cols"
        visible_rows=$(( rows - 10 ))
        [[ $visible_rows -lt 3 ]] && visible_rows=3

        if [[ $offset -gt $(( total - visible_rows )) ]]; then
            offset=$(( total - visible_rows ))
        fi
        [[ $offset -lt 0 ]] && offset=0

        ws_show_header
        ws_draw_breadcrumb

        local shown=0
        for ((i = offset; i < total && shown < visible_rows; i++)); do
            echo -e "${lines[$i]}"
            ((shown++))
        done
        if [[ $total -eq 0 ]]; then
            echo -e "${CYAN}(empty)${NC}"
        fi

        echo ""
        if [[ $total -gt $visible_rows ]]; then
            echo -e "${CYAN}-- line $((offset + 1))-$((offset + shown)) of ${total} --${NC}"
        fi

        local bar="${CYAN}[↑↓]${NC} Scroll  ${CYAN}[Esc/←]${NC} Back  ${CYAN}[?]${NC} Help  ${CYAN}[q]${NC} Quit"
        [[ -n "$WS_SCROLL_EXTRA_BAR" ]] && bar="${bar}\n${WS_SCROLL_EXTRA_BAR}"
        ws_draw_action_bar "$bar"

        ws_read_key
        key="$WS_LAST_KEY"
        case "$key" in
            UP) ((offset--)) || true; [[ $offset -lt 0 ]] && offset=0 ;;
            DOWN) ((offset++)) || true ;;
            ESC|LEFT)
                tput cnorm 2>/dev/null || true
                WS_SCROLL_RESULT="back"
                return 0
                ;;
            Q)
                tput cnorm 2>/dev/null || true
                WS_SCROLL_RESULT="quit"
                return 0
                ;;
            QMARK)
                ws_show_header
                echo -e "${YELLOW}${BOLD}HELP${NC}\n"
                echo -e "$WS_SCROLL_HELP_TEXT"
                echo ""
                read -rsn1 -p "Press any key to continue..."
                ;;
            EOF)
                tput cnorm 2>/dev/null || true
                WS_SCROLL_RESULT="quit"
                return 0
                ;;
            CHAR:*)
                local c="${key#CHAR:}"
                if [[ -n "$c" && "$WS_SCROLL_EXTRA_KEYS" == *"$c"* ]]; then
                    tput cnorm 2>/dev/null || true
                    WS_SCROLL_RESULT="key:${c}"
                    return 0
                fi
                ;;
            *) : ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ws_format_status_row <index> — one display row for the Changes list.
# ------------------------------------------------------------------------------
ws_format_status_row() {
    local idx="$1"
    local path="${WS_STATUS_PATH[$idx]}"
    local orig="${WS_STATUS_ORIG[$idx]}"
    local badge="${WS_STATUS_BADGE[$idx]}"
    local color label

    case "$badge" in
        conflict)  color="$RED";    label="CONFLICT" ;;
        untracked) color="$CYAN";   label="untracked" ;;
        renamed)   color="$YELLOW"; label="renamed  " ;;
        added)     color="$GREEN";  label="added    " ;;
        deleted)   color="$RED";    label="deleted  " ;;
        staged)    color="$GREEN";  label="staged   " ;;
        *)         color="$YELLOW"; label="modified " ;;
    esac

    if [[ -n "$orig" ]]; then
        echo -e "${color}${BOLD}[${label}]${NC} ${orig} ${CYAN}→${NC} ${BOLD}${path}${NC}"
    else
        echo -e "${color}${BOLD}[${label}]${NC} ${BOLD}${path}${NC}"
    fi
}

WS_CHANGES_HELP_TEXT="Up/Down - move    Enter or Right - open diff for the selected file
Esc or Left - leave the Workspace Explorer    Space - mark a file
/ - filter the list by typing part of a filename    q - quit the Explorer
R - revert ALL tracked changes to last commit (untracked files are never touched)
M - revert only the MARKED files to last commit
U - undo the last Explorer action (restores the files it changed)
H - this file's full commit history (File Timeline)"

# ------------------------------------------------------------------------------
# ws_changes_screen — Screen 1: the git-status view, and entry point for the
# whole Workspace Explorer.
# ------------------------------------------------------------------------------
ws_changes_screen() {
    local nav_marked=()
    while true; do
        ws_load_status

        WS_NAV_ITEMS=()
        local i
        for i in "${!WS_STATUS_PATH[@]}"; do
            WS_NAV_ITEMS+=("$(ws_format_status_row "$i")")
        done

        WS_BREADCRUMB=("Changes")
        WS_NAV_TITLE="📂 CHANGES  (${#WS_STATUS_PATH[@]} file(s))"
        WS_NAV_MARKABLE="true"
        WS_NAV_FILTERABLE="true"
        WS_NAV_HELP_TEXT="$WS_CHANGES_HELP_TEXT"
        WS_NAV_EXTRA_KEYS="RMUH"
        local undo_hint=""
        [[ -n "$WS_LAST_ACTION_KIND" ]] && undo_hint="  ${CYAN}[U]${NC} Undo: ${WS_LAST_ACTION_DESC}"
        WS_NAV_EXTRA_BAR="${CYAN}[R]${NC} Revert all  ${CYAN}[M]${NC} Revert marked  ${CYAN}[H]${NC} File Timeline${undo_hint}"
        WS_NAV_MARKED_INDICES=("${nav_marked[@]}")

        ws_list_navigate
        nav_marked=("${WS_NAV_MARKED_INDICES[@]}")

        case "$WS_NAV_RESULT" in
            open)
                local sel="$WS_NAV_SELECTED"
                local path="${WS_STATUS_PATH[$sel]}"
                local badge="${WS_STATUS_BADGE[$sel]}"
                if [[ "$badge" == "conflict" ]]; then
                    ws_conflict_screen "$path" || { tput cnorm 2>/dev/null || true; return 0; }
                else
                    ws_file_diff_screen "$path" "$badge" || { tput cnorm 2>/dev/null || true; return 0; }
                fi
                ;;
            key:R)
                ws_changes_revert_all
                ;;
            key:M)
                ws_changes_revert_marked "${nav_marked[@]}"
                nav_marked=()
                ;;
            key:U)
                ws_undo_last_action
                ;;
            key:H)
                if [[ "$WS_NAV_SELECTED" -ge 0 ]]; then
                    ws_file_timeline_screen "${WS_STATUS_PATH[$WS_NAV_SELECTED]}" || { tput cnorm 2>/dev/null || true; return 0; }
                fi
                ;;
            back|quit|*)
                tput cnorm 2>/dev/null || true
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ws_changes_revert_all — "R" on the Changes list. Tracked files only, per
# design decision: untracked files are never touched by a batch revert.
# ------------------------------------------------------------------------------
ws_changes_revert_all() {
    local -a targets=()
    local i
    for i in "${!WS_STATUS_PATH[@]}"; do
        [[ "${WS_STATUS_BADGE[$i]}" != "untracked" ]] && targets+=("$i")
    done
    if [[ ${#targets[@]} -eq 0 ]]; then
        echo -e "${YELLOW}[i] No tracked changes to revert.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return
    fi
    ws_show_header
    ws_draw_breadcrumb
    echo -e "${YELLOW}${BOLD}REVERT ALL TRACKED CHANGES (${#targets[@]} file(s))${NC}\n"
    for i in "${targets[@]}"; do
        echo -e "  $(ws_format_status_row "$i")"
    done
    echo ""
    if ! confirm_destructive "Revert ${#targets[@]} tracked file(s) to their last commit — untracked files are left alone"; then
        return
    fi

    local ts backup_dir
    ts=$(date '+%Y%m%d-%H%M%S')
    backup_dir="$(ws_git_dir)/wizard-backups/revert-all-${ts}"
    create_safety_backup "pre-revert-all"

    local -a files_for_journal=()
    local path sanitized
    for i in "${targets[@]}"; do
        path="${WS_STATUS_PATH[$i]}"
        sanitized=$(ws_backup_file_content "$path" "$backup_dir")
        files_for_journal+=("${sanitized}|${path}")
        run_git restore --source=HEAD --staged --worktree -- "$path"
    done
    ws_record_last_action_files "Revert all (${#targets[@]} file(s)) to last commit" "$backup_dir" "${files_for_journal[@]}"
    echo -e "${GREEN}[✔] Reverted ${#targets[@]} file(s).${NC}"
    read -rsn1 -p "Press any key to continue..."
}

# ------------------------------------------------------------------------------
# ws_changes_revert_marked <marked original indices...> — "M" on the list.
# ------------------------------------------------------------------------------
ws_changes_revert_marked() {
    local -a marked=("$@")
    if [[ ${#marked[@]} -eq 0 ]]; then
        echo -e "${YELLOW}[i] No files marked. Press Space on a file first.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return
    fi
    local -a targets=()
    local -a skipped_untracked=()
    local m
    for m in "${marked[@]}"; do
        if [[ "${WS_STATUS_BADGE[$m]}" == "untracked" ]]; then
            skipped_untracked+=("${WS_STATUS_PATH[$m]}")
        else
            targets+=("$m")
        fi
    done

    ws_show_header
    ws_draw_breadcrumb
    echo -e "${YELLOW}${BOLD}REVERT MARKED FILES (${#targets[@]} file(s))${NC}\n"
    for m in "${targets[@]}"; do
        echo -e "  $(ws_format_status_row "$m")"
    done
    if [[ ${#skipped_untracked[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}[i] Skipping untracked (no commit to revert to): ${skipped_untracked[*]}${NC}"
    fi
    echo ""
    if [[ ${#targets[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Nothing to revert.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return
    fi
    if ! confirm_destructive "Revert ${#targets[@]} marked file(s) to their last commit"; then
        return
    fi

    local ts backup_dir
    ts=$(date '+%Y%m%d-%H%M%S')
    backup_dir="$(ws_git_dir)/wizard-backups/revert-marked-${ts}"
    create_safety_backup "pre-revert-marked"

    local -a files_for_journal=()
    local path sanitized
    for m in "${targets[@]}"; do
        path="${WS_STATUS_PATH[$m]}"
        sanitized=$(ws_backup_file_content "$path" "$backup_dir")
        files_for_journal+=("${sanitized}|${path}")
        run_git restore --source=HEAD --staged --worktree -- "$path"
    done
    ws_record_last_action_files "Revert marked (${#targets[@]} file(s)) to last commit" "$backup_dir" "${files_for_journal[@]}"
    echo -e "${GREEN}[✔] Reverted ${#targets[@]} marked file(s).${NC}"
    read -rsn1 -p "Press any key to continue..."
}

# ------------------------------------------------------------------------------
# ws_conflict_screen <path> — raw conflicted file + Abort Merge/Rebase/Cherry-pick.
# ------------------------------------------------------------------------------
ws_conflict_screen() {
    local path="$1"
    while true; do
        WS_BREADCRUMB=("Changes" "${path} (CONFLICT)")
        local content
        if [[ -f "$path" ]]; then
            content=$(cat "$path")
        else
            content="(file not present on disk)"
        fi
        WS_SCROLL_CONTENT="${RED}${BOLD}This file has unresolved merge conflict markers (<<<<<<<, =======, >>>>>>>).${NC}
${YELLOW}Resolve it in an editor, or abort the in-progress operation below.${NC}

${content}"
        local kind
        kind=$(ws_detect_in_progress_operation)
        WS_SCROLL_EXTRA_BAR="${RED}[A]${NC} Abort ${kind:-merge} (discards ALL conflict-resolution progress)"
        WS_SCROLL_EXTRA_KEYS="A"
        WS_SCROLL_HELP_TEXT="Up/Down - scroll    Esc/Left - back to Changes    A - abort the in-progress ${kind:-merge}"

        ws_scroll_view
        case "$WS_SCROLL_RESULT" in
            key:A)
                ws_show_header
                ws_draw_breadcrumb
                if confirm_destructive "Abort the in-progress ${kind:-merge} — discards ALL conflict-resolution progress"; then
                    create_safety_backup "pre-${kind:-merge}-abort"
                    if ws_abort_in_progress_operation; then
                        echo -e "${GREEN}[✔] Aborted.${NC}"
                        read -rsn1 -p "Press any key to continue..."
                        return 0
                    fi
                    read -rsn1 -p "Press any key to continue..."
                fi
                ;;
            quit)
                tput cnorm 2>/dev/null || true
                return 1
                ;;
            back|*)
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ws_file_diff_screen <path> <badge> — Screen 1's diff/detail view: the
# scrollable diff plus the three revert actions (or Delete for untracked),
# plus the shortcut into File Timeline. Returns 1 if the user quit the whole
# Explorer from here, 0 otherwise (back to Changes).
# ------------------------------------------------------------------------------
ws_file_diff_screen() {
    local path="$1"
    local badge="$2"

    while true; do
        ws_load_status
        local i y="" found="false"
        for i in "${!WS_STATUS_PATH[@]}"; do
            if [[ "${WS_STATUS_PATH[$i]}" == "$path" ]]; then
                y="${WS_STATUS_Y[$i]}"
                badge="${WS_STATUS_BADGE[$i]}"
                found="true"
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            echo -e "${GREEN}[✔] '${path}' no longer has pending changes.${NC}"
            read -rsn1 -p "Press any key to continue..."
            return 0
        fi

        WS_BREADCRUMB=("Changes" "$path")

        local diff_mode=""
        [[ "$y" == " " ]] && diff_mode="--staged"

        local body
        if ws_is_binary_file "$path"; then
            body="${YELLOW}(binary file — showing size change only)${NC}\n\n$(git diff --stat -- "$path" 2>/dev/null)"
        else
            body=$(ws_render_diff "$(ws_file_diff "$path" $diff_mode)")
            [[ -z "$body" ]] && body="${CYAN}(no textual diff available)${NC}"
        fi
        WS_SCROLL_CONTENT="$body"

        local bar extra_keys="T"
        local hash2="" hash3=""
        if [[ "$badge" == "untracked" ]]; then
            bar="${RED}[D]${NC} Delete this untracked file (no backup tag possible — not a revert)"
            extra_keys="DT"
        else
            bar=""
            extra_keys="T"
            # "Revert to last commit" only makes sense if a committed version
            # of this exact path exists — a freshly-added, never-committed
            # file (badge=added, path new under HEAD) has none, and
            # `git restore --source=HEAD` on it would just fail outright.
            if git cat-file -e "HEAD:${path}" 2>/dev/null; then
                bar="${CYAN}[1]${NC} Revert to last commit"
                extra_keys="1T"
            fi
            hash2=$(ws_hash_before_last_change "$path")
            if [[ -n "$hash2" ]]; then
                bar="${bar}  ${CYAN}[2]${NC} Revert to version before last change"
                extra_keys="${extra_keys}2"
            fi
            hash3=$(ws_hash_original_add "$path")
            if [[ -n "$hash3" && "$hash3" != "$hash2" ]]; then
                bar="${bar}  ${CYAN}[3]${NC} Revert to original state"
                extra_keys="${extra_keys}3"
            fi
        fi
        bar="${bar}  ${CYAN}[T]${NC} File Timeline"
        WS_SCROLL_EXTRA_BAR="$bar"
        WS_SCROLL_EXTRA_KEYS="$extra_keys"
        WS_SCROLL_HELP_TEXT="Up/Down - scroll the diff    Esc/Left - back to Changes
T - this file's full commit history (File Timeline)
$([[ "$badge" == "untracked" ]] && echo "D - delete this untracked file" || echo "1/2/3 - revert to an earlier version of this file, as shown above")"

        ws_scroll_view
        case "$WS_SCROLL_RESULT" in
            key:T)
                if declare -F ws_file_timeline_screen &>/dev/null; then
                    ws_file_timeline_screen "$path" || return 1
                else
                    echo -e "${YELLOW}[i] File Timeline arrives in Stage 4.${NC}"
                    read -rsn1 -p "Press any key to continue..."
                fi
                ;;
            key:D)
                ws_show_header
                ws_draw_breadcrumb
                echo -e "${RED}${BOLD}DELETE UNTRACKED FILE${NC}\n"
                echo -e "${RED}'${path}' has never been committed — there is no version to fall back to.${NC}"
                echo -e "${RED}This cannot be undone through the Explorer's backup system.${NC}\n"
                if confirm_destructive "Permanently delete the untracked file '${path}'"; then
                    ws_delete_untracked "$path"
                    log_action "WORKSPACE EXPLORER: deleted untracked file ${path}"
                    echo -e "${GREEN}[✔] Deleted.${NC}"
                    read -rsn1 -p "Press any key to continue..."
                    return 0
                fi
                ;;
            key:1)
                ws_perform_single_revert "$path" "last commit" ws_revert_to_last_commit && return 0
                ;;
            key:2)
                ws_perform_single_revert "$path" "version before last change" ws_revert_to_before_last_change && return 0
                ;;
            key:3)
                ws_perform_single_revert "$path" "original state" ws_revert_to_original_state && return 0
                ;;
            quit)
                tput cnorm 2>/dev/null || true
                return 1
                ;;
            back|*)
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ws_perform_single_revert <path> <human label> <revert function name>
# Shared confirm + file-content-backup + journal wrapper for options 1/2/3.
# The revert function itself (ws_revert_to_last_commit etc.) already calls
# create_safety_backup + run_git; this wraps it with the confirmation and
# the file-content backup that makes "Undo last action" possible.
# ------------------------------------------------------------------------------
ws_perform_single_revert() {
    local path="$1"
    local label="$2"
    local fn="$3"

    ws_show_header
    ws_draw_breadcrumb
    echo -e "${YELLOW}${BOLD}REVERT TO: ${label}${NC}\n"
    if ! confirm_destructive "Revert '${path}' to its ${label}"; then
        return 1
    fi

    local ts backup_dir sanitized
    ts=$(date '+%Y%m%d-%H%M%S')
    backup_dir="$(ws_git_dir)/wizard-backups/revert-${ts}"
    sanitized=$(ws_backup_file_content "$path" "$backup_dir")

    if ! "$fn" "$path"; then
        echo -e "${YELLOW}[i] Nothing to revert to (no earlier version found).${NC}"
        read -rsn1 -p "Press any key to continue..."
        return 1
    fi

    ws_record_last_action_files "Revert '${path}' to ${label}" "$backup_dir" "${sanitized}|${path}"
    echo -e "${GREEN}[✔] Reverted.${NC}"
    read -rsn1 -p "Press any key to continue..."
    return 0
}

# ==============================================================================
# STAGE 4 OF 6: FILE TIMELINE — all commits touching one file (git log
# --follow), paged ~50 at a time; a commit's change to that file; and the
# four commit actions (Apply / Restore file / Undo file change / Undo commit
# safely). Screen 5 (Project Timeline) reuses ws_commit_list_screen and
# ws_commit_detail_actions_bar below, per the original spec's "reusing the
# same commit-detail code" instruction.
# ==============================================================================

ws_format_commit_row() {
    local hash="$1" author="$2" date="$3" subject="$4"
    echo -e "${CYAN}${BOLD}${hash:0:8}${NC}  ${GREEN}${author}${NC}  ${YELLOW}${date}${NC}  ${subject}"
}

# ------------------------------------------------------------------------------
# ws_commit_list_screen — generic paged commit browser shared by File
# Timeline and Project Timeline.
#
# INPUTS:
#   WS_CL_FETCH_FN    name of a function taking (limit, skip) that echoes
#                     "hash\x1fauthor\x1fdate\x1fsubject" lines
#   WS_CL_COUNT_FN    name of a function taking no args that echoes the
#                     total commit count
#   WS_CL_TITLE       title text (page/total appended automatically)
#   WS_CL_BREADCRUMB  array
#   WS_CL_PAGE_SIZE   commits per page (default 50)
#
# OUTPUT:
#   WS_CL_RESULT          "open" | "back" | "quit"
#   WS_CL_SELECTED_HASH / _AUTHOR / _DATE / _SUBJECT  (when result == "open")
# ------------------------------------------------------------------------------
ws_commit_list_screen() {
    local page=0
    local page_size="${WS_CL_PAGE_SIZE:-50}"

    while true; do
        local total
        total=$("$WS_CL_COUNT_FN")
        [[ -z "$total" ]] && total=0

        local total_pages=$(( (total + page_size - 1) / page_size ))
        [[ $total_pages -lt 1 ]] && total_pages=1
        if [[ $page -ge $total_pages ]]; then
            page=$(( total_pages - 1 ))
        fi
        [[ $page -lt 0 ]] && page=0
        local skip=$((page * page_size))

        local -a hashes=() authors=() dates=() subjects=()
        WS_NAV_ITEMS=()
        while IFS=$'\x1f' read -r h a d s; do
            [[ -z "$h" ]] && continue
            hashes+=("$h")
            authors+=("$a")
            dates+=("$d")
            subjects+=("$s")
            WS_NAV_ITEMS+=("$(ws_format_commit_row "$h" "$a" "$d" "$s")")
        done < <("$WS_CL_FETCH_FN" "$page_size" "$skip")

        WS_BREADCRUMB=("${WS_CL_BREADCRUMB[@]}")
        WS_NAV_TITLE="${WS_CL_TITLE}  (page $((page + 1))/${total_pages}, ${total} commit(s) total)"
        WS_NAV_MARKABLE="false"
        WS_NAV_FILTERABLE="true"
        WS_NAV_HELP_TEXT="Up/Down - move    Enter/Right - view this commit    Esc/Left - back
/ - filter by author/date/message    N - next page    P - previous page    q - quit the Explorer"

        local extra="" bar=""
        if [[ $((page + 1)) -lt $total_pages ]]; then
            extra="N"
            bar="${CYAN}[N]${NC} Next page"
        fi
        if [[ $page -gt 0 ]]; then
            extra="${extra}P"
            [[ -n "$bar" ]] && bar="${bar}  "
            bar="${bar}${CYAN}[P]${NC} Previous page"
        fi
        WS_NAV_EXTRA_KEYS="$extra"
        WS_NAV_EXTRA_BAR="$bar"
        WS_NAV_MARKED_INDICES=()

        ws_list_navigate

        case "$WS_NAV_RESULT" in
            open)
                WS_CL_RESULT="open"
                WS_CL_SELECTED_HASH="${hashes[$WS_NAV_SELECTED]}"
                WS_CL_SELECTED_AUTHOR="${authors[$WS_NAV_SELECTED]}"
                WS_CL_SELECTED_DATE="${dates[$WS_NAV_SELECTED]}"
                WS_CL_SELECTED_SUBJECT="${subjects[$WS_NAV_SELECTED]}"
                return 0
                ;;
            key:N)
                ((page++)) || true
                ;;
            key:P)
                ((page--)) || true
                [[ $page -lt 0 ]] && page=0
                ;;
            back|quit|*)
                WS_CL_RESULT="$WS_NAV_RESULT"
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ws_perform_commit_file_action <path> <hash> <label> <action fn taking hash,path>
# Shared confirm + file-content-backup + journal wrapper for the File
# Timeline's Apply / Restore file / Undo file change actions — all three
# rewrite WORKING-TREE content for one file, same as Stage 3's revert
# options, so they need the same file-content backup (not just a HEAD tag)
# to be undoable.
# ------------------------------------------------------------------------------
ws_perform_commit_file_action() {
    local path="$1"
    local hash="$2"
    local label="$3"
    local fn="$4"

    ws_show_header
    ws_draw_breadcrumb
    echo -e "${YELLOW}${BOLD}${label}${NC}\n"
    if ! confirm_destructive "${label}: '${path}' at commit ${hash:0:8}"; then
        return 1
    fi

    local ts backup_dir sanitized
    ts=$(date '+%Y%m%d-%H%M%S')
    backup_dir="$(ws_git_dir)/wizard-backups/commit-action-${ts}"
    sanitized=$(ws_backup_file_content "$path" "$backup_dir")

    local out
    out=$("$fn" "$hash" "$path" 2>&1)
    local rc=$?

    ws_record_last_action_files "${label}: '${path}' at ${hash:0:8}" "$backup_dir" "${sanitized}|${path}"

    if [[ $rc -ne 0 ]] || echo "$out" | grep -q '^<<<<<<<\|^CONFLICT\|^Applied patch.*with conflicts'; then
        echo -e "${RED}[!] This didn't apply cleanly — '${path}' may now contain conflict markers.${NC}"
        echo -e "${YELLOW}    Use [U] Undo last action on the Changes screen to put it back exactly as it was.${NC}"
        [[ -n "$out" ]] && echo -e "\n${out}"
    else
        echo -e "${GREEN}[✔] Done.${NC}"
    fi
    read -rsn1 -p "Press any key to continue..."
    return 0
}

# ------------------------------------------------------------------------------
# ws_perform_commit_revert_safe <hash> <subject>
# "Undo this commit (safe)" — a COMMIT-level action (git revert creates a
# new commit), so the HEAD tag create_safety_backup makes IS the correct and
# sufficient undo mechanism here (undo = reset --hard to that tag), unlike
# the worktree-level actions above. Detects and offers to abort a revert
# conflict the same way the Changes screen handles a merge conflict.
# ------------------------------------------------------------------------------
ws_perform_commit_revert_safe() {
    local hash="$1"
    local subject="$2"

    ws_show_header
    ws_draw_breadcrumb
    echo -e "${YELLOW}${BOLD}UNDO THIS COMMIT (safe revert)${NC}\n"
    echo -e "Commit ${CYAN}${hash:0:8}${NC}: ${subject}\n"
    if ! confirm_destructive "Create a new commit that undoes ${hash:0:8} (\"${subject}\")"; then
        return 1
    fi

    local ts tag
    ts=$(date '+%Y%m%d-%H%M%S')
    tag="backup/pre-revert-commit-${ts}"
    if git rev-parse HEAD &>/dev/null && [[ "$DRY_RUN" != "true" ]]; then
        git tag "$tag" HEAD 2>/dev/null || true
    fi
    create_safety_backup "pre-revert-commit"

    if ws_revert_commit_safe "$hash"; then
        ws_record_last_action_commit "Undo commit ${hash:0:8} (\"${subject}\")" "$tag"
        echo -e "${GREEN}[✔] Commit undone with a new revert commit.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return 0
    fi

    local kind
    kind=$(ws_detect_in_progress_operation)
    if [[ "$kind" == "revert" ]]; then
        echo -e "${RED}[!] The revert hit a conflict and is still in progress.${NC}"
        echo -e "${YELLOW}    Conflicted file(s):${NC}"
        git diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/      /'
        echo ""
        echo -e "  ${RED}[A]${NC} Abort the revert (discards it, returns to the pre-revert state)"
        echo -e "  ${YELLOW}[Esc]${NC} Leave it — resolve the conflict manually, then commit"
        read -rsn1 -p "Choice: " kchoice
        if [[ "$kchoice" == "a" || "$kchoice" == "A" ]]; then
            if confirm_destructive "Abort the in-progress revert"; then
                run_git revert --abort
                echo -e "${GREEN}[✔] Aborted.${NC}"
            fi
        fi
    else
        echo -e "${RED}[!] Revert failed — the working tree may have uncommitted changes to a file this commit touched.${NC}"
    fi
    read -rsn1 -p "Press any key to continue..."
    return 0
}

_ws_file_timeline_fetch() { ws_file_log "$WS_TIMELINE_PATH" "$1" "$2"; }
_ws_file_timeline_count() { ws_file_log_count "$WS_TIMELINE_PATH"; }

# ------------------------------------------------------------------------------
# ws_file_timeline_screen <path> — Screen 2: all commits touching this file.
# Returns 1 if the user quit the whole Explorer from here, 0 otherwise.
# ------------------------------------------------------------------------------
ws_file_timeline_screen() {
    local path="$1"
    WS_TIMELINE_PATH="$path"

    while true; do
        WS_CL_FETCH_FN="_ws_file_timeline_fetch"
        WS_CL_COUNT_FN="_ws_file_timeline_count"
        WS_CL_TITLE="📜 FILE TIMELINE"
        WS_CL_BREADCRUMB=("Changes" "$path" "History")
        WS_CL_PAGE_SIZE=50

        ws_commit_list_screen

        case "$WS_CL_RESULT" in
            open)
                ws_file_timeline_commit_screen "$path" "$WS_CL_SELECTED_HASH" "$WS_CL_SELECTED_SUBJECT" || return 1
                ;;
            quit)
                return 1
                ;;
            back|*)
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ws_file_timeline_commit_screen <path> <hash> <subject> — that commit's
# change to this one file, plus the four File Timeline actions.
# Returns 1 if the user quit the whole Explorer from here, 0 otherwise.
# ------------------------------------------------------------------------------
ws_file_timeline_commit_screen() {
    local path="$1"
    local hash="$2"
    local subject="$3"

    while true; do
        WS_BREADCRUMB=("Changes" "$path" "History" "${hash:0:8}")

        local body
        if ws_is_binary_file "$path"; then
            body="${YELLOW}(binary file at this commit — diff not shown)${NC}"
        else
            body=$(ws_render_diff "$(ws_commit_file_diff "$hash" "$path")")
            [[ -z "$body" ]] && body="${CYAN}(no change to this file in this commit)${NC}"
        fi
        WS_SCROLL_CONTENT="$body"
        WS_SCROLL_EXTRA_BAR="${CYAN}[A]${NC} Apply to current  ${CYAN}[F]${NC} Restore file to this commit  ${CYAN}[U]${NC} Undo only this file's change  ${CYAN}[C]${NC} Undo this commit (safe)"
        WS_SCROLL_EXTRA_KEYS="AFUC"
        WS_SCROLL_HELP_TEXT="Up/Down - scroll    Esc/Left - back to this file's timeline
A - apply this historical change to your current file
F - restore the file to exactly how it looked at this commit
U - undo only this commit's change to this one file (reverse-apply)
C - undo the WHOLE commit safely (git revert — affects every file it touched)"

        ws_scroll_view
        case "$WS_SCROLL_RESULT" in
            key:A)
                ws_perform_commit_file_action "$path" "$hash" "Apply this change to current version" ws_apply_commit_file_to_current
                ;;
            key:F)
                ws_perform_commit_file_action "$path" "$hash" "Restore file to how it was at this commit" ws_restore_file_to_commit
                ;;
            key:U)
                ws_perform_commit_file_action "$path" "$hash" "Undo only this file's change in this commit" ws_undo_file_change_in_commit
                ;;
            key:C)
                ws_perform_commit_revert_safe "$hash" "$subject"
                return 0
                ;;
            quit)
                return 1
                ;;
            back|*)
                return 0
                ;;
        esac
    done
}

# ==============================================================================
# STAGE 5 OF 6: PROJECT TIMELINE — all repo commits, paged ~50 at a time.
# Enter shows message/stats/files touched; Enter on a file reuses
# ws_file_timeline_commit_screen from Stage 4 verbatim (same actions, same
# code), per the original spec's "Same actions as the File Timeline, reusing
# the same commit-detail code" instruction.
# ==============================================================================

_ws_project_timeline_fetch() { ws_project_log "$1" "$2"; }
_ws_project_timeline_count() { ws_project_log_count; }

# ------------------------------------------------------------------------------
# ws_project_timeline_screen — Screen 3: all repo commits.
# Returns 1 if the user quit the whole Explorer from here, 0 otherwise.
# ------------------------------------------------------------------------------
ws_project_timeline_screen() {
    while true; do
        WS_CL_FETCH_FN="_ws_project_timeline_fetch"
        WS_CL_COUNT_FN="_ws_project_timeline_count"
        WS_CL_TITLE="🕒 PROJECT TIMELINE"
        WS_CL_BREADCRUMB=("Project Timeline")
        WS_CL_PAGE_SIZE=50

        ws_commit_list_screen

        case "$WS_CL_RESULT" in
            open)
                ws_project_commit_detail_screen "$WS_CL_SELECTED_HASH" "$WS_CL_SELECTED_SUBJECT" || return 1
                ;;
            quit)
                return 1
                ;;
            back|*)
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ws_project_commit_detail_screen <hash> <subject> — message, stats, and the
# list of files this commit touched; Enter on a file reuses
# ws_file_timeline_commit_screen (Stage 4) for that file's change in this
# commit, with the same Apply/Restore/Undo-file/Undo-commit actions.
# ------------------------------------------------------------------------------
ws_project_commit_detail_screen() {
    local hash="$1"
    local subject="$2"

    while true; do
        local -a files=()
        WS_NAV_ITEMS=()
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            files+=("$f")
            WS_NAV_ITEMS+=("$(echo -e "${CYAN}${f}${NC}")")
        done < <(ws_commit_files "$hash")

        WS_BREADCRUMB=("Project Timeline" "${hash:0:8}")
        WS_NAV_TITLE="$(ws_commit_summary "$hash")

${YELLOW}${BOLD}FILES TOUCHED (${#files[@]})${NC}"
        WS_NAV_MARKABLE="false"
        WS_NAV_FILTERABLE="true"
        WS_NAV_HELP_TEXT="Up/Down - move    Enter/Right - view this file's change in this commit
Esc/Left - back to Project Timeline    / - filter by filename    q - quit the Explorer"
        WS_NAV_EXTRA_KEYS=""
        WS_NAV_EXTRA_BAR=""
        WS_NAV_MARKED_INDICES=()

        ws_list_navigate

        case "$WS_NAV_RESULT" in
            open)
                ws_file_timeline_commit_screen "${files[$WS_NAV_SELECTED]}" "$hash" "$subject" || return 1
                ;;
            quit)
                return 1
                ;;
            back|*)
                return 0
                ;;
        esac
    done
}

# ==============================================================================
# STAGE 6 OF 6: TOP-LEVEL ENTRY SCREEN — the home screen the Module 2 menu
# entry opens. Changes, File Timeline (via a file you pick here), and
# Project Timeline are all reachable from it.
#
# A NOTE ON "q": every sub-screen's own "quit" result just returns to THIS
# home screen (not all the way out of the tool) — only pressing q/Esc HERE,
# at the home screen itself, actually leaves the Explorer and returns to the
# Module 2 menu. This needed no changes to any of Stages 1-5: this screen is
# a thin additive wrapper on top of them.
# ==============================================================================

# ------------------------------------------------------------------------------
# ws_get_tracked_files — NUL-safe list of every tracked file, relative to
# the repo root, regardless of the caller's current subdirectory. Sets
# WS_PICKER_TRACKED. `git ls-files -z` (not plain newline-separated output)
# is what makes this safe for filenames containing spaces, or — in the rare
# but real case — literal newlines.
# ------------------------------------------------------------------------------
ws_get_tracked_files() {
    WS_PICKER_TRACKED=()
    local f
    while IFS= read -r -d '' f; do
        [[ -n "$f" ]] && WS_PICKER_TRACKED+=("$f")
    done < <(git ls-files -z 2>/dev/null)
}

# ------------------------------------------------------------------------------
# ws_get_deleted_files — paths that were deleted at some point in history and
# are NOT currently tracked (a file deleted and later re-added is correctly
# excluded — it belongs in the tracked list instead). Sets WS_PICKER_DELETED.
# Requires WS_PICKER_TRACKED to already be populated (ws_get_tracked_files).
# ------------------------------------------------------------------------------
ws_get_deleted_files() {
    WS_PICKER_DELETED=()
    local -A tracked_set=()
    local f
    for f in "${WS_PICKER_TRACKED[@]}"; do
        tracked_set["$f"]=1
    done
    local -A seen=()
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        [[ -n "${tracked_set[$f]:-}" ]] && continue
        [[ -n "${seen[$f]:-}" ]] && continue
        seen["$f"]=1
        WS_PICKER_DELETED+=("$f")
    done < <(git log --diff-filter=D --name-only --format="" 2>/dev/null)
}

# ------------------------------------------------------------------------------
# ws_format_picker_row <path> <badge-already-colored-or-empty>
# Truncates very long paths in the middle (keeping the start — usually the
# most identifying directory — and the end, usually the filename) so one
# absurdly long path can't push the badge off the end of the terminal.
# ------------------------------------------------------------------------------
ws_format_picker_row() {
    local path="$1"
    local badge="$2"
    local display="$path"
    local maxlen=70
    if [[ ${#path} -gt $maxlen ]]; then
        local keep=$(( (maxlen - 1) / 2 ))
        display="${path:0:$keep}…${path: -$keep}"
    fi
    echo -e "${display}${badge}"
}

WS_FILE_PICKER_HELP_TEXT="Up/Down - move    Enter/Right - open this file's History
Esc/Left - back    / - filter by typing part of a path (case-insensitive)
PgUp/PgDn/Home/End - scroll a long list    q - quit the Explorer
H - toggle showing files that were deleted but still have history
Badges: [M]=modified [A]=added [D]=deleted [R]=renamed [!]=conflict (current
working tree); [deleted] = no longer tracked, shown only when toggled on."

# ------------------------------------------------------------------------------
# ws_file_picker_screen — interactive file picker for File Timeline. Loads
# the tracked-file list ONCE per visit (cheap to re-filter afterward, but
# `git ls-files`/`git log --diff-filter=D` over a huge repo is not something
# to redo on every keystroke), runs from the repo root so the whole
# repository is visible regardless of the caller's cwd, and returns to
# itself (cursor and filter preserved) after a round trip into a file's
# History. Returns 1 if the user quit the whole Explorer from here.
# ------------------------------------------------------------------------------
ws_file_picker_screen() {
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -z "$repo_root" ]]; then
        ws_show_header
        ws_draw_breadcrumb
        echo -e "${RED}[!] Not a git repository — nothing to browse.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return 0
    fi

    local orig_dir="$PWD"
    cd "$repo_root" || return 0
    ws_get_tracked_files

    local show_deleted="false"
    local last_selected_path=""
    local last_filter=""
    local rc=0

    while true; do
        if [[ "$show_deleted" == "true" ]]; then
            ws_get_deleted_files
        else
            WS_PICKER_DELETED=()
        fi
        ws_load_status

        if [[ ${#WS_PICKER_TRACKED[@]} -eq 0 && ${#WS_PICKER_DELETED[@]} -eq 0 ]]; then
            ws_show_header
            WS_BREADCRUMB=("Workspace Explorer" "File Timeline" "Browse")
            ws_draw_breadcrumb
            echo -e "${CYAN}This repository has no tracked files yet — nothing to browse.${NC}"
            read -rsn1 -p "Press any key to continue..."
            cd "$orig_dir" 2>/dev/null || true
            return 0
        fi

        local -a paths=()
        WS_NAV_ITEMS=()
        local p si badge initial_cursor=-1 idx=0
        for p in "${WS_PICKER_TRACKED[@]}" "${WS_PICKER_DELETED[@]}"; do
            paths+=("$p")
            badge=""
            for si in "${!WS_STATUS_PATH[@]}"; do
                if [[ "${WS_STATUS_PATH[$si]}" == "$p" ]]; then
                    case "${WS_STATUS_BADGE[$si]}" in
                        modified) badge="  ${YELLOW}[M]${NC}" ;;
                        staged) badge="  ${GREEN}[M]${NC}" ;;
                        added) badge="  ${GREEN}[A]${NC}" ;;
                        deleted) badge="  ${RED}[D]${NC}" ;;
                        renamed) badge="  ${YELLOW}[R]${NC}" ;;
                        conflict) badge="  ${RED}[!]${NC}" ;;
                    esac
                    break
                fi
            done
            if [[ -z "$badge" ]]; then
                for si in "${!WS_PICKER_DELETED[@]}"; do
                    if [[ "${WS_PICKER_DELETED[$si]}" == "$p" ]]; then
                        badge="  ${RED}[deleted]${NC}"
                        break
                    fi
                done
            fi
            WS_NAV_ITEMS+=("$(ws_format_picker_row "$p" "$badge")")
            [[ "$p" == "$last_selected_path" ]] && initial_cursor=$idx
            ((idx++))
        done

        WS_BREADCRUMB=("Workspace Explorer" "File Timeline" "Browse")
        WS_NAV_TITLE="📜 BROWSE FILES"
        WS_NAV_MARKABLE="false"
        WS_NAV_FILTERABLE="true"
        WS_NAV_VIEWPORT="true"
        WS_NAV_CASE_INSENSITIVE="true"
        WS_NAV_ITEM_NOUN="files"
        WS_NAV_INITIAL_CURSOR="$initial_cursor"
        WS_NAV_INITIAL_FILTER="$last_filter"
        WS_NAV_HELP_TEXT="$WS_FILE_PICKER_HELP_TEXT"
        WS_NAV_EXTRA_KEYS="H"
        local h_label="Show"
        [[ "$show_deleted" == "true" ]] && h_label="Hide"
        WS_NAV_EXTRA_BAR="${CYAN}[H]${NC} ${h_label} deleted files"
        WS_NAV_MARKED_INDICES=()

        ws_list_navigate
        last_filter="$WS_NAV_LAST_FILTER"

        case "$WS_NAV_RESULT" in
            open)
                last_selected_path="${paths[$WS_NAV_SELECTED]}"
                ws_file_timeline_screen "${paths[$WS_NAV_SELECTED]}"
                rc=$?
                cd "$repo_root" 2>/dev/null || true
                if [[ $rc -ne 0 ]]; then
                    cd "$orig_dir" 2>/dev/null || true
                    return 1
                fi
                ;;
            key:H)
                if [[ "$show_deleted" == "true" ]]; then show_deleted="false"; else show_deleted="true"; fi
                if [[ "$WS_NAV_SELECTED" -ge 0 ]]; then
                    last_selected_path="${paths[$WS_NAV_SELECTED]}"
                fi
                ;;
            quit)
                cd "$orig_dir" 2>/dev/null || true
                return 1
                ;;
            back|*)
                cd "$orig_dir" 2>/dev/null || true
                return 0
                ;;
        esac
    done
}

ws_workspace_explorer_pick_file_timeline() {
    ws_show_header
    ws_draw_breadcrumb
    echo -e "${YELLOW}${BOLD}FILE TIMELINE — TYPE A PATH${NC}\n"
    echo -e "${CYAN}Enter the path to a tracked file (relative to the repo root, tab-completes).${NC}"
    local filepath
    read -e -r -p "File path (ENTER with nothing to cancel): " filepath
    if [[ -z "$filepath" ]]; then
        return
    fi
    if ! git ls-files --error-unmatch -- "$filepath" &>/dev/null && [[ ! -e "$filepath" ]]; then
        echo -e "${RED}[!] '${filepath}' doesn't exist and isn't tracked by git.${NC}"
        read -rsn1 -p "Press any key to continue..."
        return
    fi
    ws_file_timeline_screen "$filepath"
}

# ------------------------------------------------------------------------------
# ws_file_timeline_chooser — shown when "File Timeline" is opened from the
# Explorer's top-level menu: browse interactively (the file picker below) or
# type a path manually (the pre-existing behavior above, unchanged). Uses
# the same list navigator as everything else in the Explorer, so Esc/Left/q
# all back out exactly like every other screen.
# ------------------------------------------------------------------------------
ws_file_timeline_chooser() {
    WS_BREADCRUMB=("Workspace Explorer" "File Timeline")
    WS_NAV_ITEMS=(
        "$(echo -e "${GREEN}${BOLD}Browse files interactively${NC}  ${CYAN}(recommended)${NC}")"
        "$(echo -e "${GREEN}${BOLD}Type a file path manually${NC}")"
    )
    WS_NAV_TITLE="📜 FILE TIMELINE"
    WS_NAV_MARKABLE="false"
    WS_NAV_FILTERABLE="false"
    WS_NAV_HELP_TEXT="Up/Down - move    Enter/Right - open    Esc/Left or q - back"
    WS_NAV_EXTRA_KEYS=""
    WS_NAV_EXTRA_BAR=""
    WS_NAV_MARKED_INDICES=()

    ws_list_navigate

    if [[ "$WS_NAV_RESULT" == "open" ]]; then
        case "$WS_NAV_SELECTED" in
            0) ws_file_picker_screen ;;
            1) ws_workspace_explorer_pick_file_timeline ;;
        esac
    fi
}

ws_workspace_explorer() {
    while true; do
        WS_BREADCRUMB=("Workspace Explorer")
        WS_NAV_ITEMS=(
            "$(echo -e "${GREEN}${BOLD}📂 Changes${NC}  ${CYAN}— status, diff, revert${NC}")"
            "$(echo -e "${GREEN}${BOLD}📜 File Timeline${NC}  ${CYAN}— full history of one file${NC}")"
            "$(echo -e "${GREEN}${BOLD}🕒 Project Timeline${NC}  ${CYAN}— every commit in this repo${NC}")"
        )
        WS_NAV_TITLE="🧙 WORKSPACE EXPLORER"
        WS_NAV_MARKABLE="false"
        WS_NAV_FILTERABLE="false"
        WS_NAV_HELP_TEXT="Up/Down - move    Enter/Right - open    Esc/Left or q - leave the Workspace Explorer"
        WS_NAV_EXTRA_KEYS=""
        WS_NAV_EXTRA_BAR=""
        WS_NAV_MARKED_INDICES=()

        ws_list_navigate

        case "$WS_NAV_RESULT" in
            open)
                case "$WS_NAV_SELECTED" in
                    0) ws_changes_screen ;;
                    1) ws_file_timeline_chooser ;;
                    2) ws_project_timeline_screen ;;
                esac
                ;;
            back|quit|*)
                tput cnorm 2>/dev/null || true
                return 0
                ;;
        esac
    done
}
