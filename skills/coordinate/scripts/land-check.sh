#!/usr/bin/env bash
# land-check.sh -- the check action of land: may the verified head be merged,
# now? Read-only on GitHub; the merge itself is land-merge.sh, run by the
# coordinator. docs/designs/current/DESIGN-coordinate-merge-policy.md.
#
# Usage: land-check.sh --session S [--pr N] [--repo R] [--no-seal]
#
# 1. The unit's verify capture: the latest VERIFIED capture (with --pr, the
#    latest naming #N), whose seal must check against verify_board at any
#    visit, and which must read `verified <pr> <sha>`. No such capture means
#    the run can't be at land: exit 2.
# 2. The head, re-read live: board-verdict.sh --head-only. A head other than
#    <sha> is `moved <pr> <sha> <new>`.
# 3. The merge state, body, title and base branch, in one read (gh pr view
#    --json mergeStateStatus,body,title,baseRefName,files): DIRTY is `dirty <pr>`.
# 3a. The record's pauses (board-lib.sh's bl_pauses_on, over the record read
#    live): a pause on `all`, or on the unit of the pull request's holding, in
#    force or unreadable and with no go-ahead on that unit, is
#    `paused <pr> <sha>`. It comes before the worker's evidence, so a paused
#    pull request isn't asked for a fix before its merge could happen anyway
#    (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1).
# 4. The worker's review round, read from the body (panel-evidence.sh): no
#    Review panel table, a malformed one, fewer than three seats or any
#    verdict but pass is `unready <pr> <sha>`.
# 5. The reviewed head against <sha> (board-lib.sh's bl_reviewed_fresh): a
#    head further from it than merge-ins of the base branch is `unready`.
# 6. The body's mechanical checks (shirabe validate --pr-body, with the
#    title), then the squash message (squash-message.sh): a failure of either
#    is `unready`.
# 7. The record's holds on the pull request, each evaluated live
#    (board-lib.sh's bl_holds_eval, over the same read): any not met, or whose condition can't be
#    read, is `held <pr> <sha>`. A hold is reported held because this check
#    read it, never because someone remembers it.
# 8. The merge posture: the start's POSTURE capture narrowed by a fresh
#    posture-read.sh (board-lib.sh's bl_merge_posture): `permit <pr> <sha>`,
#    `deny <pr> <sha>` or `confirm <pr> <sha>`.
# 9. For those three, the tokens goal_fit reads: when the run is at roadmap
#    scope and the pull request's Holdings row names a unit by its roadmap
#    heading tag, the roadmap is read on the host's default branch, and on a
#    roadmap/v2 roadmap the detail gains `milestone: {tag, evidence: [clause, ...]}` (milestone.sh
#    evidence; the clauses in the roadmap's order, numbered from 1), so goal
#    fit can name the clauses the pull request advances
#    (docs/designs/DESIGN-milestone-verdicts.md, Decision 2). A version 1
#    roadmap, a discipline scope or no holding naming the pull request adds
#    nothing. A read that fails (a contents read with no content, as for a
#    file over 1 MB, included), or a unit that isn't a milestone with
#    Evidence, adds `milestone_error: <why>` instead and never changes the
#    token: the merge question is already answered.
# The token is sealed to the latest entry into land (captured as LAND). The
# detail goes to context key coord/land.json as data: the verdict and the
# pull request it is about; the pauses as read (pause-read.sh's JSON, with
# the unit and the pause that holds it); for `unready`, the reason (no-evidence,
# malformed:<rule>, too-few-seats, not-unanimous, stale:<why>, body-checks or
# message); the changed files, the evidence as parsed, the freshness result, the body checks' findings, the
# built message and the holds with their states, as far as the check got;
# and from step 9, `milestone` ({tag, evidence}) when the milestone's
# Evidence was read, or `milestone_error` (why it couldn't be) when it wasn't.
#
# The repository is the one the record's Holdings row for #<pr> links;
# --repo overrides it, for tests. --no-seal (tests) prints the bare token.
#
# Exit codes: 0 a token printed; 2 no valid verify capture, or a read failed;
# 64 usage.
set -uo pipefail

