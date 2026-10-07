#!/usr/bin/env bash
# eval-koto-shim_test.sh — the execute evals' koto shim on an execute session
# Part of the execute skill
#
# The drift scenarios grade what the run did after the drift question: the
# state the tick landed on, what `koto status` reports, and the failure_reason
# the run ends with. Those come from the shim's execute-session arm, so this
# harness drives it the way the skill does and pins:
#   a bare `next execute-<slug>` answers the scenario's koto-next-execute.json
#   evidence, inline or as @file, picks koto-next-execute-<field>-<value>.json
#   with KOTO_CALL_LOG set, the tick's state reaches `koto status`, the
#     fixture's context assignments reach `koto context get` with
#     ${evidence.<field>} filled in, a finished session answers later ticks
#     with its terminal, refuses further evidence as koto's terminal_state,
#     and every call is logged
#   state is per scenario, and `init --replace-terminal` on a finished
#     session starts it fresh, so runs sharing a clone don't leak into each
#     other
#   `context add` / `context exists` round-trip with session state, and stay
#     unmatched without it
#   evidence no fixture answers fails as no match
#   the drift-intent-changing assignment is the one execute.md makes
#   the older work-on arm still answers
#   a koto-passthrough scenario goes to EVAL_KOTO_WRAPPER ahead of PATH, and
#     refuses when that wrapper is missing
#
# Usage: eval-koto-shim_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
FIXTURES="$SCRIPT_DIR/../evals/fixtures"
SHIM="$FIXTURES/bin/koto"
TEMPLATE="$SCRIPT_DIR/../koto-templates/execute.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/eval-koto-shim-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

WF=execute-diamond-test

# k <scenario> <log|""> <args...> — the shim, as the eval's PATH gives it.
k() {
    local sc="$1" log="$2"
    shift 2
    if [ -n "$log" ]; then
        EVAL_SCENARIO="$sc" KOTO_CALL_LOG="$log" "$SHIM" "$@"
    else
        (unset KOTO_CALL_LOG; EVAL_SCENARIO="$sc" "$SHIM" "$@")
    fi
}

# --- drift-intent-changing, with session state ------------------------------

LOG="$WORK/ic/koto-calls.log"
mkdir -p "$WORK/ic"
SC=drift-intent-changing

got=$(k "$SC" "$LOG" next "$WF" --no-cleanup | jq -r .state)
[ "$got" = worktree_discipline_check ] \
    && pass "a bare tick answers koto-next-execute.json (worktree_discipline_check)" \
    || fail "a bare tick answered [$got]"

got=$(k "$SC" "$LOG" status "$WF" | jq -c '{current_state, is_terminal}')
[ "$got" = '{"current_state":"worktree_discipline_check","is_terminal":false}' ] \
    && pass "status reports the state the bare tick landed on" \
    || fail "status after the bare tick: [$got]"

got=$(k "$SC" "$LOG" context get "$WF" drift_facts.json | jq -r .route)
[ "$got" = judge ] && pass "the drift_facts.json key fixture still answers" \
    || fail "drift_facts.json route: [$got]"

EVIDENCE="$WORK/ic/evidence.json"
printf '%s' '{"impact":"intent-changing","rationale":"main deleted the PLAN doc"}' > "$EVIDENCE"
resp=$(k "$SC" "$LOG" next "$WF" --with-data @"$EVIDENCE" --no-cleanup)
if [ "$(printf '%s' "$resp" | jq -r '"\(.action) \(.state) \(.result.status)"')" = "done done_blocked failure" ]; then
    pass "impact intent-changing (@file) answers the done_blocked terminal"
else
    fail "the intent-changing tick answered [$(printf '%s' "$resp" | head -c 200)]"
fi

got=$(k "$SC" "$LOG" status "$WF" | jq -c '{current_state, is_terminal, outcome: .result.payload.outcome, step: .result.payload.step}')
[ "$got" = '{"current_state":"done_blocked","is_terminal":true,"outcome":"error","step":"execute:re-evaluation"}' ] \
    && pass "status reports the retained done_blocked with its payload" \
    || fail "status after the terminal: [$got]"

