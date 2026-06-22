#!/usr/bin/env bash
# run-evals.sh - Run skill evals using /skill-creator
#
# Usage:
#   scripts/run-evals.sh <skill-name>        Run evals for one skill
#   scripts/run-evals.sh --all               Run evals for all skills
#   scripts/run-evals.sh --list              List skills with evals
#   scripts/run-evals.sh --validate <skill>  Re-validate existing results
#   scripts/run-evals.sh --prep-only <skill>      Prepare workspace only (for /skill-creator)
#
# Each skill's evals live at skills/<name>/evals/evals.json.
# Results go to skills/<name>/evals/workspace/iteration-<N>/.
#
# Exit codes:
#   0  All assertions passed
#   1  One or more assertions failed
#   2  No results produced (infrastructure failure)
#   3  Missing prerequisites
#
# Prerequisites: claude CLI, python3, skill-creator plugin installed
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
SKILLS_DIR="$REPO_ROOT/skills"

# Prerequisite checks
command -v claude >/dev/null 2>&1 || { echo "Error: claude CLI not found"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found"; exit 3; }

usage() {
  echo "Usage: $0 <skill-name> | --all | --list | --validate <skill> | --prep-only <skill>"
  echo ""
  echo "  <skill-name>       Run evals for a specific skill (prep + execute + validate)"
  echo "  --all              Run evals for all skills that have evals/"
  echo "  --list             List skills that have evals"
  echo "  --validate <skill> Re-validate the latest iteration without re-running"
  echo "  --prep-only <skill>     Prepare workspace only (use with /skill-creator in Claude Code)"
  exit 1
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
  eval_count=$(python3 -c "import json; print(len(json.load(open('$evals_file'))['evals']))")

  echo "=== Preparing evals for skill: $skill_name ==="
  echo "  Evals file: $evals_file"
  echo "  Eval count: $eval_count"
  echo "  Iteration: $iteration"
  echo "  Output: $iter_dir"
  echo ""

  python3 << PYEOF
import json, os, shutil

with open("$evals_file") as f:
    data = json.load(f)

iter_dir = "$iter_dir"
evals_dir = os.path.dirname("$evals_file")

for eval_item in data["evals"]:
    eval_id = eval_item["id"]
    eval_name = eval_item.get("name", f"eval-{eval_id}")
    prompt = eval_item["prompt"]

    eval_dir = os.path.join(iter_dir, eval_name)
    os.makedirs(os.path.join(eval_dir, "with_skill", "outputs"), exist_ok=True)
    os.makedirs(os.path.join(eval_dir, "without_skill", "outputs"), exist_ok=True)

    metadata = {
        "eval_id": eval_id,
        "eval_name": eval_name,
        "prompt": prompt,
        "assertions": eval_item.get("assertions", [])
    }
    with open(os.path.join(eval_dir, "eval_metadata.json"), "w") as f:
        json.dump(metadata, f, indent=2)

    # Copy fixture files to inputs/ if fixture_dir is specified
    fixture_dir_rel = eval_item.get("fixture_dir")
    if fixture_dir_rel:
        fixture_dir = os.path.join(evals_dir, fixture_dir_rel)
        if os.path.isdir(fixture_dir):
            inputs_dir = os.path.join(eval_dir, "inputs")
            if os.path.exists(inputs_dir):
                shutil.rmtree(inputs_dir)
            shutil.copytree(fixture_dir, inputs_dir)
            metadata["has_fixtures"] = True
            with open(os.path.join(eval_dir, "eval_metadata.json"), "w") as f:
                json.dump(metadata, f, indent=2)
            print(f"  Prepared: {eval_name} (with fixtures from {fixture_dir_rel})")
        else:
            print(f"  WARNING: fixture_dir not found: {fixture_dir}")
            print(f"  Prepared: {eval_name}")
    else:
        print(f"  Prepared: {eval_name}")

print(f"\nPrepared {len(data['evals'])} eval directories.")
PYEOF

  # Return values for callers
  echo "$iter_dir" > /tmp/run-evals-iter-dir
  echo "$eval_count" > /tmp/run-evals-eval-count
  echo "$iteration" > /tmp/run-evals-iteration
}

# Returns 0 if the skill's evals.json contains at least one tier-2 eval.
skill_has_tier2() {
  local evals_file="$1"
  python3 -c "
import json, sys
d = json.load(open('$evals_file'))
sys.exit(0 if any(e.get('tier', 1) == 2 for e in d['evals']) else 1)
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
  iso_root=$(mktemp -d "${TMPDIR:-/tmp}/shirabe-eval-iso.XXXXXX") || return 1
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
    git push --quiet --set-upstream origin "$branch" >/dev/null 2>&1
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

# Belt-and-suspenders: ensure the sandbox is removed even if the run exits early
# (failed assertions, signal, or error) before run_skill_evals reaches cleanup.
trap cleanup_tier2_isolation EXIT

run_skill_evals() {
  local skill_name="$1"
  local skill_dir="$SKILLS_DIR/$skill_name"
  local evals_file="$skill_dir/evals/evals.json"

  # Step 1: Prepare
  prep_skill_evals "$skill_name" || return $?

  local iter_dir eval_count iteration
  iter_dir=$(cat /tmp/run-evals-iter-dir)
  eval_count=$(cat /tmp/run-evals-eval-count)
  iteration=$(cat /tmp/run-evals-iteration)

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
      tier2_isolation_block=$(cat <<ISOBLOCK

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
ISOBLOCK
)
    else
      echo "  WARNING: failed to set up isolated checkout for tier-2 evals." >&2
      echo "  Refusing to run tier-2 evals against the live working tree." >&2
      cleanup_tier2_isolation
      return 2
    fi
  fi

  # Step 2: Build tier-specific instructions for each eval.
  # When tier-2 isolation is active, point the shimmed-bin path at the clone's
  # copy of the fixtures so the agent's PATH shim and working directory stay
  # consistent inside the sandbox.
  local fixtures_bin="$skill_dir/evals/fixtures/bin"
  if [ -n "$tier2_checkout" ]; then
    fixtures_bin="$tier2_checkout/skills/$skill_name/evals/fixtures/bin"
  fi
  local tier_instructions
  tier_instructions=$(python3 << PYEOF
import json

with open("$evals_file") as f:
    data = json.load(f)

lines = []
for ev in data["evals"]:
    tier = ev.get("tier", 1)
    name = ev.get("name", f"eval-{ev['id']}")
    if tier == 2:
        scenario = ev.get("scenario", "")
        lines.append(f"- {name}: TIER 2 (execute) — set EVAL_SCENARIO={scenario}, prepend $fixtures_bin to PATH. "
                     f"Instruct agent: 'Execute the workflow. gh and koto are available on PATH.'")
    else:
        lines.append(f"- {name}: TIER 1 (plan_only) — "
                     f"Instruct agent: 'Read the skill file and describe the exact sequence of commands you would run. Do NOT execute any commands.'")

print("\\n".join(lines))
PYEOF
)

  # Step 3: Run evals via claude -p with /skill-creator
  echo ""
  echo "Invoking claude with /skill-creator to run evals..."
  echo "(this may take several minutes)"
  echo ""

  local claude_exit=0
  claude -p "$(cat <<PROMPT
Invoke /skill-creator. You already have an existing skill with evals ready to run.

The skill is at: $skill_dir/SKILL.md
The evals are at: $evals_file
The eval workspace is prepared at: $iter_dir

Each eval directory in the workspace has:
- eval_metadata.json with the prompt and assertions
- with_skill/outputs/ (empty, for you to fill)
- without_skill/outputs/ (empty, for you to fill)

TIER-SPECIFIC INSTRUCTIONS:
Evals are split into two tiers. For each eval, apply the matching tier instruction below.

$tier_instructions

For tier 2 evals, before spawning the with-skill agent:
1. Set the EVAL_SCENARIO environment variable as specified above.
2. Prepend $fixtures_bin to PATH so the agent uses shimmed gh and koto binaries.
These environment variables must be passed to the spawned agent process.
$tier2_isolation_block

For tier 1 evals, the agent must NOT execute any commands. It should only read the
skill file and describe its planned execution sequence.

Follow the skill-creator's "Running and evaluating test cases" workflow:
- Step 1: For each eval, spawn a with-skill agent (reads the skill SKILL.md then executes the prompt) and a without-skill baseline agent (same prompt, no skill). Save outputs to the respective outputs/ directories.
  - IMPORTANT: If eval_metadata.json contains "has_fixtures": true, an inputs/ directory exists alongside it with pre-defined plan artifact files (e.g. plan_my-feature_analysis.md, plan_my-feature_issue_1.md, etc.). Before running the with-skill agent for that eval, treat those files as already present in wip/ — the skill should read them rather than improvising fixture content. The agent must use the provided fixture files as the plan artifacts under review, not invent new ones.
- Step 2: Grade each with-skill run against the assertions in eval_metadata.json. Write grading.json in each with_skill/ directory.
- Step 3: Capture timing data (total_tokens, duration_ms) to timing.json in each run directory.
- Step 4: Run the aggregation and generate the viewer to /tmp/${skill_name}-eval-review.html using --static mode.

This is iteration $iteration for the $skill_name skill.
PROMPT
)" 2>&1 || claude_exit=$?

  if [ "$claude_exit" -ne 0 ]; then
    echo ""
    echo "Warning: claude -p exited with status $claude_exit"
  fi

  # Step 3: Validate results
  echo ""
  echo "=== Validating results ==="
  validate_results "$iter_dir" "$eval_count"

  # Step 4: Open viewer if it was generated
  local viewer="/tmp/${skill_name}-eval-review.html"
  if [ -f "$viewer" ]; then
    echo ""
    echo "Open the eval viewer:"
    echo "  xdg-open $viewer"
  fi

  # Tear down the tier-2 isolation sandbox (if one was created for this skill).
  cleanup_tier2_isolation
}

validate_results() {
  local iter_dir="$1"
  local expected_count="$2"
  local graded=0
  local missing_outputs=()
  local missing_grading=()
  local total_assertions=0
  local passed_assertions=0
  local failed_assertions=0

  for eval_dir in "$iter_dir"/*/; do
    [ -d "$eval_dir" ] || continue
    local name
    name=$(basename "$eval_dir")
    # Skip non-eval entries
    [[ "$name" == *.json ]] && continue
    [[ "$name" == *.html ]] && continue
    [[ "$name" == *.md ]] && continue

    # Check with_skill outputs exist
    if [ ! -d "$eval_dir/with_skill/outputs" ] || [ -z "$(ls -A "$eval_dir/with_skill/outputs" 2>/dev/null)" ]; then
      missing_outputs+=("$name/with_skill")
    fi

    # Check without_skill outputs exist
    if [ ! -d "$eval_dir/without_skill/outputs" ] || [ -z "$(ls -A "$eval_dir/without_skill/outputs" 2>/dev/null)" ]; then
      missing_outputs+=("$name/without_skill")
    fi

    # Check grading exists and tally
    # Only with_skill is graded against assertions; without_skill is the baseline
    if [ -f "$eval_dir/with_skill/grading.json" ]; then
      graded=$((graded + 1))
      local counts
      counts=$(python3 -c "
import json
with open('$eval_dir/with_skill/grading.json') as f:
    g = json.load(f)
# Handle both formats: {expectations: [...]} and bare [...]
exps = g if isinstance(g, list) else g.get('expectations', [])
p = sum(1 for e in exps if e.get('passed', False))
print(f'{len(exps)} {p}')
" 2>/dev/null || echo "0 0")
      local total passed
      total=$(echo "$counts" | cut -d' ' -f1)
      passed=$(echo "$counts" | cut -d' ' -f2)
      total_assertions=$((total_assertions + total))
      passed_assertions=$((passed_assertions + passed))
      failed_assertions=$((failed_assertions + total - passed))
    else
      missing_grading+=("$name")
    fi
  done

  echo "  Evals expected: $expected_count"
  echo "  Evals graded:   $graded"
  echo "  Assertions:     $passed_assertions/$total_assertions passed"

  if [ ${#missing_outputs[@]} -gt 0 ]; then
    echo ""
    echo "  Missing outputs:"
    for m in "${missing_outputs[@]}"; do
      echo "    - $m"
    done
  fi

  if [ ${#missing_grading[@]} -gt 0 ]; then
    echo ""
    echo "  Missing grading:"
    for m in "${missing_grading[@]}"; do
      echo "    - $m"
    done
  fi

  if [ "$failed_assertions" -gt 0 ]; then
    echo ""
    echo "  FAILED ASSERTIONS: $failed_assertions"
    for eval_dir in "$iter_dir"/*/; do
      [ -d "$eval_dir" ] || continue
      local gfile="$eval_dir/with_skill/grading.json"
      [ -f "$gfile" ] || continue
      local ename
      ename=$(basename "$eval_dir")
      python3 -c "
import json
with open('$gfile') as f:
    g = json.load(f)
exps = g if isinstance(g, list) else g.get('expectations', [])
for e in exps:
    if not e.get('passed', False):
        print(f'    [$ename] FAIL: {e.get(\"text\", \"unknown\")}')
        if e.get('evidence'):
            print(f'           {e[\"evidence\"]}')
" 2>/dev/null
    done
    return 1
  fi

  if [ "$graded" -eq 0 ]; then
    echo ""
    echo "  WARNING: No evals were graded. The claude session may not have produced results."
    echo "  Re-run or check the workspace: $iter_dir"
    return 2
  fi

  echo ""
  echo "  All assertions passed."
  return 0
}

# Main
if [ $# -eq 0 ]; then
  usage
fi

case "$1" in
  --list)
    echo "Skills with evals:"
    list_skills_with_evals
    ;;
  --all)
    failed_skills=()
    infra_failed=()
    for skill_dir in "$SKILLS_DIR"/*/; do
      name=$(basename "$skill_dir")
      if [ -f "$skill_dir/evals/evals.json" ]; then
        if ! run_skill_evals "$name"; then
          rc=$?
          if [ "$rc" -eq 2 ] || [ "$rc" -eq 3 ]; then
            infra_failed+=("$name")
          else
            failed_skills+=("$name")
          fi
        fi
        echo ""
      fi
    done
    echo "=== Summary ==="
    if [ ${#failed_skills[@]} -gt 0 ]; then
      echo "  Failed assertions: ${failed_skills[*]}"
    fi
    if [ ${#infra_failed[@]} -gt 0 ]; then
      echo "  Infrastructure failures: ${infra_failed[*]}"
    fi
    if [ ${#failed_skills[@]} -eq 0 ] && [ ${#infra_failed[@]} -eq 0 ]; then
      echo "  All skills passed."
    fi
    [ ${#failed_skills[@]} -gt 0 ] && exit 1
    [ ${#infra_failed[@]} -gt 0 ] && exit 2
    exit 0
    ;;
  --prep-only)
    if [ $# -lt 2 ]; then
      echo "Usage: $0 --prep-only <skill-name>"
      exit 1
    fi
    prep_skill_evals "$2"
    iter_dir=$(cat /tmp/run-evals-iter-dir)
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
    eval_count=$(python3 -c "import json; print(len(json.load(open('$SKILLS_DIR/$skill_name/evals/evals.json'))['evals']))")
    echo "=== Validating iteration $iteration for $skill_name ==="
    validate_results "$iter_dir" "$eval_count"
    ;;
  --help|-h)
    usage
    ;;
  *)
    run_skill_evals "$1"
    ;;
esac
