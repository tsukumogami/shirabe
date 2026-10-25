#!/usr/bin/env bash
# state-handover.sh -- the stored set a replacement coordinator continues
# from, read from the record alone, and its gaps. A read; the `reconcile`
# state's handover gate runs it with --check
# (docs/designs/archive/DESIGN-coordinate-record-container.md, Decision 3).
#
# Usage:
#   state-handover.sh --session S [--check]
#   state-handover.sh --scope roadmap|discipline --name N --repo O/R [--check]   (tests)
#
# The session must have a found record (coord-log.sh run-facts); the override
# flags are for tests, with RS_SESSION naming the session that holds it.
#
# Prints, as one JSON object: arguments and cap (Run's rows, or null),
# coordinator (the current address, or null), told (who has been told it),
# workers (one per live holding: unit, worker, phase, told, next), work (every
# Work row, local agents included), standing (every Standing row), holds (the
# Holds section as it stands) and gaps. It also prints the crash set (PRD
# R17): each worker's pushed_head when kept, reports_to (the row, or null),
# rules and briefs (their rows' values), friction, and host (record/host). A
# gap is {gap, fix}:
#   no-arguments | no-cap | no-coordinator   a Run row is missing
#   no-reports-to                            the reports-to row is missing
#   no-next-step <unit>                      a live holding has no Work row
#   leg-unclassified <worker>                a live holding's leg names a
#                                            request this host's store
#                                            doesn't hold (the run was
#                                            imported here), and the leg has
#                                            no end yet (PRD R15)
#   not-told <worker>                        a live holding's Worker has no
#                                            `told` row for the current address
#                                            and no `pending` row (a worker
#                                            whose session ended, recorded so
#                                            the handover doesn't wait on it)
#   carry-unacknowledged                     a discipline rotation carried
#                                            its predecessor's state, and no
#                                            Standing go-ahead set since this
#                                            run's start (not one the carry
#                                            brought) acknowledges it; printed
#                                            as carry: {carried, start,
#                                            acknowledged}
# A live holding is one dispatched and not merged: a row whose Dispatch status
# is `dispatched` and that doesn't carry a Verified head with a blank Pull
# request (merged, waiting for its teardown, so its worker has nothing left to
# report). A `dispatching` row is left out: its worker may not have started,
# and the reconcile pass settles it to `dispatched` when the listing finds
# its worker, before this gate runs, so a launched worker is checked from the
# next start on. Each fix is the state-stored-set.sh call that closes the gap.
#
# With --check nothing is printed on success; the gaps go to stderr.
#
# Exit codes: 0 no gaps (or printed, without --check); 1 --check found gaps;
# 2 a read failed; 10 the run has no found record, or the target isn't a
# canonical record of this scope; 64 usage.
#
# koto reads: the record through state-read.sh, and koto request get
# <request> for each live holding on a leg. It reads nothing on GitHub.
set -uo pipefail

PROG=state-handover
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO=
CHECK=0

usage() { sed -n '/^# Usage:/,/^# Prints/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --check) CHECK=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/state-common.sh"
lib_facts
lib_run_found || { echo "$PROG: the run has no found record" >&2; exit 10; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/state-handover.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT
rs_record "$WD/parsed.json"
case $? in
    0) ;;
    65) echo "$PROG: $(lib_record_name) doesn't read back as a $SCOPE record for $NAME" >&2; exit 10 ;;
    4) lib_scrub < "$WD/parsed.json.err" >&2; exit 10 ;;
    12) lib_die2 "$(lib_scrub < "$WD/parsed.json.err")" ;;
    *) lib_die2 "cannot read the record: $(lib_scrub < "$WD/parsed.json.err")" ;;
esac
# The crash set and record/host are part of what a replacement continues from
# (PRD R17).
rs_host "${RS_SESSION:-$SESSION}" "$WD/host.json" || lib_die2 "cannot read record/host: $(lib_scrub < "$WD/host.json.err")"
[ -s "$WD/parsed.json.pushed" ] || echo '{}' > "$WD/parsed.json.pushed"

# A live holding on a leg whose request this host's store doesn't hold (the run
# was imported here) has no end yet: the gap holds until reconcile-legs.sh
# re-legs it or moves it to the message path (PRD R15). koto exits 2 for a
# request its store doesn't hold; any other failed read is a failed read.
: > "$WD/unclassified"
while IFS='	' read -r w rp; do
    [ -n "$w" ] || continue
    "${KOTO:-${KOTO_BIN:-koto}}" request get "${rp%%:*}" < /dev/null > /dev/null
    case $? in
        0) ;;
        2) printf '%s\t%s\n' "$w" "$rp" >> "$WD/unclassified" ;;
        *) lib_die2 "cannot read request ${rp%%:*} of $w's leg" ;;
    esac
