#!/usr/bin/env bash
# reconcile-check.sh -- one reconcile re-check, printed as one fact.
#
# Each subcommand makes the reads for one claim in the coordinator's record
# and prints one fact in reconcile-report.sh's coordinate-reconcile-facts/v1
# shape: {kind, status: ok|not_verified, read_at, reason, ...}. A read that
# fails, runs past its deadline, or returns something this script can't
# interpret is a not_verified fact with the reason, not a failure of this
# script: reconcile reports what it couldn't read rather than stopping on it,
# and it never turns an unreadable answer into a verdict. Every value taken
# from a record row is checked against a fixed pattern before it reaches a
# command, and one that fails is a not_verified fact that reaches no command.
#
# Reads only. `gh` is called with read subcommands and `gh api` with GET;
# `git` only with ls-remote, against the repository the row names.
#
# Usage:
#   reconcile-check.sh pr       --repo R --number N
#   reconcile-check.sh board    --repo R --sha S --base B
#   reconcile-check.sh branch   --repo R --branch B
#   reconcile-check.sh appeared --repo R --branch B
#   reconcile-check.sh files    --repo R --number N
#   reconcile-check.sh merge    --repo R --number N --verified-head S
#   reconcile-check.sh close    --repo R --kind issue|pr --number N
#   reconcile-check.sh deferral --repo R --row-file F --run-start T
#
# Exit codes: 0 a fact printed; 64 usage error.
#
# Environment: RECONCILE_READ_DEADLINE, seconds per read (default 8), and
# RECONCILE_BOARD_DEADLINE for the board check (default 26, since the board
# check bounds itself at 24 s). A deadline can only make a read give up
# sooner; it can't change a verdict.
#
# Requires: bash 3.2+, jq, gh, git.
set -uo pipefail

PROG=reconcile-check
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

DEADLINE=${RECONCILE_READ_DEADLINE:-8}
BOARD_DEADLINE=${RECONCILE_BOARD_DEADLINE:-26}
# The file list a scoping-ahead holding is judged by. Past this many files
# the fact says truncated, and the report doesn't call the holding
# consistent on a partial list.
FILES_CAP=300
# A merge reads the contents API twice per file. Past this many files it
# reports not confirmed rather than spending that many reads, and says why.
MERGE_FILE_CAP=100

usage() {
    awk '/^# Usage:/{on=1} on&&/^# Exit codes/{exit} on' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 64
}

[ $# -ge 1 ] || usage
SUB=$1
shift
REPO="" NUMBER="" SHA="" BASE="" BRANCH="" KIND="" VHEAD="" ROWFILE="" RUNSTART=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --repo) REPO=$2 ;;
        --number) NUMBER=$2 ;;
        --sha) SHA=$2 ;;
        --base) BASE=$2 ;;
        --branch) BRANCH=$2 ;;
        --kind) KIND=$2 ;;
        --verified-head) VHEAD=$2 ;;
        --row-file) ROWFILE=$2 ;;
        --run-start) RUNSTART=$2 ;;
        *) usage ;;
    esac
    shift 2
done

# refuse KIND REASON -- print the not_verified fact and stop.
refuse() { rd_not_verified "$1" "$2"; exit 0; }

need_repo()   { rd_valid_repo "$REPO" || refuse "$SUB" "invalid repository in the record row"; }
need_number() { rd_valid_number "$NUMBER" || refuse "$SUB" "invalid pull request or issue number in the record row"; }
need_branch() { rd_valid_branch "$BRANCH" || refuse "$SUB" "invalid branch in the record row"; }

# read_or_fail KIND SECS CMD... -- run CMD under a deadline; on failure print
# the not_verified fact and exit. CMD's stdout is left in $OUT.
read_or_fail() {
    local kind=$1 secs=$2 rc
    shift 2
    OUT=$(rd_deadline "$secs" "$@" 2>/dev/null)
    rc=$?
    [ "$rc" -eq 124 ] && refuse "$kind" "read timed out after ${secs}s"
    [ "$rc" -ne 0 ] && refuse "$kind" "read failed (exit $rc)"
    return 0
}

