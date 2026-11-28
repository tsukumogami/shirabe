#!/usr/bin/env bash
# decision-render.sh -- render the message a decision entry owes, from the
# live entry. The render states' default action (escalate, decision_withdraw,
# decision_reply, decision_redirect): the coordinator sends exactly the text
# this writes and marks it sent with state-decision.sh --sent, which checks
# the text against this render's seal.
#
# Usage: decision-render.sh --session S --state ST --kind escalation|withdrawal|reply|redirect
#
# The entry is the one decision_next routed: its sealed DECISION_NEXT capture
# (`escalate <n>`, `withdraw <n>`, `reply <n>` or `redirect <n>`), whose word
# must be the kind's. Never an argument. The run's escalation target is its
# REPORTS_TO variable (coord-log.sh vars): `a person` when empty, else
# `coordinator <topic>`. The entry is read live through state-decision.sh
# --read.
#
# It refuses (prints `refused`, sealed) unless the entry owes that kind right
# now, so a second rendering after the owing cleared is refused too:
#   escalation  State escalated, Owed escalation, and state-schema.jq's
#               escalation_problems for the run's target is empty (held by a
#               question identity, one pass-up ground, the run's target); to
#               a person, also every released decision has an undecided
#               attempt of this session's behind it (koto decisions attempts
#               --in=<session> --question <identity>). Limit: an attempt
#               recorded by a predecessor session of the same chain doesn't
#               count, as koto reads attempts per session; the refusal names
#               the shirabe question attempt line that records one here
#   withdrawal  Owed withdrawal. For an entry held by a question, the line
#               where the question would be is its identity, which the
#               receiving coordinator's report-questions.sh matches it by
#   reply       State settled, Owed reply, and an Outcome cell carrying its
#               reason (`<outcome>; reason: <reason>`)
#   redirect    decision_next routed `redirect <n> <seq>`, naming the report by
#               its log sequence; entry <n> holds this run's `report <seq>.<i>`
#               stamp; some entry holds that report's addressed mark (the
#               state-schema.jq's d_addressed_mark, an Evidence line state-decision.sh
#               --open-from-report writes); and no entry has an Evidence line
#               stamped `redirect <seq>`, which --sent writes. Stamps are read by
#               position (state-schema.jq's d_stamps), never from a line's text.
#
# On a render it writes the text to the context key coord/decision_message.txt
# with coord-log.sh seal --file --key and prints
# `message <kind> <n> <round> [entries:<n>@<round>.<n>@<round>] [report:<seq>] [qseal:<seq>:<sha256>] keyseal:<seq>:<sha256>`,
# sealed (report:<seq> on a redirect, naming the report it answers; entries:
# on an escalation, every entry it carries). keyseal is the key's own seal,
# carried in the engine-written capture so a reader can check the key against
# it (coord-log.sh check --key, with `keyseal:` read as `sealed:`). Free text
# is rendered with `@` encoded, as in the record, so a message never mentions
# anyone. No message names a sender topic: a run has no variable for its own,
# and the receiver takes the source from its holding.
#
# An escalation carries the routed entry and the other escalated entries
# owing their escalation to the same target, lowest first, at most four. No
# code here lays out a question's fields: its content is koto's, and only
# shirabe question render presents it.
#   To a person: the identities are ordered as shirabe question pending
#   --in <session> lists them (one it doesn't list goes last, by identity),
#   and `shirabe question render <identities> --in <session>` is run.
#   coord/decision_question.json is its first prompt, byte for byte (jq -c of
#   `.prompts[0]`), the input to a question tool; qseal is that key's seal.
#   The message is that prompt's `text`. Only the entries whose identities
#   that prompt carries are listed in entries:. When an entry's decision has
#   no undecided attempt of this session's behind it the render is refused
#   and no prompt input is written. A need, which render puts under
#   `requests`, is never in a prompt, so an escalation of needs alone is
#   refused here.
#   To a coordinator: the message names each identity and nothing else; the
#   receiving coordinator reads each question from koto (its report-questions.sh
#   takes them from koto decisions open), so no text is re-worded.
#   shirabe is SHIRABE_BIN when set, else the one on PATH.
#
# An old-style escalation (an entry held by no question identity, escalated
# in a run under way when entries came to be held by identities) is rendered
# alone, as it was before: `Decision <n> round <r>.`, the context, problem and
# question paragraphs, the options with the recommended one first and its
# reason, the fixed answer line, then `Digest: <sha256 of every byte above>`;
# coord/decision_question.json is its structured form {decision, round,
# question, context, problem, recommendation, reason, options: [{label,
# explanation, recommended}]}, and the verdict carries no entries:.
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
# shirabe, as the other coordinate scripts call it: SHIRABE_BIN, else the one on PATH.
SHIRABE=${SHIRABE_BIN:-shirabe}
. "$HERE/state-common.sh"
lib_run_stamp

