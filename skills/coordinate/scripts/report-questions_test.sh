#!/usr/bin/env bash
# report-questions_test.sh -- report-questions.sh against the gh and koto
# stand-ins: the Questions part and its citations, question-shaped and
# phrasing-matched lines, fenced and quoted lines skipped, the caps, a report
# with no holding, a coordinator's escalation and withdrawal first lines with
# the digest checked, and the sealed list.
#
# testdata/report-questions/questions-shape.txt is the contract fixture: a
# report written to the exact Questions: shape a worker's report is asked to
# use (a `Questions:` line, then one numbered item per line).
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
    printf '%s' "${VIA:-message}" > "$T/via"
    koto context add "$S" report_source --from-file "$T/via"
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
eq "contract: a report in the Questions shape parses" "0 questions 2" "$RC $(printf '%s' "$OUT" | cut -d' ' -f1-2)"
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

escalation() { # escalation <n> <round> [question]: an escalation as decision-render.sh renders it
    printf 'Decision %s round %s.\n\nThe context.\n\nThe problem.\n\n%s\n1. wait (recommended: the release is Friday)\n   one upgrade carries both\n2. merge now\n   the format lands this week\n\nAnswer naming decision %s round %s and an option, or give another outcome with its reason.\n' "$1" "$2" "${3:-Merge before the release?}" "$1" "$2" > "$T/esc"
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
run "holding none rr" "$(escalation 4 1 | sed 's/$/\r/')" "$COORD"
eq "escalation: one relayed with CRLF line ends is unreadable, not a worker's question" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(printf 'Hi, relaying this.\n'; escalation 4 1)" "$COORD"
eq "escalation: one with a line put before its first is unreadable, not a worker's question" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(printf 'Hi, relaying this.\n'; escalation 4 1; printf 'Thanks.\n')" "$COORD"
eq "escalation: one with a line before and a line after is unreadable, not a worker's question" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(escalation 4 1 | sed 's/^/> /')" "$COORD"
eq "escalation: one relayed as a quote is unreadable, not dropped" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(escalation 4 1 | sed 's/^/    /')" "$COORD"
eq "escalation: one indented as a code block is unreadable, not a worker's question" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(escalation 4 1 | sed 's/^/ > /')" "$COORD"
eq "escalation: one quoted after a space is unreadable, not dropped" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(printf 'Done with the first half.\nShould the second half wait for the release?\n')" "$COORD"
eq "a coordinator's ordinary report, with no digest line, still gives its questions" "question|Should the second half wait for the release?" \
    "$(list | jq -r '[.[] | "\(.kind)|\(.text)"] | join(" ")')"

withdrawal() { # withdrawal <n> <round>: a withdrawal as decision-render.sh renders it
    printf 'Withdrawn: decision %s round %s.\n\nMerge before the release?\n\nNew evidence reopened this decision, so the escalation is withdrawn. No answer is needed.\n' "$1" "$2"
}
OPEN_UP='[{"decision":"2","round":"1","question":"Merge before the release?","options":"wait\nmerge now","state":"escalated","source":"coordinator rr #4 round 1 [20260926T070000Z report 3.1]",
  "verdict":"escalate","recommendation":"wait","reason":"r","context":"c","problem":"p","grounds":"scope","target":"a person","updated":"2026-09-26T09:00Z"}]'
run "holding none rr" "$(withdrawal 4 1)" "$COORD" "$OPEN_UP"
eq "withdrawal: an item naming the source it reopens" "withdrawal|coordinator rr #4 round 1|4 1" \
    "$(list | jq -r '.[0] | "\(.kind)|\(.source)|\(.n) \(.round)"')"
run "holding none rr" "$(withdrawal 5 1)" "$COORD" "$OPEN_UP"
eq "withdrawal: of an entry never opened gives none" "0 none" "$RC $(word)"
run "holding none rr" "$(printf 'Relaying:\n'; withdrawal 4 1)" "$COORD" "$OPEN_UP"
eq "withdrawal: one with a line put before it is unreadable, not a worker's question" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(withdrawal 4 1 | sed 's/^/> /')" "$COORD" "$OPEN_UP"
eq "withdrawal: one relayed as a quote is unreadable, not dropped" "0 unreadable" "$RC $(word)"
# The contract with decision-render.sh: a withdrawal it renders reads back
# as a withdrawal, so the exact-shape check can't drift from the renderer.
RENDERED_WDR=$(printf '%s' "$RENDERED_ESC" | jq -c '.state = "coordinator-verdict" | .owed = "withdrawal" | .asked = "2026-09-26T09:05Z" | del(.verdict)')
db '.issues = [] | .issues += [{repo: "acme/widgets", number: 298, title: "Coordinator record: ROADMAP-wdr",
    body: $b, state: "open", author: "coord", editor: null}]' \
    --arg b "$(render "$(record_json roadmap wdr | jq -c --argjson e "[$RENDERED_WDR]" '.decisions = {next: 5, entries: $e}')" issue)"
