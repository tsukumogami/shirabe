#!/usr/bin/env bash
# coordinate-template-structure_engine_test.sh -- guarantees over coordinate.md,
# checked on the compiled template (koto template compile) and its source.
#
# Proves the check-state contract holds for every state with a default action:
# no accepts block (evidence can't skip the read), no polling or confirmation,
# every gate overridable: false, the only command gate is coord-verdict.sh over
# the state's own capture, and a context gate appears only on a decider
# input's key (context-exists), or on coord/pick.json, the facts pick_facts
# cuts the pick decider's input, coord/pick_slice.json, from. One command gate
# reads another state's capture on purpose:
# report_questions' report_holding re-reads report_facts' sealed verdict, the
# one report_facts routed on, to send a report with no questions on to
# classification only when it had a holding. Also: the design's decision
# states and edges exist; no cycle is made of check states only; the state set is the design's; no write script
# (state-open, state-write, state-holding, land-merge, merge-exec)
# appears in any default action or gate; no directive names
# merge-exec.sh; no check script calls `gh api` without --method GET (GraphQL
# queries aside) or sends a GraphQL mutation; nothing says the human merges;
# every reference file is named by a state; the three deciders are declared
# with their inputs gated; teardown takes `removed` into the inventory, whose
# gate passes --absent-route and routes exit 5 to teardown_handoff and exit 6
# back to teardown with teardown_topic kept. The GitHub record is gone
# (docs/designs/current/DESIGN-coordinator-record-teardown.md): no STORE
# variable, no move, predecessor close-out or rotation close-out state, a
# rotation's end (pick_facts's rotation-over and the hub's `end`) goes straight
# to rotation_end, and a roadmap's close ends the run with nothing to close.
# Every state-entry.sh call the templates, SKILL.md or the references give
# with an outward kind passes --on, which state-entry.sh requires. The Run
# `role` row is built only by state-stored-set.sh and state-open.sh's seed and
# --carry --role, a fixture script that builds it failing; its readers are an
# allow-list (the writers, state-handover.sh, coordinate-open.sh and
# dispatch-worker.sh's input_role, a fixture adding a read to its
# resolve_grant or a function that one calls failing, and coordinate-report.sh,
# the record line's reader) over three read forms
# (state-read.sh --run, `role` used as a Run key, a direct record/run read),
# with the scripts that read the Run section or the record at the branch base
# listed for a direct record/run read, an entry naming a function for a script
# with two paths, and fixtures adding each form failing; and no script passes
# --role to niwa dispatch. The reconcile directive's no-role fill (the
# opener's role= or one ask with no recommendation, never inferred) and its
# no-reports-to fill for a start given --dispatched-by sit in the reconcile
# state's directive and in no other state's text, and that directive closes
# every handover gap before it prints the first report with
# reconcile-report-get.sh --md, and submits reconciled: reported after both
# (Decision 3).
#
# Needs koto (to compile) and jq; SKIPs without koto, which
# run-tests.sh --engine turns into a failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
TPL="$HERE/../koto-templates/coordinate.md"
for b in koto jq; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/coord-structure.XXXXXX") || exit 1; ktg_on_exit 'rm -rf "$T"'
export HOME="$T/home"; mkdir -p "$HOME"
J=$(koto template compile "$TPL" 2>/dev/null) || { echo "FAIL: coordinate.md does not compile"; exit 1; }

WANT="ask_up classify_report decision_answer decision_apply decision_carry decision_evidence decision_next decision_open decision_raise decision_redirect decision_redirect_send decision_reply decision_reply_send decision_take decision_verdict decision_withdraw decision_withdraw_send deferral_dispose destroy dispatch dispatch_check done done_handed_over done_not_active done_stopped escalate escalate_send failure goal_fit land land_merge leg_pick leg_spent merge_confirm merged_facts milestone_reopen milestone_verdict pick pick_facts posture_ask predecessor_carry promote quiet_check rebrief rebrief_record reconcile reconcile_pass record record_conflict record_find record_open report_facts report_link report_questions roadmap_blocked roadmap_close roadmap_close_step roadmap_status rotation_end start start_posture status_message surface surface_check take_report teardown teardown_confirm teardown_handoff teardown_inventory verified_confirm verify verify_board wait wait_leg"
GOT=$(jq -r '.states | keys[]' "$J" | sort | tr '\n' ' ' | sed 's/ $//')
[ "$GOT" = "$WANT" ] && pass "the state set is the design's" || fail "the state set is the design's" "$(diff <(echo "$WANT" | tr ' ' '\n') <(echo "$GOT" | tr ' ' '\n'))"

