#!/usr/bin/env bash
# run-evals_test.sh -- test harness for scripts/run-evals.sh's nested session:
# the permission mode it pins, and the failure it reports when that session
# ends without executing anything.
#
# Usage: bash scripts/run-evals_test.sh
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# No model is called. A stub claude (scripts/run-evals/fixtures/bin/claude) is
# put first on PATH; it records the arguments, prompt, working directory and
# TMPDIR it was started with, and replays a fixture transcript. The runner is
# pointed at a throwaway suite through RUN_EVALS_SKILLS_DIR, so no iteration is
# written into this checkout.
#
# Two groups:
#   classifier cases run scripts/lib/classify-eval-session.py against the
#   fixture transcripts directly;
#   runner cases run scripts/run-evals.sh end to end against the stub.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
RUNNER="$SCRIPT_DIR/run-evals.sh"
CLASSIFY="$SCRIPT_DIR/lib/classify-eval-session.py"
FIXTURES="$SCRIPT_DIR/run-evals/fixtures"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/run-evals-test.XXXXXX")
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

RC=0
OUT=""

# -- classifier -------------------------------------------------------------

classify() { # classify <command> <transcript> [<requested-mode>]
  RC=0
  OUT=$(python3 "$CLASSIFY" "$@" 2>&1) || RC=$?
}

field() { # field <name> -- read one field of the last verdict JSON in OUT
  printf '%s' "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)[sys.argv[1]])" "$1"
}

# The four fixtures are real captures (see each file's header). The inline
# transcripts further down are hand-written, and only for shapes no real run
# has produced here: an ExitPlanMode, a denial with no denial record.

classify verdict "$FIXTURES/plan-mode.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = not_executed ] \
  && [ "$(field permission_mode)" = plan ] \
  && [ "$(field executing_calls_ran)" = 2 ]; then
  pass "real plan-mode session: not_executed although its read-only command and plan-file Write ran"
else
  fail "plan-mode transcript (rc=$RC): $OUT"
fi

classify verdict "$FIXTURES/all-denied.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = not_executed ] \
  && [ "$(field executing_calls)" = 3 ] && [ "$(field permission_denials)" = 3 ] \
  && [ "$(field executing_calls_ran)" = 0 ]; then
  pass "real all-denied session: three calls, three denials, not_executed"
else
  fail "all-denied transcript (rc=$RC): $OUT"
fi

classify verdict "$FIXTURES/all-failed.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = executed ] \
  && [ "$(field executing_calls_ran)" = 2 ] && [ "$(field permission_denials)" = 0 ]; then
  pass "real session whose every command exited nonzero: executed (exit 2 territory, not 4)"
else
  fail "all-failed transcript (rc=$RC): $OUT"
fi

classify verdict "$FIXTURES/executed.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = executed ] \
  && [ "$(field permission_mode)" = acceptEdits ] \
  && [ "$(field executing_calls_ran)" = 2 ]; then
  pass "real graded run: a subagent's Write and the parent's Bash both count; later inits ignored"
else
  fail "executed transcript (rc=$RC): $OUT"
fi

classify verdict "$FIXTURES/executed.jsonl"
if printf '%s' "$(field result_text)" | grep -q "^I ran iteration 2"; then
  pass "real graded run: the final message is the last of its three result messages"
else
  fail "executed transcript final message: $(field result_text)"
fi

cat > "$T/exit-plan-then-stop.jsonl" <<'EOF'
{"type":"system","subtype":"init","permissionMode":"acceptEdits"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_e1","name":"Bash","input":{"command":"ls"}}]},"parent_tool_use_id":null}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_e1","type":"tool_result","content":"a","is_error":false}]},"parent_tool_use_id":null}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_e2","name":"ExitPlanMode","input":{"plan":"p"}}]},"parent_tool_use_id":null}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_e2","type":"tool_result","content":"not approved","is_error":true}]},"parent_tool_use_id":null}
{"type":"result","subtype":"success","result":"stopped","permission_denials":[]}
EOF
classify verdict "$T/exit-plan-then-stop.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = not_executed ] && [ "$(field exit_plan_mode)" = True ]; then
  pass "ExitPlanMode outside plan mode with nothing run after it: not_executed"
else
  fail "exit-plan-then-stop (rc=$RC): $OUT"
fi

