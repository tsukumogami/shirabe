#!/usr/bin/env bash
# decision-render_test.sh -- decision-render.sh against the gh and koto
# stand-ins: the four kinds' text, the escalation's shape and digest, every
# refusal, the seal on the stored text, and record-decision.sh's read modes
# the renderer reads through.
#
# Usage: bash skills/coordinate/scripts/decision-render_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/test-lib.sh"
R="$HERE/decision-render.sh"
RUNSTAMP=20260926T080000Z
db_init

# The entries every case starts from, as the codec parses them.
ESC='{"decision":"3","round":"1","question":"Ship the migration before the release?",
  "options":"ship now -- users get the new format this week\nwait for the release -- one upgrade carries both changes\nsplit it -- the reader ships now, the writer on Friday","state":"escalated","source":"self [20260926T080000Z raise 7]",
  "verdict":"escalate","recommendation":"wait for the release","reason":"the release is Friday and the migration rides it",
  "context":"The migration rewrites the lockfile format, and the release on Friday is the next time users upgrade.",
  "problem":"Shipping it now splits users across two formats for a week; waiting holds two other features behind it.",
  "grounds":"scope","target":"a person","owed":"escalation","updated":"2026-09-26T09:00Z"}'
SETTLED_W='{"decision":"4","round":"0","question":"Keep the shared clone?","options":"yes\nno","state":"settled",
  "source":"worker w1 [20260926T080000Z report 12.1]","verdict":"settle","owed":"reply",
  "outcome":"keep the shared clone; reason: the per-project installs held","decided_by":"coordinator","updated":"2026-09-26T09:00Z"}'
SETTLED_C='{"decision":"5","round":"0","question":"Merge before the release?","options":"merge now\nwait","state":"settled",
  "source":"coordinator roadmap-r #2 round 1 [20260926T080000Z report 14.1]","verdict":"settle","owed":"reply",
  "outcome":"wait; reason: the release is Friday","decided_by":"a person","updated":"2026-09-26T09:00Z"}'
WITHDRAW='{"decision":"6","round":"2","question":"Pin the plugin?","options":"pin\ndont pin","state":"coordinator-verdict",
  "source":"self [20260926T080000Z raise 9]","owed":"withdrawal",
  "evidence":"2026-09-26T09:30Z dispatcher [20260926T080000Z wait 20]: the release moved","updated":"2026-09-26T09:30Z"}'
ADDRESSED="2026-09-26T09:00Z worker w1 [20260926T080000Z report 12.1]: addressed to a person"
REDIRECT='{"decision":"7","round":"0","question":"Ship it?","options":"ship\nhold","state":"proposed",
  "source":"worker w1 [20260926T080000Z report 12.1]","updated":"2026-09-26T09:00Z",
  "evidence":"2026-09-26T09:00Z worker w1 [20260926T080000Z report 12.1]: addressed to a person"}'

N=0
# case_run <entries-json-array> <routed token> <state> <kind> [reports-to] [next]:
# a fresh record and session, decision_next's sealed capture, then the render.
# Sets S and OUT (stdout), and RC.
case_run() {
    N=$((N + 1))
    local ref=$((100 + N)) vars
    db '.issues = [] | .issues += [{repo: "acme/widgets", number: $k, title: "Coordinator record: ROADMAP-feat",
        body: $b, state: "open", author: "coord", editor: null}]' --argjson k "$ref" \
        --arg b "$(render "$(record_json roadmap feat | jq -c --argjson e "$1" --argjson n "${6:-10}" '.decisions = {next: $n, entries: $e}')" issue)"
    S="coordinate-roadmap-feat-c$N-$RUNSTAMP"
    vars=$(roadmap_vars feat | jq -c --arg r "${5-}" '.REPORTS_TO = $r')
    found_session "$S" "$vars" "$ref"
    log_to "$S" reconcile decision_next
    log_capture "$S" DECISION_NEXT "$(bash "$HERE/coord-log.sh" seal --session "$S" --state decision_next --token "$2")"
    log_to "$S" decision_next "$3"
    OUT=$(bash "$R" --session "$S" --state "$3" --kind "$4" 2>"$T/err")
    RC=$?
    seen "$OUT" >/dev/null
}
word() { printf '%s' "$OUT" | cut -d' ' -f1; }
msg() { koto context get "$S" coord/decision_message.txt; }
keyseal() { printf '%s' "$OUT" | tr ' ' '\n' | sed -n 's/^keyseal:/sealed:/p'; }

