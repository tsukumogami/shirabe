#!/usr/bin/env bash
# run-evals.sh - Run skill evals using /skill-creator
#
# Usage:
#   scripts/run-evals.sh                     Run evals for the skills changed since the last v* tag
#   scripts/run-evals.sh <skill-name>        Run evals for one skill
#   scripts/run-evals.sh --all               Run evals for all skills
#   scripts/run-evals.sh --list              List skills with evals
#   scripts/run-evals.sh --list-changed      Print the skills changed since the last v* tag, one per line
#   scripts/run-evals.sh --validate <skill>  Re-validate existing results
#   scripts/run-evals.sh --prep-only <skill>      Prepare workspace only (for /skill-creator)
#
# Options (combine with a selection):
#   --scenario <name>     Run only the named eval from that skill's suite
#   --runs <N>            Run the selection N times and report a pass rate
#   --summary-out <file>  Write a machine-readable summary of the skills run
#
# Environment:
#   EVAL_MODEL  When set: the model the nested session (the grader) runs on,
#               and the default for every scenario that names none. Unset: the
#               session keeps the CLI default, tier-1 scenarios run on sonnet,
#               and the rest inherit the session's model. See "Models" below.
#
# Each skill's evals live at skills/<name>/evals/evals.json.
# Results go to skills/<name>/evals/workspace/iteration-<N>/.
#
# Exit codes:
#   0  All assertions passed
#   1  One or more assertions failed, or a usage error in the arguments
#   2  No results produced, or a scenario graded zero assertions
#      (infrastructure failure -- see "Grading nothing is a failure" below).
#      Under --runs N, any run returning 2 makes the invocation exit 2, ahead of
#      runs that only failed assertions. Also: git could not answer the
#      changed-since-tag selection, the --summary-out file could not be
#      written, the run's own koto store could not be set up, or the run left
#      files naming its scratch root in $HOME/.koto (see setup_eval_koto). A
#      run that also classified as 4 below exits 4.
#   3  Missing prerequisites, or a model or suite the harness refuses (an
#      EVAL_MODEL or scenario model off the pattern, a suite with no evals)
#   4  The nested claude session stopped in plan mode or ran no command and
#      wrote no file, so no scenario ran (runner or host failure -- see "Nested
#      session permission mode" below)
#
# Prerequisites: claude CLI, python3, skill-creator plugin installed
#
# Nested session permission mode
#   The runner starts one nested `claude -p` session per run, and that session
#   would otherwise inherit whatever default permission mode the host has
#   configured. On a host whose default is plan, it writes a plan and stops, and
#   the run grades nothing for a reason no scenario declared. So the runner pins
#   the mode (EVAL_CLAUDE_PERMISSION_ARGS below), runs the session from the repo
#   root, and gives it one extra directory, a scratch root it creates per run and
#   removes afterwards:
#
#     --permission-mode acceptEdits   the edit tools (Write, Edit) are accepted
#                                     inside the repo and the scratch root only;
#                                     any other tool that would prompt (web
#                                     fetches, MCP tools, edits elsewhere) is
#                                     denied, since a -p session has nobody to
#                                     answer a prompt
#     --allowedTools Bash             the scenarios run shell: /skill-creator
#                                     grades with python3, and tier-2 scenarios
#                                     run gh, koto, git and bash with an
#                                     environment prefix, which acceptEdits
#                                     alone would deny. This allows every shell
#                                     command, so a command can still write
#                                     outside the repo; the bound above is on
#                                     the edit tools, not on the shell
#     --add-dir <scratch root>        the session's TMPDIR, where a scenario's
#                                     "empty directory" and the tier-2 clone live
#
#   Rejected: plan and manual execute nothing in a -p session; acceptEdits
#   without the allow rule denies python3; dontAsk runs only what allow rules
#   name, and with plain Write and Edit rules it let a write outside the repo and
#   the scratch root through, so matching the bound acceptEdits gives would take
#   hand-written path rules for both directories; auto leaves each call to a
#   classifier, so results would vary with it; bypassPermissions also admits
#   every prompting tool. A pattern
#   allow list (Bash(koto *) and the like) denies the environment-prefixed,
#   absolute-path and `bash -c` forms this runner's own instructions produce.
#
#   Subagents the session spawns inherit all three. The same mode and allow rule
#   go on the one nested `claude` the session is told to start itself, for the
#   preflight liveness eval. --verbose is there because the CLI requires it for
#   stream-json in -p.
#
#   The session's stream-json transcript is saved as runner_session.jsonl in the
#   iteration directory. When a run grades nothing and that transcript shows the
#   session stopped in plan mode, or ran no command and wrote no file, the
#   runner reports NESTED SESSION DID NOT EXECUTE with the permission mode that
#   was in effect and exits 4, so the
#   failure is not mistaken for a suite that graded nothing. The classification
#   lives in scripts/lib/classify-eval-session.py.
#
# Scenario criteria: expectations, falling back to assertions
#   A scenario's graded criteria come from its `expectations` key. `assertions`
#   is the older name for the same thing and is read when `expectations` is
#   absent, so suites written against either name grade correctly. Reading only
#   `assertions` is what let fourteen of the eighteen suites in this repo report
#   green while contributing zero graded criteria.
#
# Scenario working tree, and grading against it
#   A scenario's `files:` key lists the paths its premise says already exist.
#   Prep materializes each one into <eval-dir>/workspace/, which is that
#   scenario's working tree, and records a hash of the materialized tree.
#   Content comes from the first of: a per-scenario fixture under
#   evals/fixtures/<eval-name>/, a shared precondition tree under
#   evals/fixtures/files/, the file at that path in this repo, or a generated
#   stub carrying the scenario's own expected_output. After the run, the harness
#   copies that tree into <eval-dir>/with_skill/outputs/post_run_tree/ with a
#   manifest classifying each path against the prep-time hashes. That copy is
#   what lets an assertion grade what the run produced rather than what the
#   agent said it did.
#
# Grading nothing is a failure
#   A scenario whose grading yields an empty criteria list fails the run. The
#   report names each such scenario and says whether its suite declared no
#   criteria at all or declared some and graded none of them, because the two
#   have different fixes.
#
# Changed-since-tag selection
#   With no skill name, the harness runs the skills that have evals/evals.json
#   and have any added, modified, renamed or deleted file under skills/<name>/
#   between the last v* tag (git describe --tags --abbrev=0 --match 'v*') and
#   HEAD, through the same loop --all uses. The diff runs with -z --no-renames,
#   so a rename counts against both the old and the new skill, and every name is
#   checked against ^[a-z0-9][a-z0-9-]*$ before it is used. With no v* tag every
#   skill with evals is selected. --list-changed prints the selection and runs
#   nothing; it is what the release eval check reads.
#
# Models
#   The nested session, which also grades every scenario, gets --model only
#   when the caller sets EVAL_MODEL; otherwise it runs on the claude CLI's own
#   default, as it always has, so a default run's grader is unchanged. Each
#   scenario's with-skill and baseline agents run on, in order:
#     - the scenario's own `model` key in evals.json;
#     - for a tier-1 scenario (tier absent or 1, plan_only: it checks the
#       structure or routing a skill describes, and is not the preflight
#       liveness scenario), EVAL_MODEL, else sonnet;
#     - for any other scenario (tier 2, execute; the liveness scenario),
#       EVAL_MODEL when the caller set it, else "inherit": no model override,
#       so the agents run on the session's model as they did before.
#   Prep writes the resolved value into the scenario's eval_metadata.json as
#   `model`, and the per-eval instruction line tells the session to spawn both
#   agents on it, or with no override for "inherit". A session flag alone would
#   not reach those agents, which pick their own model unless told. Every value must match
#   ^[A-Za-z0-9][A-Za-z0-9._:-]*$ (it cannot start with -), and the harness
#   refuses a run or a suite that carries one that doesn't.
#
# Summary (--summary-out <file>)
#   Writes {"schema": "run-evals-summary/v1", "skills": {<name>: {...}}} with,
#   per skill run: runs (attempted, so an early stop shows), runs_passed,
#   assertions_passed and assertions_graded (summed from each run's
#   validation_summary.json), models (the distinct values in the iterations'
#   eval_metadata.json) and exit_code. It is written when --runs stops early on
#   3 or 4 too, and when the default selection finds nothing to run, so a caller
#   never has to parse the report above. A summary that cannot be written turns
#   an exit 0 into 2, so a caller never reads success with no summary behind it.
#
# Credentials
#   The nested session starts with GH_TOKEN, GITHUB_TOKEN and SSH_AUTH_SOCK
#   unset. It runs shell without prompting, so this narrows what a scenario can
#   reach; stored gh logins, git credential helpers and SSH keys on disk stay
#   reachable, which is why the release eval check names its host before it runs.
#
# Tier-2 isolation:
#   Tier-2 (execute) evals run the REAL workflow — run-cascade.sh --push, folder
#   moves, and `git mv` into docs/designs/current/ — against a live git repo. Run
#   directly in this checkout, a tier-2 cascade eval would mutate the working tree
#   (e.g. move a fixture DESIGN into docs/designs/current/) and leak artifacts that
#   collide with the next run. To prevent that, when a skill has any tier-2 evals
#   the runner creates a throwaway, fully isolated clone of this repo under a temp
#   dir (setup_tier2_isolation) and instructs the agent to `cd` into that clone
#   before executing the workflow. The clone has its own .git and a local bare
#   origin, so `git mv`/`git commit`/`git push` land in the sandbox and never touch
#   the live tree or the real remote. A clone (rather than `git worktree add`) is
#   used deliberately: concurrent agents share this repo's .git/worktrees, and a
#   nested worktree would register there and risk cross-run contention; a clone is
#   self-contained. This mirrors the temp-repo pattern in run-cascade_test.sh.
#   The eval workspace (outputs/, grading.json) still lives in the live tree so
#   --validate works; only the workflow EXECUTION is sandboxed.

set -uo pipefail
# Note: no set -e; we handle errors explicitly for --all resilience

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# RUN_EVALS_SKILLS_DIR exists for scripts/run-evals_test.sh, which runs the
# harness against a throwaway suite instead of writing iterations into this tree.
# It is test-only: the nested session may edit files only under the repo and the
# scratch root, so a real run with it pointing outside the repo would have every
# output and grading.json write denied unless that directory were also passed
# with --add-dir.
SKILLS_DIR="${RUN_EVALS_SKILLS_DIR:-$REPO_ROOT/skills}"
# RUN_EVALS_REPO_ROOT is test-only too: it overrides the repository the
# changed-since-tag selection asks git about, so the suite can point it at a
# temporary repository with its own tags. Nothing else reads it; the nested
# session still runs from REPO_ROOT.
GIT_ROOT="${RUN_EVALS_REPO_ROOT:-$REPO_ROOT}"
CLASSIFY_SESSION="$SCRIPT_DIR/lib/classify-eval-session.py"

# ---------------------------------------------------------------------------
# Ablation mode
#
# `--withhold <rule key>` anywhere in the arguments measures what withholding
# one instruction section does, instead of running a suite: the arguments go
# unchanged to scripts/ablation/ablation.py run, which runs its own sessions
# and grades them with scripts, sharing nothing below this block. Without the
# flag nothing here runs and the runner takes its usual path.
# Method: docs/measurement/offload-ablation/README.md.
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --withhold|--withhold=*)
      command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found"; exit 3; }
      exec python3 "$SCRIPT_DIR/ablation/ablation.py" run "$@" ;;
  esac
