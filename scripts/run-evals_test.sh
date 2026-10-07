#!/usr/bin/env bash
# run-evals_test.sh -- test harness for scripts/run-evals.sh: the nested
# session's permission mode, model and environment, the failure it reports when
# that session ends without executing anything, the changed-since-tag
# selection, the --summary-out file and the --runs exit code.
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

# The cases set these themselves; a value from the caller's shell would change
# what the runner does.
unset EVAL_MODEL STUB_CLAUDE_SEQUENCE RUN_EVALS_REPO_ROOT

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

# The session ended while its with-skill agent still ran: it executed, so the
# exit stays 0, but the stopped agent is named with its status, and the one
# that completed is not.
classify verdict "$FIXTURES/agent-stopped.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = executed ] && [ "$(field agents_launched)" = 2 ] \
  && [ "$(field stopped_agents)" = "[{'description': 'With-skill execute eval run', 'status': 'stopped'}]" ]; then
  pass "real stopped-agent session: two agents launched, only the stopped one is listed, with its status"
else
  fail "agent-stopped verdict (rc=$RC): $OUT"
fi
classify report "$FIXTURES/agent-stopped.jsonl" acceptEdits
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "EVAL AGENT DID NOT FINISH" \
  && printf '%s' "$OUT" | grep -q "Did not finish: With-skill execute eval run (status: stopped)" \
  && ! printf '%s' "$OUT" | grep -q "Did not finish: Baseline"; then
  pass "report on a stopped agent: exit 0, named failure, the stopped agent and its status"
else
  fail "report on a stopped agent (rc=$RC): $OUT"
fi
# A session that ran its agents in the foreground and waited: both complete,
# none is listed, and the report says nothing.
classify verdict "$FIXTURES/agents-foreground.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = executed ] && [ "$(field agents_launched)" = 2 ] \
  && [ "$(field stopped_agents)" = "[]" ]; then
  pass "real foreground session: two agents launched, none listed as unfinished"
else
  fail "agents-foreground verdict (rc=$RC): $OUT"
fi
classify report "$FIXTURES/agents-foreground.jsonl" acceptEdits
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  pass "report on a foreground session: exit 0, silent"
else
  fail "report on a foreground session (rc=$RC): $OUT"
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
# The session is told to run its agents in the foreground and wait for all of
# them: a -p session that ends its turn stops any agent still running.
if grep -q "run_in_background set to false" "$LOG/prompt" \
  && grep -q "Never end your turn, and never grade, while an agent you launched is still running" "$LOG/prompt"; then
  pass "runner: the prompt has the session run its agents in the foreground and wait for every one"
else
  fail "runner prompt: no foreground/wait instruction"
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

# -- models -----------------------------------------------------------------

# metadata_model <skill> <scenario> -- the model prep wrote for that scenario
# in the skill's latest iteration.
metadata_model() {
  local dir
  dir=$(ls -d "$SUITE/$1"/evals/workspace/iteration-* | sort -t- -k2 -n | tail -n 1)
  python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('model'))" \
    "$dir/$2/eval_metadata.json"
}

run_runner grade demo
if [ "$RC" -eq 0 ] && ! grep -qx -- "--model" "$LOG/args" \
  && [ "$(metadata_model demo demo-scenario)" = sonnet ] \
  && grep -q "demo-scenario: .*with-skill agent and its baseline agent on model sonnet" "$LOG/prompt"; then
  pass "model: by default the grader session gets no --model, and a tier-1 scenario runs on sonnet"
else
  fail "model default (rc=$RC): --model=$(arg_after --model) metadata=$(metadata_model demo demo-scenario)"
fi

EVAL_MODEL=opus run_runner grade demo
if [ "$RC" -eq 0 ] && [ "$(arg_after --model)" = opus ] \
  && [ "$(metadata_model demo demo-scenario)" = opus ] \
  && grep -q "demo-scenario: .*on model opus" "$LOG/prompt"; then
  pass "model: EVAL_MODEL=opus reaches the grader session, the metadata and the per-eval line"
else
  fail "EVAL_MODEL=opus (rc=$RC): --model=$(arg_after --model) metadata=$(metadata_model demo demo-scenario)"
