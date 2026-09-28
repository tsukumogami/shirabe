#!/usr/bin/env bash
# decision-render.sh -- render the message a decision entry owes, from the
# live entry. The render states' default action (escalate, decision_withdraw,
# decision_reply, decision_redirect): the coordinator sends exactly the text
# this writes and marks it sent with record-decision.sh --sent, which checks
# the text against this render's seal.
#
# Usage: decision-render.sh --session S --state ST --kind escalation|withdrawal|reply|redirect
#
# The entry is the one decision_next routed: its sealed DECISION_NEXT capture
# (`escalate <n>`, `withdraw <n>`, `reply <n>` or `redirect <n>`), whose word
# must be the kind's. Never an argument. The run's escalation target is its
# REPORTS_TO variable (coord-log.sh vars): `a person` when empty, else
# `coordinator <topic>`. The entry is read live through record-decision.sh
# --read.
#
# It refuses (prints `refused`, sealed) unless the entry owes that kind right
# now, so a second rendering after the owing cleared is refused too:
#   escalation  State escalated, Owed escalation, and the codec's
#               escalation_problems for the run's target is empty (the
#               recommendation one of the options; reason, context and
#               problem non-empty after trimming; a ground; the run's target)
#   withdrawal  Owed withdrawal
#   reply       State settled, Owed reply, and an Outcome cell carrying its
#               reason (`<outcome>; reason: <reason>`)
#   redirect    the entry holds this run's `report` stamp, and no Evidence line
#               stamped `redirect` with that report's sequence
#
# On a render it writes the text to the context key coord/decision_message.txt
# with coord-log.sh seal --file --key and prints
# `message <kind> <n> <round> keyseal:<seq>:<sha256>`, sealed; keyseal is the
# key's own seal, carried in the engine-written capture so a reader can check
# the key against it (coord-log.sh check --key, with `keyseal:` read as
# `sealed:`). Free text is rendered with `@` encoded, as in the record, so a
# message never mentions anyone. No message names a sender topic: a run has
# no variable for its own, and the receiver takes the source from its
# holding.
#
# An escalation reads:
#
#   Decision <n> round <r>.
#
#   <context paragraph>
#
#   <problem paragraph>
#
#   <question>
#   1. <recommended option> (recommended: <reason>)
#   2. <other option>
#
#   Answer naming decision <n> round <r> and an option, or give another outcome with its reason.
#   Digest: <sha256 of every byte above this line>
#
# Exit codes: 0 a verdict was printed (`message ...` or `refused`); 2 a read
# failed (the capture, the variables, the record); 64 usage.
set -uo pipefail

PROG=decision-render
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= STATE= KIND=
usage() { sed -n '/^# Usage:/,/^# The entry is/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --state) [ $# -ge 2 ] || usage; STATE=$2; shift 2 ;;
        --kind) [ $# -ge 2 ] || usage; KIND=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] && [ -n "$STATE" ] || usage
case "$KIND" in
    escalation) WORD=escalate ;; withdrawal) WORD=withdraw ;; reply) WORD=reply ;; redirect) WORD=redirect ;;
    *) usage ;;
esac
SCOPE= NAME= REPO=
. "$HERE/record-common.sh"
lib_run_stamp

T=$(mktemp -d "${TMPDIR:-/tmp}/decision-render.XXXXXX")
trap 'rm -rf "$T"' EXIT

seal_token() { # seal_token <token>: print it sealed to this state's visit
    bash "$HERE/coord-log.sh" seal --session "$SESSION" --state "$STATE" --token "$1" || lib_die2 "cannot seal the verdict"
}
refuse() { echo "$PROG: refused: $*" >&2; seal_token refused; exit 0; }

# The routed entry.
CAP=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name DECISION_NEXT --state decision_next)
case $? in
    0) ;;
    1) refuse "no sealed decision_next verdict from the latest visit" ;;
    *) lib_die2 "cannot read the decision_next capture" ;;
esac
set -- $CAP
[ "${1-}" = "$WORD" ] || refuse "decision_next routed \`${1-}\`, not \`$WORD\`"
N=${2-}
[[ $N =~ ^[1-9][0-9]*$ ]] || refuse "decision_next's verdict names no entry"

VARS=$(bash "$HERE/coord-log.sh" vars --session "$SESSION") || lib_die2 "cannot read the session's variables"
RT=$(printf '%s' "$VARS" | jq -r '.REPORTS_TO // ""')
if [ -n "$RT" ]; then TARGET="coordinator $RT"; else TARGET="a person"; fi

bash "$HERE/record-decision.sh" --session "$SESSION" --read "$N" > "$T/entry.json" 2> "$T/read.err"
case $? in
    0) ;;
    1) refuse "the record has no entry $N" ;;
    10) cat "$T/read.err" >&2; refuse "the record can't be read canonically" ;;
    *) cat "$T/read.err" >&2; lib_die2 "cannot read entry $N" ;;
