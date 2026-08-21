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
# Options (combine with <skill-name>):
#   --scenario <name>  Run only the named eval from that skill's suite
#   --runs <N>         Run the selection N times and report a pass rate
#
# Each skill's evals live at skills/<name>/evals/evals.json.
# Results go to skills/<name>/evals/workspace/iteration-<N>/.
#
# Exit codes:
#   0  All assertions passed
#   1  One or more assertions failed
#   2  No results produced, or a scenario graded zero assertions
#      (infrastructure failure -- see "Grading nothing is a failure" below)
#   3  Missing prerequisites
#
# Prerequisites: claude CLI, python3, skill-creator plugin installed
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

# Prerequisite checks
command -v claude >/dev/null 2>&1 || { echo "Error: claude CLI not found"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found"; exit 3; }

usage() {
  echo "Usage: $0 [--scenario <name>] [--runs <N>] <skill-name>"
  echo "       $0 --all | --list | --validate <skill> | --prep-only <skill>"
  echo ""
  echo "  <skill-name>       Run evals for a specific skill (prep + execute + validate)"
  echo "  --all              Run evals for all skills that have evals/"
  echo "  --list             List skills that have evals"
  echo "  --validate <skill> Re-validate the latest iteration without re-running"
  echo "  --prep-only <skill>     Prepare workspace only (use with /skill-creator in Claude Code)"
  echo ""
  echo "  --scenario <name>  Restrict the run to one eval, by its 'name' in evals.json"
  echo "  --runs <N>         Repeat the run N times and report a pass rate across them"
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

  EVAL_SCENARIO_FILTER="$EVAL_SCENARIO_FILTER" REPO_ROOT="$REPO_ROOT" python3 << PYEOF
import hashlib, json, os, shutil

with open("$evals_file") as f:
    data = json.load(f)

iter_dir = "$iter_dir"
evals_dir = os.path.dirname("$evals_file")
fixtures_root = os.path.join(evals_dir, "fixtures")
repo_root = os.environ["REPO_ROOT"]
selected = os.environ.get("EVAL_SCENARIO_FILTER", "")

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
  local preflight_fixture="$skill_dir/evals/fixtures/preflight-liveness"
  if [ -n "$tier2_checkout" ]; then
    fixtures_bin="$tier2_checkout/skills/$skill_name/evals/fixtures/bin"
    preflight_fixture="$tier2_checkout/skills/$skill_name/evals/fixtures/preflight-liveness"
  fi
  local tier_instructions
  tier_instructions=$(EVAL_SCENARIO_FILTER="$EVAL_SCENARIO_FILTER" python3 << PYEOF
import json, os

with open("$evals_file") as f:
    data = json.load(f)

selected = os.environ.get("EVAL_SCENARIO_FILTER", "")

lines = []
for ev in data["evals"]:
    tier = ev.get("tier", 1)
    name = ev.get("name", f"eval-{ev['id']}")
    if selected and name != selected:
        continue
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
                     f"run (claude --plugin-dir <fixture-path> -p ...), invoke the skill /{target} "
                     f"in that run, and report VERBATIM everything the nested run put in front of "
                     f"the model before the skill body, plus a byte count. Do not call "
                     f"scripts/skill-preflight.sh yourself — the point is the skill load, not the "
                     f"script.'")
        continue
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
  - IMPORTANT: If eval_metadata.json contains "has_fixtures": true, an inputs/ directory exists alongside it with pre-defined plan artifact files (e.g. plan_my-feature_analysis.md, plan_my-feature_issue_1.md, etc.). Before running the with-skill agent for that eval, treat those files as already present in wip/ — the skill should read them rather than improvising fixture content. The agent must use the provided fixture files as the plan artifacts under review, not invent new ones.
- Step 2: Grade each with-skill run against the assertions in eval_metadata.json. Write grading.json in each with_skill/ directory. Grade EVERY assertion listed there — one entry in grading.json per assertion. A scenario whose grading.json comes back empty fails the run.
- Step 3: Capture timing data (total_tokens, duration_ms) to timing.json in each run directory.
- Step 4: Run the aggregation and generate the viewer to /tmp/${skill_name}-eval-review.html using --static mode.

This is iteration $iteration for the $skill_name skill.
PROMPT
)" 2>&1 || claude_exit=$?

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

  # Step 5: Open viewer if it was generated
  local viewer="/tmp/${skill_name}-eval-review.html"
  if [ -f "$viewer" ]; then
    echo ""
    echo "Open the eval viewer:"
    echo "  xdg-open $viewer"
  fi

  # Tear down the tier-2 isolation sandbox (if one was created for this skill).
  cleanup_tier2_isolation

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
# 2 nothing was graded, or some scenario graded zero of its criteria.
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
# evidence. The exit status is 0 only when every run passed; the rate is printed
# either way, since a rate is the point of asking.
run_skill_evals_repeated() {
  local skill_name="$1"
  local runs="$2"

  local run_no=1
  local runs_passed=0
  local total_assertions=0
  local passed_assertions=0
  local per_run=""

  while [ "$run_no" -le "$runs" ]; do
    echo ""
    echo "########## Run $run_no of $runs ##########"
    # Clear first: prep_skill_evals returns early on a missing suite without
    # setting this, and a stale value would make the run below read the previous
    # run's tally and report it as this one's.
    PREP_ITER_DIR=""
    local rc=0
    run_skill_evals "$skill_name" || rc=$?

    # Exit 3 is a missing prerequisite or a missing suite. Repeating it N times
    # produces N copies of the same error, so stop and say which run stopped.
    if [ "$rc" -eq 3 ]; then
      echo ""
      echo "  Stopping after run $run_no: prerequisites missing, and repeating cannot fix that."
      return 3
    fi

    local tally="0 0"
    if [ -n "$PREP_ITER_DIR" ] && [ -f "$PREP_ITER_DIR/validation_summary.json" ]; then
      tally=$(python3 -c "
import json
s = json.load(open('$PREP_ITER_DIR/validation_summary.json'))
print(s['passed_assertions'], s['total_assertions'])
" 2>/dev/null || echo "0 0")
    fi
    local run_passed run_total
    run_passed=$(echo "$tally" | cut -d' ' -f1)
    run_total=$(echo "$tally" | cut -d' ' -f2)
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
  return 1
}

# Main
if [ $# -eq 0 ]; then
  usage
fi

parse_run_options "$@"
set -- ${PARSED_ARGS[@]+"${PARSED_ARGS[@]}"}

if [ $# -eq 0 ]; then
  usage
fi

case "$1" in
  --list)
    echo "Skills with evals:"
    list_skills_with_evals
    ;;
  --all)
    if [ -n "$EVAL_SCENARIO_FILTER" ]; then
      echo "Error: --scenario names one eval in one suite; use it with a skill name, not --all"
      exit 1
    fi
    failed_skills=()
    infra_failed=()
    for skill_dir in "$SKILLS_DIR"/*/; do
      name=$(basename "$skill_dir")
      if [ -f "$skill_dir/evals/evals.json" ]; then
        rc=0
        if [ "$EVAL_RUNS" -gt 1 ]; then
          run_skill_evals_repeated "$name" "$EVAL_RUNS" || rc=$?
        else
          run_skill_evals "$name" || rc=$?
        fi
        if [ "$rc" -ne 0 ]; then
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
    if [ "$EVAL_RUNS" -gt 1 ]; then
      run_skill_evals_repeated "$1" "$EVAL_RUNS"
    else
      run_skill_evals "$1"
    fi
    ;;
esac