fi

# The liveness scenario is not tier 1, so by default it inherits the session's
# model: no override in its metadata or its instruction line.
run_runner grade live
if [ "$RC" -eq 0 ] && ! grep -qx -- "--model" "$LOG/args" \
  && [ "$(metadata_model live liveness)" = inherit ] \
  && grep -q "liveness: .*with no model override, so they run on this session's model" "$LOG/prompt"; then
  pass "model: by default a scenario that is not tier 1 inherits the session's model"
else
  fail "model inherit (rc=$RC): metadata=$(metadata_model live liveness)"
fi

EVAL_MODEL=opus run_runner grade live
if [ "$RC" -eq 0 ] && [ "$(arg_after --model)" = opus ] \
  && [ "$(metadata_model live liveness)" = opus ]; then
  pass "model: an explicit EVAL_MODEL also reaches a scenario that is not tier 1"
else
  fail "model inherit with EVAL_MODEL (rc=$RC): metadata=$(metadata_model live liveness)"
fi

# Tier-2 scenarios are checked through --prep-only: a full run would stand up
# the isolated clone, which is not what these cases test.
mkdir -p "$SUITE/tiers/evals"
echo "# tiers skill" > "$SUITE/tiers/SKILL.md"
cat > "$SUITE/tiers/evals/evals.json" <<'EOF'
{"skill_name": "tiers", "evals": [
  {"id": 1, "name": "tier1-scenario", "tier": 1, "mode": "plan_only", "prompt": "one",
   "expected_output": "one", "files": [], "expectations": ["stub criterion"]},
  {"id": 2, "name": "tier2-scenario", "tier": 2, "mode": "execute", "prompt": "two",
   "expected_output": "two", "files": [], "expectations": ["stub criterion"]},
  {"id": 3, "name": "tier2-pinned", "tier": 2, "mode": "execute", "model": "haiku",
   "prompt": "three", "expected_output": "three", "files": [], "expectations": ["stub criterion"]}
]}
EOF
run_runner plan --prep-only tiers
if [ "$RC" -eq 0 ] && [ ! -e "$LOG/args" ] \
  && [ "$(metadata_model tiers tier1-scenario)" = sonnet ] \
  && [ "$(metadata_model tiers tier2-scenario)" = inherit ] \
  && [ "$(metadata_model tiers tier2-pinned)" = haiku ]; then
  pass "model: by default tier 1 gets sonnet, tier 2 inherits, and a tier-2 model key is kept"
else
  fail "model tiers (rc=$RC): t1=$(metadata_model tiers tier1-scenario) t2=$(metadata_model tiers tier2-scenario) pinned=$(metadata_model tiers tier2-pinned)"
fi
EVAL_MODEL=opus run_runner plan --prep-only tiers
if [ "$RC" -eq 0 ] && [ "$(metadata_model tiers tier1-scenario)" = opus ] \
  && [ "$(metadata_model tiers tier2-scenario)" = opus ] \
  && [ "$(metadata_model tiers tier2-pinned)" = haiku ]; then
  pass "model: with EVAL_MODEL set both tiers take it, and a scenario's own key still wins"
else
  fail "model tiers with EVAL_MODEL (rc=$RC): t1=$(metadata_model tiers tier1-scenario) t2=$(metadata_model tiers tier2-scenario) pinned=$(metadata_model tiers tier2-pinned)"
fi
rm -rf "$SUITE/tiers"

mkdir -p "$SUITE/pinned/evals"
echo "# pinned skill" > "$SUITE/pinned/SKILL.md"
cat > "$SUITE/pinned/evals/evals.json" <<'EOF'
{"skill_name": "pinned", "evals": [
  {"id": 1, "name": "pinned-scenario", "prompt": "one", "expected_output": "one",
   "model": "haiku", "files": [], "expectations": ["stub criterion"]},
  {"id": 2, "name": "default-scenario", "prompt": "two", "expected_output": "two",
   "files": [], "expectations": ["stub criterion"]}
]}
EOF
EVAL_MODEL=opus run_runner grade pinned
if [ "$RC" -eq 0 ] && [ "$(arg_after --model)" = opus ] \
  && [ "$(metadata_model pinned pinned-scenario)" = haiku ] \
  && [ "$(metadata_model pinned default-scenario)" = opus ] \
  && grep -q "pinned-scenario: .*on model haiku" "$LOG/prompt" \
  && grep -q "default-scenario: .*on model opus" "$LOG/prompt"; then
  pass "model: a scenario's own model wins over EVAL_MODEL; its sibling keeps EVAL_MODEL"
