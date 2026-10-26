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
#   state is OPEN (--state open), or OPEN or MERGED (--state all and
#   --state open-else-merged)
#
# `--state all` drops CLOSED-unmerged pull requests on purpose: a PR the user
# closed is never a survivor, so it can't stand beside the open one that
# replaced it and turn one answer into "several".
#
# `--state open-else-merged` is for a reader that follows one PR from open to
# merged: /execute's ci_monitor gates, which keep reading the run's PR after
# it merges (#958). When the five checks leave any OPEN pull request, only the
# OPEN ones are kept, so the answer is the `--state open` answer; only on a
# branch with no open candidate are the MERGED ones kept. So an earlier run's
# MERGED PR on a reused head never stands beside the open one and turns the
# answer ambiguous, as it would under `--state all`, and a branch with neither
# (a CLOSED-unmerged PR only) answers zero survivors, as `--state open` does.
#
# Those five can't tell two runs apart: two sessions resuming the same PLAN
# slug under one account share the author and the head branch. So every PR a
# run records gets an entry naming the run in its index session,
# `pr.<owner>.<repo>.<n>` (scripts/run-trail.sh index, read here through
# scripts/lib/record-store.sh's rs_index_latest_run). Nothing is written into
# the PR's text. With --run-id, a PR that passed the five checks is then
# dropped only when:
#
#   its latest index entry names another run   another run recorded it last
#
# Every other candidate survives: one whose latest entry names this run, and
# one with no entry at all (opened before the index existed, or by a skill
# that records none, such as /scope). The index can only take a PR away: an
# entry planted for this run never makes a PR that fails one of the five
# checks a survivor. Without --run-id (a lookup run by hand, outside any koto
# session) the index is not read and the five checks alone decide. A form of
# the index that can't be read is a failed read (exit 2), never a guess.
#
# Taking over. A run that re-enters a PLAN after an earlier run on it ended,
# and has lost that run's identity, finds its own branch's PR recorded last by
# another run: the ordinary lookup refuses it (exit 5) and GitHub refuses a
# second PR on the same head. `--take-over` is the one way out, and only an
# explicit caller passes it (/execute's re-entry, on the directive's say-so,
# through adopt-or-create-pr.sh, which refuses --take-over on any head but
# the PLAN's own impl/<slug>);
# no lookup takes a PR over on its own. With it, when the lookup would exit 5
# -- no survivor, and exactly one PR that passed the five checks is another
# run's -- the script writes this run's entry into that PR's index session
# (`run-trail.sh index --session <S> --mode single-pr`, the topic from
# execute-<topic>), looks again, and prints the URL. It edits no PR. A PR from
# a fork, another author, another base, or another head never reaches that
# point, so it is never taken over. In every other case --take-over changes
# nothing.
#
# Usage:
#   owned-pr.sh --repo <owner/repo> --head <branch>
#               --state open|all|open-else-merged
#               [--base <branch>] [--run-id <id> [--take-over --session <s>]]
#
# Flags may come in any order, each at most once, as `--flag value`. Closed
# patterns, checked before any gh call:
#   --repo    ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$, neither half `.` or `..`
#   --head    ^[A-Za-z0-9._/-]+$, no `..`, no leading `-` or `/`
#   --base    the same pattern as --head. When omitted, the repository's
#             default branch (read from `gh api repos/<repo>`) is the base,
#             checked against the same pattern.
#   --state   exactly `open`, `all` or `open-else-merged`
#   --run-id  ^[0-9a-f]{32}$, the caller's run identity (run-id.sh get)
#   --take-over  needs --run-id, --session and --state open; takes no value
#   --session execute-<topic>, the run's record root, whose entry a
#             --take-over writes (only with --take-over)
#
# Output and exit codes. The contract names no caller step: each caller maps
# these codes to its own (for /execute, see the orchestrator_setup directive in
# skills/execute/koto-templates/execute.md).
#
#   0  exactly one survivor: its URL is the only line on stdout
#   0  zero survivors: stdout is empty. A branch whose only PRs come from
#      forks, other authors, or another base counts as zero. A PR another
#      run recorded last is never a survivor either, but it is reported:
#      exit 5 for one, exit 4 for several.
#   3  several survivors, none of them with an index entry naming this run:
#      stdout is empty
#   4  ambiguous, picks none: several candidates (PRs that passed the five
#      checks) of which at least one has an index entry -- this run's PR
#      beside a PR with no entry, any survivor beside one another run
#      recorded, or several PRs other runs recorded. stdout is empty
#   5  no survivor, and exactly one PR that passed the five checks was
#      recorded last by another run: the PR on this login and branch belongs
#      to a different run. Never adopted without --take-over. stdout is
#      empty; stderr names the PR
#   2  a gh read or an index read failed (a gh read after one retry), or
#      returned something outside its expected shape, or a takeover's index
#      write failed: stdout is empty
#   64 usage error: stdout is empty and no gh call was made
#
# Diagnostics go to stderr. Every gh call reads stdin from /dev/null.
#
# Exact gh invocations:
#   gh api user
#   gh api repos/<repo>                                  (only without --base)
#   gh pr list --repo <repo> --head <branch> --state <open|all>
#       (`all` for --state open-else-merged)
#       --json url,state,isCrossRepository,author,baseRefName,headRefName
#       --limit 100
# No gh call writes. The index reads are koto reads at the shared address
# (one per candidate, only with --run-id); a --take-over's one write is
# scripts/run-trail.sh's.
#
# Requires: bash 3.2+, jq, koto (with --run-id).
set -uo pipefail

