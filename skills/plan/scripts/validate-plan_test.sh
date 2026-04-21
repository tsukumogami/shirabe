#!/usr/bin/env bash
#
# validate-plan_test.sh - Tests for validate-plan.sh
#
# Usage:
#   bash validate-plan_test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-plan.sh"
TEST_DIR=""
PASS_COUNT=0
FAIL_COUNT=0

setup() {
    TEST_DIR=$(mktemp -d)
    # Initialize a git repo so upstream tracking checks work
    git init -q "$TEST_DIR/repo"
    git -C "$TEST_DIR/repo" config user.email "test@example.com"
    git -C "$TEST_DIR/repo" config user.name "Test"
    git -C "$TEST_DIR/repo" commit --allow-empty -q -m "init"
    mkdir -p "$TEST_DIR/repo/docs/plans" "$TEST_DIR/repo/docs/designs"
}

teardown() {
    rm -rf "$TEST_DIR"
}

fail() {
    local test_name="$1"
    local reason="$2"
    echo "FAIL: $test_name - $reason" >&2
    ((FAIL_COUNT++)) || true
}

pass() {
    local test_name="$1"
    echo "PASS: $test_name" >&2
    ((PASS_COUNT++)) || true
}

# Write a minimal valid PLAN to a path
write_valid_plan() {
    local path="$1"
    local extra_frontmatter="${2:-}"
    cat > "$path" <<EOF
---
schema: plan/v1
execution_mode: single-pr
issue_count: 1
${extra_frontmatter}
---

# PLAN: test

## Status

Draft
EOF
}

# ── Test: valid PLAN with no upstream exits 0 ──
test_valid_no_upstream() {
    local name="valid PLAN no upstream exits 0"
    setup

    write_valid_plan "$TEST_DIR/repo/docs/plans/PLAN-test.md"

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 0, got: $exit_code"
    fi

    teardown
}

# ── Test: missing schema exits 2 ──
test_missing_schema() {
    local name="missing schema exits 2"
    setup

    cat > "$TEST_DIR/repo/docs/plans/PLAN-test.md" <<'EOF'
---
execution_mode: single-pr
issue_count: 1
---

# PLAN: test
EOF

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 2 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 2, got: $exit_code"
    fi

    teardown
}

# ── Test: wrong schema exits 2 ──
test_wrong_schema() {
    local name="wrong schema exits 2"
    setup

    cat > "$TEST_DIR/repo/docs/plans/PLAN-test.md" <<'EOF'
---
schema: plan/v2
execution_mode: single-pr
issue_count: 1
---

# PLAN: test
EOF

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 2 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 2, got: $exit_code"
    fi

    teardown
}

# ── Test: missing execution_mode exits 2 ──
test_missing_execution_mode() {
    local name="missing execution_mode exits 2"
    setup

    cat > "$TEST_DIR/repo/docs/plans/PLAN-test.md" <<'EOF'
---
schema: plan/v1
issue_count: 1
---

# PLAN: test
EOF

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 2 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 2, got: $exit_code"
    fi

    teardown
}

# ── Test: missing issue_count exits 2 ──
test_missing_issue_count() {
    local name="missing issue_count exits 2"
    setup

    cat > "$TEST_DIR/repo/docs/plans/PLAN-test.md" <<'EOF'
---
schema: plan/v1
execution_mode: single-pr
---

# PLAN: test
EOF

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 2 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 2, got: $exit_code"
    fi

    teardown
}

# ── Test: upstream file does not exist exits 3 ──
test_upstream_file_not_found() {
    local name="upstream file not found exits 3"
    setup

    write_valid_plan "$TEST_DIR/repo/docs/plans/PLAN-test.md" \
        "upstream: docs/designs/DESIGN-nonexistent.md"

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 3 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 3, got: $exit_code"
    fi

    teardown
}

# ── Test: upstream file exists but not tracked exits 3 ──
test_upstream_file_not_tracked() {
    local name="upstream file not tracked exits 3"
    setup

    # Create the design file but do NOT git add it
    cat > "$TEST_DIR/repo/docs/designs/DESIGN-untracked.md" <<'EOF'
---
status: Accepted
---

# DESIGN: untracked
EOF

    write_valid_plan "$TEST_DIR/repo/docs/plans/PLAN-test.md" \
        "upstream: docs/designs/DESIGN-untracked.md"

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 3 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 3, got: $exit_code"
    fi

    teardown
}

# ── Test: upstream file has wrong status exits 3 ──
test_upstream_wrong_status() {
    local name="upstream file wrong status exits 3"
    setup

    # Create a tracked design with status Current (not Accepted)
    cat > "$TEST_DIR/repo/docs/designs/DESIGN-current.md" <<'EOF'
---
status: Current
---

# DESIGN: current
EOF
    git -C "$TEST_DIR/repo" add docs/designs/DESIGN-current.md
    git -C "$TEST_DIR/repo" commit -q -m "add design"

    write_valid_plan "$TEST_DIR/repo/docs/plans/PLAN-test.md" \
        "upstream: docs/designs/DESIGN-current.md"

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 3 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 3, got: $exit_code"
    fi

    teardown
}

# ── Test: valid PLAN with Accepted upstream exits 0 ──
test_valid_with_accepted_upstream() {
    local name="valid PLAN with Accepted upstream exits 0"
    setup

    # Create a tracked design with status Accepted
    cat > "$TEST_DIR/repo/docs/designs/DESIGN-accepted.md" <<'EOF'
---
status: Accepted
---

# DESIGN: accepted
EOF
    git -C "$TEST_DIR/repo" add docs/designs/DESIGN-accepted.md
    git -C "$TEST_DIR/repo" commit -q -m "add design"

    write_valid_plan "$TEST_DIR/repo/docs/plans/PLAN-test.md" \
        "upstream: docs/designs/DESIGN-accepted.md"

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 0, got: $exit_code"
    fi

    teardown
}

# ── Test: valid PLAN with Planned upstream exits 0 ──
# /plan transitions the upstream design Accepted -> Planned when creating the PLAN doc,
# so Planned must be accepted in CI (which runs after the PLAN doc is created).
test_valid_with_planned_upstream() {
    local name="valid PLAN with Planned upstream exits 0"
    setup

    # Create a tracked design with status Planned (post-/plan transition)
    cat > "$TEST_DIR/repo/docs/designs/DESIGN-planned.md" <<'EOF'
---
status: Planned
---

# DESIGN: planned
EOF
    git -C "$TEST_DIR/repo" add docs/designs/DESIGN-planned.md
    git -C "$TEST_DIR/repo" commit -q -m "add design"

    write_valid_plan "$TEST_DIR/repo/docs/plans/PLAN-test.md" \
        "upstream: docs/designs/DESIGN-planned.md"

    local exit_code=0
    "$VALIDATOR" "$TEST_DIR/repo/docs/plans/PLAN-test.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 0, got: $exit_code"
    fi

    teardown
}

# ── Test: file not found exits 1 ──
test_file_not_found() {
    local name="file not found exits 1"

    local exit_code=0
    "$VALIDATOR" "/nonexistent/PLAN.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 1 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit 1, got: $exit_code"
    fi
}

# ── Run all tests ──
echo "Running validate-plan.sh tests..." >&2
echo "" >&2

test_valid_no_upstream
test_missing_schema
test_wrong_schema
test_missing_execution_mode
test_missing_issue_count
test_upstream_file_not_found
test_upstream_file_not_tracked
test_upstream_wrong_status
test_valid_with_accepted_upstream
test_valid_with_planned_upstream
test_file_not_found

echo "" >&2
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed" >&2

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
