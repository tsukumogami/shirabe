#!/usr/bin/env bash
# run-evals_test.sh -- test harness for scripts/run-evals.sh: the session
# classifier the graded path used, and the script-case runner every selection
# now goes to (scripts/lib/script-cases.py), with the changed-since-tag list.
#
# Usage: bash scripts/run-evals_test.sh
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# No model is called. A failing stub claude (scripts/run-evals/fixtures/bin/
# claude) is put first on PATH; it records every call in $STUB_CLAUDE_RECORD
# and exits non-zero, so the runner cases can show it was never started. The
# runner cases run a temporary copy of the tree that is its own git
# repository, holding the runner, a throwaway fixture skill and the tracked
# fixture scripts under scripts/cases/ its cases name, so nothing is written
# into this checkout.
#
# Three groups:
#   classifier cases run scripts/lib/classify-eval-session.py against the
#   fixture transcripts directly;
#   runner cases run scripts/run-evals.sh end to end: the fixture skill in the
#   copy, and /deliver's hand-off case on this tree and on a mutated copy
#   (those need koto, which check-handoff.sh compiles the templates with);
#   selection cases run --list-changed against a throwaway repository.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

# The cases set these themselves; a value from the caller's shell would change
# what the runner does.
unset EVAL_MODEL STUB_CLAUDE_RECORD RUN_EVALS_REPO_ROOT RUN_EVALS_SKILLS_DIR

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
RUNNER="$SCRIPT_DIR/run-evals.sh"
CLASSIFY="$SCRIPT_DIR/lib/classify-eval-session.py"
FIXTURES="$SCRIPT_DIR/run-evals/fixtures"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/run-evals-test.XXXXXX") || exit 1
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
ktg_on_exit cleanup

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

# The six fixtures are real captures (see each file's header). The inline
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
if grep -q "^I ran iteration 2" <<<"$(field result_text)"; then
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
  && grep -q "NESTED SESSION DID NOT EXECUTE" <<<"$OUT" \
  && grep -q "Permission mode in effect: plan" <<<"$OUT" \
  && grep -q "Permission mode requested: acceptEdits" <<<"$OUT"; then
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
if [ "$RC" -eq 0 ] && grep -q "ran in permission mode acceptEdits, not the dontAsk" <<<"$OUT"; then
  pass "report on executed in another mode: exit 0, with a note naming both modes"
else
  fail "report on a mode mismatch (rc=$RC): $OUT"
fi

# The session ended while its with-skill agent still ran: it executed, so the
# exit stays 0, but the stopped agent is named with its status, and the one
# that completed is not.
classify verdict "$FIXTURES/agent-stopped.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = executed ] && [ "$(field agents_launched)" = 2 ] \
  && [ "$(field unfinished_agents)" = "[{'description': 'With-skill execute eval run', 'status': 'stopped'}]" ]; then
  pass "real stopped-agent session: two agents launched, only the stopped one is listed, with its status"
else
  fail "agent-stopped verdict (rc=$RC): $OUT"
fi
classify report "$FIXTURES/agent-stopped.jsonl" acceptEdits
if [ "$RC" -eq 0 ] && grep -q "EVAL AGENT DID NOT FINISH" <<<"$OUT" \
  && grep -q "Did not finish: With-skill execute eval run (status: stopped)" <<<"$OUT" \
  && ! grep -q "Did not finish: Baseline" <<<"$OUT"; then
  pass "report on a stopped agent: exit 0, named failure, the stopped agent and its status"
else
  fail "report on a stopped agent (rc=$RC): $OUT"
fi
# A session that ran its agents in the foreground and waited: both complete,
# none is listed, and the report says nothing.
classify verdict "$FIXTURES/agents-foreground.jsonl"
if [ "$RC" -eq 0 ] && [ "$(field verdict)" = executed ] && [ "$(field agents_launched)" = 2 ] \
  && [ "$(field unfinished_agents)" = "[]" ]; then
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
# unfinished, for a run where some scenarios graded: the unfinished agents
# alone, never the did-not-execute claim, and nothing when all completed.
classify unfinished "$FIXTURES/agent-stopped.jsonl"
if [ "$RC" -eq 0 ] && grep -q "Did not finish: With-skill execute eval run (status: stopped)" <<<"$OUT" \
  && ! grep -q "DID NOT EXECUTE" <<<"$OUT"; then
  pass "unfinished on a stopped agent: exit 0, the agent and its status only"