got=$(k "$SC" "$LOG" context get "$WF" failure_reason)
[ "$got" = "worktree_discipline_check: upstream-drift detected (intent-changing): main deleted the PLAN doc" ] \
    && pass "failure_reason carries the origin state and the submitted rationale" \
    || fail "failure_reason: [$got]"

got=$(k "$SC" "$LOG" next "$WF" --no-cleanup | jq -r '"\(.action) \(.state)"')
[ "$got" = "done done_blocked" ] \
    && pass "a later bare tick on the finished session answers its terminal" \
    || fail "a later bare tick answered [$got]"

resp=$(k "$SC" "$LOG" next "$WF" --with-data '{"impact":"intent-changing","rationale":"a second try"}' --no-cleanup); rc=$?
if [ "$rc" -eq 2 ] && [ "$(printf '%s' "$resp" | jq -r .error.code)" = terminal_state ] \
    && [ "$(k "$SC" "$LOG" context get "$WF" failure_reason)" = "worktree_discipline_check: upstream-drift detected (intent-changing): main deleted the PLAN doc" ]; then
    pass "evidence on the finished session is refused as terminal_state (exit 2) and the context is untouched"
else
    fail "evidence on a finished session: rc $rc, [$resp]"
fi

if grep -qx "next $WF --with-data @$EVIDENCE --no-cleanup" "$LOG" \
    && grep -qx "context get $WF failure_reason" "$LOG"; then
    pass "every call is appended to KOTO_CALL_LOG"
else
    fail "the call log is missing calls: $(tr '\n' '|' < "$LOG")"
fi

# The assignments the fixtures make are the ones execute.md makes: the reason
# on worktree_discipline_check's intent-changing edge, and the outcome and
# step on escalate_upstream_drift's edge to done_blocked. Both drift
# scenarios carry the fixture, so both are checked.
want=$(grep -F 'failure_reason: "worktree_discipline_check: upstream-drift detected (intent-changing): ${evidence.rationale}"' "$TEMPLATE" | wc -l | tr -d ' ')
escalate=$(awk '/^  escalate_upstream_drift:$/ { on = 1; next } on && /^  [a-z_]+:$/ { exit } on' "$TEMPLATE")
tpl_outcome=$(printf '%s\n' "$escalate" | sed -n 's/^ *outcome: *//p')
tpl_step=$(printf '%s\n' "$escalate" | sed -n 's/^ *step: *"\(.*\)"$/\1/p')
for sc in drift-intent-changing drift-informational; do
    got=$(jq -c '[.failure_reason, .outcome, .step]' "$FIXTURES/scenarios/$sc/koto-next-execute-impact-intent-changing.context.json")
    exp=$(jq -cn --arg o "$tpl_outcome" --arg s "$tpl_step" \
        '["worktree_discipline_check: upstream-drift detected (intent-changing): ${evidence.rationale}", $o, $s]')
    if [ "$want" = 1 ] && [ -n "$tpl_outcome" ] && [ -n "$tpl_step" ] && [ "$got" = "$exp" ]; then
        pass "$sc: the fixture's assignments match execute.md (failure_reason, outcome $tpl_outcome, step $tpl_step)"
    else
        fail "$sc: fixture assignments $got, template gives $exp (failure_reason lines: $want)"
    fi
done

# --- inline evidence, and evidence no fixture answers -----------------------

LOG2="$WORK/inline/koto-calls.log"
mkdir -p "$WORK/inline"
k "$SC" "$LOG2" next "$WF" --no-cleanup >/dev/null
got=$(k "$SC" "$LOG2" next "$WF" --with-data '{"impact":"intent-changing","rationale":"inline"}' --no-cleanup | jq -r .state)
[ "$got" = done_blocked ] && pass "inline JSON evidence picks the same fixture" \
    || fail "inline evidence answered [$got]"
got=$(k "$SC" "$LOG2" context get "$WF" failure_reason)
[ "$got" = "worktree_discipline_check: upstream-drift detected (intent-changing): inline" ] \
    && pass "inline evidence fills \${evidence.rationale}" \
    || fail "inline failure_reason: [$got]"

