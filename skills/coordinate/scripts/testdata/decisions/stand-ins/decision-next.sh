#!/usr/bin/env bash
# decision-next.sh -- STAND-IN for decisions-replay_engine_test.sh, until the
# coordinate-decisions plan's Issue 8 ships the real script; Issue 8 removes it
# from the harness's STAND_INS.
#
# The DESIGN's owed rules 3 to 9 in routing order, over the section read
# through record-decision.sh --list: withdraw, reply, redirect, escalate,
# take, verdict (held entries skipped), then clear-report or clear. For a
# verdict it writes the entry to coord/decision.json, which the verdict arm's
# gate requires. Rules 1 and 2 (the carry and the unrecorded writes) and the
# --owed mode are Issue 8's and its own tests cover them.
#
# Usage: decision-next.sh --session S
set -uo pipefail
[ "${1-}" = --session ] || exit 64
SESSION=$2
HERE=$(cd "$(dirname "$0")" && pwd)
RUN=${SESSION##*-}
seal() { bash "$HERE/coord-log.sh" seal --session "$SESSION" --state decision_next --token "$1"; }

D=$(bash "$HERE/record-decision.sh" --session "$SESSION" --list) || exit 2
# redirect: the first entry a report of this run wrote, when an entry from
# that report was addressed to a person and the first carries no redirect line
# for the report.
NEXT=$(printf '%s' "$D" | jq -r --arg run "$RUN" '
  def rep: [(.source + "\n" + (.evidence // "")) | scan("\\[" + $run + " report ([0-9]+)\\.[0-9]+\\]")] | map(.[0]) | unique;
  def pick(f): [.entries[] | select(f) | .decision | tonumber] | min;
  . as $doc
  | ([.entries[] | select((.evidence // "") | test("addressed to a person")) | rep[]] | unique) as $addressed
  | ([$addressed[] as $r
      | ([$doc.entries[] | select(rep | index($r)) | .decision | tonumber] | min) as $n
      | select($n != null)
      | select(any($doc.entries[]; .decision == ($n | tostring)
          and ((.evidence // "") | test("\\[" + $run + " redirect " + $r + "\\]") | not)))
      | {n: $n, r: $r}] | min_by(.n)) as $redirect
  | if pick(.owed == "withdrawal") != null then "withdraw \(pick(.owed == "withdrawal"))"
    elif pick(.owed == "reply") != null then "reply \(pick(.owed == "reply"))"
    elif $redirect != null then "redirect \($redirect.n) \($redirect.r)"
    elif pick(.owed == "escalation") != null then "escalate \(pick(.owed == "escalation"))"
    elif pick(.state == "proposed") != null then "take \(pick(.state == "proposed"))"
    elif pick(.state == "coordinator-verdict" and (.verdict // "") == "") != null
      then "verdict \(pick(.state == "coordinator-verdict" and (.verdict // "") == ""))"
    else "" end') || exit 2

if [ -n "$NEXT" ]; then
    if [ "${NEXT%% *}" = verdict ]; then
        F=$(mktemp "${TMPDIR:-/tmp}/dn-standin.XXXXXX")
        printf '%s' "$D" | jq -c --arg n "${NEXT#* }" '.entries[] | select(.decision == $n)' > "$F"
        koto context add "$SESSION" coord/decision.json --from-file "$F" >/dev/null || { rm -f "$F"; exit 2; }
        rm -f "$F"
    fi
    seal "$NEXT"
    exit 0
fi

# clear-report: the latest report_questions visit routed to decision_open, and
# neither classify_report nor wait has been entered since.
if jq -s -e '
    [.[] | select(.type == "transitioned" or .type == "directed_transition")] as $t
    | ([$t | to_entries[] | select(.value.payload.from == "report_questions") | .key] | last) as $q
    | $q != null and $t[$q].payload.to == "decision_open"
      and ([$t[($q + 1):][] | select(.payload.to == "classify_report" or .payload.to == "wait")] | length) == 0
' "$(koto session dir "$SESSION")/koto-$SESSION.state.jsonl" >/dev/null; then
    seal clear-report
else
    seal clear
fi