else
  fail "scenario model (rc=$RC): pinned=$(metadata_model pinned pinned-scenario) default=$(metadata_model pinned default-scenario)"
fi

EVAL_MODEL="-x" run_runner grade demo
if [ "$RC" -eq 3 ] && [ ! -e "$LOG/args" ] && printf '%s' "$OUT" | grep -q "EVAL_MODEL must match"; then
  pass "model: an EVAL_MODEL that does not match the pattern is refused before any session"
else
  fail "EVAL_MODEL=-x (rc=$RC): $OUT"
fi

mkdir -p "$SUITE/badmodel/evals"
echo "# badmodel skill" > "$SUITE/badmodel/SKILL.md"
cat > "$SUITE/badmodel/evals/evals.json" <<'EOF'
{"skill_name": "badmodel", "evals": [
  {"id": 1, "name": "bad-scenario", "prompt": "one", "expected_output": "one",
   "model": "opus; rm -rf /", "files": [], "expectations": ["stub criterion"]}
]}
EOF
run_runner grade badmodel
if [ "$RC" -eq 3 ] && [ ! -e "$LOG/args" ] && [ ! -d "$SUITE/badmodel/evals/workspace/iteration-1" ] \
  && printf '%s' "$OUT" | grep -q "bad-scenario declares a model that does not match"; then
  pass "model: a scenario model that does not match the pattern refuses the suite, exit 3, no iteration"
else
  fail "scenario model refused (rc=$RC): $OUT"
fi
rm -rf "$SUITE/badmodel"

# -- credentials ------------------------------------------------------------

GH_TOKEN=secret-token GITHUB_TOKEN=secret-token SSH_AUTH_SOCK="$T/agent.sock" run_runner grade demo
if [ "$RC" -eq 0 ] && grep -qx "GH_TOKEN=unset" "$LOG/env" \
  && grep -qx "GITHUB_TOKEN=unset" "$LOG/env" && grep -qx "SSH_AUTH_SOCK=unset" "$LOG/env"; then
  pass "credentials: the nested session sees no GH_TOKEN, GITHUB_TOKEN or SSH_AUTH_SOCK"
else
  fail "credentials reached the stub: $(tr '\n' ' ' < "$LOG/env")"
fi

# -- summary and --runs exit ------------------------------------------------

# summary_field <file> <skill> <field> -- one field of a skill's summary entry
summary_field() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert d['schema'] == 'run-evals-summary/v1', d['schema']
v = d['skills'][sys.argv[2]][sys.argv[3]]
print(','.join(v) if isinstance(v, list) else v)
" "$1" "$2" "$3" 2>/dev/null || echo "missing"
}

SUM="$T/summary.json"
rm -f "$SUM"
EVAL_MODEL=opus run_runner grade --summary-out "$SUM" pinned
if [ "$RC" -eq 0 ] && [ "$(summary_field "$SUM" pinned runs)" = 1 ] \
  && [ "$(summary_field "$SUM" pinned runs_passed)" = 1 ] \
  && [ "$(summary_field "$SUM" pinned assertions_passed)" = 2 ] \
  && [ "$(summary_field "$SUM" pinned assertions_graded)" = 2 ] \
  && [ "$(summary_field "$SUM" pinned models)" = "haiku,opus" ] \
  && [ "$(summary_field "$SUM" pinned exit_code)" = 0 ]; then
  pass "--summary-out: schema, runs, runs_passed, assertions, models and exit_code for a passing run"
else
  fail "--summary-out passing run (rc=$RC): $(cat "$SUM" 2>/dev/null)"
fi