# board_fact -- map board-verdict.sh's object to a board fact. A verdict it
# doesn't recognise is not verified: an unknown answer is not a failing board.
board_fact() {
    jq -c --arg sha "$SHA" --arg t "$(rd_now)" '
        def first_reason: (.reasons // [])[0]
          | if . == null then ""
            else (.name // .code // "") + (if (.detail // "") != "" then " (" + .detail + ")" else "" end) end;
        if (.verdict | type) != "string" then error("shape")
        elif .verdict == "verified" then {kind: "board", status: "ok", at: $sha, verdict: "holds", detail: "", read_at: $t}
        elif .verdict == "pending" then {kind: "board", status: "ok", at: $sha, verdict: "pending", detail: first_reason, read_at: $t}
        elif .verdict == "unverified" then {kind: "board", status: "ok", at: $sha, verdict: "fails", detail: first_reason, read_at: $t}
        else {kind: "board", status: "not_verified", at: $sha, reason: ("board " + .verdict), read_at: $t} end'
}

case "$SUB" in
pr)
    need_repo; need_number
    read_or_fail pr "$DEADLINE" gh pr view "$NUMBER" --repo "$REPO" --json state,isDraft,headRefOid,mergeStateStatus,baseRefName
    printf '%s' "$OUT" | jq -ce --arg t "$(rd_now)" '
        select((.state | IN("OPEN", "MERGED", "CLOSED")) and (.headRefOid | test("^[0-9a-f]{40}$")))
        | {kind: "pr", status: "ok", state, draft: (.isDraft == true), head: .headRefOid,
           merge_state: .mergeStateStatus, base: .baseRefName, read_at: $t}' 2>/dev/null \
        || refuse pr "unreadable pull request response"
    ;;

board)
    need_repo
    rd_valid_sha "$SHA" || refuse board "invalid sha"
    rd_valid_branch "$BASE" || refuse board "invalid base branch"
    read_or_fail board "$BOARD_DEADLINE" "$RD_BOARD_CHECK" --repo "$REPO" --sha "$SHA" --base "$BASE"
    printf '%s' "$OUT" | board_fact 2>/dev/null || refuse board "unreadable board verdict"
    ;;

branch)
    need_repo; need_branch
    read_or_fail branch "$DEADLINE" git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH"
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
    read_or_fail appeared "$DEADLINE" gh pr list --repo "$REPO" --head "$BRANCH" --state all --json number,state,url
    printf '%s' "$OUT" | jq -ce --arg t "$(rd_now)" '
        select(type == "array")
        | {kind: "appeared", status: "ok", prs: [.[] | {number, state, url}], read_at: $t}' 2>/dev/null \
        || refuse appeared "unreadable pull request list"
    ;;

files)
    need_repo; need_number
    # One JSON string per path, both sides of a rename, so a path holding a
    # tab or a newline arrives intact rather than split.
    read_or_fail files "$DEADLINE" gh api "repos/$REPO/pulls/$NUMBER/files?per_page=100" --paginate \
        --jq '.[] | .filename, (.previous_filename // empty) | tojson'
    printf '%s\n' "$OUT" | jq -sc --argjson cap "$FILES_CAP" --arg t "$(rd_now)" '
        {kind: "files", status: "ok", paths: .[0:$cap], truncated: (length > $cap), read_at: $t}' 2>/dev/null \
        || refuse files "unreadable file list"
    ;;

merge)
    # Confirmed only when every file the pull request changed as of the
    # verified head has, on the default branch, the content it had at the
    # verified head. The file list is the verified head's own diff (the
    # compare API from the pull request's base commit to the verified head),
    # not the merged pull request's final file list: a file changed at the
    # verified head and reverted afterwards is missing from the final list,
    # and it is exactly the case that must read not confirmed.
    need_repo; need_number
    rd_valid_sha "$VHEAD" || refuse merge "invalid verified head in the side-effect row"
    read_or_fail merge "$DEADLINE" gh api "repos/$REPO/pulls/$NUMBER" \
        --jq '{state: .state, merged: .merged, base: .base.ref, base_sha: .base.sha}'
    PRJ=$OUT
    MERGED=$(printf '%s' "$PRJ" | jq -r '.merged // false' 2>/dev/null)
    DEFAULT=$(printf '%s' "$PRJ" | jq -r '.base // empty' 2>/dev/null)
    BASE_SHA=$(printf '%s' "$PRJ" | jq -r '.base_sha // empty' 2>/dev/null)
    if [ "$MERGED" != true ]; then
        STATE=$(printf '%s' "$PRJ" | jq -r '.state // "unknown"' 2>/dev/null)
        jq -nc --arg s "$STATE" --arg t "$(rd_now)" \
            '{kind: "merge", status: "ok", verdict: "not_confirmed", reason: ("pull request is " + ($s | ascii_downcase) + ", not merged"), read_at: $t}'
        exit 0
    fi
    rd_valid_branch "$DEFAULT" || refuse merge "unreadable base branch"
    rd_valid_sha "$BASE_SHA" || refuse merge "unreadable base commit"
    # status NUL path NUL, with the old path of a rename as its own "removed"
    # entry: after the merge it must be gone from the default branch.
    # Read straight into a file: a shell variable can't hold the NUL bytes
    # that keep a path with a tab or a newline in one piece.
    LIST=$(mktemp "${TMPDIR:-/tmp}/reconcile-merge.XXXXXX")
    trap 'rm -f "$LIST"' EXIT
    rd_deadline "$DEADLINE" gh api "repos/$REPO/compare/$BASE_SHA...$VHEAD" \
        --jq '.files[] | (if .status == "renamed" then "removed\u0000\(.previous_filename)\u0000" else empty end), "\(.status)\u0000\(.filename)\u0000"' \
        > "$LIST" 2>/dev/null
    rc=$?
    [ "$rc" -eq 124 ] && refuse merge "read timed out after ${DEADLINE}s"
    [ "$rc" -ne 0 ] && refuse merge "read failed (exit $rc)"
    COUNT=$(tr -cd '\0' < "$LIST" | wc -c | tr -d ' ')
    COUNT=$((COUNT / 2))
    if [ "$COUNT" -eq 0 ]; then
        refuse merge "the verified head changes no files against the pull request's base"
    fi
    if [ "$COUNT" -gt "$MERGE_FILE_CAP" ]; then
        jq -nc --arg t "$(rd_now)" --argjson n "$COUNT" --argjson cap "$MERGE_FILE_CAP" \
            '{kind: "merge", status: "ok", verdict: "not_confirmed", reason: ("\($n) changed files, over the \($cap)-file read cap"), read_at: $t}'
        exit 0
    fi
    # blob_at PATH REF -- the blob sha of PATH at REF, or "absent" on a 404.
    # Returns 3 for a refused path, 2 for any other failed read.
    blob_at() {
        local enc out rc
        enc=$(rd_urlencode_path "$1") || return 3
        out=$(rd_deadline "$DEADLINE" gh api "repos/$REPO/contents/$enc?ref=$2" --jq .sha 2>&1)
        rc=$?
        if [ "$rc" -eq 0 ] && rd_valid_sha "$out"; then printf '%s' "$out"; return 0; fi
        case "$out" in *"HTTP 404"*) printf 'absent'; return 0 ;; esac
        return 2
    }
    blob_or_refuse() {  # blob_or_refuse PATH REF WHERE
        BLOB=$(blob_at "$1" "$2")
        case $? in
            0) return 0 ;;
            3) refuse merge "refused a file path from the pull request" ;;
            *) refuse merge "contents read failed $3" ;;
        esac
    }
    while IFS= read -r -d '' status && IFS= read -r -d '' path; do
        want=absent
        if [ "$status" != removed ]; then
            blob_or_refuse "$path" "$VHEAD" "at the verified head"
            want=$BLOB
            # A file the verified head changed but that isn't there is a read
            # this script can't interpret, never a match.
            [ "$want" = absent ] && refuse merge "a changed file is missing at the verified head"
        fi
        blob_or_refuse "$path" "$DEFAULT" "on the default branch"
        if [ "$want" != "$BLOB" ]; then
            jq -nc --arg p "$path" --arg t "$(rd_now)" \
                '{kind: "merge", status: "ok", verdict: "not_confirmed", reason: ("\($p) on the default branch differs from the verified head"), read_at: $t}'
            exit 0
        fi
    done < "$LIST"
    jq -nc --arg t "$(rd_now)" '{kind: "merge", status: "ok", verdict: "confirmed", reason: "", read_at: $t}'
    ;;

