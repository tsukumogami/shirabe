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
#               recommendation one of the options; every option explained,
#               `<option> -- <explanation>`; reason, context and problem
#               non-empty after trimming; a ground; the run's target)
#   withdrawal  Owed withdrawal
#   reply       State settled, Owed reply, and an Outcome cell carrying its
#               reason (`<outcome>; reason: <reason>`)
#   redirect    decision_next routed `redirect <n> <seq>`, naming the report by
#               its log sequence; entry <n> holds this run's `report <seq>.<i>`
#               stamp; some entry holds that report's addressed mark (the
#               codec's d_addressed_mark, an Evidence line record-decision.sh
#               --open-from-report writes); and entry <n> has no Evidence line
#               stamped `redirect <seq>`, which --sent writes. Stamps are read by
#               position (the codec's d_stamps), never from a line's text.
#
# On a render it writes the text to the context key coord/decision_message.txt
# with coord-log.sh seal --file --key and prints
# `message <kind> <n> <round> [report:<seq>] [qseal:<seq>:<sha256>] keyseal:<seq>:<sha256>`,
# sealed (report:<seq> on a redirect, naming the report it answers). An
# escalation also writes its structured form, for asking a person with a
# question tool, to coord/decision_question.json: {decision, round, question,
# context, problem, recommendation, reason, options: [{label, explanation,
# recommended}]}, the recommended option first; qseal is that key's seal. keyseal is the
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
#      <its explanation>
#   2. <other option>
#      <its explanation>
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
set -f
set -- $CAP
set +f
[ "${1-}" = "$WORD" ] || refuse "decision_next routed \`${1-}\`, not \`$WORD\`"
N=${2-} REP=
[[ $N =~ ^[1-9][0-9]*$ ]] || refuse "decision_next's verdict names no entry"
if [ "$KIND" = redirect ]; then
    REP=${3-}
    [[ $REP =~ ^[1-9][0-9]*$ ]] || refuse "decision_next's redirect names no report"
fi

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

# A redirect is owed per report, so its check reads the whole section.
if [ "$KIND" = redirect ]; then
    bash "$HERE/record-decision.sh" --session "$SESSION" --list > "$T/section.json" 2> "$T/read.err" \
        || { cat "$T/read.err" >&2; lib_die2 "cannot read the Decisions section"; }
else
    printf '{"next":1,"entries":[]}\n' > "$T/section.json"
fi

# Whether the entry owes this kind now; stderr says why not.
jq -r --arg k "$KIND" --arg t "$TARGET" --arg run "$RUN" --arg rep "$REP" --slurpfile sec "$T/section.json" '
  include "record-codec";
  def of_report: .run == $run and .kind == "report" and (.seq | split(".")[0]) == $rep;
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
    if any(d_stamps[]; of_report) | not then "entry \(.decision) holds nothing from report \($rep) of this run"
    elif any($sec[0].entries[] | d_stamps[]; of_report and (.text | startswith(d_addressed_mark))) | not
      then "report \($rep) asked no one but the coordinator"
    elif any(d_stamps[]; .run == $run and .kind == "redirect" and .seq == $rep) then "report \($rep) has had its redirect"
    else "" end
  end' -L "$HERE" "$T/entry.json" > "$T/why" 2> "$T/jq.err" || { cat "$T/jq.err" >&2; lib_die2 "cannot check entry $N"; }
[ -s "$T/why" ] && [ "$(cat "$T/why")" != "" ] && refuse "$(cat "$T/why")"

# The text. `@` is encoded in every free-text cell, as in the record.
jq -r --arg k "$KIND" '
  include "record-codec";
  def e: gsub("@"; "&#64;");
  def src_ref: if (.source | test("^coordinator ")) then (.source | capture("#(?<n>[0-9]+) round (?<r>[0-9]+)") | "decision \(.n) round \(.r)")
               else "decision \(.decision) round \(.round)" end;
  if $k == "escalation" then
    .recommendation as $r | .reason as $why
    | ([d_options[] | select(.label == $r)] + [d_options[] | select(.label != $r)]) as $ord
    | "Decision \(.decision) round \(.round).\n\n\(.context | e)\n\n\(.problem | e)\n\n\(.question | e)\n"
      + ($ord | to_entries | map("\(.key + 1). \(.value.label | e)"
          + (if .key == 0 then " (recommended: \($why | e))" else "" end)
          + "\n   \(.value.explanation | e)\n") | join(""))
      + "\nAnswer naming decision \(.decision) round \(.round) and an option, or give another outcome with its reason.\n"
  elif $k == "withdrawal" then
    "Withdrawn: decision \(.decision) round \(.round).\n\n\(.question | e)\n\nNew evidence reopened this decision, so the escalation is withdrawn. No answer is needed.\n"
  elif $k == "reply" then
    (.outcome | capture("^(?<o>.*?); reason: (?<r>.*)$")) as $out
    | "Answer: \(src_ref).\n\n\(.question | e)\n\nOutcome: \($out.o | e)\nReason: \($out.r | e)\nDecided by: \(.decided_by | e)\n"
  else
    "Redirect: your questions go to your coordinator.\n\nQuestions in your report go to the coordinator that dispatched you, not to a person. The coordinator answers each one, or escalates it with a recommendation. The first is decision \(.decision). Ask them under a Questions: part in your report, and repeat any that go unanswered.\n"
  end' -L "$HERE" "$T/entry.json" > "$T/message.txt" || lib_die2 "cannot render entry $N"

# store <file> <key>: the key's bytes, sealed to this visit; prints the seal
# without its `sealed:` prefix.
store() {
    local s
    s=$(bash "$HERE/coord-log.sh" seal --session "$SESSION" --state "$STATE" --file "$1" --key "$2")
    case $? in
        0) ;;
        66) lib_die2 "cannot store $2" ;;
        *) lib_die2 "cannot seal $2" ;;
    esac
    [[ $s =~ ^sealed:[0-9]+:[0-9a-f]{64}$ ]] || lib_die2 "the seal on $2 is malformed"
    printf '%s' "${s#sealed:}"
}

QSEAL=
if [ "$KIND" = escalation ]; then
    if command -v sha256sum >/dev/null 2>&1; then DIGEST=$(sha256sum < "$T/message.txt" | cut -d' ' -f1)
    else DIGEST=$(shasum -a 256 < "$T/message.txt" | cut -d' ' -f1); fi
    printf 'Digest: %s\n' "$DIGEST" >> "$T/message.txt"
    # The structured form, for asking a person with a question tool: the same
    # entry, the recommended option first, every option with its explanation.
    jq -c -L "$HERE" 'include "record-codec";
      def e: gsub("@"; "&#64;");
      .recommendation as $r
      | {decision: (.decision | tonumber), round: (.round | tonumber), question: (.question | e),
         context: (.context | e), problem: (.problem | e), recommendation: ($r | e), reason: (.reason | e),
         options: ([d_options[] | select(.label == $r) | . + {recommended: true}]
                   + [d_options[] | select(.label != $r) | . + {recommended: false}]
                   | map({label: (.label | e), explanation: (.explanation | e), recommended}))}' \
        "$T/entry.json" > "$T/question.json" || lib_die2 "cannot build the structured form"
    QSEAL=$(store "$T/question.json" coord/decision_question.json) || exit 2
fi
KEYSEAL=$(store "$T/message.txt" coord/decision_message.txt) || exit 2
ROUND=$(jq -r '.round' "$T/entry.json")
seal_token "message $KIND $N $ROUND${REP:+ report:$REP}${QSEAL:+ qseal:$QSEAL} keyseal:$KEYSEAL"