PROG=owned-pr
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
TRAIL="$SELF_DIR/../../../scripts/run-trail.sh"

RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'
RE_LOGIN='^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'
RE_RUN_ID='^[0-9a-f]{32}$'
RE_ROOT='^execute-[a-z0-9-]+$'

usage_error() {
    echo "$PROG: $*" >&2
    echo "usage: owned-pr.sh --repo <owner/repo> --head <branch> --state open|all|open-else-merged [--base <branch>] [--run-id <id> [--take-over --session <execute-topic>]]" >&2
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

REPO=""; HEAD=""; BASE=""; STATE=""; RUN_ID=""; SESSION=""; TAKE_OVER=0
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --take-over)
            case "$SEEN" in *" --take-over "*) usage_error "--take-over given more than once" ;; esac
            SEEN="$SEEN--take-over "
            TAKE_OVER=1
            shift
            ;;
        --repo|--head|--base|--state|--run-id|--session)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --repo) REPO="$2" ;;
                --head) HEAD="$2" ;;
                --base) BASE="$2" ;;
                --state) STATE="$2" ;;
                --run-id) RUN_ID="$2" ;;
                --session) SESSION="$2" ;;
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
    open|all|open-else-merged) ;;
    *) usage_error "--state must be open, all or open-else-merged, got [$STATE]" ;;
esac
case "$SEEN" in
    *" --run-id "*) [[ $RUN_ID =~ $RE_RUN_ID ]] || usage_error "--run-id [$RUN_ID] is not a run id" ;;
esac
if [ "$TAKE_OVER" -eq 1 ]; then
    [ -n "$RUN_ID" ] || usage_error "--take-over needs --run-id: it records the PR as that run's"
    [ "$STATE" = open ] || usage_error "--take-over works on an open PR only (--state open)"
    [[ $SESSION =~ $RE_ROOT ]] || usage_error "--take-over needs --session execute-<topic>: the record root whose entry it writes"
else
    case "$SEEN" in *" --session "*) usage_error "--session goes with --take-over" ;; esac
fi

command -v jq >/dev/null || read_error "jq is not on PATH"
if [ -n "$RUN_ID" ]; then
    # shellcheck source=../../../scripts/lib/record-store.sh
    . "$SELF_DIR/../../../scripts/lib/record-store.sh" || read_error "scripts/lib/record-store.sh could not be read"
fi

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

# gh pr list knows no open-else-merged: it lists every state, and the jq below
# makes the choice.
GH_STATE="$STATE"
[ "$STATE" = open-else-merged ] && GH_STATE=all

check_url() {
    [[ $1 =~ $RE_URL ]] || read_error "the owned pull request's URL is unusable [$1]"
    # The URL must name the repository that was asked about.
    local url_repo
    url_repo=$(printf '%s' "$1" | sed -E 's#^https://[^/]+/([^/]+/[^/]+)/pull/[0-9]+$#\1#')
    [ "$(printf '%s' "$url_repo" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" ] \
        || read_error "the owned pull request's URL names $url_repo, not $REPO"
}