cat > "$T/exit-plan-then-run.jsonl" <<'EOF'
{"type":"system","subtype":"init","permissionMode":"acceptEdits"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_r1","name":"ExitPlanMode","input":{"plan":"p"}}]},"parent_tool_use_id":null}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_r1","type":"tool_result","content":"ok","is_error":false}]},"parent_tool_use_id":null}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_r2","name":"Bash","input":{"command":"python3 grade.py"}}]},"parent_tool_use_id":null}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_r2","type":"tool_result","content":"Exit code 1","is_error":true}]},"parent_tool_use_id":null}
{"type":"result","subtype":"success","result":"ran","permission_denials":[]}
EOF
classify verdict "$T/exit-plan-then-run.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = executed ]; then
  pass "ExitPlanMode outside plan mode followed by a command that ran: executed"
else
  fail "exit-plan-then-run (rc=$RC): $OUT"
fi

# Cut short before any denial record: the tool-result text is the fallback.
cat > "$T/denied-text-only.jsonl" <<'EOF'
{"type":"system","subtype":"init","permissionMode":"acceptEdits"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_t1","name":"Bash","input":{"command":"gh pr list"}}]},"parent_tool_use_id":null}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_t1","type":"tool_result","content":"This command requires approval","is_error":true}]},"parent_tool_use_id":null}
EOF
classify verdict "$T/denied-text-only.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = not_executed ] && [ "$(field permission_denials)" = 1 ]; then
  pass "a denial with no denial record is recognised by its text"
else
  fail "denied-text-only (rc=$RC): $OUT"
fi

# A session with background agents ends each turn with its own result message.
# A denial recorded in an earlier one still counts, and the final message is
# the last one.
cat > "$T/multi-result.jsonl" <<'EOF'
{"type":"system","subtype":"init","permissionMode":"acceptEdits"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_m1","name":"Bash","input":{"command":"gh pr list"}}]},"parent_tool_use_id":null}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_m1","type":"tool_result","content":"denied"}]},"parent_tool_use_id":null}
{"type":"result","subtype":"success","result":"first turn","permission_denials":[{"tool_name":"Bash","tool_use_id":"toolu_m1"}],"parent_tool_use_id":null}
{"type":"result","subtype":"success","result":"final turn","permission_denials":[],"parent_tool_use_id":null}
EOF
classify verdict "$T/multi-result.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = not_executed ] \
  && [ "$(field permission_denials)" = 1 ] && [ "$(field result_text)" = "final turn" ]; then
  pass "several result messages: every denial counts, the last message is the final one"
else
  fail "several result messages (rc=$RC): $OUT"
fi

: > "$T/empty.jsonl"
classify verdict "$T/empty.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = unknown ]; then
  pass "empty transcript: unknown, not a claim either way"
else
  fail "empty transcript (rc=$RC): $OUT"
fi

classify report "$FIXTURES/plan-mode.jsonl" acceptEdits
if [ "$RC" -eq 4 ] \
  && printf '%s' "$OUT" | grep -q "NESTED SESSION DID NOT EXECUTE" \
  && printf '%s' "$OUT" | grep -q "Permission mode in effect: plan" \
  && printf '%s' "$OUT" | grep -q "Permission mode requested: acceptEdits"; then
  pass "report on plan-mode: exit 4, named failure, mode in effect and mode requested"
else
  fail "report on plan-mode (rc=$RC): $OUT"
fi

classify report "$FIXTURES/executed.jsonl" acceptEdits
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  pass "report on executed: exit 0, silent"
else
  fail "report on executed (rc=$RC): $OUT"
fi

classify report "$FIXTURES/executed.jsonl" dontAsk
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "ran in permission mode acceptEdits, not the dontAsk"; then
  pass "report on executed in another mode: exit 0, with a note naming both modes"
else
  fail "report on a mode mismatch (rc=$RC): $OUT"
fi

classify report "$T/missing.jsonl" acceptEdits
if [ "$RC" -eq 2 ] && ! printf '%s' "$OUT" | grep -q "NESTED SESSION DID NOT EXECUTE"; then
  pass "report on a missing transcript: exit 2, no not-executed claim"
else
  fail "report on a missing transcript (rc=$RC): $OUT"
fi

classify result-text "$FIXTURES/plan-mode.jsonl"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "started in plan mode"; then
  pass "result-text prints the session's final message"
else
  fail "result-text (rc=$RC): $OUT"
fi

# -- runner -----------------------------------------------------------------

