#!/usr/bin/env bash
# record-handover.sh -- the stored set a replacement coordinator continues
# from, read from the record alone, and its gaps. A read; the `reconcile`
# state's handover gate runs it with --check
# (docs/designs/DESIGN-coordinate-record-container.md, Decision 3).
#
# Usage:
#   record-handover.sh --session S [--check]
#   record-handover.sh --scope roadmap|discipline --name N --repo O/R --ref N [--check]   (tests)
#
# Prints, as one JSON object: arguments and cap (Run's rows, or null),
# coordinator (the current address, or null), told (who has been told it),
# workers (one per live holding: unit, worker, phase, told, next), work (every
# Work row, local agents included), standing (every Standing row), holds (the
# Holds section as it stands) and gaps. A gap is {gap, fix}:
#   no-arguments | no-cap | no-coordinator   a Run row is missing
#   no-next-step <unit>                      a live holding has no Work row
#   not-told <worker>                        a live holding's Worker has no
#                                            `told` row for the current address
# A live holding is one dispatched and not merged: a row whose Dispatch status
# is `dispatched` and that doesn't carry a Verified head with a blank Pull
# request (merged, waiting for its teardown, so its worker has nothing left to
# report). A `dispatching` row is left out: its worker may not have started,
# and the reconcile pass settles it to `dispatched` (or dispatch-failed) from
# the listing before this gate runs, so a launched worker is checked from the
# next start on. Each fix is the record-state.sh call that closes the gap.
#
# With --check nothing is printed on success; the gaps go to stderr.
#
# Exit codes: 0 no gaps (or printed, without --check); 1 --check found gaps;
# 2 a read failed; 10 the run has no found record, or the target isn't a
# canonical record of this scope; 64 usage.
#
# GitHub reads: gh issue view N --repo R --json body | gh pr view N --repo R
# --json body.
set -uo pipefail

PROG=record-handover
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF=
CHECK=0

usage() { sed -n '/^# Usage:/,/^# Prints/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --check) CHECK=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
lib_facts
if [ "$OVERRIDE" = 1 ]; then
    [[ $REF =~ $RE_NUM ]] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
else
    [ -z "$REF" ] || usage
    FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION")
    case $? in
        0) REF=$(printf '%s' "$FACTS" | jq -r '.ref') ;;
        1) echo "$PROG: the run has no found record" >&2; exit 10 ;;
        *) lib_die2 "cannot read the run's facts" ;;
    esac
fi
[[ $REF =~ $RE_NUM ]] || lib_die2 "the record number is not a number"

WD=$(mktemp -d "${TMPDIR:-/tmp}/record-handover.XXXXXX")
trap 'rm -rf "$WD"' EXIT
if [ "$SCOPE" = roadmap ]; then
    gh issue view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.raw" 2> "$WD/r.err" < /dev/null || lib_die2 "cannot read issue #$REF: $(lib_scrub < "$WD/r.err")"
else
    gh pr view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.raw" 2> "$WD/r.err" < /dev/null || lib_die2 "cannot read pull request #$REF: $(lib_scrub < "$WD/r.err")"
fi
tr -d '\r' < "$WD/live.raw" > "$WD/live.md"
lib_parse "$WD/live.md" "$WD/parsed.json"
case $? in
    0) ;;
    3|65) echo "$PROG: #$REF is not a canonical $SCOPE record for $NAME" >&2; exit 10 ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac

jq -c '
    def runval($k): [(.run // [])[] | select(.key == $k) | .value][0];
    (.run // []) as $run
    | ([$run[] | select(.key == "told") | .value]) as $told
    | ((.work // []) | map({(.item): .}) | add // {}) as $work
    | [.holdings[] | select(.dispatch_status == "dispatched")
        | select(((.verified_head // "") != "" and (.pull_request // "") == "") | not)] as $live
    | {arguments: runval("arguments"), cap: runval("cap"), coordinator: runval("coordinator"), told: $told,
       workers: [$live[] | {unit, worker, phase, told: (.worker as $w | $told | index($w) != null),
                            next: ($work[.unit].next // null)}],
       work: (.work // []), standing: (.standing // []), holds: (.holds // [])}
    | .gaps = ([
        (if .arguments == null then {gap: "no-arguments", fix: "record-state.sh --run arguments \"<the arguments this run was started with>\" --by <who>"} else empty end),
        (if .cap == null then {gap: "no-cap", fix: "record-state.sh --run cap <n> --by <who set it>"} else empty end),
        (if .coordinator == null then {gap: "no-coordinator", fix: "record-state.sh --run coordinator <your address> --by <you>"} else empty end),
        (.workers[] | select(.next == null) | {gap: "no-next-step \(.unit)", fix: "record-state.sh --work \"\(.unit)\" --kind holding --who \(.worker) --next \"<what happens next>\""}),
        (if .coordinator != null then (.workers[] | select(.told | not) | {gap: "not-told \(.worker)", fix: "send \(.worker) a line naming the address, then record-state.sh --told \(.worker) --by <you>"}) else empty end)
      ])' "$WD/parsed.json" > "$WD/out.json" || lib_die2 "jq failed"

if [ "$CHECK" = 1 ]; then
    N=$(jq '.gaps | length' "$WD/out.json")
    [ "$N" = 0 ] && exit 0
    echo "$PROG: the record can't hand this run over yet; $N gap(s):" >&2
    jq -r '.gaps[] | "  \(.gap): \(.fix)"' "$WD/out.json" >&2
    exit 1
fi
cat "$WD/out.json"
