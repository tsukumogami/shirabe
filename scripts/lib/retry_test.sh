#!/usr/bin/env bash
# retry_test.sh - Unit tests for retry.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/retry.sh"

PASS=0
FAIL=0

pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1 - $2"; }

# ── Test: successful command runs once ──
test_success() {
    local name="successful command runs once"
    local count_file
    count_file=$(mktemp)
    echo 0 > "$count_file"

    cmd_that_succeeds() {
        local n
        n=$(cat "$count_file")
        echo $(( n + 1 )) > "$count_file"
        return 0
    }

    retry cmd_that_succeeds
    local count
    count=$(cat "$count_file")
    rm -f "$count_file"

    if [[ "$count" -eq 1 ]]; then
        pass "$name"
    else
        fail "$name" "Expected 1 attempt, got $count"
    fi
}

# ── Test: retries on failure then succeeds ──
test_retry_then_succeed() {
    local name="retries on failure then succeeds"
    local count_file
    count_file=$(mktemp)
    echo 0 > "$count_file"

    cmd_fails_twice() {
        local n
        n=$(cat "$count_file")
        n=$(( n + 1 ))
        echo "$n" > "$count_file"
        if [[ $n -lt 3 ]]; then
            return 1
        fi
        return 0
    }

    # Use --backoff-base 0 for fast tests
    retry --max-attempts 5 --backoff-base 0 cmd_fails_twice
    local exit_code=$?
    local count
    count=$(cat "$count_file")
    rm -f "$count_file"

    if [[ "$exit_code" -eq 0 && "$count" -eq 3 ]]; then
        pass "$name"
    else
        fail "$name" "Expected exit 0 after 3 attempts, got exit=$exit_code count=$count"
    fi
}

# ── Test: exhausts retries and returns last exit code ──
test_exhaust_retries() {
    local name="exhausts retries and returns last exit code"
    local count_file
    count_file=$(mktemp)
    echo 0 > "$count_file"

    cmd_always_fails() {
        local n
        n=$(cat "$count_file")
        echo $(( n + 1 )) > "$count_file"
        return 42
    }

    set +e
    retry --max-attempts 3 --backoff-base 0 cmd_always_fails 2>/dev/null
    local exit_code=$?
    set -e

    local count
    count=$(cat "$count_file")
    rm -f "$count_file"

    if [[ "$exit_code" -eq 42 && "$count" -eq 3 ]]; then
        pass "$name"
    else
        fail "$name" "Expected exit 42 after 3 attempts, got exit=$exit_code count=$count"
    fi
}

# ── Test: no command prints error ──
test_no_command() {
    local name="no command prints error"
    set +e
    local output
    output=$(retry 2>&1)
    local exit_code=$?
    set -e

    if [[ "$exit_code" -ne 0 && "$output" == *"no command specified"* ]]; then
        pass "$name"
    else
        fail "$name" "Expected error message, got exit=$exit_code output='$output'"
    fi
}

# ── Test: custom max-attempts is respected ──
test_custom_max_attempts() {
    local name="custom max-attempts is respected"
    local count_file
    count_file=$(mktemp)
    echo 0 > "$count_file"

    cmd_always_fails() {
        local n
        n=$(cat "$count_file")
        echo $(( n + 1 )) > "$count_file"
        return 1
    }

    set +e
    retry --max-attempts 5 --backoff-base 0 cmd_always_fails 2>/dev/null
    set -e

    local count
    count=$(cat "$count_file")
    rm -f "$count_file"

    if [[ "$count" -eq 5 ]]; then
        pass "$name"
    else
        fail "$name" "Expected 5 attempts, got $count"
    fi
}

# ── Test: double-source guard ──
test_double_source() {
    local name="double-source guard prevents re-loading"
    # Source again - should not error
    source "$SCRIPT_DIR/retry.sh"
    if declare -f retry &>/dev/null; then
        pass "$name"
    else
        fail "$name" "retry function not available after re-source"
    fi
}

# ── Run tests ──
echo "Running retry.sh tests..."
echo ""

test_success
test_retry_then_succeed
test_exhaust_retries
test_no_command
test_custom_max_attempts
test_double_source

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