# --- the escalation -----------------------------------------------------------------

case_run "[$ESC]" "escalate 3" escalate escalation
eq "escalation: rendered" "0 message" "$RC $(word)"
eq "escalation: the verdict names the kind, entry and round" "message escalation 3 1" "$(printf '%s' "$OUT" | cut -d' ' -f1-4)"
BODY=$(msg | sed '$d')
cat > "$T/want" <<'EOF'
Decision 3 round 1.

The migration rewrites the lockfile format, and the release on Friday is the next time users upgrade.

Shipping it now splits users across two formats for a week; waiting holds two other features behind it.

Ship the migration before the release?
1. wait for the release (recommended: the release is Friday and the migration rides it)
   one upgrade carries both changes
2. ship now
   users get the new format this week
3. split it
   the reader ships now, the writer on Friday

Answer naming decision 3 round 1 and an option, or give another outcome with its reason.
EOF
eq "escalation: context, problem, the question with the recommendation first, every option explained, the answer line" "$(cat "$T/want")" "$BODY"
qform() { koto context get "$S" coord/decision_question.json; }
eq "escalation: the structured form, the recommended option first with every explanation" \
    'wait for the release:true:one upgrade carries both changes|ship now:false:users get the new format this week|split it:false:the reader ships now, the writer on Friday' \
    "$(qform | jq -r '[.options[] | "\(.label):\(.recommended):\(.explanation)"] | join("|")')"
eq "escalation: the structured form carries the question, context, problem and reason" \
    '3 1|Ship the migration before the release?|the release is Friday and the migration rides it' \
    "$(qform | jq -r '"\(.decision) \(.round)|\(.question)|\(.reason)"')"
[ "$(qform | jq -r .context)" = "The migration rewrites the lockfile format, and the release on Friday is the next time users upgrade." ] &&
    ok "escalation: the structured form's context is the entry's" || bad "escalation: the structured form's context is the entry's" "$(qform)"
eq "escalation: the structured form checks against its seal" "$(qform)" \
    "$(bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$(printf '%s' "$OUT" | tr ' ' '\n' | sed -n 's/^qseal:/sealed:/p')" --key coord/decision_question.json)"
msg | sed '$d' > "$T/above"
if command -v sha256sum >/dev/null 2>&1; then D=$(sha256sum < "$T/above" | cut -d' ' -f1); else D=$(shasum -a 256 < "$T/above" | cut -d' ' -f1); fi
eq "escalation: the last line is the digest of every byte above it" "Digest: $D" "$(msg | tail -1)"
eq "escalation: one decision in the message" 1 "$(msg | grep -c '^Decision ')"
eq "escalation: the stored text checks against the key's seal" "$(msg)" \
    "$(bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$(keyseal)" --key coord/decision_message.txt)"
printf 'Decision 3 round 1.\n\nsomething else\n' > "$T/edited"
koto context add "$S" coord/decision_message.txt --from-file "$T/edited"
bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$(keyseal)" --key coord/decision_message.txt >/dev/null 2>&1
eq "escalation: an edited text fails the key's seal" 1 "$?"
bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$OUT" >/dev/null 2>&1
eq "escalation: the verdict's own seal holds" 0 "$?"

