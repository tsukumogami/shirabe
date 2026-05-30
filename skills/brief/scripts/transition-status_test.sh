#!/usr/bin/env bash
#
# transition-status_test.sh - Tests for transition-status.sh
#
# Exercises the Draft -> Accepted transition that /prd's setup phase runs
# on a brief input, plus the no-op / refusal paths the workflow relies on:
#   * Draft -> Accepted updates frontmatter and body atomically
#   * Accepted -> Accepted is a no-op (idempotent re-runs are safe)
#   * Done -> Accepted is refused (terminal status, no downgrade)
#   * Path errors when invoked against a missing or non-brief target
#
# Usage:
#   bash transition-status_test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSITION_SCRIPT="$SCRIPT_DIR/transition-status.sh"
TEST_DIR=""
PASS_COUNT=0
FAIL_COUNT=0

setup() {
    TEST_DIR=$(mktemp -d)
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

write_brief() {
    local path="$1"
    local fm_status="$2"
    local body_status="$3"

    cat > "$path" <<EOF
---
status: ${fm_status}
problem: |
  Test problem.
outcome: |
  Test outcome.
---

# BRIEF: test

## Status

${body_status}

## Problem Statement

Stub.

## User Outcome

Stub.

## User Journeys

Stub.

## Scope Boundary

Stub.
EOF
}

read_fm_status() {
    local path="$1"
    sed -n '2,/^---$/p' "$path" | grep -E '^status:' | sed 's/^status:[[:space:]]*//' | head -1
}

read_body_status() {
    local path="$1"
    grep -A 3 '^## Status' "$path" | grep -E '^(Draft|Accepted|Done)' | head -1
}

# Test 1: Draft brief -> Accepted transitions both frontmatter and body.
# This is the path /prd's setup phase runs when invoked on a Draft brief.
test_draft_to_accepted() {
    local name="Draft brief transitions to Accepted (frontmatter + body)"
    setup

    local brief="$TEST_DIR/BRIEF-feature.md"
    write_brief "$brief" Draft Draft

    if ! "$TRANSITION_SCRIPT" "$brief" Accepted >/dev/null 2>&1; then
        fail "$name" "script exited non-zero"
        teardown
        return
    fi

    local fm body
    fm=$(read_fm_status "$brief")
    body=$(read_body_status "$brief")

    if [[ "$fm" != "Accepted" ]]; then
        fail "$name" "frontmatter status is '$fm', expected 'Accepted'"
        teardown
        return
    fi

    if [[ "$body" != "Accepted" ]]; then
        fail "$name" "body status is '$body', expected 'Accepted'"
        teardown
        return
    fi

    pass "$name"
    teardown
}

# Test 2: Accepted brief -> Accepted is a no-op. /prd's setup must remain
# idempotent so re-runs of the workflow do not error.
test_accepted_no_op() {
    local name="already-Accepted brief is a no-op on Accepted target"
    setup

    local brief="$TEST_DIR/BRIEF-feature.md"
    write_brief "$brief" Accepted Accepted

    local before
    before=$(sha1sum "$brief" | awk '{print $1}')

    if ! "$TRANSITION_SCRIPT" "$brief" Accepted >/dev/null 2>&1; then
        fail "$name" "script exited non-zero on no-op call"
        teardown
        return
    fi

    local after
    after=$(sha1sum "$brief" | awk '{print $1}')

    if [[ "$before" != "$after" ]]; then
        fail "$name" "file was modified on no-op call"
        teardown
        return
    fi

    pass "$name"
    teardown
}

# Test 3: Done brief is terminal -- /prd must not silently downgrade it.
# The transition script refuses; /prd's setup will see the non-zero exit
# and surface the error rather than corrupting the brief.
test_done_refuses_downgrade() {
    local name="Done brief refuses Accepted target (terminal status)"
    setup

    local brief="$TEST_DIR/BRIEF-feature.md"
    write_brief "$brief" Done Done

    local before
    before=$(sha1sum "$brief" | awk '{print $1}')

    if "$TRANSITION_SCRIPT" "$brief" Accepted >/dev/null 2>&1; then
        fail "$name" "script exited zero when refusing Done -> Accepted"
        teardown
        return
    fi

    local after
    after=$(sha1sum "$brief" | awk '{print $1}')

    if [[ "$before" != "$after" ]]; then
        fail "$name" "file was modified after refused transition"
        teardown
        return
    fi

    pass "$name"
    teardown
}

# Test 4: Missing file path returns a clear error. /prd's setup uses the
# script's exit code to decide whether the transition happened.
test_missing_file_errors() {
    local name="missing brief path exits non-zero"
    setup

    if "$TRANSITION_SCRIPT" "$TEST_DIR/does-not-exist.md" Accepted >/dev/null 2>&1; then
        fail "$name" "script exited zero on missing file"
        teardown
        return
    fi

    pass "$name"
    teardown
}

# Test 5: Frontmatter and body are updated in the same invocation. This
# is the FC03 invariant -- a partial update would leave the brief failing
# `shirabe validate`. We assert both fields move together.
test_atomic_frontmatter_and_body() {
    local name="Draft -> Accepted updates frontmatter and body atomically"
    setup

    local brief="$TEST_DIR/BRIEF-feature.md"
    write_brief "$brief" Draft Draft

    "$TRANSITION_SCRIPT" "$brief" Accepted >/dev/null 2>&1

    local fm body
    fm=$(read_fm_status "$brief")
    body=$(read_body_status "$brief")

    if [[ "$fm" != "$body" ]]; then
        fail "$name" "frontmatter ('$fm') and body ('$body') diverged"
        teardown
        return
    fi

    pass "$name"
    teardown
}

main() {
    test_draft_to_accepted
    test_accepted_no_op
    test_done_refuses_downgrade
    test_missing_file_errors
    test_atomic_frontmatter_and_body

    echo ""
    echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
