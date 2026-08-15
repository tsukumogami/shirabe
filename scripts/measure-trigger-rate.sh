#!/usr/bin/env bash
#
# measure-trigger-rate.sh - measure how often /execute is selected for
# plan-shaped prompts, and record the result.
#
# The prompt set is skills/execute/evals/trigger-set.json: a bare JSON list of
# {query, should_trigger} objects, which is the shape skill-creator's
# run_eval.py parses. It is deliberately NOT skills/execute/evals/evals.json --
# that file is an object, not a list, and scripts/check-evals-exist.sh keys on
# that literal filename.
#
# Usage:
#   scripts/measure-trigger-rate.sh --label <name> [options]
#
# Options:
#   --label <name>          required; names the run in the results file
#                           (e.g. baseline, baseline-repeat, rewritten)
#   --runs-per-query <n>    runs per query, default 5
#   --workers <n>           parallel workers, default 10
#   --timeout <s>           per-query timeout in seconds, default 60
#   --description <text>    measure this description instead of the one
#                           currently in skills/execute/SKILL.md
#   --description-file <p>  same, read from a file. Use this to re-measure a
#                           description recorded in an earlier run, which is
#                           how an old baseline gets reproduced after the
#                           frontmatter has moved on.
#   --note <text>           free-text note recorded with the run
#   --model <name>          model for the selector, default the user's
#   --results <path>        results file, default skills/execute/evals/trigger-results.json
#   -h, --help              this message
#
# What gets reported
#
#   The QUANTIZED per-query pass rate: a query passes when it triggers on a
#   majority of its runs (rate >= 0.5) and the expectation was trigger, or when
#   it stays under that threshold and the expectation was no-trigger. The rate
#   is passing queries over total queries.
#
#   The continuous per-run trigger rate is not the headline number. The selector
#   is stochastic and run_eval.py shells out to `claude -p` with no seed and no
#   temperature control, so a continuous rate wanders between runs over an
#   unchanged set. Quantizing at a majority vote absorbs that.
#
# Tolerance band
#
#   +/- 1 query on a 20-query set, i.e. +/- 5 percentage points. Two runs over
#   an unchanged set agree when their pass counts differ by at most 1. The
#   script prints the comparison against the previous recorded run. This is a
#   declared band, not a reproducibility claim: exact reproducibility is not
#   achievable against a stochastic selector and is not claimed anywhere here.
#
# Prerequisites: claude CLI, python3, and the skill-creator plugin. Set
# SKILL_CREATOR_DIR to point at a skill-creator checkout elsewhere.
#
# Exit codes:
#   0 - the measurement ran and was recorded
#   2 - usage error
#   3 - missing prerequisite

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILL_DIR="$REPO_ROOT/skills/execute"
EVAL_SET="$SKILL_DIR/evals/trigger-set.json"
RESULTS="$SKILL_DIR/evals/trigger-results.json"

TOLERANCE_QUERIES=1

LABEL=""
RUNS_PER_QUERY=5
WORKERS=10
TIMEOUT=60
DESCRIPTION=""
DESCRIPTION_FILE=""
NOTE=""
MODEL=""

usage() {
    sed -n '3,55p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --label) LABEL="${2:-}"; shift 2 ;;
        --runs-per-query) RUNS_PER_QUERY="${2:-}"; shift 2 ;;
        --workers) WORKERS="${2:-}"; shift 2 ;;
        --timeout) TIMEOUT="${2:-}"; shift 2 ;;
        --description) DESCRIPTION="${2:-}"; shift 2 ;;
        --description-file) DESCRIPTION_FILE="${2:-}"; shift 2 ;;
        --note) NOTE="${2:-}"; shift 2 ;;
        --model) MODEL="${2:-}"; shift 2 ;;
        --results) RESULTS="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$LABEL" ]; then
    echo "error: --label is required" >&2
    exit 2
fi

if [ -n "$DESCRIPTION_FILE" ]; then
    if [ -n "$DESCRIPTION" ]; then
        echo "error: pass --description or --description-file, not both" >&2
        exit 2
    fi
    if [ ! -f "$DESCRIPTION_FILE" ]; then
        echo "error: no such description file: $DESCRIPTION_FILE" >&2
        exit 2
    fi
    DESCRIPTION="$(cat "$DESCRIPTION_FILE")"
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "error: the claude CLI is not on PATH" >&2
    exit 3
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is not on PATH" >&2
    exit 3
fi

if [ ! -f "$EVAL_SET" ]; then
    echo "error: no prompt set at $EVAL_SET" >&2
    exit 3
fi

# Locate skill-creator. run_eval.py imports scripts.utils, so its skill
# directory has to be on PYTHONPATH.
if [ -n "${SKILL_CREATOR_DIR:-}" ]; then
    SC_DIR="$SKILL_CREATOR_DIR"
