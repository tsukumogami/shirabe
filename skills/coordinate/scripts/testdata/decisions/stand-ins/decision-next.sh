#!/usr/bin/env bash
# decision-next.sh -- STAND-IN for decisions-replay_engine_test.sh.
#
# The DESIGN's owed rules 3 to 9, in routing order, over the model
# model-lib.sh describes: withdraw, reply, redirect, escalate, take, verdict,
# then clear-report or clear. Rules 1 and 2 (carry and the unrecorded writes)
# need the record and the log, which the stand-in doesn't model. Issue 10 of
# the coordinate-decisions plan replaces it with
# skills/coordinate/scripts/decision-next.sh.
#
# Usage: decision-next.sh --session S
set -uo pipefail
[ "${1-}" = --session ] || exit 64
SESSION=$2
. "$(cd "$(dirname "$0")" && pwd)/model-lib.sh"

pick() { # pick <jq filter over one entry>: the lowest id it matches, or empty
    m -r "[.entries[] | select($1) | .id] | min // empty"
}
word="" n=""
for rule in 'withdraw:.owed == "withdrawal"' 'reply:.owed == "reply"' 'redirect:.redirect == true' \
    'escalate:.owed == "escalation"' 'take:.state == "proposed"' \
    'verdict:.state == "coordinator-verdict" and .verdict == ""'; do
    n=$(pick "${rule#*:}")
    if [ -n "$n" ]; then word=${rule%%:*}; break; fi
done

if [ -n "$word" ]; then
    m_set --argjson n "$n" '.current = $n'
    if [ "$word" = verdict ]; then
        m --argjson n "$n" '.entries[] | select(.id == $n)' > "$DEC_ST/$SESSION.decision.json"
        koto context add "$SESSION" coord/decision.json --from-file "$DEC_ST/$SESSION.decision.json" >/dev/null || exit 2
    fi
    seal decision_next "$word $n"
    exit 0
fi

# clear-report: the latest report_questions visit routed to decision_open, and
# neither classify_report nor wait has been entered since.
if jq -s -e '
    [.[] | select(.type == "transitioned" or .type == "directed_transition")] as $t
    | ([$t | to_entries[] | select(.value.payload.from == "report_questions") | .key] | last) as $q
    | $q != null and $t[$q].payload.to == "decision_open"
      and ([$t[($q + 1):][] | select(.payload.to == "classify_report" or .payload.to == "wait")] | length) == 0
' "$(log_file)" >/dev/null; then
    seal decision_next clear-report
else
    seal decision_next clear
fi
