#!/usr/bin/env bash
# record-coordination-verdict.sh — for /execute: record the verdict a
# coordinated run ends on, so koto can route on it.
#
# This is the default action of execute-coordinated.md's `coord_verdict`
# state. coordination-verdict.sh prints the verdict and its fields, but a koto
# command gate exposes only an exit code, so the fields reach routing and the
# terminal's result the one way koto allows: this script writes them with
# `koto context add`, and the state routes on non-overridable context-matches
# gates over `coord_verdict`.
#
# It reads GitHub (through coordination-verdict.sh) and writes koto context,
# and nothing else: it pushes nothing, merges nothing, and writes nothing to
# GitHub.
#
# Usage:
#   record-coordination-verdict.sh --session <koto-session> --merge true|false
#                                  --plan <path> --slug <slug>
#
#   --session  the koto session to read and write, ^[A-Za-z0-9][A-Za-z0-9._-]*$
#   --merge    the session's MERGE variable (`{{MERGE}}` in the template)
#   --plan     the PLAN path (`{{PLAN_DOC}}`)
#   --slug     the topic slug (`{{PLAN_SLUG}}`)
#
# koto substitutes declared variables into a default_action command but never
# context keys, so the values coord_setup recorded (repos, home_repo,
# coord_branch) and the loop's record (merge_attempts, loop_line) are read here
# with `koto context get`, each checked against its pattern before use.
#
# In order:
#   1. clear coord_verdict, pr, waiting, resume, reason, and step, so an action
#      that fails or times out part-way leaves nothing from an earlier entry
#      for the gates or the result map to read as current;
#   2. read and check the recorded coord_setup values, then run
#      coordination-verdict.sh;
#   3. check every field against its closed pattern: coord_verdict
#      ^(merged|ready|paused|dirty|error)$; pr a PR URL; waiting comma-joined
#      <url>:<human|predecessor>; resume `/execute <plan>[ --merge]`; reason
#      the decision table's conditions plus merge-call-failed,
#      merge-not-observed, and the pause conditions; step ^execute:[a-z-]+$
#      from the closed step set;
#   4. only when every field passed, write the non-empty ones, coord_verdict
#      last.
#
# Exit codes:
#   0   recorded
#   1   coordination-verdict.sh failed, or a field failed its pattern; nothing
#       was written after the clear
#   64  usage error (nothing read or written), or a recorded coord_setup
#       value is missing or invalid (the keys were cleared, nothing written)
#   70  a koto context clear or write failed
#
# Requires: bash 3.2+, jq, gh, koto.
set -uo pipefail

PROG=record-coordination-verdict

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_REPO_LIST='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)*$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'
RE_SLUG='^[a-z0-9-]+$'
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'
RE_VERDICT='^(merged|ready|paused|dirty|error)$'
RE_WAITING_ENTRY='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*:(human|predecessor)$'
RE_RESUME='^/execute [A-Za-z0-9._/-]+\.md( --merge)?$'
RE_REASON='^(merge-not-requested|head-moved|no-checks|base-unprotected|review|workflow-change|merge-method-unresolved|merge-state:[A-Z_]+(:review=(REVIEW_REQUIRED|CHANGES_REQUESTED))?|merge-call-failed|merge-not-observed|predecessor-unmerged|gate-unverified)$'
RE_STEP='^execute:(pr-closed|ready|ci|ci-timeout|status-read|pr-adopt|write-set|dispatch|push|cascade|merge-gate|coord-loop)$'
RE_ATTEMPTS='^([a-z][a-z0-9-]*:(merge-not-observed|merge-call-failed))(,[a-z][a-z0-9-]*:(merge-not-observed|merge-call-failed))*$'
RE_LOOP_LINE='^[a-z:-]+$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: record-coordination-verdict.sh --session <koto-session> --merge true|false --plan <path> --slug <slug>" >&2
    exit 64
}

SESSION=""; MERGE=""; PLAN=""; SLUG=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--merge|--plan|--slug)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION="$2" ;;
                --merge) MERGE="$2" ;;
                --plan) PLAN="$2" ;;
                --slug) SLUG="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
for f in --session --merge --plan --slug; do
    case "$SEEN" in *" $f "*) ;; *) usage_error "$f is required" ;; esac
done
[[ $SESSION =~ $RE_SESSION ]] || usage_error "session [$SESSION] is not a koto session name"
case "$MERGE" in true|false) ;; *) usage_error "--merge must be true or false, got [$MERGE]" ;; esac
[[ $SLUG =~ $RE_SLUG ]] || usage_error "--slug [$SLUG] is outside ^[a-z0-9-]+\$"
[ -n "$PLAN" ] || usage_error "--plan is empty"

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1

