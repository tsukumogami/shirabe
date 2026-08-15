#!/usr/bin/env bash
set -euo pipefail

# Tests for check-bash-floor.sh.
#
# The load-bearing case is the canary: scripts/bash-floor-canary.sh must fail
# when the runner puts it on the floor and pass under the bash running this
# harness. If that asymmetry ever stops holding, the runner has stopped
# reaching bash 3.2 and every green floor check it reports is worthless.
#
# Usage:
#   bash scripts/check-bash-floor_test.sh
#
# Requires a reachable floor: docker on Linux, or a macOS /bin/bash. Set
# FLOOR_BACKEND to pin one (docker or system); the default lets the runner
# choose.
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/check-bash-floor.sh"
CANARY="$SCRIPT_DIR/bash-floor-canary.sh"
PASS_COUNT=0
FAIL_COUNT=0

BACKEND_ARGS=""
if [ -n "${FLOOR_BACKEND:-}" ]; then
    BACKEND_ARGS="--backend $FLOOR_BACKEND"
fi

fail() {
    echo "FAIL: $1 - $2" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "PASS: $1" >&2
    PASS_COUNT=$((PASS_COUNT + 1))
}

# The bash running this harness is whatever the developer or the CI runner
# ships, which everywhere CI runs it is 4 or newer. The canary passing here and
# failing on the floor is the whole assertion.
test_canary_passes_under_this_bash() {
    local name="canary passes under this bash (${BASH_VERSION})"
    local out rc=0

    case "$BASH_VERSION" in
        3.*)
            echo "SKIP: $name - this harness is itself on the floor" >&2
            return
            ;;
    esac

    out=$(bash "$CANARY" 2>&1) || rc=$?
    if [ $rc -ne 0 ]; then
        fail "$name" "expected exit 0, got $rc: $out"
        return
    fi
    case "$out" in
        *"split into 3 fields"*) pass "$name" ;;
        *) fail "$name" "unexpected output: $out" ;;
    esac
}

# The runner's reason to exist: put that same canary on the floor and it fails.
test_canary_fails_on_the_floor() {
    local name="canary fails on the bash 3.2 floor"
    local out rc=0

    out=$($RUNNER $BACKEND_ARGS canary 2>&1) || rc=$?
    if [ $rc -eq 0 ]; then
        fail "$name" "the runner reported a pass; it is not reaching bash 3.2: $out"
        return
    fi
    if [ $rc -ne 1 ]; then
        fail "$name" "expected exit 1 (suite failed), got $rc: $out"
        return
    fi
    case "$out" in
        *"U+0001 record did not split"*) ;;
        *) fail "$name" "the failure does not name the U+0001 split: $out"; return ;;
    esac
    # The diagnostic has to show where the fields ended up, with the invisible
    # separators made visible, or the next reader has no way to recognise the
    # defect when it turns up in a real script.
    case "$out" in
        *"number=[1<U+0001>plan-to-tasks<U+0001>Make the floor checkable]"*) ;;
        *) fail "$name" "the failure does not show the concatenated field: $out"; return ;;
    esac
    case "$out" in
        *"check-bash-floor: FAIL"*) pass "$name" ;;
        *) fail "$name" "the runner did not report the suite as failed: $out" ;;
    esac
}

# The floor a run reached has to be visible in its own output, otherwise a
# green result cannot be told apart from a run that never left bash 5.
test_floor_run_names_the_version() {
    local name="a floor run reports bash 3.2 in the canary's own output"
    local out rc=0

    out=$($RUNNER $BACKEND_ARGS canary 2>&1) || rc=$?
    case "$out" in
        *"(bash 3.2"*) pass "$name" ;;
        *) fail "$name" "no bash 3.2 banner in the output: $out" ;;
    esac
}

# --list is the discovery surface: it has to name every CI suite, so a
# developer can find the one covering the script they just changed.
test_list_names_every_suite() {
    local name="--list names every CI suite and its workflow"
    local out rc=0
    local suite

    out=$($RUNNER --list 2>&1) || rc=$?
    if [ $rc -ne 0 ]; then
        fail "$name" "expected exit 0, got $rc"
        return
    fi
    for suite in plan execute templates template-consistency; do
        case "$out" in
            *"$suite"*) ;;
            *) fail "$name" "suite $suite missing from --list"; return ;;
        esac
    done
    case "$out" in
        *"check-plan-scripts.yml"*) pass "$name" ;;
        *) fail "$name" "--list does not name the workflow a suite comes from" ;;
    esac
}

# Every script the registry claims to run has to exist, or a suite silently
# stops covering something when a script is renamed.
test_registry_scripts_exist() {
    local name="every script in the registry exists"
    local out script missing=""

    out=$($RUNNER --list 2>&1)
    for script in $(echo "$out" | grep -E '^ +(skills|scripts)/.*\.sh$'); do
        [ -f "$SCRIPT_DIR/../$script" ] || missing="$missing $script"
    done
    if [ -n "$missing" ]; then
        fail "$name" "missing:$missing"
    else
        pass "$name"
    fi
}

test_unknown_suite_is_refused() {
    local name="an unknown suite is refused with exit 2"
    local out rc=0

    out=$($RUNNER $BACKEND_ARGS no-such-suite 2>&1) || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"unknown suite"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

test_no_suite_is_refused() {
    local name="naming no suite is refused with exit 2"
    local out rc=0

    out=$($RUNNER $BACKEND_ARGS 2>&1) || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"name at least one suite"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

# "the floor could not be reached" and "your code fails on the floor" are
# different answers and must not share an exit code. A missing shirabe binary
# is the first kind: the suite never ran.
test_unreachable_floor_is_not_reported_as_a_suite_failure() {
    local name="a shirabe binary that cannot be produced exits 2, not 1"
    local out rc=0

    out=$(SHIRABE_BIN=/nonexistent/shirabe $RUNNER --backend docker plan 2>&1) || rc=$?
    if [ $rc -eq 1 ]; then
        fail "$name" "reported the suite as failing on the floor; it never ran: $out"
        return
    fi
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"not executable"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

test_unknown_backend_is_refused() {
    local name="an unknown backend is refused with exit 2"
    local out rc=0

    out=$($RUNNER --backend nonsense canary 2>&1) || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"unknown backend"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

# The system backend must refuse a bash that is not 3.2 rather than run the
# suite and report a green that means nothing.
test_system_backend_refuses_a_newer_bin_bash() {
    local name="the system backend refuses a /bin/bash that is not 3.2"
    local out rc=0

    if /bin/bash -c 'case "$BASH_VERSION" in 3.2*) exit 0;; *) exit 1;; esac'; then
        echo "SKIP: $name - /bin/bash here is 3.2" >&2
        return
    fi

    out=$($RUNNER --backend system canary 2>&1) || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"/bin/bash is not 3.2"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

echo "Running check-bash-floor.sh tests..."
echo ""

test_canary_passes_under_this_bash
test_canary_fails_on_the_floor
test_floor_run_names_the_version
test_list_names_every_suite
test_registry_scripts_exist
test_unknown_suite_is_refused
test_no_suite_is_refused
test_unreachable_floor_is_not_reported_as_a_suite_failure
test_unknown_backend_is_refused
test_system_backend_refuses_a_newer_bin_bash

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

[ "$FAIL_COUNT" -eq 0 ]
