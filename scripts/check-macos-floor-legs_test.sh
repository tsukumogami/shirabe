#!/usr/bin/env bash
# check-macos-floor-legs_test.sh -- test harness for
# scripts/check-macos-floor-legs.sh.
#
# Usage: bash scripts/check-macos-floor-legs_test.sh
#
# Each case runs the lint over one fixture workflow under
# scripts/check-macos-floor-legs/fixtures/ and checks the exit status and the
# violation it names. The fixtures' headers say what each one pins. Requires
# mikefarah yq v4 and python3, like the lint itself.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LINT="$SCRIPT_DIR/check-macos-floor-legs.sh"
FIXTURES="$SCRIPT_DIR/check-macos-floor-legs/fixtures"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-macos-floor-legs-test.XXXXXX")
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

RC=0
OUT=""
# The fixtures call a `demo` suite, which the fixture registry defines in the
# format `check-bash-floor.sh --list` prints.
lint() { # lint <workflow>...
    RC=0
    OUT=$(CHECK_MACOS_FLOOR_REGISTRY="$FIXTURES/registry.txt" "$LINT" "$@" 2>&1) || RC=$?
}

has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
count() { printf '%s\n' "$OUT" | grep -c -- "$1"; }

lint "$FIXTURES/clean.yml"
if [ "$RC" -eq 0 ]; then
    pass "Linux-only bash, the floor runner, an installer pipe and bash -c pass"
else
    fail "clean fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/plain-bash.yml"
if [ "$RC" -eq 1 ] && has 'step "Run tests on both legs": bash skills/demo/scripts/one_test.sh' \
    && has "Homebrew's bash 5"; then
    pass "a suite run with plain bash on the macOS leg fails, naming the step and command"
else
    fail "plain-bash fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/system-bash.yml"
if [ "$RC" -eq 1 ] && has "/bin/bash skills/demo/scripts/one_test.sh" \
    && has "nested bash"; then
    pass "/bin/bash on a harness fails: a nested bash inside it is not on the floor"
else
    fail "system-bash fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/by-path.yml"
if [ "$RC" -eq 1 ] && has ": skills/demo/scripts/one_test.sh" \
    && has "bash scripts/two_test.sh" && [ "$(count 'step "')" -eq 2 ]; then
    pass "a suite run by path, and one chained after cd and a variable, both fail on a macos runs-on"
else
    fail "by-path fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/linux-limited-floor.yml"
if [ "$RC" -eq 1 ] && has "no floor step" && [ "$(count 'step "')" -eq 1 ]; then
    pass "a floor step limited to Linux by mistake fails as a macOS leg with no floor step"
else
    fail "linux-limited-floor fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/drift.yml"
if [ "$RC" -eq 1 ] && has "skills/demo/scripts/three_test.sh" \
    && has "in none of its floor suites (demo)" && [ "$(count 'step "')" -eq 1 ]; then
    pass "a harness run on Linux but missing from the floor suite fails; the listed one passes"
else
    fail "drift fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/weak-floor.yml"
if [ "$RC" -eq 1 ] \
    && has 'job allowed-to-fail: step "(whole job)": no floor step' \
    && has 'job compound-if: step "Run tests with a flag": bash -e skills/demo/scripts/one_test.sh' \
    && has 'job compound-if: step "(whole job)": floor suite nosuch' \
    && [ "$(count 'step "')" -eq 3 ]; then
    pass "a floor step allowed to fail, a compound if, bash -e, and an unknown suite all fail"
else
    fail "weak-floor fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/not-macos.yml"
if [ "$RC" -eq 0 ]; then
    pass "a Linux-only job, and a macOS job that runs no suite, pass"
else
    fail "not-macos fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/clean.yml" "$FIXTURES/plain-bash.yml"
if [ "$RC" -eq 1 ] && has "plain-bash.yml" && ! has "clean.yml:"; then
    pass "several workflows at once: only the failing one is named"
else
    fail "two workflows (rc=$RC): $OUT"
fi

printf 'jobs: [unclosed\n' >"$T/broken.yml"
lint "$T/broken.yml"
if [ "$RC" -eq 2 ] && has "could not read"; then
    pass "a workflow that is not YAML exits 2, not 0 or 1"
else
    fail "broken workflow (rc=$RC): $OUT"
fi

lint "$T/absent.yml"
if [ "$RC" -eq 2 ] && has "no such workflow"; then
    pass "a named workflow that does not exist exits 2, not a silent pass"
else
    fail "absent workflow (rc=$RC): $OUT"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
