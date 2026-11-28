#!/usr/bin/env bash
# coordinate-question-leg_engine_test.sh -- a leg-bound worker's question
# brought into the coordinator's record, end to end: the shipped coordinate.md
# driven through real koto from a session coordinate-open.sh opens, the
# worker a stand-in session bound to its request leg, its question raised in
# koto with the branch's shirabe. The setup and helpers are the coordinate
# engine suites' (testdata/coordinate-engine-lib.sh).
#
# Proves, in one run:
#   1. the worker raises a question addressed to the coordinator's session
#      and stops at its waiting terminal, its promoted result naming the
#      question; the `leg` tick offers the leg once, with disposition
#      `question`, and the report reaches report_questions, which routes to
#      decision_open; the entry opens by identity (Source `question <id>`);
#   2. taken and held (Verdict hold), the report is classified needs_fix, and
#      at rebrief dispatch-worker.sh --rebrief exits 9 with nothing written,
#      so `sent: refused` takes the run back to wait; the leg is in
#      question_legs and never in taken_legs, and the handover read lists the
#      question with its entry, handled;
#   3. the next `leg` tick finds the leg waiting and goes back to wait,
#      wait_target naming it under `waiting` and nothing under `unentered`;
#   4. the coordinator answers as the addressee (shirabe question settle);
#      the next `leg` tick offers the leg with disposition `answered`, the
#      report is classified needs_fix, and --rebrief runs the unit again on a
#      new leg whose brief names the answered question;
#   5. the re-briefed worker, bound to the new leg, finishes with its pull
#      request, and the `leg` tick takes that result to report_link: the unit
#      finishes on its new leg.
#
# Needs koto, jq and git, and shirabe with the question ladder (SHIRABE_BIN,
# as testdata/engine-questions.sh finds it); SKIPs (exit 0) without koto,
# which run-tests.sh --engine turns into a failure, and fails without
# shirabe.
# Usage: bash skills/coordinate/scripts/coordinate-question-leg_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"

finish() {
    echo
    echo "coordinate-question-leg: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]
    exit
}
q_have || { bad "shirabe with the question ladder is at hand" "$(cat "$T/q.err" 2>&1)"; finish; }

# niwa: no session listed, so a re-brief prints no session= line.
mkdir -p "$T/niwa-bin"
cat > "$T/niwa-bin/niwa" <<'EOF'
#!/usr/bin/env bash
case "$1 ${2-}" in
    "list --json") echo '[]' ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$T/niwa-bin/niwa"
export NIWA="$T/niwa-bin/niwa"

# The waiting worker: it records the question it raised and stops at its
# waiting terminal, whose promoted result names it, as /deliver's does.
mkdir -p "$T/tplw" "$T/tpl"
cat > "$T/tplw/deliver.md" <<'EOF'
---
name: deliver
version: "1.0"
description: a stand-in waiting worker for coordinate-question-leg_engine_test.sh
initial_state: work
states:
  work:
    accepts:
      finish:
        type: enum
        values: [wait]
        required: true
      question:
        type: string
        required: true
    transitions:
      - target: done_waiting
        when:
          finish: wait
        context_assignments:
          question: "${evidence.question}"
  done_waiting:
    terminal: true
    result:
      outcome: waiting
      question: "${context.question}"
---
## work
Stand-in.
## done_waiting
Waiting on a question.
EOF
# The re-briefed worker: it finishes with its pull request.
cat > "$T/tpl/deliver.md" <<'EOF'
---
name: deliver
version: "1.0"
description: a stand-in worker for coordinate-question-leg_engine_test.sh
initial_state: work
variables:
  TOPIC:
    required: true
states:
  work:
    accepts:
      finish:
        type: enum
        values: [go]
        required: true
    transitions:
      - target: done
        when:
          finish: go
  done:
    terminal: true
    result:
      outcome: ready
      pr: https://github.com/acme/widgets/pull/12
---
## work
Stand-in.
## done
Done.
EOF

ctx() { (cd "$WD" && koto context get "$S" "$1" 2>>"$T/ctx.err"); }
target() { ctx wait_target | jq -r "$1"; }
# rebrief_as_agent: the rebrief directive, as the agent runs it: the brief
# input in context, then dispatch-worker.sh --rebrief. RB_RC is its exit.
rebrief_as_agent() {
    brief feat-1 "Feature 1" deliver feat-1 executing > "$T/brief.json"
    (cd "$WD" && koto context add "$S" brief_input.json --from-file "$T/brief.json" > /dev/null)
    : > "$WD/.niwa/workspace.toml"
    (cd "$WD" && bash "$PS/dispatch-worker.sh" --session "$S" --rebrief > "$T/rb.out" 2> "$T/rb.err"); RB_RC=$?
    rm -f "$WD/.niwa/workspace.toml"
}