else
  fail "unfinished on a stopped agent (rc=$RC): $OUT"
fi
classify unfinished "$FIXTURES/agents-foreground.jsonl"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  pass "unfinished on a foreground session: exit 0, silent"
else
  fail "unfinished on a foreground session (rc=$RC): $OUT"
fi

classify report "$T/missing.jsonl" acceptEdits
if [ "$RC" -eq 2 ] && ! grep -q "NESTED SESSION DID NOT EXECUTE" <<<"$OUT"; then
  pass "report on a missing transcript: exit 2, no not-executed claim"
else
  fail "report on a missing transcript (rc=$RC): $OUT"
fi

classify result-text "$FIXTURES/plan-mode.jsonl"
if [ "$RC" -eq 0 ] && grep -q "started in plan mode" <<<"$OUT"; then
  pass "result-text prints the session's final message"
else
  fail "result-text (rc=$RC): $OUT"
fi

# -- runner -----------------------------------------------------------------

# The failing claude stub records every call here; every run below must leave
# it empty.
RECORD="$T/claude-record"
: > "$RECORD"
record_empty() { [ ! -s "$RECORD" ]; }

# has <needle>: OUT contains the text (no pipe, so no early-exit race).
has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }

# The fixture tree: its own git repository, so the runner's tracked-file rule
# reads the fixture's index, not this checkout's.
TREE="$T/tree"
git_in() { # git_in <dir> <git args...>
  local dir="$1"
  shift
  git -C "$dir" -c user.email=test@example.invalid -c user.name=test "$@" >/dev/null
}
mkdir -p "$TREE/scripts/cases" "$TREE/skills/fx/evals" "$TREE/skills/two/evals" "$TREE/skills/deliver"
cp "$RUNNER" "$REPO_ROOT/scripts/check-handoff.sh" "$TREE/scripts/"
cp -R "$SCRIPT_DIR/lib" "$TREE/scripts/lib"
echo "# deliver" > "$TREE/skills/deliver/SKILL.md"
echo "# fx" > "$TREE/skills/fx/SKILL.md"
echo "# two" > "$TREE/skills/two/SKILL.md"

case_script() { # case_script <path under the tree> <body>
  printf '#!/bin/sh\n%s\n' "$2" > "$TREE/$1"
  chmod +x "$TREE/$1"
}
case_script scripts/cases/pass.sh 'echo "fixture pass"'
case_script scripts/cases/fail.sh 'echo "fixture failure: the hand-off word drifted"; exit 1'
# marker.sh <word>: leaves ran-<word> in the tree, so a case that should
# never have run shows it did.
case_script scripts/cases/marker.sh ': > "$PWD/ran-$1"'
case_script scripts/release-eval-check.sh ': > "$PWD/ran-release"'
case_script scripts/cases/env.sh 'env > "$PWD/case-env"'
case_script scripts/cases/sleeper.sh 'sleep 300 &
echo $! > "$PWD/child-pid"
sleep 300'
case_script scripts/cases/lines.sh 'i=1
while [ "$i" -le 500 ]; do
  if [ "$i" -eq 400 ]; then printf "line %d \033[31mred\033[0m\n" "$i"; else printf "line %d\n" "$i"; fi
  i=$((i + 1))
done
exit 1'
ln -s marker.sh "$TREE/scripts/cases/link.sh"

