#!/usr/bin/env bash
# record-scope-exit.sh -- writes the facts a /scope terminal result reports.
#
# koto resolves a terminal's `result:` map from literals, variables, and
# `${context.<key>}`, and a transition's assignments cannot read context or a
# script's output. So every result value that comes from the repository -- the
# PLAN's path and mode, the next command, the startable items, the scoping PR --
# is written to context here, by a default action, and read by the result map.
# Nothing here comes from agent evidence.
#
# Run as the default action of four states in skills/scope/koto-templates/scope.md:
#
#   resume_route      --stage resume   the PLAN facts, so row 41's refusal can
#                                      name the next command by mode (R23)
#   cleanup_full_run, cleanup_re_evaluation, cleanup_abandonment, and
#   republish_record  --stage exit     the PLAN facts plus, on an intent run,
#                                      the owned PR, then exit_record
#
# Context keys this script owns, cleared first on every run:
#
#   plan_path            docs/plans/PLAN-<topic>.md when that file exists
#   plan_execution_mode  single-pr | multi-pr | coordinated, from the PLAN's
#                        frontmatter (never from evidence); empty otherwise
#   next                 /execute docs/plans/PLAN-<topic>.md   single-pr, coordinated
#                        /work-on #<first startable>           multi-pr
#                        empty without a PLAN
#   startable            multi-pr only: startable-issues.sh's `#<N> <title>`
#                        lines, newline-joined
#   pr                   --stage exit only: the owned open PR on the current
#                        branch when the intent is continue or stop, empty
#                        when it is none (no gh call is made then)
#   exit_record          --stage exit only: ok | error, written last. error
#                        means the PR lookup could not name exactly one owned
#                        PR (owned-pr.sh zero, several, or a read failure),
#                        which the cleanup states route to done_error with
#                        scope:pr-create.
#
# Keys are written even when empty, so a terminal result lists in `missing`
# only a value that genuinely failed to resolve. `wip_paths` belongs to
# publish-scoping-pr.sh; this script writes it empty only when no publish ran.
#
# Usage:
#   record-scope-exit.sh --session <name> --topic <slug>
#                        --intent <continue|stop|none> --stage <resume|exit>
#
# Exit codes: 0 written; 64 usage error, nothing written; 66 a `koto context`
# call failed. Read-only on GitHub and on the working tree. bash 3.2.
set -uo pipefail

PROG=record-scope-exit
HERE=$(cd "$(dirname "$0")" && pwd)
OWNED="$HERE/../../execute/scripts/owned-pr.sh"
STARTABLE="$HERE/startable-issues.sh"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: record-scope-exit.sh --session <name> --topic <slug> --intent <continue|stop|none> --stage <resume|exit>\n' >&2
    exit 64
}

SESSION_ARG=""; TOPIC=""; INTENT=""; STAGE=""
SEEN=" "
while [ "$#" -gt 0 ]; do
    case "$1" in
        --session|--topic|--intent|--stage)
            [ "$#" -ge 2 ] || usage "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION_ARG="$2" ;;
                --topic) TOPIC="$2" ;;
                --intent) INTENT="$2" ;;
                --stage) STAGE="$2" ;;
            esac
            shift ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
for f in --session --topic --intent --stage; do
    case "$SEEN" in *" $f "*) ;; *) usage "$f is required" ;; esac
done
[[ "$TOPIC" =~ $RE_TOPIC ]] || usage "--topic [$TOPIC] does not match $RE_TOPIC"
case "$INTENT" in continue|stop|none) ;; *) usage "--intent must be continue, stop or none" ;; esac
case "$STAGE" in resume|exit) ;; *) usage "--stage must be resume or exit" ;; esac

SESSION="${KOTO_TICK_SESSION:-$SESSION_ARG}"
[ -n "$SESSION" ] || usage "no session: --session is empty and KOTO_TICK_SESSION is unset"

ctx_remove() {
    koto context remove "$SESSION" "$1" >/dev/null && return 0
    printf '%s: koto context remove failed for %s\n' "$PROG" "$1" >&2
    exit 66
}
ctx_add() {
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null && return 0
    printf '%s: koto context add failed for %s\n' "$PROG" "$1" >&2
    exit 66
}

KEYS="plan_path plan_execution_mode next startable"
[ "$STAGE" = exit ] && KEYS="$KEYS pr exit_record"
for k in $KEYS; do ctx_remove "$k"; done

# --- the PLAN ---------------------------------------------------------------------

PLAN="docs/plans/PLAN-${TOPIC}.md"
PLAN_PATH=""; MODE=""; NEXT=""; START=""

frontmatter_field() { # frontmatter_field <file> <key>
    awk -v k="$2" '
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; inside = 1; next }
        inside && /^---[[:space:]]*$/ { exit }
        inside && index($0, k ":") == 1 {
            v = substr($0, length(k) + 2)
            sub(/[[:space:]]+#.*$/, "", v)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
            print v; exit
        }
    ' "$1"
}

if [ -f "$PLAN" ] && [ -r "$PLAN" ]; then
    PLAN_PATH="$PLAN"
    MODE=$(frontmatter_field "$PLAN" execution_mode)
    case "$MODE" in
        single-pr|coordinated) NEXT="/execute $PLAN" ;;
        multi-pr)
            START=$(bash "$STARTABLE" "$PLAN" 2>/dev/null) || START=""
            FIRST=$(printf '%s\n' "$START" | sed -n '1s/^\(#[0-9][0-9]*\).*/\1/p')
            if [ -n "$FIRST" ]; then NEXT="/work-on $FIRST"; else NEXT="/work-on"; fi
            ;;
        *) MODE="" ;;
    esac
fi

ctx_add plan_path "$PLAN_PATH"
ctx_add plan_execution_mode "$MODE"
ctx_add next "$NEXT"
ctx_add startable "$START"

[ "$STAGE" = exit ] || { printf 'recorded=resume\n'; exit 0; }

# --- the scoping PR ---------------------------------------------------------------

koto context exists "$SESSION" wip_paths >/dev/null || ctx_add wip_paths ""

if [ "$INTENT" = none ]; then
    ctx_add pr ""
    ctx_add exit_record ok
    printf 'recorded=exit\n'
    exit 0
fi

record_error() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    ctx_add pr ""
    ctx_add exit_record error
    printf 'recorded=error\n'
    exit 0
}

BRANCH=$(git symbolic-ref --quiet --short HEAD) || record_error "HEAD is not on a named branch"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner </dev/null) || REPO=""
[[ "$REPO" =~ $RE_REPO ]] || record_error "could not read the repository name"

URL=$(bash "$OWNED" --repo "$REPO" --head "$BRANCH" --state open </dev/null)
RC=$?
[ "$RC" -eq 0 ] || record_error "owned-pr.sh exited $RC"
[ -n "$URL" ] || record_error "no owned open PR on $BRANCH"
[[ "$URL" =~ $RE_PR_URL ]] || record_error "owned-pr.sh printed a URL outside the pattern"

ctx_add pr "$URL"
ctx_add exit_record ok
printf 'recorded=exit\n'