close)
    # A close is settled when the target reads closed; a merged pull request
    # is closed too.
    need_repo; need_number
    case "$KIND" in issue|pr) ;; *) usage ;; esac
    read_or_fail close "$DEADLINE" gh "$KIND" view "$NUMBER" --repo "$REPO" --json state
    printf '%s' "$OUT" | jq -ce --arg t "$(rd_now)" '
        select(.state | IN("OPEN", "CLOSED", "MERGED"))
        | (.state != "OPEN") as $done
        | {kind: "close", status: "ok", verdict: (if $done then "confirmed" else "not_confirmed" end),
           reason: (if $done then "" else "target is open" end), read_at: $t}' 2>/dev/null \
        || refuse close "unreadable state"
    ;;

deferral)
    need_repo
    [ -f "$ROWFILE" ] || usage
    [[ $RUNSTART =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || usage
    RAW=$(rd_deadline "$DEADLINE" "$RD_DEFERRAL_CHECK" --row-file "$ROWFILE" --run-start "$RUNSTART" 2>/dev/null)
    rc=$?
    [ "$rc" -eq 124 ] && refuse deferral "disposal check timed out after ${DEADLINE}s"
    # The check prints one line; anything else is an answer this script
    # doesn't interpret.
    case "$RAW" in *$'\n'*) refuse deferral "disposal check printed more than one line" ;; esac
    case "$rc:$RAW" in
        0:"disposed filed "*)
            N=${RAW#disposed filed }
            N=${N#\#}
            rd_valid_number "$N" || refuse deferral "disposal names an unreadable issue number"
            # An issue that can't be read is not verified rather than
            # undisposed: gh doesn't tell a missing issue from a failed read.
            read_or_fail deferral "$DEADLINE" gh issue view "$N" --repo "$REPO" --json number
            jq -nc --arg how "filed #$N" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: $how, read_at: $t}' ;;
        0:"disposed closed"|0:"disposed carried "*)
            jq -nc --arg how "${RAW#disposed }" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: $how, read_at: $t}' ;;
        0:"undisposed raised-this-run")
            jq -nc --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: true, how: "raised this run", read_at: $t}' ;;
        1:"undisposed "*)
            jq -nc --arg why "${RAW#undisposed }" --arg t "$(rd_now)" \
                '{kind: "deferral", status: "ok", disposed: false, how: $why, read_at: $t}' ;;
        *)
            refuse deferral "disposal check failed (exit $rc)" ;;
    esac
    ;;

*) usage ;;
esac