cat > "$TREE/skills/fx/evals/evals.json" <<'EOF'
{"skill_name": "fx", "evals": [
  {"id": 1, "name": "pass-case", "grader": "script", "handoff": "fx", "run": "scripts/cases/pass.sh"},
  {"id": 2, "name": "fail-case", "grader": "script", "handoff": "fx", "run": "scripts/cases/fail.sh"},
  {"id": 3, "name": "graded-case", "prompt": "do it", "expectations": ["it is done"],
   "run": "scripts/cases/marker.sh graded"},
  {"id": 4, "name": "no-grader-case", "run": "scripts/cases/marker.sh nograder"},
  {"id": 5, "name": "unknown-grader-case", "grader": "scripted", "run": "scripts/cases/marker.sh scripted"},
  {"id": 6, "name": "untracked-script", "grader": "script", "handoff": "fx", "run": "scripts/cases/untracked.sh"},
  {"id": 7, "name": "symlinked-script", "grader": "script", "handoff": "fx", "run": "scripts/cases/link.sh symlink"},
  {"id": 8, "name": "release-script", "grader": "script", "handoff": "fx", "run": "scripts/release-eval-check.sh"},
  {"id": 9, "name": "traversal-script", "grader": "script", "handoff": "fx", "run": "scripts/cases/../release-eval-check.sh"},
  {"id": 10, "name": "dotdot-arg", "grader": "script", "handoff": "fx", "run": "scripts/cases/marker.sh .."},
  {"id": 11, "name": "option-arg", "grader": "script", "handoff": "fx", "run": "scripts/cases/marker.sh --all"},
  {"id": 12, "name": "semicolon-arg", "grader": "script", "handoff": "fx", "run": "scripts/cases/marker.sh deliver;id"},
  {"id": 13, "name": "no-such-skill", "grader": "script", "handoff": "fx", "run": "scripts/check-handoff.sh deliver nosuchskill"},
  {"id": 14, "name": "shell-syntax", "grader": "script", "handoff": "fx",
   "run": "scripts/cases/marker.sh $(touch pwned) | touch pwned2 > pwned3"},
  {"id": 15, "name": "env-case", "grader": "script", "handoff": "fx", "run": "scripts/cases/env.sh"},
  {"id": 16, "name": "timeout-case", "grader": "script", "handoff": "fx", "run": "scripts/cases/sleeper.sh", "timeout": 2},
  {"id": 17, "name": "long-output", "grader": "script", "handoff": "fx", "run": "scripts/cases/lines.sh"}
]}
EOF
cat > "$TREE/skills/two/evals/evals.json" <<'EOF'
{"skill_name": "two", "evals": [
  {"id": 1, "name": "two-pass", "grader": "script", "handoff": "two", "run": "scripts/cases/pass.sh"},
  {"id": 2, "name": "two-fail", "grader": "script", "handoff": "two", "run": "scripts/cases/fail.sh"}
]}
EOF
git_in "$TREE" init -q
git_in "$TREE" add -A
git_in "$TREE" commit -q -m fixture
# Present on disk, never added: the untracked-script case.
case_script scripts/cases/untracked.sh ': > "$PWD/ran-untracked"'

# run_tree <runner args...>: the fixture tree's runner, with the failing stub
# first on PATH and the billing and credential variables a caller might hold
# set; sets OUT and RC.
run_tree() {
  RC=0
  OUT=$(cd "$T" && env ANTHROPIC_API_KEY=sk-test ANTHROPIC_AUTH_TOKEN=tok-test \
    ANTHROPIC_BASE_URL=https://example.invalid CLAUDE_CODE_USE_BEDROCK=1 CLAUDE_CODE_USE_VERTEX=1 \
    GH_TOKEN=secret-token GITHUB_TOKEN=secret-token SSH_AUTH_SOCK="$T/agent.sock" \
    STUB_CLAUDE_RECORD="$RECORD" PATH="$FIXTURES/bin:$PATH" TMPDIR="$T" \
    bash "$TREE/scripts/run-evals.sh" "$@" 2>&1) || RC=$?
}

# sfield <summary> <skill> <python expression over the skill's entry `e`>
sfield() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert d['schema'] == 'script-cases-summary/v1', d['schema']
e = d['skills'][sys.argv[2]]
print(eval(sys.argv[3]))
" "$1" "$2" "$3" 2>&1
}

SUM="$T/summary.json"
run_tree fx --summary-out "$SUM"
FX_OUT="$OUT"

if [ "$RC" -eq 1 ] && has "PASS 1 pass-case" && has "PASS 15 env-case" \
  && has "FAIL 2 fail-case: exited 1" && has "    fixture failure: the hand-off word drifted" \
  && has "script cases: 2 of 14 passed"; then
  pass "runner: script cases run, a failing one is named with its output, 2 of 14 passed, exit 1"
else
  fail "runner fixture run (rc=$RC): $OUT"
fi

if has "REFUSED 3 graded-case: graded cases don't run" \
  && has "REFUSED 4 no-grader-case: graded cases don't run" \
  && has "REFUSED 5 unknown-grader-case: graded cases don't run" \
  && [ ! -e "$TREE/ran-graded" ] && [ ! -e "$TREE/ran-nograder" ] && [ ! -e "$TREE/ran-scripted" ]; then
  pass "runner: a graded case, one with no grader and one with an unknown grader are refused and their run never executes"