PROG=land-check
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/board-lib.sh"

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
SESSION= PR= REPO= NO_SEAL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --pr) [ $# -ge 2 ] || usage; PR=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
bl_session_ok "$SESSION" || usage
[ -z "$PR" ] || bl_pr_ok "$PR" || usage
[ -z "$REPO" ] || bl_repo_ok "$REPO" || usage

if [ -n "$PR" ]; then
    CAP=$(bl_capture "$SESSION" VERIFIED verify_board --any-visit --for "$PR")
else
    CAP=$(bl_capture "$SESSION" VERIFIED verify_board --any-visit)
fi
[ $? -eq 0 ] || { echo "$PROG: no valid verify capture: this run can't be at land" >&2; exit 2; }
set -f; set -- $CAP; set +f
if [ $# -ne 3 ] || [ "$1" != verified ] || ! bl_pr_ok "$2" || ! bl_sha_ok "$3"; then
    echo "$PROG: the verify capture reads [$CAP], not a verified head" >&2
    exit 2
fi
PR=$2 SHA=$3

if [ -z "$REPO" ]; then
    REPO=$(bl_unit_repo "$SESSION" "$PR") || exit 2
fi

HO=$(bash "$HERE/board-verdict.sh" --repo "$REPO" --pr "$PR" --head-only) || { echo "$PROG: the head re-read failed" >&2; exit 2; }
V=$(printf '%s' "$HO" | jq -r '.verdict // ""')
NOW=$(printf '%s' "$HO" | jq -r '.head // ""')
case "$V" in
    head) ;;
    error:head-moved)
        # The ref moved while it was read: whichever of the two isn't the
        # verified head is the new one.
        [ "$NOW" = "$SHA" ] && NOW=$(printf '%s' "$HO" | jq -r '.ref // ""') ;;
    *) echo "$PROG: the head re-read ended in [$V]" >&2; exit 2 ;;
esac
bl_sha_ok "$NOW" || { echo "$PROG: the head re-read gave no sha" >&2; exit 2; }
if [ "$NOW" != "$SHA" ]; then
    bl_seal "$SESSION" land "moved $PR $SHA $NOW" "$NO_SEAL" || exit 2
    exit 0
fi

MS=$(mktemp "${TMPDIR:-/tmp}/land-check.XXXXXX") || exit 2
trap 'rm -f "$MS" "$MS".*' EXIT
bl_gh "$MS" pr view "$PR" --repo "$REPO" --json mergeStateStatus,body,title,baseRefName,files || { echo "$PROG: the pull request read failed" >&2; exit 2; }
STATE=$(jq -r '.mergeStateStatus // ""' "$MS")
[[ $STATE =~ ^[A-Z_]+$ ]] || { echo "$PROG: merge state [$STATE]" >&2; exit 2; }
if [ "$STATE" = DIRTY ]; then
    bl_seal "$SESSION" land "dirty $PR" "$NO_SEAL" || exit 2
    exit 0
fi
jq -r '.body // ""' "$MS" > "$MS.body" || exit 2
TITLE=$(jq -r '.title // ""' "$MS")
BASE=$(jq -r '.baseRefName // ""' "$MS")
bl_branch_ok "$BASE" || { echo "$PROG: base branch [$BASE]" >&2; exit 2; }

