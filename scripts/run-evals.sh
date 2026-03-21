#!/usr/bin/env bash
# run-evals.sh - Run skill evals using the skill-creator pattern
#
# Usage:
#   scripts/run-evals.sh <skill-name>        Run evals for one skill
#   scripts/run-evals.sh --all               Run evals for all skills
#   scripts/run-evals.sh --list              List skills with evals
#
# Each skill's evals live at skills/<name>/evals/evals.json.
# Results go to skills/<name>/evals/workspace/iteration-<N>/.
#
# The script spawns agents with and without the skill loaded,
# collects outputs, and generates an eval viewer for human review.
#
# Prerequisites: claude CLI, python3

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

  # Extract eval prompts and spawn agents
  python3 << PYEOF
import json, subprocess, os, sys

with open("$evals_file") as f:
    data = json.load(f)

skill_path = "$skill_dir/SKILL.md"
iter_dir = "$iter_dir"
skill_name = "$skill_name"

for eval_item in data["evals"]:
    eval_id = eval_item["id"]
    eval_name = eval_item.get("name", f"eval-{eval_id}")
    prompt = eval_item["prompt"]

    eval_dir = os.path.join(iter_dir, eval_name)
    os.makedirs(os.path.join(eval_dir, "with_skill", "outputs"), exist_ok=True)
    os.makedirs(os.path.join(eval_dir, "without_skill", "outputs"), exist_ok=True)

    # Write eval metadata
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

  # Run evals via claude -p
  echo "Running evals via claude..."
  echo ""

  claude -p "$(cat <<PROMPT
You are running evals for the $skill_name skill. Use the /skill-creator workflow.

Skill path: $skill_dir/SKILL.md
Eval workspace: $iter_dir
Evals file: $evals_file

For each eval in the workspace:
1. Read the eval_metadata.json to get the prompt
2. Spawn a with-skill agent: read the skill's SKILL.md, then execute the prompt. Save outputs to the with_skill/outputs/ directory.
3. Spawn a without-skill agent: execute the same prompt without reading any skill files. Save outputs to the without_skill/outputs/ directory.
4. Launch both agents in parallel per eval, and run all evals in parallel.
5. After all agents complete, grade each with-skill run against the assertions in eval_metadata.json. Write grading.json with fields: text, passed, evidence.
6. Save timing.json for each run with total_tokens and duration_ms.

After grading, report a summary: how many assertions passed vs failed, and any notable differences between with-skill and without-skill outputs.
PROMPT
)" 2>&1 || echo "Warning: claude -p exited with non-zero status"

  # Generate viewer
  if [ -n "$SKILL_CREATOR_PATH" ]; then
    echo ""
    echo "Generating eval viewer..."
    python3 "$SKILL_CREATOR_PATH/eval-viewer/generate_review.py" \
      "$iter_dir" \
      --skill-name "$skill_name" \
      --static "/tmp/${skill_name}-eval-review.html" 2>/dev/null \
      && echo "Viewer: /tmp/${skill_name}-eval-review.html" \
      || echo "Warning: viewer generation failed (results may be incomplete)"
  fi
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