else
  fail "runner refusals of non-script cases: $(ls "$TREE" | tr '\n' ' ') -- $OUT"
fi

if record_empty; then
  pass "runner: with ANTHROPIC_*/CLAUDE_CODE_USE_* set, the failing claude stub was never started"
else
  fail "runner started claude: $(cat "$RECORD")"
fi

# refused_case <id> <name> <rule text> [<marker that must not exist>]
refused_case() {
  local id="$1" name="$2" rule="$3" marker="${4:-}"
  if has "FAIL $id $name: refused: " && has "$rule" \
    && { [ -z "$marker" ] || [ ! -e "$TREE/$marker" ]; }; then
    pass "containment: $name refused before running, naming the rule ($rule)"
  else
    fail "containment $name: want [$rule]; marker=${marker:-none} exists=$([ -n "$marker" ] && [ -e "$TREE/$marker" ] && echo yes || echo no) -- $OUT"
  fi
}
refused_case 6 untracked-script "'scripts/cases/untracked.sh' is not tracked by git" ran-untracked
refused_case 7 symlinked-script "'scripts/cases/link.sh' resolves through a symlink" ran-symlink
refused_case 8 release-script "'scripts/release-eval-check.sh' is not scripts/check-handoff.sh or under scripts/cases/" ran-release
refused_case 9 traversal-script "'scripts/release-eval-check.sh' is not scripts/check-handoff.sh or under scripts/cases/" ran-release
refused_case 10 dotdot-arg "the argument '..' does not match [A-Za-z0-9][A-Za-z0-9._-]*" ran-..
refused_case 11 option-arg "the argument '--all' does not match" ran---all
refused_case 12 semicolon-arg "the argument 'deliver;id' does not match" "ran-deliver;id"
refused_case 13 no-such-skill "the skill argument 'nosuchskill' names no directory under skills/"
refused_case 14 shell-syntax "the argument '\$(touch' does not match"
if [ ! -e "$TREE/pwned" ] && [ ! -e "$TREE/pwned2" ] && [ ! -e "$TREE/pwned3" ] \
  && [ ! -e "$T/pwned" ] && [ ! -e "$T/pwned2" ] && [ ! -e "$T/pwned3" ]; then
  pass "containment: \$(...), | and > in run never act as shell syntax"
else
  fail "containment: shell syntax in run acted: $(ls "$TREE" "$T" | tr '\n' ' ')"
fi

ENV_FILE="$TREE/case-env"
env_has() { grep -q "^$1=" "$ENV_FILE"; }
env_keys=$(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$ENV_FILE" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
case_home=$(sed -n 's/^HOME=//p' "$ENV_FILE" 2>/dev/null)
extra_keys=""
for key in $env_keys; do
  case "$key" in PATH|LANG|TMPDIR|HOME|KOTO_HOME|PWD|OLDPWD|SHLVL|_) ;; *) extra_keys="$extra_keys $key" ;; esac
done
if [ -f "$ENV_FILE" ] && ! env_has ANTHROPIC_API_KEY && ! env_has GH_TOKEN && ! env_has GITHUB_TOKEN \
  && ! env_has SSH_AUTH_SOCK && ! env_has ANTHROPIC_AUTH_TOKEN && ! env_has CLAUDE_CODE_USE_BEDROCK \
  && [ -z "$extra_keys" ] && env_has KOTO_HOME && env_has TMPDIR \
  && [ -n "$case_home" ] && [ "$case_home" != "$HOME" ]; then
  pass "environment: only PATH, LANG, TMPDIR, a fresh HOME and KOTO_HOME reach a case; no token or billing variable"
else
  fail "environment: keys [$env_keys] extra [$extra_keys] HOME [$case_home] caller HOME [$HOME]"
fi
if [ -n "$case_home" ] && [ ! -e "$case_home" ]; then
  pass "environment: the case's temporary HOME is removed after it runs"
else
  fail "environment: the case's HOME [$case_home] is still there"
fi

child=$(cat "$TREE/child-pid" 2>/dev/null)
if has "FAIL 16 timeout-case: timed out after 2s" && [ -n "$child" ] && ! kill -0 "$child" 2>/dev/null; then
  pass "timeout: a case past its shortened timeout fails as timed out, and its background child is gone"
