#!/usr/bin/env bash
# reconcile-check.sh -- one reconcile re-check, printed as one fact.
#
# Each subcommand makes the reads for one claim in the coordinator's record
# and prints one fact in reconcile-report.sh's coordinate-reconcile-facts/v1
# shape: {kind, status: ok|not_verified, read_at, reason, ...}. A read that
# fails or runs past its deadline is a not_verified fact with the reason, not
# a failure of this script: reconcile reports what it couldn't read rather
# than stopping on it. Every value taken from a record row is checked against
# a fixed pattern before it reaches a command, and one that fails is a
# not_verified fact that reaches no command at all.
#
# Reads only. `gh` is called with read subcommands and `gh api` with GET;
# `git` only with ls-remote, against the repository the row names.
#
# Usage:
#   reconcile-check.sh pr       --repo R --number N
#   reconcile-check.sh board    --repo R --sha S --base B
#   reconcile-check.sh branch   --repo R --branch B
#   reconcile-check.sh appeared --repo R --branch B
#   reconcile-check.sh files    --repo R --number N [--cap C]
#   reconcile-check.sh merge    --repo R --number N --verified-head S
#   reconcile-check.sh close    --repo R --kind issue|pr --number N
#   reconcile-check.sh deferral --repo R --row-file F --run-start T
#
# Exit codes: 0 a fact printed; 64 usage error.
#
# Environment: RECONCILE_READ_DEADLINE, seconds per read (default 8).
#
# Requires: bash 3.2+, jq, gh, git.
set -uo pipefail

PROG=reconcile-check
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

DEADLINE=${RECONCILE_READ_DEADLINE:-8}
# The contents API is read once per changed file for a merge; past this many
# files the merge is reported not confirmed rather than read in full.
MERGE_FILE_CAP=100

usage() { sed -n '17,27p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

[ $# -ge 1 ] || usage
SUB=$1
shift
REPO="" NUMBER="" SHA="" BASE="" BRANCH="" CAP=300 KIND="" VHEAD="" ROWFILE="" RUNSTART=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --repo) REPO=$2 ;;
        --number) NUMBER=$2 ;;
        --sha) SHA=$2 ;;
        --base) BASE=$2 ;;
        --branch) BRANCH=$2 ;;
        --cap) CAP=$2 ;;
        --kind) KIND=$2 ;;
        --verified-head) VHEAD=$2 ;;
        --row-file) ROWFILE=$2 ;;
        --run-start) RUNSTART=$2 ;;
        *) usage ;;
    esac
    shift 2
done

# refuse KIND REASON -- a row value failed its pattern: report, run nothing.
refuse() { rd_not_verified "$1" "$2"; exit 0; }

need_repo()   { rd_valid_repo "$REPO" || refuse "$SUB" "invalid repository in the record row"; }
need_number() { rd_valid_number "$NUMBER" || refuse "$SUB" "invalid pull request or issue number in the record row"; }
need_branch() { rd_valid_branch "$BRANCH" || refuse "$SUB" "invalid branch in the record row"; }

# read_or_fail KIND CMD... -- run CMD under the deadline; on failure print
# the not_verified fact and exit. Stdout of CMD is left in $OUT.
read_or_fail() {
    local kind=$1 rc
    shift
    OUT=$(rd_deadline "$DEADLINE" "$@" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 124 ]; then refuse "$kind" "read timed out after ${DEADLINE}s"; fi
    if [ "$rc" -ne 0 ]; then refuse "$kind" "read failed (exit $rc)"; fi
}

case "$SUB" in
pr)
    need_repo; need_number
    read_or_fail pr gh pr view "$NUMBER" --repo "$REPO" --json state,isDraft,headRefOid,mergeStateStatus,baseRefName
    printf '%s' "$OUT" | jq -c --arg t "$(rd_now)" '
        {kind: "pr", status: "ok", state: .state, draft: .isDraft, head: .headRefOid,
         merge_state: .mergeStateStatus, base: .baseRefName, read_at: $t}' 2>/dev/null \
        || refuse pr "unreadable pull request response"
    ;;