WDR="coordinate-roadmap-wdr-$RUNSTAMP"
found_session "$WDR" "$(roadmap_vars wdr | jq -c '.REPORTS_TO = "ws"')" 298
log_to "$WDR" reconcile decision_next
log_capture "$WDR" DECISION_NEXT "$(bash "$HERE/coord-log.sh" seal --session "$WDR" --state decision_next --token "withdraw 4")"
log_to "$WDR" decision_next decision_withdraw
bash "$HERE/decision-render.sh" --session "$WDR" --state decision_withdraw --kind withdrawal > /dev/null 2> "$T/render.err" ||
    bad "the round trip renders a withdrawal" "$(cat "$T/render.err")"
run "holding none rr" "$(koto context get "$WDR" coord/decision_message.txt)" "$COORD" "$OPEN_UP"
eq "round trip: decision-render.sh's withdrawal reads back as a withdrawal of that source" "0 withdrawal|coordinator rr #4 round 1" \
    "$RC $(list | jq -r '.[0] | "\(.kind)|\(.source)"')"
run "holding none rr" "$(withdrawal 4 1; printf 'Should the second half wait for the release?\n')" "$COORD" "$OPEN_UP"
eq "withdrawal: one with the sender's own question after it is unreadable, never the question dropped" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(withdrawal 4 1; printf '\n'; withdrawal 5 1)" "$COORD" "$OPEN_UP"
eq "withdrawal: two relayed together are unreadable, never the second lost" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(withdrawal 4 1 | sed 's/$/\r/')" "$COORD" "$OPEN_UP"
eq "withdrawal: one with CRLF line ends is unreadable" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(withdrawal 4 1 | sed '1s/round 1\./round 1.5 extra/')" "$COORD" "$OPEN_UP"
eq "withdrawal: a first line with more after it is unreadable, not read as round 1" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(withdrawal 4 1 | sed 's/No answer is needed\./Answer anyway./')" "$COORD" "$OPEN_UP"
eq "withdrawal: an altered closing sentence is unreadable" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(withdrawal 4 1)" "$COORD" \
    "[$(printf '%s' "$OPEN_UP" | jq -c '.[0] | .state = "settled" | .outcome = "wait; reason: r" | .decided_by = "a person" | .owed = "reply" | del(.verdict)')]"
eq "withdrawal: of a settled entry is an item too, which reopens it" "withdrawal|coordinator rr #4 round 1" \
    "$(list | jq -r '.[0] | "\(.kind)|\(.source)"')"
run "unknown -" "Should it ship?" ""
eq "a report that names no dispatch topic is unreadable" "0 unreadable" "$RC $(word)"
run "holding none rr" "$(escalation 4 1 "Merge $(printf '%420s' '' | tr ' ' x) before the release?")" "$COORD"
eq "a coordinator's escalation isn't held to the 400-character cap" "0 questions 1" "$RC $(printf '%s' "$OUT" | cut -d' ' -f1-2)"
run "holding none rr" "$(printf 'Answer: decision 4 round 1.\n\nOutcome: wait\n')" "$COORD" "$OPEN_UP"
eq "an Answer: first line is ordinary text" "0 none" "$RC $(word)"

# --- robustness ------------------------------------------------------------------------

# A context or problem line that starts like an option: the options are read
# upward from the answer line, so it is never taken for one.
printf 'Decision 4 round 1.\n\n1. The first half of the context reads like an option.\n\nThe problem.\n\nMerge before the release?\n1. wait (recommended: the release is Friday)\n   one upgrade carries both\n2. merge now\n   the format lands this week\n\nAnswer naming decision 4 round 1 and an option, or give another outcome with its reason.\n' > "$T/esc2"
printf 'Digest: %s\n' "$(sha < "$T/esc2")" >> "$T/esc2"
run "holding none rr" "$(cat "$T/esc2")" "$COORD"
eq "escalation: a context line starting with 1. isn't an option" "Merge before the release?|wait -- one upgrade carries both,merge now -- the format lands this week" \
    "$(list | jq -r '.[0] | "\(.text)|\(.options | join(","))"')"
escalation 4 1 | sed '$d' | sed 's/^Answer naming decision 4 round 1 /Answer naming decision 5 round 1 /' > "$T/esc3"
printf 'Digest: %s\n' "$(sha < "$T/esc3")" >> "$T/esc3"
run "holding none rr" "$(cat "$T/esc3")" "$COORD"
eq "escalation: one whose answer line names another entry is unreadable, though its digest holds" "0 unreadable" "$RC $(word)"