else
  fail "timeout: child=[$child] alive=$([ -n "$child" ] && kill -0 "$child" 2>/dev/null && echo yes || echo no) -- $OUT"
  [ -n "$child" ] && kill -9 "$child" 2>/dev/null
fi

esc=$(printf '\033')
if has "FAIL 17 long-output: exited 1" && has "    line 301
" && has "    line 500
" && ! has "    line 300
" && ! has "$esc" && has "    line 400 red"; then
  pass "output: a failing case's reason is its last 200 lines (301 to 500) with the escape byte stripped"
else
  fail "output truncation: $OUT"
fi
if [ "$(sfield "$SUM" fx "len(e['cases'][-1]['reason'].splitlines())")" = 201 ] \
  && [ "$(sfield "$SUM" fx "chr(27) in json.dumps(e)")" = False ]; then
  pass "output: the summary's reason is the status line and the same 200 lines, with no escape byte"
else
  fail "summary reason: $(sfield "$SUM" fx "e['cases'][-1]['reason'][:200]")"
fi

if [ "$(sfield "$SUM" fx "e['cases_run'], e['cases_passed'], e['assertions']['passed'], e['assertions']['graded']")" = "(14, 2, 2, 14)" ] \
  && [ "$(sfield "$SUM" fx "[c['id'] for c in e['refused']]")" = "[3, 4, 5]" ] \
  && [ "$(sfield "$SUM" fx "e['scenario_set'].startswith('sha256:') and len(e['scenario_set']) == 71")" = True ]; then
  pass "summary: cases run and passed, assertions, refused cases and scenario_set for the fixture skill"
else
  fail "summary fixture: $(head -c 600 "$SUM" 2>/dev/null)"
fi

SUM2="$T/summary-two.json"
run_tree two --summary-out "$SUM2"
if [ "$RC" -eq 1 ] && has "script cases: 1 of 2 passed" \
  && [ "$(sfield "$SUM2" two "e['assertions']['passed'], e['assertions']['graded'], e['pass_rate']")" = "(1, 2, 0.5)" ] \
  && [ "$(sfield "$SUM2" two "[(c['name'], c['verdict']) for c in e['cases']]")" = "[('two-pass', 'pass'), ('two-fail', 'fail')]" ]; then
  pass "summary: two script cases, one failing: assertions 1 of 2, pass rate 0.5, one pass and one fail verdict, exit 1"
else
  fail "summary two (rc=$RC): $(cat "$SUM2" 2>/dev/null) -- $OUT"
fi

run_tree --scenario pass-case --runs 3 --release-subset --no-baseline fx
if [ "$RC" -eq 0 ] && has "PASS 1 pass-case" && has "script cases: 1 of 1 passed" && ! has "REFUSED"; then
  pass "options: --scenario narrows to the named case; --runs, --release-subset and --no-baseline are ignored"
else
  fail "options (rc=$RC): $OUT"
fi

run_tree
if [ "$RC" -eq 1 ] && has "== fx" && has "== two" && has "script cases: 3 of 16 passed"; then
  pass "default: no skill name runs every skill's script cases, as --all"
else
  fail "default run (rc=$RC): $OUT"
fi

run_tree --prep-only fx
if [ "$RC" -eq 3 ] && has "--prep-only prepares a model-graded run" && [ ! -d "$TREE/skills/fx/evals/workspace" ]; then
  pass "--prep-only is refused with exit 3 and prepares nothing"
else
  fail "--prep-only (rc=$RC): $OUT"
fi

run_tree --bogus fx
if [ "$RC" -eq 1 ] && has "unknown option '--bogus'"; then
  pass "an unknown option is a usage error, exit 1"
else
  fail "unknown option (rc=$RC): $OUT"
fi

run_tree --list
if [ "$RC" -eq 0 ] && has "Skills with evals:" && has "  fx (17 evals)" && has "  two (2 evals)"; then
  pass "--list keeps its behaviour"
else
  fail "--list (rc=$RC): $OUT"
fi

if record_empty; then
  pass "runner: no run in this group started claude"
else
  fail "runner started claude: $(cat "$RECORD")"
fi

# -- /deliver's hand-off case -----------------------------------------------

if ! command -v koto >/dev/null; then
  fail "koto is not on PATH: /deliver's hand-off case compiles its templates with koto, so it was not checked"
