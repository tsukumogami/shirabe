#!/usr/bin/env bash
# run-intake.sh -- the default action of /scope's `intake` state.
#
# koto has already checked every argument a pattern can express, at `koto
# init`. What is left needs the working tree, and this script runs it:
#
#   1. resolve-intent.sh      the effective intent, RUN_INTENT, printed on
#                             stdout for koto to capture
#   2. check-upstream.sh      the --upstream battery (wip, tracked, confined,
#                             basename)
#   3. check-recorded-intent.sh
#                             an explicit --intent that differs from the
#                             intent an unfinished run already recorded
#
# and writes the verdict to the session's context, where `intake`'s
# non-overridable context-matches gates route on it. A command gate could not
# do this: it exposes only an exit code, so a reason or a recorded value
# printed by a check would never reach routing or the terminal's result.
#
# Context keys this script owns, cleared first on every run so a re-entry
# never routes on a value an earlier entry wrote:
#
#   intake_verdict  ok | refused | error   (written last)
#   reason          on refused: upstream-wip | upstream-untracked |
#                   upstream-outside | upstream-basename | intent-mismatch
#   recorded        on intent-mismatch: continue | stop | none
#
# A reason or recorded value outside those sets is not written, and the
# verdict becomes error: a check printing something unexpected is a check this
# script cannot vouch for. A check that cannot read what it needs (exit 2)
# also makes the verdict error. The verdict is written after the keys it
# explains, so a run interrupted mid-write leaves no verdict, which `intake`
# routes to done_error.
#
# The session is koto's own $KOTO_TICK_SESSION when koto set it, and the
# --session argument otherwise; the template passes "scope-{{TOPIC}}", the
# name scope-open.sh opens.
#
# Usage:
#   run-intake.sh --session <name> --topic <slug> --intent-flag <value>
#                 --upstream <value>
#
# Output: exactly one line on stdout, RUN_INTENT (continue, stop, or none).
# koto's capture refuses an empty value, so a line is printed even when the
# verdict is error: INTENT_FLAG when it is non-empty, else none.
#
# Exit codes:
#   0   the verdict was written (ok, refused, or error)
#   64  a usage error; nothing written
#   66  a `koto context` call failed; koto reports the action as failed and
#       the state's fallback tells the agent what to do
#
# Read-only apart from koto's context store: it writes no file in the working
# tree and makes no network or gh call. bash 3.2.

set -uo pipefail

PROG=run-intake.sh
HERE=$(cd "$(dirname "$0")" && pwd)

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_REASON='^(upstream-wip|upstream-untracked|upstream-outside|upstream-basename|intent-mismatch)$'
RE_RECORDED='^(continue|stop|none)$'

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: run-intake.sh --session <name> --topic <slug> --intent-flag <value> --upstream <value>\n' >&2
    exit 64
}

SESSION_ARG=""
TOPIC=""
FLAG=""
UPSTREAM=""
SEEN_SESSION=0
SEEN_TOPIC=0
SEEN_FLAG=0
SEEN_UPSTREAM=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --session)     [ "$#" -ge 2 ] || usage "--session requires a value"; SESSION_ARG="$2"; SEEN_SESSION=$((SEEN_SESSION + 1)); shift ;;
        --topic)       [ "$#" -ge 2 ] || usage "--topic requires a value"; TOPIC="$2"; SEEN_TOPIC=$((SEEN_TOPIC + 1)); shift ;;
        --intent-flag) [ "$#" -ge 2 ] || usage "--intent-flag requires a value"; FLAG="$2"; SEEN_FLAG=$((SEEN_FLAG + 1)); shift ;;
        --upstream)    [ "$#" -ge 2 ] || usage "--upstream requires a value"; UPSTREAM="$2"; SEEN_UPSTREAM=$((SEEN_UPSTREAM + 1)); shift ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done

[ "$SEEN_SESSION" -eq 1 ] || usage "--session is required once"
[ "$SEEN_TOPIC" -eq 1 ] || usage "--topic is required once"
[ "$SEEN_FLAG" -eq 1 ] || usage "--intent-flag is required once"
[ "$SEEN_UPSTREAM" -eq 1 ] || usage "--upstream is required once"

