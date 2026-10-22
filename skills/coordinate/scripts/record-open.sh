#!/usr/bin/env bash
# record-open.sh -- open this scope's coordinator record, exactly once.
# Agent-run, from the directive of state record_open; never a default action.
#
# It re-reads GitHub first, because the find that routed here may be minutes
# old: a record that now exists (an open issue with the exact title, or an
# open pull request on the record branch) is refused with exit 10 rather than
# opened a second time. The body must be a canonical record for this scope in
# the right container before anything is written.
#
# Roadmap scope: one issue titled "Coordinator record: ROADMAP-<name>".
# Discipline scope: the branch coordinate/discipline-<name> cut from the
# default branch's head with one empty commit, made through GitHub's git-data
# API (the coordinator usually has no checkout of the host), then a draft pull
# request titled "docs(coordinate): <name> rotation <start> to <end>". An
# existing branch is refused unless --recut, which deletes the remote ref
# first (the find's stale-branch and unopened cases), so a squash-merged
# history never comes back.
#
# On the session store (roadmap scope, --store session or the run's STORE
# variable; docs/designs/DESIGN-coordinator-session-record.md, Decision 10) the
# issue opens in the moved shape, every section empty and a Run section holding
# only the `store session` row, and the body's state, with that row, is written
# into the run's session (record/meta and one key per section) through the
# write core. The issue comes first because the seed writes through the core
# against that record's number, so a seed that fails leaves the issue open in
# the moved shape with no state behind it (record= already printed, then the
# core's own exit). Running this again is refused (exit 10: the issue exists),
# and the next start's find stops at `session-absent`; a person closes the empty
# issue, and the start after that opens the record afresh.
#
# A discipline rotation on the session store
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3): when
# the run's find sealed `first`, the rotation opens in this run's session: no
# branch, no commit, no pull request. The body (an empty record of the
# discipline) gains the `store session` Run row and is seeded through the write
# core, then record-state.sh --rotation writes record/rotation, {start, end,
# host_repo, predecessor: null}. It prints record=<session>.
#
# --carry is predecessor_carry's step, agent-run like every write, after the
# find sealed `predecessor <session>` or `predecessor handoff:<sha>`. It builds this
# rotation's first state from the predecessor's: Holdings, Deferrals, Side
# effects, Reversals, Holds, Run, Standing, Work, the unsettled Decisions
# entries and the next decision number, read from the predecessor's session,
# or, for the one-time bridge from a rotation that ran on GitHub, from
# docs/disciplines/<name>.md at <sha> through the handoff parser. The state is
# seeded through the write core like any write (its checks, its JSON
# validation), and record/rotation names the predecessor (null for the
# bridge), the window today to today plus ROTATION_DAYS less one. The carry
# report, the predecessor and the holds and Standing rows it carried, goes to
# coord/predecessor_carry.json and stdout, then `carried=<predecessor>` (exit
# 0), or `refused` with the reason on stderr and in the report (exit 65). A
# carry run again after it landed reads as carried; one cut short is seeded
# again.
#
# Usage:
#   record-open.sh --session S --body-file F [--start YYYY-MM-DD --end YYYY-MM-DD] [--recut]
#                  [--store github|session]
#   record-open.sh --session S --carry
#   record-open.sh --scope roadmap|discipline --name N --repo O/R
#                  --skip-session-checks --body-file F [...]         (tests)
#
# --start and --end are required at discipline scope and refused at roadmap
# scope. Before any read, the session must pass `coord-log.sh provenance` and
# show no directed transition in the run.
#
# Exit codes: 0 opened (prints record=<url>); 10 refused (a record exists, the
# branch exists without --recut, provenance, or a directed transition); 11 a
# write failed partway (prints step=<ref-delete|commit|ref-create|pr-create|
# issue-create|moved-render|seed-render>); 2 a read failed; 64 usage; 65 the
# body was refused. On the session store, once record=<url> is printed, a
# failed seed exits with the write core's code (10, 11, 12, 13 or 65), the
# issue left as the paragraph above describes. A session rotation's open exits
# 0 (record=<session>) or with the write core's or record-state.sh's code;
# --carry exits 0 carried, 65 refused, 2 a read failed.
#
# GitHub calls:
#   reads:  those record-common.sh's lib_open_issues and lib_discipline_read make;
#           gh api --method GET repos/R/git/ref/heads/<default> --jq .object.sha
#           gh api --method GET repos/R/git/commits/<sha> --jq .tree.sha
#   writes: gh issue create --repo R --title T --body-file F
#           gh api --method DELETE repos/R/git/refs/heads/coordinate/discipline-<name>
#           gh api --method POST repos/R/git/commits -f message=... -f tree=... -f parents[]=...
#           gh api --method POST repos/R/git/refs -f ref=refs/heads/... -f sha=...
#           gh pr create --repo R --draft --head ... --base <default> --title T --body-file F
set -uo pipefail

