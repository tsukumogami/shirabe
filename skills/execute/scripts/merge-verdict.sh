#!/usr/bin/env bash
# merge-verdict.sh — for /execute: decide, from one live GitHub read, whether a
# PR may be merged now, and print that decision as one verdict line.
#
# This script only reads. It applies the merge decision table of
# DESIGN-scope-then-execute (Key Interfaces) to a single snapshot of the PR and
# of its base branch's rules, first match wins, and prints the verdict. The one
# merge call in the repository lives in merge-exec.sh, which runs this script
# itself immediately before merging rather than trusting a verdict someone
# stored.
#
# Everything it decides on arrives as an argument or from GitHub. It reads no
# stdin (every gh call runs with stdin from /dev/null), no workflow session
# context, and no state file. The CI deadline and the no-checks grace window
# are measured from the head commit's `committedDate` in the same PR snapshot,
# so a resumed run measures the same deadline with no bookkeeping.
#
# Usage:
#   merge-verdict.sh --repo <owner/repo> --pr <n> --merge <true|false>
#                    --expected-head <sha|none> [--confirm]
#
# Flags may come in any order; each appears at most once, and only the
# space-separated `--flag value` form is accepted. Closed patterns, checked
# before any gh call:
#   --repo           ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$  (neither half may be `.`
#                    or `..`)
#   --pr             ^[1-9][0-9]*$
#   --merge          exactly `true` or `false`
#   --expected-head  ^[0-9a-f]{40}$ or the literal `none` (`none` makes row 8
#                    fire)
#
# --confirm reads only the PR's state, re-reading about once a second until it
# reports MERGED or the confirm window (20 s) elapses, and evaluates no other
# row. --merge and --expected-head are still required and still validated.
#
# Environment:
#   EXECUTE_CI_WAIT_LIMIT_SECS  the per-head-commit CI deadline in seconds.
#                               Honored only when it matches ^[0-9]+$ and lies
#                               in 1..86400; anything else means 1800.
#   MERGE_CONFIRM_WAIT_SECS     the --confirm window. Honored only in 0..20, so
#                               it can narrow the window, never widen it.
#
# Output: on success exactly one line on stdout, the verdict. Every diagnostic
# goes to stderr. The verdict grammar, as anchored extended regular expressions
# (tests hold every verdict to this list, and merge_route's context-matches
# gates key on it):
#
#   ^merged$
#   ^pending:(checks|merge-state)$
#   ^mergeable:(squash|merge|rebase):[0-9a-f]{40}$
#   ^awaiting:(merge-not-requested|head-moved|no-checks|base-unprotected|review|workflow-change|merge-method-unresolved)$
#   ^awaiting:merge-state:[A-Z_]+(:review=(REVIEW_REQUIRED|CHANGES_REQUESTED))?$
#   ^error:execute:(pr-closed|ready|ci|ci-timeout|status-read)$
#   ^not-merged:(merge-call-failed|merge-not-observed)$
#
# This script prints every one of those except `not-merged:merge-call-failed`,
# which belongs to merge-exec.sh and is listed so callers have one grammar.
#
# Decision table (first match wins):
#   1  state MERGED                                  merged
#   2  state CLOSED                                  error:execute:pr-closed
#   3  isDraft                                       error:execute:ready
#   4  mergeStateStatus DIRTY                        awaiting:merge-state:DIRTY
#   5  a check in the fail or cancel bucket          error:execute:ci
#   6  a check pending (any bucket but pass,         pending:checks, or
#      skipping, fail, cancel), a check the base's   error:execute:ci-timeout
#      rules require not yet reported (read only     once the head commit is
#      with --merge true), or zero checks within     older than the deadline
#      120 s of the head commit
#   7  --merge false                                 awaiting:merge-not-requested
#   8  expected head `none` or not headRefOid        awaiting:head-moved
#   9  zero checks after the grace window            awaiting:no-checks
#   10 mergeStateStatus UNKNOWN                      pending:merge-state, or
#                                                    awaiting:merge-state:UNKNOWN
#                                                    past the deadline
#   11 mergeStateStatus other than CLEAN, or         awaiting:merge-state:<S>
#      reviewDecision REVIEW_REQUIRED or             [:review=<decision>]
#      CHANGES_REQUESTED
#   12 the base requires neither a non-empty set of  awaiting:base-unprotected
#      status checks nor an approving review (an
#      unreadable source counts as requiring nothing)
#   13 the rules require a review, not APPROVED      awaiting:review
#   14 the PR touches .github/workflows/,            awaiting:workflow-change
#      .github/actions/, or a CODEOWNERS file, not
#      APPROVED (an incomplete file list gives
#      error:execute:status-read)
#   15 no allowed merge method readable              awaiting:merge-method-unresolved
#   16 otherwise                                     mergeable:<method>:<headRefOid>
#   17 --confirm, a read reports MERGED              merged
#   19 --confirm, no MERGED within the window        not-merged:merge-not-observed
#
# A read that fails on every attempt, or returns a value outside its expected
# shape, is error:execute:status-read, except the two protection reads of rows
# 6 and 12, where an unreadable source counts as requiring nothing. Merge
# method: squash when squash is allowed, otherwise a merge commit when allowed,
# otherwise rebase. Row 12 sees classic protection through the branch endpoint,
# which a read-only token can see: a `protected: true` branch contributes its
# required status check names. Classic required reviews are not visible to
# read access, so only a ruleset `pull_request` rule counts as a review
# requirement; a base protected only by classic required reviews reads as
# unprotected, which refuses rather than merges.
#
# Exit codes:
#   0 — a verdict is on stdout (every verdict, --confirm included, so callers
#       route on the printed line and never on the exit code)
#   1 — an internal failure before any verdict (no temporary directory)
#   2 — usage error: a missing, unknown, or repeated flag, or a value outside
#       its pattern. stdout is empty and no gh call was made.
#
# Exact gh invocations (stdin is always /dev/null). Reads that fail are retried,
# at most 3 attempts per read with 1 s and then 2 s of backoff (3 s in total),
# so one run fits inside a 30-second default-action limit on a normal network.
#
#   Snapshot (every run without --confirm):
#     gh pr view <pr> --repo <repo> --json state,isDraft,mergeStateStatus,reviewDecision,headRefOid,baseRefName,changedFiles,commits
#   Head commit date, only when the snapshot's commit list lacks headRefOid:
#     gh api repos/<repo>/commits/<headRefOid>
#   Checks (after rows 1-4). An exit whose stderr says "no checks reported" is
#   zero checks; any exit (including the pending exit, 8) whose stdout is a
#   JSON array is read as that array:
#     gh pr checks <pr> --repo <repo> --json name,bucket
#   Base protection, only with --merge true (after row 5):
#     gh api repos/<repo>/branches/<baseRefName>
#     gh api repos/<repo>/rules/branches/<baseRefName> --paginate
#   Changed files, only when row 14 can fire (reviewDecision not APPROVED); the
#   complete list, never the snapshot's first 100 files:
#     gh api repos/<repo>/pulls/<pr>/files --paginate
#   Allowed merge methods (row 15):
#     gh api repos/<repo>
#   Confirm read (--confirm only, once per poll):
#     gh pr view <pr> --repo <repo> --json state
set -uo pipefail

