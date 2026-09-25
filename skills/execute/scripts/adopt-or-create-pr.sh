#!/usr/bin/env bash
# adopt-or-create-pr.sh — for /execute's orchestrator_setup: find the home PR
# this run owns on a branch, open one when the directive says to create it, and
# record it.
#
# The agent runs this script from orchestrator_setup's directive; it is never a
# default action, because `gh pr create`'s success is itself the externally
# visible event (references/default-action-conversion.md). What it records, it
# records from owned-pr.sh's output only: the home PR's URL as the koto context
# key `home_pr`, and `waiting` as `<url>:human`. No transition and no agent
# evidence ever writes `home_pr`.
#
# Usage:
#   adopt-or-create-pr.sh --session <koto-session> --repo <owner/repo>
#                         --head <branch>
#                         [--create --plan-slug <slug> --plan-doc <path>]
#
#   --session    ^[A-Za-z0-9][A-Za-z0-9._-]*$
#   --repo       a single owner/repo, the run's recorded write set
#   --head       the branch the PR's head must be, pattern as owned-pr.sh's
#   --create     when no owned PR exists, open one as a draft:
#                  gh pr create --draft --repo <repo> --head <branch>
#                    --title "impl: <slug>" --body "Implements <path>."
#                then resolve again, and record what the lookup finds.
#   --plan-slug  ^[a-z0-9-]+$            (required with --create)
#   --plan-doc   ^[A-Za-z0-9._/-]+\.md$   (required with --create)
#
# Each flag appears at most once, as `--flag value`.
#
# Exit codes, mapped to /execute's steps in SKILL.md ("Owned-PR lookup"):
#   0   one owned PR: recorded, and its URL is on stdout
#   2   a lookup read failed                     -> execute:status-read
#   3   several owned PRs; or, after --create,   -> execute:pr-adopt
#       the lookup still finds none or several
#   4   no owned PR and no --create: nothing     -> the caller's create path
#       recorded (only the current-branch check
#       uses this)
#   5   gh pr create failed; nothing recorded    -> orchestrator_setup blocked
#   64  usage error; no gh or koto call made
#   70  the koto context write failed
#
# Requires: bash 3.2+, jq (through owned-pr.sh), gh, koto.
set -uo pipefail

PROG=adopt-or-create-pr

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'
RE_SLUG='^[a-z0-9-]+$'
RE_DOC='^[A-Za-z0-9._/-]+\.md$'
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: adopt-or-create-pr.sh --session <s> --repo <owner/repo> --head <branch> [--create --plan-slug <slug> --plan-doc <path>]" >&2
    exit 64
}

SESSION=""; REPO=""; HEAD=""; CREATE=0; SLUG=""; DOC=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--repo|--head|--plan-slug|--plan-doc)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION="$2" ;;
                --repo) REPO="$2" ;;
                --head) HEAD="$2" ;;
                --plan-slug) SLUG="$2" ;;
                --plan-doc) DOC="$2" ;;
            esac
            shift 2
            ;;
        --create)
            case "$SEEN" in *" --create "*) usage_error "--create given more than once" ;; esac
            SEEN="$SEEN--create "
            CREATE=1
            shift
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

[[ $SESSION =~ $RE_SESSION ]] || usage_error "--session [$SESSION] is not a koto session name"
[[ $REPO =~ $RE_REPO ]] || usage_error "--repo [$REPO] is not a single owner/repo"
case "/$REPO/" in */./*|*/../*) usage_error "--repo [$REPO] names a dot path segment" ;; esac
[[ $HEAD =~ $RE_BRANCH ]] || usage_error "--head [$HEAD] is not an allowed branch name"
case "$HEAD" in -*|/*|*..*|*/) usage_error "--head [$HEAD] is not an allowed branch name" ;; esac
if [ "$CREATE" -eq 1 ]; then
    [[ $SLUG =~ $RE_SLUG ]] || usage_error "--plan-slug [$SLUG] must match ^[a-z0-9-]+\$"
    [[ $DOC =~ $RE_DOC ]] || usage_error "--plan-doc [$DOC] must be a plain .md path"
    case "/$DOC/" in */../*) usage_error "--plan-doc [$DOC] names a .. segment" ;; esac
else
    [ -z "$SLUG$DOC" ] || usage_error "--plan-slug and --plan-doc go with --create"
fi

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
OWNED="$SELF_DIR/owned-pr.sh"

lookup() {
    URL=$("$BASH" "$OWNED" --repo "$REPO" --head "$HEAD" --state open </dev/null)
    LOOKUP_RC=$?
}

record() {
    [[ $URL =~ $RE_URL ]] || { echo "$PROG: owned-pr.sh printed [$URL], not a PR URL" >&2; exit 2; }
    printf '%s' "$URL" | koto context add "$SESSION" home_pr >/dev/null \
        || { echo "$PROG: could not record home_pr" >&2; exit 70; }
    printf '%s' "$URL:human" | koto context add "$SESSION" waiting >/dev/null \
        || { echo "$PROG: could not record waiting" >&2; exit 70; }
    printf '%s\n' "$URL"
    exit 0
}

lookup
case "$LOOKUP_RC" in
    0) [ -n "$URL" ] && record ;;
    2) exit 2 ;;
    3) exit 3 ;;
    *) echo "$PROG: owned-pr.sh exited $LOOKUP_RC" >&2; exit 2 ;;
esac

# Zero owned PRs on the branch.
if [ "$CREATE" -eq 0 ]; then
    echo "$PROG: no owned PR on $REPO head $HEAD" >&2
    exit 4
fi

if ! gh pr create --draft --repo "$REPO" --head "$HEAD" \
        --title "impl: $SLUG" --body "Implements $DOC." </dev/null >&2; then
    echo "$PROG: gh pr create failed; nothing recorded" >&2
    exit 5
fi

lookup
case "$LOOKUP_RC" in
    0)
        [ -n "$URL" ] && record
        echo "$PROG: created a PR, but no owned PR is found on $REPO head $HEAD" >&2
        exit 3
        ;;
    2) exit 2 ;;
    *) exit 3 ;;
esac