# ctx_get <key> -- the value, or empty when the key is absent. koto reports a
# missing key with a non-zero exit and its error on stdout, so the exit status,
# not the output, decides.
ctx_get() {
    local v
    v=$(koto context get "$SESSION" "$1") || return 0
    printf '%s' "$v"
}

ctx_clear() {
    local k
    for k in "$@"; do
        koto context remove "$SESSION" "$k" >/dev/null || {
            echo "$PROG: could not clear context key $k in session $SESSION" >&2
            exit 70
        }
    done
}

ctx_write() { # ctx_write <key> <value>
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null || {
        echo "$PROG: could not write context key $1 in session $SESSION" >&2
        exit 70
    }
}

ctx_clear coord_verdict pr waiting resume reason step

REPOS=$(ctx_get repos)
HOME_REPO=$(ctx_get home_repo)
CB=$(ctx_get coord_branch)
ATTEMPTS=$(ctx_get merge_attempts)
LOOP_LINE=$(ctx_get loop_line)
[[ $REPOS =~ $RE_REPO_LIST ]] || usage_error "the recorded repos [$REPOS] is missing or invalid"
[[ $HOME_REPO =~ $RE_REPO ]] || usage_error "the recorded home_repo [$HOME_REPO] is missing or invalid"
[[ $CB =~ $RE_BRANCH ]] || usage_error "the recorded coord_branch [$CB] is missing or invalid"
[ -z "$ATTEMPTS" ] || [[ $ATTEMPTS =~ $RE_ATTEMPTS ]] || ATTEMPTS=""
[ -z "$LOOP_LINE" ] || [[ $LOOP_LINE =~ $RE_LOOP_LINE ]] || LOOP_LINE=""

set -- --plan "$PLAN" --slug "$SLUG" --repos "$REPOS" --home-repo "$HOME_REPO" \
    --coord-branch "$CB" --merge "$MERGE"
[ -n "$ATTEMPTS" ] && set -- "$@" --attempts "$ATTEMPTS"
[ -n "$LOOP_LINE" ] && set -- "$@" --loop-line "$LOOP_LINE"

OUT=$("$BASH" "$SELF_DIR/coordination-verdict.sh" "$@" </dev/null)
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "$PROG: coordination-verdict.sh exited $RC; nothing recorded" >&2
    exit 1
fi

field() { # field <key> -- the value of the one `<key>=` line
    printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | head -1
}
V=$(field coord_verdict)
PR=$(field pr)
WAITING=$(field waiting)
RESUME=$(field resume)
REASON=$(field reason)
STEP=$(field step)

bad() { echo "$PROG: $*; nothing recorded" >&2; exit 1; }
[[ $V =~ $RE_VERDICT ]] || bad "verdict [$V] is outside ^(merged|ready|paused|dirty|error)\$"
[ -z "$PR" ] || [[ $PR =~ $RE_URL ]] || bad "pr [$PR] is not a pull request URL"
if [ -n "$WAITING" ]; then
    rest="$WAITING"
    while [ -n "$rest" ]; do
        e="${rest%%,*}"
        if [ "$e" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
        [[ $e =~ $RE_WAITING_ENTRY ]] || bad "waiting entry [$e] is not <url>:<human|predecessor>"
    done
fi
[ -z "$RESUME" ] || [[ $RESUME =~ $RE_RESUME ]] || bad "resume [$RESUME] is not an /execute command"
[ -z "$REASON" ] || [[ $REASON =~ $RE_REASON ]] || bad "reason [$REASON] is outside the closed condition set"
[ -z "$STEP" ] || [[ $STEP =~ $RE_STEP ]] || bad "step [$STEP] is outside the closed step set"
if [ "$V" = error ] && [ -z "$STEP" ]; then bad "an error verdict carries no step"; fi

[ -n "$PR" ] && ctx_write pr "$PR"
[ -n "$WAITING" ] && ctx_write waiting "$WAITING"
[ -n "$RESUME" ] && ctx_write resume "$RESUME"
[ -n "$REASON" ] && ctx_write reason "$REASON"
[ -n "$STEP" ] && ctx_write step "$STEP"
# Last, so a gate never sees a verdict whose companion keys are missing.
ctx_write coord_verdict "$V"
echo "$PROG: recorded coord_verdict=$V" >&2
exit 0
