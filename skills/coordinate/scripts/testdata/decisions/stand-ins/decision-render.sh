#!/usr/bin/env bash
# decision-render.sh -- STAND-IN for decisions-replay_engine_test.sh.
#
# Renders the message the current entry owes, with the DESIGN's fixed first
# lines, into "$DEC_ST/<session>.message" (the text) and
# "$DEC_ST/<session>.message.json" (kind, entry, round, source), and refuses
# an entry that doesn't owe the kind asked for. It doesn't write or seal the
# detail key the real renderer does. Issue 10 of the coordinate-decisions plan
# replaces it with skills/coordinate/scripts/decision-render.sh.
#
# Usage: decision-render.sh --session S --state ST --kind escalation|withdrawal|reply|redirect
set -uo pipefail
[ "${1-}" = --session ] && [ "${3-}" = --state ] && [ "${5-}" = --kind ] || exit 64
SESSION=$2 STATE=$4 KIND=$6
. "$(cd "$(dirname "$0")" && pwd)/model-lib.sh"

n=$(m -r '.current // empty')
e=$(m --argjson n "${n:-0}" '.entries[] | select(.id == $n)')
owes() { printf '%s' "$e" | jq -e "$1" >/dev/null; }
case "$KIND" in
    escalation) owes '.owed == "escalation" and .rec != "" and .reason != ""' ;;
    withdrawal) owes '.owed == "withdrawal"' ;;
    reply) owes '.owed == "reply"' ;;
    redirect) owes '.redirect == true' ;;
    *) exit 64 ;;
esac || { seal "$STATE" refused; exit 0; }

# A reply to a coordinator names the source entry and round, which the
# source column carries: `coordinator <topic> #<n> round <r>`.
printf '%s' "$e" | jq -r --arg k "$KIND" '
  if $k == "escalation" then
    "Decision \(.id) round \(.round).\n\nContext for \(.question)\n\nWhat is unresolved.\n\n\(.question)\n1. \(.rec) (recommended: \(.reason))\n"
    + (.rec as $r | [.options[] | select(. != $r)] | to_entries | map("\(.key + 2). \(.value)") | join("\n"))
    + "\n\nAnswer naming decision \(.id) round \(.round) and an option, or give another outcome with its reason."
  elif $k == "withdrawal" then "Withdrawn: decision \(.id) round \(.round). No answer is needed."
  elif $k == "reply" then
    (if (.source | test("^coordinator ")) then
       (.source | capture("#(?<n>[0-9]+) round (?<r>[0-9]+)")) as $s
       | "Answer: decision \($s.n) round \($s.r): \(.outcome). Decided by \(.decided_by)."
     else "Decision \(.id): \(.outcome). Decided by \(.decided_by)." end)
  else "Your questions go to the coordinator, which answers them or escalates them with a recommendation."
  end' > "$DEC_ST/$SESSION.message"
printf '%s' "$e" | jq -c --arg k "$KIND" '{kind: $k, n: .id, round: .round, source: .source, outcome: .outcome, decided_by: .decided_by}' \
    > "$DEC_ST/$SESSION.message.json"
seal "$STATE" "message $KIND $n $(printf '%s' "$e" | jq -r .round)"
