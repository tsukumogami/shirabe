#!/usr/bin/env bash
# decision-render_test.sh -- decision-render.sh against the gh and koto
# stand-ins: the four kinds' text, the escalation as shirabe question render
# gives it (its first prompt byte for byte, four at most, in pending's order,
# refused with no attempt behind it, no field laid out here), every
# refusal, the seal on the stored text, and state-decision.sh's read modes
# the renderer reads through, over the record in the run's session.
#
# Usage: bash skills/coordinate/scripts/decision-render_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
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
    local vars
    S="coordinate-roadmap-feat-c$N-$RUNSTAMP"
    vars=$(roadmap_vars feat | jq -c --arg r "${5-}" '.REPORTS_TO = $r')
    found_session "$S" "$vars"
    seed_session "$S" "$(record_json roadmap feat | jq -c --argjson e "$1" --argjson n "${6:-10}" '.decisions = {next: $n, entries: $e}')"
    [ -z "${PRE:-}" ] || "$PRE" # koto's and shirabe's fixtures for this session
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
# An escalation is held by question identities, and shirabe question render
# alone presents them (the stand-in in testdata/question-stand-in, whose
# prompts carry none of the question's content). The content koto holds is
# marked, so any field this script laid out itself would show in the message.
PATH="$HERE/testdata/question-stand-in:$PATH"
QA=0a1b2c3d-0000-4000-8000-00000000000a/000000000002
QB=0a1b2c3d-0000-4000-8000-00000000000b/000000000003
QC=0a1b2c3d-0000-4000-8000-00000000000c/000000000004
QD=0a1b2c3d-0000-4000-8000-00000000000d/000000000005
QE=0a1b2c3d-0000-4000-8000-00000000000e/000000000006
CONTENT='{"context":"CTX-MARK","problem":"PROB-MARK","ask":"ASK-MARK?","question":"CTX-MARK\n\nPROB-MARK\n\nASK-MARK?","options":[{"label":"LABEL-MARK","reason":"REASON-MARK"}],"ground":"GROUND-MARK","waiting":["issue-12"],"label":"cache"}'
MARKS="CTX-MARK PROB-MARK ASK-MARK REASON-MARK GROUND-MARK LABEL-MARK"
qkey() { printf '%s' "$1" | tr '/' '_'; }
KD() { mkdir -p "$KOTO_STORE/decisions/$1"; printf '%s' "$KOTO_STORE/decisions/$1"; }
# PRE_IDS: the questions koto holds open for the next case_run, each with its
# content and, unless NO_ATTEMPT is set, an undecided attempt of the session's
# (ATTEMPT_RESULT another result); PENDING: shirabe question pending's list.
PRE_IDS= NO_ATTEMPT= ATTEMPT_RESULT= PENDING=
pre() {
    local q at='[]'
    rm -rf "$KOTO_STORE/decisions" "$KOTO_STORE/shirabe-calls"
    for q in $PRE_IDS; do
        jq -nc --arg q "$q" '{identity: $q, open: true, raiser: {name: "w1"}, question: {need: "decision"}, entries: [], answer: null}' \
            > "$(KD history)/$(qkey "$q").json"
        printf '%s' "$CONTENT" > "$(KD content)/$(qkey "$q").json"
        [ -n "$NO_ATTEMPT" ] || at=$(printf '%s' "$at" | jq -c --arg q "$q" --arg r "${ATTEMPT_RESULT:-undecided}" '. + [{id: "000000000005", result: $r, status: "in-effect", questions: [$q]}]')
    done
    printf '{"attempts":%s,"in":"%s","unreadable":[],"v":1}' "$at" "$S" > "$(KD attempts)/$S.json"
    [ -z "$PENDING" ] || printf '%s' "$PENDING" > "$(KD pending)/$S.json"
}
PRE=pre
# HELD <n> <identity> [jq]: an escalated entry held by the question, owing its escalation
HELD() {
    printf '%s' "$ESC" | jq -c --arg n "$1" --arg q "$2" '.decision = $n | .options = "" | .grounds = "changes-scope"
        | .source = "question \($q) [20260926T080000Z report 7.\($n)]" | del(.recommendation, .context, .problem)'"${3:+ | $3}"
}
qform() { koto context get "$S" coord/decision_question.json; }
calls() { grep -h "^question $1 " "$KOTO_STORE/shirabe-calls" 2>/dev/null; }