# Evidence the current state doesn't take is refused as koto refuses it, with
# the same error, before any fixture is looked up.
refused() {
    # $1 label, $2 evidence, $3 expected .error.details[0] as compact JSON
    local resp rc
    resp=$(k "$SC" "$WORK/refuse.log" next "$WF" --with-data "$2" --no-cleanup); rc=$?
    if [ "$rc" -eq 2 ] && [ "$(printf '%s' "$resp" | jq -c '[.error.code, .error.details[0]]')" = "[\"invalid_submission\",$3]" ]; then
        pass "$1 is refused as invalid_submission (exit 2)"
    else
        fail "$1: rc $rc, [$resp]"
    fi
}
refused "an unknown field" '{"impact":"informational","status":"override"}' '{"field":"status","reason":"unknown field \"status\""}'
refused "a missing required field" '{"rationale":"only"}' '{"field":"impact","reason":"required field missing"}'
refused "an enum value outside its values" '{"impact":"none"}' '{"field":"impact","reason":"value \"none\" is not in allowed values [\"informational\", \"intent-changing\"]"}'
refused "a non-string enum value" '{"impact":5}' '{"field":"impact","reason":"expected string for enum, got number"}'
refused "a string field given a number" '{"impact":"informational","rationale":5}' '{"field":"rationale","reason":"expected string, got number"}'
# Every problem is reported, in koto's order. This is koto 0.14's own answer
# to the same submission on a state of the same shape.
resp=$(k "$SC" "$WORK/refuse.log" next "$WF" --with-data '{"impact":"bogus","rationale":5,"x":1}' --no-cleanup)
want='{"error":{"code":"invalid_submission","details":[{"field":"x","reason":"unknown field \"x\""},{"field":"impact","reason":"value \"bogus\" is not in allowed values [\"informational\", \"intent-changing\"]"},{"field":"rationale","reason":"expected string, got number"}],"message":"evidence validation failed"}}'
[ "$(printf '%s' "$resp" | jq -c .)" = "$want" ] \
    && pass "several problems are all reported, in koto's order and words" \
    || fail "several problems: [$resp]"

# The wrong answer is accepted and routed, as koto would route it, in each
# scenario -- not refused, which would hand the run a retry real koto doesn't.
LOG6="$WORK/wrong/koto-calls.log"
mkdir -p "$WORK/wrong"
k drift-intent-changing "$LOG6" next "$WF" --no-cleanup >/dev/null
got=$(k drift-intent-changing "$LOG6" next "$WF" --with-data '{"impact":"informational"}' --no-cleanup | jq -r .state)
[ "$got" = spawn_and_await ] \
    && pass "drift-intent-changing: impact informational routes to spawn_and_await" \
    || fail "drift-intent-changing informational answered [$got]"
got=$(k drift-intent-changing "$LOG6" next "$WF" --no-cleanup | jq -r .state)
[ "$got" = spawn_and_await ] \
    && pass "a bare tick answers where the last tick left the session (spawn_and_await)" \
    || fail "bare tick after informational answered [$got]"
resp=$(k drift-intent-changing "$LOG6" next "$WF" --with-data '{"impact":"intent-changing","rationale":"too late"}' --no-cleanup); rc=$?
if [ "$rc" -eq 2 ] && [ "$(printf '%s' "$resp" | jq -r '.error.details[0].field')" = impact ]; then
    pass "a second drift answer at spawn_and_await is refused: that state takes only tasks"
else
    fail "second drift answer at spawn_and_await: rc $rc, [$resp]"
fi
k drift-informational "$LOG6" next "$WF" --no-cleanup >/dev/null
got=$(k drift-informational "$LOG6" next "$WF" --with-data '{"impact":"intent-changing","rationale":"r"}' --no-cleanup | jq -r .state)
[ "$got" = done_blocked ] \
    && pass "drift-informational: impact intent-changing ends at done_blocked" \
    || fail "drift-informational intent-changing answered [$got]"

k drift-informational "$WORK/nomatch.log" next "$WF" --no-cleanup >/dev/null 2>&1
k drift-informational "$WORK/nomatch.log" next "$WF" --with-data '{"impact":"informational"}' --no-cleanup >/dev/null 2>&1
k drift-informational "$WORK/nomatch.log" next "$WF" --with-data '{"tasks":[]}' --no-cleanup >/dev/null 2>&1
[ $? -eq 1 ] && pass "valid evidence with no fixture fails as no match" \
    || fail "valid evidence with no fixture did not fail"