refused() { # refused <name> <entry-json-array> <token> <state> <kind> [reports-to]
    case_run "$2" "$3" "$4" "$5" "${6-}"
    eq "$1" "0 refused" "$RC $(word)"
}
without() { printf '%s' "$ESC" | jq -c "$1"; }
refused "escalation: a blank recommendation is refused" "[$(without '.recommendation = " "')]" "escalate 3" escalate escalation
refused "escalation: a blank reason is refused" "[$(without '.reason = "  "')]" "escalate 3" escalate escalation
refused "escalation: a blank context is refused" "[$(without '.context = "  "')]" "escalate 3" escalate escalation
refused "escalation: a blank problem is refused" "[$(without '.problem = " "')]" "escalate 3" escalate escalation
refused "escalation: a recommendation outside the options is refused" "[$(without '.recommendation = "ship later"')]" "escalate 3" escalate escalation
refused "escalation: an option without its explanation is refused" \
    "[$(without '.options = "ship now\nwait for the release -- one upgrade carries both changes"')]" "escalate 3" escalate escalation
refused "escalation: a target other than the run's is refused" "[$ESC]" "escalate 3" escalate escalation ws
refused "escalation: an entry that owes no escalation is refused" "[$(without '.owed = ""')]" "escalate 3" escalate escalation
refused "escalation: a second rendering after the owing cleared is refused" "[$(without '.owed = "" | .asked = "2026-09-26T09:05Z"')]" "escalate 3" escalate escalation
refused "escalation: a routed word that isn't escalate is refused" "[$ESC]" "reply 3" escalate escalation
refused "escalation: an entry the record doesn't hold is refused" "[$ESC]" "escalate 9" escalate escalation
case_run "[$(without '.target = "coordinator ws"')]" "escalate 3" escalate escalation ws
eq "escalation: to a coordinator, when the run reports to it" "0 message" "$RC $(word)"

# --- withdrawal, reply, redirect ----------------------------------------------------

case_run "[$WITHDRAW]" "withdraw 6" decision_withdraw withdrawal
eq "withdrawal: rendered" "message withdrawal 6 2" "$(printf '%s' "$OUT" | cut -d' ' -f1-4)"
eq "withdrawal: names the decision and round" "Withdrawn: decision 6 round 2." "$(msg | head -1)"
case "$(msg)" in *"No answer is needed."*) ok "withdrawal: says no answer is needed" ;; *) bad "withdrawal: says no answer is needed" "$(msg)" ;; esac
refused "withdrawal: an entry that owes none is refused" "[$(printf '%s' "$WITHDRAW" | jq -c '.owed = ""')]" "withdraw 6" decision_withdraw withdrawal

case_run "[$SETTLED_W]" "reply 4" decision_reply reply
cat > "$T/want" <<'EOF'
Answer: decision 4 round 0.

Keep the shared clone?

Outcome: keep the shared clone
Reason: the per-project installs held
Decided by: coordinator
EOF
eq "reply to a worker: the decision, round, outcome, reason and who decided" "$(cat "$T/want")" "$(msg)"
case_run "[$SETTLED_C]" "reply 5" decision_reply reply
eq "reply to a coordinator: names the source's entry and round" "Answer: decision 2 round 1." "$(msg | head -1)"
refused "reply: an outcome without its reason is refused" "[$(printf '%s' "$SETTLED_W" | jq -c '.outcome = "keep it"')]" "reply 4" decision_reply reply
refused "reply: an entry that owes none is refused" "[$(printf '%s' "$SETTLED_W" | jq -c '.owed = ""')]" "reply 4" decision_reply reply

case_run "[$REDIRECT]" "redirect 7 12" decision_redirect redirect
eq "redirect: rendered, naming its report" "message redirect 7 0 report:12" "$(printf '%s' "$OUT" | cut -d' ' -f1-5)"
case "$(msg)" in *"go to the coordinator"*"answers each one"*"escalates it with a recommendation"*"decision 7"*)
        ok "redirect: the questions go to the coordinator, which answers or escalates them, starting with decision 7" ;;
    *) bad "redirect: the questions go to the coordinator, which answers or escalates them, starting with decision 7" "$(msg)" ;; esac
refused "redirect: a report that has had its redirect is refused" \
    "[$(printf '%s' "$REDIRECT" | jq -c --arg a "$ADDRESSED" '.evidence = $a + "\n2026-09-26T09:05Z this coordinator [20260926T080000Z redirect 12]: redirect sent"')]" \
    "redirect 7 12" decision_redirect redirect
