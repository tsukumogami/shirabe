#!/usr/bin/env bash
# run-evals-handoff_test.sh - scripts/run-evals.sh hands --withhold runs, and
# only those, to the ablation harness.
#
# No model is called: every case either stops at a refusal the harness makes
# before any session starts, or at the runner's own prerequisite check.
#
# Usage: bash scripts/ablation/run-evals-handoff_test.sh
# Exit codes: 0 all cases pass; 1 a case failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RUNNER="$(cd "$SCRIPT_DIR/.." && pwd)/run-evals.sh"
CASE="$SCRIPT_DIR/cases/work-on-introspection-evidence.json"
KEY="skills/work-on/references/phases/phase-2-introspection.md#L20-L24"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

run() {
    RC=0
    OUT=$("$@" 2>&1) || RC=$?
}

# A --withhold that disagrees with the case: the harness refuses, by name,
# before any session. That the refusal comes from ablation.py is the proof the
# hand-off happened, wherever the flag sits in the arguments.
run "$RUNNER" --runs 1 --case "$CASE" --withhold "skills/x.md#L1-L2" work-on
case "$RC:$OUT" in
    2:*"ablation: skills/x.md#L1-L2: --withhold does not match"*) pass "--withhold after other options reaches the harness" ;;
    *) fail "--withhold after other options reaches the harness (rc=$RC): $OUT" ;;
esac

run "$RUNNER" "--withhold=skills/x.md#L1-L2" --case "$CASE" work-on
case "$RC:$OUT" in
    2:*"ablation: skills/x.md#L1-L2: --withhold does not match"*) pass "--withhold=<key> reaches the harness" ;;
    *) fail "--withhold=<key> reaches the harness (rc=$RC): $OUT" ;;
esac

# No --case: exactly one committed case must match the key and the skill.
run "$RUNNER" --withhold "$KEY" deliver
case "$RC:$OUT" in
    2:*"expected one case under scripts/ablation/cases/, found 0"*) pass "no matching case is refused" ;;
    *) fail "no matching case is refused (rc=$RC): $OUT" ;;
esac

python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(json.dumps({"cases":[c, dict(c, id="second")]}))' "$CASE" > "$T/two.json"
run "$RUNNER" --withhold "$KEY" --case "$T/two.json" work-on
case "$RC:$OUT" in
    2:*"expected one case, found 2"*) pass "a file with several cases needs --case-id" ;;
    *) fail "a file with several cases needs --case-id (rc=$RC): $OUT" ;;
esac

# Without --withhold the runner never reaches the harness. With no claude on
# PATH it stops at its own prerequisite check, and nothing says "ablation".
mkdir -p "$T/bin"
ln -s "$(command -v python3)" "$T/bin/python3"
run env PATH="$T/bin:/usr/bin:/bin" "$RUNNER" --runs 1 work-on
case "$RC:$OUT" in
    *ablation*) fail "without --withhold the harness is not reached (rc=$RC): $OUT" ;;
    3:*"claude CLI not found"*) pass "without --withhold the runner takes its own path" ;;
    *) fail "without --withhold the runner takes its own path (rc=$RC): $OUT" ;;
esac

printf 'run-evals-handoff_test: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