PROG=merge-verdict

RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_PR='^[1-9][0-9]*$'
RE_SHA='^[0-9a-f]{40}$'
RE_UINT='^[0-9]+$'
RE_UPPER='^[A-Z_]+$'
RE_UPPER_OR_EMPTY='^[A-Z_]*$'
RE_BRANCH='^[A-Za-z0-9._/-]+$'

GRACE_SECS=120
READ_ATTEMPTS=3

usage() {
    echo "usage: merge-verdict.sh --repo <owner/repo> --pr <n> --merge <true|false> --expected-head <sha|none> [--confirm]" >&2
}

usage_error() {
    echo "$PROG: $*" >&2
    usage
    exit 2
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

REPO=""
PR=""
MERGE=""
EXPECTED=""
CONFIRM=false
HAVE_REPO=0
HAVE_PR=0
HAVE_MERGE=0
HAVE_EXPECTED=0

while [ $# -gt 0 ]; do
    case "$1" in
        --repo|--pr|--merge|--expected-head)
            FLAG="$1"
            [ $# -ge 2 ] || usage_error "$FLAG needs a value"
            VALUE="$2"
            shift 2
            case "$FLAG" in
                --repo)
                    [ "$HAVE_REPO" -eq 0 ] || usage_error "--repo given more than once"
                    HAVE_REPO=1
                    REPO="$VALUE"
                    ;;
                --pr)
                    [ "$HAVE_PR" -eq 0 ] || usage_error "--pr given more than once"
                    HAVE_PR=1
                    PR="$VALUE"
                    ;;
                --merge)
                    [ "$HAVE_MERGE" -eq 0 ] || usage_error "--merge given more than once"
                    HAVE_MERGE=1
                    MERGE="$VALUE"
                    ;;
                --expected-head)
                    [ "$HAVE_EXPECTED" -eq 0 ] || usage_error "--expected-head given more than once"
                    HAVE_EXPECTED=1
                    EXPECTED="$VALUE"
                    ;;
            esac
            ;;
        --confirm)
            [ "$CONFIRM" = false ] || usage_error "--confirm given more than once"
            CONFIRM=true
            shift
            ;;
        *)
            usage_error "unknown argument [$1]"
            ;;
    esac