board)
    need_repo
    rd_valid_sha "$SHA" || refuse board "invalid sha"
    rd_valid_branch "$BASE" || refuse board "invalid base branch"
    read_or_fail board "$RD_BOARD_CHECK" --repo "$REPO" --sha "$SHA" --base "$BASE"
    printf '%s' "$OUT" | jq -c --arg sha "$SHA" --arg t "$(rd_now)" '
        if (.verdict | type) != "string" then error("shape")
        elif (.verdict | startswith("error:")) then
          {kind: "board", status: "not_verified", at: $sha, reason: ("board " + .verdict), read_at: $t}
        else
          {kind: "board", status: "ok", at: $sha,
           verdict: ({verified: "holds", pending: "pending", unverified: "fails"}[.verdict] // "fails"),
           detail: ((.reasons // [])[0] | if . == null then "" else ((.name // .code // "") + (if (.detail // "") != "" then " (" + .detail + ")" else "" end)) end),
           read_at: $t}
        end' 2>/dev/null || refuse board "unreadable board verdict"
    ;;

branch)
    need_repo; need_branch
    read_or_fail branch git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH"
    TIP=$(printf '%s\n' "$OUT" | awk -v r="refs/heads/$BRANCH" '$2 == r { print $1; exit }')
    if [ -z "$TIP" ]; then
        jq -nc --arg t "$(rd_now)" '{kind: "branch", status: "ok", state: "gone", tip: null, read_at: $t}'
    elif rd_valid_sha "$TIP"; then
        jq -nc --arg tip "$TIP" --arg t "$(rd_now)" '{kind: "branch", status: "ok", state: "present", tip: $tip, read_at: $t}'
    else
        refuse branch "unreadable ls-remote output"
    fi
    ;;

appeared)
    need_repo; need_branch
    read_or_fail appeared gh pr list --repo "$REPO" --head "$BRANCH" --state all --json number,state,url
    printf '%s' "$OUT" | jq -c --arg t "$(rd_now)" '
        {kind: "appeared", status: "ok", prs: [.[] | {number, state, url}], read_at: $t}' 2>/dev/null \
        || refuse appeared "unreadable pull request list"
    ;;

files)
    need_repo; need_number
    [[ $CAP =~ ^[1-9][0-9]{0,3}$ ]] || usage
    read_or_fail files gh api "repos/$REPO/pulls/$NUMBER/files?per_page=100" --paginate \
        --jq '.[] | [.filename, (.previous_filename // empty)] | .[]'
    printf '%s\n' "$OUT" | jq -Rsc --argjson cap "$CAP" --arg t "$(rd_now)" '
        split("\n") | map(select(length > 0)) as $all
        | {kind: "files", status: "ok", paths: $all[0:$cap], truncated: (($all | length) > $cap), read_at: $t}'
    ;;

