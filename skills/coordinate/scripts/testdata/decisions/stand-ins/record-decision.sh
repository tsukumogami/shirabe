#!/usr/bin/env bash
# record-decision.sh -- STAND-IN for decisions-replay_engine_test.sh.
#
# Writes the model model-lib.sh describes, by the DESIGN's mode table. It is
# not bound to the workflow state or a sealed capture as the real script is:
# the harness names the entry. Issue 10 of the coordinate-decisions plan
# replaces it with skills/coordinate/scripts/record-decision.sh.
#
# Usage: record-decision.sh --session S <mode> [args]
#   --open QUESTION OPTION...       a proposed entry whose source is `self`
#   --open-from-report              one entry or evidence line per extracted question
#   --take N
#   --settle N OUTCOME
#   --escalate N REC REASON
#   --hold N REASON
#   --evidence N SOURCE TEXT        TEXT starting "Withdrawn:" marks the source's withdrawal
#   --answer N ROUND OUTCOME [FINAL]  FINAL: the final decider a nested reply named
#   --sent KIND N
# Exit 0 written; 65 refused.
set -uo pipefail
[ "${1-}" = --session ] || exit 64
SESSION=$2; shift 2
. "$(cd "$(dirname "$0")" && pwd)/model-lib.sh"

# The evidence rules, in one jq definition: clear the verdict; on a settled
# entry keep the old outcome as evidence and clear an owed reply; on a sent
# escalation owe a withdrawal, on an unsent one owe nothing.
EVIDENCE='def evidence($src; $text; $wd):
  .evidence += (if .state == "settled"
      then [{src: "previous outcome", text: "\(.outcome) (\(.decided_by))", withdrawal: false}] else [] end)
  | .evidence += [{src: $src, text: $text, withdrawal: $wd}]
  | .owed = (if .state == "escalated" then (if .owed == "escalation" then "" else "withdrawal" end)
             elif .owed == "reply" then "" else .owed end)
  | .verdict = "" | .outcome = "" | .decided_by = "" | .state = "coordinator-verdict";
def owes_reply: (.source | test("^(worker|coordinator|dispatcher) "))
  and ((.evidence | last // {}) | .withdrawal != true);
def settle($o; $by): .state = "settled" | .outcome = $o | .decided_by = $by | .verdict = "settle"
  | .owed = (if owes_reply then "reply" else "" end);'

entry_is() { m -e --argjson n "$1" --arg s "$2" 'any(.entries[]; .id == $n and .state == $s)' >/dev/null; }

case "${1-}" in
    --open-from-report)
        Q="$DEC_ST/$SESSION.questions.json"
        [ -f "$Q" ] || exit 65
        m_set --slurpfile q "$Q" "$EVIDENCE"'
          reduce $q[0][] as $i (.;
            if $i.kind == "withdrawal" then
              (.entries |= map(if .source == $i.source then evidence($i.source; "Withdrawn: decision \($i.n) round \($i.round)."; true) else . end))
            else
              .entries += [{id: .next, round: 0, question: $i.text, options: ($i.options // ["yes", "no"]),
                state: "proposed", source: $i.source, verdict: "", rec: "", reason: "", target: "",
                owed: "", redirect: false, addressed: ($i.addressed // false), evidence: [], outcome: "", decided_by: ""}]
              | .next += 1
            end)
          | (if any(.entries[]; .addressed == true and .redirect_done != true) then
               (first(.entries[] | select(.addressed == true and .redirect_done != true) | .id)) as $f
               | .entries |= map(if .id == $f then .redirect = true else . end
                                 | if .addressed == true then .redirect_done = true else . end)
             else . end)'
        ;;
    --open)
        [ -n "${2-}" ] && [ $# -ge 4 ] || exit 65
        q=$2; shift 2
        opts=$(jq -nc '$ARGS.positional' --args "$@")
        m_set --arg q "$q" --argjson o "$opts" '.entries += [{id: .next, round: 0, question: $q, options: $o,
            state: "proposed", source: "self", verdict: "", rec: "", reason: "", target: "", owed: "",
            redirect: false, evidence: [], outcome: "", decided_by: ""}] | .next += 1'
        ;;
    --take)
        entry_is "$2" proposed || exit 65
        m_set --argjson n "$2" '.entries |= map(if .id == $n then .state = "coordinator-verdict" else . end)'
        ;;
    --settle)
        entry_is "$2" coordinator-verdict || exit 65
        [ -n "${3-}" ] || exit 65
        m_set --argjson n "$2" --arg o "$3" "$EVIDENCE"'
          .entries |= map(if .id == $n then settle($o; "coordinator") else . end)'
        ;;
    --escalate)
        entry_is "$2" coordinator-verdict || exit 65
        [ -n "${3-}" ] && [ -n "${4-}" ] || exit 65
        m_set --argjson n "$2" --arg r "$3" --arg why "$4" --arg t "$(target)" '
          .entries |= map(if .id == $n then .state = "escalated" | .verdict = "escalate" | .round += 1
            | .rec = $r | .reason = $why | .target = $t | .owed = "escalation" else . end)'
        ;;
    --hold)
        entry_is "$2" coordinator-verdict || exit 65
        m_set --argjson n "$2" --arg why "$3" '.entries |= map(if .id == $n then .verdict = "hold" | .reason = $why else . end)'
        ;;
    --evidence)
        m -e --argjson n "$2" 'any(.entries[]; .id == $n)' >/dev/null || exit 65
        wd=false
        case "$4" in Withdrawn:*) wd=true ;; esac
        m_set --argjson n "$2" --arg s "$3" --arg t "$4" --argjson wd "$wd" "$EVIDENCE"'
          .entries |= map(if .id == $n then evidence($s; $t; $wd) else . end)'
        ;;
    --answer)
        n=$2 r=$3 o=$4 fin=${5-}
        by=$(target)
        [ -n "$fin" ] && by="$by (final: $fin)"
        if m -e --argjson n "$n" --argjson r "$r" 'any(.entries[]; .id == $n and .state == "escalated" and .round == $r)' >/dev/null; then
            m_set --argjson n "$n" --arg o "$o" --arg by "$by" "$EVIDENCE"'
              .entries |= map(if .id == $n then settle($o; $by) else . end)'
        elif m -e --argjson n "$n" --arg o "$o" --arg by "$by" 'any(.entries[]; .id == $n and .state == "settled" and .outcome == $o and .decided_by == $by)' >/dev/null; then
            :   # a re-sent answer is already recorded
        else
            exec "$0" --session "$SESSION" --evidence "$n" "$by" "answer: $o"
        fi
        ;;
    --sent)
        case "$2" in
            redirect) m_set --argjson n "$3" '.entries |= map(if .id == $n then .redirect = false else . end)' ;;
            escalation|withdrawal|reply)
                m -e --argjson n "$3" --arg k "$2" 'any(.entries[]; .id == $n and .owed == $k)' >/dev/null || exit 65
                m_set --argjson n "$3" '.entries |= map(if .id == $n then .owed = "" else . end)' ;;
            *) exit 64 ;;
        esac
        ;;
    *) exit 64 ;;
esac
