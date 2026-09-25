#!/usr/bin/env bash
# owned-pr.sh — find the one pull request this user owns on a head branch.
#
# Every head-branch lookup in the tactical chain goes through this script:
# /execute's home PR and merge reads, /scope's publish and executed report, and
# /deliver's re-checks. It is the ownership filter, and it never picks among
# several candidates. A branch name is not proof of ownership: a fork can open a
# pull request from a branch with the same name, and so can another author, so
# a lookup that took "the first PR on this branch" could adopt, edit, ready, or
# merge somebody else's work.
#
# A pull request survives the filter only when all of these hold:
#
#   isCrossRepository == false        its head lives in <repo>, not a fork
#   author.login == the login `gh api user` reports
#   baseRefName == the expected base
#   headRefName == the expected head branch
#   state is OPEN (--state open), or OPEN or MERGED (--state all)
#
# `--state all` drops CLOSED-unmerged pull requests on purpose: a PR the user
# closed is never a survivor, so it can't stand beside the open one that
# replaced it and turn one answer into "several".
#
# Usage:
#   owned-pr.sh --repo <owner/repo> --head <branch> --state open|all
#               [--base <branch>]
#
# Flags may come in any order, each at most once, as `--flag value`. Closed
# patterns, checked before any gh call:
#   --repo    ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$, neither half `.` or `..`
#   --head    ^[A-Za-z0-9._/-]+$, no `..`, no leading `-` or `/`
#   --base    the same pattern as --head. When omitted, the repository's
#             default branch (read from `gh api repos/<repo>`) is the base,
#             checked against the same pattern.
#   --state   exactly `open` or `all`
#
# Output and exit codes. The contract names no caller step: each caller maps
# these codes to its own (see skills/execute/SKILL.md, "Owned-PR lookup").
#
#   0  exactly one survivor: its URL is the only line on stdout
#   0  zero survivors: stdout is empty. A branch whose only PRs come from
#      forks, other authors, or another base counts as zero.
#   3  several survivors: stdout is empty
#   2  a gh read failed (after one retry) or returned something outside its
#      expected shape: stdout is empty
#   64 usage error: stdout is empty and no gh call was made
#
# Diagnostics go to stderr. Every gh call reads stdin from /dev/null.
#
# Exact gh invocations:
#   gh api user
#   gh api repos/<repo>                                  (only without --base)
#   gh pr list --repo <repo> --head <branch> --state <open|all>
#       --json url,state,isCrossRepository,author,baseRefName,headRefName
#       --limit 100
#
# Requires: bash 3.2+, jq.
set -uo pipefail

PROG=owned-pr

RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'
RE_LOGIN='^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: owned-pr.sh --repo <owner/repo> --head <branch> --state open|all [--base <branch>]" >&2
    exit 64
}

read_error() {
    echo "$PROG: $*" >&2
    exit 2
}

valid_branch() {
    local b="$1"
    [[ $b =~ $RE_BRANCH ]] || return 1
    case "$b" in
        -*|/*|*..*|*/) return 1 ;;
    esac
    return 0
}

REPO=""; HEAD=""; BASE=""; STATE=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --repo|--head|--base|--state)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --repo) REPO="$2" ;;
                --head) HEAD="$2" ;;
                --base) BASE="$2" ;;
                --state) STATE="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done

[ -n "$REPO" ] || usage_error "--repo is required"
[ -n "$HEAD" ] || usage_error "--head is required"
[ -n "$STATE" ] || usage_error "--state is required"
[[ $REPO =~ $RE_REPO ]] || usage_error "[$REPO] is not a single owner/repo"
case "/$REPO/" in
    */./*|*/../*) usage_error "[$REPO] names a dot path segment" ;;
esac
valid_branch "$HEAD" || usage_error "[$HEAD] is not an allowed branch name"
case "$SEEN" in
    *" --base "*) valid_branch "$BASE" || usage_error "[$BASE] is not an allowed base branch name" ;;
esac
case "$STATE" in
    open|all) ;;
    *) usage_error "--state must be open or all, got [$STATE]" ;;
esac

command -v jq >/dev/null || read_error "jq is not on PATH"

# gh_read <outvar> <args...> -- run one gh read, retried once after 1 s. Sets
# the named variable to stdout on success; returns non-zero after two failures.
gh_read() {
    local __out="$1" attempt out
    shift
    for attempt in 1 2; do
        if out=$(gh "$@" </dev/null); then
            printf -v "$__out" '%s' "$out"
            return 0
        fi
        [ "$attempt" -eq 1 ] && sleep 1
    done
    return 1
}

USER_JSON=""
gh_read USER_JSON api user || read_error "gh api user failed"
LOGIN=$(printf '%s' "$USER_JSON" | jq -r 'if type == "object" then (.login // "") else "" end') \
    || read_error "gh api user returned something that is not a JSON object"
[[ $LOGIN =~ $RE_LOGIN ]] || read_error "gh api user returned an unusable login [$LOGIN]"

if [ -z "$BASE" ]; then
    REPO_JSON=""
    gh_read REPO_JSON api "repos/$REPO" || read_error "gh api repos/$REPO failed"
    BASE=$(printf '%s' "$REPO_JSON" | jq -r 'if type == "object" then (.default_branch // "") else "" end') \
        || read_error "gh api repos/$REPO returned something that is not a JSON object"
    valid_branch "$BASE" || read_error "the default branch of $REPO is unusable [$BASE]"
fi

LIST_JSON=""
gh_read LIST_JSON pr list --repo "$REPO" --head "$HEAD" --state "$STATE" \
    --json url,state,isCrossRepository,author,baseRefName,headRefName --limit 100 \
    || read_error "gh pr list failed for $REPO head $HEAD"

SURVIVORS=$(printf '%s' "$LIST_JSON" | jq -r \
    --arg login "$LOGIN" --arg base "$BASE" --arg head "$HEAD" --arg state "$STATE" '
    if type != "array" then error("not an array") else . end
    | map(select(
        type == "object"
        and (.isCrossRepository == false)
        and ((.author.login // "") == $login)
        and (.baseRefName == $base)
        and (.headRefName == $head)
        and (if $state == "open" then .state == "OPEN"
             else (.state == "OPEN" or .state == "MERGED") end)
      ))
    | .[] | (.url // "")') \
    || read_error "gh pr list returned something that is not a JSON array of pull requests"

if [ -z "$SURVIVORS" ]; then
    exit 0
fi

COUNT=$(printf '%s\n' "$SURVIVORS" | grep -c .)
if [ "$COUNT" -gt 1 ]; then
    echo "$PROG: $COUNT owned pull requests on $REPO head $HEAD; refusing to pick one" >&2
    exit 3
fi

URL="$SURVIVORS"
[[ $URL =~ $RE_URL ]] || read_error "the owned pull request's URL is unusable [$URL]"
# The URL must name the repository that was asked about.
URL_REPO=$(printf '%s' "$URL" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/[0-9]+$#\1#')
LC_URL_REPO=$(printf '%s' "$URL_REPO" | tr 'A-Z' 'a-z')
LC_REPO=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')
[ "$LC_URL_REPO" = "$LC_REPO" ] || read_error "the owned pull request's URL names $URL_REPO, not $REPO"

printf '%s\n' "$URL"
exit 0