rm -f "$SUM"
run_runner plan --runs 3 --summary-out "$SUM" demo
if [ "$RC" -eq 4 ] && [ "$(summary_field "$SUM" demo runs)" = 1 ] \
  && [ "$(summary_field "$SUM" demo runs_passed)" = 0 ] \
  && [ "$(summary_field "$SUM" demo exit_code)" = 4 ]; then
  pass "--summary-out: written when --runs stops early on 4, with the one run attempted"
else
  fail "--summary-out early stop (rc=$RC): $(cat "$SUM" 2>/dev/null)"
fi

rm -f "$SUM"
STUB_CLAUDE_SEQUENCE="nograde failgrade grade" run_runner grade --runs 3 --summary-out "$SUM" demo
if [ "$RC" -eq 2 ] && [ "$(wc -l < "$LOG/calls" | tr -d ' ')" = 3 ] \
  && [ "$(summary_field "$SUM" demo runs)" = 3 ] \
  && [ "$(summary_field "$SUM" demo runs_passed)" = 1 ] \
  && [ "$(summary_field "$SUM" demo assertions_passed)" = 1 ] \
  && [ "$(summary_field "$SUM" demo assertions_graded)" = 2 ] \
  && [ "$(summary_field "$SUM" demo exit_code)" = 2 ]; then
  pass "--runs 3: a nothing-graded run makes it exit 2 although another run failed assertions"
else
  fail "--runs 3 nograde/fail/grade (rc=$RC): $(cat "$SUM" 2>/dev/null)"
fi

STUB_CLAUDE_SEQUENCE="failgrade grade" run_runner grade --runs 2 demo
if [ "$RC" -eq 1 ]; then
  pass "--runs 2: runs that only failed assertions still exit 1"
else
  fail "--runs 2 fail/grade (rc=$RC): $OUT"
fi

# -- changed-since-tag selection --------------------------------------------

# A throwaway repository with its own tags. RUN_EVALS_REPO_ROOT points git at
# it and RUN_EVALS_SKILLS_DIR at its skills/, so the selection never reads
# this checkout's history.
REPO="$T/repo"
mkdir -p "$REPO"
git_t() { git -C "$REPO" -c user.email=test@example.invalid -c user.name=test "$@" >/dev/null 2>&1; }
git_t init -q
make_skill() { # make_skill <name> -- a skill with one passing-stub scenario
  mkdir -p "$REPO/skills/$1/evals"
  echo "# $1" > "$REPO/skills/$1/SKILL.md"
  printf '{"skill_name": "%s", "evals": [{"id": 1, "name": "%s-scenario", "prompt": "p", "expected_output": "o", "files": [], "expectations": ["stub criterion"]}]}\n' "$1" "$1" \
    > "$REPO/skills/$1/evals/evals.json"
}
make_skill alpha
make_skill beta
make_skill gamma
mkdir -p "$REPO/skills/noevals"
echo "# no evals" > "$REPO/skills/noevals/SKILL.md"
echo "notes" > "$REPO/skills/gamma/notes.md"
# Iterations the runner writes into the repository must not count as changes.
echo "workspace/" > "$REPO/.gitignore"
git_t add -A
git_t commit -q -m init

run_select() { # run_select <stub-mode> <runner args...>
  local mode="$1"
  shift
  rm -rf "$LOG"
  RC=0
  OUT=$(cd "$T" && RUN_EVALS_REPO_ROOT="$REPO" RUN_EVALS_SKILLS_DIR="$REPO/skills" \
    STUB_CLAUDE_MODE="$mode" STUB_CLAUDE_LOG_DIR="$LOG" PATH="$FIXTURES/bin:$PATH" \
    TMPDIR="$T" bash "$RUNNER" "$@" 2>&1) || RC=$?
}

run_select grade --list-changed
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "No v\* tag found" \
  && [ "$(printf '%s\n' "$OUT" | grep -v '^No v' | tr '\n' ' ')" = "alpha beta gamma " ] \
  && [ ! -e "$LOG/args" ]; then
  pass "selection: with no v* tag every skill with evals is selected, and the note says so"
else
  fail "selection, no tag (rc=$RC): $OUT"
fi