# Words the generic arms match on ("transition", "init ") inside inline
# evidence must not reach them.
k drift-informational "$WORK/nomatch.log" next "$WF" --with-data '{"tasks":[{"name":"transition","description":"init the thing"}]}' --no-cleanup >/dev/null 2>&1
[ $? -eq 1 ] && pass "evidence with no fixture never falls through to the generic arms" \
    || fail "evidence mentioning transition/init was answered by a generic arm"

# --- context add / exists ----------------------------------------------------

LOG3="$WORK/ctx/koto-calls.log"
mkdir -p "$WORK/ctx"
k "$SC" "$LOG3" context exists "$WF" run_id; rc=$?
[ "$rc" -eq 1 ] && pass "context exists answers 1 for a key never added" \
    || fail "context exists on an absent key exited $rc"
printf 'abc123' | k "$SC" "$LOG3" context add "$WF" run_id; rc=$?
if [ "$rc" -eq 0 ] && k "$SC" "$LOG3" context exists "$WF" run_id \
    && [ "$(k "$SC" "$LOG3" context get "$WF" run_id)" = abc123 ]; then
    pass "context add stores a key that exists and get read back"
else
    fail "context add round trip: add exit $rc, get [$(k "$SC" "$LOG3" context get "$WF" run_id 2>&1)]"
fi
printf 'from a file' > "$WORK/ctx/f.txt"
k "$SC" "$LOG3" context add "$WF" notes.md --from-file "$WORK/ctx/f.txt"
[ "$(k "$SC" "$LOG3" context get "$WF" notes.md)" = "from a file" ] \
    && pass "context add --from-file stores the file" \
    || fail "context add --from-file: [$(k "$SC" "$LOG3" context get "$WF" notes.md 2>&1)]"
k "$SC" "$LOG3" context exists "$WF" plan_intent.md \
    && pass "context exists answers 0 for a key the scenario's fixtures hold" \
    || fail "context exists missed a key fixture"

# --- without session state ---------------------------------------------------

got=$(k "$SC" "" next "$WF" --no-cleanup | jq -r .state)
[ "$got" = worktree_discipline_check ] && pass "without KOTO_CALL_LOG a bare tick still answers" \
    || fail "stateless bare tick answered [$got]"
got=$(k "$SC" "" status "$WF" | jq -r .current_state)
[ "$got" = unknown ] && pass "without KOTO_CALL_LOG status keeps its default" \
    || fail "stateless status: [$got]"
printf 'x' | k "$SC" "" context add "$WF" run_id >/dev/null 2>&1
[ $? -eq 1 ] && pass "without KOTO_CALL_LOG context add stays unmatched, as before" \
    || fail "stateless context add did not fail"

# --- drift-informational -----------------------------------------------------

LOG4="$WORK/inf/koto-calls.log"
mkdir -p "$WORK/inf"
k drift-informational "$LOG4" next "$WF" --no-cleanup >/dev/null
resp=$(k drift-informational "$LOG4" next "$WF" --with-data '{"impact":"informational"}' --no-cleanup)
if [ "$(printf '%s' "$resp" | jq -r .state)" = spawn_and_await ] \
    && printf '%s' "$resp" | jq -r .directive | grep -q 'PLAN-diamond-test.md'; then
    pass "drift-informational: impact informational answers spawn_and_await for the diamond PLAN"
else
    fail "drift-informational answered [$(printf '%s' "$resp" | head -c 200)]"
fi
[ "$(k drift-informational "$LOG4" status "$WF" | jq -r .current_state)" = spawn_and_await ] \
    && pass "drift-informational: status reports spawn_and_await" \
    || fail "drift-informational status: [$(k drift-informational "$LOG4" status "$WF")]"

# --- one clone, several runs -------------------------------------------------
#
# The drift evals share a clone, a call log and a session name, so a finished
# run must not answer for the next scenario, or for a run that enters afresh.

