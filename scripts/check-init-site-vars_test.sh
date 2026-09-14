#!/usr/bin/env bash
# check-init-site-vars_test.sh — each case removes the variable from exactly one
# init site and requires the check to fail on that site alone.
#
# A check that fires when everything is wrong is worth little; the failure this
# guards against is one site drifting while the others stay correct. So every
# site gets its own case, and the unmutated copy gets one too, because a check
# that always fails would pass every mutation case and prove nothing.
#
# The mutations run against copies in a temp tree with the repo's layout, never
# against the working tree.
#
# Usage: check-init-site-vars_test.sh
# Exit codes: 0 all pass, 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CHECK="$SCRIPT_DIR/check-init-site-vars.sh"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

TEMPLATE="skills/work-on/koto-templates/work-on.md"
SKILL_DOC="skills/work-on/SKILL.md"
EXECUTE_TEMPLATE="skills/execute/koto-templates/execute.md"

# new_tree — a temp copy of the four files the check reads.
new_tree() {
    local d; d=$(mktemp -d); TMPS+=("$d")
    mkdir -p "$d/scripts" "$d/$(dirname "$TEMPLATE")" "$d/$(dirname "$EXECUTE_TEMPLATE")"
    cp "$CHECK" "$d/scripts/"
    cp "$REPO_ROOT/$TEMPLATE" "$d/$TEMPLATE"
    cp "$REPO_ROOT/$SKILL_DOC" "$d/$SKILL_DOC"
    cp "$REPO_ROOT/$EXECUTE_TEMPLATE" "$d/$EXECUTE_TEMPLATE"
    echo "$d"
}

# expect <label> <expected-exit> <dir> [<substring the stderr must contain>]
expect() {
    local label="$1" want="$2" dir="$3" needle="${4:-}"
    local out got
    out=$(bash "$dir/scripts/check-init-site-vars.sh" 2>&1); got=$?
    if [[ "$got" != "$want" ]]; then
        fail "$label: expected exit $want, got $got"
        return
    fi
    if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
        fail "$label: exit $got as expected, but output did not name '$needle'"
        return
    fi
    pass "$label (exit $got)"
}

# drop_nth_occurrence <file> <pattern> <n> — delete the nth line matching pattern.
drop_nth_occurrence() {
    local file="$1" pattern="$2" n="$3"
    awk -v pat="$pattern" -v target="$n" '
        $0 ~ pat { seen++; if (seen == target) next }
        { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Case 1 — the unmutated copy passes. Without this, a check that always failed
# would satisfy every case below.
T=$(new_tree)
expect "unmutated copy passes" 0 "$T"

# Case 2 — the issue-backed init block in SKILL.md forgets the variable.
T=$(new_tree)
drop_nth_occurrence "$T/$SKILL_DOC" "var PLUGIN_ROOT=" 1
expect "first SKILL.md init site missing PLUGIN_ROOT is caught" 1 "$T" "init site 1 does not pass required variable PLUGIN_ROOT"

# Case 3 — the free-form init block forgets it. The distinct site number is the
# point: the check reports which one drifted, not merely that one did.
T=$(new_tree)
drop_nth_occurrence "$T/$SKILL_DOC" "var PLUGIN_ROOT=" 2
expect "second SKILL.md init site missing PLUGIN_ROOT is caught" 1 "$T" "init site 2 does not pass required variable PLUGIN_ROOT"

# Case 4 — the spawn tick in execute.md stops injecting into child vars.
T=$(new_tree)
# python3 rather than `sed -i '0,/re/s///'`: that address form and in-place
# flag are GNU extensions, and this suite also runs under the bash 3.2 floor.
python3 - "$T/$EXECUTE_TEMPLATE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = " | .vars.PLUGIN_ROOT = $p"
i = s.find(needle)
assert i != -1, "injection text not found; the test's mutation is stale"
open(p, "w").write(s[:i] + s[i + len(needle):])
PY
expect "first child task build missing PLUGIN_ROOT is caught" 1 "$T" "injects .vars.PLUGIN_ROOT into 1 of them"

# Case 5 — the complete tick stops injecting. Same mutation, other occurrence.
T=$(new_tree)
python3 - "$T/$EXECUTE_TEMPLATE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = " | .vars.PLUGIN_ROOT = $p"
i = s.rfind(needle)
assert i != -1, "injection text not found; the test's mutation is stale"
open(p, "w").write(s[:i] + s[i + len(needle):])
PY
expect "second child task build missing PLUGIN_ROOT is caught" 1 "$T" "injects .vars.PLUGIN_ROOT into 1 of them"

# Case 6 — a THIRD tick is added later and forgets the injection entirely. This
# is the drift the counting exists for: both existing sites are still correct.
T=$(new_tree)
printf 'TASKS=$(${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}})\n' >> "$T/$EXECUTE_TEMPLATE"
expect "a new task build with no injection is caught" 1 "$T" "builds 3 task array(s)"

# Case 7 — the check must not silently pass when it can no longer see the init
# sites it is supposed to cover.
T=$(new_tree)
sed -i 's/koto init/koto start/g' "$T/$SKILL_DOC"
expect "init blocks moving out of SKILL.md is caught" 1 "$T" "no 'koto init'"

# Case 8 — nor when a file it reads is gone.
T=$(new_tree)
rm "$T/$EXECUTE_TEMPLATE"
expect "a missing input file is caught" 1 "$T" "missing file"

echo
echo "check-init-site-vars_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