esac

# Whether the entry owes this kind now; stderr says why not.
jq -r --arg k "$KIND" --arg t "$TARGET" --arg run "$RUN" '
  include "record-codec";
  . as $e
  | def stamps: [(.source // ""), ((.evidence // "") | split("\n")[])] | [.[] | scan("\\[([0-9]{8}T[0-9]{6}Z) ([a-z]+) ([0-9.]+)\\]")];
  if $k == "escalation" then
    if .state != "escalated" then "entry \(.decision) is \(.state), not escalated"
    elif .owed != "escalation" then "entry \(.decision) owes no escalation"
    else (escalation_problems($t) | join("; ")) end
  elif $k == "withdrawal" then
    if .owed != "withdrawal" then "entry \(.decision) owes no withdrawal" else "" end
  elif $k == "reply" then
    if .state != "settled" then "entry \(.decision) is \(.state), not settled"
    elif .owed != "reply" then "entry \(.decision) owes no reply"
    elif (.outcome | test("; reason: .")) | not then "entry \(.decision)'"'"'s outcome carries no reason"
    else "" end
  else
    ([stamps[] | select(.[0] == $run and .[1] == "report") | .[2] | split(".")[0]] | last) as $rep
    | if $rep == null then "entry \(.decision) was written by no report of this run"
      elif any(stamps[]; .[0] == $run and .[1] == "redirect" and .[2] == $rep) then "the report behind entry \(.decision) has had its redirect"
      else "" end
  end' -L "$HERE" "$T/entry.json" > "$T/why" 2> "$T/jq.err" || { cat "$T/jq.err" >&2; lib_die2 "cannot check entry $N"; }
[ -s "$T/why" ] && [ "$(cat "$T/why")" != "" ] && refuse "$(cat "$T/why")"

# The text. `@` is encoded in every free-text cell, as in the record.
jq -r --arg k "$KIND" '
  def e: gsub("@"; "&#64;");
  def src_ref: if (.source | test("^coordinator ")) then (.source | capture("#(?<n>[0-9]+) round (?<r>[0-9]+)") | "decision \(.n) round \(.r)")
               else "decision \(.decision) round \(.round)" end;
  if $k == "escalation" then
    .recommendation as $r
    | "Decision \(.decision) round \(.round).\n\n\(.context | e)\n\n\(.problem | e)\n\n\(.question | e)\n"
      + "1. \($r | e) (recommended: \(.reason | e))\n"
      + ([.options | split("\n")[] | select(. != $r)] | to_entries | map("\(.key + 2). \(.value | e)\n") | join(""))
      + "\nAnswer naming decision \(.decision) round \(.round) and an option, or give another outcome with its reason.\n"
  elif $k == "withdrawal" then
    "Withdrawn: decision \(.decision) round \(.round).\n\n\(.question | e)\n\nNew evidence reopened this decision, so the escalation is withdrawn. No answer is needed.\n"
  elif $k == "reply" then
    (.outcome | capture("^(?<o>.*?); reason: (?<r>.*)$")) as $out
    | "Answer: \(src_ref).\n\n\(.question | e)\n\nOutcome: \($out.o | e)\nReason: \($out.r | e)\nDecided by: \(.decided_by | e)\n"
  else
    "Redirect: your questions go to your coordinator.\n\nQuestions in your report go to the coordinator that dispatched you, not to a person. The coordinator answers each one, or escalates it with a recommendation. The first is decision \(.decision). Ask them under a Questions: part in your report, and repeat any that go unanswered.\n"
  end' "$T/entry.json" > "$T/message.txt" || lib_die2 "cannot render entry $N"
if [ "$KIND" = escalation ]; then
    if command -v sha256sum >/dev/null 2>&1; then DIGEST=$(sha256sum < "$T/message.txt" | cut -d' ' -f1)
    else DIGEST=$(shasum -a 256 < "$T/message.txt" | cut -d' ' -f1); fi
    printf 'Digest: %s\n' "$DIGEST" >> "$T/message.txt"
fi

KEYSEAL=$(bash "$HERE/coord-log.sh" seal --session "$SESSION" --state "$STATE" --file "$T/message.txt" --key coord/decision_message.txt)
case $? in
    0) ;;
    66) lib_die2 "cannot store the message" ;;
    *) lib_die2 "cannot seal the message" ;;
esac
[[ $KEYSEAL =~ ^sealed:[0-9]+:[0-9a-f]{64}$ ]] || lib_die2 "the message's seal is malformed"
ROUND=$(jq -r '.round' "$T/entry.json")
seal_token "message $KIND $N $ROUND keyseal:${KEYSEAL#sealed:}"
