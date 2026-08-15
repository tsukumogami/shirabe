#!/usr/bin/env bash
set -euo pipefail

# Tests for check-template-interpolation.sh.
#
# Usage:
#   bash scripts/check-template-interpolation_test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check-template-interpolation.sh"
TEST_DIR=""
PASS_COUNT=0
FAIL_COUNT=0

setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/skills/demo/koto-templates"
}

teardown() {
    rm -rf "$TEST_DIR"
}

fail() {
    echo "FAIL: $1 - $2" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "PASS: $1" >&2
    PASS_COUNT=$((PASS_COUNT + 1))
}

write_template() {
    cat > "$TEST_DIR/skills/demo/koto-templates/demo.md"
}

run_check() {
    "$CHECK_SCRIPT" "$TEST_DIR/skills" 2>&1
}

# A template whose gate uses a declared {{KEY}} reference is clean.
test_clean_template() {
    local name="clean template with {{KEY}} gate passes"
    setup
    write_template <<'EOF'
---
name: demo
variables:
  PLAN_SLUG:
    required: true
states:
  check:
    gates:
      classified:
        type: command
        command: "test -f wip/work-on_{{PLAN_SLUG}}_impact.json"
EOF
    if run_check > /dev/null 2>&1; then
        pass "$name"
    else
        fail "$name" "expected exit 0, got non-zero: $(run_check)"
    fi
    teardown
}

# The defect this check exists for: ${NAME} in a gate command.
test_shell_interpolation_in_gate_fails() {
    local name="\${NAME} in a gate command fails"
    setup
    write_template <<'EOF'
---
name: demo
states:
  worktree_discipline_check:
    gates:
      impact_classified:
        type: command
        command: "test -f wip/work-on_${PLAN_SLUG}_impact.json"
EOF
    local out rc=0
    out=$(run_check) || rc=$?
    if [[ $rc -ne 0 ]]; then
        pass "$name (non-zero exit)"
    else
        fail "$name" "expected non-zero exit, got 0"
    fi
    if [[ "$out" == *"worktree_discipline_check"* ]]; then
        pass "$name (names the offending state)"
    else
        fail "$name" "expected the state name in the output, got: $out"
    fi
    teardown
}

# The same defect written without braces.
test_bare_dollar_in_default_action_fails() {
    local name="\$NAME in a default_action command fails"
    setup
    write_template <<'EOF'
---
name: demo
states:
  build:
    default_action:
      type: command
      command: "make -C $PROJECT_DIR all"
EOF
    local rc=0
    run_check > /dev/null 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
        pass "$name"
    else
        fail "$name" "expected non-zero exit, got 0"
    fi
    teardown
}

# Command substitution is what a gate's shell is for; it must not be flagged.
test_command_substitution_allowed() {
    local name="\$(...) command substitution passes"
    setup
    write_template <<'EOF'
---
name: demo
states:
  guard:
    gates:
      not_on_main:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
EOF
    if run_check > /dev/null 2>&1; then
        pass "$name"
    else
        fail "$name" "expected exit 0, got: $(run_check)"
    fi
    teardown
}

# koto's own evidence namespace lives in context_assignments, which the check
# does not read, so a template using it stays clean.
test_evidence_reference_allowed() {
    local name="\${evidence.<field>} in context_assignments passes"
    setup
    write_template <<'EOF'
---
name: demo
states:
  setup:
    transitions:
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "setup blocked: ${evidence.detail}"
EOF
    if run_check > /dev/null 2>&1; then
        pass "$name"
    else
        fail "$name" "expected exit 0, got: $(run_check)"
    fi
    teardown
}

echo "Running check-template-interpolation.sh tests..." >&2
echo "" >&2

test_clean_template
test_shell_interpolation_in_gate_fails
test_bare_dollar_in_default_action_fails
test_command_substitution_allowed
test_evidence_reference_allowed

echo "" >&2
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed" >&2

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