PRE_IDS=$QA
case_run "[$(HELD 3 "$QA")]" "escalate 3" escalate escalation
eq "escalation: rendered" "0 message" "$RC $(word)"
eq "escalation: the verdict names the kind, entry and round" "message escalation 3 1" "$(printf '%s' "$OUT" | cut -d' ' -f1-4)"
eq "escalation: the verdict lists the entries the prompt carries" "entries:3@1" "$(printf '%s' "$OUT" | tr ' ' '\n' | grep '^entries:')"
eq "escalation: shirabe question render is asked for the question, in the run's session" "question render $QA --in $S" "$(calls render)"
RAW=$(shirabe question render "$QA" --in "$S")
case "$RAW" in *"\"prompts\":[$(qform)]"*) ok "escalation: coord/decision_question.json is byte for byte the render's first prompt" ;;
    *) bad "escalation: coord/decision_question.json is byte for byte the render's first prompt" "$(qform)" ;; esac
eq "escalation: the message is that prompt's text" "$(qform | jq -j .text)" "$(msg)"
LAID=
for m in $MARKS; do case "$(msg)$(qform)" in *"$m"*) LAID="$LAID $m" ;; esac; done
eq "escalation: no field of the question is laid out by the renderer" "" "$LAID"
case "$(msg)" in *"Digest:"*|*"Decision 3 round 1."*) bad "escalation: no text of the renderer's own around the prompt" "$(msg)" ;;
    *) ok "escalation: no text of the renderer's own around the prompt" ;; esac
eq "escalation: the prompt input checks against its seal" "$(qform)" \
    "$(bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$(printf '%s' "$OUT" | tr ' ' '\n' | sed -n 's/^qseal:/sealed:/p')" --key coord/decision_question.json)"
eq "escalation: the stored text checks against the key's seal" "$(msg)" \
    "$(bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$(keyseal)" --key coord/decision_message.txt)"
printf 'Decision 3 round 1.\n\nsomething else\n' > "$T/edited"
koto context add "$S" coord/decision_message.txt --from-file "$T/edited"
bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$(keyseal)" --key coord/decision_message.txt >/dev/null 2>&1
eq "escalation: an edited text fails the key's seal" 1 "$?"
bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$OUT" >/dev/null 2>&1
eq "escalation: the verdict's own seal holds" 0 "$?"

# Never more than four, in shirabe question pending's order.
PRE_IDS="$QA $QB $QC $QD $QE"
PENDING="{\"questions\":[{\"identity\":\"$QD\",\"waiting\":5},{\"identity\":\"$QB\",\"waiting\":2}],\"v\":1}"
case_run "[$(HELD 3 "$QA"), $(HELD 4 "$QB"), $(HELD 5 "$QC"), $(HELD 6 "$QD"), $(HELD 7 "$QE")]" "escalate 5" escalate escalation
eq "escalation: the routed entry and the next lowest, four at most" "entries:5@1.3@1.4@1.6@1" "$(printf '%s' "$OUT" | tr ' ' '\n' | grep '^entries:')"
eq "escalation: rendered in pending's order, the unlisted after by identity" "question render $QD $QB $QA $QC --in $S" "$(calls render)"
PENDING=