SUITE="$T/skills"
mkdir -p "$SUITE/demo/evals" "$SUITE/live/evals"
echo "# demo skill" > "$SUITE/demo/SKILL.md"
cat > "$SUITE/demo/evals/evals.json" <<'EOF'
{"skill_name": "demo", "evals": [
  {"id": 1, "name": "demo-scenario", "prompt": "do the thing",
   "expected_output": "the thing is done", "files": [],
   "expectations": ["stub criterion"]}
]}
EOF
mkdir -p "$SUITE/pair/evals"
echo "# pair skill" > "$SUITE/pair/SKILL.md"
cat > "$SUITE/pair/evals/evals.json" <<'EOF'
{"skill_name": "pair", "evals": [
  {"id": 1, "name": "first-scenario", "prompt": "one", "expected_output": "one",
   "files": [], "expectations": ["stub criterion"]},
  {"id": 2, "name": "second-scenario", "prompt": "two", "expected_output": "two",
   "files": [], "expectations": ["stub criterion"]}
]}
EOF
echo "# live skill" > "$SUITE/live/SKILL.md"
# No "tier": 2 here, although the real liveness evals declare it: tier 2 makes
# the runner clone and push this checkout, which fails on a detached CI
# checkout and is not what this case tests. The liveness instruction keys on
# "preflight": "live" alone.
cat > "$SUITE/live/evals/evals.json" <<'EOF'
{"skill_name": "live", "evals": [
  {"id": 1, "name": "liveness", "mode": "execute",
   "preflight": "live", "preflight_skill": "some-skill",
   "prompt": "load the fixture plugin", "expected_output": "a report",
   "files": [], "expectations": ["stub criterion"]}
]}
EOF

LOG="$T/log"

run_runner() { # run_runner <stub-mode> <runner args...>
  local mode="$1"
  shift
  rm -rf "$LOG"
  RC=0
  OUT=$(cd "$T" && RUN_EVALS_SKILLS_DIR="$SUITE" STUB_CLAUDE_MODE="$mode" \
    STUB_CLAUDE_LOG_DIR="$LOG" PATH="$FIXTURES/bin:$PATH" TMPDIR="$T" \
    bash "$RUNNER" "$@" 2>&1) || RC=$?
}

# arg_after <flag> -- the argument that followed <flag> in the stub's argv
arg_after() {
  awk -v f="$1" 'prev == f { print; exit } { prev = $0 }' "$LOG/args"
}

run_runner plan demo
if [ "$RC" -eq 4 ] \
  && printf '%s' "$OUT" | grep -q "NESTED SESSION DID NOT EXECUTE" \
  && printf '%s' "$OUT" | grep -q "Permission mode in effect: plan"; then
  pass "runner: a session that only planned exits 4 and names the mode in effect"
else
  fail "runner, plan-mode session (rc=$RC): $OUT"
fi

# The flags. The stub was started from $T, so a cwd of the repo root proves the
# runner moved there rather than inheriting the operator's directory.
if [ "$(arg_after --permission-mode)" = acceptEdits ] \
  && [ "$(arg_after --allowedTools)" = Bash ] \
  && grep -qx -- "--output-format" "$LOG/args" \
  && [ "$(arg_after --output-format)" = stream-json ]; then
  pass "runner: passes --permission-mode acceptEdits --allowedTools Bash, stream-json"
else
  fail "runner flags: $(tr '\n' ' ' < "$LOG/args")"
fi

scratch=$(arg_after --add-dir)
if [ -n "$scratch" ] && [ "$(cat "$LOG/tmpdir")" = "$scratch" ] \
  && [ "$(cat "$LOG/cwd")" = "$REPO_ROOT" ]; then
  pass "runner: --add-dir is the session's TMPDIR, and the session runs from the repo root"
else
  fail "runner scratch/cwd: add-dir=$scratch tmpdir=$(cat "$LOG/tmpdir") cwd=$(cat "$LOG/cwd")"
fi

if [ -n "$scratch" ] && [ ! -e "$scratch" ]; then
  pass "runner: removes the scratch root after the run"
else
  fail "runner left the scratch root behind: $scratch"
fi

if grep -q "This session runs with: --permission-mode acceptEdits --allowedTools Bash --add-dir $scratch" "$LOG/prompt"; then
  pass "runner: tells the session its permissions and scratch directory"
else
  fail "runner prompt lacks the permissions block"
fi

transcript=$(ls "$SUITE"/demo/evals/workspace/iteration-*/runner_session.jsonl 2>/dev/null | tail -n 1)
if [ -n "$transcript" ] && cmp -s "$transcript" "$FIXTURES/plan-mode.jsonl"; then
  pass "runner: saves the session transcript in the iteration directory"
