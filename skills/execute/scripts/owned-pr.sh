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
# Those five can't tell two runs apart: two sessions resuming the same PLAN
# slug under one account share the author and the head branch. So a PR also
# carries the run that opened it, as one hidden line in its body that
# run-id.sh writes:
#
#   <!-- shirabe-run: <id> -->
#
# With --run-id, a PR that passed the five checks is then kept only when:
#
#   its marker names <id>             the caller's own run opened it
#   it carries no marker at all       opened before markers existed, or by a
#                                     skill that doesn't stamp one (/scope):
#                                     the login-and-branch match stands
#
# A PR whose marker names any other run, or whose marker line is malformed,
# is dropped however well its login and branch match. Without --run-id (a
# lookup run by hand, outside any koto session) the marker is not consulted
# and the five checks alone decide, as they did before markers existed.
#
# Taking over. A run that re-enters a PLAN after an earlier run on it ended,
# and has lost that run's identity, finds its own branch's PR carrying a
# foreign marker: the ordinary lookup refuses it (exit 5) and GitHub refuses a
# second PR on the same head. `--take-over` is the one way out, and only an
# explicit caller passes it (/execute's re-entry, on the directive's say-so,
# through adopt-or-create-pr.sh, which refuses --take-over on any head but
# the PLAN's own impl/<slug>);
# no lookup takes a PR over on its own. With it, when the lookup would exit 5
# -- no survivor, and exactly one PR that passed the five checks carries a
# foreign marker -- the script rewrites that PR's marker to name --run-id
# (`gh pr edit --body-file`, the rest of the body kept), looks again, and
# prints the URL. A PR from a fork, another author, another base, or another
# head never reaches that point, so it is never taken over. In every other
# case --take-over changes nothing. It is the only path on which this script
# writes to GitHub.
#
# Usage:
#   owned-pr.sh --repo <owner/repo> --head <branch> --state open|all
#               [--base <branch>] [--run-id <id>]
#
# Flags may come in any order, each at most once, as `--flag value`. Closed
# patterns, checked before any gh call:
#   --repo    ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$, neither half `.` or `..`
#   --head    ^[A-Za-z0-9._/-]+$, no `..`, no leading `-` or `/`
#   --base    the same pattern as --head. When omitted, the repository's
#             default branch (read from `gh api repos/<repo>`) is the base,
#             checked against the same pattern.
#   --state   exactly `open` or `all`
#   --run-id  ^[0-9a-f]{32}$, the caller's run identity (run-id.sh get)
#   --take-over  needs --run-id and --state open; takes no value
#
# Output and exit codes. The contract names no caller step: each caller maps
# these codes to its own (see skills/execute/SKILL.md, "Owned-PR lookup").
#
#   0  exactly one survivor: its URL is the only line on stdout
#   0  zero survivors: stdout is empty. A branch whose only PRs come from
#      forks, other authors, or another base counts as zero. A PR another
#      run marked is never a survivor either, but it is reported: exit 5
#      for one, exit 4 for several.
#   3  several survivors, none of them carrying a run marker: stdout is empty
#   4  ambiguous, picks none: several candidates (PRs that passed the five
#      checks) of which at least one carries a run marker -- two runs' PRs, a
#      marked PR beside an unmarked one, this run's or an unmarked PR beside
#      one another run marked, or several PRs other runs marked. stdout is
#      empty
#   5  no survivor, and exactly one PR that passed the five checks carries
#      another run's marker (or a malformed one): the PR on this login and
#      branch belongs to a different run. Never adopted without --take-over.
#      stdout is empty; stderr names the PR
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
#       --json url,state,isCrossRepository,author,baseRefName,headRefName,body
#       --limit 100
#   gh pr edit <number> --repo <repo> --body-file <file>   (only a --take-over)
#
# Requires: bash 3.2+, jq.
set -uo pipefail

PROG=owned-pr
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64

RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'
RE_LOGIN='^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'
RE_RUN_ID='^[0-9a-f]{32}$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: owned-pr.sh --repo <owner/repo> --head <branch> --state open|all [--base <branch>] [--run-id <id> [--take-over]]" >&2
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

REPO=""; HEAD=""; BASE=""; STATE=""; RUN_ID=""; TAKE_OVER=0
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --take-over)
            case "$SEEN" in *" --take-over "*) usage_error "--take-over given more than once" ;; esac
            SEEN="$SEEN--take-over "
            TAKE_OVER=1
            shift
            ;;
        --repo|--head|--base|--state|--run-id)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --repo) REPO="$2" ;;
                --head) HEAD="$2" ;;
                --base) BASE="$2" ;;
                --state) STATE="$2" ;;
                --run-id) RUN_ID="$2" ;;
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
case "$SEEN" in
    *" --run-id "*) [[ $RUN_ID =~ $RE_RUN_ID ]] || usage_error "--run-id [$RUN_ID] is not a run id" ;;
esac
if [ "$TAKE_OVER" -eq 1 ]; then
    [ -n "$RUN_ID" ] || usage_error "--take-over needs --run-id: it restamps the PR with that run"
    [ "$STATE" = open ] || usage_error "--take-over works on an open PR only (--state open)"
fi

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