refused() { # refused <name> <entry-json-array> <token> <state> <kind> [reports-to]
    case_run "$2" "$3" "$4" "$5" "${6-}"
    eq "$1" "0 refused" "$RC $(word)"
}
without() { printf '%s' "$ESC" | jq -c "$1"; }
PRE_IDS=$QA NO_ATTEMPT=1
refused "escalation: an owner-escalated entry with no attempt of the session's behind it is refused" "[$(HELD 3 "$QA")]" "escalate 3" escalate escalation
koto context exists "$S" coord/decision_question.json; eq "  ... and no prompt input is written" 1 "$?"
eq "  ... nor is render asked" "" "$(calls render)"
NO_ATTEMPT= ATTEMPT_RESULT=decided
refused "escalation: a decided attempt doesn't count" "[$(HELD 3 "$QA")]" "escalate 3" escalate escalation
ATTEMPT_RESULT=
pre_closed() { pre; : > "$KOTO_STORE/decisions/render-closed"; }
PRE=pre_closed
refused "escalation: a question render finds closed is refused" "[$(HELD 3 "$QA")]" "escalate 3" escalate escalation
PRE=pre
refused "escalation: a ground that isn't pass-up's is refused" "[$(HELD 3 "$QA" '.grounds = "scope"')]" "escalate 3" escalate escalation
refused "escalation: a target other than the run's is refused" "[$(HELD 3 "$QA")]" "escalate 3" escalate escalation ws
refused "escalation: an entry that owes no escalation is refused" "[$(HELD 3 "$QA" '.owed = ""')]" "escalate 3" escalate escalation
refused "escalation: a second rendering after the owing cleared is refused" "[$(HELD 3 "$QA" '.owed = "" | .asked = "2026-09-26T09:05Z"')]" "escalate 3" escalate escalation
refused "escalation: a routed word that isn't escalate is refused" "[$(HELD 3 "$QA")]" "reply 3" escalate escalation
refused "escalation: an entry the record doesn't hold is refused" "[$(HELD 3 "$QA")]" "escalate 9" escalate escalation
PRE_IDS="$QA $QB"
case_run "[$(HELD 3 "$QA" '.target = "coordinator ws"'), $(HELD 4 "$QB" '.target = "coordinator ws"')]" "escalate 3" escalate escalation ws
eq "escalation: to a coordinator, when the run reports to it" "0 message" "$RC $(word)"
eq "escalation: to a coordinator, the message names each identity and nothing else" "$(printf 'Passed up to you in koto, by identity:\n\n%s\n%s' "$QA" "$QB")" "$(msg)"
eq "  ... with no prompt and no render" "|" "$(koto context exists "$S" coord/decision_question.json && echo prompt)|$(calls render)"
PRE_IDS=

# An old-style escalation: an entry held by no question identity, escalated in
# a run already under way when entries came to be held by identities, is
# rendered alone and as it was before (the base's fixture and expectations),
# with no shirabe call.
PRE_IDS=$QA NO_ATTEMPT=1
case_run "[$ESC, $(HELD 4 "$QA")]" "escalate 3" escalate escalation
eq "old-style escalation: rendered" "0 message" "$RC $(word)"
eq "old-style escalation: the verdict names the kind, entry and round, and lists no entries" "message escalation 3 1|" \
    "$(printf '%s' "$OUT" | cut -d' ' -f1-4)|$(printf '%s' "$OUT" | tr ' ' '\n' | grep '^entries:')"
cat > "$T/want" <<'WANT'
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
WANT
eq "old-style escalation: context, problem, the question with the recommendation first, every option explained, the answer line" "$(cat "$T/want")" "$(msg | sed '$d')"
msg | sed '$d' > "$T/above"
if command -v sha256sum >/dev/null 2>&1; then D=$(sha256sum < "$T/above" | cut -d' ' -f1); else D=$(shasum -a 256 < "$T/above" | cut -d' ' -f1); fi
eq "old-style escalation: the last line is the digest of every byte above it" "Digest: $D" "$(msg | tail -1)"
eq "old-style escalation: one decision in the message" 1 "$(msg | grep -c '^Decision ')"
eq "old-style escalation: the structured form, the recommended option first with every explanation" \
    'wait for the release:true:one upgrade carries both changes|ship now:false:users get the new format this week|split it:false:the reader ships now, the writer on Friday' \
    "$(qform | jq -r '[.options[] | "\(.label):\(.recommended):\(.explanation)"] | join("|")')"
eq "old-style escalation: the structured form checks against its seal" "$(qform)" \
    "$(bash "$HERE/coord-log.sh" check --session "$S" --state escalate --sealed "$(printf '%s' "$OUT" | tr ' ' '\n' | sed -n 's/^qseal:/sealed:/p')" --key coord/decision_question.json)"
eq "old-style escalation: no shirabe call" "" "$(cat "$KOTO_STORE/shirabe-calls" 2>/dev/null)"
NO_ATTEMPT=
PRE_IDS=
refused "old-style escalation: a blank context is refused, as before" "[$(without '.context = "  "')]" "escalate 3" escalate escalation
refused "old-style escalation: a recommendation outside the options is refused, as before" "[$(without '.recommendation = "ship later"')]" "escalate 3" escalate escalation
refused "old-style escalation: an option without its explanation is refused, as before" \
    "[$(without '.options = "ship now\nwait for the release -- one upgrade carries both changes"')]" "escalate 3" escalate escalation
