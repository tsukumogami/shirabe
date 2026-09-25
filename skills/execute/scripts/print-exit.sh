#!/usr/bin/env bash
# print-exit.sh — for /execute: render the exit lines from the terminal result.
#
# The agent never composes /execute's exit summary. The template's terminal
# states declare a `result:` map (outcome, step, reason, pr, repos, resume,
# waiting), koto resolves it on the tick that lands in the terminal, and this
# script prints the human-facing lines from it. Every value is checked against
# a closed pattern first, and anything that fails its pattern is dropped rather
# than printed, so a value an agent or a stale key smuggled into context never
# reaches the summary as text.
#
# Usage:
#   print-exit.sh [<file>]     read the JSON from <file>, or from stdin
#   print-exit.sh --refused    a koto init refusal: no session, no result
#
# The JSON may be the terminal `koto next` response, `koto status` on a
# retained terminal, or the bare result object ({status, summary, payload});
# the payload is read from `.result.payload` or `.payload`, the status from
# `.result.status` or `.status`.
#
# Output, one key=value per line, in this order:
#
#   outcome=<merged|ready-awaiting-merge|paused-for-review|paused-awaiting-merges|error>
#                                          always; an unreadable or unknown
#                                          outcome prints error
#   step=<execute:...>                     on error only
#   exit=<full-run|abandonment-forced|re-evaluation>
#                                          the state file's exit: value, per
#                                          SKILL.md's outcome-versus-exit table;
#                                          absent on a pause and on a refusal
#   repos=<owner/repo[,owner/repo...]>     the write set, fixed at start
#   pr=<url>                               on merged
#   pr=<url> waiting=<human|predecessor> reason=<condition>
#                                          per unmerged PR (reason only when
#                                          the result carries one)
#   resume=<command>                       on a pause
#   note=the PR may still be queued and may merge later
#                                          on reason merge-not-observed
#
# A refusal (--refused, or a result whose outcome is koto's `refused`) prints
# `outcome=error` and `step=execute:refused`; `refused` itself is never printed
# after `outcome=`.
#
# Exit codes: 0 lines printed; 64 usage error; 65 the input is not JSON.
#
# Requires: bash 3.2+, jq.
set -uo pipefail

PROG=print-exit

RE_OUTCOME='^(merged|ready-awaiting-merge|paused-for-review|paused-awaiting-merges|error)$'
RE_STEP='^execute:[a-z][a-z0-9_-]*$'
RE_REPO_LIST='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)*$'
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'
# The merge decision table's conditions, the two merge-step outcomes, and the
# coordinated pause conditions.
RE_REASON='^(merge-not-requested|head-moved|no-checks|base-unprotected|review|workflow-change|merge-method-unresolved|merge-state:[A-Z_]+(:review=(REVIEW_REQUIRED|CHANGES_REQUESTED))?|merge-call-failed|merge-not-observed|predecessor-unmerged|gate-unverified)$'
RE_ROLE='^(human|predecessor)$'
RE_RESUME='^/execute [A-Za-z0-9._/-]+\.md( --[a-z][a-z-]*)*$'

refused() {
    printf 'outcome=error\n'
    printf 'step=execute:refused\n'
    exit 0
}

if [ $# -gt 1 ]; then
    echo "usage: print-exit.sh [--refused | <file>]" >&2
    exit 64
fi
if [ "${1:-}" = "--refused" ]; then
    refused
fi

if [ $# -eq 1 ]; then
    [ -f "$1" ] || { echo "$PROG: no such file: $1" >&2; exit 64; }
    INPUT=$(cat -- "$1")
else
    INPUT=$(cat)
fi

command -v jq >/dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 65; }
printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null || {
    echo "$PROG: the input is not a JSON object" >&2
    exit 65
}

# field <name> — a payload value as one line, or empty (a non-string or a
# value holding a newline reads as empty, so it can never pass a pattern).
field() {
    printf '%s' "$INPUT" | jq -r --arg k "$1" '
        ((.result.payload // .payload // {}) | if type == "object" then .[$k] else null end) as $v
        | if ($v | type) == "string" and ($v | test("\n") | not) then $v else "" end'
}
STATUS=$(printf '%s' "$INPUT" | jq -r '(.result.status // .status // "") | if type == "string" then . else "" end')

OUTCOME=$(field outcome)
STEP=$(field step)
REASON=$(field reason)
PR=$(field pr)
REPOS=$(field repos)
RESUME=$(field resume)
WAITING=$(field waiting)

[ "$OUTCOME" = "refused" ] && refused

if ! [[ $OUTCOME =~ $RE_OUTCOME ]]; then
    # A terminal whose result carries no readable outcome (a session from a
    # template older than the result maps) is reported as an error the run
    # could not read, never as a success.
    OUTCOME=error
    STEP=execute:status-read
fi
[[ $STEP =~ $RE_STEP ]] || STEP=""
[[ $REASON =~ $RE_REASON ]] || REASON=""
[[ $PR =~ $RE_URL ]] || PR=""
[[ $REPOS =~ $RE_REPO_LIST ]] || REPOS=""
[[ $RESUME =~ $RE_RESUME ]] || RESUME=""

printf 'outcome=%s\n' "$OUTCOME"
if [ "$OUTCOME" = "error" ]; then
    [ -n "$STEP" ] || STEP=execute:status-read
    printf 'step=%s\n' "$STEP"
fi

EXIT=""
case "$OUTCOME" in
    merged) EXIT=full-run ;;
    ready-awaiting-merge)
        # The DIRTY route ends at done_blocked, a failure terminal, and is a
        # forced stop even though nothing errored.
        if [ "$STATUS" = "failure" ]; then EXIT=abandonment-forced; else EXIT=full-run; fi
        ;;
    error)
        if [ "$STEP" = "execute:re-evaluation" ]; then EXIT=re-evaluation; else EXIT=abandonment-forced; fi
        ;;
esac
[ -n "$EXIT" ] && printf 'exit=%s\n' "$EXIT"

[ -n "$REPOS" ] && printf 'repos=%s\n' "$REPOS"

if [ "$OUTCOME" = "merged" ]; then
    [ -n "$PR" ] && printf 'pr=%s\n' "$PR"
else
    # One entry per unmerged PR, `<url>:<role>` comma-joined. A URL carries a
    # colon, so each entry splits on its last one.
    printed=0
    rest="$WAITING"
    while [ -n "$rest" ]; do
        entry="${rest%%,*}"
        if [ "$entry" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
        url="${entry%:*}"
        role="${entry##*:}"
        if [[ $url =~ $RE_URL ]] && [[ $role =~ $RE_ROLE ]]; then
            line="pr=$url waiting=$role"
            [ -n "$REASON" ] && line="$line reason=$REASON"
            printf '%s\n' "$line"
            printed=1
        fi
    done
    if [ "$printed" -eq 0 ] && [ -n "$PR" ]; then
        line="pr=$PR waiting=human"
        [ -n "$REASON" ] && line="$line reason=$REASON"
        printf '%s\n' "$line"
    fi
fi

case "$OUTCOME" in
    paused-for-review|paused-awaiting-merges)
        [ -n "$RESUME" ] && printf 'resume=%s\n' "$RESUME"
        ;;
esac

if [ "$REASON" = "merge-not-observed" ]; then
    printf 'note=the PR may still be queued and may merge later\n'
fi
exit 0
