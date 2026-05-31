#!/usr/bin/env bash
#
# transition-status_test.sh - Tests for the comp transition-status.sh
#
# Exercises the three valid forward transitions and the refusal paths:
#   * Draft -> Accepted updates frontmatter and body atomically
#   * Accepted -> Done updates frontmatter and body atomically
#   * Draft -> Done (shortcut) updates frontmatter and body atomically
#   * Accepted -> Accepted is a no-op (idempotent re-runs are safe)
#   * Accepted -> Draft is refused (no regression)
#   * Done -> Accepted is refused (terminal status)
#   * Missing file path exits non-zero
#   * Output JSON carries moved: false
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

write_comp() {
    local path="$1"
    local fm_status="$2"
    local body_status="$3"

    cat > "$path" <<EOF
---
status: ${fm_status}
problem: |
  Test competitive question.
scope: |
  Test market slice.
---

# COMP: test

## Status

${body_status}

## Market Overview

Stub.

## Competitors

### Acme

Stub.

## Comparative Matrix

| Tool | Dim |
|------|-----|
| Acme | x   |

## Opportunities

Stub.

## Implications

Stub.

## References

- Stub (2026-01-01)
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

# Helper: assert a valid transition updates both frontmatter and body.
assert_valid_transition() {
    local name="$1"
    local from="$2"
    local to="$3"
    setup

    local comp="$TEST_DIR/COMP-feature.md"
    write_comp "$comp" "$from" "$from"

    local out
    if ! out=$("$TRANSITION_SCRIPT" "$comp" "$to" 2>/dev/null); then
        fail "$name" "script exited non-zero"
        teardown
        return
    fi

    local fm body moved
    fm=$(read_fm_status "$comp")
    body=$(read_body_status "$comp")
    moved=$(echo "$out" | jq -r '.moved')

    if [[ "$fm" != "$to" ]]; then
        fail "$name" "frontmatter status is '$fm', expected '$to'"
        teardown
        return
    fi
    if [[ "$body" != "$to" ]]; then
        fail "$name" "body status is '$body', expected '$to'"
        teardown
        return
    fi
    if [[ "$moved" != "false" ]]; then
        fail "$name" "output moved is '$moved', expected 'false'"
        teardown
        return
    fi

    pass "$name"
    teardown
}

# Helper: assert a transition is refused and the file is left untouched.
assert_refused_transition() {
    local name="$1"
    local from="$2"
    local to="$3"
    setup

    local comp="$TEST_DIR/COMP-feature.md"
    write_comp "$comp" "$from" "$from"

    local before
    before=$(sha1sum "$comp" | awk '{print $1}')

    if "$TRANSITION_SCRIPT" "$comp" "$to" >/dev/null 2>&1; then
        fail "$name" "script exited zero when refusing ${from} -> ${to}"
        teardown
        return
    fi

    local after
    after=$(sha1sum "$comp" | awk '{print $1}')
    if [[ "$before" != "$after" ]]; then
        fail "$name" "file was modified after refused transition"
        teardown
        return
    fi

    pass "$name"
    teardown
}

test_draft_to_accepted() {
    assert_valid_transition "Draft -> Accepted updates frontmatter and body" Draft Accepted
}

test_accepted_to_done() {
    assert_valid_transition "Accepted -> Done updates frontmatter and body" Accepted Done
}

test_draft_to_done() {
    assert_valid_transition "Draft -> Done shortcut updates frontmatter and body" Draft Done
}

test_accepted_no_op() {
    local name="already-Accepted comp is a no-op on Accepted target"
    setup
    local comp="$TEST_DIR/COMP-feature.md"
    write_comp "$comp" Accepted Accepted
    local before
    before=$(sha1sum "$comp" | awk '{print $1}')
    if ! "$TRANSITION_SCRIPT" "$comp" Accepted >/dev/null 2>&1; then
        fail "$name" "script exited non-zero on no-op call"
        teardown
        return
    fi
    local after
    after=$(sha1sum "$comp" | awk '{print $1}')
    if [[ "$before" != "$after" ]]; then
        fail "$name" "file was modified on no-op call"
        teardown
        return
    fi
    pass "$name"
    teardown
}

test_accepted_refuses_regression() {
    assert_refused_transition "Accepted refuses Draft target (no regression)" Accepted Draft
}

test_done_refuses_downgrade() {
    assert_refused_transition "Done refuses Accepted target (terminal status)" Done Accepted
}

test_missing_file_errors() {
    local name="missing comp path exits non-zero"
    setup
    if "$TRANSITION_SCRIPT" "$TEST_DIR/does-not-exist.md" Accepted >/dev/null 2>&1; then
        fail "$name" "script exited zero on missing file"
        teardown
        return
    fi
    pass "$name"
    teardown
}

main() {
    test_draft_to_accepted
    test_accepted_to_done
    test_draft_to_done
    test_accepted_no_op
    test_accepted_refuses_regression
    test_done_refuses_downgrade
    test_missing_file_errors

    echo ""
    echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