refused "old-style escalation: a target other than the run's is refused, as before" "[$ESC]" "escalate 3" escalate escalation ws

# A coordinator restarted in a new session holds no attempt for a question its
# predecessor attempted: the refusal names the line that records one here.
PRE_IDS=$QA NO_ATTEMPT=1
refused "escalation: with no attempt in this session, refused" "[$(HELD 3 "$QA")]" "escalate 3" escalate escalation
grep -qF "shirabe question attempt --in $S --what '<the question>' --result undecided --basis ${QA%/*}:${QA##*/}" "$T/err" \
    && ok "  ... naming the shirabe question attempt line for this session" || bad "  ... naming the shirabe question attempt line for this session" "$(cat "$T/err")"
NO_ATTEMPT=
# shirabe is SHIRABE_BIN when it is set, as state-handover.sh calls it.
printf '#!/usr/bin/env bash\nprintf "via SHIRABE_BIN\\n" >> "$KOTO_STORE/shirabe-bin-calls"\nexec "%s/testdata/question-stand-in/shirabe" "$@"\n' "$HERE" > "$T/shirabe-bin"
chmod +x "$T/shirabe-bin"
rm -f "$KOTO_STORE/shirabe-bin-calls"
SHIRABE_BIN="$T/shirabe-bin" case_run "[$(HELD 3 "$QA")]" "escalate 3" escalate escalation
eq "escalation: shirabe is called as SHIRABE_BIN when it is set (pending and render)" "0 message|2" "$RC $(word)|$(wc -l < "$KOTO_STORE/shirabe-bin-calls" | tr -d ' ')"
PRE_IDS=


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
refused "redirect: a report whose redirect is recorded on another of its entries is refused" \
    "[$REDIRECT, $(printf '%s' "$REDIRECT" | jq -c '.decision = "8" | .source = "worker w1 [20260926T080000Z report 12.2]" | .evidence = "2026-09-26T09:05Z this coordinator [20260926T080000Z redirect 12]: redirect sent"')]" \
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

case_run "[$(printf '%s' "$WITHDRAW" | jq -c '.question = "Ask @alice before the release?"')]" "withdraw 6" decision_withdraw withdrawal
case "$(msg)" in *"@alice"*) bad "a mention is encoded in the message" "$(msg)" ;; *"&#64;alice"*) ok "a mention is encoded in the message" ;;
    *) bad "a mention is encoded in the message" "$(msg)" ;; esac

# --- state-decision.sh's read modes ---------------------------------------------------

PRE_IDS=$QA
case_run "[$(HELD 3 "$QA"), $SETTLED_W]" "escalate 3" escalate escalation
eq "read: --read of an entry held by a question carries koto's content as it holds it" "$(printf '%s' "$CONTENT" | jq -cS .)" \
    "$(bash "$HERE/state-decision.sh" --session "$S" --read 3 | jq -cS .content)"
eq "read: --read of an entry with no identity carries no content" null "$(bash "$HERE/state-decision.sh" --session "$S" --read 4 | jq -c .content)"
eq "read: --list prints the section" '10 3,4' \
    "$(bash "$HERE/state-decision.sh" --session "$S" --list | jq -r '"\(.next) \([.entries[].decision] | join(","))"')"
eq "read: --read prints one entry" escalated "$(bash "$HERE/state-decision.sh" --session "$S" --read 3 | jq -r .state)"
bash "$HERE/state-decision.sh" --session "$S" --read 8 >/dev/null 2>&1
eq "read: --read of an entry the record doesn't hold exits 1" 1 "$?"
# --list and --read read the Decisions section alone (shirabe#1315): a section
# they don't read isn't theirs to judge, and one they read that isn't
# canonical is refused.
koto context get "$S" record/decisions > "$T/decisions.kept"
printf '"not a record"' | koto context add "$S" record/holdings
eq "read: a section --list doesn't read isn't judged" '10 3,4' \
    "$(bash "$HERE/state-decision.sh" --session "$S" --list | jq -r '"\(.next) \([.entries[].decision] | join(","))"')"
printf '"not a record"' | koto context add "$S" record/decisions
bash "$HERE/state-decision.sh" --session "$S" --list >/dev/null 2>&1
eq "read: a record that isn't canonical is refused with 10" 10 "$?"
koto context add "$S" record/decisions --from-file "$T/decisions.kept"
# --list gets Decisions directly (shirabe#1315), so the failure is that get's.
mkdir -p "$T/kfail"
cat > "$T/kfail/koto" <<EOF
#!/usr/bin/env bash
if [ "\${1:-} \${2:-} \${4:-}" = "context get record/decisions" ]; then
    echo "koto stub: read failed" >&2
    exit 1