else
  fail "runner transcript not saved where expected: '$transcript'"
fi

run_runner failed demo
if [ "$RC" -eq 2 ] && ! printf '%s' "$OUT" | grep -q "NESTED SESSION DID NOT EXECUTE"; then
  pass "runner: a session whose commands all ran and failed stays exit 2, not 4"
else
  fail "runner, all-failed session (rc=$RC): $OUT"
fi

run_runner denied demo
if [ "$RC" -eq 4 ] && printf '%s' "$OUT" | grep -q "Permission denials: 3"; then
  pass "runner: a session whose every call was denied exits 4"
else
  fail "runner, all-denied session (rc=$RC): $OUT"
fi

run_runner nograde demo
if [ "$RC" -eq 2 ] && ! printf '%s' "$OUT" | grep -q "NESTED SESSION DID NOT EXECUTE" \
  && printf '%s' "$OUT" | grep -q "ZERO-GRADED SCENARIOS"; then
  pass "runner: a session that executed but graded nothing stays exit 2, not 4"
else
  fail "runner, executed-but-ungraded (rc=$RC): $OUT"
fi

# Validation also exits 2 when some scenarios graded and others did not. A
# grade on disk means the session ran, so even a plan-mode-looking transcript
# must not turn that into "no scenario ran".
run_runner partial pair
if [ "$RC" -eq 2 ] && ! printf '%s' "$OUT" | grep -q "NESTED SESSION DID NOT EXECUTE" \
  && printf '%s' "$OUT" | grep -q "Evals graded:   1"; then
  pass "runner: a partly graded run stays exit 2 whatever the transcript says"
else
  fail "runner, partly graded (rc=$RC): $OUT"
fi

run_runner grade demo
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "All assertions passed." \
  && printf '%s' "$OUT" | grep -q "I ran iteration 2 of the writing-style evals"; then
  pass "runner: a graded run exits 0 and prints the session's final message"
else
  fail "runner, graded session (rc=$RC): $OUT"
fi

run_runner plan --runs 3 demo
if [ "$RC" -eq 4 ] && printf '%s' "$OUT" | grep -q "Stopping after run 1: the nested session did not execute"; then
  pass "runner: --runs stops at the first not-executed run"
else
  fail "runner, --runs on a not-executed session (rc=$RC): $OUT"
fi

run_runner plan live
if grep -q "claude --permission-mode acceptEdits --allowedTools Bash --plugin-dir" "$LOG/prompt"; then
  pass "runner: the liveness eval's own nested claude gets the same permission flags"
else
  fail "runner: liveness instruction lacks the permission flags"
fi

# --prep-only and --validate are what skills PRs use in the meantime; neither
# may start a session.
run_runner plan --prep-only demo
if [ "$RC" -eq 0 ] && [ ! -e "$LOG/args" ] && printf '%s' "$OUT" | grep -q "Workspace ready."; then
  pass "--prep-only prepares a workspace and starts no session"
else
  fail "--prep-only (rc=$RC, session started: $([ -e "$LOG/args" ] && echo yes || echo no)): $OUT"
fi

latest=$(ls -d "$SUITE"/demo/evals/workspace/iteration-* | sort -t- -k2 -n | tail -n 1)
mkdir -p "$latest/demo-scenario/with_skill/outputs" "$latest/demo-scenario/without_skill/outputs"
echo x > "$latest/demo-scenario/with_skill/outputs/response.md"
echo x > "$latest/demo-scenario/without_skill/outputs/response.md"
echo '{"expectations": [{"text": "stub criterion", "passed": true}]}' > "$latest/demo-scenario/with_skill/grading.json"
run_runner plan --validate demo
if [ "$RC" -eq 0 ] && [ ! -e "$LOG/args" ] && printf '%s' "$OUT" | grep -q "All assertions passed."; then
  pass "--validate grades the latest iteration and starts no session"
else
  fail "--validate (rc=$RC): $OUT"
fi

rm -f "$latest/demo-scenario/with_skill/grading.json"
run_runner plan --validate demo
if [ "$RC" -eq 2 ] && ! printf '%s' "$OUT" | grep -q "NESTED SESSION DID NOT EXECUTE"; then
  pass "--validate on an ungraded iteration stays exit 2 (it has no session to classify)"
else
  fail "--validate ungraded (rc=$RC): $OUT"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
