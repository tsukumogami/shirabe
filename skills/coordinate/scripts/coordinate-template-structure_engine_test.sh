#!/usr/bin/env bash
# coordinate-template-structure_engine_test.sh -- guarantees over coordinate.md,
# checked on the compiled template (koto template compile) and its source.
#
# Proves the check-state contract holds for every state with a default action:
# no accepts block (evidence can't skip the read), no polling or confirmation,
# every gate overridable: false, the only command gate is coord-verdict.sh over
# the state's own capture, and a context gate appears only as a decider input
# (context-exists). One command gate reads another state's capture on purpose:
# report_questions' report_holding re-reads report_facts' sealed verdict, the
# one report_facts routed on, to send a report with no questions on to
# classification only when it had a holding. Also: the design's decision
# states and edges exist; no cycle is made of check states only; the state set is the design's; no write script
# (record-open, record-write, record-holding, rotation-close, land-merge,
# merge-exec) appears in any default action or gate; no directive names
# merge-exec.sh; no check script calls `gh api` without --method GET (GraphQL
# queries aside) or sends a GraphQL mutation; nothing says the human merges;
# every reference file is named by a state; the three deciders are declared
# with their inputs gated.
#
# Needs koto (to compile) and jq; SKIPs without koto, which
# run-tests.sh --engine turns into a failure.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TPL="$HERE/../koto-templates/coordinate.md"
for b in koto jq; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/coord-structure.XXXXXX"); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
J=$(koto template compile "$TPL" 2>/dev/null) || { echo "FAIL: coordinate.md does not compile"; exit 1; }

WANT="ask_up classify_report decision_answer decision_apply decision_carry decision_evidence decision_next decision_open decision_raise decision_redirect decision_redirect_send decision_reply decision_reply_send decision_take decision_verdict decision_withdraw decision_withdraw_send deferral_dispose destroy dispatch dispatch_check done done_handed_over done_not_active done_stopped escalate escalate_send failure land land_merge leg_pick merge_confirm merged_facts pick pick_facts posture_ask predecessor_close predecessor_done predecessor_handed_over predecessor_handoff predecessor_step promote quiet_check rebrief reconcile reconcile_pass record record_conflict record_find record_open report_facts report_questions roadmap_blocked roadmap_close roadmap_close_step rotation_close rotation_done rotation_step start start_posture status_message surface surface_check take_report teardown teardown_inventory verified_confirm verify verify_board wait wait_leg"
GOT=$(jq -r '.states | keys[]' "$J" | sort | tr '\n' ' ' | sed 's/ $//')
[ "$GOT" = "$WANT" ] && pass "the state set is the design's" || fail "the state set is the design's" "$(diff <(echo "$WANT" | tr ' ' '\n') <(echo "$GOT" | tr ' ' '\n'))"

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
          elif .value.type == "context-exists" and ((.value.key | test("^coord/(pick|report|decision)\\.json$")) | not) then "\($s).\(.key): a context gate that is not a decider input"
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

# The design's decision states and changed edges, as from>to pairs.
EDGES='decision_next>decision_carry decision_next>decision_open decision_next>decision_answer
decision_next>decision_evidence decision_next>decision_raise decision_next>decision_withdraw
decision_next>decision_reply decision_next>decision_redirect decision_next>escalate
decision_next>decision_take decision_next>decision_verdict decision_next>classify_report
decision_next>pick_facts decision_next>record_conflict decision_carry>decision_next
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
failure>decision_raise surface>decision_raise surface>surface_check dispatch_check>decision_next'
MISSING=$(for e in $EDGES; do
    jq -e --arg f "${e%%>*}" --arg t "${e#*>}" 'any(.states[$f].transitions[]?; .target == $t)' "$J" >/dev/null || echo "$e"
done)
[ -z "$MISSING" ] && pass "every decision state and edge the design names exists" || fail "every decision state and edge the design names exists" "$MISSING"
for e in report_facts\>classify_report report_facts\>wait failure\>wait surface\>wait; do
    jq -e --arg f "${e%%>*}" --arg t "${e#*>}" 'any(.states[$f].transitions[]?; .target == $t)' "$J" >/dev/null \
        && fail "the edge the design replaced is gone: $e" || pass "the edge the design replaced is gone: $e"
done
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

WRITES=$(jq -r '.states | to_entries[] | .key as $s | [(.value.default_action.command // ""), ((.value.gates // {}) | to_entries[] | .value.command // "")] | .[] | select(test("record-open|record-write|record-write-core|record-holding|record-decision.sh\" --session \"[^\"]*\" --(carry|open|take|settle|escalate|hold|evidence|answer|sent)|rotation-close|land-merge|merge-exec")) | $s' "$J")
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
    grep -qE '^[[:space:]]*(\.|source)[[:space:]]+[^#]*record-write-core' "$f" && fail "$c: sources no write core" || pass "$c: sources no write core"
done
grep -qE '^[[:space:]]*(\.|source)[[:space:]]+[^#]*record-write-core' "$HERE/record-common.sh" && fail "record-common.sh sources no write core" || pass "record-common.sh sources no write core"

# decisions_writers <dir>: every script there, other than record-decision.sh
# and the tests, that opens the Decisions section (sets DECISIONS_WRITER=1).
decisions_writers() {
    grep -lE '^[^#]*DECISIONS_WRITER=1' "$1"/*.sh 2>/dev/null | grep -v '_test\.sh$' | grep -v '/record-decision\.sh$' || true
}
OPENERS=$(decisions_writers "$HERE")
[ -z "$OPENERS" ] && pass "only record-decision.sh opens the Decisions section" || fail "only record-decision.sh opens the Decisions section" "$OPENERS"
grep -qE '^[^#]*DECISIONS_WRITER=1' "$HERE/record-decision.sh" && pass "record-decision.sh opens it" || fail "record-decision.sh opens it"
mkdir -p "$T/openers"
cp "$HERE/record-decision.sh" "$HERE/record-write.sh" "$T/openers/"
printf '\nDECISIONS_WRITER=1\n' >> "$T/openers/record-write.sh"
[ "$(decisions_writers "$T/openers")" = "$T/openers/record-write.sh" ] && pass "the check names another script that opens it" ||
    fail "the check names another script that opens it" "$(decisions_writers "$T/openers")"

grep -qiE 'the human merges|a person merges' "$TPL" "$HERE/../SKILL.md" && fail "nothing says the human merges" || pass "nothing says the human merges"
for r in loop.md brief-template.md verification-checklist.md record-template.md; do
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