fi
exec "$HERE/testdata/koto" "\$@"
EOF
chmod +x "$T/kfail/koto"
PATH="$T/kfail:$PATH" bash "$HERE/state-decision.sh" --session "$S" --list >/dev/null 2>&1
eq "read: a failed read exits 2" 2 "$?"
seed_session "$S" "$(record_json roadmap feat)"
eq "read: a record with no section lists none" '{"next":1,"entries":[]}' "$(bash "$HERE/state-decision.sh" --session "$S" --list)"
bash "$HERE/state-decision.sh" --session "$S" --read x >/dev/null 2>&1
eq "read: an entry that isn't a number is usage" 64 "$?"

echo "== render: the koto calls don't grow with the entries (shirabe#1315) =="
# The render gets the Decisions section directly and never lists record/,
# which names every entry: the same render on a record with a few entries and
# with 300 makes the same koto calls.
# filler <session> <count>: plain entries numbered from 1.
filler() {
    local d="$KOTO_STORE/context/$1/record/entries" i
    mkdir -p "$d"
    for ((i = 1; i <= $2; i++)); do
        printf '{"n":%d,"stamp":"2026-09-26T08:00:00Z","kind":"entry","text":"note %d"}' "$i" "$i" > "$d/$(printf '%06d' "$i")"
    done
}
# koto_calls <entries> <entries-json-array> <token> <state> <kind>: case_run's
# run with <entries> entries in the record, then the render's verdict words
# (its seals left out: they name the session) and its koto calls, the calls
# kept in $T/kc.calls.
koto_calls() {
    local n=$1; shift
    N=$((N + 1))
    S="coordinate-roadmap-feat-c$N-$RUNSTAMP"
    found_session "$S" "$(roadmap_vars feat | jq -c '.REPORTS_TO = ""')"
    seed_session "$S" "$(record_json roadmap feat | jq -c --argjson e "$1" '.decisions = {next: 10, entries: $e}')"
    [ -z "${PRE:-}" ] || "$PRE"
    log_to "$S" reconcile decision_next
    log_capture "$S" DECISION_NEXT "$(bash "$HERE/coord-log.sh" seal --session "$S" --state decision_next --token "$2")"
    log_to "$S" decision_next "$3"
    filler "$S" "$n"
    : > "$KOTO_STORE/calls"
    OUT=$(bash "$R" --session "$S" --state "$3" --kind "$4" 2>"$T/err")
    printf '%s %s' "$(printf '%s' "$OUT" | tr ' ' '\n' | grep -vE '^[a-z]*seal:' | tr '\n' ' ' | sed 's/ $//')" "$(wc -l < "$KOTO_STORE/calls" | tr -d ' ')"
    cp "$KOTO_STORE/calls" "$T/kc.calls"
}
ESC_HELD=$(HELD 3 "$QA"); PRE_IDS=$QA
for kind in escalation:escalate:escalate:ESC_HELD withdrawal:withdraw:decision_withdraw:WITHDRAW \
    reply:reply:decision_reply:SETTLED_W redirect:redirect:decision_redirect:REDIRECT; do
    IFS=: read -r k w st v <<< "$kind"
    case "$k" in escalation) tok="$w 3" ;; withdrawal) tok="$w 6" ;; reply) tok="$w 4" ;; redirect) tok="$w 7 12" ;; esac
    FEW=$(koto_calls 3 "[${!v}]" "$tok" "$st" "$k")
    MANY=$(koto_calls 300 "[${!v}]" "$tok" "$st" "$k")
    case "${FEW##* }" in ''|*[!0-9]*) bad "$k: the render runs" "$FEW"; continue ;; esac
    eq "$k: the same verdict and koto calls with 3 entries and with 300 (${FEW##* } calls)" "$FEW" "$MANY"
    eq "  ... rendered" "message $k" "$(printf '%s' "$FEW" | cut -d' ' -f1-2)"
    eq "  ... never listing record/" 0 "$(grep -cE '^context list (.* )?--prefix record/( |$)' "$T/kc.calls")"
done

tokens_ok decision-render
done_tests decision-render