refused "redirect: an entry no report of this run wrote is refused" \
    "[$(printf '%s' "$REDIRECT" | jq -c '.source = "worker w1 [20260925T080000Z report 12.1]" | .evidence = ""')]" "redirect 7 12" decision_redirect redirect
refused "redirect: a report that addressed no one is refused" \
    "[$(printf '%s' "$REDIRECT" | jq -c '.evidence = ""')]" "redirect 7 12" decision_redirect redirect
refused "redirect: another report's addressed mark doesn't count" \
    "[$(printf '%s' "$REDIRECT" | jq -c '.evidence = "2026-09-26T09:00Z worker w1 [20260926T080000Z report 15.1]: addressed to a person"')]" \
    "redirect 7 12" decision_redirect redirect
refused "redirect: a routed redirect naming no report is refused" "[$REDIRECT]" "redirect 7" decision_redirect redirect
case_run "[$(printf '%s' "$REDIRECT" | jq -c '.source = "worker w1 [20260926T080000Z report 12.1]"'),
  $(printf '%s' "$REDIRECT" | jq -c '.decision = "8" | .source = "worker w1 [20260926T080000Z report 12.2]" | .evidence = "2026-09-26T09:00Z worker w1 [20260926T080000Z report 12.2]: addressed to a person"')]" \
    "redirect 7 12" decision_redirect redirect 2>/dev/null
eq "redirect: the addressed mark may be on another entry of the same report" "message redirect 7 0" "$(printf '%s' "$OUT" | cut -d' ' -f1-4)"
case_run "[$(printf '%s' "$REDIRECT" | jq -c --arg a "$ADDRESSED" '.evidence = $a + "\n2026-09-26T09:05Z dispatcher [20260926T080000Z wait 13]: quoting [20260926T080000Z redirect 12] in text"')]" \
    "redirect 7 12" decision_redirect redirect
eq "redirect: a stamp inside a line's text isn't a stamp" "message redirect 7 0" "$(printf '%s' "$OUT" | cut -d' ' -f1-4)"

# --- @ is encoded ---------------------------------------------------------------------

case_run "[$(without '.context = "Ask @alice before the release."')]" "escalate 3" escalate escalation
case "$(msg)" in *"@alice"*) bad "a mention is encoded in the message" "$(msg)" ;; *"&#64;alice"*) ok "a mention is encoded in the message" ;;
    *) bad "a mention is encoded in the message" "$(msg)" ;; esac

# --- record-decision.sh's read modes ---------------------------------------------------

case_run "[$ESC, $SETTLED_W]" "escalate 3" escalate escalation
eq "read: --list prints the section" '10 3,4' \
    "$(bash "$HERE/record-decision.sh" --session "$S" --list | jq -r '"\(.next) \([.entries[].decision] | join(","))"')"
eq "read: --read prints one entry" escalated "$(bash "$HERE/record-decision.sh" --session "$S" --read 3 | jq -r .state)"
bash "$HERE/record-decision.sh" --session "$S" --read 8 >/dev/null 2>&1
eq "read: --read of an entry the record doesn't hold exits 1" 1 "$?"
db '.issues[0].body = "not a record"'
bash "$HERE/record-decision.sh" --session "$S" --list >/dev/null 2>&1
eq "read: a record that isn't canonical is refused with 10" 10 "$?"
db '.fail += [{match: "issue view", rc: 1, stderr: "gh: server error"}]'
bash "$HERE/record-decision.sh" --session "$S" --list >/dev/null 2>&1
eq "read: a failed read exits 2" 2 "$?"
db '.fail = []'
db '.issues[0].body = $b' --arg b "$(render "$(record_json roadmap feat)" issue)"
eq "read: a record with no section lists none" '{"next":1,"entries":[]}' "$(bash "$HERE/record-decision.sh" --session "$S" --list)"
bash "$HERE/record-decision.sh" --session "$S" --read x >/dev/null 2>&1
eq "read: an entry that isn't a number is usage" 64 "$?"

tokens_ok decision-render
done_tests decision-render