LOG5="$WORK/shared/koto-calls.log"
mkdir -p "$WORK/shared"
k drift-intent-changing "$LOG5" next "$WF" --no-cleanup >/dev/null
k drift-intent-changing "$LOG5" next "$WF" --with-data '{"impact":"intent-changing","rationale":"r"}' --no-cleanup >/dev/null
got=$(k drift-informational "$LOG5" next "$WF" --no-cleanup | jq -r .state)
[ "$got" = worktree_discipline_check ] \
    && pass "another scenario on the same log and session starts from its own first tick" \
    || fail "drift-informational after drift-intent-changing answered [$got]"

k drift-intent-changing "$LOG5" init "$WF" --template x --attach-live --replace-terminal >/dev/null
got=$(k drift-intent-changing "$LOG5" status "$WF" | jq -r .current_state)
k drift-intent-changing "$LOG5" context exists "$WF" failure_reason; rc=$?
if [ "$got" = unknown ] && [ "$rc" -eq 1 ] \
    && [ "$(k drift-intent-changing "$LOG5" next "$WF" --no-cleanup | jq -r .state)" = worktree_discipline_check ]; then
    pass "init --replace-terminal on a finished session starts it fresh, as koto does"
else
    fail "after init --replace-terminal: status [$got], failure_reason exists rc $rc"
fi

k drift-intent-changing "$LOG5" init "$WF" --template x --attach-live --replace-terminal >/dev/null
[ "$(k drift-intent-changing "$LOG5" status "$WF" | jq -r .current_state)" = worktree_discipline_check ] \
    && pass "init --replace-terminal on a live session keeps it" \
    || fail "init on a live session dropped its state"

# --- the older work-on arm ---------------------------------------------------

got=$(k e2e-plan-happy "" next work-on-probe --no-cleanup | jq -c . 2>/dev/null)
want=$(jq -c . "$FIXTURES/scenarios/e2e-plan-happy/koto-next-work-on.json")
[ -n "$got" ] && [ "$got" = "$want" ] && pass "the work-on arm still answers koto-next-work-on.json" \
    || fail "work-on arm answered [$got]"

# --- passthrough: the eval run's own koto first ------------------------------
#
# A koto-passthrough scenario hands each call to EVAL_KOTO_WRAPPER when the
# runner set it, whatever PATH says, so a reordered PATH can't put the real
# koto (and the real $HOME/.koto) in front of the run's wrapper. Without it,
# the next koto on PATH after the shim answers, as before.
mkdir -p "$WORK/pt/wrapper" "$WORK/pt/onpath"
printf '#!/bin/sh\necho "wrapper $*"\n' > "$WORK/pt/wrapper/koto"
printf '#!/bin/sh\necho "onpath $*"\n' > "$WORK/pt/onpath/koto"
chmod +x "$WORK/pt/wrapper/koto" "$WORK/pt/onpath/koto"
got=$(EVAL_SCENARIO=coord-outline-one-repo EVAL_KOTO_WRAPPER="$WORK/pt/wrapper/koto" \
    PATH="$FIXTURES/bin:$WORK/pt/onpath:$PATH" "$SHIM" session list)
[ "$got" = "wrapper session list" ] && pass "passthrough: EVAL_KOTO_WRAPPER answers ahead of any koto on PATH" \
    || fail "passthrough with a wrapper answered [$got]"
got=$( (unset EVAL_KOTO_WRAPPER; EVAL_SCENARIO=coord-outline-one-repo PATH="$FIXTURES/bin:$WORK/pt/onpath:$PATH" "$SHIM" session list) )
[ "$got" = "onpath session list" ] && pass "passthrough: without one, the next koto on PATH answers" \
    || fail "passthrough without a wrapper answered [$got]"
got=$(EVAL_SCENARIO=coord-outline-one-repo EVAL_KOTO_WRAPPER="$WORK/pt/missing" \
    PATH="$FIXTURES/bin:$WORK/pt/onpath:$PATH" "$SHIM" session list 2>&1); rc=$?
[ "$rc" -eq 127 ] && case "$got" in *"is not executable"*) true ;; *) false ;; esac \
    && pass "passthrough: a wrapper that isn't there refuses (127) instead of falling back to PATH" \
    || fail "passthrough with a missing wrapper: rc=$rc [$got]"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
