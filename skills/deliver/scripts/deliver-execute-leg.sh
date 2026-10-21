#!/usr/bin/env bash
# deliver-execute-leg.sh -- /deliver's two reads around the execute leg, run
# as default actions.
#
# koto substitutes only {{VAR}} values and captures into a command or a
# directive, never ${context.<key>}, so a value this run holds in context
# reaches /execute's arguments only through a capture, and a value a lost leg
# should name reaches the result only through a context key a script writes.
# This script is both of those, and nothing else: it makes no GitHub call and
# no repository write.
#
# Modes:
#
#   handover   mode_route's default action, captured as EXEC_HANDOVER, which
#              execute_run's directive appends to /execute's arguments. It
#              runs scripts/plan-mode.sh on docs/plans/PLAN-<topic>.md. On a
#              coordinated PLAN (plan-mode.sh exit 10) it reads `checked_pr`,
#              the PR scoped_check verified (the one /scope published), from
#              this session's context and prints exactly
#                --coordination-pr <url>
#              followed by ` --store <value>` when --store is not empty, so
#              /execute's setup checks the coordination PR and the store it
#              was handed (a single-pr /execute refuses both flags, which is
#              why nothing else gets them). On any other PLAN it prints
#                none
#              which the directive reads as "append nothing".
#   lost       execute_lost's default action, on the way to done_error when
#              the execute leg was refused or its request isn't in this host's
#              request store. It reads `koto status execute-<topic>` (read
#              only) and writes the execute session's state to this session's
#              `execute_state` key, which the terminals' result maps carry:
#              its current_state when that matches ^[a-z][a-z0-9_]*$ (a
#              session koto removed at its terminal still reports its state),
#              `absent` when koto answers that no such session exists here,
#              and `unreadable` for anything else. It prints
#                execute_state=<value>
#
# Usage:
#   deliver-execute-leg.sh handover --topic <slug> [--session <name>] [--store github|session|""]
#   deliver-execute-leg.sh lost --topic <slug> [--session <name>]
#
# The session is koto's $KOTO_TICK_SESSION when koto set it, else --session,
# as deliver-probe.sh takes it.
#
# Exit codes:
#   0   handover: a line was printed; lost: execute_state was written
#   64  usage error (a topic, session or store outside its pattern); nothing
#       read or written
#   66  handover: a `koto context` read failed, or on a coordinated PLAN the
#       session holds no checked_pr or one outside the PR-URL pattern
#       (scoped_check's gate guarantees one, so this is a broken run, stopped
#       loudly rather than handed to /execute without its PR); lost: the
#       `koto context add` failed
#
# Reads koto's context and status and the PLAN's frontmatter; writes only this
# session's execute_state. bash 3.2.
set -uo pipefail

PROG=deliver-execute-leg
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/../../.." && pwd)
PLAN_MODE="$PLUGIN/scripts/plan-mode.sh"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_STORE='^(github|session)?$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
RE_STATE='^[a-z][a-z0-9_]*$'

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: deliver-execute-leg.sh handover --topic <slug> [--session <name>] [--store github|session]\n' >&2
    printf '       deliver-execute-leg.sh lost --topic <slug> [--session <name>]\n' >&2
    exit 64
}

MODE="${1:-}"
case "$MODE" in
    handover|lost) shift ;;
    *) usage "the first argument must be handover or lost" ;;
esac
TOPIC=""; SESSION_ARG=""; STORE=""; SEEN=" "
while [ "$#" -gt 0 ]; do
    case "$1" in
        --topic|--session|--store)
            [ "$#" -ge 2 ] || usage "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --topic) TOPIC="$2" ;;
                --session) SESSION_ARG="$2" ;;
                --store)
                    [ "$MODE" = handover ] || usage "--store applies only to handover"
                    STORE="$2" ;;
            esac
            shift ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
[[ "$TOPIC" =~ $RE_TOPIC ]] || usage "--topic [$TOPIC] does not match $RE_TOPIC"
[[ "$STORE" =~ $RE_STORE ]] || usage "--store [$STORE] is not github or session"
SESSION="${KOTO_TICK_SESSION:-$SESSION_ARG}"
[[ "$SESSION" =~ $RE_SESSION ]] || usage "no usable session: --session is empty or invalid and KOTO_TICK_SESSION is unset"

case "$MODE" in
handover)
    rc=0
    "$BASH" "$PLAN_MODE" "docs/plans/PLAN-$TOPIC.md" </dev/null >/dev/null || rc=$?
    if [ "$rc" -ne 10 ]; then
        printf 'none\n'
        exit 0
    fi
    # Only `exists` answering 1 means the key is absent; any other answer is
    # a failed read.
    erc=0
    koto context exists "$SESSION" checked_pr </dev/null >/dev/null || erc=$?
    case "$erc" in
        0) ;;
        1) printf '%s: the session holds no checked_pr on a coordinated PLAN; scoped_check should have written it\n' "$PROG" >&2
           exit 66 ;;
        *) printf '%s: koto context exists failed for checked_pr\n' "$PROG" >&2
           exit 66 ;;
    esac
    PR=$(koto context get "$SESSION" checked_pr </dev/null) || {
        printf '%s: koto context get failed for checked_pr\n' "$PROG" >&2
        exit 66
    }
    [[ "$PR" =~ $RE_PR_URL ]] || {
        printf '%s: checked_pr is not a pull request URL; nothing was handed to /execute\n' "$PROG" >&2
        exit 66
    }
    if [ -n "$STORE" ]; then
        printf -- '--coordination-pr %s --store %s\n' "$PR" "$STORE"
    else
        printf -- '--coordination-pr %s\n' "$PR"
    fi
    exit 0
    ;;
lost)
    src=0
    ST=$(koto status "execute-$TOPIC" </dev/null) || src=$?
    STATE=unreadable
    if [ "$src" -eq 0 ]; then
        cur=$(printf '%s' "$ST" | jq -r 'if type == "object" and (.current_state | type) == "string" then .current_state else "" end') || cur=""
        [[ "$cur" =~ $RE_STATE ]] && STATE="$cur"
    elif [ "$src" -eq 2 ]; then
        nf=$(printf '%s' "$ST" | jq -r 'if type == "object" and (.error | type) == "string" and (.error | test("not found")) then "yes" else "no" end') || nf=no
        [ "$nf" = yes ] && STATE=absent
    fi
    printf '%s' "$STATE" | koto context add "$SESSION" execute_state >/dev/null || {
        printf '%s: koto context add failed for execute_state\n' "$PROG" >&2
        exit 66
    }
    printf 'execute_state=%s\n' "$STATE"
    exit 0
    ;;
esac