git_t tag v0.1.0
run_select grade
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "No skill with evals changed since v0.1.0." \
  && [ "$(git -C "$REPO" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse 'v0.1.0^{commit}')" ] \
  && [ ! -e "$LOG/args" ]; then
  pass "selection: a run on the tagged commit selects nothing, says so, exits 0 and starts no session"
else
  fail "selection, nothing changed (rc=$RC): $OUT"
fi

rm -f "$SUM"
run_select grade --summary-out "$SUM"
if [ "$RC" -eq 0 ] && python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d == {'schema': 'run-evals-summary/v1', 'skills': {}} else 1)
" "$SUM"; then
  pass "selection: nothing changed still writes an empty summary"
else
  fail "selection, nothing changed summary (rc=$RC): $(cat "$SUM" 2>/dev/null)"
fi

echo "changed" >> "$REPO/skills/alpha/SKILL.md"
# An evals/-only change: the skill body is untouched.
printf '{"skill_name": "beta", "evals": [{"id": 1, "name": "beta-scenario", "prompt": "p2", "expected_output": "o", "files": [], "expectations": ["stub criterion"]}]}\n' \
  > "$REPO/skills/beta/evals/evals.json"
echo "changed" >> "$REPO/skills/noevals/SKILL.md"
git_t commit -q -am "change alpha, beta's evals, and a skill without evals"

run_select grade --list-changed
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tr '\n' ' ')" = "alpha beta " ]; then
  pass "selection: --list-changed prints a changed skill and an evals/-only change, not gamma or a skill without evals"
else
  fail "selection, --list-changed (rc=$RC): $OUT"
fi

run_select grade
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "Skills with evals changed since v0.1.0: alpha beta" \
  && printf '%s' "$OUT" | grep -q "=== Preparing evals for skill: alpha ===" \
  && printf '%s' "$OUT" | grep -q "=== Preparing evals for skill: beta ===" \
  && ! printf '%s' "$OUT" | grep -q "Preparing evals for skill: gamma" \
  && printf '%s' "$OUT" | grep -q "All skills passed."; then
  pass "selection: no skill name prints the selection and runs it through the --all loop"
else
  fail "selection, default run (rc=$RC): $OUT"
fi

make_skill delta
git_t add -A
git_t commit -q -m "add delta"
git_t mv skills/gamma/notes.md skills/delta/notes.md
git_t commit -q -m "move a file from gamma to delta"
run_select grade --list-changed
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tr '\n' ' ')" = "alpha beta delta gamma " ]; then
  pass "selection: a rename selects both the skill the file left and the one it joined"
else
  fail "selection, rename (rc=$RC): $OUT"
fi

# A shallow clone that fetched no tags (the shape CI's default checkout has)
# finds no v* tag, so a run with no skill name selects every skill with evals
# and runs them, rather than nothing.
SHALLOW="$T/shallow"
git clone -q --depth 1 --no-tags "file://$REPO" "$SHALLOW" >/dev/null 2>&1
rm -rf "$LOG"
RC=0
OUT=$(cd "$T" && RUN_EVALS_REPO_ROOT="$SHALLOW" RUN_EVALS_SKILLS_DIR="$SHALLOW/skills" \
  STUB_CLAUDE_MODE=grade STUB_CLAUDE_LOG_DIR="$LOG" PATH="$FIXTURES/bin:$PATH" \
  TMPDIR="$T" bash "$RUNNER" 2>&1) || RC=$?
if [ "$RC" -eq 0 ] && [ "$(git -C "$SHALLOW" rev-parse --is-shallow-repository)" = true ] \
  && [ -z "$(git -C "$SHALLOW" tag -l)" ] \
  && printf '%s' "$OUT" | grep -q "No v\* tag found" \
  && printf '%s' "$OUT" | grep -q "=== Preparing evals for skill: alpha ===" \
  && printf '%s' "$OUT" | grep -q "=== Preparing evals for skill: beta ===" \
  && printf '%s' "$OUT" | grep -q "=== Preparing evals for skill: delta ===" \
  && printf '%s' "$OUT" | grep -q "=== Preparing evals for skill: gamma ===" \
  && ! printf '%s' "$OUT" | grep -q "Preparing evals for skill: noevals" \
  && printf '%s' "$OUT" | grep -q "All skills passed."; then
  pass "selection: a shallow clone with no tags runs every skill with evals"
