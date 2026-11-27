#!/usr/bin/env bash
#
# question-guard.sh - the shirabe plugin's PreToolUse hook on the question tool
#
# Claude Code runs this before every AskUserQuestion call (hooks/hooks.json),
# with the PreToolUse JSON on stdin. It denies a question prompt opened in a
# turn no person typed, and leaves alone one opened in a turn a person typed
# after the session's first, in any session, including one a skill the person
# invoked opens later in that turn (PRD-decision-escalation-ladder R27). A
# session's first turn can't be told from a dispatched brief, so it follows
# the run mode. The deciding lives in the shirabe
# binary's `hook question-guard` subcommand, which reads the turn's origin
# from the session record the input names and the run mode from
# CLAUDE_CODE_SESSION_ATTENDED (docs/spikes/SPIKE-question-guard-turn-origin.md).
#
# What it does, in order:
#   1. Reads stdin once. SHIRABE_PRE_ACTION_HOOK=off, exactly, gives no
#      decision on every call, as it does for the Bash hook.
#   2. Gives no decision, without starting the binary, when the input
#      doesn't name the question tool at all.
#   3. Finds `shirabe` on the absolute PATH entries (a relative entry is
#      skipped, so a repository can't plant one), then at
#      ~/.shirabe/bin/shirabe, where install.sh puts it.
#   4. Pipes the input into `shirabe hook question-guard` as a background job
#      beside a 4-second watchdog that kills it, so a hang ends inside the 5
#      seconds hooks.json gives the hook.
#   5. Passes the binary's answer through only when it exited 0 and printed
#      nothing or one complete deny line.
#
# Fails open: with no binary, a binary that exits non-zero, is killed, or
# prints anything else, the hook gives no decision and the prompt opens.
# Without the binary it can read neither the turn's origin nor the run mode,
# and the requirement refuses a prompt only where the session is known to be
# unattended or the turn known not to be a person's. Unlike the Bash hook,
# there is no fallback deny.
#
# Security: the input is attacker-shaped. It is never evaluated, never
# interpolated into the output, and reaches the binary through a pipe. A
# hostile binary on PATH can't approve a call: only a deny is passed through.
#
# Requires bash 3.2; no jq. Always exits 0.

# How long the binary may run before the watchdog kills it; hooks.json's
# timeout is 5 seconds.
WATCHDOG_SECONDS=4

DENY_PREFIX='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",'

INPUT=$(cat)

if [ "${SHIRABE_PRE_ACTION_HOOK-}" = "off" ]; then
    exit 0
fi

case "$INPUT" in
    *AskUserQuestion*) ;;
    *) exit 0 ;;
esac

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
# its exit status (137 when the watchdog killed it). Monitor mode gives the
# binary's job and the watchdog process groups of their own, so a kill takes
# a child the binary started too; hooks/pre-action-deny.sh explains why.
run_shirabe() {
    local bin="$1" job dog status
    set -m
    (printf '%s' "$INPUT" | exec "$bin" hook question-guard) 2>/dev/null &
    job=$!
    (sleep "$WATCHDOG_SECONDS"; kill -KILL -- "-$job" "$job") >/dev/null 2>&1 &
    dog=$!
    wait "$job"
    status=$?
    kill -KILL -- "-$dog" "$dog" 2>/dev/null
    printf '\n%s' "$status"
}

BIN=$(find_shirabe)
[ -n "$BIN" ] || exit 0

RESULT=$(run_shirabe "$BIN" 2>/dev/null)
STATUS=${RESULT##*$'\n'}
OUTPUT=${RESULT%$'\n'*}
# One trailing newline is the binary's println.
OUTPUT=${OUTPUT%$'\n'}
[ "$STATUS" = "0" ] || exit 0
case "$OUTPUT" in
    *$'\n'*)
        ;;
    "$DENY_PREFIX"*'"}}')
        printf '%s\n' "$OUTPUT"
        ;;
esac
exit 0
