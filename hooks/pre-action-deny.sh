#!/usr/bin/env bash
#
# pre-action-deny.sh - the shirabe plugin's Bash PreToolUse hook
#
# Claude Code runs this before every Bash call (hooks/hooks.json), with the
# PreToolUse JSON on stdin. The checking lives in the shirabe binary's
# `pre-action-hook` subcommand; this script finds the binary, runs it, and
# stands in for it when it can't run. It denies a `gh pr create` or `gh pr
# edit` breaking a PR-body rule and a `git push` that would send a commit with
# an AI-attribution trailer, and gives no decision on anything else
# (docs/designs/DESIGN-pre-action-denies.md).
#
# What it does, in order:
#   1. Reads stdin once. SHIRABE_PRE_ACTION_HOOK=off, exactly, gives no
#      decision on every call.
#   2. Finds `shirabe` on the absolute PATH entries (a relative entry is
#      skipped, so a repository can't plant one), then at
#      ~/.shirabe/bin/shirabe, where install.sh puts it.
#   3. Pipes the input into `shirabe pre-action-hook --plugin-root <root>
#      --rules "$RULE_IDS"`, as a background job beside a 26-second watchdog
#      that kills it, so a hang ends inside Claude Code's 30 seconds. The
#      --rules list is the version handshake: a binary that doesn't check
#      every rule on it exits non-zero.
#   4. Passes the binary's answer through only when it exited 0 and printed
#      nothing or one deny line. Anything else (no binary, a non-zero exit, a
#      kill, other output, `allow` or `ask`) is a binary that can't run, and
#      the coarse test decides: a command whose text names `gh` ... `pr` ...
#      `create`|`edit` or `git` ... `push` gets a fixed deny naming the
#      binary, and every other command gets no decision.
#
# Security: the input is attacker-shaped. It is never evaluated, never
# interpolated into the output, and reaches the binary through a pipe, not a
# here-string (bash before 5.1 backs a here-string with a temporary file).
# The deny is built from constant text and RULE_IDS. A hostile binary on PATH
# can't approve a command: only a deny is passed through.
#
# Requires bash 3.2 and POSIX sed, tr and awk; no jq. Always exits 0.

# The rules this hook denies, in registry order. scripts/check-rule-registry.sh
# reads this line against the registry's `deny` fields, and the binary checks
# it against its own table.
RULE_IDS="pr-body/conventional-title pr-body/one-separator pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/conformance commit/no-ai-trailer"

# How long the binary may run before the watchdog kills it. Its own deadline
# is 25 seconds; Claude Code's is 30.
WATCHDOG_SECONDS=26

DENY_PREFIX='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",'

INPUT=$(cat)

if [ "${SHIRABE_PRE_ACTION_HOOK-}" = "off" ]; then
    exit 0
fi