else
  fail "selection, shallow clone (rc=$RC): $OUT"
fi

# A root git cannot read is an error, not "no tag" selecting every skill.
mkdir -p "$T/not-a-repo"
RC=0
OUT=$(cd "$T" && RUN_EVALS_REPO_ROOT="$T/not-a-repo" RUN_EVALS_SKILLS_DIR="$REPO/skills" \
  PATH="$FIXTURES/bin:$PATH" GIT_CEILING_DIRECTORIES="$T" bash "$RUNNER" --list-changed 2>&1) || RC=$?
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q "is not a git repository" \
  && ! printf '%s' "$OUT" | grep -q "No v\* tag found"; then
  pass "selection: a repository root git cannot read exits 2 instead of selecting everything"
else
  fail "selection, unreadable root (rc=$RC): $OUT"
fi

# -- tier-2 isolation -------------------------------------------------------

# The tier-2 clone's throwaway origin has a default branch, so node-cut.sh can
# cut a node in it (#585), on a host whose init.defaultBranch is master. A
# detached or shallow CI checkout can't be cloned and pushed the way the
# runner does, so this runs a copy of the runner from a throwaway repository on
# a feature branch; the stub's hook cuts a node in the clone and in the second
# clone while they exist.
ISO="$T/iso-src"
mkdir -p "$ISO/scripts" "$ISO/skills/execute/scripts"
cp "$RUNNER" "$ISO/scripts/"
cp -R "$SCRIPT_DIR/lib" "$ISO/scripts/lib"
cp "$REPO_ROOT/skills/execute/scripts/node-cut.sh" "$ISO/skills/execute/scripts/"
(cd "$ISO" && git -c init.defaultBranch=master init -q . && git add -A \
  && git -c user.email=t@example.com -c user.name=t commit -q -m runner \
  && git checkout -q -b feature/under-test) >/dev/null 2>&1
ISO_HEAD=$(git -C "$ISO" rev-parse HEAD)
mkdir -p "$T/iso-suite/isoskill/evals"
echo "# isoskill" > "$T/iso-suite/isoskill/SKILL.md"
cat > "$T/iso-suite/isoskill/evals/evals.json" <<'EOF'
{"skill_name": "isoskill", "evals": [
  {"id": 1, "name": "iso-scenario", "tier": 2, "mode": "execute", "prompt": "cut a node",
   "expected_output": "a node", "files": [], "expectations": ["stub criterion"]}
]}
EOF
PROBE_OUT="$T/iso-probe.out"
cat > "$T/iso-probe.sh" <<'EOF'
#!/usr/bin/env bash
# Cut one node in the tier-2 clone and one in the second clone. node-cut.sh's
# own key=value lines are prefixed home_ and second_ so each cut is read on
# its own.
co=$(sed -n '/^An isolated, throwaway clone of this repository has been prepared at:$/{n;s/^ *//;p;}' "$1")
{
  echo "checkout=$co"
  (cd "$co" && bash skills/execute/scripts/node-cut.sh iso-test pr-core) | sed 's/^/home_/'
  echo "home_rc=${PIPESTATUS[0]}"
  echo "head=$(git -C "$co" rev-parse HEAD)"
  echo "origin_head=$(git -C "$co" symbolic-ref --short refs/remotes/origin/HEAD)"
  (cd "$(dirname "$co")/second-clone" && bash "$co/skills/execute/scripts/node-cut.sh" iso-test pr-app) | sed 's/^/second_/'
  echo "second_rc=${PIPESTATUS[0]}"
} > "$PROBE_OUT" 2>&1
EOF
chmod +x "$T/iso-probe.sh"
rm -rf "$LOG" "$PROBE_OUT"
RC=0
OUT=$(cd "$T" && RUN_EVALS_SKILLS_DIR="$T/iso-suite" STUB_CLAUDE_MODE=grade STUB_CLAUDE_LOG_DIR="$LOG" \
  STUB_CLAUDE_HOOK="$T/iso-probe.sh" PROBE_OUT="$PROBE_OUT" PATH="$FIXTURES/bin:$PATH" TMPDIR="$T" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch GIT_CONFIG_VALUE_0=master \
  bash "$ISO/scripts/run-evals.sh" isoskill 2>&1) || RC=$?