done

# The permission mode every nested claude session runs under. See "Nested
# session permission mode" in the header for why it is this and nothing wider.
# The mode is kept separately because the not-executed report compares it with
# the mode the session says was in effect. The prompt's PERMISSIONS AND SCRATCH
# DIRECTORY block describes what these flags allow in words; change it with them.
EVAL_CLAUDE_PERMISSION_MODE="acceptEdits"
EVAL_CLAUDE_PERMISSION_ARGS=(--permission-mode "$EVAL_CLAUDE_PERMISSION_MODE" --allowedTools Bash)

# ---------------------------------------------------------------------------
# Preflight kill switch
#
# Every skill body opens with the injected prerequisite check
# (scripts/skill-preflight.sh). Two things about this harness make that check
# fire here when it would not fire for a user:
#
#   Tier-2 fixtures put shim binaries in skills/<name>/evals/fixtures/bin and
#   prepend that directory to PATH. Those shims resolve under $PWD, and the
#   resolver refuses to execute a binary that resolves under the directory it
#   was invoked from -- a correct refusal, and one that emits a "prerequisite
#   not met, was not probed" block.
#
#   These evals are transcript-graded. Preflight text in front of the model is
#   part of the input, so leaving it there silently changes the input to every
#   existing scenario in the corpus.
#
# So the harness turns the check off for itself. The seam is
# SHIRABE_PREFLIGHT_DISABLE, the same shape as PR_BODY_HOOK_DISABLE in
# crates/shirabe/src/pr_body_hook.rs: set to anything other than empty, `0`, or
# `false`, the check short-circuits to silence and exit 0. It is exported here
# rather than injected per-eval so it reaches the `claude -p` process and every
# agent that process spawns.
#
# Setting it means the check does not run. It does NOT relax the resolver: the
# refusal rule that made the shims unprobeable is unchanged, and a scenario
# that wants the check to run must clear the variable.
#
# The exception is the liveness eval, which exists to prove the injected line
# still executes. An eval declaring "preflight": "live" is run with this
# variable cleared -- disabling the check there would make the eval assert
# nothing at all. See the per-eval instructions built below.
# ---------------------------------------------------------------------------
SHIRABE_PREFLIGHT_DISABLE=1
export SHIRABE_PREFLIGHT_DISABLE

# ---------------------------------------------------------------------------
# koto's legacy command environment
#
# A tier-2 scenario that carries a `koto-passthrough` file runs a real koto,
# entered through the skill's entry script and scripts/koto-open.sh. That
# koto's gates call the fixture `gh` stub, which reads EVAL_SCENARIO,
# EVAL_SCENARIO_DIR and GH_CALL_LOG. From the koto release that fixes a
# session's command environment at creation, those variables no longer reach
# the commands koto runs, so the stub would find no scenario.
# scripts/lib/koto-legacy-env.sh exports koto-open.sh's harness-only knob
# (SHIRABE_KOTO_LEGACY_ENVIRONMENT) when the koto on PATH accepts
# --legacy-environment, so every session a scenario opens keeps the old
# environment. It is exported here, like the switch above, so it reaches the
# `claude -p` process and every entry script it runs. On an older koto it
# stays unset and nothing changes. Scenarios without `koto-passthrough` get it
# too: their canned koto shim ignores the flag, and KOTO_CALL_LOG then records
# it on the `init` line, which no scenario's expectations read. Temporary,
# #483.
# ---------------------------------------------------------------------------
# shellcheck source=lib/koto-legacy-env.sh
. "$SCRIPT_DIR/lib/koto-legacy-env.sh"
# The probe asks koto for its init help only, but it runs under a throwaway
# HOME all the same: what this runner starts is kept out of $HOME/.koto, with
# a tripwire for detectable leaks (see setup_eval_koto).
koto_probe_home=$(mktemp -d "${TMPDIR:-/tmp}/shirabe-eval-koto-probe.XXXXXX") || {
  echo "Error: could not create a directory for the koto probe"
  exit 3
}
HOME="$koto_probe_home" koto_legacy_env_enable
rm -rf "$koto_probe_home"

# Prerequisite checks
command -v claude >/dev/null 2>&1 || { echo "Error: claude CLI not found"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found"; exit 3; }

usage() {
  echo "Usage: $0 [--scenario <name>] [--runs <N>] [--summary-out <file>] [<skill-name>]"
  echo "       $0 --withhold <rule key> [--case <file>] [--runs <N>] <skill-name>   (ablation mode)"
  echo "       $0 --all | --list | --list-changed | --validate <skill> | --prep-only <skill>"
  echo ""
  echo "  (no skill name)    Run evals for the skills changed since the last v* tag"
  echo "  <skill-name>       Run evals for a specific skill (prep + execute + validate)"
  echo "  --all              Run evals for all skills that have evals/"
  echo "  --list             List skills that have evals"
  echo "  --list-changed     Print the skills changed since the last v* tag and run nothing"
  echo "  --validate <skill> Re-validate the latest iteration without re-running"
  echo "  --prep-only <skill>     Prepare workspace only (use with /skill-creator in Claude Code)"
  echo ""
  echo "  --scenario <name>     Restrict the run to one eval, by its 'name' in evals.json"
  echo "  --runs <N>            Repeat the run N times and report a pass rate across them"
  echo "  --summary-out <file>  Write a run-evals-summary/v1 JSON summary of the skills run"
  echo ""
  echo "  EVAL_MODEL=<model>    Grader and scenario model; unset, tier-1 scenarios run on sonnet and the rest inherit"
  echo ""
  echo "  Running one scenario N times:"
  echo "    $0 --scenario baseline-malformed-state --runs 5 scope"
  exit 1
}

# Scenario filter, consumed by prep_skill_evals through the environment so the
# name never reaches a shell or Python expression as interpolated text.
EVAL_SCENARIO_FILTER=""
# How many times to repeat the selection. 1 keeps the single-run path exactly as
# it was, aggregate reporting included only when N > 1.
EVAL_RUNS=1
# Where --summary-out writes, and the JSON-lines file each skill run appends its
# tally to until then. Empty means no summary was asked for.
SUMMARY_OUT=""
SUMMARY_LINES=""

# A model name as `claude --model` takes it: an alias or a full ID. The pattern
# cannot start with -, so a value can never be read as an option.
valid_model() {
  case "$1" in
    ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._:-]*) return 1 ;;
  esac
  return 0
}

# EVAL_MODEL_EXPLICIT is the caller's EVAL_MODEL, empty when none was given.
# Only an explicit value changes the nested session's model (the grader) and
# the model of scenarios that don't name one and aren't tier 1; see "Models".
EVAL_MODEL_EXPLICIT="${EVAL_MODEL:-}"
EVAL_MODEL="${EVAL_MODEL:-sonnet}"
if ! valid_model "$EVAL_MODEL"; then
  # 3, like a refused suite, and not 1: a caller reading 1 as "assertions
  # failed" would record a rate for a run that never started.
  echo "Error: EVAL_MODEL must match ^[A-Za-z0-9][A-Za-z0-9._:-]*\$; refusing to run"
  exit 3
fi
# Prep's Python reads both from the environment.
export EVAL_MODEL EVAL_MODEL_EXPLICIT
# The nested session's model flag: none unless the caller named a model, so a
# default run grades on the same model it always has.
EVAL_SESSION_MODEL_ARGS=()
if [ -n "$EVAL_MODEL_EXPLICIT" ]; then
  EVAL_SESSION_MODEL_ARGS=(--model "$EVAL_MODEL_EXPLICIT")
fi

# Peel the options off the front of the argument list. They are options rather
# than positional arguments because they modify a run rather than name one, and
# both are meaningful alongside a bare skill name.
parse_run_options() {
  PARSED_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --scenario)
        [ $# -ge 2 ] || { echo "Error: --scenario needs a name"; exit 1; }
        EVAL_SCENARIO_FILTER="$2"
        shift 2
        ;;
      --scenario=*)
        EVAL_SCENARIO_FILTER="${1#--scenario=}"
        shift
        ;;
      --runs)
        [ $# -ge 2 ] || { echo "Error: --runs needs a count"; exit 1; }
        EVAL_RUNS="$2"
        shift 2
        ;;
      --runs=*)
        EVAL_RUNS="${1#--runs=}"
        shift
        ;;
      --summary-out)
        [ $# -ge 2 ] && [ -n "$2" ] || { echo "Error: --summary-out needs a file"; exit 1; }
        SUMMARY_OUT="$2"
        shift 2
        ;;
      --summary-out=*)
        SUMMARY_OUT="${1#--summary-out=}"
        [ -n "$SUMMARY_OUT" ] || { echo "Error: --summary-out needs a file"; exit 1; }
        shift
        ;;
      *)
        PARSED_ARGS+=("$1")
        shift
        ;;
    esac
  done

  case "$EVAL_RUNS" in
    ''|*[!0-9]*) echo "Error: --runs must be a positive integer, got '$EVAL_RUNS'"; exit 1 ;;
  esac
  [ "$EVAL_RUNS" -ge 1 ] || { echo "Error: --runs must be at least 1"; exit 1; }
}

list_skills_with_evals() {
  local found=0
  for skill_dir in "$SKILLS_DIR"/*/; do
    local name
    name=$(basename "$skill_dir")
    if [ -f "$skill_dir/evals/evals.json" ]; then
      local count
      count=$(python3 -c "import json; print(len(json.load(open('$skill_dir/evals/evals.json'))['evals']))" 2>/dev/null || echo "?")
      echo "  $name ($count evals)"
      found=$((found + 1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "  (no skills have evals)"
  fi
}

# The changed-since-tag selection (see "Changed-since-tag selection" in the
# header). Sets CHANGED_TAG to the tag compared against, empty when there is no
# v* tag, and CHANGED_SKILLS to the selected names, sorted. Globals rather than
# output, so a caller can tell "no tag" from "nothing changed"; call it
# directly, not in $(...). Returns 2 when git cannot produce the diff.
CHANGED_TAG=""
CHANGED_SKILLS=()
select_changed_skills() {
  CHANGED_TAG=""
  CHANGED_SKILLS=()
  local tag="" names="" name rest path
  # Checked first so a root git can't read is an error, not a silent "no tag"
  # that would select every skill.
  if ! git -C "$GIT_ROOT" rev-parse --verify --quiet HEAD >/dev/null; then
    echo "Error: $GIT_ROOT is not a git repository with a HEAD commit" >&2
    return 2
  fi
  # describe exits nonzero when no v* tag is reachable; that is the no-tag case.
  tag=$(git -C "$GIT_ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null) || tag=""

  if [ -z "$tag" ]; then
    for path in "$SKILLS_DIR"/*/; do
      name=$(basename "$path")
      case "$name" in
        ''|[!a-z0-9]*|*[!a-z0-9-]*) continue ;;
      esac
      [ -f "$SKILLS_DIR/$name/evals/evals.json" ] && names="$names$name
