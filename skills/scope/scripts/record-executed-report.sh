#!/usr/bin/env bash
# record-executed-report.sh -- the default action of /scope's `executed_report`.
#
# An executed single-pr topic has no PLAN left: the cascade deleted it and moved
# the DESIGN to docs/designs/current/. What /scope can still report, on an
# intent run, is the pull request that carried the work. This script finds it
# through the shared ownership filter, reads its state, and writes the answer to
# the session's context, where `executed_report`'s non-overridable
# context-matches gates route on it. A command gate could not carry the PR's URL
# or state: it exposes only an exit code.
#
# Context keys this script owns, cleared first on every run so a re-entry never
# routes on a value an earlier entry wrote:
#
#   executed_verdict   one | none | several | read-failed   (written last)
#   executed_pr        on one: the PR's URL, checked against
#                      ^https://github\.com/<owner>/<repo>/pull/<n>$
#   executed_pr_state  on one: merged | open | closed
#
# The lookup is skills/execute/scripts/owned-pr.sh --state all on the current
# branch, called unchanged. /scope maps its codes in one place, here and in
# publish-scoping-pr.sh (see SKILL.md, "Owned-PR lookup"):
#
#   one URL, exit 0     -> one, then `gh pr view <url> --json state`
#   empty, exit 0       -> none         (a foreign-only branch included)
#   exit 3              -> several
#   exit 2, or anything else, or a URL outside the pattern -> read-failed
#
# `executed_report` sends one with merged or open to done_executed, and every
# other verdict, an absent one included, to done_error with scope:pr-create.
# A foreign PR's URL is never written: owned-pr.sh prints only a survivor.
#
# Usage:
#   record-executed-report.sh --session <name> --topic <slug>
#
# The session is koto's own $KOTO_TICK_SESSION when koto set it, else
# --session. The repository is `gh repo view --json nameWithOwner`.
#
# Exit codes:
#   0   a verdict was written (any of the four)
#   64  usage error; nothing written
#   66  a `koto context` call failed
#
# Read-only on GitHub and on the working tree: its only gh calls are
# `gh repo view`, owned-pr.sh's reads, and `gh pr view`. bash 3.2.
set -uo pipefail

PROG=record-executed-report
HERE=$(cd "$(dirname "$0")" && pwd)
OWNED="$HERE/../../execute/scripts/owned-pr.sh"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: record-executed-report.sh --session <name> --topic <slug>\n' >&2
    exit 64
}

SESSION_ARG=""; TOPIC=""; SEEN_S=0; SEEN_T=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --session) [ "$#" -ge 2 ] || usage "--session needs a value"; SESSION_ARG="$2"; SEEN_S=$((SEEN_S + 1)); shift ;;
        --topic)   [ "$#" -ge 2 ] || usage "--topic needs a value"; TOPIC="$2"; SEEN_T=$((SEEN_T + 1)); shift ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
[ "$SEEN_S" -eq 1 ] || usage "--session is required once"
[ "$SEEN_T" -eq 1 ] || usage "--topic is required once"
[[ "$TOPIC" =~ $RE_TOPIC ]] || usage "--topic [$TOPIC] does not match $RE_TOPIC"

SESSION="${KOTO_TICK_SESSION:-$SESSION_ARG}"
[ -n "$SESSION" ] || usage "no session: --session is empty and KOTO_TICK_SESSION is unset"

ctx_remove() {
    # Idempotent in koto: a key never written is removed successfully.
    koto context remove "$SESSION" "$1" >/dev/null && return 0
    printf '%s: koto context remove failed for %s\n' "$PROG" "$1" >&2
    exit 66
}
ctx_add() {
    printf '%s' "$2" | koto context add "$SESSION" "$1" >/dev/null && return 0
    printf '%s: koto context add failed for %s\n' "$PROG" "$1" >&2
    exit 66
}
verdict() {
    ctx_add executed_verdict "$1"
    printf 'executed_verdict=%s\n' "$1"
    exit 0
}

ctx_remove executed_verdict
ctx_remove executed_pr
ctx_remove executed_pr_state

BRANCH=$(git symbolic-ref --quiet --short HEAD) || BRANCH=""
if [ -z "$BRANCH" ]; then
    printf '%s: HEAD is not on a named branch\n' "$PROG" >&2
    verdict read-failed
fi

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner </dev/null) || REPO=""
if ! [[ "$REPO" =~ $RE_REPO ]]; then
    printf '%s: could not read the repository name\n' "$PROG" >&2
    verdict read-failed
fi

URL=$(bash "$OWNED" --repo "$REPO" --head "$BRANCH" --state all </dev/null)
RC=$?
case "$RC" in
    0) ;;
    3) verdict several ;;
    *) printf '%s: owned-pr.sh exited %s\n' "$PROG" "$RC" >&2; verdict read-failed ;;
esac
[ -n "$URL" ] || verdict none
if ! [[ "$URL" =~ $RE_PR_URL ]]; then
    printf '%s: owned-pr.sh printed a URL outside the pattern\n' "$PROG" >&2
    verdict read-failed
fi

STATE=$(gh pr view "$URL" --json state --jq .state </dev/null) || STATE=""
case "$STATE" in
    MERGED) PR_STATE=merged ;;
    OPEN) PR_STATE=open ;;
    CLOSED) PR_STATE=closed ;;
    *) printf '%s: gh pr view gave no readable state\n' "$PROG" >&2; verdict read-failed ;;
esac

ctx_add executed_pr "$URL"
ctx_add executed_pr_state "$PR_STATE"
verdict one
