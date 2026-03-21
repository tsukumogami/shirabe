#!/usr/bin/env bash
# run-evals.sh - Run skill evals using /skill-creator
#
# Usage:
#   scripts/run-evals.sh <skill-name>        Run evals for one skill
#   scripts/run-evals.sh --all               Run evals for all skills
#   scripts/run-evals.sh --list              List skills with evals
#
# Each skill's evals live at skills/<name>/evals/evals.json.
# Results go to skills/<name>/evals/workspace/iteration-<N>/.
#
# The script prepares the workspace, then invokes claude -p with
# /skill-creator loaded to run the actual evals. After execution,
# it validates results and generates the eval viewer.
#
# Prerequisites: claude CLI, python3, skill-creator plugin installed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

# Find the skill-creator's eval viewer
SKILL_CREATOR_PATH=""
for candidate in \
  "$HOME/.claude/plugins/cache/claude-plugins-official/skill-creator"/*/skills/skill-creator \
  "$HOME/.claude/plugins/cache/anthropic-agent-skills/skill-creator"/*/skills/skill-creator; do
  if [ -d "$candidate/eval-viewer" ]; then
    SKILL_CREATOR_PATH="$candidate"
    break
  fi
done

usage() {
  echo "Usage: $0 <skill-name> | --all | --list"
  echo ""
  echo "  <skill-name>   Run evals for a specific skill"
  echo "  --all          Run evals for all skills that have evals/"
  echo "  --list         List skills that have evals"
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

run_skill_evals() {
  local skill_name="$1"
  local skill_dir="$SKILLS_DIR/$skill_name"
  local evals_file="$skill_dir/evals/evals.json"

  if [ ! -f "$evals_file" ]; then
    echo "Error: no evals found at $evals_file"
    exit 1
  fi

  if [ ! -f "$skill_dir/SKILL.md" ]; then
    echo "Error: no SKILL.md found at $skill_dir/SKILL.md"
    exit 1
  fi

  local workspace="$skill_dir/evals/workspace"
  mkdir -p "$workspace"

  local iteration
  iteration=$(next_iteration "$workspace")
  local iter_dir="$workspace/iteration-$iteration"

  local eval_count
  eval_count=$(python3 -c "import json; print(len(json.load(open('$evals_file'))['evals']))")

  echo "=== Running evals for skill: $skill_name ==="
  echo "  Evals file: $evals_file"
  echo "  Eval count: $eval_count"
  echo "  Iteration: $iteration"
  echo "  Output: $iter_dir"
  echo ""

  # Step 1: Prepare workspace directories and metadata
  python3 << PYEOF
import json, os

with open("$evals_file") as f:
    data = json.load(f)

iter_dir = "$iter_dir"

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

    print(f"  Prepared: {eval_name}")

print(f"\nPrepared {len(data['evals'])} eval directories.")
PYEOF

  # Step 2: Run evals via claude -p with /skill-creator
  echo ""
  echo "Invoking claude with /skill-creator to run evals..."
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

Follow the skill-creator's "Running and evaluating test cases" workflow:
- Step 1: For each eval, spawn a with-skill agent (reads the skill SKILL.md then executes the prompt) and a without-skill baseline agent (same prompt, no skill). Save outputs to the respective outputs/ directories.
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
    local name
    name=$(basename "$eval_dir")
    # Skip non-directory entries
    [ -d "$eval_dir" ] || continue
    [[ "$name" == *.json ]] && continue
    [[ "$name" == *.html ]] && continue

    # Check with_skill outputs exist
    if [ ! -d "$eval_dir/with_skill/outputs" ] || [ -z "$(ls -A "$eval_dir/with_skill/outputs" 2>/dev/null)" ]; then
      missing_outputs+=("$name/with_skill")
    fi

    # Check without_skill outputs exist
    if [ ! -d "$eval_dir/without_skill/outputs" ] || [ -z "$(ls -A "$eval_dir/without_skill/outputs" 2>/dev/null)" ]; then
      missing_outputs+=("$name/without_skill")
    fi

    # Check grading exists and tally
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
      local gfile="$eval_dir/with_skill/grading.json"
      [ -f "$gfile" ] || continue
      python3 -c "
import json, os
with open('$gfile') as f:
    g = json.load(f)
exps = g if isinstance(g, list) else g.get('expectations', [])
name = os.path.basename(os.path.dirname(os.path.dirname('$gfile')))
for e in exps:
    if not e.get('passed', False):
        print(f'    [{name}] FAIL: {e.get(\"text\", \"unknown\")}')
        if e.get('evidence'):
            print(f'           {e[\"evidence\"]}')
" 2>/dev/null
    done
    return 1
  fi

  if [ "$graded" -eq 0 ]; then
    echo ""
    echo "  WARNING: No evals were graded. The claude session may not have produced results."
    echo "  Check the eval workspace: $iter_dir"
    return 1
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
    for skill_dir in "$SKILLS_DIR"/*/; do
      name=$(basename "$skill_dir")
      if [ -f "$skill_dir/evals/evals.json" ]; then
        run_skill_evals "$name"
        echo ""
      fi
    done
    ;;
  --help|-h)
    usage
    ;;
  *)
    run_skill_evals "$1"
    ;;
esac