PROG=record-open
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= BODY= START= END= STORE=
RECUT=0 SKIP_CHECKS=0 CARRY=0 NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --body-file) [ $# -ge 2 ] || usage; BODY=$2; shift 2 ;;
        --start) [ $# -ge 2 ] || usage; START=$2; shift 2 ;;
        --end) [ $# -ge 2 ] || usage; END=$2; shift 2 ;;
        --recut) RECUT=1; shift ;;
        --store) [ $# -ge 2 ] || usage; STORE=$2; shift 2 ;;
        --carry) CARRY=1; shift ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
if [ "$CARRY" = 1 ]; then
    [ -n "$SESSION" ] && [ -z "$BODY$START$END$STORE$SCOPE$NAME$REPO" ] && [ "$RECUT" = 0 ] || usage
else
    [ -n "$BODY" ] && [ -r "$BODY" ] || usage
fi
. "$HERE/record-common.sh"
lib_facts
[ "$CARRY" = 0 ] || [ "$SCOPE" = discipline ] || usage

# rotation_write <start> <end> <predecessor-or-empty>: record/rotation for this
# run's rotation, through record-state.sh (its writer). Exits with its code on a
# refusal.
rotation_write() {
    jq -n -c --arg s "$1" --arg e "$2" --arg h "$REPO" --arg p "$3" \
        '{start: $s, end: $e, host_repo: $h, predecessor: (if $p == "" then null else $p end)}' > "$T/rotation.json" \
        || lib_die2 "jq failed"
    bash "$HERE/record-state.sh" --session "$SESSION" --rotation "$T/rotation.json" > /dev/null
}