echo "== 1. the worker's question opens an entry by its identity =="
REQ=$(cd "$T/work" && koto request create --role deliver --template deliver.md --inputs '{}' \
    --requested-by coord --coordinator-of-record coordinate-feat-1 | jq -r .request_id)
if [ -z "$REQ" ] || ! empty_run qleg "leg $REQ:deliver"; then
    bad "1: reach wait with a leg-bound holding" "$(cat "$T/open.err" "$T/tick.err" 2>&1)"
    finish
fi
(cd "$T" && koto init deliver-feat-1 --template "$T/tplw/deliver.md" --koto-leg "$REQ:deliver" > /dev/null 2> "$T/child.err") \
    || bad "1: the worker's session binds to its leg" "$(cat "$T/child.err")"
q_raise "$T" deliver-feat-1 "session:$S" "Pin the loader to v2?" loader-pin \
    "pin -- one upgrade path" "float -- nothing to keep pinned" \
    || bad "1: the worker raises its question to the coordinator" "$(cat "$T/q.err")"
eq "1: koto lists it open at the coordinator" "$QI" \
    "$( (cd "$WD" && koto decisions open --at "$S") | jq -r '[.questions[] | select(.addressee.name == "'"$S"'") | .identity] | join(" ")')"
(cd "$T" && koto next deliver-feat-1 --with-data "$(jq -nc --arg q "$QI" '{finish: "wait", question: $q}')" > /dev/null 2> "$T/child.err") \
    || bad "1: the worker stops at its waiting terminal" "$(cat "$T/child.err")"
eq "1: the leg tick takes the waiting result for its question, to decision_open" decision_open "$(at --with-data '{"event":"leg"}')"
eq "  ... offered with disposition question, naming it" "question $QI" "$(target '"\(.disposition) \(.question)"')"
eq "  ... listed unentered until its entry exists" "$QI" "$(target '[.unentered[].identity] | join(" ")')"
echo '{}' > "$T/words.json"
write_as_agent state-decision.sh --open-from-report --text-file "$T/words.json"
eq "1: state-decision.sh opens the entry with no wording of its own" 0 $?
case "$(live_body | jq -r '.decisions.entries[-1].source // ""')" in
    "question $QI "*) ok "  ... held by the question's identity" ;;
    *) bad "  ... held by the question's identity" "$(live_body | jq -c '.decisions')" ;;
esac
N=$(live_body | jq -r '.decisions.entries[-1].decision')

echo "== 2. held, the re-brief is refused while the question is open =="
eq "2: the opened entry is taken up" decision_take "$(at --with-data '{"opened":"opened"}')"
write_as_agent state-decision.sh --take
eq "2: and comes up for a verdict" decision_verdict "$(at --with-data '{"taken":"taken"}')"
write_as_agent state-decision.sh --hold --reason "the loader's maintainers answer this week"
eq "2: --hold writes" 0 $?
eq "2: held, the report goes on to classification" classify_report "$(at --with-data '{"verdict":"hold","rationale":"waits on a fact"}')"
eq "2: needs_fix, as the directive says for a question" rebrief "$(at --with-data '{"classification":"needs_fix"}')"
ROW_BEFORE=$(live_body | jq -c '.holdings[] | select(.worker == "feat-1")')
rebrief_as_agent
eq "2: --rebrief exits 9 while the question is open" 9 "$RB_RC"
grep -q "waits on question $QI" "$T/rb.err" && ok "  ... saying the unit waits on it" || bad "  ... saying the unit waits on it" "$(cat "$T/rb.err")"
eq "  ... the holding unchanged" "$ROW_BEFORE" "$(live_body | jq -c '.holdings[] | select(.worker == "feat-1")')"
eq "2: sent: refused takes the run back to wait" wait "$(at --with-data '{"sent":"refused"}')"
eq "  ... the leg in question_legs" "$REQ:deliver" "$(ctx question_legs)"
eq "  ... and never in taken_legs" "" "$(ctx taken_legs | grep -Fx "$REQ:deliver")"
(cd "$WD" && bash "$PS/state-handover.sh" --session "$S") > "$T/handover.json" 2> "$T/handover.err"
eq "2: the handover read lists the question with its entry, held" "$QI $N true" \
    "$(jq -r '.open_questions[] | "\(.identity) \(.decision) \(.handled)"' "$T/handover.json" 2>>"$T/jq.err")"