else
    SC_DIR=""
    for candidate in "$HOME"/.claude/plugins/cache/*/skill-creator/*/skills/skill-creator; do
        if [ -f "$candidate/scripts/run_eval.py" ]; then
            SC_DIR="$candidate"
            break
        fi
    done
fi

if [ -z "$SC_DIR" ] || [ ! -f "$SC_DIR/scripts/run_eval.py" ]; then
    echo "error: could not find skill-creator's run_eval.py" >&2
    echo "       set SKILL_CREATOR_DIR to a skill-creator skill directory" >&2
    exit 3
fi

# run_loop.py is deliberately not used. It wraps the same measurement in an
# automatic description rewriter (improve_description), so pointing it at the
# description under test would rewrite the thing being measured.

RAW="$(mktemp -t trigger-rate.XXXXXX)"
trap 'rm -f "$RAW"' EXIT

echo "prompt set:      $EVAL_SET"
echo "skill:           $SKILL_DIR"
echo "runs per query:  $RUNS_PER_QUERY"
echo "label:           $LABEL"
echo ""

set -- --eval-set "$EVAL_SET" \
       --skill-path "$SKILL_DIR" \
       --runs-per-query "$RUNS_PER_QUERY" \
       --num-workers "$WORKERS" \
       --timeout "$TIMEOUT" \
       --verbose
if [ -n "$DESCRIPTION" ]; then
    set -- "$@" --description "$DESCRIPTION"
fi
if [ -n "$MODEL" ]; then
    set -- "$@" --model "$MODEL"
fi

PYTHONPATH="$SC_DIR${PYTHONPATH:+:$PYTHONPATH}" \
    python3 "$SC_DIR/scripts/run_eval.py" "$@" >"$RAW"
status=$?

if [ $status -ne 0 ]; then
    echo "error: run_eval.py exited $status; nothing recorded" >&2
    exit $status
fi

RAW="$RAW" RESULTS="$RESULTS" LABEL="$LABEL" NOTE="$NOTE" \
RUNS_PER_QUERY="$RUNS_PER_QUERY" MODEL="$MODEL" \
TOLERANCE_QUERIES="$TOLERANCE_QUERIES" python3 <<'PY'
import json
import os
import subprocess
from datetime import datetime, timezone

raw = json.load(open(os.environ["RAW"]))
results_path = os.environ["RESULTS"]
label = os.environ["LABEL"]
tolerance = int(os.environ["TOLERANCE_QUERIES"])

summary = raw["summary"]
passed, total = summary["passed"], summary["total"]
rate = round(passed / total, 4) if total else 0.0

try:
    cli = subprocess.run(["claude", "--version"], capture_output=True, text=True).stdout.strip()
except Exception:
    cli = "unknown"

run = {
    "label": label,
    "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "runs_per_query": int(os.environ["RUNS_PER_QUERY"]),
    "model": os.environ.get("MODEL") or "default",
    "cli_version": cli,
    "description_measured": raw["description"],
    "queries": total,
    "queries_passed": passed,
    "quantized_pass_rate": rate,
    "per_query": [
        {
            "query": r["query"],
            "should_trigger": r["should_trigger"],
            "triggers": r["triggers"],
            "runs": r["runs"],
            "pass": r["pass"],
        }
        for r in sorted(raw["results"], key=lambda r: (not r["should_trigger"], r["query"]))
    ],
}
if os.environ.get("NOTE"):
    run["note"] = os.environ["NOTE"]

if os.path.exists(results_path):
    doc = json.load(open(results_path))
else:
    doc = {
        "skill": "execute",
        "prompt_set": "skills/execute/evals/trigger-set.json",
        "procedure": "scripts/measure-trigger-rate.sh",
        "metric": "quantized per-query pass rate: a query passes when its trigger rate over runs_per_query runs falls on the expected side of a 0.5 majority threshold",
        "tolerance_band": "+/- 1 query on a 20-query set (+/- 5 percentage points); two runs over an unchanged set agree when their pass counts differ by at most 1",
        "reproducibility": "not exact. run_eval.py shells out to `claude -p`, which exposes no seed and no temperature control. The tolerance band is a declared agreement window, not a claim of bit-equal reruns.",
        "runs": [],
    }

previous = doc["runs"][-1] if doc["runs"] else None
doc["runs"].append(run)

with open(results_path, "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")

print("")
print("label:                %s" % label)
print("queries passed:       %d/%d" % (passed, total))
print("quantized pass rate:  %.1f%%" % (rate * 100))
if previous:
    delta = passed - previous["queries_passed"]
    verdict = "within" if abs(delta) <= tolerance else "OUTSIDE"
    print("vs %-18s %+d queries (%s the +/- %d band)"
          % (previous["label"] + ":", delta, verdict, tolerance))
print("")
print("recorded in %s" % results_path)
PY