# store_row <state-file> <out>: the state with the `store session` Run row a
# record on the session store keeps (the crash set's rows need it), added when
# it has none.
store_row() {
    jq -c --arg t "$(date -u +%Y-%m-%dT%H:%MZ)" '
        if any((.run // [])[]; .key == "store") then .
        else .run = ((.run // []) + [{key: "store", value: "session", set_by: "the session rotation (record-open.sh)", set: $t}]) end' "$1" > "$2"
}

if [ "$CARRY" = 1 ]; then
    T=$(mktemp -d "${TMPDIR:-/tmp}/record-open.XXXXXX") || lib_die2 "cannot make a temporary directory"
    trap 'rm -rf "$T"' EXIT
    TOKEN=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name RECORD_FIND --state record_find --any-visit 2>/dev/null) \
        || lib_die2 "the run's find sealed no verdict"
    PRED=${TOKEN% sealed:*}
    case "$PRED" in "predecessor "*) PRED=${PRED#predecessor } ;; *) lib_die2 "the run's find sealed no predecessor: ${TOKEN% sealed:*}" ;; esac
    lib_slug
    # carry_report <verdict> <reason> [<state-file>]: the report into
    # coord/predecessor_carry.json and on stdout, then carried=<predecessor>
    # (exit 0) or refused (exit 65, the reason on stderr).
    carry_report() {
        local st=${3:-}
        [ -n "$st" ] || { echo '{}' > "$T/empty.json"; st="$T/empty.json"; }
        jq -c --arg v "$1" --arg r "$2" --arg p "$PRED" '{verdict: $v, predecessor: $p, reason: $r,
            holds: [(.holds // [])[] | {hold, on, until, set_by}],
            standing: [(.standing // [])[] | {standing, kind, owner}]}' "$st" > "$T/report.json" || lib_die2 "jq failed"
        "$KOTO" context add "$SESSION" coord/predecessor_carry.json --from-file "$T/report.json" < /dev/null > /dev/null 2> "$T/k.err" \
            || lib_die2 "koto context add coord/predecessor_carry.json failed: $(lib_scrub < "$T/k.err")"
        cat "$T/report.json"
        if [ "$1" = carried ]; then
            echo "carried=$PRED"
            exit 0
        fi
        echo "refused"
        echo "$PROG: refused: $2" >&2
        exit 65
    }
    # A carry that already landed: this run holds the rotation, naming PRED.
    if rs_rotation "$SESSION" "$T/mine" 2> /dev/null; then
        if [ "$(jq -r '.predecessor // ""' "$T/mine")" = "$PRED" ] || { [[ $PRED =~ ^handoff: ]] && jq -e '.predecessor == null' "$T/mine" > /dev/null; }; then
            rs_session_state "$SESSION" "$T/landed" > /dev/null 2>&1 || lib_die2 "cannot read this run's rotation"
            carry_report carried "the carry had landed" "$T/landed"
        fi
        carry_report refused "this run already holds a rotation that names another predecessor"
    fi
    # The predecessor's state, as JSON.
    if [[ $PRED =~ ^coordinate-${SLUG}-[0-9]{8}T[0-9]{6}Z$ ]]; then
        rs_session_state "$PRED" "$T/pred"
        case $? in
            0) ;;
            4|12) carry_report refused "$PRED holds no readable record: $(lib_scrub < "$T/pred.err" | head -1)" ;;
            *) lib_die2 "cannot read $PRED's record: $(lib_scrub < "$T/pred.err")" ;;
        esac
        jq -e --arg n "$NAME" '.scope == {kind: "discipline", name: $n}' "$T/pred" > /dev/null \
            || carry_report refused "$PRED's record is not this discipline's"
        RPRED=$PRED
    elif [[ $PRED =~ ^handoff:[0-9a-f]{40}$ ]]; then
        lib_file_at "docs/disciplines/$NAME.md" "${PRED#handoff:}" "$T/handoff.md"
        case $? in
            0) ;;
            1) carry_report refused "docs/disciplines/$NAME.md is not at ${PRED#handoff:}" ;;
            *) lib_die2 "cannot read docs/disciplines/$NAME.md: $(lib_scrub < "$T/handoff.md.err")" ;;
        esac
        if ! bash "$HERE/record-parse.sh" --format handoff "$T/handoff.md" > "$T/pred" 2> "$T/parse.err"; then
            carry_report refused "docs/disciplines/$NAME.md is not a handoff: $(lib_scrub < "$T/parse.err" | head -1)"
        fi
        jq -e --arg n "$NAME" --arg h "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" \
            '.scope.name == $n and (.rotation.host_repo | ascii_downcase) == $h' "$T/pred" > /dev/null \
            || carry_report refused "docs/disciplines/$NAME.md is a handoff for another discipline or host"
        RPRED=
    else
        carry_report refused "the predecessor $PRED is neither a session of this discipline nor handoff:<sha>"
    fi
    # This rotation's first state: the predecessor's sections, its unsettled
    # decisions under the same next number, and the store row.
    jq -c --arg n "$NAME" '{scope: {kind: "discipline", name: $n},
            holdings: (.holdings // []), deferrals: (.deferrals // []),
            side_effects: (.side_effects // []), reversals: (.reversals // [])}
        + (if (.holds // []) == [] then {} else {holds: .holds} end)
        + (if (.run // []) == [] then {} else {run: .run} end)
        + (if (.standing // []) == [] then {} else {standing: .standing} end)
        + (if (.work // []) == [] then {} else {work: .work} end)
        + (if .decisions == null then {}
           else {decisions: {next: .decisions.next, entries: [(.decisions.entries // [])[] | select(.state != "settled")]}} end)
        | .holdings |= map(del(.pushed_head))' "$T/pred" > "$T/carry.json" || lib_die2 "jq failed"
    store_row "$T/carry.json" "$T/next.json" || lib_die2 "jq failed"
    if ! bash "$HERE/record-render.sh" --container issue --written "$(lib_now)" "$T/next.json" > "$T/seed.md" 2> "$T/render.err"; then
        carry_report refused "the predecessor's state doesn't render as a record: $(lib_scrub < "$T/render.err" | head -1)" "$T/next.json"
    fi
    lib_write_guard
    # The core takes over T and its EXIT trap, so it runs in a subshell: its
    # refusal becomes this carry's `refused`, sealed below.
    if ! ( BODY="$T/seed.md" END= CLOSE=0
           . "$HERE/record-write-core.sh"
           SESSION_SEED=1 CORE_STORE=session
           core_write > /dev/null ) 2> "$T/seed.err"; then
        carry_report refused "the carry's write was refused: $(lib_scrub < "$T/seed.err" | head -2 | tr '\n' ' ')" "$T/next.json"
    fi
    TODAY=$(date -u +%Y-%m-%d)
    DAYS=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.ROTATION_DAYS // "7"')
    [[ $DAYS =~ ^[1-9][0-9]{0,2}$ ]] || DAYS=7
    ENDD=$(jq -rn --arg d "$TODAY" --argjson n "$DAYS" '$d | strptime("%Y-%m-%d") | mktime + (($n - 1) * 86400) | strftime("%Y-%m-%d")') \
        || lib_die2 "cannot compute the rotation's end"
    if ! rotation_write "$TODAY" "$ENDD" "$RPRED" 2> "$T/rot.err"; then
        carry_report refused "the rotation's window wasn't written: $(lib_scrub < "$T/rot.err" | head -1)" "$T/next.json"
    fi
    carry_report carried "carried from $PRED" "$T/next.json"
fi
# The new record's store: --store, else the run's STORE variable
# (coordinate-open.sh --store), else GitHub.
if [ -z "$STORE" ] && [ -n "$SESSION" ]; then
    STORE=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.STORE // ""') \
        || lib_die2 "the session's variables couldn't be read"
fi
case "${STORE:-github}" in github|session) ;; *) usage ;; esac
# At discipline scope the store isn't the invocation's: the find decides, and a
# new rotation opens on the session store (below).
if [ "$SCOPE" = discipline ]; then
    lib_valid_date "$START" && lib_valid_date "$END" || usage
    if [ "$END" \< "$START" ]; then echo "$PROG: refused: the end date $END is before the start $START" >&2; exit 65; fi
    PR_TITLE="docs(coordinate): $NAME rotation $START to $END"
else
    [ -z "$START$END" ] && [ "$RECUT" = 0 ] || usage
fi
lib_write_guard

T=$(mktemp -d "${TMPDIR:-/tmp}/record-open.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

lib_parse "$BODY" "$T/parsed.json"
case $? in
    0) ;;
    3|65) echo "$PROG: refused: the body is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$T/parsed.json.err" >&2; echo >&2; exit 65 ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac
# A new record opens with no Decisions section: entries are written, and a
# predecessor's are carried in, only by record-decision.sh, which checks each
# one.
if jq -e 'has("decisions")' "$T/parsed.json" > /dev/null; then
    echo "$PROG: refused: a new record opens without a Decisions section; record-decision.sh writes and carries decisions" >&2
    exit 65
fi

step_failed() { echo "step=$1"; echo "$PROG: the $1 write failed: $(lib_scrub < "$T/w.err")" >&2; exit 11; }

# A new discipline rotation on the session store (the find sealed `first`): no
# branch, no commit, no pull request. The body is seeded into this run's session
# through the write core, with the `store session` Run row, then its window goes
# to record/rotation.
if [ "$SCOPE" = discipline ] && lib_session_rotation; then
    [ "$RECUT" = 0 ] || { echo "$PROG: --recut is for a rotation on GitHub; a session rotation has no branch" >&2; exit 64; }
    jq 'del(.written)' "$T/parsed.json" > "$T/body.json" || lib_die2 "jq failed"
    store_row "$T/body.json" "$T/seed.json" || lib_die2 "jq failed"
    bash "$HERE/record-render.sh" --container issue --written "$(lib_now)" "$T/seed.json" > "$T/seed.md" 2> "$T/w.err" || step_failed seed-render
    # The core takes over T and its EXIT trap; it removes this script's own
    # scratch directory as CORE_CLEANUP, so the window is written from a copy.
    ROT_T=$(mktemp -d "${TMPDIR:-/tmp}/record-open-rot.XXXXXX") || lib_die2 "cannot make a temporary directory"
    ( BODY="$T/seed.md" END= CLOSE=0 CORE_CLEANUP=$T
      . "$HERE/record-write-core.sh"
      SESSION_SEED=1 CORE_STORE=session
      core_write > /dev/null ) || { RC=$?; rm -rf "$ROT_T"; exit $RC; }
    T=$ROT_T
    trap 'rm -rf "$T"' EXIT
    rotation_write "$START" "$END" "" || exit $?
    echo "record=$SESSION"
    exit 0
fi

if [ "$SCOPE" = roadmap ]; then
    lib_open_issues "$T/issues.json" || lib_die2 "the open-issue listing failed"
    N=$(jq length "$T/issues.json")
    if [ "$N" -gt 0 ]; then
        echo "$PROG: refused: an open issue titled \"$ISSUE_TITLE\" exists (#$(jq -r 'map(.number | tostring) | join(", #")' "$T/issues.json"))" >&2
        exit 10
    fi
    if [ "$STORE" != session ]; then
        URL=$(gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body-file "$BODY" 2> "$T/w.err" < /dev/null) || step_failed issue-create
        echo "record=$(printf '%s' "$URL" | tail -1)"
        exit 0
    fi
    # On the session store (docs/designs/DESIGN-coordinator-session-record.md,
    # Decision 10) the issue opens in the moved shape, a Run section holding
    # only the `store session` row, and the record's state, that row included,
    # goes into this run's session through the write core's seeding write.
    NOWM=$(date -u +%Y-%m-%dT%H:%MZ)
    jq -c --arg t "$NOWM" '{scope, holdings: [], deferrals: [], side_effects: [], reversals: [],
        run: [{key: "store", value: "session", set_by: "the invocation (--store session)", set: $t}]}' "$T/parsed.json" \
        | bash "$HERE/record-render.sh" --container issue --written "$(lib_now)" > "$T/moved.md" 2> "$T/w.err" || step_failed moved-render
    jq -c --arg t "$NOWM" 'del(.written) | .run = ((.run // []) + [{key: "store", value: "session", set_by: "the invocation (--store session)", set: $t}])' "$T/parsed.json" \
        | bash "$HERE/record-render.sh" --container issue --written "$(lib_now)" > "$T/seed.md" 2> "$T/w.err" || step_failed seed-render
    URL=$(gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body-file "$T/moved.md" 2> "$T/w.err" < /dev/null) || step_failed issue-create
    URL=$(printf '%s' "$URL" | tail -1)
    REF=${URL##*/issues/}
    [[ $REF =~ $RE_NUM ]] || lib_die2 "the new issue's URL names no number: $URL"
    echo "record=$URL"
    # The core takes over T and its EXIT trap; it removes this script's own
    # scratch directory, which holds the seed body, as CORE_CLEANUP.
    BODY="$T/seed.md" END= CLOSE=0 CORE_CLEANUP=$T
    . "$HERE/record-write-core.sh"
    SESSION_SEED=1 CORE_STORE=session
    core_write > /dev/null || exit $?
    exit 0
fi

lib_discipline_read "$T" || lib_die2 "a discipline read failed"
OPEN=$(jq -r '[.[] | select(.state == "OPEN") | .number | tostring] | join(", #")' "$T/prs.json")
if [ -n "$OPEN" ]; then
    echo "$PROG: refused: $BRANCH has an open pull request (#$OPEN)" >&2
    exit 10
fi
if [ "$BRANCH_EXISTS" = 1 ]; then
    if [ "$RECUT" = 0 ]; then
        echo "$PROG: refused: $BRANCH exists; re-run with --recut to delete and cut it again" >&2
        exit 10
    fi
    gh api --method DELETE "repos/$REPO/git/refs/heads/$BRANCH" > /dev/null 2> "$T/w.err" < /dev/null || step_failed ref-delete
fi
BASE_SHA=$(gh api --method GET "repos/$REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha 2> /dev/null < /dev/null) || lib_die2 "cannot read the head of $DEFAULT_BRANCH"
[[ $BASE_SHA =~ $RE_SHA ]] || lib_die2 "the head of $DEFAULT_BRANCH is not a sha"
TREE=$(gh api --method GET "repos/$REPO/git/commits/$BASE_SHA" --jq .tree.sha 2> /dev/null < /dev/null) || lib_die2 "cannot read the tree of $BASE_SHA"
[[ $TREE =~ $RE_SHA ]] || lib_die2 "the tree of $BASE_SHA is not a sha"
NEW=$(gh api --method POST "repos/$REPO/git/commits" -f message="docs(coordinate): open $NAME rotation record" \
    -f tree="$TREE" -f "parents[]=$BASE_SHA" --jq .sha 2> "$T/w.err" < /dev/null) || step_failed commit
[[ $NEW =~ $RE_SHA ]] || step_failed commit
gh api --method POST "repos/$REPO/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$NEW" > /dev/null 2> "$T/w.err" < /dev/null || step_failed ref-create
URL=$(gh pr create --repo "$REPO" --draft --head "$BRANCH" --base "$DEFAULT_BRANCH" --title "$PR_TITLE" \
    --body-file "$BODY" 2> "$T/w.err" < /dev/null) || step_failed pr-create
echo "record=$(printf '%s' "$URL" | tail -1)"
