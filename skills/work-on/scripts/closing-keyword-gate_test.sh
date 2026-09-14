#!/usr/bin/env bash
# closing-keyword-gate_test.sh — does pr_creation's gate recognise a closing
# keyword, and refuse a body that lacks one?
#
# The gate is a shell expression inside the template, so the cases run the
# expression EXTRACTED FROM THE TEMPLATE rather than a copy pasted here. A copy
# would keep passing after someone edited the real one.
#
# `gh` is replaced with a stub that prints a body from the environment. That is
# the whole point: the gate must be exercised against bodies, and reaching the
# real GitHub would test the network instead. What the stub cannot cover is the
# shape of `gh pr view --json body --jq .body` itself — if that invocation is
# wrong, these cases still pass. The merge-state gate has the same exposure and
# the same answer: the invocation is copied from a shipped, working gate.
#
# Usage: closing-keyword-gate_test.sh
# Exit codes: 0 all pass, 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMPS=()
# The trailing `return 0` is load-bearing: the loop's last command is a test
# that is FALSE when TMPS is empty, and on bash 3.2 an EXIT trap's final
# status replaces the script's own, turning a clean exit into a failure that
# prints nothing at all.
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; return 0; }
trap cleanup EXIT

# The gate command, read out of the template: the `command:` line belonging to
# the closing_keyword gate, unquoted from its YAML single-quoted scalar.
GATE=$(awk '
    /^      closing_keyword:$/ { found=1 }
    found && /^        command:/ {
        sub(/^        command:[[:space:]]*/, "")
        sub(/^'"'"'/, ""); sub(/'"'"'$/, "")
        print
        exit
    }
' "$TEMPLATE")

if [[ -z "$GATE" ]]; then
    echo "could not read the closing_keyword gate command from $TEMPLATE" >&2
    exit 2
fi

# A gh stub that prints $PR_BODY, so the gate can be run against any body.
STUB_DIR=$(mktemp -d); TMPS+=("$STUB_DIR")
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Stands in for `gh pr view --json body --jq .body`.
if [[ "${GH_FAIL:-0}" == "1" ]]; then
    echo "gh: could not resolve to a PullRequest" >&2
    exit 1
fi
printf '%s\n' "${PR_BODY:-}"
STUB
chmod +x "$STUB_DIR/gh"

# run_gate <issue-number> <body> — substitute {{ISSUE_NUMBER}} as koto would,
# then run the expression with the stub ahead of the real gh.
run_gate() {
    local issue="$1" body="$2"
    local cmd="${GATE//\{\{ISSUE_NUMBER\}\}/$issue}"
    PATH="$STUB_DIR:$PATH" PR_BODY="$body" GH_FAIL="${3:-0}" sh -c "$cmd" >/dev/null 2>&1
}

expect() {
    local label="$1" want="$2" issue="$3" body="$4" ghfail="${5:-0}"
    run_gate "$issue" "$body" "$ghfail"; local got=$?
    if [[ "$got" == "$want" ]]; then pass "$label (exit $got)"
    else fail "$label: expected exit $want, got $got"; fi
}

# --- bodies that must pass ---------------------------------------------------
expect "Fixes #42 is recognised" 0 42 "Part 1

---

Fixes #42"
expect "lowercase fixes is recognised" 0 42 "fixes #42"
expect "Closes is recognised" 0 42 "Closes #42"
expect "Resolved is recognised" 0 42 "Resolved #42"
expect "the keyword mid-body is recognised" 0 42 "Some context.
Fixes #42
More context."

# --- bodies that must fail ---------------------------------------------------
expect "a body with no closing keyword fails" 1 42 "Part 1

---

Refs #42"
expect "a bare issue reference is not a closing keyword" 1 42 "See #42 for context"
expect "an empty body fails" 1 42 ""

# --- THE ANCHORING CASE ------------------------------------------------------
# A body closing #123 must not satisfy the gate for issue #12. This is the same
# substring defect the anchor finder exists to avoid, in a second place.
expect "Fixes #123 does NOT satisfy issue 12" 1 12 "Fixes #123"
expect "Fixes #12 DOES satisfy issue 12 at end of body" 0 12 "Fixes #12"
expect "Fixes #1234 does NOT satisfy issue 123" 1 123 "Fixes #1234"

# --- free-form mode ----------------------------------------------------------
# No issue number means no issue to close, so the gate passes rather than
# blocking work that has nothing to reference.
expect "an empty issue number passes without consulting the body" 0 "" "no keyword here"

# --- fail-closed -------------------------------------------------------------
# An unreadable pull request must NOT read as satisfied.
expect "an unreadable pull request fails rather than passing" 1 42 "Fixes #42" 1

echo
echo "closing-keyword-gate_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
