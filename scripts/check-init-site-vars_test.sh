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
# The trailing `return 0` is load-bearing: the loop's last command is a test
# that is FALSE when TMPS is empty, and under `set -e` an EXIT trap's final
# status replaces the script's own, turning a clean exit into a failure that
# prints nothing at all. The trigger is `set -e` and not any shell version --
# measured, bash 5.2 and 3.2 behave identically.
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; return 0; }
trap cleanup EXIT

TEMPLATE="skills/work-on/koto-templates/work-on.md"
SKILL_DOC="skills/work-on/SKILL.md"
EXECUTE_TEMPLATE="skills/execute/koto-templates/execute.md"
HARNESS="skills/work-on/scripts/terminal-retention_test.sh"

# new_tree — a temp copy of the four files the check reads.
new_tree() {
    local d; d=$(mktemp -d); TMPS+=("$d")
    mkdir -p "$d/scripts" "$d/$(dirname "$TEMPLATE")" "$d/$(dirname "$EXECUTE_TEMPLATE")"
    cp "$CHECK" "$d/scripts/"
    cp "$REPO_ROOT/$TEMPLATE" "$d/$TEMPLATE"
    cp "$REPO_ROOT/$SKILL_DOC" "$d/$SKILL_DOC"
    cp "$REPO_ROOT/$EXECUTE_TEMPLATE" "$d/$EXECUTE_TEMPLATE"
    mkdir -p "$d/$(dirname "$HARNESS")"
    cp "$REPO_ROOT/$HARNESS" "$d/$HARNESS"
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

# Case 4 — the spawn tick in execute.md stops injecting into child vars. It is
# the only task build: the complete tick advances bare and submits no tasks.
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
expect "child task build missing PLUGIN_ROOT is caught" 1 "$T" "injects .vars.PLUGIN_ROOT into 0 of them"

# Case 6 — a SECOND tick is added later and forgets the injection entirely. This
# is the drift the counting exists for: the existing site is still correct.
T=$(new_tree)
printf 'TASKS=$(${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}})\n' >> "$T/$EXECUTE_TEMPLATE"
expect "a new task build with no injection is caught" 1 "$T" "builds 2 task array(s)"

# Case 9 — A TEST HARNESS that inits the shipped template and forgets the
# variable. This category was missed by the first version of this check, and the
# omission cost two suites: every case in them failed at init, reporting a
# missing session rather than a missing variable.
T=$(new_tree)
python3 - "$T/$HARNESS" <<'PYMUT'
import sys
p = sys.argv[1]
s = open(p).read()
needle = " \\\n        --var PLUGIN_ROOT=/nonexistent/plugin-root"
assert needle in s, "the harness mutation is stale"
open(p, "w").write(s.replace(needle, "", 1))
PYMUT
expect "a harness init missing PLUGIN_ROOT is caught" 1 "$T" "inits the shipped template without required variable PLUGIN_ROOT"

# Case 10 — and the harness scan must not report zero sites. A scan that matches
# nothing reports OK forever, which is the failure mode of every check that
# looks for something by pattern.
T=$(new_tree)
python3 - "$T/$HARNESS" <<'PYMUT'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("koto init", "koto start"))
PYMUT
expect "a harness scan matching nothing is caught" 1 "$T" "covering nothing"

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