# list_candidates -- read the branch's PRs and keep the ones that pass the five
# checks, one line each: `<mark> <url>`. The mark is `none` (no marker line),
# `mine` (every marker line names --run-id), `foreign` (a marker line names
# another run, or is malformed), or, without --run-id, `marked`.
list_candidates() {
    LIST_JSON=""
    gh_read LIST_JSON pr list --repo "$REPO" --head "$HEAD" --state "$STATE" \
        --json url,state,isCrossRepository,author,baseRefName,headRefName,body --limit 100 \
        || read_error "gh pr list failed for $REPO head $HEAD"

    CANDIDATES=$(printf '%s' "$LIST_JSON" | jq -r \
        --arg login "$LOGIN" --arg base "$BASE" --arg head "$HEAD" --arg state "$STATE" \
        --arg runid "$RUN_ID" '
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
        | .[]
        | [(.body // "") | tostring | split("\n")[]
           | select(test("^\\s*<!--\\s*shirabe-run:"))] as $marks
        | (if ($marks | length) == 0 then "none"
           elif $runid == "" then "marked"
           elif ($marks | all(test("^\\s*<!-- shirabe-run: " + $runid + " -->\\s*$"))) then "mine"
           else "foreign" end) as $mark
        | $mark + " " + (.url // "")') \
        || read_error "gh pr list returned something that is not a JSON array of pull requests"

    SURVIVORS=$(printf '%s\n' "$CANDIDATES" | sed -n -E 's/^(none|mine|marked) //p')
    FOREIGN=$(printf '%s\n' "$CANDIDATES" | sed -n 's/^foreign //p')
    N_SURV=$(printf '%s' "$SURVIVORS" | grep -c .)
    N_FOREIGN=$(printf '%s' "$FOREIGN" | grep -c .)
    N_MARKED=$(printf '%s\n' "$CANDIDATES" | grep -cE '^(mine|marked) ')
}

check_url() {
    [[ $1 =~ $RE_URL ]] || read_error "the owned pull request's URL is unusable [$1]"
    # The URL must name the repository that was asked about.
    local url_repo
    url_repo=$(printf '%s' "$1" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/[0-9]+$#\1#')
    [ "$(printf '%s' "$url_repo" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" ] \
        || read_error "the owned pull request's URL names $url_repo, not $REPO"
}

# take_over <url> -- rewrite the one foreign-marked candidate's body so its
# only marker names --run-id, then post it. The rest of the body is kept as
# it is.
take_over() {
    local url="$1" body_file
    check_url "$url"
    body_file=$(mktemp "${TMPDIR:-/tmp}/owned-pr-takeover.XXXXXX") || read_error "mktemp failed"
    # shellcheck disable=SC2064
    trap "rm -f '$body_file'" EXIT
    # The live body as listed, restamped by run-id.sh: the one writer of the
    # marker line, so the format lives in one place.
    printf '%s' "$LIST_JSON" | jq -r --arg url "$url" \
        '[.[] | select(type == "object" and .url == $url)][0] | (.body // "") | tostring' \
        > "$body_file" || read_error "could not read the body of $url"
    "$BASH" "$SELF_DIR/run-id.sh" restamp "$RUN_ID" "$body_file" </dev/null \
        || read_error "could not restamp the body of $url"
    echo "$PROG: taking over $url: its marker named another run; restamping it with this run's" >&2
    gh pr edit "${url##*/}" --repo "$REPO" --body-file "$body_file" </dev/null >&2 \
        || read_error "gh pr edit failed while taking over $url"
}

list_candidates

if [ "$N_SURV" -eq 0 ] && [ "$N_FOREIGN" -eq 1 ] && [ "$TAKE_OVER" -eq 1 ]; then
    TAKEN="$FOREIGN"
    take_over "$TAKEN"
    list_candidates
    if [ "$N_SURV" -ne 1 ] || [ "$SURVIVORS" != "$TAKEN" ]; then
        read_error "after taking over $TAKEN the lookup does not find it as this run's"
    fi
fi

if [ "$N_SURV" -eq 0 ]; then
    if [ "$N_FOREIGN" -eq 1 ]; then
        echo "$PROG: the one pull request on $REPO head $HEAD ($FOREIGN) was opened by another run; not adopting it" >&2
        exit 5
    fi
    if [ "$N_FOREIGN" -gt 1 ]; then
        echo "$PROG: $N_FOREIGN pull requests on $REPO head $HEAD were opened by other runs; refusing to pick one" >&2
        exit 4
    fi
    exit 0
fi

# A survivor beside another run's candidate is ambiguous too: under
# --state all, an unmarked (or this run's) merged PR can sit beside an open
# PR another run marked on the same head, and picking the survivor would
# compute a verdict while that other run works on the branch.
if [ "$N_SURV" -ge 1 ] && [ "$N_FOREIGN" -gt 0 ]; then
    echo "$PROG: $REPO head $HEAD has $N_SURV candidate(s) for this run beside $N_FOREIGN another run marked; ambiguous, refusing to pick one" >&2
    exit 4
fi

if [ "$N_SURV" -gt 1 ]; then
    if [ "$N_MARKED" -gt 0 ]; then
        echo "$PROG: $N_SURV owned pull requests on $REPO head $HEAD, at least one carrying a run marker; ambiguous, refusing to pick one" >&2
        exit 4
    fi
    echo "$PROG: $N_SURV owned pull requests on $REPO head $HEAD; refusing to pick one" >&2
    exit 3
fi

URL="$SURVIVORS"
check_url "$URL"
printf '%s\n' "$URL"
exit 0
