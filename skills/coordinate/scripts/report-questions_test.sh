#!/usr/bin/env bash
# report-questions_test.sh -- report-questions.sh against the gh and koto
# stand-ins: the Questions part and its citations, question-shaped and
# phrasing-matched lines, fenced and quoted lines skipped, the caps, a report
# with no holding, a coordinator's escalation and withdrawal first lines with
# the digest checked, and the sealed list.
#
# testdata/report-questions/questions-shape.txt is the contract fixture: a
# report written to the exact Questions: shape render-brief.sh asks workers
# for, which render-brief_test.sh checks the brief prints.
#
# Usage: bash skills/coordinate/scripts/report-questions_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/test-lib.sh"
Q="$HERE/report-questions.sh"
RUNSTAMP=20260926T080000Z
db_init

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
ENTRY='{"decision":"3","round":"0","question":"What cap does one question get?","options":"400\n1000","state":"proposed",
  "source":"worker w1 [20260926T080000Z report 5.1]","updated":"2026-09-26T09:00Z"}'

N=0
# run <report-facts token> <report text> [holding-json] [entries-json]: a fresh
# record and session, report_facts' sealed verdict, the report, then the
# extraction. Sets S, OUT (stdout) and RC.
run() {
    N=$((N + 1))
    local ref=$((200 + N)) rec
    rec=$(record_json roadmap feat | jq -c --argjson e "${4:-[]}" '.decisions = {next: 10, entries: $e}')
    [ -n "${3-}" ] && rec=$(printf '%s' "$rec" | jq -c --argjson h "$3" '.holdings = [$h]')
    db '.issues = [] | .issues += [{repo: "acme/widgets", number: $k, title: "Coordinator record: ROADMAP-feat",
        body: $b, state: "open", author: "coord", editor: null}]' --argjson k "$ref" --arg b "$(render "$rec" issue)"
    S="coordinate-roadmap-feat-q$N-$RUNSTAMP"
    found_session "$S" "$(roadmap_vars feat)" "$ref"
    log_to "$S" wait take_report
    printf '%s' "$2" > "$T/report"
    koto context add "$S" worker_report --from-file "$T/report"
    log_to "$S" take_report report_facts
    log_capture "$S" REPORT "$(bash "$HERE/coord-log.sh" seal --session "$S" --state report_facts --token "$1")"
    log_to "$S" report_facts report_questions
    OUT=$(bash "$Q" --session "$S" 2>"$T/err")
    RC=$?
    seen "$OUT" >/dev/null
}
word() { printf '%s' "$OUT" | cut -d' ' -f1; }
list() { koto context get "$S" coord/questions.json; }
WORKER=$(holding w1 '{"entry_point":"/shirabe:work-on"}')
COORD=$(holding rr '{"entry_point":"/shirabe:coordinate"}')

# --- the Questions part -------------------------------------------------------------

run "holding none w1" "$(cat "$HERE/testdata/report-questions/questions-shape.txt")" "$WORKER" "[$ENTRY]"
eq "contract: the brief's Questions shape parses" "0 questions 2" "$RC $(printf '%s' "$OUT" | cut -d' ' -f1-2)"
eq "contract: its items, in order" "Should the extractor also read questions from the pull request body?|Keep the 400-character cap for one question (decision 3)" \
    "$(list | jq -r '[.[].text] | join("|")')"
eq "contract: a citation of the worker's own entry is kept" "null 3" "$(list | jq -r '[.[].cite | tostring] | join(" ")')"
eq "contract: each item is indexed and names the worker" "1 worker w1|2 worker w1" "$(list | jq -r '[.[] | "\(.index) \(.source)"] | join("|")')"
eq "the stored list checks against the key's seal" "$(list)" \
    "$(bash "$HERE/coord-log.sh" check --session "$S" --state report_questions --sealed "$(printf '%s' "$OUT" | tr ' ' '\n' | sed -n 's/^keyseal:/sealed:/p')" --key coord/questions.json)"
printf '[]' > "$T/edited"; koto context add "$S" coord/questions.json --from-file "$T/edited"
bash "$HERE/coord-log.sh" check --session "$S" --state report_questions --sealed "$(printf '%s' "$OUT" | tr ' ' '\n' | sed -n 's/^keyseal:/sealed:/p')" --key coord/questions.json >/dev/null 2>&1
eq "an edited list fails the key's seal" 1 "$?"

run "holding none w1" "$(cat "$HERE/testdata/report-questions/questions-shape.txt")" "$WORKER" \
    "[$(printf '%s' "$ENTRY" | jq -c '.source = "worker w2 [20260926T080000Z report 5.1]"')]"