# The GitHub record's states and its store choice are gone, and a rotation's
# end and a roadmap's close no longer pass through a close-out on GitHub.
GONE=$(jq -r '[(.states | keys[] | select(test("^(record_move|predecessor_(handoff|close|step|done|handed_over)|rotation_(close|step|done))$"))),
               (.variables // {} | keys[] | select(. == "STORE"))] | .[]' "$J")
[ -z "$GONE" ] && pass "no GitHub record state or STORE variable is declared" || fail "no GitHub record state or STORE variable is declared" "$GONE"
jq -e '([.states.pick_facts.transitions[] | select(.when["gates.pick_facts_verdict.exit_code"] == 32) | .target] == ["rotation_end"])
       and ([.states.wait.transitions[] | select(.when.event == "end" and .when["vars.DISCIPLINE"].is_set == true) | .target] == ["rotation_end"])
       and ([.states.record_find.transitions[] | .when["gates.record_find_verdict.exit_code"] | select(. == 17 or . == 18 or . == 19)] == [])
       and ([.states.roadmap_close_step.transitions[] | select(.when.step == "closed") | [.target, .context_assignments.outcome]] == [["done", "closed"]])' "$J" >/dev/null \
    && pass "a rotation's end goes straight to rotation_end and a roadmap's close ends the run" \
    || fail "a rotation's end goes straight to rotation_end and a roadmap's close ends the run"

# The dispatch path's three action states keep their own contract, checked in
# DISPATCH below: leg_pick routes on a context-matches gate over the
# wait_target its own action writes; wait_leg reads one leg through a
# request-leg gate and accepts rescan or back while the leg is open, so the
# hub is never held by one worker; teardown_inventory's verdict is sealed as a
# file through coord-log.sh seal --file --key and read by teardown-verdict.sh,
# which coord-verdict.sh's token form can't carry.
DISPATCH_STATES='["leg_pick","wait_leg","teardown_inventory"]'
BADCHECK=$(jq -r --argjson skip "$DISPATCH_STATES" '.states | to_entries[] | select(.value.default_action != null) | select(.key as $k | ($skip | index($k)) | not) | .key as $s | .value as $v
  | [ (if $v.accepts != null then "\($s): has accepts" else empty end),
      (if ($v.default_action.polling // null) != null then "\($s): polls" else empty end),
      (if ($v.default_action.requires_confirmation // false) then "\($s): requires confirmation" else empty end),
      (($v.default_action.capture_stdout_as // "") as $cap
        | ($v.gates // {}) | to_entries[]
        | if .value.overridable != false then "\($s).\(.key): overridable"
          elif $s == "report_questions" and .key == "report_holding" then
            (if (.value.command | test("coord-verdict\\.sh\" --session \"\\{\\{SESSION_NAME\\}\\}\" --state report_facts --capture \"\\{\\{REPORT\\}\\}\"")) then empty
             else "\($s).\(.key): not coord-verdict over report_facts\u0027 capture" end)
          elif .value.type == "command" and ((.value.command | test("coord-verdict\\.sh\" --session \"\\{\\{SESSION_NAME\\}\\}\" --state " + $s + " --capture \"\\{\\{" + $cap + "\\}\\}\"")) | not) then "\($s).\(.key): not coord-verdict over its own capture"
          elif .value.type == "context-matches" then "\($s).\(.key): a context-matches gate"
          elif .value.type == "context-exists" and ((.value.key | test("^coord/(pick|pick_slice|report|decision)\\.json$")) | not) then "\($s).\(.key): a context gate that is not a decider input"
          else empty end) ] | .[]' "$J")
[ -z "$BADCHECK" ] && pass "every check state keeps the contract" || fail "every check state keeps the contract" "$BADCHECK"

# The dispatch path's action states: no polling or confirmation, every gate
# overridable: false, and each gate the one the design names.
DISPATCH=$(jq -r '.states as $st
  | [ (if ($st.leg_pick.gates.leg_target.type != "context-matches" or $st.leg_pick.gates.leg_target.key != "wait_target") then "leg_pick: not leg_target over wait_target" else empty end),
      (if $st.leg_pick.accepts != null then "leg_pick: has accepts" else empty end),
      (if $st.wait_leg.gates.leg_result.type != "request-leg" then "wait_leg: not a request-leg gate" else empty end),
      (if (($st.wait_leg.accepts // {}) | keys) != ["watch"] then "wait_leg: accepts more than watch" else empty end),
      (if ($st.teardown_inventory.gates.inventory_durable.command | test("teardown-verdict\\.sh\" gate --session") | not) then "teardown_inventory: not teardown-verdict.sh gate" else empty end),
      (if $st.teardown_inventory.accepts != null then "teardown_inventory: has accepts" else empty end),
      ($st | to_entries[] | select(.key == "leg_pick" or .key == "wait_leg" or .key == "teardown_inventory") | .key as $s | .value
        | (if (.default_action.polling // null) != null then "\($s): polls" else empty end),
          (if (.default_action.requires_confirmation // false) then "\($s): requires confirmation" else empty end),
          ((.gates // {}) | to_entries[] | select(.value.overridable != false) | "\($s).\(.key): overridable")) ] | .[]' "$J")
[ -z "$DISPATCH" ] && pass "the dispatch path's action states keep theirs" || fail "the dispatch path's action states keep theirs" "$DISPATCH"

# The removed route: teardown takes `removed` into the same inventory as
# `stopped`; the inventory's gate passes --absent-route, and its two absent
# routes go to the handoff (5, after removed) and back to teardown (6, after
# stopped) with teardown_topic kept, while 2 and 3 still go to surface.
jq -e '(.states.teardown.accepts.teardown.values | index("removed")) != null
       and any(.states.teardown.transitions[]; .target == "teardown_inventory" and .when.teardown == "removed")
       and any(.states.teardown.transitions[]; .target == "teardown_inventory" and .when.teardown == "stopped")
       and (.states.teardown_inventory.gates.inventory_durable.command | test("teardown-verdict\\.sh\" gate --session \"\\{\\{SESSION_NAME\\}\\}\" --absent-route$"))
       and ([.states.teardown_inventory.transitions[] | select(.when["gates.inventory_durable.exit_code"] == 5) | .target] == ["teardown_handoff"])
       and ([.states.teardown_inventory.transitions[] | select(.when["gates.inventory_durable.exit_code"] == 6) | [.target, (.context_assignments // null)]] == [["teardown", null]])
       and ([.states.teardown_inventory.transitions[] | select(.when["gates.inventory_durable.exit_code"] == 2 or .when["gates.inventory_durable.exit_code"] == 3) | .target] | unique) == ["surface"]' "$J" >/dev/null \
    && pass "teardown takes removed; the inventory routes absent to the handoff (5) or back to teardown (6), the topic kept" \
    || fail "teardown takes removed; the inventory routes absent to the handoff (5) or back to teardown (6), the topic kept"
jq -e '(.states.teardown.directive + .states.teardown.details | contains("`removed`"))
       and (.states.teardown_inventory.details | contains("absent"))
       and (.states.teardown_handoff.details | contains("removed yes"))
       and (.states.destroy.details | contains("removed yes"))' "$J" >/dev/null \
    && pass "the teardown, inventory, handoff and destroy directives explain removed" \
    || fail "the teardown, inventory, handoff and destroy directives explain removed"

# The design's decision states and changed edges, as from>to pairs.
EDGES='decision_next>decision_carry decision_next>decision_open decision_next>decision_answer
decision_next>decision_evidence decision_next>decision_raise decision_next>decision_withdraw
decision_next>decision_reply decision_next>decision_redirect decision_next>escalate
decision_next>decision_take decision_next>decision_verdict decision_next>classify_report
decision_next>pick_facts decision_carry>decision_next
decision_take>decision_next decision_verdict>decision_next escalate>escalate_send
escalate>record_conflict decision_withdraw>decision_withdraw_send decision_withdraw>record_conflict
decision_reply>decision_reply_send decision_reply>record_conflict decision_redirect>decision_redirect_send
decision_redirect>record_conflict escalate_send>decision_next escalate_send>decision_answer
decision_withdraw_send>decision_next decision_reply_send>decision_next decision_redirect_send>decision_next
report_questions>decision_open report_questions>classify_report report_questions>wait
report_questions>rebrief report_questions>surface decision_open>decision_next
decision_raise>decision_next decision_answer>decision_next decision_answer>decision_apply
decision_evidence>decision_next surface_check>wait surface_check>surface
wait>decision_answer wait>decision_evidence wait>decision_raise pick_facts>decision_next
roadmap_close>roadmap_blocked roadmap_blocked>wait report_facts>report_questions
failure>decision_raise surface>decision_raise surface>surface_check dispatch_check>decision_next
wait_leg>leg_spent leg_spent>record leg_spent>surface
roadmap_status>milestone_verdict milestone_verdict>record milestone_verdict>wait classify_report>roadmap_status
wait>milestone_reopen milestone_reopen>record milestone_reopen>wait'
MISSING=$(for e in $EDGES; do
    jq -e --arg f "${e%%>*}" --arg t "${e#*>}" 'any(.states[$f].transitions[]?; .target == $t)' "$J" >/dev/null || echo "$e"
done)
[ -z "$MISSING" ] && pass "every decision state and edge the design names exists" || fail "every decision state and edge the design names exists" "$MISSING"
for e in report_facts\>classify_report report_facts\>wait failure\>wait surface\>wait; do
    jq -e --arg f "${e%%>*}" --arg t "${e#*>}" 'any(.states[$f].transitions[]?; .target == $t)' "$J" >/dev/null \
        && fail "the edge the design replaced is gone: $e" || pass "the edge the design replaced is gone: $e"
done
# pick's two routes (shirabe#549, #550): a unit waiting on a person goes to
# decision_raise with the unit it parks and never to a dispatch, and a unit
# scoped alone is a dispatch like any other, its topic passed on.
jq -e '([.states.pick.transitions[] | select(.when.choice == "await_decision") | [.target, .when["evidence.unit"]]] == [["decision_raise", "present"]])
       and ([.states.pick.transitions[] | select(.when.choice == "scope") | [.target, .context_assignments.dispatch_topic]] == [["dispatch_check", "${evidence.unit}"]])' "$J" >/dev/null \
    && pass "pick parks a unit through decision_raise and dispatches a scope like any unit" \
    || fail "pick parks a unit through decision_raise and dispatches a scope like any unit"
# A checkpoint report (progress, 64) goes through report_questions like any
# report, so a question it asks is still read; from there it goes back to
# wait, never to classify_report or a re-brief (shirabe#491).
jq -e '(.states.report_facts.transitions | any(.target == "report_questions" and .when["gates.report_facts_verdict.exit_code"] == 64))
       and ([.states.report_questions.transitions[] | select(.when["gates.report_holding.exit_code"] == 64) | .target] | unique) == ["wait"]' "$J" >/dev/null \
    && pass "a checkpoint report is read for questions and goes back to wait" || fail "a checkpoint report is read for questions and goes back to wait"
# A report's pull request reaches its holding through report_link, and `done`
# reaches verify only with a pull request: report_pr reads report_facts' seal.
jq -e '(.states.report_facts.transitions | any(.target == "report_link" and .when["gates.report_facts_verdict.exit_code"] == 63))
       and (.states.wait.transitions | any(.target == "take_report" and .when.event == "progress"))
       and (.states.report_link.transitions | any(.target == "report_facts" and .when.linked == "written"))
       and .states.classify_report.gates.report_pr.overridable == false
       and (.states.classify_report.gates.report_pr.command | test("report-pr\\.sh\" --session"))
       and ([.states.classify_report.transitions[] | select(.when.classification == "done")
             | [.target, .when["gates.report_pr.exit_code"], (.when["vars.ROADMAP_FORM"] // null)]]
            == [["verify", 0, null], ["wait", 1, "feature"], ["roadmap_status", 1, "milestone"]])
       and ([.states.classify_report.transitions[] | select(.when["gates.report_pr.exit_code"] == 1) | .context_assignments]
            | length == 2 and all(. == {report_topic: "", worker_report: ""}))
       and (.states.verify_board.transitions | any(.target == "wait" and .when["gates.verify_board_verdict.exit_code"] == 77))
       and (.states.verify_board.transitions | any(.target == "wait" and .when["gates.verify_board_verdict.exit_code"] == 78))' "$J" >/dev/null \
    && pass "report_link links a report's pull request; done needs one; verify_board leaves on no-pr" \
    || fail "report_link links a report's pull request; done needs one; verify_board leaves on no-pr"
# The verdict arm waits on the entry decision-next.sh writes, as pick waits on pick_input.
jq -e '.states.decision_next.gates.decision_input == {type: "context-exists", key: "coord/decision.json", overridable: false}
       and any(.states.decision_next.transitions[]; .target == "decision_verdict" and .when["gates.decision_input.exists"] == true)' "$J" >/dev/null \
    && pass "decision_next's verdict arm needs coord/decision.json" || fail "decision_next's verdict arm needs coord/decision.json"
# surface_check passes through to wait in the same tick, so the step that
# reports an accepted need must be in wait's own directive, the one shown.
jq -e '.states.surface_check.accepts == null and (.states.wait.directive | contains("coord/need.json") and contains("--blocked"))' "$J" >/dev/null \
    && pass "wait's directive says to report an accepted need, since surface_check is passed through" \
    || fail "wait's directive says to report an accepted need, since surface_check is passed through"
# The arms that reach decision_answer and decision_evidence need the fields
# state-decision.sh reads: koto has no conditional required, so the arm does.
jq -e '
  any(.states.wait.transitions[]; .target == "decision_answer" and .when.event == "answer"
      and .when["evidence.decision"] == "present" and .when["evidence.round"] == "present")
  and any(.states.wait.transitions[]; .target == "decision_evidence" and .when.event == "evidence"
      and .when["evidence.decision"] == "present")
  and any(.states.escalate_send.transitions[]; .target == "decision_answer" and .when.sent == "answered"
      and .when["evidence.decision"] == "present" and .when["evidence.round"] == "present")' "$J" >/dev/null \
    && pass "an answer or evidence arm needs its decision (and round) present" \
    || fail "an answer or evidence arm needs its decision (and round) present"
# A reply and a redirect go to the entry's source, never to whatever report
# arrived last: a newer report can overwrite report_topic first.
for st in decision_reply_send decision_redirect_send; do
    jq -e --arg s "$st" '.states[$s].directive | test("to the entry.s source")' "$J" >/dev/null \
        && pass "$st sends to the entry's source" || fail "$st sends to the entry's source"
done
jq -e '.states.decision_redirect_send.details | contains("report_topic")' "$J" >/dev/null \
    && pass "decision_redirect_send warns off report_topic" || fail "decision_redirect_send warns off report_topic"
for w in answer evidence raise; do
    jq -e --arg w "$w" '.states.wait.accepts.event.values | index($w)' "$J" >/dev/null && pass "wait takes the $w event" || fail "wait takes the $w event"
done

# check_cycle <compiled template>: the states left in a cycle made of check
# states only (a default action and no accepts), found by pruning every check
# state no other remaining one leads to. Such a cycle would re-read forever
# with no evidence to break it; roadmap_close reaching wait through
# roadmap_blocked, an agent state, is what keeps the close out of one.
# One edge is left out on purpose: decision_next's `clear` to pick_facts.
# pick_facts goes back to decision_next only on decision-next.sh --owed pick,
# which fires on exactly the rules whose absence is `clear`, read in one pass
# over the same record, so the pair can't turn twice without a write between.
check_cycle() {
    jq -r --arg skip "decision_next>pick_facts" '
        def prune: . as {n: $n, e: $e}
            | ($n | map(. as $x | select(any($e[]; .[1] == $x)))) as $k
            | if ($k | length) == ($n | length) then $n
              else {n: $k, e: ($e | map(select((.[0] as $a | $k | index($a)) and (.[1] as $b | $k | index($b)))))} | prune end;
        .states as $st
        | [$st | to_entries[] | select(.value.default_action != null and .value.accepts == null) | .key] as $c
        | [$st | to_entries[] | .key as $f | select($c | index($f)) | .value.transitions[]? | .target
           | select(. as $t | $c | index($t)) | select(($f + ">" + .) != $skip) | [$f, .]] as $e
        | {n: $c, e: $e} | prune | .[]' "$1"
}
CYC=$(check_cycle "$J")
[ -z "$CYC" ] && pass "no cycle is made of check states only" || fail "no cycle is made of check states only" "$CYC"
jq '(.states.roadmap_close.transitions[] | select(.target == "roadmap_blocked")) .target = "pick_facts"' "$J" > "$T/cycle.json"
[ -n "$(check_cycle "$T/cycle.json")" ] && pass "the cycle check finds a close routed straight back to pick_facts" \
    || fail "the cycle check finds a close routed straight back to pick_facts"

NONOVR=$(jq -r '.states | to_entries[] | .key as $s | (.value.gates // {}) | to_entries[] | select(.value.overridable != false) | "\($s).\(.key)"' "$J")
[ -z "$NONOVR" ] && pass "every gate in the template is overridable: false" || fail "every gate in the template is overridable: false" "$NONOVR"

WRITES=$(jq -r '.states | to_entries[] | .key as $s | [(.value.default_action.command // ""), ((.value.gates // {}) | to_entries[] | .value.command // "")] | .[] | select(test("state-open|state-write|state-write-core|state-holding|state-hold\\.sh|state-decision.sh\" --session \"[^\"]*\" --(carry|open|take|settle|escalate|hold|evidence|answer|sent)|land-merge|merge-exec")) | $s' "$J")
[ -z "$WRITES" ] && pass "no write script runs as an action or a gate" || fail "no write script runs as an action or a gate" "$WRITES"

MEXEC=$(jq -r '.states | to_entries[] | select(((.value.directive // "") + (.value.details // "")) | test("merge-exec")) | .key' "$J")
[ -z "$MEXEC" ] && pass "no directive names merge-exec.sh" || fail "no directive names merge-exec.sh" "$MEXEC"

CHECKS=$(jq -r '.states[] | .default_action.command // empty' "$J" | sed -n 's#.*/skills/coordinate/scripts/\([a-z-]*\.sh\).*#\1#p' | sort -u)
for c in $CHECKS; do
    f="$HERE/$c"
    [ -f "$f" ] || { fail "check script $c exists"; continue; }
    # Every `gh api` call in a check script is a GET, or a GraphQL query.
    bad=$(grep -n 'gh api' "$f" | grep -v -- '--method GET' | grep -v 'gh api graphql' | grep -v '^[0-9]*:[[:space:]]*#' || true)
    [ -z "$bad" ] && pass "$c: every gh api call is a GET or a GraphQL query" || fail "$c: every gh api call is a GET or a GraphQL query" "$bad"
    grep -qi 'mutation' "$f" && fail "$c: sends no GraphQL mutation" || pass "$c: sends no GraphQL mutation"
    grep -qE '^[[:space:]]*(\.|source)[[:space:]]+[^#]*state-write-core' "$f" && fail "$c: sources no write core" || pass "$c: sources no write core"
done
grep -qE '^[[:space:]]*(\.|source)[[:space:]]+[^#]*state-write-core' "$HERE/state-common.sh" && fail "state-common.sh sources no write core" || pass "state-common.sh sources no write core"

# decisions_writers <dir>: every script there, other than state-decision.sh
# and the tests, that opens the Decisions section (sets DECISIONS_WRITER=1).
decisions_writers() {
    grep -lE '^[^#]*DECISIONS_WRITER=["'\'']?1' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' | grep -v '/state-decision\.sh$' || true
}
OPENERS=$(decisions_writers "$HERE")
[ -z "$OPENERS" ] && pass "only state-decision.sh opens the Decisions section" || fail "only state-decision.sh opens the Decisions section" "$OPENERS"
grep -qE '^[^#]*DECISIONS_WRITER=1' "$HERE/state-decision.sh" && pass "state-decision.sh opens it" || fail "state-decision.sh opens it"
mkdir -p "$T/openers"
cp "$HERE/state-decision.sh" "$HERE/state-write.sh" "$T/openers/"
printf '\nDECISIONS_WRITER="1"\n' >> "$T/openers/state-write.sh"
[ "$(decisions_writers "$T/openers")" = "$T/openers/state-write.sh" ] && pass "the check names another script that opens it" ||
    fail "the check names another script that opens it" "$(decisions_writers "$T/openers")"
# The Holds section the same way: only state-hold.sh sets HOLDS_WRITER=1.
holds_writers() {
    grep -lE '^[^#]*HOLDS_WRITER=["'\'']?1' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' | grep -v '/state-hold\.sh$' || true
}
HOPENERS=$(holds_writers "$HERE")
[ -z "$HOPENERS" ] && pass "only state-hold.sh opens the Holds section" || fail "only state-hold.sh opens the Holds section" "$HOPENERS"
grep -qE '^[^#]*HOLDS_WRITER=1' "$HERE/state-hold.sh" && pass "state-hold.sh opens it" || fail "state-hold.sh opens it"
printf '\nHOLDS_WRITER=1\n' >> "$T/openers/state-write.sh"
[ "$(holds_writers "$T/openers")" = "$T/openers/state-write.sh" ] && pass "the check names another script that opens the Holds section" ||
    fail "the check names another script that opens the Holds section" "$(holds_writers "$T/openers")"
# The stored set's sections the same way: only state-stored-set.sh sets STATE_WRITER=1.
state_writers() {
    grep -lE '^[^#]*STATE_WRITER=["'\'']?1' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' | grep -v '/state-stored-set\.sh$' || true
}
SOPENERS=$(state_writers "$HERE")
[ -z "$SOPENERS" ] && pass "only state-stored-set.sh opens the Run, Standing and Work sections" || fail "only state-stored-set.sh opens the Run, Standing and Work sections" "$SOPENERS"
grep -qE '^[^#]*STATE_WRITER=1' "$HERE/state-stored-set.sh" && pass "state-stored-set.sh opens them" || fail "state-stored-set.sh opens them"
printf '\nSTATE_WRITER=1\n' >> "$T/openers/state-write.sh"
[ "$(state_writers "$T/openers")" = "$T/openers/state-write.sh" ] && pass "the check names another script that opens the stored set" ||
    fail "the check names another script that opens the stored set" "$(state_writers "$T/openers")"
# A milestone's verdict-owed Work row the same way: only roadmap-status.sh
# sets VERDICT_WRITER=1 (docs/designs/DESIGN-milestone-verdicts.md).
verdict_writers() {
    grep -lE '^[^#]*VERDICT_WRITER=["'\'']?1' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' | grep -v '/roadmap-status\.sh$' || true
}
VOPENERS=$(verdict_writers "$HERE")
[ -z "$VOPENERS" ] && pass "only roadmap-status.sh opens the verdict-owed rows" || fail "only roadmap-status.sh opens the verdict-owed rows" "$VOPENERS"
grep -qE '^[^#]*VERDICT_WRITER=1' "$HERE/roadmap-status.sh" && pass "roadmap-status.sh opens them" || fail "roadmap-status.sh opens them"
printf '\nVERDICT_WRITER=1\n' >> "$T/openers/state-write.sh"
[ "$(verdict_writers "$T/openers")" = "$T/openers/state-write.sh" ] && pass "the check names another script that opens the verdict-owed rows" ||
    fail "the check names another script that opens the verdict-owed rows" "$(verdict_writers "$T/openers")"
# references/state-keys.md's key table names each flag beside the one script
# the checks above hold it to, so the reference and the scripts agree.
KEYS_REF="$HERE/../references/state-keys.md"
for fw in record/decisions:state-decision.sh:DECISIONS_WRITER record/holds:state-hold.sh:HOLDS_WRITER \
          record/run:state-stored-set.sh:STATE_WRITER record/work:roadmap-status.sh:VERDICT_WRITER; do
    key=${fw%%:*}; rest=${fw#*:}; script=${rest%%:*}; flag=${rest#*:}
    grep -E "^\| [^|]*\`$key\`" "$KEYS_REF" | grep -qF "\`$script\` (\`$flag\`)" \
        && pass "state-keys.md names $script ($flag) as $key's writer" \
        || fail "state-keys.md names $script ($flag) as $key's writer"
done

# A discipline rotation's own keys on the session store, record/rotation and
# record/reasoning (docs/designs/current/DESIGN-coordinator-record-teardown.md,
# Decision 3): only state-stored-set.sh writes them, through core_write_rotation,
# and no other script names either key in a koto context write.
rotation_writers() {
    grep -lE '^[^#]*core_write_rotation' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' \
        | grep -v '/state-stored-set\.sh$' | grep -v '/state-write-core\.sh$' || true
    grep -lE '^[^#]*context add[^#]*record/(rotation|reasoning)' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' || true
}
ROPENERS=$(rotation_writers "$HERE")
[ -z "$ROPENERS" ] && pass "only state-stored-set.sh writes record/rotation and record/reasoning" \
    || fail "only state-stored-set.sh writes record/rotation and record/reasoning" "$ROPENERS"
grep -qE '^[^#]*core_write_rotation' "$HERE/state-stored-set.sh" && pass "state-stored-set.sh writes them" || fail "state-stored-set.sh writes them"
printf '\n"$KOTO" context add "$S" record/reasoning --from-file f\n' >> "$T/openers/state-write.sh"
[ "$(rotation_writers "$T/openers")" = "$T/openers/state-write.sh" ] && pass "the check names another script that writes a rotation key" ||
    fail "the check names another script that writes a rotation key" "$(rotation_writers "$T/openers")"

# The rest of the record's keys (references/state-keys.md): record/meta, the
# sections and record/host are written only by the write core, and
# record/entries/<n>, record/posted/<n> and record/archive/<n> only by
# state-entry.sh (and the legacy import, through core_import_add). No other
# script writes or removes a record/ key itself, and only state-stored-set.sh
# calls core_write_host.
record_key_writers() {
    grep -lE '^[^#]*context (add|remove)[^#]*record/' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' \
        | grep -v '/state-write-core\.sh$' | grep -v '/state-entry\.sh$' || true
    grep -lE '^[^#]*context (add|remove)[^#]*record/(entries|posted|archive)/' "$1"/state-write-core.sh 2>/dev/null || true
    grep -lE '^[^#]*core_write_host' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' \
        | grep -v '/state-stored-set\.sh$' | grep -v '/state-write-core\.sh$' || true
}
KOPENERS=$(record_key_writers "$HERE")
[ -z "$KOPENERS" ] && pass "only the write core and state-entry.sh write the record's keys" \
    || fail "only the write core and state-entry.sh write the record's keys" "$KOPENERS"
grep -qE '^[^#]*context add[^#]*record/entries/' "$HERE/state-entry.sh" && grep -qE '^[^#]*context add[^#]*record/posted/' "$HERE/state-entry.sh" \
    && pass "state-entry.sh writes record/entries and record/posted" || fail "state-entry.sh writes record/entries and record/posted"
grep -qE '^[^#]*context add[^#]*record/meta' "$HERE/state-write-core.sh" && grep -qE '^[^#]*context add[^#]*record/host' "$HERE/state-write-core.sh" \
    && pass "the write core writes record/meta and record/host" || fail "the write core writes record/meta and record/host"
grep -qE '^[^#]*core_write_host' "$HERE/state-stored-set.sh" && pass "state-stored-set.sh writes record/host" || fail "state-stored-set.sh writes record/host"
rm -rf "$T/keyw" && mkdir -p "$T/keyw" && cp "$HERE/state-write.sh" "$HERE/state-write-core.sh" "$HERE/state-entry.sh" "$HERE/state-stored-set.sh" "$T/keyw/"
printf '\n"$KOTO" context add "$S" record/meta --from-file f\n' >> "$T/keyw/state-write.sh"
[ "$(record_key_writers "$T/keyw")" = "$T/keyw/state-write.sh" ] && pass "the check names another script that writes a record key" ||
    fail "the check names another script that writes a record key" "$(record_key_writers "$T/keyw")"
printf '\n"$KOTO" context add "$S" "record/entries/$N" --from-file f\n' >> "$T/keyw/state-write-core.sh"
[ "$(record_key_writers "$T/keyw" | grep -c 'state-write-core')" = 1 ] && pass "the check names the write core writing an entry" ||
    fail "the check names the write core writing an entry" "$(record_key_writers "$T/keyw")"

# ---- The Run role row: its writers and its readers ---------------------------
# docs/designs/DESIGN-coordinator-named-roles.md, Decision 1. The row is built
# only by state-stored-set.sh and by state-open.sh's seed (seed_state) and its
# --carry --role (carry_role); every other change to it goes through
# state-stored-set.sh --run role. Its readers are held to an allow-list, which
# gains each named caller in the change that adds it.
#
# role_hits <root>: one line per counted use in every script under <root> (a
# skill directory) but the tests and testdata, `<path>\t<function>\t<form>\t<line>`,
# <path> relative to <root> and <function> the bash function the line sits in
# (`-` outside one, and in a jq file). Comment lines aren't counted. The forms:
#   run-read    a call to state-read.sh --run
#   role-key    the literal role used as a Run key: a `.key == "role"` or
#               `.key != "role"` comparison, or passed to a helper that takes
#               a Run key (`run_has role`, `runval("role")`)
#   record-run  a direct read of record/run (an rs_key, a koto context call)
#   role-row    a Run row built with the key role (`key: "role"`)
# A whole read (state-stored-set.sh --list, --record, rs_record,
# rs_record_api) names no row, so it isn't counted. A file the scan can't read
# prints a `scan-failed` line, which every check below reports.
cat > "$T/role-hits.awk" <<'AWK'
{
    line = $0
    if (line ~ /^[[:space:]]*#/) next
    fn = (n > 0 ? names[n] : "-")
    if (path ~ /\.sh$/ && match(line, /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/)) {
        def = substr(line, RSTART, RLENGTH)
        ind = def; sub(/[^[:space:]].*$/, "", ind)
        name = def; sub(/^[[:space:]]*(function[[:space:]]+)?/, "", name); sub(/[[:space:]]*\(.*$/, "", name)
        fn = name
        rest = substr(line, RSTART + RLENGTH)
        if (rest !~ /\}[[:space:]]*;?[[:space:]]*$/) { n++; names[n] = name; inds[n] = ind }
    } else if (n > 0 && line ~ ("^" inds[n] "\\}")) {
        n--
    }
    if (line ~ /state-read\.sh[^|;&#]*--run([^A-Za-z0-9_-]|$)/) print path "\t" fn "\trun-read\t" FNR
    if (line ~ /\.key[[:space:]]*[!=]=[[:space:]]*\\?"role\\?"/ || line ~ /run_has[[:space:]]+\\?"?role([^A-Za-z0-9_-]|$)/ \
        || line ~ /runval\([[:space:]]*\\?"role\\?"[[:space:]]*\)/) print path "\t" fn "\trole-key\t" FNR
    if (line ~ /record\/run([^A-Za-z0-9_\/-]|$)/) print path "\t" fn "\trecord-run\t" FNR
    if (line ~ /(^|[^.A-Za-z0-9_])"?key"?[[:space:]]*:[[:space:]]*\\?"role\\?"/ || line ~ /\.key[[:space:]]*=[[:space:]]*\\?"role/) \
        print path "\t" fn "\trole-row\t" FNR
}
AWK
role_hits() {
    local f
    (cd "$1" && find . -type f \( -name '*.sh' -o -name '*.jq' \) ! -name '*_test.sh' ! -path './scripts/testdata/*' | sed 's|^\./||' | LC_ALL=C sort) \
        | while IFS= read -r f; do
            awk -v path="$f" -f "$T/role-hits.awk" "$1/$f" || printf '%s\t-\tscan-failed\t0\n' "$f"
        done
}

# The writers: a role row built anywhere but state-stored-set.sh and
# state-open.sh's seed_state and carry_role fails.
role_writers() {
    role_hits "$1" | awk -F'\t' '$3 == "scan-failed" || ($3 == "role-row" && $1 != "scripts/state-stored-set.sh" \
        && ($1 ":" $2) != "scripts/state-open.sh:seed_state" && ($1 ":" $2) != "scripts/state-open.sh:carry_role")'
}
RW=$(role_writers "$HERE/..") || RW="the writer check failed: $RW"
[ -z "$RW" ] && pass "only state-stored-set.sh and state-open.sh's seed and carry build the Run role row" \
    || fail "only state-stored-set.sh and state-open.sh's seed and carry build the Run role row" "$RW"
RH_ALL=$(role_hits "$HERE/..")
for w in "scripts/state-stored-set.sh	-" "scripts/state-open.sh	seed_state" "scripts/state-open.sh	carry_role"; do
    grep -q "^$w	role-row	" <<<"$RH_ALL" && pass "${w%%	*} (${w#*	}) builds the role row" || fail "${w%%	*} (${w#*	}) builds the role row" "$RH_ALL"
done
grep -nE '^[^#]*(^|[^A-Za-z_])seed_state "' "$HERE/state-open.sh" | grep -v 'seed_state()' > /dev/null \
    && grep -nE '^[^#]*(^|[^A-Za-z_])carry_role "' "$HERE/state-open.sh" | grep -v 'carry_role()' > /dev/null \
    && pass "state-open.sh writes it in its seed and its --carry --role" || fail "state-open.sh writes it in its seed and its --carry --role"
rm -rf "$T/rolew" && mkdir -p "$T/rolew/scripts" && cp "$HERE/state-write.sh" "$T/rolew/scripts/"
printf '%s\n' "jq '.run += [{key: \"role\", value: \"director\", set_by: \"x\", set: \"2026-09-26T08:00Z\"}]' \"\$F\" > \"\$F.next\"" >> "$T/rolew/scripts/state-write.sh"
[ "$(role_writers "$T/rolew" | cut -f1 | sort -u)" = scripts/state-write.sh ] && pass "the check names a fixture script that writes the role row" \
    || fail "the check names a fixture script that writes the role row" "$(role_writers "$T/rolew")"
mkdir -p "$T/rolew2/scripts" && cp "$HERE/state-open.sh" "$T/rolew2/scripts/"
printf '%s\n' 'rotation_role() {' "    jq '.run = [{key: \"role\", value: \"manager\", set_by: \"x\", set: \"y\"}]' \"\$1\"" '}' >> "$T/rolew2/scripts/state-open.sh"
[ "$(role_writers "$T/rolew2" | cut -f1,2 | sort -u)" = "scripts/state-open.sh	rotation_role" ] \
    && pass "  ... and one in another function of state-open.sh" || fail "  ... and one in another function of state-open.sh" "$(role_writers "$T/rolew2")"

# The readers. ROLE_ALLOW names who may read the row by any of the three read
# forms: the writers, state-handover.sh, coordinate-open.sh, which reads the
# role of the run a start continues, dispatch-worker.sh's input_role alone,
# which writes a successor brief's role from it (Decision 2), and
# coordinate-report.sh, whose --record-line prints it on the record line
# (Decision 3): dispatch-worker.sh's resolve_grant, and every function that
# one calls, stays role-blind, so a grant never depends on a role. An entry
# `<path>:<function>` pins a script with two paths to the function that may
# read it, so a read in any other function of that script (or outside one)
# fails, the readers' list below included.
ROLE_ALLOW="scripts/state-schema.jq scripts/state-stored-set.sh scripts/state-open.sh scripts/state-handover.sh scripts/coordinate-open.sh scripts/dispatch-worker.sh:input_role scripts/coordinate-report.sh"
# ROLE_READERS: the scripts that read the Run section or the record at the
# branch base this test landed on. Each may keep its whole reads for other rows,
# and may read record/run directly; any other script that adds a direct
# record/run read fails. The list is the output of this grep, run at that base
# (c17f9b0e) from the repository root, not typed:
#   git grep -lE '^[^#]*(rs_record|rs_session_state|rs_session_read|rs_facts|state-read\.sh|state-handover\.sh|state-stored-set\.sh[^#]*--(list|rules)|record/run|[^A-Za-z0-9_]\.run([^A-Za-z0-9_]|$))' \
#       c17f9b0e -- 'skills/coordinate/*.sh' 'skills/coordinate/*.jq' ':!:*_test.sh' ':!:skills/coordinate/scripts/testdata/*' \
#       | sed 's/^[^:]*:skills\/coordinate\///'
ROLE_READERS="legacy-import/import.sh
scripts/board-lib.sh
scripts/board-verdict.sh
scripts/closeout-read.sh
scripts/coord-log.sh
scripts/coordinate-open.sh
scripts/coordinate-report.sh
scripts/decision-next.sh
scripts/decision-render.sh
scripts/deferral-check.sh
scripts/dispatch-worker.sh
scripts/handover-classify.sh
scripts/land-check.sh
scripts/land-merge.sh
scripts/panel-evidence.sh
scripts/pick-facts.sh
scripts/quiet-check.sh
scripts/rebrief-record.sh
scripts/reconcile-deps.sh
scripts/reconcile-read.sh
scripts/resolve-coordinator.sh
scripts/roadmap-status.sh
scripts/state-common.sh
scripts/state-confirm.sh
scripts/state-decision.sh
scripts/state-entry.sh
scripts/state-find.sh
scripts/state-handover.sh
scripts/state-hold.sh
scripts/state-holding.sh
scripts/state-open.sh
scripts/state-read.sh
scripts/state-schema.jq
scripts/state-stored-set.sh
scripts/state-write-core.sh"
# role_readers <root> [<allow> [<readers>]]: each counted read the lists don't
# admit. The lists reach awk through its environment, which may hold a newline.
role_readers() {
    role_hits "$1" | ROLE_A="${2-$ROLE_ALLOW}" ROLE_R="${3-$ROLE_READERS}" awk -F'\t' '
        BEGIN {
            allow = ENVIRON["ROLE_A"]; readers = ENVIRON["ROLE_R"]
            na = split(allow, a, /[[:space:]]+/)
            for (i = 1; i <= na; i++) {
                if (a[i] == "") continue
                if (index(a[i], ":")) { p = a[i]; sub(/:.*/, "", p); pinned[p] = 1; okfn[a[i]] = 1 } else okfile[a[i]] = 1
            }
            nr = split(readers, r, /[[:space:]]+/)
            for (i = 1; i <= nr; i++) if (r[i] != "") rd[r[i]] = 1
        }
        $3 == "scan-failed" { print; next }
        $3 == "role-row" { next }
        ($1 in pinned) { if (!(($1 ":" $2) in okfn)) print; next }
        ($1 in okfile) { next }
        $3 == "record-run" && ($1 in rd) { next }
        { print }'
}
RR=$(role_readers "$HERE/..") || RR="the reader check failed: $RR"
[ -z "$RR" ] && pass "only the writers, state-handover.sh, coordinate-open.sh, dispatch-worker.sh's input_role and coordinate-report.sh read the Run role row, and only the listed readers read record/run" \
    || fail "only the writers, state-handover.sh, coordinate-open.sh, dispatch-worker.sh's input_role and coordinate-report.sh read the Run role row, and only the listed readers read record/run" "$RR"
grep -q '^scripts/dispatch-worker.sh	input_role	role-key	' <<<"$RH_ALL" && pass "dispatch-worker.sh's input_role reads it, a reader the check sees" \
    || fail "dispatch-worker.sh's input_role reads it, a reader the check sees" "$RH_ALL"
grep -q '^scripts/coordinate-report.sh	-	run-read	' <<<"$RH_ALL" && grep -q '^scripts/coordinate-report.sh	-	role-key	' <<<"$RH_ALL" \
    && pass "coordinate-report.sh reads it through state-read.sh --run for the record line, a reader the check sees" \
    || fail "coordinate-report.sh reads it through state-read.sh --run for the record line, a reader the check sees" "$(grep coordinate-report <<<"$RH_ALL")"
grep -q '^scripts/state-handover.sh	-	role-key	' <<<"$RH_ALL" && pass "state-handover.sh reads it, a reader the check sees" \
    || fail "state-handover.sh reads it, a reader the check sees" "$RH_ALL"
grep -q '^scripts/coordinate-open.sh	[^	]*	run-read	' <<<"$RH_ALL" && pass "coordinate-open.sh reads it through state-read.sh --run, a reader the check sees" \
    || fail "coordinate-open.sh reads it through state-read.sh --run, a reader the check sees" "$RH_ALL"
eq_fx() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "want [$2], got [$3]"; }
eq_fx "  ... and with coordinate-open.sh and coordinate-report.sh off the list, their reads fail the check" "scripts/coordinate-open.sh
scripts/coordinate-report.sh" \
    "$(role_readers "$HERE/.." "scripts/state-schema.jq scripts/state-stored-set.sh scripts/state-open.sh scripts/state-handover.sh scripts/dispatch-worker.sh:input_role" | cut -f1 | sort -u)"
# into_fn <name> <function> <line>: a skill directory holding dispatch-worker.sh
# with <line> added as the first line of <function>; prints what role_readers
# reports there, path, function and form.
into_fn() {
    rm -rf "$T/rolef-$1" && mkdir -p "$T/rolef-$1/scripts"
    awk -v f="$2" -v l="$3" '{ print } $0 == (f "() {") { print "    " l }' "$HERE/dispatch-worker.sh" > "$T/rolef-$1/scripts/dispatch-worker.sh"
    role_readers "$T/rolef-$1" | cut -f1,2,3 | sort -u
}
RG_KEY="R=\$(jq -r '[.run[] | select(.key == \"role\") | .value][0]' \"\$WORK/state.json\")"
eq_fx "a fixture adding a state-read.sh --run call to dispatch-worker.sh's resolve_grant fails" "scripts/dispatch-worker.sh	resolve_grant	run-read" \
    "$(into_fn rg-run resolve_grant 'R=$(bash "$HERE/state-read.sh" --session "$SESSION" --run)')"
eq_fx "a fixture adding a .key == \"role\" filter to resolve_grant fails" "scripts/dispatch-worker.sh	resolve_grant	role-key" \
    "$(into_fn rg-key resolve_grant "$RG_KEY")"
eq_fx "  ... and one in probe_help, which resolve_grant calls" "scripts/dispatch-worker.sh	probe_help	role-key" \
    "$(into_fn ph-key probe_help "$RG_KEY")"
eq_fx "  ... while dispatch-worker.sh as it is passes" "" \
    "$(role_readers "$HERE/.." | grep '^scripts/dispatch-worker.sh' | cut -f1,2,3)"
# The reconcile directive's order (Decision 3): every handover gap is closed
# before the first report is printed, so a role the no-role fix writes is the
# one its record line names, and the submit comes last.
RD=$(jq -r '.states.reconcile.directive' "$J")
pos() { awk -v p="$1" 'BEGIN { RS = "\001" } { i = index($0, p); print (i ? i : 0) }' <<<"$RD"; }
P_GAPS=$(pos 'state-handover.sh" --session {{SESSION_NAME}} --check')
P_MD=$(pos 'reconcile-report-get.sh" --session {{SESSION_NAME}} --md')
P_SUB=$(pos 'submit `reconciled: reported`')
[ "$P_GAPS" -gt 0 ] && [ "$P_MD" -gt "$P_GAPS" ] && [ "$P_SUB" -gt "$P_MD" ] \
    && pass "reconcile's directive closes the handover gaps, then prints with reconcile-report-get.sh --md, then submits" \
    || fail "reconcile's directive closes the handover gaps, then prints with reconcile-report-get.sh --md, then submits" "gaps=$P_GAPS md=$P_MD submit=$P_SUB"

# The reconcile directive's no-role and no-reports-to fills (Decision 1;
# PRD R2 and R9): in the reconcile state's directive, the part shown, and in
# no other state's directive or details.
for phrase in '`no-role` with the `role=` value the opener printed' 'is never inferred from the scope, the cap, the holdings,' \
              'A start given `--dispatched-by`'; do
    jq -e --arg p "$phrase" '.states.reconcile.directive | contains($p)' "$J" > /dev/null \
        && pass "reconcile's directive says: $phrase" || fail "reconcile's directive says: $phrase"
    OTHERS=$(jq -r --arg p "$phrase" '.states | to_entries[] | select(.key != "reconcile")
        | select(((.value.directive // "") + (.value.details // "")) | contains($p)) | .key' "$J")
    [ -z "$OTHERS" ] && pass "  ... and no other state does" || fail "  ... and no other state does" "$OTHERS"
done
# role_fixture <name> <script> <line>: a skill directory holding a copy of
# <script> (from scripts/, or a new empty one) with <line> appended; prints
# what role_readers reports there, path and form.
role_fixture() {
    rm -rf "$T/roler-$1" && mkdir -p "$T/roler-$1/scripts"
    if [ -f "$HERE/$2" ]; then cp "$HERE/$2" "$T/roler-$1/scripts/"; else printf '#!/usr/bin/env bash\n' > "$T/roler-$1/scripts/$2"; fi
    printf '%s\n' "$3" >> "$T/roler-$1/scripts/$2"
    role_readers "$T/roler-$1" | cut -f1,3 | sort -u
}
eq_fx "a fixture adding .key == \"role\" to land-merge.sh fails" "scripts/land-merge.sh	role-key" \
    "$(role_fixture lm land-merge.sh "R=\$(jq -r '[.run[] | select(.key == \"role\") | .value][0]' \"\$F\")")"
eq_fx "a fixture adding run_has role director to rebrief-record.sh fails" "scripts/rebrief-record.sh	role-key" \
    "$(role_fixture rb rebrief-record.sh 'run_has role director && echo yes')"
eq_fx "a fixture adding runval(\"role\") to a listed reader fails" "scripts/pick-facts.sh	role-key" \
    "$(role_fixture pf pick-facts.sh "jq -r 'runval(\"role\")' \"\$F\"")"
eq_fx "a fixture calling state-read.sh --run from a script not on the list fails" "scripts/posture-read.sh	run-read" \
    "$(role_fixture pr posture-read.sh 'bash "$HERE/state-read.sh" --session "$S" --run > "$T/run.json"')"
eq_fx "a fixture adding a record/run read to a new script fails" "scripts/new-reader.sh	record-run" \
    "$(role_fixture nr new-reader.sh 'koto context get "$S" record/run > "$T/run.json"')"
eq_fx "  ... and to need-check.sh, which reads no record today" "scripts/need-check.sh	record-run" \
    "$(role_fixture nc need-check.sh 'rs_key "$S" record/run "$T/run.json"')"
eq_fx "a record/run read added to a listed reader is its own to keep" "" \
    "$(role_fixture rc reconcile-read.sh 'rs_key "$S" record/run "$T/run.json"')"
eq_fx "a whole read (rs_record, --list) isn't counted by itself" "" \
    "$(role_fixture wr need-check.sh 'rs_record "$T/rec"; bash "$HERE/state-stored-set.sh" --session "$S" --list > "$T/l"')"
# A script with two paths, its allow-list entry naming the function that may read the row.
rm -rf "$T/roler-two" && mkdir -p "$T/roler-two/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'brief_path() {' '    R=$(bash "$HERE/state-read.sh" --session "$S" --run)' \
    "    jq -r '[.[] | select(.key == \"role\") | .value][0]' <<<\"\$R\"" '}' 'grant_path() {' '    G=$(posture)' '}' \
    > "$T/roler-two/scripts/two-path.sh"
eq_fx "a read in the function the list names passes" "" \
    "$(role_readers "$T/roler-two" "scripts/two-path.sh:brief_path" "" | cut -f1,2,3)"
printf '%s\n' 'grant_path_role() {' "    jq -r '[.run[] | select(.key == \"role\")][0]' \"\$F\"" '}' >> "$T/roler-two/scripts/two-path.sh"
eq_fx "  ... and one in another function of that script fails" "scripts/two-path.sh	grant_path_role	role-key" \
    "$(role_readers "$T/roler-two" "scripts/two-path.sh:brief_path" "" | cut -f1,2,3)"
printf '%s\n' 'koto context get "$S" record/run > "$T/r"' >> "$T/roler-two/scripts/two-path.sh"
eq_fx "  ... as does one outside any function, even for a listed reader" \
    "scripts/two-path.sh	-	record-run
scripts/two-path.sh	grant_path_role	role-key" \
    "$(role_readers "$T/roler-two" "scripts/two-path.sh:brief_path" "scripts/two-path.sh" | cut -f1,2,3 | sort)"

# No script passes --role to niwa dispatch, whose own --role grants
# authorities: not on the dispatch command, not in an array that command
# expands, and not through a helper that appends to one (launch_flag).
cat > "$T/dispatch-role.awk" <<'AWK'
function has_role(s) { return s ~ /(^|[^A-Za-z0-9_-])--role([^A-Za-z0-9_-]|$)/ }
NR == FNR {
    line = $0
    if (line ~ /^[[:space:]]*#/) { cmd = ""; next }
    fn = (n > 0 ? names[n] : "-")
    if (match(line, /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/)) {
        def = substr(line, RSTART, RLENGTH)
        ind = def; sub(/[^[:space:]].*$/, "", ind)
        name = def; sub(/^[[:space:]]*(function[[:space:]]+)?/, "", name); sub(/[[:space:]]*\(.*$/, "", name)
        fn = name
        if (substr(line, RSTART + RLENGTH) !~ /\}[[:space:]]*;?[[:space:]]*$/) { n++; names[n] = name; inds[n] = ind }
    } else if (n > 0 && line ~ ("^" inds[n] "\\}")) {
        n--
    }
    # Each array a line appends to or sets, by function.
    s = line
    while (match(s, /(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*\+?=\(/)) {
        a = substr(s, RSTART, RLENGTH); sub(/^[^A-Za-z_]/, "", a); sub(/\+?=\($/, "", a)
        sets[fn SUBSEP a] = 1
        s = substr(s, RSTART + RLENGTH)
    }
    # A command continued over lines is read whole.
    cmd = cmd " " line
    if (line ~ /\\$/) next
    if (cmd ~ /(niwa|NIWA)[}"']*[[:space:]]+dispatch([[:space:]]|$)/) {
        if (has_role(cmd)) print FILENAME ":" FNR ": --role on the niwa dispatch command"
        s = cmd
        while (match(s, /\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]/)) {
            a = substr(s, RSTART + 2, RLENGTH - 5); arr[a] = 1
            s = substr(s, RSTART + RLENGTH)
        }
    }
    cmd = ""
    next
}
FNR == 1 {
    for (k in sets) { split(k, kk, SUBSEP); if ((kk[2] in arr) && kk[1] != "-") helper[kk[1]] = 1 }
}
{
    line = $0
    if (line ~ /^[[:space:]]*#/ || !has_role(line)) next
    for (a in arr) if (line ~ ("(^|[^A-Za-z0-9_])" a "\\+?=\\(")) { print FILENAME ":" FNR ": --role into " a ", which niwa dispatch is given"; next }
    for (h in helper) if (line ~ ("(^|[^A-Za-z0-9_])" h "([[:space:]]|$)") && line !~ ("^[[:space:]]*" h "[[:space:]]*\\(\\)")) {
        print FILENAME ":" FNR ": --role through " h ", which feeds niwa dispatch"; next
    }
}
AWK
dispatch_role() {
    local f
    find "$1" -type f -name '*.sh' ! -name '*_test.sh' ! -path '*/testdata/*' | LC_ALL=C sort | while IFS= read -r f; do
        awk -f "$T/dispatch-role.awk" "$f" "$f" || echo "$f: the check couldn't read it"
    done
}
DR=$(dispatch_role "$HERE/..")
[ -z "$DR" ] && pass "no script under skills/coordinate passes --role to niwa dispatch" \
    || fail "no script under skills/coordinate passes --role to niwa dispatch" "$DR"
rm -rf "$T/dispr" && mkdir -p "$T/dispr" && cp "$HERE/dispatch-worker.sh" "$T/dispr/a.sh" && cp "$HERE/dispatch-worker.sh" "$T/dispr/b.sh"
printf '%s\n' 'launch_flag --role --role manager' >> "$T/dispr/a.sh"
printf '%s\n' 'LAUNCH_ARGS+=(--role "$ROLE")' >> "$T/dispr/b.sh"
printf '%s\n' '#!/usr/bin/env bash' 'dc_with_deadline 30 "$NIWA" dispatch "$PROMPT" --name "$TOPIC" \' '    --role director --detach' > "$T/dispr/c.sh"
printf '%s\n' '#!/usr/bin/env bash' 'PROMPT="Run /shirabe:coordinate x --role manager"' '"$NIWA" dispatch "$PROMPT" --name "$TOPIC" --detach' > "$T/dispr/d.sh"
eq_fx "the check names --role through launch_flag, into LAUNCH_ARGS and on the command, not in the prompt" "a.sh b.sh c.sh" \
    "$(dispatch_role "$T/dispr" | sed 's|^.*/||; s|:.*||' | sort -u | tr '\n' ' ' | sed 's/ $//')"

# Every call that writes an outward kind names where the entry goes:
# state-entry.sh refuses one without --on (exit 65). The kinds are its own
# OUTWARD_KINDS, and each code span in the templates, SKILL.md and the
# references that passes --kind <outward kind> must pass --on too.
OUTWARD=$(sed -n 's/^OUTWARD_KINDS=" *\(.*[^ ]\) *"$/\1/p' "$HERE/state-entry.sh")
# outward_without_on <file>...: file:line and span of each such call with no
# --on. awk, not perl: run-tests.sh's PATH holds only the declared tools and
# the POSIX utilities. With RS a backtick, each record is the text between two
# backticks, so a call inside a fenced block is judged by the whole block.
outward_without_on() {
    awk -v kinds="$OUTWARD" 'BEGIN { RS = "`"; gsub(/ +/, "|", kinds); kre = "--kind[ \t\n]+(" kinds ")[^A-Za-z0-9_-]" }
        FNR == 1 { line = 1 }
        {
            s = $0 " "
            if (s !~ /--on[^A-Za-z0-9_-]/) {
                off = 0; rest = s
                while (match(rest, kre)) {
                    pre = substr(s, 1, off + RSTART - 1); nl = gsub(/\n/, "", pre)
                    span = $0; gsub(/[ \t\n]+/, " ", span)
                    printf "%s:%d: %s\n", FILENAME, line + nl, span
                    off += RSTART + RLENGTH - 1; rest = substr(s, off + 1)
                }
            }
            t = $0; line += gsub(/\n/, "", t)
        }' "$@"
}
case " $OUTWARD " in *" goal-fit "*) pass "state-entry.sh's outward kinds are read" ;; *) fail "state-entry.sh's outward kinds are read" "$OUTWARD" ;; esac
NOON=$(outward_without_on "$HERE"/../koto-templates/*.md "$HERE/../SKILL.md" "$HERE"/../references/*.md)
[ -z "$NOON" ] && pass "every outward-kind state-entry.sh call passes --on" || fail "every outward-kind state-entry.sh call passes --on" "$NOON"
mkdir -p "$T/outward"
printf '%s\n' 'Post it:' '`state-entry.sh --kind goal-fit --text-file f`.' 'Record it: `state-entry.sh --kind milestone-verdict --on none --text-file f`.' \
    'Count it: `state-entry.sh --kind work --text-file f`.' > "$T/outward/coordinate.md"
[ "$(outward_without_on "$T/outward/coordinate.md")" = "$T/outward/coordinate.md:2: state-entry.sh --kind goal-fit --text-file f" ] \
    && pass "the check names an outward-kind call with no --on" \
    || fail "the check names an outward-kind call with no --on" "$(outward_without_on "$T/outward/coordinate.md")"

grep -qiE 'the human merges|a person merges' "$TPL" "$HERE/../SKILL.md" && fail "nothing says the human merges" || pass "nothing says the human merges"
for r in loop.md brief-template.md verification-checklist.md state-keys.md; do
    n=$(jq -r --arg r "$r" '[.states[] | select(((.directive // "") + (.details // "")) | contains("references/" + $r))] | length' "$J")
    [ "$n" -gt 0 ] && pass "a state names references/$r" || fail "a state names references/$r"
done
for d in pick.choice classify_report.classification decision_verdict.verdict; do
    st=${d%%.*}; fld=${d#*.}
    jq -e --arg s "$st" --arg f "$fld" '.states[$s].accepts[$f].decider != null' "$J" >/dev/null && pass "$d carries a decider" || fail "$d carries a decider"
    [ -f "$HERE/../koto-templates/coordinate.$d.decider.jsonl" ] && pass "$d has fixtures" || fail "$d has fixtures"
done
TERMS=$(jq -r '.states | to_entries[] | select(.value.terminal == true) | .key' "$J" | sort | tr '\n' ' ')
[ "$TERMS" = "done done_handed_over done_not_active done_stopped " ] && pass "the terminals are the four the report names" || fail "the terminals are the four the report names" "$TERMS"
RK=$(jq -r '[.states[] | select(.terminal == true) | (.result // {} | keys | sort | join(","))] | unique | join(";")' "$J")
[ "$RK" = "host,outcome,record,scope" ] && pass "every terminal's result carries outcome, scope, host, record" || fail "every terminal's result carries outcome, scope, host, record" "$RK"
echo; echo "coordinate template structure: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