done

[ "$HAVE_REPO" -eq 1 ] || usage_error "--repo is required"
[ "$HAVE_PR" -eq 1 ] || usage_error "--pr is required"
[ "$HAVE_MERGE" -eq 1 ] || usage_error "--merge is required"
[ "$HAVE_EXPECTED" -eq 1 ] || usage_error "--expected-head is required"

[[ $REPO =~ $RE_REPO ]] || usage_error "--repo [$REPO] is not owner/repo"
case "/$REPO/" in
    */./*|*/../*) usage_error "--repo [$REPO] names a dot path segment" ;;
esac
[[ $PR =~ $RE_PR ]] || usage_error "--pr [$PR] is not a PR number"
case "$MERGE" in
    true|false) ;;
    *) usage_error "--merge [$MERGE] is not true or false" ;;
esac
if [ "$EXPECTED" != none ] && ! [[ $EXPECTED =~ $RE_SHA ]]; then
    usage_error "--expected-head [$EXPECTED] is not a 40-character lowercase sha or none"
fi

# ---------------------------------------------------------------------------
# Environment knobs, each bounded
# ---------------------------------------------------------------------------

LIMIT=1800
LIMIT_RAW="${EXECUTE_CI_WAIT_LIMIT_SECS-}"
if [ -n "$LIMIT_RAW" ]; then
    # The length cap keeps the arithmetic below from overflowing; 10# keeps a
    # leading zero from being read as octal.
    if [[ $LIMIT_RAW =~ $RE_UINT ]] && [ ${#LIMIT_RAW} -le 9 ] \
        && [ $((10#$LIMIT_RAW)) -ge 1 ] && [ $((10#$LIMIT_RAW)) -le 86400 ]; then
        LIMIT=$((10#$LIMIT_RAW))
    else
        echo "$PROG: ignoring EXECUTE_CI_WAIT_LIMIT_SECS [$LIMIT_RAW] (want an integer in 1..86400); using 1800" >&2
    fi
fi

CONFIRM_WINDOW=20
CONFIRM_RAW="${MERGE_CONFIRM_WAIT_SECS-}"
if [ -n "$CONFIRM_RAW" ]; then
    if [[ $CONFIRM_RAW =~ $RE_UINT ]] && [ ${#CONFIRM_RAW} -le 9 ] && [ $((10#$CONFIRM_RAW)) -le 20 ]; then
        CONFIRM_WINDOW=$((10#$CONFIRM_RAW))
    else
        echo "$PROG: ignoring MERGE_CONFIRM_WAIT_SECS [$CONFIRM_RAW] (want an integer in 0..20); using 20" >&2
    fi
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/merge-verdict.XXXXXX") || {
    echo "$PROG: could not create a temporary directory" >&2
    exit 1
}
trap 'rm -rf "$TMPD"' EXIT

verdict() {
    printf '%s\n' "$1"
    exit 0
}

status_read() {
    echo "$PROG: $*" >&2
    verdict "error:execute:status-read"
}

# relay_stderr — hand gh's own diagnostic to the reader, prefixed, so a failed
# read says why it failed instead of disappearing.
relay_stderr() {
    if [ -s "$TMPD/err" ]; then
        sed "s/^/$PROG: gh: /" "$TMPD/err" >&2
    fi
}

# gh_read <args...> — one read, retried. Sets READ_OUT to gh's stdout and
# returns 0 on an exit-0 attempt; returns 1 after READ_ATTEMPTS failures.
READ_OUT=""
gh_read() {
    local attempt=1 rc
    while :; do
        READ_OUT=$(gh "$@" </dev/null 2>"$TMPD/err")
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        echo "$PROG: gh $* failed (exit $rc, attempt $attempt of $READ_ATTEMPTS)" >&2
        relay_stderr
        [ "$attempt" -ge "$READ_ATTEMPTS" ] && return 1
        sleep "$attempt"
        attempt=$((attempt + 1))
    done
}

# is_json_array <text> — true when the text parses as one JSON array.
is_json_array() {
    [ -n "$1" ] || return 1
    jq -e 'type == "array"' >/dev/null <<<"$1"
}

# ---------------------------------------------------------------------------
# Confirm mode (rows 17 and 19)
# ---------------------------------------------------------------------------

if [ "$CONFIRM" = true ]; then
    START=$SECONDS
    while :; do
        STATE_OUT=$(gh pr view "$PR" --repo "$REPO" --json state </dev/null 2>"$TMPD/err")
        RC=$?
        if [ "$RC" -eq 0 ]; then
            CONFIRM_STATE=$(jq -r '.state // ""' <<<"$STATE_OUT")
            [ "$CONFIRM_STATE" = MERGED ] && verdict "merged"
            echo "$PROG: confirm poll reports state [$CONFIRM_STATE]" >&2
        else
            echo "$PROG: confirm poll failed (exit $RC)" >&2
            relay_stderr
        fi
        [ $((SECONDS - START)) -ge "$CONFIRM_WINDOW" ] && break
        sleep 1
    done
    verdict "not-merged:merge-not-observed"
fi

# ---------------------------------------------------------------------------
# Snapshot (rows 1-4)
# ---------------------------------------------------------------------------

gh_read pr view "$PR" --repo "$REPO" \
    --json state,isDraft,mergeStateStatus,reviewDecision,headRefOid,baseRefName,changedFiles,commits \
    || status_read "the PR view could not be read"
SNAP="$READ_OUT"
jq -e 'type == "object"' >/dev/null <<<"$SNAP" || status_read "the PR view is not a JSON object"

snap() {
    jq -r "$1" <<<"$SNAP"
}

STATE=$(snap '.state // ""')
case "$STATE" in
    MERGED) verdict "merged" ;;
    CLOSED) verdict "error:execute:pr-closed" ;;
    OPEN) ;;
    *) status_read "unexpected PR state [$STATE]" ;;
esac

IS_DRAFT=$(snap '.isDraft')
case "$IS_DRAFT" in
    true) verdict "error:execute:ready" ;;
    false) ;;
    *) status_read "unexpected isDraft [$IS_DRAFT]" ;;
esac

MSS=$(snap '.mergeStateStatus // ""')
[[ $MSS =~ $RE_UPPER ]] || status_read "unexpected mergeStateStatus [$MSS]"
[ "$MSS" = DIRTY ] && verdict "awaiting:merge-state:DIRTY"

REVIEW=$(snap '.reviewDecision // ""')
[[ $REVIEW =~ $RE_UPPER_OR_EMPTY ]] || status_read "unexpected reviewDecision [$REVIEW]"

HEAD_OID=$(snap '.headRefOid // ""')
[[ $HEAD_OID =~ $RE_SHA ]] || status_read "unexpected headRefOid [$HEAD_OID]"

BASE=$(snap '.baseRefName // ""')
[[ $BASE =~ $RE_BRANCH ]] || status_read "unexpected baseRefName [$BASE]"
case "/$BASE/" in
    */./*|*/../*) status_read "baseRefName [$BASE] names a dot path segment" ;;
esac

CHANGED=$(snap '.changedFiles // ""')
{ [[ $CHANGED =~ $RE_UINT ]] && [ ${#CHANGED} -le 9 ]; } || status_read "unexpected changedFiles [$CHANGED]"
CHANGED=$((10#$CHANGED))

HEAD_DATE=$(snap '.headRefOid as $h | ([(.commits // [])[] | select(.oid == $h) | .committedDate] | .[0]) // ""')
if [ -z "$HEAD_DATE" ]; then
    gh_read api "repos/$REPO/commits/$HEAD_OID" || status_read "the head commit could not be read"
    HEAD_DATE=$(jq -r '.commit.committer.date // ""' <<<"$READ_OUT")
fi
AGE=$(jq -n --arg d "$HEAD_DATE" '(now - ($d | fromdateiso8601)) | floor') \
    || status_read "the head commit date [$HEAD_DATE] is not an ISO 8601 time"
[[ $AGE =~ $RE_UINT ]] || AGE=0

# ---------------------------------------------------------------------------
# Checks (rows 5 and 6)
# ---------------------------------------------------------------------------

CHECKS=""
ATTEMPT=1
while :; do
    CHECKS_OUT=$(gh pr checks "$PR" --repo "$REPO" --json name,bucket </dev/null 2>"$TMPD/err")
    RC=$?
    if is_json_array "$CHECKS_OUT"; then
        jq -e 'all(type == "object")' >/dev/null <<<"$CHECKS_OUT" \
            || status_read "the PR's checks are not a list of objects"
        CHECKS="$CHECKS_OUT"
        break
    fi
    if [ "$RC" -ne 0 ] && grep -q 'no checks reported' "$TMPD/err"; then
        CHECKS='[]'
        break
    fi
    echo "$PROG: gh pr checks failed (exit $RC, attempt $ATTEMPT of $READ_ATTEMPTS)" >&2
    relay_stderr
    [ "$ATTEMPT" -ge "$READ_ATTEMPTS" ] && status_read "the PR's checks could not be read"
    sleep "$ATTEMPT"
    ATTEMPT=$((ATTEMPT + 1))
done

# Buckets follow gh's own aggregation, as scripts/ci-gate-expression_test.sh
# documents: pass and skipping succeeded; fail and cancel failed; pending and
# anything unrecognized is still pending, never passed.
CHECK_COUNT=$(jq 'length' <<<"$CHECKS")
CHECK_FAILED=$(jq '[.[] | select(.bucket == "fail" or .bucket == "cancel")] | length' <<<"$CHECKS")
CHECK_PENDING=$(jq '[.[] | select((.bucket // "") as $b | ["pass", "skipping", "fail", "cancel"] | index($b) | not)] | length' <<<"$CHECKS")

[ "$CHECK_FAILED" -gt 0 ] && verdict "error:execute:ci"

# Base protection, read only when a merge was requested: with --merge false no
# protection or method read happens at all (row 7).
REQUIRED_CHECKS='[]'
REVIEW_REQUIRED_BY_RULES=false
if [ "$MERGE" = true ]; then
    CLASSIC_REQ='[]'
    if gh_read api "repos/$REPO/branches/$BASE"; then
        CLASSIC_REQ=$(jq -c 'if .protected == true then
                [((.protection.required_status_checks.contexts // [])[]),
                 ((.protection.required_status_checks.checks // [])[] | .context)]
                | map(select(type == "string" and . != "")) | unique
            else [] end' <<<"$READ_OUT") || CLASSIC_REQ='[]'
    else
        echo "$PROG: branch protection unreadable; counting it as requiring nothing" >&2
    fi
    RULES='[]'
    if gh_read api "repos/$REPO/rules/branches/$BASE" --paginate; then
        RULES=$(jq -cs 'map(if type == "array" then . else [] end) | add // []' <<<"$READ_OUT") || RULES='[]'
    else
        echo "$PROG: branch rules unreadable; counting them as requiring nothing" >&2
    fi
    RULES_REQ=$(jq -c '[.[] | select(.type == "required_status_checks")
            | (.parameters.required_status_checks // [])[] | .context]
            | map(select(type == "string" and . != "")) | unique' <<<"$RULES") || RULES_REQ='[]'
    REVIEW_REQUIRED_BY_RULES=$(jq '[.[] | select(.type == "pull_request")
            | (.parameters.required_approving_review_count // 0)] | any(. >= 1)' <<<"$RULES") \
        || REVIEW_REQUIRED_BY_RULES=false
    REQUIRED_CHECKS=$(jq -cn --argjson a "$CLASSIC_REQ" --argjson b "$RULES_REQ" '$a + $b | unique')
fi

UNREPORTED=$(jq -n --argjson req "$REQUIRED_CHECKS" --argjson checks "$CHECKS" \
    '$req - [$checks[] | .name] | length')

if [ "$CHECK_PENDING" -gt 0 ] || [ "$UNREPORTED" -gt 0 ] \
    || { [ "$CHECK_COUNT" -eq 0 ] && [ "$AGE" -le "$GRACE_SECS" ]; }; then
    [ "$AGE" -gt "$LIMIT" ] && verdict "error:execute:ci-timeout"
    verdict "pending:checks"
fi

# ---------------------------------------------------------------------------
# Rows 7-11
# ---------------------------------------------------------------------------

[ "$MERGE" = true ] || verdict "awaiting:merge-not-requested"

[ "$EXPECTED" = "$HEAD_OID" ] || verdict "awaiting:head-moved"

[ "$CHECK_COUNT" -eq 0 ] && verdict "awaiting:no-checks"

if [ "$MSS" = UNKNOWN ]; then
    [ "$AGE" -gt "$LIMIT" ] && verdict "awaiting:merge-state:UNKNOWN"
    verdict "pending:merge-state"
fi

REVIEW_SUFFIX=""
case "$REVIEW" in
    REVIEW_REQUIRED|CHANGES_REQUESTED) REVIEW_SUFFIX=":review=$REVIEW" ;;
esac
if [ "$MSS" != CLEAN ] || [ -n "$REVIEW_SUFFIX" ]; then
    verdict "awaiting:merge-state:$MSS$REVIEW_SUFFIX"
fi

# ---------------------------------------------------------------------------
# Rows 12-14: the base's own requirements, not GitHub's merge state
# ---------------------------------------------------------------------------

REQUIRED_COUNT=$(jq 'length' <<<"$REQUIRED_CHECKS")
if [ "$REQUIRED_COUNT" -eq 0 ] && [ "$REVIEW_REQUIRED_BY_RULES" != true ]; then
    verdict "awaiting:base-unprotected"
fi

if [ "$REVIEW_REQUIRED_BY_RULES" = true ] && [ "$REVIEW" != APPROVED ]; then
    verdict "awaiting:review"
fi

if [ "$REVIEW" != APPROVED ]; then
    gh_read api "repos/$REPO/pulls/$PR/files" --paginate \
        || status_read "the PR's changed files could not be read"
    FILES=$(jq -cs 'if all(type == "array") then add // [] else error("not a list of pages") end' <<<"$READ_OUT") \
        || status_read "the PR's changed-file list is malformed"
    FILE_COUNT=$(jq 'length' <<<"$FILES")
    [ "$FILE_COUNT" -eq "$CHANGED" ] \
        || status_read "the changed-file list has $FILE_COUNT entries but the PR reports $CHANGED"
    # A rename counts on both sides: moving a workflow out of .github/workflows/
    # changes the gate as much as editing it does.
    TOUCHES_GATE=$(jq '[.[] | .filename, (.previous_filename // empty)]
        | map(select(type == "string"))
        | any(startswith(".github/workflows/") or startswith(".github/actions/")
              or . == "CODEOWNERS" or endswith("/CODEOWNERS"))' <<<"$FILES") \
        || status_read "the PR's changed-file list is malformed"
    [ "$TOUCHES_GATE" = true ] && verdict "awaiting:workflow-change"
fi

# ---------------------------------------------------------------------------
# Rows 15-16: the merge method
# ---------------------------------------------------------------------------

METHOD=""
if gh_read api "repos/$REPO"; then
    METHOD=$(jq -r 'if .allow_squash_merge == true then "squash"
        elif .allow_merge_commit == true then "merge"
        elif .allow_rebase_merge == true then "rebase"
        else "" end' <<<"$READ_OUT") || METHOD=""
fi
case "$METHOD" in
    squash|merge|rebase) verdict "mergeable:$METHOD:$HEAD_OID" ;;
    *) verdict "awaiting:merge-method-unresolved" ;;
esac