# index_mark <url> -- with --run-id, what the PR's index says: `mine` (its
# latest entry names --run-id), `foreign` (it names another run) or `none`
# (no entry). Without --run-id the index isn't read and the answer is `none`.
index_mark() {
    local latest rc
    [ -n "$RUN_ID" ] || { printf 'none'; return 0; }
    check_url "$1"
    latest=$(rs_index_latest_run "$REPO" "${1##*/}")
    rc=$?
    [ "$rc" -eq 0 ] || read_error "the index of $1 could not be read (record-store exit $rc)"
    if [ -z "$latest" ]; then printf 'none'
    elif [ "$latest" = "$RUN_ID" ]; then printf 'mine'
    else printf 'foreign'
    fi
}

# list_candidates -- read the branch's PRs, keep the ones that pass the five
# checks, and sort them by what the index says: SURVIVORS (mine or none),
# FOREIGN (another run's), each one URL per line, and N_MINE.
list_candidates() {
    local urls url mark
    LIST_JSON=""
    gh_read LIST_JSON pr list --repo "$REPO" --head "$HEAD" --state "$GH_STATE" \
        --json url,state,isCrossRepository,author,baseRefName,headRefName --limit 100 \
        || read_error "gh pr list failed for $REPO head $HEAD"

    urls=$(printf '%s' "$LIST_JSON" | jq -r \
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
        # open-else-merged took the `all` arm above; this narrows it to the
        # OPEN candidates whenever there is one.
        | if $state == "open-else-merged" and any(.[]; .state == "OPEN")
          then map(select(.state == "OPEN")) else . end
        | .[] | (.url // "")') \
        || read_error "gh pr list returned something that is not a JSON array of pull requests"

    SURVIVORS=""; FOREIGN=""; N_SURV=0; N_FOREIGN=0; N_MINE=0
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        mark=$(index_mark "$url") || exit $?
        case "$mark" in
            foreign) FOREIGN="${FOREIGN:+$FOREIGN
}$url"; N_FOREIGN=$((N_FOREIGN + 1)) ;;
            *) SURVIVORS="${SURVIVORS:+$SURVIVORS
}$url"; N_SURV=$((N_SURV + 1))
               [ "$mark" = mine ] && N_MINE=$((N_MINE + 1)) ;;
        esac
    done <<<"$urls"
}

# take_over <url> -- write this run's entry into the one foreign candidate's
# index session, so its latest entry names --run-id. No PR is edited.
take_over() {
    local url="$1" topic
    check_url "$url"
    topic=${SESSION#execute-}
    echo "$PROG: taking over $url: another run recorded it last; recording it as this run's in its index" >&2
    "$BASH" "$TRAIL" index --repo "$REPO" --number "${url##*/}" --session "$SESSION" \
        --mode single-pr --topic "$topic" </dev/null >&2 \
        || read_error "the index entry for $url could not be written while taking it over"
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
        echo "$PROG: the one pull request on $REPO head $HEAD ($FOREIGN) was recorded by another run; not adopting it" >&2
        exit 5
    fi
    if [ "$N_FOREIGN" -gt 1 ]; then
        echo "$PROG: $N_FOREIGN pull requests on $REPO head $HEAD were recorded by other runs; refusing to pick one" >&2
        exit 4
    fi
    exit 0
fi

# A survivor beside another run's candidate is ambiguous too: under
# --state all, this run's (or an unrecorded) merged PR can sit beside an open
# PR another run recorded on the same head, and picking the survivor would
# compute a verdict while that other run works on the branch.
if [ "$N_SURV" -ge 1 ] && [ "$N_FOREIGN" -gt 0 ]; then
    echo "$PROG: $REPO head $HEAD has $N_SURV candidate(s) for this run beside $N_FOREIGN another run recorded; ambiguous, refusing to pick one" >&2
    exit 4
fi

if [ "$N_SURV" -gt 1 ]; then
    if [ "$N_MINE" -gt 0 ]; then
        echo "$PROG: $N_SURV owned pull requests on $REPO head $HEAD, at least one recorded by this run; ambiguous, refusing to pick one" >&2
        exit 4
    fi
    echo "$PROG: $N_SURV owned pull requests on $REPO head $HEAD; refusing to pick one" >&2
    exit 3
fi

URL="$SURVIVORS"
check_url "$URL"
printf '%s\n' "$URL"
exit 0