eq "  ... and no question-unhandled gap" "" "$(jq -r '.gaps[].gap | select(startswith("question-unhandled"))' "$T/handover.json" 2>>"$T/jq.err")"

echo "== 3. the leg is held as waiting until the question closes =="
eq "3: the next leg tick goes back to wait" wait "$(at --with-data '{"event":"leg"}')"
eq "  ... wait_target names nothing, the leg waiting, nothing unentered" "none $REQ $QI 0" \
    "$(target '"\(.path) \(.waiting[0].request) \(.waiting[0].question) \(.unentered | length)"')"
eq "  ... and rebrief entered once" 1 "$(entered rebrief)"

echo "== 4. answered, the unit runs again on a new leg =="
(cd "$WD" && "$SHIRABE_BIN" question settle "$QI" --in "$S" --chosen pin --reason "one upgrade path is easier to keep" \
    > "$T/settle.json" 2> "$T/settle.err") || bad "4: the coordinator settles the question as its addressee" "$(cat "$T/settle.err")"
eq "4: koto reads it closed" false "$( (cd "$WD" && koto decisions history "$QI") | jq -r .open)"
st=$(at --with-data '{"event":"leg"}')
eq "  ... offered with disposition answered" "answered $QI" "$(target '"\(.disposition) \(.question)"')"
# The held entry may come up for its answer on the way; record it from koto.
for _ in 1 2 3 4 5; do
    case "$st" in
        decision_answer) write_as_agent state-decision.sh --answer --outcome pin
                         st=$(at --with-data '{"answered":"recorded"}') ;;
        decision_verdict) write_as_agent state-decision.sh --settle --outcome pin --reason "one upgrade path is easier to keep"
                          st=$(at --with-data '{"verdict":"settle","rationale":"answered in koto"}') ;;
        *) break ;;
    esac
done
eq "4: the answered result reaches classification" classify_report "$st"
eq "4: needs_fix reaches rebrief" rebrief "$(at --with-data '{"classification":"needs_fix"}')"
rebrief_as_agent
eq "4: --rebrief runs the unit again" 0 "$RB_RC"
NEWRP=$(sed -n 's/^leg=//p' "$T/rb.out")
case "$NEWRP" in
    *":deliver") [ "${NEWRP%%:*}" != "$REQ" ] && ok "  ... on a new leg" || bad "  ... on a new leg" "$NEWRP" ;;
    *) bad "  ... on a new leg" "$(cat "$T/rb.out" "$T/rb.err")" ;;
esac
eq "  ... the holding on it" "leg $NEWRP" "$(live_body | jq -r '.holdings[] | select(.worker == "feat-1") | .return_path')"
BRIEF=$(sed -n 's/^brief=//p' "$T/rb.out")
if [ -f "$BRIEF" ] && grep -qF "question \`$QI\`, which you raised, has been answered" "$BRIEF"; then
    ok "  ... its brief naming the answered question"
else
    bad "  ... its brief naming the answered question" "brief '$BRIEF': $(sed -n 1,20p "$BRIEF" 2>&1)"
fi
at --with-data '{"sent":"sent"}' > /dev/null
from_to rebrief rebrief_record && ok "4: sent goes on to rebrief_record" || bad "4: sent goes on to rebrief_record" "now at $(now_at)"

echo "== 5. the unit finishes on its new leg =="
[ "$(now_at)" = wait ] || at > /dev/null
eq "5: back at wait" wait "$(now_at)"
(cd "$T" && koto init deliver-feat-1-r --template "$T/tpl/deliver.md" --var TOPIC=feat-1 --koto-leg "$NEWRP" > "$T/child.out" 2> "$T/child.err" \
    && koto next deliver-feat-1-r --no-cleanup --with-data '{"finish":"go"}' >> "$T/child.out" 2>> "$T/child.err") \
    || bad "5: the re-briefed worker binds to the new leg and finishes" "$(cat "$T/child.out" "$T/child.err")"
eq "5: its result carrying pr goes to report_link" report_link "$(at --with-data '{"event":"leg"}')"
eq "  ... offered as a resolved leg" "resolved ${NEWRP%%:*}" "$(target '"\(.disposition) \(.request)"')"

finish