eq "a citation of another worker's entry is dropped" "null null" "$(list | jq -r '[.[].cite | tostring] | join(" ")')"

run "holding none w1" "$(printf 'Questions:\n1. first?\n\n2) second (decision 3)\nThat is all.\n3. not an item\n')" "$WORKER" "[$ENTRY]"
eq "the part runs over blank lines and ends at the first other line" "first?|second (decision 3)" "$(list | jq -r '[.[].text] | join("|")')"

# --- lines outside the part ------------------------------------------------------------

REPORT_TEXT='Verdict: done.
Should the cap be 400 or 1000?
Please decide whether to ship.
Waiting on the release decision from the vendor.
```
Is this a question in a log?
```
> Is this a quoted question?
~~~
please decide inside a tilde fence
~~~
Last line, without a newline, is a question?'
run "holding none w1" "$REPORT_TEXT" "$WORKER"
eq "a line ending in ?, a decision phrasing and a last line without a newline are questions" \
    "Should the cap be 400 or 1000?|Please decide whether to ship.|Last line, without a newline, is a question?" "$(list | jq -r '[.[].text] | join("|")')"
eq "the phrasing addressed to a person is marked" "false true false" "$(list | jq -r '[.[].addressed | tostring] | join(" ")')"
run "holding none w1" "$(printf 'Should it ship?\r\nDone.\r\n')" "$WORKER"
eq "a CRLF line is read without its carriage return" "Should it ship?" "$(list | jq -r '.[0].text')"

# --- verdicts --------------------------------------------------------------------------

run "holding none w1" "Done. Nothing to ask." "$WORKER"
eq "no question gives none" "0 none" "$RC $(word)"
run "holding none w1" "" "$WORKER"
eq "an empty report is unreadable" "0 unreadable" "$RC $(word)"
run "holding none w1" "$(for i in 1 2 3 4 5 6 7 8 9 10 11; do echo "Question $i?"; done)" "$WORKER"
eq "eleven questions overflow" "0 overflow" "$RC $(word)"
koto context get "$S" coord/questions.json >/dev/null 2>&1
eq "an overflow stores no list" 1 "$?"
run "holding none w1" "$(for i in 1 2 3 4 5 6 7 8 9 10; do echo "Question $i?"; done)" "$WORKER"
eq "ten questions are within the cap" "questions 10" "$(printf '%s' "$OUT" | cut -d' ' -f1-2)"
run "holding none w1" "$(printf 'Is %s?' "$(printf '%400s' '' | tr ' ' x)")" "$WORKER"
eq "a question over 400 characters overflows" "0 overflow" "$RC $(word)"

# --- no holding ------------------------------------------------------------------------

run "unknown w1" "$(cat "$HERE/testdata/report-questions/questions-shape.txt")" "" "[$ENTRY]"
eq "no holding: every citation is dropped" "null null" "$(list | jq -r '[.[].cite | tostring] | join(" ")')"
eq "no holding: the source is the topic the report named" "worker w1" "$(list | jq -r '.[0].source')"
run "refused w1 pr-closed" "Keep it?" "$WORKER"
eq "a refused holding counts as none" "worker w1 null" "$(list | jq -r '.[0] | "\(.source) \(.cite)"')"

# --- a coordinator's first lines ---------------------------------------------------------

escalation() { # escalation <n> <round>: an escalation as decision-render.sh renders it
    printf 'Decision %s round %s.\n\nThe context.\n\nThe problem.\n\nMerge before the release?\n1. wait (recommended: the release is Friday)\n   one upgrade carries both\n2. merge now\n   the format lands this week\n\nAnswer naming decision %s round %s and an option, or give another outcome with its reason.\n' "$1" "$2" "$1" "$2" > "$T/esc"
    printf 'Digest: %s\n' "$(sha < "$T/esc")" >> "$T/esc"
    cat "$T/esc"
}
run "holding none rr" "$(escalation 4 1)" "$COORD"
eq "escalation: one item from a coordinator holding" "0 questions 1" "$RC $(printf '%s' "$OUT" | cut -d' ' -f1-2)"
eq "escalation: its question, options, recommendation and source" \
    'escalation|Merge before the release?|wait -- one upgrade carries both,merge now -- the format lands this week|wait|coordinator rr #4 round 1|4 1' \
    "$(list | jq -r '.[0] | "\(.kind)|\(.text)|\(.options | join(","))|\(.recommended)|\(.source)|\(.n) \(.round)"')"
# The contract with decision-render.sh: an escalation it renders, relayed as a
# report, reads back as the same question, options and recommendation.
RENDERED_ESC='{"decision":"4","round":"1","question":"Merge before the release?",
  "options":"merge now -- the format lands this week\nwait -- one upgrade carries both","state":"escalated",
  "source":"self [20260926T080000Z raise 2]","verdict":"escalate","recommendation":"wait","reason":"the release is Friday",
  "context":"The context.","problem":"The problem.","grounds":"scope","target":"coordinator ws","owed":"escalation","updated":"2026-09-26T09:00Z"}'