SESSION="${KOTO_TICK_SESSION:-$SESSION_ARG}"
[ -n "$SESSION" ] || usage "no session: --session is empty and KOTO_TICK_SESSION is unset"

ctx_remove() {
    koto context remove "$SESSION" "$1" >/dev/null && return 0
    printf '%s: koto context remove failed for %s on session %s\n' "$PROG" "$1" "$SESSION" >&2
    exit 66
}

ctx_add() {
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null && return 0
    printf '%s: koto context add failed for %s on session %s\n' "$PROG" "$1" "$SESSION" >&2
    exit 66
}

# The line koto captures when intent could not be resolved.
fallback_intent() {
    case "$FLAG" in
        continue|stop) printf '%s' "$FLAG" ;;
        *) printf 'none' ;;
    esac
}

# finish <verdict> <run-intent> [<reason> [<recorded>]]
finish() {
    local verdict="$1" intent="$2" reason="${3:-}" recorded="${4:-}"
    if [ "$verdict" = "refused" ]; then
        [ -n "$reason" ] && ctx_add reason "$reason"
        [ -n "$recorded" ] && ctx_add recorded "$recorded"
    fi
    ctx_add intake_verdict "$verdict"
    printf '%s\n' "$intent"
    exit 0
}

# --- clear the keys this script owns -------------------------------------------

ctx_remove intake_verdict
ctx_remove reason
ctx_remove recorded

# --- the checks -------------------------------------------------------------------

if ! [[ "$TOPIC" =~ $RE_TOPIC ]]; then
    printf '%s: topic does not match %s; no state file path can be composed\n' "$PROG" "$RE_TOPIC" >&2
    finish error "$(fallback_intent)"
fi
STATE_FILE="wip/scope_${TOPIC}_state.md"

RUN_INTENT=$(bash "$HERE/resolve-intent.sh" --intent-flag "$FLAG" --state-file "$STATE_FILE")
RC=$?
if [ "$RC" -ne 0 ] || ! [[ "$RUN_INTENT" =~ $RE_RECORDED ]]; then
    printf '%s: resolve-intent.sh could not resolve the intent (exit %s)\n' "$PROG" "$RC" >&2
    finish error "$(fallback_intent)"
fi

OUT=$(bash "$HERE/check-upstream.sh" --upstream "$UPSTREAM")
RC=$?
case "$RC" in
    0) ;;
    1)
        REASON=$(printf '%s\n' "$OUT" | sed -n '1p')
        if [[ "$REASON" =~ $RE_REASON ]] && [ "$REASON" != "intent-mismatch" ]; then
            finish refused "$RUN_INTENT" "$REASON"
        fi
        printf '%s: check-upstream.sh printed a reason outside the closed set\n' "$PROG" >&2
        finish error "$RUN_INTENT"
        ;;
    *)
        printf '%s: check-upstream.sh could not decide (exit %s)\n' "$PROG" "$RC" >&2
        finish error "$RUN_INTENT"
        ;;
esac

OUT=$(bash "$HERE/check-recorded-intent.sh" --intent-flag "$FLAG" --state-file "$STATE_FILE")
RC=$?
case "$RC" in
    0) ;;
    1)
        REASON=$(printf '%s\n' "$OUT" | sed -n '1p')
        RECORDED=$(printf '%s\n' "$OUT" | sed -n 's/^recorded=//p' | sed -n '1p')
        if [ "$REASON" = "intent-mismatch" ] && [[ "$RECORDED" =~ $RE_RECORDED ]]; then
            finish refused "$RUN_INTENT" "$REASON" "$RECORDED"
        fi
        printf '%s: check-recorded-intent.sh printed a reason or recorded value outside the closed set\n' "$PROG" >&2
        finish error "$RUN_INTENT"
        ;;
    *)
        printf '%s: check-recorded-intent.sh could not decide (exit %s)\n' "$PROG" "$RC" >&2
        finish error "$RUN_INTENT"
        ;;
esac

finish ok "$RUN_INTENT"