DETAIL=$(jq -c --arg pr "$PR" '{pr: $pr, files: [.files[]?.path]}' "$MS") || exit 2
# detail <jq filter> [jq args...]: add to the check's detail.
detail() {
    local f=$1
    shift
    DETAIL=$(printf '%s' "$DETAIL" | jq -c "$@" "$f") || { echo "$PROG: the detail couldn't be built" >&2; exit 2; }
}
# finish <token>: store the detail as coord/land.json (unless --no-seal) and
# print the sealed token.
finish() {
    detail '.verdict = $v' --arg v "${1%% *}"
    if [ "$NO_SEAL" = 0 ]; then
        printf '%s\n' "$DETAIL" > "$MS.detail"
        "$KOTO" context add "$SESSION" coord/land.json --from-file "$MS.detail" >/dev/null || {
            echo "$PROG: could not write coord/land.json" >&2; exit 2; }
    fi
    bl_seal "$SESSION" land "$1" "$NO_SEAL" || exit 2
    exit 0
}
# unready <reason>: what's missing is the worker's to fix.
unready() {
    detail '.reason = $r' --arg r "$1"
    echo "$PROG: unready: $1" >&2
    finish "unready $PR $SHA"
}

# The record, read once for the pauses and the holds.
bl_record_parsed "$SESSION" "$MS.rec" || { echo "$PROG: the record couldn't be read for its pauses and holds" >&2; exit 2; }
PAUSES=$(bl_pauses_on "$MS.rec" "$REPO" "$PR") || { echo "$PROG: the record's pauses couldn't be read" >&2; exit 2; }
detail '.pauses = $p' --argjson p "$PAUSES"
PAUSED=$(printf '%s' "$PAUSES" | jq -r '.paused // empty')
if [ -n "$PAUSED" ]; then
    echo "$PROG: paused: $(printf '%s' "$PAUSES" | jq -r --arg s "$PAUSED" '.pauses[] | select(.standing == $s) | "\(.standing) (on \(.on), until \(.until), \(.state))"')" >&2
    finish "paused $PR $SHA"
fi

EV=$(bash "$HERE/panel-evidence.sh" "$MS.body") || { echo "$PROG: the evidence couldn't be read" >&2; exit 2; }
detail '.evidence = $e' --argjson e "$EV"
case "$(printf '%s' "$EV" | jq -r .status)" in
    ok) ;;
    absent) unready no-evidence ;;
    *) unready "malformed:$(printf '%s' "$EV" | jq -r .reason)" ;;
esac
[ "$(printf '%s' "$EV" | jq .count)" -ge 3 ] || unready too-few-seats
[ "$(printf '%s' "$EV" | jq '.passes == .count')" = true ] || unready not-unanimous

REVIEWED=$(printf '%s' "$EV" | jq -r .reviewed_head)
FRESH=$(bl_reviewed_fresh "$REPO" "$BASE" "$REVIEWED" "$SHA") || { echo "$PROG: the reviewed head's comparison failed" >&2; exit 2; }
detail '.freshness = $f' --arg f "$FRESH"
case "$FRESH" in
    fresh) ;;
    stale\ *) unready "stale:${FRESH#stale }" ;;
    *) echo "$PROG: freshness [$FRESH]" >&2; exit 2 ;;
esac

shirabe validate --pr-body "$MS.body" --pr-title "$TITLE" --format json > "$MS.pb" 2> "$MS.pb.err"
case "$(jq -r '.outcome // ""' "$MS.pb")" in
    clean) ;;
    violations)
        detail '.body_checks = $f' --argjson f "$(jq -c '[.findings[]?.message]' "$MS.pb")"
        unready body-checks ;;
    *) sed 's/^/  /' "$MS.pb.err" | head -n 3 >&2
       echo "$PROG: the PR-body check gave no outcome (its stderr above)" >&2; exit 2 ;;
esac
MSG=$(bash "$HERE/squash-message.sh" --title "$TITLE" "$MS.body" 2> "$MS.msg.err")
case $? in
    0) detail '.message = $m' --arg m "$MSG" ;;
    1) detail '.message_refusal = $m' --arg m "$(head -1 "$MS.msg.err")"
       unready message ;;
    *) echo "$PROG: the message couldn't be built" >&2; exit 2 ;;
esac