# Prints the path of the shirabe binary, or nothing.
find_shirabe() {
    local rest dir
    rest="${PATH-}:"
    while [ -n "$rest" ]; do
        dir=${rest%%:*}
        rest=${rest#*:}
        case "$dir" in
            /*)
                if [ -f "$dir/shirabe" ] && [ -x "$dir/shirabe" ]; then
                    printf '%s' "$dir/shirabe"
                    return
                fi
                ;;
        esac
    done
    case "${HOME-}" in
        /*)
            if [ -f "$HOME/.shirabe/bin/shirabe" ] && [ -x "$HOME/.shirabe/bin/shirabe" ]; then
                printf '%s' "$HOME/.shirabe/bin/shirabe"
            fi
            ;;
    esac
}

# Runs the binary under the watchdog. Prints its output, then a newline and
# its exit status (137 when the watchdog killed it).
#
# Monitor mode gives the binary's job and the watchdog process groups of
# their own, so a kill takes every process in the group. Killing only the
# binary would leave a child it started (a shim's real binary, a stub's
# `sleep`) holding this command substitution's pipe open, and the read would
# wait for that child instead of the watchdog. Each kill also names the
# process itself, in case its group was never set up: bash sets a job's group
# from the parent and the child both, and on a rare race the child's call
# fails (it says so on stderr, which the caller discards).
run_shirabe() {
    local bin="$1" job dog status
    set -m
    (printf '%s' "$INPUT" | exec "$bin" pre-action-hook --plugin-root "${CLAUDE_PLUGIN_ROOT-}" --rules "$RULE_IDS") 2>/dev/null &
    job=$!
    (sleep "$WATCHDOG_SECONDS"; kill -KILL -- "-$job" "$job") >/dev/null 2>&1 &
    dog=$!
    wait "$job"
    status=$?
    kill -KILL -- "-$dog" "$dog" 2>/dev/null
    printf '\n%s' "$status"
}

# The coarse "named in the text" test (PRD Definitions), on the raw input:
# true when it names `gh`, later `pr`, later `create` or `edit`, or `git`,
# later `push`, as separate words, ignoring case and quotes.
#
# The command reaches this script as a JSON string, so its escapes are turned
# back into characters first: without that, a newline in the command is the
# two characters `\n` and glues `git` to the word before it. A backslash-
# newline is read as a space, as the shell joins the two lines. Escaped
# backslashes are set aside first, so `\\n` stays a backslash and an `n`. A
# decoded newline is written as a space: like every character outside
# [a-z0-9_-], it only separates words.
#
# The text is then lowercased and split one word per line, and awk looks for
# the words in order. That is the binary's own reading (named_in_text) and
# takes time linear in the input; a grep -E with `.*` between the words is
# quadratic on a few megabytes of `gh` and `pr`, which would push a run past
# Claude Code's 30 seconds. hooks/testdata/coarse-cases.tsv holds both to the
# same answers.
names_guarded() {
    local sep tab cr
    sep=$(printf '\001')
    tab=$(printf '\t')
    cr=$(printf '\r')
    printf '%s' "$INPUT" | LC_ALL=C sed \
        -e "s/\\\\\\\\/$sep/g" \
        -e "s/$sep\\\\n/ /g" \
        -e 's/\\n/ /g' \
        -e "s/\\\\r/$cr/g" \
        -e "s/\\\\t/$tab/g" \
        -e 's/\\"/"/g' \
        -e "s/$sep/\\\\/g" |
        LC_ALL=C tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' |
        LC_ALL=C tr -cs 'a-z0-9_-' '\n' |
        LC_ALL=C awk '
            $0 == "gh" { gh = 1; next }
            gh && $0 == "pr" { pr = 1; next }
            pr && ($0 == "create" || $0 == "edit") { found = 1; exit }
            $0 == "git" { git = 1; next }
            git && $0 == "push" { found = 1; exit }
            END { exit !found }
        '
}

# The fixed deny for a command the binary couldn't check. Constant text and
# the RULE_IDS ids only, already JSON-safe: `\n` is a JSON escape, not a
# newline, and nothing here holds a quote or a backslash of its own.
print_binary_deny() {
    local ids="${RULE_IDS// /, }"
    printf '%s' "$DENY_PREFIX"
    printf '%s' '"permissionDecisionReason":"'
    printf '%s' 'shirabe could not check this command (binary: the shirabe binary is missing, older than this plugin, or failed to run), so it is denied.'
    printf '%s' '\nIt names `gh pr create`, `gh pr edit` or `git push`, which are guarded by: '
    printf '%s' "$ids"
    printf '%s' '.\nFix: ask the user to install or update the shirabe binary with `curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/main/install.sh | sh`, then run the command again.'
    printf '%s' '\nIf you believe this deny is wrong, ask the user.'
    printf '%s\n' '"}}'
}

BIN=$(find_shirabe)
if [ -n "$BIN" ]; then
    RESULT=$(run_shirabe "$BIN" 2>/dev/null)
    STATUS=${RESULT##*$'\n'}
    OUTPUT=${RESULT%$'\n'*}
    # One trailing newline is the binary's println.
    OUTPUT=${OUTPUT%$'\n'}
    if [ "$STATUS" = "0" ]; then
        case "$OUTPUT" in
            "")
                exit 0
                ;;
            *$'\n'*)
                ;;
            "$DENY_PREFIX"*'"}}')
                printf '%s\n' "$OUTPUT"
                exit 0
                ;;
        esac
    fi
fi

if names_guarded; then
    print_binary_deny
fi
exit 0