db '.issues = [] | .issues += [{repo: "acme/widgets", number: 299, title: "Coordinator record: ROADMAP-low",
    body: $b, state: "open", author: "coord", editor: null}]' \
    --arg b "$(render "$(record_json roadmap low | jq -c --argjson e "[$RENDERED_ESC]" '.decisions = {next: 5, entries: $e}')" issue)"
LOW="coordinate-roadmap-low-$RUNSTAMP"
found_session "$LOW" "$(roadmap_vars low | jq -c '.REPORTS_TO = "ws"')" 299
log_to "$LOW" reconcile decision_next
log_capture "$LOW" DECISION_NEXT "$(bash "$HERE/coord-log.sh" seal --session "$LOW" --state decision_next --token "escalate 4")"
log_to "$LOW" decision_next escalate
bash "$HERE/decision-render.sh" --session "$LOW" --state escalate --kind escalation > /dev/null 2> "$T/render.err" ||
    bad "the round trip renders an escalation" "$(cat "$T/render.err")"
run "holding none rr" "$(koto context get "$LOW" coord/decision_message.txt)" "$COORD"
eq "round trip: decision-render.sh's escalation reads back as the same question, options and recommendation" \
    'Merge before the release?|wait -- one upgrade carries both,merge now -- the format lands this week|wait|coordinator rr #4 round 1' \
    "$(list | jq -r '.[0] | "\(.text)|\(.options | join(","))|\(.recommended)|\(.source)"')"

run "holding none rr" "$(escalation 4 1 | sed 's/The problem./A changed problem./')" "$COORD"
eq "escalation: a body that doesn't hash to its digest is unreadable" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(escalation 4 1 | sed '$d')" "$COORD"
eq "escalation: one without its digest line is unreadable" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(escalation 4 1)" "$COORD" \
    '[{"decision":"2","round":"0","question":"Merge before the release?","options":"wait\nmerge now","state":"proposed","source":"coordinator rr #4 round 1 [20260926T070000Z report 3.1]","updated":"2026-09-26T09:00Z"}]'
eq "escalation: a re-sent one already opened gives none" "0 none" "$RC $(word)"
run "holding none rr" "$(escalation 4 2)" "$COORD" \
    '[{"decision":"2","round":"0","question":"Merge before the release?","options":"wait\nmerge now","state":"settled","source":"coordinator rr #4 round 1 [20260926T070000Z report 3.1]","outcome":"wait; reason: r","decided_by":"a person","updated":"2026-09-26T09:00Z"}]'
eq "escalation: a later round of the same entry opens anew" "questions 1" "$(printf '%s' "$OUT" | cut -d' ' -f1-2)"
run "holding none w1" "$(escalation 4 1)" "$WORKER"
eq "escalation: from a worker holding the first line is ordinary text" "question|Merge before the release?" "$(list | jq -r '[.[] | "\(.kind)|\(.text)"] | join(" ")')"
run "unknown rr" "$(escalation 4 1)" ""
eq "escalation: with no holding the first line is ordinary text" "question" "$(list | jq -r '[.[].kind] | unique | join(" ")')"

OPEN_UP='[{"decision":"2","round":"1","question":"Merge before the release?","options":"wait\nmerge now","state":"escalated","source":"coordinator rr #4 round 1 [20260926T070000Z report 3.1]",
  "verdict":"escalate","recommendation":"wait","reason":"r","context":"c","problem":"p","grounds":"scope","target":"a person","updated":"2026-09-26T09:00Z"}]'
run "holding none rr" "$(printf 'Withdrawn: decision 4 round 1.\n\nNo answer is needed.\n')" "$COORD" "$OPEN_UP"
eq "withdrawal: an item naming the source it reopens" "withdrawal|coordinator rr #4 round 1|4 1" \
    "$(list | jq -r '.[0] | "\(.kind)|\(.source)|\(.n) \(.round)"')"
run "holding none rr" "$(printf 'Withdrawn: decision 5 round 1.\n\nNo answer is needed.\n')" "$COORD" "$OPEN_UP"
eq "withdrawal: of nothing open gives none" "0 none" "$RC $(word)"
run "holding none rr" "$(printf 'Answer: decision 4 round 1.\n\nOutcome: wait\n')" "$COORD" "$OPEN_UP"
eq "an Answer: first line is ordinary text" "0 none" "$RC $(word)"

tokens_ok report-questions
done_tests report-questions