T=$(mktemp -d "${TMPDIR:-/tmp}/decision-render.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT
# One record read for the step: the entry and, for a redirect, the section
# come from one read of the Decisions section (shirabe#1315).
rs_once_begin "$T/once" decisions || lib_die2 "cannot make a temporary directory"

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

bash "$HERE/state-decision.sh" --session "$SESSION" --read "$N" > "$T/entry.json" 2> "$T/read.err"
case $? in
    0) ;;
    1) refuse "the record has no entry $N" ;;
    10) cat "$T/read.err" >&2; refuse "the record can't be read canonically" ;;
    *) cat "$T/read.err" >&2; lib_die2 "cannot read entry $N" ;;
esac

# A redirect is owed per report, and an escalation carries every entry owing
# one to the target, so their checks read the whole section.
if [ "$KIND" = redirect ] || [ "$KIND" = escalation ]; then
    bash "$HERE/state-decision.sh" --session "$SESSION" --list > "$T/section.json" 2> "$T/read.err" \
        || { cat "$T/read.err" >&2; lib_die2 "cannot read the Decisions section"; }
else
    printf '{"next":1,"entries":[]}\n' > "$T/section.json"
fi

# Whether the entry owes this kind now; stderr says why not.
jq -r --arg k "$KIND" --arg t "$TARGET" --arg run "$RUN" --arg rep "$REP" --slurpfile sec "$T/section.json" '
  include "state-schema";
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
    elif any($sec[0] | d_section_stamps[]; of_report and (.text | startswith(d_addressed_mark))) | not
      then "report \($rep) asked no one but the coordinator"
    elif any($sec[0] | d_section_stamps[]; .run == $run and .kind == "redirect" and .seq == $rep) then "report \($rep) has had its redirect"
    else "" end
  end' -L "$HERE" "$T/entry.json" > "$T/why" 2> "$T/jq.err" || { cat "$T/jq.err" >&2; lib_die2 "cannot check entry $N"; }
[ -s "$T/why" ] && [ "$(cat "$T/why")" != "" ] && refuse "$(cat "$T/why")"

# The text. `@` is encoded in every free-text cell, as in the record.
jq -r --arg k "$KIND" '
  include "state-schema";
  def e: gsub("@"; "&#64;");
  def src_ref: if (.source | test("^coordinator ")) then (.source | capture("#(?<n>[0-9]+) round (?<r>[0-9]+)") | "decision \(.n) round \(.r)")
               else "decision \(.decision) round \(.round)" end;
  # An old-style escalation (an entry held by no question identity, from a
  # run under way when entries came to be held by identities) is rendered as
  # it was then; one held by an identity is rendered by shirabe below.
  if $k == "escalation" then
    if d_identity != "" then empty
    else
      .recommendation as $r | .reason as $why
      | ([d_options[] | select(.label == $r)] + [d_options[] | select(.label != $r)]) as $ord
      | "Decision \(.decision) round \(.round).\n\n\(.context | e)\n\n\(.problem | e)\n\n\(.question | e)\n"
        + ($ord | to_entries | map("\(.key + 1). \(.value.label | e)"
            + (if .key == 0 then " (recommended: \($why | e))" else "" end)
            + "\n   \(.value.explanation | e)\n") | join(""))
        + "\nAnswer naming decision \(.decision) round \(.round) and an option, or give another outcome with its reason.\n"
    end
  elif $k == "withdrawal" then
    # An entry held by a question names its identity where the question
    # would be, so the receiving coordinator matches the withdrawal by it.
    "Withdrawn: decision \(.decision) round \(.round).\n\n\(if d_identity != "" then d_identity else (.question | e) end)\n\nNew evidence reopened this decision, so the escalation is withdrawn. No answer is needed.\n"
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

# koto_out <file> <args...>: koto's answer into <file>; a failed read stops.
koto_out() {
    local f=$1; shift
    "$KOTO" "$@" > "$f" 2> "$T/koto.err" || { lib_scrub < "$T/koto.err" >&2; echo >&2; lib_die2 "cannot read koto ($1 $2)"; }
}
QSEAL= ELIST=
LEGACY=0
[ "$KIND" = escalation ] && [ -z "$(jq -r -L "$HERE" 'include "state-schema"; d_identity' "$T/entry.json")" ] && LEGACY=1
if [ "$LEGACY" = 1 ]; then
    # An old-style escalation, as it was rendered before entries were held by
    # question identities: the digest line, and the structured form for
    # asking a person with a question tool (the recommended option first).
    if command -v sha256sum >/dev/null 2>&1; then DIGEST=$(sha256sum < "$T/message.txt" | cut -d' ' -f1)
    else DIGEST=$(shasum -a 256 < "$T/message.txt" | cut -d' ' -f1); fi
    printf 'Digest: %s\n' "$DIGEST" >> "$T/message.txt"
    jq -c -L "$HERE" 'include "state-schema";
      def e: gsub("@"; "&#64;");
      .recommendation as $r
      | {decision: (.decision | tonumber), round: (.round | tonumber), question: (.question | e),
         context: (.context | e), problem: (.problem | e), recommendation: ($r | e), reason: (.reason | e),
         options: ([d_options[] | select(.label == $r) | . + {recommended: true}]
                   + [d_options[] | select(.label != $r) | . + {recommended: false}]
                   | map({label: (.label | e), explanation: (.explanation | e), recommended}))}' \
        "$T/entry.json" > "$T/question.json" || lib_die2 "cannot build the structured form"
    QSEAL=$(store "$T/question.json" coord/decision_question.json) || exit 2