merge)
    need_repo; need_number
    rd_valid_sha "$VHEAD" || refuse merge "invalid verified head in the side-effect row"
    read_or_fail merge gh pr view "$NUMBER" --repo "$REPO" --json state,baseRefName
    STATE=$(printf '%s' "$OUT" | jq -r '.state // empty' 2>/dev/null)
    BASE=$(printf '%s' "$OUT" | jq -r '.baseRefName // empty' 2>/dev/null)
    rd_valid_branch "$BASE" || refuse merge "unreadable base branch"
    if [ "$STATE" != MERGED ]; then
        jq -nc --arg s "$STATE" --arg t "$(rd_now)" \
            '{kind: "merge", status: "ok", verdict: "not_confirmed", reason: ("pull request is " + ($s | ascii_downcase)), read_at: $t}'
        exit 0
    fi
    read_or_fail merge gh api "repos/$REPO/pulls/$NUMBER/files?per_page=100" --paginate \
        --jq '.[] | [.status, .filename] | @tsv'
    FILES=$OUT
    COUNT=$(printf '%s\n' "$FILES" | grep -c . || true)
    if [ "$COUNT" -gt "$MERGE_FILE_CAP" ]; then
        jq -nc --arg t "$(rd_now)" --argjson n "$COUNT" \
            '{kind: "merge", status: "ok", verdict: "not_confirmed", reason: ("\($n) changed files, over the per-merge read cap"), read_at: $t}'
        exit 0
    fi
    # blob_at PATH REF -- the blob sha of PATH at REF, "absent" on a 404.
    blob_at() {
        local enc out rc
        enc=$(rd_urlencode_path "$1") || return 3
        out=$(rd_deadline "$DEADLINE" gh api "repos/$REPO/contents/$enc?ref=$2" --jq .sha 2>&1)
        rc=$?
        if [ "$rc" -eq 0 ]; then printf '%s' "$out"; return 0; fi
        case "$out" in *"HTTP 404"*|*"Not Found"*) printf 'absent'; return 0 ;; esac
        return 2
    }
    while IFS=$'\t' read -r status path; do
        [ -n "$path" ] || continue
        want=absent
        if [ "$status" != removed ]; then
            want=$(blob_at "$path" "$VHEAD") || {
                [ $? -eq 3 ] && refuse merge "refused a file path from the pull request"
                refuse merge "contents read failed at the verified head"; }
        fi
        have=$(blob_at "$path" "$BASE") || {
            [ $? -eq 3 ] && refuse merge "refused a file path from the pull request"
            refuse merge "contents read failed on the default branch"; }
        if [ "$want" != "$have" ]; then
            jq -nc --arg p "$path" --arg t "$(rd_now)" \
                '{kind: "merge", status: "ok", verdict: "not_confirmed", reason: ("\($p) on the default branch differs from the verified head"), read_at: $t}'
            exit 0
        fi
    done <<EOF
$FILES
EOF
    jq -nc --arg t "$(rd_now)" '{kind: "merge", status: "ok", verdict: "confirmed", reason: "", read_at: $t}'
    ;;

close)
    need_repo; need_number
    case "$KIND" in issue|pr) ;; *) usage ;; esac
    read_or_fail close gh "$KIND" view "$NUMBER" --repo "$REPO" --json state
    printf '%s' "$OUT" | jq -c --arg t "$(rd_now)" '
        {kind: "close", status: "ok",
         verdict: (if (.state == "CLOSED" or .state == "MERGED") then "confirmed" else "not_confirmed" end),
         reason: (if (.state == "CLOSED" or .state == "MERGED") then "" else "target is " + (.state | ascii_downcase) end),
         read_at: $t}' 2>/dev/null || refuse close "unreadable state"
    ;;

deferral)
    need_repo
    [ -f "$ROWFILE" ] || usage
    [[ $RUNSTART =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || usage
    LINE=$(rd_deadline "$DEADLINE" "$RD_DEFERRAL_CHECK" --row-file "$ROWFILE" --run-start "$RUNSTART" 2>/dev/null)
    rc=$?
    [ "$rc" -eq 124 ] && refuse deferral "disposal check timed out after ${DEADLINE}s"
    case "$rc:$LINE" in
        0:"disposed filed "*)
            N=${LINE#disposed filed }
            N=${N#\#}
            rd_valid_number "$N" || refuse deferral "disposal names an unreadable issue number"
            NUMBER=$N
            read_or_fail deferral gh issue view "$NUMBER" --repo "$REPO" --json number
            jq -nc --arg how "filed #$NUMBER" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: $how, read_at: $t}' ;;
        0:"disposed "*)
            jq -nc --arg how "${LINE#disposed }" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: $how, read_at: $t}' ;;
        0:"undisposed raised-this-run")
            jq -nc --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: "raised this run", read_at: $t}' ;;
        1:"undisposed"*)
            jq -nc --arg why "${LINE#undisposed}" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: false, how: ($why | ltrimstr(" ")), read_at: $t}' ;;
        *)
            refuse deferral "disposal check failed (exit $rc)" ;;
    esac
    ;;

*) usage ;;
esac