HOLDS=$(bl_holds_eval "$MS.rec" "$REPO" "$PR") || { echo "$PROG: the record's holds couldn't be read" >&2; exit 2; }
detail '.holds = $h' --argjson h "$HOLDS"
if [ "$(printf '%s' "$HOLDS" | jq 'any(.[]; .state != "met")')" = true ]; then
    echo "$PROG: held: $(printf '%s' "$HOLDS" | jq -r '[.[] | select(.state != "met") | "\(.hold) (\(.until), \(.state))"] | join(", ")')" >&2
    finish "held $PR $SHA"
fi

P=$(bl_merge_posture "$SESSION") || exit 2

# milestone_evidence: step 9. Prints the milestone detail as JSON, nothing
# when there is none to add; returns 1 with the reason on stdout when the
# read failed.
milestone_evidence() {
    local vars scope roadmap host unit db ms re='^docs/roadmaps/([A-Za-z0-9._-]+/)*ROADMAP-[A-Za-z0-9._-]+\.md$'
    local tagre='^(Feature [0-9]+|[A-Za-z]+[0-9]+[a-z]?)$'
    vars=$(bash "$HERE/coord-log.sh" vars --session "$SESSION") || { echo "the session's variables couldn't be read"; return 1; }
    scope=$(printf '%s' "$vars" | jq -r '.SCOPE // ""')
    roadmap=$(printf '%s' "$vars" | jq -r '.ROADMAP // ""')
    host=$(printf '%s' "$vars" | jq -r '.HOST_REPO // ""')
    [ "$scope" = roadmap ] || return 0
    # The unit of the Holdings row that links this pull request, as
    # bl_pauses_on finds it.
    unit=$(jq -r --arg r "$REPO" --arg n "$PR" \
        '[.holdings[] | select(.pull_request | test("^\\[#" + $n + "\\]\\(https://github\\.com/" + ($r | gsub("\\."; "\\.")) + "/pull/" + $n + "\\)$"; "i")) | .unit][0] // ""' "$MS.rec") \
        || { echo "the record's holdings couldn't be read"; return 1; }
    # Only a roadmap heading's tag can name a milestone; work a person assigned
    # outside the roadmap holds a unit of another shape and gets nothing.
    [[ $unit =~ $tagre ]] || return 0
    bl_repo_ok "$host" || { echo "the host [$host] is not owner/repo"; return 1; }
    if ! [[ $roadmap =~ $re ]] || case "$roadmap" in *..*) true ;; *) false ;; esac; then
        echo "the roadmap path [$roadmap] is not docs/roadmaps/.../ROADMAP-<name>.md"; return 1
    fi
    # Read without --jq, and parsed here, as every other read in this check.
    bl_gh "$MS.host" api --method GET "repos/$host" || { echo "$host couldn't be read for its default branch"; return 1; }
    db=$(jq -r '.default_branch // ""' "$MS.host")
    bl_branch_ok "$db" || { echo "$host's default branch [$db] isn't a branch name"; return 1; }
    bl_gh "$MS.rm" api --method GET "repos/$host/contents/$roadmap?ref=$db" || { echo "$roadmap couldn't be read on $db"; return 1; }
    jq -r '.content // empty' "$MS.rm" > "$MS.rm.b64" && [ -s "$MS.rm.b64" ] && lib_b64d "$MS.rm.b64" "$MS.roadmap" \
        || { echo "$roadmap on $db couldn't be decoded"; return 1; }
    [ "$(bash "$HERE/milestone.sh" schema "$MS.roadmap" 2>/dev/null)" = roadmap/v2 ] || return 0
    ms=$(bash "$HERE/milestone.sh" evidence "$MS.roadmap" "$unit" 2> "$MS.ms.err") \
        || { echo "$unit has no Evidence on $db: $(head -1 "$MS.ms.err" | sed 's/^milestone: //')"; return 1; }
    printf '%s' "$ms" | jq -c '{tag, evidence}'
}
if M=$(milestone_evidence); then
    [ -z "$M" ] || detail '.milestone = $m' --argjson m "$M"
else
    echo "$PROG: the milestone's Evidence wasn't read: $M" >&2
    detail '.milestone_error = $e' --arg e "$M"
fi
finish "$P $PR $SHA"
