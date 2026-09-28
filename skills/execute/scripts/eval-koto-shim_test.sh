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
#     with its terminal, and every call is logged
#   `context add` / `context exists` round-trip with session state, and stay
#     unmatched without it
#   evidence no fixture answers fails as no match
#   the drift-intent-changing assignment is the one execute.md makes
#   the older work-on arm still answers
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

if grep -qx "next $WF --with-data @$EVIDENCE --no-cleanup" "$LOG" \
    && grep -qx "context get $WF failure_reason" "$LOG"; then
    pass "every call is appended to KOTO_CALL_LOG"
else
    fail "the call log is missing calls: $(tr '\n' '|' < "$LOG")"
fi

# The assignment the fixture makes is the one execute.md makes.
want=$(grep -F 'failure_reason: "worktree_discipline_check: upstream-drift detected (intent-changing): ${evidence.rationale}"' "$TEMPLATE" | wc -l | tr -d ' ')
fixture=$(jq -r .failure_reason "$FIXTURES/scenarios/$SC/koto-next-execute-impact-intent-changing.context.json")
if [ "$want" = 1 ] && [ "$fixture" = 'worktree_discipline_check: upstream-drift detected (intent-changing): ${evidence.rationale}' ]; then
    pass "the fixture's failure_reason assignment matches execute.md's worktree_discipline_check edge"
else
    fail "fixture assignment [$fixture], template matches [$want]"
fi

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

k "$SC" "$WORK/nomatch.log" next "$WF" --with-data '{"impact":"informational"}' --no-cleanup >/dev/null 2>&1
[ $? -eq 1 ] && pass "evidence with no fixture fails as no match" \
    || fail "evidence with no fixture did not fail"

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

# --- the older work-on arm ---------------------------------------------------

got=$(k e2e-plan-happy "" next work-on-probe --no-cleanup | jq -c . 2>/dev/null)
want=$(jq -c . "$FIXTURES/scenarios/e2e-plan-happy/koto-next-work-on.json")
[ -n "$got" ] && [ "$got" = "$want" ] && pass "the work-on arm still answers koto-next-work-on.json" \
    || fail "work-on arm answered [$got]"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