done <<EOF
$(jq -r '.holdings[] | select(.dispatch_status == "dispatched")
    | select(((.verified_head // "") != "" and (.pull_request // "") == "") | not)
    | select((.return_path // "") | startswith("leg ")) | [.worker, (.return_path | ltrimstr("leg "))] | @tsv' "$WD/parsed.json")
EOF
jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {worker: .[0], leg: .[1]})' "$WD/unclassified" > "$WD/unclassified.json" \
    || lib_die2 "jq failed"

# A rotation that carried its predecessor's state (a record/rotation naming its
# predecessor, or this run's carry report, coord/predecessor_carry.json)
# dispatches and merges
# nothing on it until a person acknowledges the carry: a Standing go-ahead set at
# or after this run's start (the start of its chain of restarts, coord-log.sh
# chain-start, so a crash restart doesn't ask again), and not one the carry
# itself brought over (the report lists those).
echo '{"carried": false}' > "$WD/carry.json"
if [ -n "$SESSION" ] && [ "$SCOPE" = discipline ]; then
    RS=${RS_SESSION:-$SESSION}
    CARRIED=false
    if rs_key "$SESSION" coord/predecessor_carry.json "$WD/report.json"; then
        jq -e '.verdict == "carried"' "$WD/report.json" > /dev/null 2>&1 && CARRIED=true
    else
        case $? in 1) echo '{}' > "$WD/report.json" ;; *) lib_die2 "cannot read coord/predecessor_carry.json" ;; esac
    fi
    rs_rotation "$RS" "$WD/rotation.json"
    case $? in
        0) jq -e '.predecessor != null' "$WD/rotation.json" > /dev/null && CARRIED=true ;;
        1) ;;
        *) lib_die2 "cannot read record/rotation" ;;
    esac
    if [ "$CARRIED" = true ]; then
        START=$(bash "$HERE/coord-log.sh" chain-start --session "$SESSION" 2>/dev/null) || lib_die2 "cannot read the run's start"
        START=$(printf '%s' "$START" | cut -c1-16)Z
        jq -c --arg s "$START" '{carried: true, start: $s, carried_ids: [(.standing // [])[] | .standing]}' "$WD/report.json" > "$WD/carry.json" \
            || lib_die2 "coord/predecessor_carry.json is not JSON"
    fi
fi

jq -c --slurpfile host "$WD/host.json" --slurpfile pushed "$WD/parsed.json.pushed" --slurpfile unc "$WD/unclassified.json" \
    --slurpfile carry "$WD/carry.json" '
    def runval($k): [(.run // [])[] | select(.key == $k) | .value][0];
    (.run // []) as $run
    | ([$run[] | select(.key == "told") | .value]) as $told
    | ([$run[] | select(.key == "pending") | .value]) as $pending
    | ((.work // []) | map(select(.kind == "holding") | {(.item): .}) | add // {}) as $work
    | [.holdings[] | select(.dispatch_status == "dispatched")
        | select(((.verified_head // "") != "" and (.pull_request // "") == "") | not)] as $live
    | {arguments: runval("arguments"), cap: runval("cap"), coordinator: runval("coordinator"), told: $told, pending: $pending,
       workers: [$live[] | {unit, worker, phase, told: (.worker as $w | $told | index($w) != null),
                            pending: (.worker as $w | $pending | index($w) != null),
                            next: ($work[.unit].next // null)}],
       work: (.work // []), standing: (.standing // []), holds: (.holds // [])}
    | .workers |= map(.worker as $w | if $pushed[0][$w] then . + {pushed_head: $pushed[0][$w]} else . end)
    | . + {reports_to: ([$run[] | select(.key == "reports-to") | .value][0]), rules: [$run[] | select(.key == "rules") | .value],
         briefs: [$run[] | select(.key == "briefs") | .value], friction: ([$run[] | select(.key == "friction") | .value][0]),
         host: $host[0]}
    | (if $carry[0].carried then
         ($carry[0].carried_ids) as $brought
         | .carry = {carried: true, start: $carry[0].start,
                     acknowledged: any(.standing[]; .kind == "go-ahead" and .set >= $carry[0].start
                                                    and (.standing as $s | $brought | index($s) | not))}
       else . end)
    | .gaps = ([
        (if .carry.carried == true and (.carry.acknowledged | not)
         then {gap: "carry-unacknowledged", fix: "show the person the carried holds and Standing rows (coord/predecessor_carry.json), then record their go-ahead: state-stored-set.sh --standing go-ahead --what \"the carried state is acknowledged\" --owner <who>"}
         else empty end),
        (if .arguments == null then {gap: "no-arguments", fix: "state-stored-set.sh --run arguments \"<the arguments this run was started with>\" --by <who>"} else empty end),
        (if .cap == null then {gap: "no-cap", fix: "state-stored-set.sh --run cap <n> --by <who set it>"} else empty end),
        (if .coordinator == null then {gap: "no-coordinator", fix: "state-stored-set.sh --run coordinator <your address> --by <you>"} else empty end),
        (if .reports_to == null then {gap: "no-reports-to", fix: "state-stored-set.sh --run reports-to \"<role>[ at <address>]\" --by <who>"} else empty end),
        (.workers[] | select(.next == null) | {gap: "no-next-step \(.unit)", fix: "state-stored-set.sh --work \"\(.unit)\" --kind holding --who \(.worker) --next \"<what happens next>\""}),
        ($unc[0][] | {gap: "leg-unclassified \(.worker)", fix: "reconcile-legs.sh --session <this run> --topic \(.worker) --return-path \"leg \(.leg)\" (the reconcile pass runs it; run it by hand when the pass reported it not verified)"}),
        (if .coordinator != null then (.workers[] | select((.told or .pending) | not) | {gap: "not-told \(.worker)", fix: "send \(.worker) a line naming the address, then state-stored-set.sh --told \(.worker) --by <you>; when its session has ended and can'"'"'t be messaged, state-stored-set.sh --pending \(.worker) --by <you>, and it learns the address when it next starts"}) else empty end)
      ])' "$WD/parsed.json" > "$WD/out.json" || lib_die2 "jq failed"

if [ "$CHECK" = 1 ]; then
    N=$(jq '.gaps | length' "$WD/out.json")
    [ "$N" = 0 ] && exit 0
    echo "$PROG: the record can't hand this run over yet; $N gap(s):" >&2
    jq -r '.gaps[] | "  \(.gap): \(.fix)"' "$WD/out.json" >&2
    exit 1
fi
cat "$WD/out.json"