elif [ "$KIND" = escalation ]; then
    # The entries the message carries: the routed one, then the other
    # escalated entries owing their escalation to this target, lowest first,
    # at most four.
    jq -c -L "$HERE" --arg t "$TARGET" --arg n "$N" 'include "state-schema";
      [.entries[] | select(.state == "escalated" and .owed == "escalation" and .target == $t and d_identity != "")
        | {n: .decision, r: .round, id: d_identity}]
      | ([.[] | select(.n == $n)] + ([.[] | select(.n != $n)] | sort_by(.n | tonumber))) | .[0:4]' \
        "$T/section.json" > "$T/batch.json" || lib_die2 "cannot read the escalated entries"
    jq -r '.[] | [.n, .id] | @tsv' "$T/batch.json" > "$T/batch.tsv" || lib_die2 "cannot read the escalated entries"
    if [ "$TARGET" = "a person" ]; then
        # The owner is asked only a decision this session attempted: each one
        # has an undecided attempt of the session's tied to its question.
        while IFS=$'\t' read -r bn bid; do
            koto_out "$T/history.json" decisions history "$bid"
            [ "$(jq -r '.question.need // "decision"' "$T/history.json")" = decision ] || continue
            koto_out "$T/attempts.json" decisions attempts "--in=$SESSION" --question "$bid"
            jq -e --arg q "$bid" 'any((.attempts // [])[]; .result == "undecided" and (.status // "in-effect") == "in-effect"
                and ((((.questions // []) | index($q)) != null) or .question == $q))' "$T/attempts.json" > /dev/null \
                || refuse "entry $bn (question $bid) is escalated to the owner with no undecided attempt of this session's behind it; record one here with: shirabe question attempt --in $SESSION --what '<the question>' --result undecided --basis ${bid%/*}:${bid##*/}"
        done < "$T/batch.tsv"
        "$SHIRABE" question pending --in "$SESSION" > "$T/pending.json" 2> "$T/shirabe.err" \
            || { lib_scrub < "$T/shirabe.err" >&2; echo >&2; lib_die2 "cannot read shirabe question pending"; }
        jq -r --slurpfile p "$T/pending.json" '[($p[0].questions // [])[].identity] as $o
            | sort_by((($o | index(.id)) // 1000000), .id) | .[].id' "$T/batch.json" > "$T/ordered" \
            || lib_die2 "cannot order the escalated questions"
        IDS=()
        while read -r bid; do IDS+=("$bid"); done < "$T/ordered"
        "$SHIRABE" question render "${IDS[@]}" --in "$SESSION" > "$T/render.json" 2> "$T/shirabe.err"
        rc=$?
        case $rc in
            0) ;;
            8) refuse "a question escalated here is no longer open: $(lib_scrub < "$T/shirabe.err" | head -1)" ;;
            *) lib_scrub < "$T/shirabe.err" >&2; echo >&2; lib_die2 "shirabe question render exited $rc" ;;
        esac
        jq -e '(.prompts // []) | length > 0' "$T/render.json" > /dev/null \
            || refuse "shirabe question render gave no prompt: a need is a request, never a question tool's"
        # The prompt input, byte for byte the render's first prompt; the
        # message, that prompt's own text.
        jq -c '.prompts[0]' "$T/render.json" > "$T/question.json" || lib_die2 "cannot read the rendered prompt"
        jq -j '.prompts[0].text' "$T/render.json" > "$T/message.txt" || lib_die2 "cannot read the rendered prompt"
        printf '\n' >> "$T/message.txt"
        ELIST=$(jq -r --slurpfile r "$T/render.json" '($r[0].prompts[0].identities // []) as $p
            | [.[] | select(.id as $i | $p | index($i)) | "\(.n)@\(.r)"] | join(".")' "$T/batch.json") \
            || lib_die2 "cannot read the rendered prompt"
        case ".$ELIST" in *".$N@"*) ;; *) refuse "the rendered prompt doesn't carry entry $N" ;; esac
        QSEAL=$(store "$T/question.json" coord/decision_question.json) || exit 2
    else
        # To a coordinator: each identity, and no text of the question's.
        jq -r '"Passed up to you in koto, by identity:\n\n" + (map(.id) | join("\n"))' "$T/batch.json" > "$T/message.txt" \
            || lib_die2 "cannot render the escalation"
        ELIST=$(jq -r 'map("\(.n)@\(.r)") | join(".")' "$T/batch.json") || lib_die2 "cannot read the escalated entries"
    fi
fi
KEYSEAL=$(store "$T/message.txt" coord/decision_message.txt) || exit 2
ROUND=$(jq -r '.round' "$T/entry.json")
seal_token "message $KIND $N $ROUND${ELIST:+ entries:$ELIST}${REP:+ report:$REP}${QSEAL:+ qseal:$QSEAL} keyseal:$KEYSEAL"