probe() { sed -n "s/^$1=//p" "$PROBE_OUT" 2>/dev/null | head -n 1; }
if [ "$RC" -eq 0 ] && [ -n "$(probe checkout)" ] \
  && [ "$(probe home_rc)" = 0 ] && [ "$(probe home_cut)" = new ] \
  && [ "$(probe home_base)" = "$ISO_HEAD" ] && [ "$(probe head)" = "$ISO_HEAD" ] \
  && [ "$(probe origin_head)" = origin/main ] \
  && [ "$(probe second_rc)" = 0 ] && [ "$(probe second_cut)" = new ]; then
  pass "tier-2: under init.defaultBranch=master, node-cut.sh cuts from the clone's origin main, at the commit under test"
else
  fail "tier-2 origin default (rc=$RC): $(cat "$PROBE_OUT" 2>/dev/null) -- $OUT"
fi

# No koto the nested session reaches reads or writes $HOME/.koto: each run's
# koto keeps its store in the run's scratch root. The "real" koto here is a fake
# that records the HOME it ran under and writes a session where that HOME says,
# and the caller names it through KOTO_BIN, not PATH, as a developer trying a
# local koto build would. The hook reaches koto every way a session can:
# directly, as koto-open.sh does (${KOTO_BIN:-koto}), through the eval koto
# shim's passthrough, and through the shim again with the fake koto put ahead
# of the run's wrapper on PATH, as a login-shell snapshot could. Afterwards the
# caller's HOME must hold no .koto at all.
FAKE_HOME="$T/fake-home"
mkdir -p "$FAKE_HOME" "$T/fake-koto"
KOTO_SEEN="$T/koto-seen"
cat > "$T/fake-koto/koto" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$HOME" >> "$KOTO_SEEN"
mkdir -p "$HOME/.koto/sessions/probe"
EOF
chmod +x "$T/fake-koto/koto"
cat > "$T/koto-probe.sh" <<'EOF'
#!/usr/bin/env bash
# Reach koto every way a session can.
{
  koto session list
  echo "direct_rc=$?"
  "${KOTO_BIN:-koto}" session list
  echo "kotobin_rc=$?"
  PATH="$EVAL_SHIM_BIN:$PATH" EVAL_SCENARIO=coord-outline-one-repo koto session list
  echo "shim_rc=$?"
  PATH="$EVAL_SHIM_BIN:$FAKE_KOTO_DIR:$PATH" EVAL_SCENARIO=coord-outline-one-repo koto session list
  echo "reordered_rc=$?"
} > "$PROBE_OUT" 2>&1
EOF
chmod +x "$T/koto-probe.sh"
koto_run() { # koto_run <hook> [VAR=value...] -- the iso suite under a fake HOME; sets OUT, RC
  local hook="$1"
  shift
  rm -rf "$LOG" "$PROBE_OUT" "$KOTO_SEEN" "$FAKE_HOME/.koto"
  RC=0
  OUT=$(cd "$T" && env HOME="$FAKE_HOME" RUN_EVALS_SKILLS_DIR="$T/iso-suite" STUB_CLAUDE_MODE=grade \
    STUB_CLAUDE_LOG_DIR="$LOG" STUB_CLAUDE_HOOK="$hook" PROBE_OUT="$PROBE_OUT" KOTO_SEEN="$KOTO_SEEN" \
    EVAL_SHIM_BIN="$REPO_ROOT/skills/execute/evals/fixtures/bin" FAKE_KOTO_DIR="$T/fake-koto" TMPDIR="$T" \
    "$@" bash "$ISO/scripts/run-evals.sh" isoskill 2>&1) || RC=$?
}
koto_run "$T/koto-probe.sh" KOTO_BIN="$T/fake-koto/koto" PATH="$FIXTURES/bin:$PATH"
# Five koto calls: the runner's startup help probe, in a throwaway HOME of its
# own, and the hook's four, in the run's store.
SEEN_STORE=$(grep -cx "$T/shirabe-eval-scratch\.[A-Za-z0-9]*/koto-home" "$KOTO_SEEN" 2>/dev/null) || SEEN_STORE=0
SEEN_PROBE=$(grep -cx "$T/shirabe-eval-koto-probe\.[A-Za-z0-9]*" "$KOTO_SEEN" 2>/dev/null) || SEEN_PROBE=0
SEEN_ALL=$(grep -c . "$KOTO_SEEN" 2>/dev/null) || SEEN_ALL=0
if [ "$RC" -eq 0 ] && [ "$(probe direct_rc)" = 0 ] && [ "$(probe kotobin_rc)" = 0 ] \
  && [ "$(probe shim_rc)" = 0 ] && [ "$(probe reordered_rc)" = 0 ] \
  && [ "$SEEN_STORE" -eq 4 ] && [ "$SEEN_PROBE" -eq 1 ] && [ "$SEEN_ALL" -eq 5 ] \
  && [ ! -e "$FAKE_HOME/.koto" ]; then
  pass "koto: every route to koto keeps its store in the run's scratch root, never in \$HOME/.koto"