"
    done
  else
    CHANGED_TAG="$tag"
    local diff_file
    diff_file=$(mktemp "${TMPDIR:-/tmp}/run-evals-diff.XXXXXX") || return 2
    # -z keeps any path intact; --no-renames reports a rename as a delete and an
    # add, so both the skill a file left and the one it joined are selected.
    if ! git -C "$GIT_ROOT" diff --name-only -z --no-renames "$tag" HEAD -- skills/ > "$diff_file"; then
      rm -f "$diff_file"
      echo "Error: git diff $tag HEAD failed in $GIT_ROOT" >&2
      return 2
    fi
    while IFS= read -r -d '' path; do
      rest="${path#skills/}"
      # A file directly under skills/ belongs to no skill.
      case "$rest" in
        */*) ;;
        *) continue ;;
      esac
      name="${rest%%/*}"
      case "$name" in
        ''|[!a-z0-9]*|*[!a-z0-9-]*)
          echo "  WARNING: ignoring a changed path whose skill name is not ^[a-z0-9][a-z0-9-]*\$" >&2
          continue
          ;;
      esac
      [ -f "$SKILLS_DIR/$name/evals/evals.json" ] || continue
      names="$names$name
"
    done < "$diff_file"
    rm -f "$diff_file"
  fi

  # Every name was checked against the skill-name pattern above, so splitting
  # the sorted list on whitespace can neither split a name nor glob.
  local sorted
  sorted=$(printf '%s' "$names" | sort -u)
  for name in $sorted; do
    CHANGED_SKILLS+=("$name")
  done
  return 0
}

next_iteration() {
  local workspace="$1"
  local n=1
  while [ -d "$workspace/iteration-$n" ]; do
    n=$((n + 1))
  done
  echo "$n"
}

latest_iteration() {
  local workspace="$1"
  local n=0
  while [ -d "$workspace/iteration-$((n + 1))" ]; do
    n=$((n + 1))
  done
  echo "$n"
}

# Set by prep_skill_evals for its callers. Globals rather than files under /tmp
# so two runs of this script (or the N runs of one --runs invocation) cannot read
# each other's values. The /tmp files are still written because --prep-only
# documents them as its handoff to an interactive /skill-creator session.
PREP_ITER_DIR=""
PREP_EVAL_COUNT=0
PREP_ITERATION=0

prep_skill_evals() {
  local skill_name="$1"
  local skill_dir="$SKILLS_DIR/$skill_name"
  local evals_file="$skill_dir/evals/evals.json"

  if [ ! -f "$evals_file" ]; then
    echo "Error: no evals found at $evals_file"
    return 3
  fi

  if [ ! -f "$skill_dir/SKILL.md" ]; then
    echo "Error: no SKILL.md found at $skill_dir/SKILL.md"
    return 3
  fi

  local workspace="$skill_dir/evals/workspace"
  mkdir -p "$workspace"

  local iteration
  iteration=$(next_iteration "$workspace")
  local iter_dir="$workspace/iteration-$iteration"

  local eval_count
  eval_count=$(EVAL_SCENARIO_FILTER="$EVAL_SCENARIO_FILTER" python3 -c "
import json, os
sel = os.environ.get('EVAL_SCENARIO_FILTER', '')
evals = json.load(open('$evals_file'))['evals']
if sel:
    evals = [e for e in evals if e.get('name') == sel]
print(len(evals))
")

  if [ "$eval_count" -eq 0 ]; then
    if [ -n "$EVAL_SCENARIO_FILTER" ]; then
      echo "Error: no eval named '$EVAL_SCENARIO_FILTER' in $evals_file"
    else
      echo "Error: $evals_file declares no evals"
    fi
    return 3
  fi

  echo "=== Preparing evals for skill: $skill_name ==="
  echo "  Evals file: $evals_file"
  echo "  Eval count: $eval_count"
  if [ -n "$EVAL_SCENARIO_FILTER" ]; then
    echo "  Scenario:   $EVAL_SCENARIO_FILTER (filtered)"
  fi
  echo "  Iteration: $iteration"
  echo "  Output: $iter_dir"
  echo ""

  local prep_rc=0
  EVAL_SCENARIO_FILTER="$EVAL_SCENARIO_FILTER" REPO_ROOT="$REPO_ROOT" python3 << PYEOF || prep_rc=$?
import hashlib, json, os, re, shutil, sys

with open("$evals_file") as f:
    data = json.load(f)

iter_dir = "$iter_dir"
evals_dir = os.path.dirname("$evals_file")
fixtures_root = os.path.join(evals_dir, "fixtures")
repo_root = os.environ["REPO_ROOT"]
selected = os.environ.get("EVAL_SCENARIO_FILTER", "")

# The model each scenario's agents run on (see "Models" in the header): its own
# model key; else, for a tier-1 scenario (plan_only, the structure and routing
# checks), EVAL_MODEL or sonnet; else EVAL_MODEL when the caller gave one, and
# otherwise "inherit", meaning the agents run on the nested session's model as
# they always have. EVAL_MODEL was validated by the shell before this runs.
# Every scenario is checked before anything is written, so a refused suite
# leaves no iteration.
MODEL_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]*")
tier1_default = os.environ.get("EVAL_MODEL") or "sonnet"
other_default = os.environ.get("EVAL_MODEL_EXPLICIT") or "inherit"


def is_tier1(eval_item):
    return eval_item.get("tier", 1) == 1 and eval_item.get("preflight") != "live"


models = {}
bad_models = []
for eval_item in data["evals"]:
    eval_name = eval_item.get("name", f"eval-{eval_item['id']}")
    if selected and eval_name != selected:
        continue
    model = eval_item.get("model",
                          tier1_default if is_tier1(eval_item) else other_default)
    if not isinstance(model, str) or not MODEL_PATTERN.fullmatch(model):
        bad_models.append(eval_name)
        continue
    models[eval_name] = model
if bad_models:
    for eval_name in bad_models:
        print(f"Error: {eval_name} declares a model that does not match"
              f" ^[A-Za-z0-9][A-Za-z0-9._:-]*$; refusing the suite")
    sys.exit(3)

# Two names for the same thing. 'expectations' is what the current suites write
# and carries the great majority of the corpus; 'assertions' is the older name.
# Reading only the older one is how a suite on the newer name graded nothing and
# still reported green, so the newer name wins and the older one is the fallback.
CRITERIA_KEYS = ("expectations", "assertions")


def criteria_for(eval_item):
    for key in CRITERIA_KEYS:
        value = eval_item.get(key)
        if value:
            return list(value), key
    return [], None


def safe_target(root, rel):
    """Resolve rel under root, refusing absolute paths and traversal escapes.

    A scenario's files: entries are authored data, and the harness writes to
    every one of them, so this bounds the writes to the scenario's own tree.
    """
    if os.path.isabs(rel):
        return None
    root_n = os.path.abspath(root)
    target = os.path.abspath(os.path.join(root_n, rel))
    if target != root_n and not target.startswith(root_n + os.sep):
        return None
    return target


def precondition_source(eval_name, rel):
    """Where a declared precondition's content comes from, most specific first.

    A per-scenario fixture beats a shared one, and both beat the file at that
    path in this repo -- which is the case that covers the suites declaring
    skills/<x>/evals/fixtures/... paths, since those files really do exist.

    The repo fallback deliberately skips wip/. Those files are live workflow
    state: they come and go while a workflow runs, so reading one would make the
    scenario's input depend on what happened to be staged at that moment. That
    is exactly the variation --runs exists to measure, and letting it in through
    the fixture path would confound the measurement. A wip/ precondition comes
    from a fixture or from a stub, never from the working tree.
    """
    candidates = [
        os.path.join(fixtures_root, eval_name, rel),
        os.path.join(fixtures_root, "files", rel),
    ]
    if not rel.startswith("wip/"):
        candidates.append(os.path.join(repo_root, rel))
    for candidate in candidates:
        if os.path.isfile(candidate) and not os.path.islink(candidate):
            return candidate
    return None


STUB_TEMPLATE = """<!-- Generated by scripts/run-evals.sh.

This path is declared under files: for the eval '{eval_name}', so the scenario's
premise is that it exists. No fixture content was found for it, so the harness
wrote this stub and pasted the scenario's own expected_output below. To replace
the stub, add the real file at:

  {suggested}
-->

{described}
"""


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def materialize_files(eval_item, eval_dir, eval_name):
    """Create the scenario's declared preconditions in its own working tree.

    Returns (workspace_dir, from_fixture, stubbed, refused). The tree exists even
    when nothing is declared, because the post-run capture reads it either way.
    """
    ws = os.path.join(eval_dir, "workspace")
    if os.path.exists(ws):
        shutil.rmtree(ws)
    os.makedirs(ws)

    from_fixture, stubbed, refused = [], [], []
    for rel in (eval_item.get("files") or []):
        target = safe_target(ws, rel)
        if target is None:
            refused.append(rel)
            continue
        parent = os.path.dirname(target)
        if parent:
            os.makedirs(parent, exist_ok=True)
        source = precondition_source(eval_name, rel)
        if source:
            shutil.copyfile(source, target)
            from_fixture.append(rel)
            continue
        body = STUB_TEMPLATE.format(
            eval_name=eval_name,
            suggested=os.path.join(fixtures_root, eval_name, rel),
            described=eval_item.get("expected_output", "") or "(no expected_output recorded)",
        )
        with open(target, "w") as fh:
            fh.write(body)
        stubbed.append(rel)

    # Hash every materialized path so the post-run capture can say what the run
    # added, changed, or deleted rather than just what the tree ends up holding.
    baseline = {}
    for dirpath, _dirnames, filenames in os.walk(ws):
        for filename in filenames:
            full = os.path.join(dirpath, filename)
            baseline[os.path.relpath(full, ws)] = digest(full)
    with open(os.path.join(eval_dir, ".workspace_baseline.json"), "w") as fh:
        json.dump(baseline, fh, indent=2, sort_keys=True)

    return ws, from_fixture, stubbed, refused


prepared = 0
for eval_item in data["evals"]:
    eval_id = eval_item["id"]
    eval_name = eval_item.get("name", f"eval-{eval_id}")
    if selected and eval_name != selected:
        continue
    prompt = eval_item["prompt"]

    eval_dir = os.path.join(iter_dir, eval_name)
    os.makedirs(os.path.join(eval_dir, "with_skill", "outputs"), exist_ok=True)
    os.makedirs(os.path.join(eval_dir, "without_skill", "outputs"), exist_ok=True)

    criteria, criteria_key = criteria_for(eval_item)
    workspace_dir, from_fixture, stubbed, refused = materialize_files(
        eval_item, eval_dir, eval_name
    )

    metadata = {
        "eval_id": eval_id,
        "eval_name": eval_name,
        "prompt": prompt,
        # Written under the key the grading step already reads. criteria_source
        # records which key in evals.json it came from, so a suite author can see
        # the resolution rather than inferring it.
        "assertions": criteria,
        "criteria_source": criteria_key,
        "declared_files": list(eval_item.get("files") or []),
        "workspace_dir": workspace_dir,
        "files_from_fixture": from_fixture,
        "files_stubbed": stubbed,
        "model": models[eval_name],
    }
    if refused:
        metadata["files_refused"] = refused

    # Copy fixture files to inputs/ if fixture_dir is specified
    fixture_dir_rel = eval_item.get("fixture_dir")
    note = ""
    if fixture_dir_rel:
        fixture_dir = os.path.join(evals_dir, fixture_dir_rel)
        if os.path.isdir(fixture_dir):
            inputs_dir = os.path.join(eval_dir, "inputs")
            if os.path.exists(inputs_dir):
                shutil.rmtree(inputs_dir)
            shutil.copytree(fixture_dir, inputs_dir)
            metadata["has_fixtures"] = True
            note = f" (with fixtures from {fixture_dir_rel})"
        else:
            print(f"  WARNING: fixture_dir not found: {fixture_dir}")

    with open(os.path.join(eval_dir, "eval_metadata.json"), "w") as f:
        json.dump(metadata, f, indent=2)

    if criteria_key is None:
        print(f"  WARNING: {eval_name} declares neither expectations nor assertions;"
              f" it will grade nothing and fail validation.")
    for rel in refused:
        print(f"  WARNING: {eval_name} declares an out-of-tree precondition, refused: {rel}")

    detail = f"{len(criteria)} criteria"
    if criteria_key and criteria_key != "expectations":
        detail += f" (from '{criteria_key}')"
    if from_fixture:
        detail += f", {len(from_fixture)} precondition(s) from fixtures"
    if stubbed:
        detail += f", {len(stubbed)} stubbed"
    print(f"  Prepared: {eval_name}{note} -- {detail}")
    if stubbed:
        for rel in stubbed:
            print(f"      stub: workspace/{rel}")
    prepared += 1

print(f"\nPrepared {prepared} eval directories.")
PYEOF
  # 3 is the model refusal above, raised before anything was written. Any other
  # failure here goes on as it always has, to the validation that reports it.
  if [ "$prep_rc" -eq 3 ]; then
    return 3
  fi

  # Return values for callers
  PREP_ITER_DIR="$iter_dir"
  PREP_EVAL_COUNT="$eval_count"
  PREP_ITERATION="$iteration"
  echo "$iter_dir" > /tmp/run-evals-iter-dir
  echo "$eval_count" > /tmp/run-evals-eval-count
  echo "$iteration" > /tmp/run-evals-iteration
}

# Returns 0 if the selection contains at least one tier-2 eval. Honours the
# scenario filter: narrowing to a single tier-1 scenario must not stand up the
# isolated clone that only tier-2 execution needs.
skill_has_tier2() {
  local evals_file="$1"
  EVAL_SCENARIO_FILTER="$EVAL_SCENARIO_FILTER" python3 -c "
import json, os, sys
sel = os.environ.get('EVAL_SCENARIO_FILTER', '')
evals = json.load(open('$evals_file'))['evals']
if sel:
    evals = [e for e in evals if e.get('name') == sel]
sys.exit(0 if any(e.get('tier', 1) == 2 for e in evals) else 1)
" 2>/dev/null
}

# Create a throwaway, fully isolated clone of the repo for tier-2 eval execution.
# The clone lives under a temp dir, has its own .git, and points origin at a local
# bare repo in the same temp dir so the workflow's `git push` succeeds without
# touching the live tree or the real remote. On success, sets TIER2_CHECKOUT to
# the clone path and TIER2_ISOLATION_ROOT to the temp root (used by cleanup).
# Returns nonzero on failure (caller must NOT fall back to the live tree).
# Note: this sets globals rather than echoing, so it must be called directly
# (not in a command substitution) or the assignments would be lost to a subshell.
TIER2_ISOLATION_ROOT=""
TIER2_CHECKOUT=""
setup_tier2_isolation() {
  local iso_root checkout bare branch
  # Under the run's scratch root when there is one, because that is the one
  # directory outside the repo the nested session may edit files in.
  iso_root=$(mktemp -d "${EVAL_SCRATCH_ROOT:-${TMPDIR:-/tmp}}/shirabe-eval-iso.XXXXXX") || return 1
  TIER2_ISOLATION_ROOT="$iso_root"
  checkout="$iso_root/checkout"
  bare="$iso_root/origin.git"

  # Clone the live repo locally. --no-hardlinks keeps the sandbox fully
  # independent of the live object store so a runaway gc/push in the clone can
  # never corrupt the live repo.
  if ! git clone --no-hardlinks --quiet "$REPO_ROOT" "$checkout" >/dev/null 2>&1; then
    return 1
  fi

  # Replace origin with a throwaway bare repo so the cascade's `git push` lands
  # in the sandbox, never the real remote.
  git init --bare --quiet "$bare" >/dev/null 2>&1 || return 1
  (
    cd "$checkout" || exit 1
    git config user.email "eval@shirabe.test"
    git config user.name "Shirabe Eval Harness"
    git remote remove origin >/dev/null 2>&1 || true
    git remote add origin "$bare"
    branch=$(git rev-parse --abbrev-ref HEAD)
    git push --quiet --set-upstream origin "$branch" >/dev/null 2>&1 || exit 1
    # origin needs a default branch, or node-cut.sh, which cuts every node
    # from it, has nothing to cut from (#585). It is main, at the commit this
    # checkout starts on, so a node runs the scripts of the tree under test.
    # The bare origin's HEAD names it and the checkout knows it, whatever
    # init.defaultBranch this host has, as for the second clone below.
    if [ "$branch" != main ]; then
      git push --quiet origin HEAD:refs/heads/main >/dev/null 2>&1 || exit 1
    fi
    git --git-dir="$bare" symbolic-ref HEAD refs/heads/main || exit 1
    git fetch --quiet origin >/dev/null 2>&1 || exit 1
    git remote set-head origin main >/dev/null 2>&1 || exit 1
  ) || return 1

  # A second, independent repository for scenarios whose PLAN puts a node in
  # another repository (the coordinated multi-repo ones): its own bare origin
  # and a clone of it on main, so node-cut.sh --repo-dir cuts there and
  # node-push.sh pushes there, never into the checkout above.
  git init --bare --quiet "$iso_root/second-origin.git" >/dev/null 2>&1 || return 1
  git clone --quiet "$iso_root/second-origin.git" "$iso_root/second-clone" >/dev/null 2>&1 || return 1
  (
    cd "$iso_root/second-clone" || exit 1
    git config user.email "eval@shirabe.test"
    git config user.name "Shirabe Eval Harness"
    git checkout --quiet -b main
    git commit --quiet --allow-empty -m "init"
    git push --quiet --set-upstream origin main >/dev/null 2>&1 || exit 1
    # The bare origin's HEAD names main, and the clone knows it: node-cut.sh
    # cuts from the default branch it reads there, whatever init.defaultBranch
    # this host has.
    git --git-dir="$iso_root/second-origin.git" symbolic-ref HEAD refs/heads/main || exit 1
    git remote set-head origin main >/dev/null 2>&1 || exit 1
  ) || return 1

  TIER2_CHECKOUT="$checkout"
}

cleanup_tier2_isolation() {
  if [ -n "$TIER2_ISOLATION_ROOT" ] && [ -d "$TIER2_ISOLATION_ROOT" ]; then
    rm -rf "$TIER2_ISOLATION_ROOT"
  fi
  TIER2_ISOLATION_ROOT=""
  TIER2_CHECKOUT=""
}

# The per-run scratch root: the nested session's TMPDIR and the one directory
# outside the repo it is given with --add-dir. Sets EVAL_SCRATCH_ROOT; like
# setup_tier2_isolation it must be called directly, not in $(...).
EVAL_SCRATCH_ROOT=""
setup_eval_scratch() {
  EVAL_SCRATCH_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/shirabe-eval-scratch.XXXXXX") || {
    EVAL_SCRATCH_ROOT=""
    return 1
  }
}

# The run's own koto store. koto keeps its sessions, config, coordinator
# records and terminal index under $HOME/.koto, which on a shared host holds
# live sessions of other work. An eval run must never read or write that: a
# session a killed run leaves there refuses the next run of the same scenario
# (origin_mismatch), and a real coordinator's session must not be visible to,
# or touched by, a scenario. The recipe is the one the ablation harness uses
# (scripts/ablation/koto-intercept): every real koto call runs with HOME inside
# the run's own directory. Keep the two in step: the ablation wrapper takes
# that HOME from ABLATION_KOTO_HOME and does not clear KOTO_SESSIONS_BASE, so a
# change to the recipe here belongs there too, or a note there saying why not.
#
# Here that is a wrapper, $scratch/koto-bin/koto, which runs the real koto
# (KOTO_BIN when the caller set it, else the koto on PATH) with HOME set to
# $scratch/koto-home. KOTO_SESSIONS_BASE would move the sessions somewhere
# else again, so the wrapper clears it. The nested session reaches the wrapper
# three ways:
#   - the session's PATH has the wrapper's directory first;
#   - KOTO_BIN is unset in the session, so koto-open.sh's ${KOTO_BIN:-koto}
#     resolves through PATH like every other call;
#   - EVAL_KOTO_WRAPPER names the wrapper, and the eval koto shim's passthrough
#     execs it before it looks at PATH at all.
# Only the last holds whatever PATH order the session ends up with. A
# login-shell snapshot that puts another koto ahead of the wrapper would send a
# direct `koto` call, or koto-open.sh's, to that koto and the real HOME; an
# execute scenario puts the shim first on every command, so its calls take the
# third route, and koto_store_tripwire is the backstop for the rest. With no
# koto to wrap, the wrapper refuses instead of letting some other PATH entry
# supply one. Every command koto runs (gates, default actions) inherits the
# scratch HOME too: a gate that reads git or gh config sees none, which is why
# the tier-2 clones carry a local git identity.
#
# The store goes when the scratch root does. Sets EVAL_KOTO_BIN_DIR to the
# wrapper's directory; call it directly, not in $(...). Returns 1 when
# KOTO_BIN names nothing executable, when koto resolves to the wrapper itself,
# or when the store or wrapper directory can't be made or the wrapper can't be
# written.
EVAL_KOTO_BIN_DIR=""
setup_eval_koto() {
  local scratch="$1" real wrapper
  EVAL_KOTO_BIN_DIR=""
  mkdir -p "$scratch/koto-home" "$scratch/koto-bin" || return 1
  wrapper="$scratch/koto-bin/koto"
  if [ -n "${KOTO_BIN:-}" ]; then
    # A bare name resolves through PATH now, before the wrapper's directory is
    # put in front of it, so the wrapper never execs itself.
    real=$(command -v -- "$KOTO_BIN" 2>/dev/null) || real=""
    case "$real" in /*) ;; *) echo "  Error: KOTO_BIN [$KOTO_BIN] names no executable koto." >&2; return 1 ;; esac
  else
    real=$(command -v koto 2>/dev/null) || real=""
  fi
  case "$real" in "$scratch/koto-bin/"*) echo "  Error: koto resolves to this run's own wrapper." >&2; return 1 ;; esac
  {
    printf '#!/bin/sh\n'
    if [ -n "$real" ]; then
      printf '# This eval run'"'"'s koto: the real one, with its store in the run'"'"'s scratch root.\n'
      printf 'unset KOTO_SESSIONS_BASE\n'
      printf 'HOME=%s exec %s "$@"\n' "$(shell_quote "$scratch/koto-home")" "$(shell_quote "$real")"
    else
      printf 'echo "koto: this eval run found no koto to wrap (KOTO_BIN unset, none on PATH); refusing rather than run one under the real HOME" >&2\n'
      printf 'exit 127\n'
    fi
  } > "$wrapper" || return 1
  chmod +x "$wrapper" || return 1
  EVAL_KOTO_BIN_DIR="$scratch/koto-bin"
}

# koto_store_tripwire <scratch> <marker>: return 1, naming the files, when
# anything under $HOME/.koto changed since <marker> was made and mentions the
# run's scratch root, which every path a tier-2 scenario works in sits under.
# Other work on the host writes there too, so a change alone proves nothing; a
# mention of this run's own directory does. It sees only such writes: not
# reads, not a write from a session working in the live tree (where tier-1
# scenarios start), and not one that records no path. The wrapper above is
# what keeps those out.
koto_store_tripwire() {
  local scratch="$1" marker="$2" hits
  [ -d "$HOME/.koto" ] || return 0
  hits=$(find "$HOME/.koto" -type f -newer "$marker" -exec grep -lF -- "$scratch" {} + 2>/dev/null) || true
  [ -n "$hits" ] || return 0
  echo ""
  echo "  EVAL RUN REACHED \$HOME/.koto"
  echo "  The run's koto was meant to keep its store in the scratch root, but these"
  echo "  files under \$HOME/.koto changed during the run and name it. The run's"
  echo "  results are not trusted; remove the files once you have looked at them."
  printf '%s\n' "$hits" | sed 's/^/    /'
  return 1
}

# shell_quote <string>: the string as one single-quoted sh word.
shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

cleanup_eval_scratch() {
  if [ -n "$EVAL_SCRATCH_ROOT" ] && [ -d "$EVAL_SCRATCH_ROOT" ]; then
    rm -rf "$EVAL_SCRATCH_ROOT"
  fi
  EVAL_SCRATCH_ROOT=""
}

cleanup_run_dirs() {
  cleanup_tier2_isolation
  cleanup_eval_scratch
}

# Belt-and-suspenders: ensure the sandbox is removed even if the run exits early
# (failed assertions, signal, or error) before run_skill_evals reaches cleanup.
trap cleanup_run_dirs EXIT

# Copy each scenario's post-run working tree into its output directory, with a
# manifest saying what the run did to it.
#
# This is the harness's job rather than the agent's. An assertion about what a
# run produced can only be graded against the tree the run left behind, and if
# capturing that tree were an instruction in the prompt, a run that ignored the
# instruction would be graded against its own narration -- which is the failure
# mode this exists to close. Copying here means the tree is captured whether the
# agent cooperated or not.
#
# Tier-1 scenarios execute nothing, so their manifest records an unchanged tree.
# That is the honest result for a scenario whose subject is a plan, not a tree.
capture_post_run_state() {
  local iter_dir="$1"

  python3 << PYEOF
import hashlib, json, os, shutil

iter_dir = "$iter_dir"


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def tree_digests(root):
    out = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for filename in filenames:
            full = os.path.join(dirpath, filename)
            if os.path.islink(full):
                continue
            out[os.path.relpath(full, root)] = digest(full)
    return out


captured = 0
changed_total = 0
for entry in sorted(os.listdir(iter_dir)):
    eval_dir = os.path.join(iter_dir, entry)
    workspace = os.path.join(eval_dir, "workspace")
    if not os.path.isdir(eval_dir) or not os.path.isdir(workspace):
        continue

    outputs = os.path.join(eval_dir, "with_skill", "outputs")
    os.makedirs(outputs, exist_ok=True)
    dest = os.path.join(outputs, "post_run_tree")
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(workspace, dest, symlinks=True)

    baseline_path = os.path.join(eval_dir, ".workspace_baseline.json")
    baseline = {}
    if os.path.isfile(baseline_path):
        with open(baseline_path) as fh:
            baseline = json.load(fh)
    after = tree_digests(workspace)

    lines, changed = [], 0
    for rel in sorted(set(baseline) | set(after)):
        if rel not in baseline:
            status = "added"
        elif rel not in after:
            status = "deleted"
        elif baseline[rel] != after[rel]:
            status = "modified"
        else:
            status = "unchanged"
        if status != "unchanged":
            changed += 1
        lines.append(f"{status}\t{rel}")

    manifest = os.path.join(outputs, "post_run_tree_manifest.txt")
    with open(manifest, "w") as fh:
        fh.write("# Scenario working tree after the run, against the tree prep materialized.\n")
        fh.write("# Grade assertions about produced files against post_run_tree/, not narration.\n")
        if not lines:
            fh.write("# (the scenario declared no preconditions and the run produced no files)\n")
        for line in lines:
            fh.write(line + "\n")

    captured += 1
    changed_total += changed

if captured:
    print(f"  Captured {captured} scenario working tree(s); {changed_total} path(s) changed by the run.")
else:
    print("  No scenario working trees to capture.")
PYEOF
}

run_skill_evals() {
  local skill_name="$1"
  local skill_dir="$SKILLS_DIR/$skill_name"
  local evals_file="$skill_dir/evals/evals.json"

  # Step 1: Prepare
  prep_skill_evals "$skill_name" || return $?

  local iter_dir eval_count iteration
  iter_dir="$PREP_ITER_DIR"
  eval_count="$PREP_EVAL_COUNT"
  iteration="$PREP_ITERATION"

  # Step 1a: The scratch root comes first, so the tier-2 clone lands inside it.
  if ! setup_eval_scratch; then
    echo "  Error: could not create a scratch directory for the nested session." >&2
    return 2
  fi
  local scratch="$EVAL_SCRATCH_ROOT"

  # Every koto the nested session runs keeps its store in the scratch root and
  # out of $HOME/.koto, with a tripwire for detectable leaks. Refuse rather
  # than run against the real store.
  if ! setup_eval_koto "$scratch"; then
    echo "  Error: could not set up the run's own koto store; refusing to run against \$HOME/.koto." >&2
    cleanup_run_dirs
    return 2
  fi

  # Step 1b: For skills with tier-2 evals, stand up an isolated clone so the
  # real workflow (run-cascade.sh --push, folder moves, git mv) executes against
  # a sandbox checkout instead of the live working tree. See the "Tier-2
  # isolation" note in the file header.
  local tier2_checkout=""
  local tier2_isolation_block=""
  if skill_has_tier2 "$evals_file"; then
    echo "=== Tier-2 evals detected: setting up isolated checkout ==="
    # Call directly (not via $(...)): setup_tier2_isolation sets globals.
    if setup_tier2_isolation; then
      tier2_checkout="$TIER2_CHECKOUT"
      echo "  Isolated checkout: $tier2_checkout"
      echo "  (workflow execution sandboxed; live tree will not be mutated)"
      echo ""
      # read -d '' rather than $(cat <<...): bash 3.2 mis-parses a heredoc
      # holding an apostrophe inside a command substitution. read keeps the
      # trailing newline $(...) used to strip, so it is stripped below.
      IFS= read -r -d '' tier2_isolation_block <<ISOBLOCK || true

TIER-2 ISOLATION (MANDATORY for every tier 2 eval):
An isolated, throwaway clone of this repository has been prepared at:
  $tier2_checkout
Tier-2 evals run the REAL workflow (run-cascade.sh --push, folder moves, git mv
into docs/designs/current/), which mutates the repository working tree. To keep
the live checkout clean, the with-skill agent for EVERY tier-2 eval MUST run with
its working directory set to $tier2_checkout — i.e. cd into that directory before
invoking the workflow, and pass fixture/plan paths relative to it (the clone
contains an identical copy of skills/execute/evals/fixtures/...). The clone has
its own git remote (a local throwaway), so the workflow's git commit/push land in
the sandbox. Do NOT run any tier-2 workflow command in the original repository
checkout. Tier-1 evals are unaffected (they execute no commands).
A scenario whose PLAN puts a node in a second repository uses the clone the
harness provides for it, with its own throwaway origin, at:
  $TIER2_ISOLATION_ROOT/second-clone
Pass it to node-cut.sh with --repo-dir for that node.
ISOBLOCK
      tier2_isolation_block="${tier2_isolation_block%$'\n'}"
    else
      echo "  WARNING: failed to set up isolated checkout for tier-2 evals." >&2
      echo "  Refusing to run tier-2 evals against the live working tree." >&2
      cleanup_run_dirs
      return 2
    fi
  fi

  # Step 2: Build tier-specific instructions for each eval.
  # When tier-2 isolation is active, point the shimmed-bin path at the clone's
  # copy of the fixtures so the agent's PATH shim and working directory stay
  # consistent inside the sandbox.
  local fixtures_bin="$skill_dir/evals/fixtures/bin"
  local preflight_fixture="$skill_dir/evals/fixtures/preflight-liveness"
  if [ -n "$tier2_checkout" ]; then
    fixtures_bin="$tier2_checkout/skills/$skill_name/evals/fixtures/bin"
    preflight_fixture="$tier2_checkout/skills/$skill_name/evals/fixtures/preflight-liveness"
  fi
  local tier_instructions=""
  local nested_permission_text="${EVAL_CLAUDE_PERMISSION_ARGS[*]}"
  # Written to a file in the scratch root and read back, rather than captured
  # with $(...): bash 3.2 mis-parses a heredoc inside a command substitution
  # when the heredoc holds an unpaired quote.
  local tier_file="$scratch/tier-instructions.txt"
  EVAL_SCENARIO_FILTER="$EVAL_SCENARIO_FILTER" python3 > "$tier_file" << PYEOF
import json, os

with open("$evals_file") as f:
    data = json.load(f)

selected = os.environ.get("EVAL_SCENARIO_FILTER", "")
iter_dir = "$iter_dir"
tier2_workdir = "$tier2_checkout"


def resolve_logs(env):
    """Join each relative *_LOG value to the tier-2 working directory.

    A log path in an eval's env is written relative to the scenario's working
    directory. Passed through as written, it resolves against whatever
    directory each command runs in, and a coordinated run works in node
    worktrees: a gh call made there lands in a stray log the grader never
    reads, and the shim's state directory beside it starts empty.
    """
    out = dict(env)
    for name, value in env.items():
        if (tier2_workdir and name.endswith("_LOG") and isinstance(value, str)
                and not os.path.isabs(value)):
            out[name] = os.path.normpath(os.path.join(tier2_workdir, value))
    return out


def scenario_model(name):
    """The model prep resolved and wrote into the scenario's metadata."""
    try:
        with open(os.path.join(iter_dir, name, "eval_metadata.json")) as fh:
            return json.load(fh).get("model") or "inherit"
    except (OSError, ValueError):
        return "inherit"


lines = []
for ev in data["evals"]:
    tier = ev.get("tier", 1)
    name = ev.get("name", f"eval-{ev['id']}")
    if selected and name != selected:
        continue
    # Both agents of a scenario run on its model: a session flag alone would
    # not reach the agents the session spawns.
    model = scenario_model(name)
    if model == "inherit":
        model_text = (" Spawn this eval's with-skill agent and its baseline agent with no "
                      "model override, so they run on this session's model.")
    else:
        model_text = (f" Spawn this eval's with-skill agent and its baseline agent on model "
                      f"{model} (set it as each agent's model).")
    # The liveness eval is the one scenario that must run with the injected
    # preflight check ENABLED. The harness exports SHIRABE_PREFLIGHT_DISABLE=1
    # for everything else (see the header block); clearing it here is what
    # keeps this eval from asserting against a check that was switched off.
    if ev.get("preflight") == "live":
        target = ev.get("preflight_skill", "")
        lines.append(f"- {name}: TIER 2 (execute) — PREFLIGHT LIVENESS. "
                     f"Run every command for this eval with SHIRABE_PREFLIGHT_DISABLE CLEARED "
                     f"(prefix with 'env -u SHIRABE_PREFLIGHT_DISABLE'). Do not set it, do not "
                     f"re-export it: this eval exists to prove the injected line still runs, and "
                     f"with the variable set it would assert nothing. "
                     f"A self-contained fixture plugin is at $preflight_fixture. "
                     f"Instruct agent: 'Load that fixture plugin in a nested non-interactive claude "
                     f"run (claude $nested_permission_text --plugin-dir <fixture-path> -p ...; keep those "
                     f"permission flags, or the nested run inherits the host's default mode), invoke the skill /{target} "
                     f"in that run, and report VERBATIM everything the nested run put in front of "
                     f"the model before the skill body, plus a byte count. Do not call "
                     f"scripts/skill-preflight.sh yourself — the point is the skill load, not the "
                     f"script.'" + model_text)
        continue
    if tier == 2:
        scenario = ev.get("scenario", "")
        # An eval may declare extra environment for its run (a call log for the
        # gh shim, a CI wait limit), as a flat map of names to string values.
        # A relative log path is made absolute against the scenario's working
        # directory here, so a call from a node worktree lands in the same log.
        extra = ev.get("env") or {}
        env_text = ""
        if isinstance(extra, dict) and extra:
            extra = resolve_logs(extra)
            env_text = " Also set " + ", ".join(f"{k}={v}" for k, v in sorted(extra.items())) + "."
        lines.append(f"- {name}: TIER 2 (execute) — set EVAL_SCENARIO={scenario}, prepend $fixtures_bin to PATH.{env_text} "
                     f"Instruct agent: 'Execute the workflow. gh and koto are available on PATH.'" + model_text)
    else:
        lines.append(f"- {name}: TIER 1 (plan_only) — "
                     f"Instruct agent: 'Read the skill file and describe the exact sequence of commands you would run. Do NOT execute any commands.'" + model_text)

print("\\n".join(lines))
PYEOF
  tier_instructions=$(cat "$tier_file")
  rm -f "$tier_file"

  # Step 3: Run evals via claude -p with /skill-creator
  echo ""
  echo "Invoking claude with /skill-creator to run evals..."
  echo "(this may take several minutes)"
  echo ""

  local claude_exit=0
  # What koto_store_tripwire compares $HOME/.koto against.
  local koto_marker="$scratch/koto-marker"
  : > "$koto_marker"
  local transcript="$iter_dir/runner_session.jsonl"
  local prompt=""
  # read -d '' for the same bash 3.2 reason as the isolation block above.
  IFS= read -r -d '' prompt <<PROMPT || true
Invoke /skill-creator. You already have an existing skill with evals ready to run.

The skill is at: $skill_dir/SKILL.md
The evals are at: $evals_file
The eval workspace is prepared at: $iter_dir

Each eval directory in the workspace has:
- eval_metadata.json with the prompt and assertions
- with_skill/outputs/ (empty, for you to fill)
- without_skill/outputs/ (empty, for you to fill)
- workspace/ — that scenario's working tree

SCENARIO WORKING TREE (applies to every eval):
Every eval directory has a workspace/ subdirectory. Any path the scenario declares
under files: in evals.json has already been materialized there, because the
scenario's premise is that those files exist. eval_metadata.json lists them under
declared_files, and says which came from fixtures (files_from_fixture) and which
are harness-written stubs (files_stubbed).

When a scenario executes anything, the with-skill agent MUST run with its working
directory set to that scenario's workspace/ directory, so the files it reads are
the declared preconditions and the files it writes land where they can be graded.
The one exception is a tier-2 eval under the isolation block below, which runs in
the isolated clone instead. Do not edit files outside the scenario's workspace/.

After the run, this harness copies each workspace/ into
with_skill/outputs/post_run_tree/ with a manifest of what the run added, changed,
or deleted. Grade any assertion about a file the run was supposed to produce
against that tree, not against what the agent said it did.

PERMISSIONS AND SCRATCH DIRECTORY (applies to every eval):
This session runs with: $nested_permission_text --add-dir $scratch
The Write and Edit tools are accepted inside $REPO_ROOT and inside $scratch,
and denied anywhere else. Shell commands run. Agents you spawn inherit the same
rules. Keep every write, by tool or by shell, inside those two directories. The
one exception is the viewer in Step 4 below, which is generated by a shell
command to /tmp/${skill_name}-eval-review.html because the scratch directory is
deleted when the run ends.
When a scenario asks for an empty or temporary directory, create it under
$scratch (it is also TMPDIR, so mktemp -d lands there). Do not change the
permission mode, and do not ask for approval: nobody can answer in this session.

TIER-SPECIFIC INSTRUCTIONS:
Evals are split into two tiers. For each eval, apply the matching tier instruction below.

$tier_instructions

For tier 2 evals, before spawning the with-skill agent:
1. Set the EVAL_SCENARIO environment variable as specified above.
2. Prepend $fixtures_bin to PATH so the agent uses shimmed gh and koto binaries.
These environment variables must be passed to the spawned agent process.
$tier2_isolation_block

PREFLIGHT CHECK (applies to every eval):
This harness runs with SHIRABE_PREFLIGHT_DISABLE=1 exported, which turns off the
prerequisite check that every shirabe skill body injects at load. It is off because
tier-2 fixtures put shim binaries under the working directory and the check
correctly refuses to probe those, which would otherwise put a "prerequisite not
met" block in front of the model in every transcript-graded scenario. Keep it set
for every agent you spawn, and do not unset it — EXCEPT for an eval whose tier
instruction above says PREFLIGHT LIVENESS. That one eval must run with the variable
cleared, because its subject is whether the injected line still executes.

For tier 1 evals, the agent must NOT execute any commands. It should only read the
skill file and describe its planned execution sequence.

Follow the skill-creator's "Running and evaluating test cases" workflow:
- Step 1: For each eval, spawn a with-skill agent (reads the skill SKILL.md then executes the prompt) and a without-skill baseline agent (same prompt, no skill). Save outputs to the respective outputs/ directories.
  - WAIT FOR EVERY AGENT: launch each agent in the foreground, with run_in_background set to false (put both of an eval's Agent calls in one message so they still run side by side). This session is non-interactive: when you end your turn the session ends, and any agent still running is stopped with its scenario ungraded. Never end your turn, and never grade, while an agent you launched is still running; one agent finishing first is not the other finishing.
  - IMPORTANT: If eval_metadata.json contains "has_fixtures": true, an inputs/ directory exists alongside it with pre-defined plan artifact files (e.g. plan_my-feature_analysis.md, plan_my-feature_issue_1.md, etc.). Before running the with-skill agent for that eval, treat those files as already present in wip/ — the skill should read them rather than improvising fixture content. The agent must use the provided fixture files as the plan artifacts under review, not invent new ones.
- Step 2: Grade each with-skill run against the assertions in eval_metadata.json. Write grading.json in each with_skill/ directory. Grade EVERY assertion listed there — one entry in grading.json per assertion. A scenario whose grading.json comes back empty fails the run.
- Step 3: Capture timing data (total_tokens, duration_ms) to timing.json in each run directory.
- Step 4: Run the aggregation and generate the viewer to /tmp/${skill_name}-eval-review.html using --static mode.

This is iteration $iteration for the $skill_name skill.
PROMPT
  prompt="${prompt%$'\n'}"

  # Run from the repo root: acceptEdits bounds file edits to the working
  # directory plus --add-dir, so the directory the operator happened to invoke
  # this script from must not decide what the session may write. stdout is the
  # stream-json transcript the not-executed check reads; stderr stays on the
  # terminal. The subshell drops the credentials named under "Credentials" in
  # the header before the session starts, without touching this shell's.
  (
    cd "$REPO_ROOT" || exit 1
    unset GH_TOKEN GITHUB_TOKEN SSH_AUTH_SOCK
    # The run's koto, by every route (see setup_eval_koto).
    unset KOTO_BIN
    PATH="$EVAL_KOTO_BIN_DIR:$PATH"
    EVAL_KOTO_WRAPPER="$EVAL_KOTO_BIN_DIR/koto"
    export EVAL_KOTO_WRAPPER
    # The checkout the execute gh shim seeds a gh/db.json scenario from (its
    # @HEAD_SHA@, @BRANCH@ and coordination PR's remote_url), whichever
    # directory its first call runs in. Unset without a tier-2 clone.
    if [ -n "$tier2_checkout" ]; then
      EVAL_COORDINATION_CHECKOUT="$tier2_checkout"
      export EVAL_COORDINATION_CHECKOUT
    else
      unset EVAL_COORDINATION_CHECKOUT
    fi
    TMPDIR="$scratch" claude -p "$prompt" \
      "${EVAL_CLAUDE_PERMISSION_ARGS[@]}" \
      ${EVAL_SESSION_MODEL_ARGS[@]+"${EVAL_SESSION_MODEL_ARGS[@]}"} \
      --add-dir "$scratch" \
      --output-format stream-json --verbose
  ) > "$transcript" || claude_exit=$?

  # What `claude -p` printed in its default text mode: the session's last message.
  python3 "$CLASSIFY_SESSION" result-text "$transcript"

  if [ "$claude_exit" -ne 0 ]; then
    echo ""
    echo "Warning: claude -p exited with status $claude_exit"
  fi

  # Step 3: Capture what the run left in each scenario's working tree, before
  # validation reads the grades, so post_run_tree/ is already on disk when a
  # failed assertion sends someone looking for the evidence.
  echo ""
  echo "=== Capturing post-run filesystem state ==="
  capture_post_run_state "$iter_dir"

  # Step 4: Validate results
  echo ""
  echo "=== Validating results ==="
  local validate_rc=0
  validate_results "$iter_dir" "$eval_count" || validate_rc=$?

  # Step 4b: A run that graded nothing may never have executed at all. Only a
  # run where no scenario produced a grading.json is re-examined: validation
  # also exits 2 for a run that graded some scenarios and not others, and any
  # grade on disk means the session ran and is the better evidence. The 4 below
  # is classify-eval-session.py's EXIT_NOT_EXECUTED.
  local graded_count=""
  graded_count=$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1]))['graded'])
" "$iter_dir/validation_summary.json") || graded_count=""
  if [ "$validate_rc" -eq 2 ] && [ "$graded_count" = "0" ]; then
    local classify_rc=0
    python3 "$CLASSIFY_SESSION" report "$transcript" "$EVAL_CLAUDE_PERMISSION_MODE" || classify_rc=$?
    if [ "$classify_rc" -eq 4 ]; then
      validate_rc=4
    fi
  elif [ "$validate_rc" -eq 2 ]; then
    # Some scenarios graded and some didn't: the session ran, but an agent of
    # one it launched may have been stopped before it finished. Name it.
    python3 "$CLASSIFY_SESSION" unfinished "$transcript" || true
  fi

  # Step 4c: A run that reached the real koto store is an infrastructure
  # failure, whatever it graded. A run classified as not executed (4) keeps
  # its 4, which outranks a 2 here as it does in run_skill_list.
  if ! koto_store_tripwire "$scratch" "$koto_marker" && [ "$validate_rc" -ne 4 ]; then
    validate_rc=2
  fi

  # Step 5: Open viewer if it was generated
  local viewer="/tmp/${skill_name}-eval-review.html"
  if [ -f "$viewer" ]; then
    echo ""
    echo "Open the eval viewer:"
    echo "  xdg-open $viewer"
  fi

  # Tear down the tier-2 isolation sandbox (if one was created for this skill)
  # and the scratch root it lived in.
  cleanup_run_dirs

  # Return the verdict, not the teardown's status. Without this the function
  # returned whatever cleanup_tier2_isolation returned -- always 0 -- so a run
  # with failing assertions exited 0 and --all recorded no failures.
  return "$validate_rc"
}

# Tally an iteration's grades and decide the run's verdict.
#
# The whole tally lives in one Python pass rather than a bash loop shelling out
# per directory: it has to correlate three things per scenario (how many criteria
# the suite declared, how many the grading produced, how many passed) and a
# per-scenario zero is the case that used to slip through. It also writes
# validation_summary.json, which is what the --runs aggregate reads instead of
# re-parsing this output.
#
# Exit codes: 0 all graded and passing; 1 at least one assertion failed;
# 2 nothing was graded, or some scenario graded zero of its criteria, has no
# grading.json, or is missing from the iteration -- so a 2 can come from a run
# that graded other scenarios fine (step 4b in run_skill_evals relies on this).
validate_results() {
  local iter_dir="$1"
  local expected_count="$2"

  python3 << PYEOF
import json, os, sys

iter_dir = "$iter_dir"
expected_count = int("$expected_count")

missing_outputs = []
missing_grading = []
zero_graded = []
failures = []
graded = 0
total_assertions = 0
passed_assertions = 0
failed_assertions = 0
scenarios = []


def load_grades(path):
    """Read grading.json in either shape: {expectations: [...]} or a bare list."""
    try:
        with open(path) as fh:
            g = json.load(fh)
    except (OSError, ValueError):
        return None
    return g if isinstance(g, list) else g.get("expectations", [])


def declared_count(eval_dir):
    """How many criteria the suite declared for this scenario, or None if unknown."""
    meta_path = os.path.join(eval_dir, "eval_metadata.json")
    try:
        with open(meta_path) as fh:
            meta = json.load(fh)
    except (OSError, ValueError):
        return None
    return len(meta.get("assertions") or [])


entries = sorted(os.listdir(iter_dir)) if os.path.isdir(iter_dir) else []
for name in entries:
    eval_dir = os.path.join(iter_dir, name)
    if not os.path.isdir(eval_dir):
        continue

    # capture_post_run_state writes into with_skill/outputs/ before this runs, so
    # its two entries are excluded here. Without that, an outputs/ directory the
    # agent never wrote to would look populated and the check would never fire.
    HARNESS_WRITTEN = ("post_run_tree", "post_run_tree_manifest.txt")
    for side in ("with_skill", "without_skill"):
        outputs = os.path.join(eval_dir, side, "outputs")
        produced = []
        if os.path.isdir(outputs):
            produced = [e for e in os.listdir(outputs) if e not in HARNESS_WRITTEN]
        if not produced:
            missing_outputs.append(f"{name}/{side}")

    # Only with_skill is graded against assertions; without_skill is the baseline.
    grading_path = os.path.join(eval_dir, "with_skill", "grading.json")
    if not os.path.isfile(grading_path):
        missing_grading.append(name)
        scenarios.append({"name": name, "graded": 0, "passed": 0, "status": "ungraded"})
        continue

    graded += 1
    grades = load_grades(grading_path)
    if grades is None:
        grades = []
    total = len(grades)
    passed = sum(1 for e in grades if e.get("passed", False))
    total_assertions += total
    passed_assertions += passed
    failed_assertions += total - passed

    if total == 0:
        # The defect this rule exists for: a scenario contributes no criteria and
        # the run reports green having graded nothing. Name the cause, because a
        # suite that declares none needs an evals.json edit while a run that
        # graded none of several needs the run looked at.
        declared = declared_count(eval_dir)
        if declared is None:
            reason = "graded 0 criteria, and its eval_metadata.json is unreadable"
        elif declared == 0:
            reason = ("declares no criteria in evals.json "
                      "(add an expectations: list to the suite)")
        else:
            reason = f"declares {declared} criteria but grading.json graded 0 of them"
        zero_graded.append((name, reason))

    for e in grades:
        if not e.get("passed", False):
            failures.append((name, e.get("text", "unknown"), e.get("evidence")))

    scenarios.append({
        "name": name,
        "graded": total,
        "passed": passed,
        "status": "zero_graded" if total == 0 else ("pass" if passed == total else "fail"),
    })

print(f"  Evals expected: {expected_count}")
print(f"  Evals graded:   {graded}")
print(f"  Assertions:     {passed_assertions}/{total_assertions} passed")

if missing_outputs:
    print("")
    print("  Missing outputs:")
    for m in missing_outputs:
        print(f"    - {m}")

shortfall = expected_count - len(scenarios)

if missing_grading:
    print("")
    print("  Missing grading:")
    for m in missing_grading:
        print(f"    - {m}")

if shortfall > 0:
    print("")
    print(f"  SCENARIOS NOT FOUND: {shortfall}")
    print(f"  The suite declares {expected_count} scenario(s) and this iteration holds"
          f" {len(scenarios)}.")
    print("  Re-run the suite, or pass --scenario if this iteration was a filtered run.")

if zero_graded or missing_grading:
    print("")
    print(f"  ZERO-GRADED SCENARIOS: {len(zero_graded) + len(missing_grading)}")
    print("  A scenario that grades nothing proves nothing; these fail the run.")
    for name, reason in zero_graded:
        print(f"    [{name}] {reason}")
    for name in missing_grading:
        print(f"    [{name}] produced no grading.json at all")

if failed_assertions:
    print("")
    print(f"  FAILED ASSERTIONS: {failed_assertions}")
    for name, text, evidence in failures:
        print(f"    [{name}] FAIL: {text}")
        if evidence:
            print(f"           {evidence}")

if graded == 0:
    print("")
    print("  WARNING: No evals were graded. The claude session may not have produced results.")
    print(f"  Re-run or check the workspace: {iter_dir}")

clean = (
    graded
    and not zero_graded
    and not missing_grading
    and shortfall <= 0
    and not failed_assertions
)
if clean:
    print("")
    print("  All assertions passed.")

summary = {
    "iter_dir": iter_dir,
    "expected": expected_count,
    "graded": graded,
    "total_assertions": total_assertions,
    "passed_assertions": passed_assertions,
    "failed_assertions": failed_assertions,
    "zero_graded": [name for name, _ in zero_graded],
    "missing_grading": missing_grading,
    "scenarios_not_found": max(shortfall, 0),
    "scenarios": scenarios,
}
try:
    with open(os.path.join(iter_dir, "validation_summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)
except OSError:
    pass

if failed_assertions:
    sys.exit(1)
if graded == 0 or zero_graded or missing_grading or shortfall > 0:
    sys.exit(2)
sys.exit(0)
PYEOF
}

# Run the selection N times and report how often it passed.
#
# One scenario run once tells you whether it passed; the same scenario run N
# times tells you how reliably it passes, which is the question worth asking of
# a model-graded eval. Pair it with --scenario to get the rate for a single
# scenario:
#
#   scripts/run-evals.sh --scenario baseline-malformed-state --runs 5 scope
#
# Each run gets its own iteration-N directory, so no run overwrites another's
# evidence. The exit status is 0 only when every run passed, 2 when any run
# returned 2 (a run that graded nothing is an infrastructure failure, and the
# release check must not read it as a plain assertion failure), and 1 when runs
# only failed assertions. The rate is printed either way, since a rate is the
# point of asking.
run_skill_evals_repeated() {
  local skill_name="$1"
  local runs="$2"

  local run_no=1
  local runs_passed=0
  local total_assertions=0
  local passed_assertions=0
  local per_run=""
  local saw_infra=0

  while [ "$run_no" -le "$runs" ]; do
    echo ""
    echo "########## Run $run_no of $runs ##########"
    # Clear first: prep_skill_evals returns early on a missing suite without
    # setting this, and a stale value would make the run below read the previous
    # run's tally and report it as this one's.
    PREP_ITER_DIR=""
    local rc=0
    run_skill_evals "$skill_name" || rc=$?
    # Before the early returns, so a summary shows the run that stopped.
    tally_run "$rc"

    # Exit 3 is a missing prerequisite or a missing suite. Repeating it N times
    # produces N copies of the same error, so stop and say which run stopped.
    if [ "$rc" -eq 3 ]; then
      echo ""
      echo "  Stopping after run $run_no: prerequisites missing, and repeating cannot fix that."
      return 3
    fi
    # Exit 4 is the nested session not executing. That is the runner or the
    # host, not the scenario, and N more sessions would stop the same way.
    if [ "$rc" -eq 4 ]; then
      echo ""
      echo "  Stopping after run $run_no: the nested session did not execute, and repeating cannot fix that."
      return 4
    fi
    [ "$rc" -eq 2 ] && saw_infra=1

    local run_passed="$TALLY_LAST_PASSED" run_total="$TALLY_LAST_GRADED"
    passed_assertions=$((passed_assertions + run_passed))
    total_assertions=$((total_assertions + run_total))

    local verdict="FAIL"
    if [ "$rc" -eq 0 ]; then
      verdict="PASS"
      runs_passed=$((runs_passed + 1))
    fi
    per_run="$per_run$run_no|$verdict|$run_passed|$run_total|${PREP_ITER_DIR:-unknown}
"
    run_no=$((run_no + 1))
  done

  echo ""
  if [ -n "$EVAL_SCENARIO_FILTER" ]; then
    echo "=== Pass rate over $runs runs: $skill_name / $EVAL_SCENARIO_FILTER ==="
  else
    echo "=== Pass rate over $runs runs: $skill_name (whole suite) ==="
  fi
  printf '%s' "$per_run" | while IFS='|' read -r n verdict p t dir; do
    [ -n "$n" ] || continue
    echo "  Run $n: $verdict  ($p/$t assertions)  $dir"
  done

  local run_rate="0.0"
  if [ "$runs" -gt 0 ]; then
    run_rate=$(python3 -c "print(f'{100.0 * $runs_passed / $runs:.1f}')")
  fi
  local assertion_rate="n/a"
  if [ "$total_assertions" -gt 0 ]; then
    assertion_rate=$(python3 -c "print(f'{100.0 * $passed_assertions / $total_assertions:.1f}%')")
  fi

  echo ""
  echo "  Pass rate:           $runs_passed/$runs runs ($run_rate%)"
  echo "  Assertion pass rate: $passed_assertions/$total_assertions ($assertion_rate)"

  if [ "$runs_passed" -eq "$runs" ]; then
    return 0
  fi
  if [ "$saw_infra" -eq 1 ]; then
    return 2
  fi
  return 1
}

# ---------------------------------------------------------------------------
# The per-skill tally behind --summary-out. begin_skill_tally resets it,
# tally_run adds one run_skill_evals result to it (reading PREP_ITER_DIR, which
# the caller clears before each run), and record_skill_summary appends the
# skill's entry to SUMMARY_LINES. write_summary turns those lines into the
# summary file. TALLY_LAST_* hold the run just tallied, for the --runs report.
# ---------------------------------------------------------------------------
TALLY_RUNS=0
TALLY_RUNS_PASSED=0
TALLY_ASSERTIONS_PASSED=0
TALLY_ASSERTIONS_GRADED=0
TALLY_ITER_DIRS=()
TALLY_LAST_PASSED=0
TALLY_LAST_GRADED=0

begin_skill_tally() {
  TALLY_RUNS=0
  TALLY_RUNS_PASSED=0
  TALLY_ASSERTIONS_PASSED=0
  TALLY_ASSERTIONS_GRADED=0
  TALLY_ITER_DIRS=()
}

tally_run() { # tally_run <exit code of run_skill_evals>
  local rc="$1" tally="0 0"
  TALLY_RUNS=$((TALLY_RUNS + 1))
  [ "$rc" -eq 0 ] && TALLY_RUNS_PASSED=$((TALLY_RUNS_PASSED + 1))
  if [ -n "$PREP_ITER_DIR" ]; then
    TALLY_ITER_DIRS+=("$PREP_ITER_DIR")
    if [ -f "$PREP_ITER_DIR/validation_summary.json" ]; then
      tally=$(python3 -c "
import json, sys
s = json.load(open(sys.argv[1]))
print(int(s['passed_assertions']), int(s['total_assertions']))
" "$PREP_ITER_DIR/validation_summary.json" 2>/dev/null || echo "0 0")
    fi
  fi
  TALLY_LAST_PASSED=$(echo "$tally" | cut -d' ' -f1)
  TALLY_LAST_GRADED=$(echo "$tally" | cut -d' ' -f2)
  TALLY_ASSERTIONS_PASSED=$((TALLY_ASSERTIONS_PASSED + TALLY_LAST_PASSED))
  TALLY_ASSERTIONS_GRADED=$((TALLY_ASSERTIONS_GRADED + TALLY_LAST_GRADED))
}

record_skill_summary() { # record_skill_summary <skill> <exit code>
  [ -n "$SUMMARY_OUT" ] || return 0
  python3 - "$SUMMARY_LINES" "$1" "$TALLY_RUNS" "$TALLY_RUNS_PASSED" \
    "$TALLY_ASSERTIONS_PASSED" "$TALLY_ASSERTIONS_GRADED" "$2" \
    ${TALLY_ITER_DIRS[@]+"${TALLY_ITER_DIRS[@]}"} <<'PYEOF'
import glob, json, os, sys

out, name = sys.argv[1], sys.argv[2]
runs, runs_passed, a_passed, a_graded, exit_code = (int(v) for v in sys.argv[3:8])
models = set()
for iter_dir in sys.argv[8:]:
    for meta in glob.glob(os.path.join(iter_dir, "*", "eval_metadata.json")):
        try:
            with open(meta) as fh:
                model = json.load(fh).get("model")
        except (OSError, ValueError):
            continue
        if isinstance(model, str) and model:
            models.add(model)
entry = {
    "runs": runs,
    "runs_passed": runs_passed,
    "assertions_passed": a_passed,
    "assertions_graded": a_graded,
    "models": sorted(models),
    "exit_code": exit_code,
}
with open(out, "a") as fh:
    fh.write(json.dumps({"skill": name, "entry": entry}) + "\n")
PYEOF
}

write_summary() {
  [ -n "$SUMMARY_OUT" ] || return 0
  if ! python3 - "$SUMMARY_LINES" "$SUMMARY_OUT" <<'PYEOF'
import json, sys

skills = {}
with open(sys.argv[1]) as fh:
    for line in fh:
        if line.strip():
            record = json.loads(line)
            skills[record["skill"]] = record["entry"]
with open(sys.argv[2], "w") as fh:
    json.dump({"schema": "run-evals-summary/v1", "skills": skills}, fh, indent=2, sort_keys=True)
    fh.write("\n")
PYEOF
  then
    echo "Error: could not write the summary to $SUMMARY_OUT" >&2
    return 1
  fi
}

cleanup_summary_lines() {
  if [ -n "$SUMMARY_LINES" ] && [ -f "$SUMMARY_LINES" ]; then
    rm -f "$SUMMARY_LINES"
  fi
}

# One skill, once or --runs times, tallied for --summary-out.
run_skill() { # run_skill <skill>
  local name="$1" rc=0
  begin_skill_tally
  if [ "$EVAL_RUNS" -gt 1 ]; then
    run_skill_evals_repeated "$name" "$EVAL_RUNS" || rc=$?
  else
    PREP_ITER_DIR=""
    run_skill_evals "$name" || rc=$?
    tally_run "$rc"
  fi
  record_skill_summary "$name" "$rc"
  return "$rc"
}

# Several skills with --all's failure collection and exit precedence. Returns
# the exit code rather than exiting, so the caller can write the summary first.
run_skill_list() { # run_skill_list <skill>...
  local failed_skills=() infra_failed=() not_executed=() name rc
  for name in "$@"; do
    rc=0
    run_skill "$name" || rc=$?
    if [ "$rc" -ne 0 ]; then
      if [ "$rc" -eq 4 ]; then
        not_executed+=("$name")
      elif [ "$rc" -eq 2 ] || [ "$rc" -eq 3 ]; then
        infra_failed+=("$name")
      else
        failed_skills+=("$name")
      fi
    fi
    echo ""
  done
  echo "=== Summary ==="
  if [ ${#failed_skills[@]} -gt 0 ]; then
    echo "  Failed assertions: ${failed_skills[*]}"
  fi
  if [ ${#infra_failed[@]} -gt 0 ]; then
    echo "  Infrastructure failures: ${infra_failed[*]}"
  fi
  if [ ${#not_executed[@]} -gt 0 ]; then
    echo "  Nested session did not execute: ${not_executed[*]}"
  fi
  if [ ${#failed_skills[@]} -eq 0 ] && [ ${#infra_failed[@]} -eq 0 ] && [ ${#not_executed[@]} -eq 0 ]; then
    echo "  All skills passed."
  fi
  # A failed assertion outranks everything, as before. A session that never
  # executed outranks a plain infra failure because it has one known cause to
  # fix, and fixing it may be what clears the other skills' exit 2s.
  [ ${#failed_skills[@]} -gt 0 ] && return 1
  [ ${#not_executed[@]} -gt 0 ] && return 4
  [ ${#infra_failed[@]} -gt 0 ] && return 2
  return 0
}

# Write the summary, when one was asked for, and exit with the run's code.
finish() { # finish <exit code>
  local rc="$1"
  write_summary || { [ "$rc" -eq 0 ] && rc=2; }
  exit "$rc"
}

# Main
parse_run_options "$@"
set -- ${PARSED_ARGS[@]+"${PARSED_ARGS[@]}"}

if [ -n "$SUMMARY_OUT" ]; then
  SUMMARY_LINES=$(mktemp "${TMPDIR:-/tmp}/run-evals-summary.XXXXXX") || {
    echo "Error: could not create a temporary file for the summary"
    exit 3
  }
  trap 'cleanup_run_dirs; cleanup_summary_lines' EXIT
fi

# No skill name: the skills changed since the last v* tag.
if [ $# -eq 0 ]; then
  if [ -n "$EVAL_SCENARIO_FILTER" ]; then
    echo "Error: --scenario names one eval in one suite; use it with a skill name"
    exit 1
  fi
  select_changed_skills || exit 2
  if [ -z "$CHANGED_TAG" ]; then
    echo "No v* tag found; selecting every skill with evals."
  fi
  if [ ${#CHANGED_SKILLS[@]} -eq 0 ]; then
    if [ -n "$CHANGED_TAG" ]; then
      echo "No skill with evals changed since $CHANGED_TAG."
    else
      echo "No skill has evals."
    fi
    finish 0
  fi
  if [ -n "$CHANGED_TAG" ]; then
    echo "Skills with evals changed since $CHANGED_TAG: ${CHANGED_SKILLS[*]}"
  else
    echo "Skills with evals: ${CHANGED_SKILLS[*]}"
  fi
  echo ""
  rc=0
  run_skill_list "${CHANGED_SKILLS[@]}" || rc=$?
  finish "$rc"
fi

case "$1" in
  --list)
    echo "Skills with evals:"
    list_skills_with_evals
    ;;
  --list-changed)
    select_changed_skills || exit 2
    # stdout carries the names alone, for callers to read; the note goes to
    # stderr.
    if [ -z "$CHANGED_TAG" ]; then
      echo "No v* tag found; selecting every skill with evals." >&2
    fi
    for name in ${CHANGED_SKILLS[@]+"${CHANGED_SKILLS[@]}"}; do
      printf '%s\n' "$name"
    done
    exit 0
    ;;
  --all)
    if [ -n "$EVAL_SCENARIO_FILTER" ]; then
      echo "Error: --scenario names one eval in one suite; use it with a skill name, not --all"
      exit 1
    fi
    all_skills=()
    for skill_dir in "$SKILLS_DIR"/*/; do
      if [ -f "$skill_dir/evals/evals.json" ]; then
        all_skills+=("$(basename "$skill_dir")")
      fi
    done
    rc=0
    run_skill_list ${all_skills[@]+"${all_skills[@]}"} || rc=$?
    finish "$rc"
    ;;
  --prep-only)
    if [ $# -lt 2 ]; then
      echo "Usage: $0 --prep-only <skill-name>"
      exit 1
    fi
    prep_skill_evals "$2" || exit $?
    iter_dir="$PREP_ITER_DIR"
    echo ""
    echo "Workspace ready. To run evals interactively:"
    echo "  Use /skill-creator in Claude Code with this workspace: $iter_dir"
    echo "  Skill path: $SKILLS_DIR/$2/SKILL.md"
    echo ""
    echo "To validate results after running:"
    echo "  $0 --validate $2"
    ;;
  --validate)
    if [ $# -lt 2 ]; then
      echo "Usage: $0 --validate <skill-name>"
      exit 1
    fi
    skill_name="$2"
    workspace="$SKILLS_DIR/$skill_name/evals/workspace"
    iteration=$(latest_iteration "$workspace")
    if [ "$iteration" -eq 0 ]; then
      echo "Error: no iterations found in $workspace"
      exit 2
    fi
    iter_dir="$workspace/iteration-$iteration"
    eval_count=$(EVAL_SCENARIO_FILTER="$EVAL_SCENARIO_FILTER" python3 -c "
import json, os
sel = os.environ.get('EVAL_SCENARIO_FILTER', '')
evals = json.load(open('$SKILLS_DIR/$skill_name/evals/evals.json'))['evals']
if sel:
    evals = [e for e in evals if e.get('name') == sel]
print(len(evals))
")
    echo "=== Validating iteration $iteration for $skill_name ==="
    validate_results "$iter_dir" "$eval_count"
    ;;
  --help|-h)
    usage
    ;;
  -*)
    echo "Error: unknown option '$1'"
    usage
    ;;
  *)
    rc=0
    run_skill "$1" || rc=$?
    finish "$rc"
    ;;
esac