else
  run_real() { # run_real <PATH> [VAR=value...] -- this tree's runner on deliver
    local path="$1"
    shift
    RC=0
    OUT=$(cd "$T" && env "$@" STUB_CLAUDE_RECORD="$RECORD" PATH="$path" TMPDIR="$T" \
      /bin/bash "$RUNNER" deliver 2>&1) || RC=$?
  }
  run_real "$FIXTURES/bin:$PATH"
  PLAIN_OUT="$OUT"
  refused_all=yes
  i=1
  while [ "$i" -le 33 ]; do
    case "$OUT" in *"REFUSED $i "*": graded cases don't run"*) ;; *) refused_all="no ($i)" ;; esac
    i=$((i + 1))
  done
  if [ "$RC" -eq 0 ] && has "PASS 34 handoff-execute-contract" && has "script cases: 1 of 1 passed" \
    && [ "$refused_all" = yes ] && record_empty; then
    pass "deliver on /bin/bash: case 34 passes, cases 1 to 33 are refused as graded, 1 of 1 passed, exit 0, no claude call"
  else
    fail "deliver (rc=$RC, refused all: $refused_all): $OUT"
  fi

  run_real "$FIXTURES/bin:$PATH" ANTHROPIC_API_KEY=sk-test ANTHROPIC_AUTH_TOKEN=tok-test \
    ANTHROPIC_BASE_URL=https://example.invalid CLAUDE_CODE_USE_BEDROCK=1 CLAUDE_CODE_USE_VERTEX=1
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$PLAIN_OUT" ] && record_empty; then
    pass "deliver with every billing variable set: the same output and exit, no claude call"
  else
    fail "deliver with billing variables (rc=$RC): $OUT"
  fi

  # No claude anywhere on PATH: python3, git and koto, and the system tools.
  NOCLAUDE="$T/noclaude-bin"
  mkdir -p "$NOCLAUDE"
  for tool in python3 git koto; do
    ln -s "$(command -v "$tool")" "$NOCLAUDE/$tool"
  done
  if PATH="$NOCLAUDE:/usr/bin:/bin" command -v claude >/dev/null; then
    fail "a claude in /usr/bin or /bin: the no-claude run cannot be made"
  else
    run_real "$NOCLAUDE:/usr/bin:/bin"
    if [ "$RC" -eq 0 ] && has "PASS 34 handoff-execute-contract" && ! has "claude CLI not found"; then
      pass "deliver with no claude on PATH exits 0, not 3"
    else
      fail "deliver with no claude (rc=$RC): $OUT"
    fi
  fi

  # A copy of the tree that is its own repository, with the word on the edge
  # into execute.md's merged state renamed: the case fails through the harness
  # and through the runner directly. Only the files the case reads are copied.
  MT="$T/mutated"
  mkdir -p "$MT/scripts/lib" "$MT/skills/deliver/evals" "$MT/skills/execute" "$MT/skills/work-on"
  cp "$RUNNER" "$REPO_ROOT/scripts/check-handoff.sh" "$MT/scripts/"
  cp "$SCRIPT_DIR/lib/script-cases.py" "$MT/scripts/lib/"
  cp "$REPO_ROOT/skills/deliver/SKILL.md" "$MT/skills/deliver/"
  cp "$REPO_ROOT/skills/deliver/evals/evals.json" "$MT/skills/deliver/evals/"
  cp -R "$REPO_ROOT/skills/deliver/koto-templates" "$MT/skills/deliver/"
  cp "$REPO_ROOT/skills/execute/SKILL.md" "$MT/skills/execute/"
  cp -R "$REPO_ROOT/skills/execute/koto-templates" "$MT/skills/execute/"
  cp -R "$REPO_ROOT/skills/work-on/koto-templates" "$MT/skills/work-on/"
  sed 's/^\(          \)outcome: merged$/\1outcome: landed/' "$REPO_ROOT/skills/execute/koto-templates/execute.md" \
    > "$MT/skills/execute/koto-templates/execute.md"
  git_in "$MT" init -q
  git_in "$MT" add -A
  RC=0
  OUT=$(cd "$T" && STUB_CLAUDE_RECORD="$RECORD" PATH="$FIXTURES/bin:$PATH" TMPDIR="$T" \
    /bin/bash "$MT/scripts/run-evals.sh" deliver 2>&1) || RC=$?
  if [ "$RC" -eq 1 ] && has "FAIL 34 handoff-execute-contract: exited 1" && has "outcome word 'landed'" \
    && has "doesn't expect it" && has "script cases: 0 of 1 passed" && record_empty; then
    pass "deliver on a copy with merged renamed to landed: case 34 fails naming landed, 0 of 1 passed, exit 1"
  else
    fail "deliver on the mutated copy (rc=$RC): $OUT"
  fi
  RC=0
  OUT=$(cd "$T" && python3 "$MT/scripts/lib/script-cases.py" deliver 2>&1) || RC=$?
  if [ "$RC" -eq 1 ] && has "outcome word 'landed'" && has "script cases: 0 of 1 passed"; then
    pass "script-cases.py on the mutated copy runs the copy's own cases and fails case 34, exit 1"
  else
    fail "script-cases.py on the mutated copy (rc=$RC): $OUT"
  fi
  rm -rf "$MT"