run "holding none w1" "$(printf 'Keep the cap at 400 (decision 3)?\nQuestions:\n1. Or 1000 (decision 3)\n')" "$WORKER" "[$ENTRY]"
eq "a citation outside the Questions part is dropped, inside it is kept" "null 3" "$(list | jq -r '[.[].cite | tostring] | join(" ")')"
# The brief's own example, the fixture render-brief_test.sh pins to the
# brief: the shape the brief teaches is the shape this reads.
run "holding none w1" "$(printf 'Done with the loader.\n\n%s\n' "$(cat "$HERE/testdata/decisions/brief-questions.txt")")" "$WORKER" "[$ENTRY]"
eq "the brief's Questions example reads as its two questions, the first citing decision 3" \
    "Should the loader pin v2.1.0 or track main? (decision 3):3|Is the flaky upload test in scope for this unit?:null" \
    "$(list | jq -r '[.[] | "\(.text):\(.cite | tostring)"] | join("|")')"
run "holding none w1" "$(printf 'Verdict: done.\n```\nlog line one\nShould it ship?\n')" "$WORKER"
eq "a fence that never closes hides nothing" "Should it ship?" "$(list | jq -r '[.[].text] | join("|")')"
VIA=leg run "holding none w1" 'leg result: status success; final state done; outcome blocked; step 3; reason Should the pin track v2.1.0 or main?; pull request ' "$WORKER"
eq "a leg result's reason is read on its own, so its question is found" "question|Should the pin track v2.1.0 or main?" "$(list | jq -r '[.[] | "\(.kind)|\(.text)"] | join(" ")')"
VIA=leg run "holding none w1" 'leg result: status success; final state done; outcome blocked; step 3; reason Keep the text; pull request here or split it?; pull request ' "$WORKER"
eq "a reason holding '; pull request ' is cut at the last one, the real field" "Keep the text; pull request here or split it?" "$(list | jq -r '.[0].text')"
VIA=leg run "holding none w1" 'leg result: status success; final state done; outcome ready; step ; reason ; pull request https://github.com/acme/widgets/pull/9' "$WORKER"
eq "a leg result with no reason gives none" "0 none" "$RC $(word)"
VIA=leg run "holding none w1" "$(for i in 1 2 3 4 5 6 7 8 9 10 11; do echo "Question $i?"; done)" "$WORKER"
eq "a leg report over the cap goes to the human, since its worker can't be rebriefed by message" "0 unreadable" "$RC $(word)"
run "holding none w1" "$(printf 'Is %s?' "$(printf '%396s' '' | tr ' ' x)")" "$WORKER"
eq "a question of exactly 400 characters is within the cap" "questions 1" "$(printf '%s' "$OUT" | cut -d' ' -f1-2)"
# 380 characters, 760 bytes: the cap counts characters.
run "holding none w1" "$(printf 'Is %s?' "$(printf '%378s' '' | sed 's/ /é/g')")" "$WORKER"
eq "the cap counts characters, not bytes" "questions 1" "$(printf '%s' "$OUT" | cut -d' ' -f1-2)"
VIA=leg run "holding none w1" "$(printf 'Is\t%s?' "$(printf '%420s' '' | tr ' ' x)")" "$WORKER"
eq "a question with a tab in it is measured whole, as a leg report over the cap shows" "0 unreadable" "$RC $(printf '%s' "$OUT" | cut -d' ' -f1)"
run "holding none rr" "$(escalation 4 1)" "$COORD" \
    '[{"decision":"2","round":"0","question":"Merge before the release?","options":"wait\nmerge now","state":"settled","source":"coordinator rr #4 round 1 [20260926T070000Z report 3.1]","outcome":"wait; reason: r","decided_by":"a person","updated":"2026-09-26T09:00Z"}]'
eq "escalation: a re-sent one whose entry has settled still opens nothing" "0 none" "$RC $(word)"

# Linear in the report: a long fenced log with a question after it.
{ echo 'Verdict: the build log is below.'; echo '```'
  i=0; while [ $i -lt 8000 ]; do echo "log line $i: please decide whether to ship?"; i=$((i + 1)); done
  echo '```'; echo 'Should the cache be cleared?'; } > "$T/big"
START=$SECONDS
run "holding none w1" "$(cat "$T/big")" "$WORKER"
ELAPSED=$((SECONDS - START))
eq "an 8000-line fenced log is skipped, the question after it kept" "Should the cache be cleared?" "$(list | jq -r '[.[].text] | join("|")')"
[ "$ELAPSED" -lt 15 ] && ok "an 8000-line report is read in ${ELAPSED}s, well inside koto's action timeout" ||
    bad "an 8000-line report is read inside koto's action timeout" "${ELAPSED}s"

tokens_ok report-questions
done_tests report-questions