else
  fail "koto store (rc=$RC): seen=[$(tr '\n' ' ' < "$KOTO_SEEN" 2>/dev/null)] home_koto=$(ls -A "$FAKE_HOME" 2>/dev/null) probe=[$(cat "$PROBE_OUT" 2>/dev/null)] -- $OUT"
fi

# The tripwire: a run that leaves a file naming its scratch root in
# $HOME/.koto fails as an infrastructure failure, whatever it graded. The hook
# writes one there itself, the way a koto run under the real HOME would.
cat > "$T/koto-leak.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$HOME/.koto/sessions/leak"
printf 'cwd = "%s/checkout"\n' "$TMPDIR" > "$HOME/.koto/sessions/leak/state.toml"
EOF
chmod +x "$T/koto-leak.sh"
koto_run "$T/koto-leak.sh" PATH="$FIXTURES/bin:$T/fake-koto:$PATH"
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q "EVAL RUN REACHED \$HOME/.koto" \
  && printf '%s' "$OUT" | grep -q "$FAKE_HOME/.koto/sessions/leak/state.toml"; then
  pass "koto: a run that wrote into \$HOME/.koto exits 2 and names the file"
else
  fail "koto tripwire (rc=$RC): $OUT"
fi
# ... and a change there that doesn't name the run, another session's, passes.
cat > "$T/koto-other.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$HOME/.koto/sessions/other"
printf 'cwd = "/elsewhere"\n' > "$HOME/.koto/sessions/other/state.toml"
EOF
chmod +x "$T/koto-other.sh"
koto_run "$T/koto-other.sh" PATH="$FIXTURES/bin:$T/fake-koto:$PATH"
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q "EVAL RUN REACHED"; then
  pass "koto: another session's write to \$HOME/.koto during the run does not trip it"
else
  fail "koto tripwire, unrelated write (rc=$RC): $OUT"
fi

# With no koto at all, the run's wrapper refuses rather than leaving PATH to
# find one. Skipped where the system directories hold a koto of their own.
if PATH=/usr/bin:/bin command -v koto >/dev/null 2>&1; then
  echo "SKIP: a koto in /usr/bin or /bin -- the no-koto wrapper was not checked"
else
  cat > "$T/koto-none.sh" <<'EOF'
#!/usr/bin/env bash
{ koto session list; echo "none_rc=$?"; } > "$PROBE_OUT" 2>&1
EOF
  chmod +x "$T/koto-none.sh"
  koto_run "$T/koto-none.sh" KOTO_BIN= PATH="$FIXTURES/bin:/usr/bin:/bin"
  if [ "$RC" -eq 0 ] && [ "$(probe none_rc)" = 127 ] && grep -q "found no koto to wrap" "$PROBE_OUT"; then
    pass "koto: with no koto to wrap, the run's koto refuses (127)"
  else
    fail "koto, none to wrap (rc=$RC): probe=[$(cat "$PROBE_OUT" 2>/dev/null)] -- $OUT"
  fi
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