fi

# -- changed-since-tag selection --------------------------------------------

# A throwaway repository with its own tags. RUN_EVALS_REPO_ROOT points git at
# it and RUN_EVALS_SKILLS_DIR at its skills/, so the selection never reads
# this checkout's history. --list-changed keeps its behaviour: it prints the
# selection and runs nothing.
REPO="$T/repo"
mkdir -p "$REPO"
git_in "$REPO" init -q
make_skill() { # make_skill <name> -- a skill with one graded scenario
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
git_in "$REPO" add -A
git_in "$REPO" commit -q -m init

run_select() { # run_select <runner args...>
  RC=0
  OUT=$(cd "$T" && RUN_EVALS_REPO_ROOT="$REPO" RUN_EVALS_SKILLS_DIR="$REPO/skills" \
    STUB_CLAUDE_RECORD="$RECORD" PATH="$FIXTURES/bin:$PATH" TMPDIR="$T" bash "$RUNNER" "$@" 2>&1) || RC=$?
}

run_select --list-changed
if [ "$RC" -eq 0 ] && has "No v* tag found" \
  && [ "$(printf '%s\n' "$OUT" | grep -v '^No v' | tr '\n' ' ')" = "alpha beta gamma " ]; then
  pass "selection: with no v* tag every skill with evals is listed, and the note says so"
else
  fail "selection, no tag (rc=$RC): $OUT"
fi

git_in "$REPO" tag v0.1.0
echo "changed" >> "$REPO/skills/alpha/SKILL.md"
printf '{"skill_name": "beta", "evals": [{"id": 1, "name": "beta-scenario", "prompt": "p2", "expected_output": "o", "files": [], "expectations": ["stub criterion"]}]}\n' \
  > "$REPO/skills/beta/evals/evals.json"
echo "changed" >> "$REPO/skills/noevals/SKILL.md"
git_in "$REPO" commit -q -am "change alpha, beta's evals, and a skill without evals"

run_select --list-changed
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tr '\n' ' ')" = "alpha beta " ]; then
  pass "selection: --list-changed prints a changed skill and an evals/-only change, not gamma or a skill without evals"
else
  fail "selection, --list-changed (rc=$RC): $OUT"
fi

make_skill delta
git_in "$REPO" add -A
git_in "$REPO" commit -q -m "add delta"
git_in "$REPO" mv skills/gamma/notes.md skills/delta/notes.md
git_in "$REPO" commit -q -m "move a file from gamma to delta"
run_select --list-changed
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tr '\n' ' ')" = "alpha beta delta gamma " ]; then
  pass "selection: a rename selects both the skill the file left and the one it joined"
else
  fail "selection, rename (rc=$RC): $OUT"
fi

# A root git cannot read is an error, not "no tag" selecting every skill.
mkdir -p "$T/not-a-repo"
RC=0
OUT=$(cd "$T" && RUN_EVALS_REPO_ROOT="$T/not-a-repo" RUN_EVALS_SKILLS_DIR="$REPO/skills" \
  PATH="$FIXTURES/bin:$PATH" GIT_CEILING_DIRECTORIES="$T" bash "$RUNNER" --list-changed 2>&1) || RC=$?
if [ "$RC" -eq 2 ] && has "is not a git repository" && ! has "No v* tag found"; then
  pass "selection: a repository root git cannot read exits 2 instead of selecting everything"
else
  fail "selection, unreadable root (rc=$RC): $OUT"
fi

if record_empty; then
  pass "selection: no run started claude"
else
  fail "selection started claude: $(cat "$RECORD")"
fi

rm -rf "$TREE"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
