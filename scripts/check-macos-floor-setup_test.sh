#!/usr/bin/env bash
# check-macos-floor-setup_test.sh -- test harness for
# scripts/check-macos-floor-setup.sh.
#
# Usage: bash scripts/check-macos-floor-setup_test.sh
#
# Every case starts from the workflows under
# scripts/check-macos-floor-setup/fixtures/clean/, which match, copies them to
# a scratch directory, changes one thing and runs the check over it. Requires
# mikefarah yq v4 and python3, like the check itself.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-macos-floor-setup.sh"
CLEAN="$SCRIPT_DIR/check-macos-floor-setup/fixtures/clean"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-macos-floor-setup-test.XXXXXX") || exit 1
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

RC=0
OUT=""
CASE=""
N=0
fresh() { # a new copy of the clean workflows in $CASE
    N=$((N + 1))
    CASE="$T/case$N"
    mkdir "$CASE" && cp "$CLEAN"/*.yml "$CASE"/
}
# edit <file> <sed expression>: rewrite one workflow in the current case.
edit() {
    sed -e "$2" "$CASE/$1" >"$CASE/$1.new" && mv "$CASE/$1.new" "$CASE/$1"
}
check() { # check [--suites]
    RC=0
    OUT=$(CHECK_MACOS_FLOOR_SETUP_DIR="$CASE" "$CHECK" "$@" 2>&1) || RC=$?
}
has() { grep -qF -- "$1" <<<"$OUT"; }

fresh
check
if [ "$RC" -eq 0 ] && has "gives all 2 floor suites their own setup"; then
    pass "matching setups pass: Linux-only steps, checkouts and steps after the floor call are not setup"
else
    fail "clean (rc=$RC): $OUT"
fi

fresh
check --suites
if [ "$RC" -eq 0 ] && [ "$OUT" = '["demo", "other"]' ]; then
    pass "--suites lists the macOS floor suites, not a docker-only one or macos-floor.yml's own"
else
    fail "--suites (rc=$RC): $OUT"
fi

fresh
edit floor-a.yml 's/run: brew install jq/run: brew install jq yq/'
check
if [ "$RC" -eq 1 ] && has "suite demo: setup differs from floor-a.yml job test" && ! has "suite other"; then
    pass "a setup step changed in its own workflow fails, naming the suite"
else
    fail "changed step (rc=$RC): $OUT"
fi

fresh
edit macos-floor.yml "s/if: matrix.suite == 'demo'/if: matrix.suite == 'demo' || matrix.suite == 'other'/"
check
if [ "$RC" -eq 1 ] && has "suite other: setup differs from floor-b.yml job test" && ! has "suite demo"; then
    pass "a step given to a suite whose own workflow lacks it fails"
else
    fail "extra step (rc=$RC): $OUT"
fi

fresh
edit macos-floor.yml "s/if: matrix.suite == 'demo'/if: matrix.suite == 'demo' || matrix.suite == 'gone'/"
check
if [ "$RC" -eq 1 ] && has "suite gone: step \"Install jq\" names a suite no workflow runs"; then
    pass "a step naming a suite no workflow runs fails"
else
    fail "stale suite (rc=$RC): $OUT"
fi

fresh
edit macos-floor.yml "s/if: matrix.suite == 'demo'/if: runner.os == 'macOS'/"
check
if [ "$RC" -eq 1 ] && has "is not matrix.suite == '<suite>' clauses joined by ||"; then
    pass "a condition that can't be mapped to suites fails"
else
    fail "unreadable condition (rc=$RC): $OUT"
fi

fresh
edit macos-floor.yml '/^env:/,/^jobs:/{/GITHUB_TOKEN/d;}'
check
if [ "$RC" -eq 1 ] && has "suite demo: floor-a.yml job test sets env GITHUB_TOKEN"; then
    pass "a variable the suite's own job sees and macos-floor.yml's doesn't fails"
else
    fail "missing env (rc=$RC): $OUT"
fi

fresh
rm "$CASE/macos-floor.yml"
check
if [ "$RC" -eq 1 ] && has "macos-floor.yml is missing"; then
    pass "no macos-floor.yml fails"
else
    fail "no safety net (rc=$RC): $OUT"
fi

fresh
rm "$CASE/floor-a.yml" "$CASE/floor-b.yml"
check --suites
if [ "$RC" -eq 2 ] && has "no workflow runs a macOS floor suite"; then
    pass "no floor suite at all exits 2, not an empty list"
else
    fail "no suites (rc=$RC): $OUT"
fi

fresh
printf 'jobs: [unclosed\n' >"$CASE/broken.yml"
check
if [ "$RC" -eq 2 ] && has "could not read"; then
    pass "a workflow that is not YAML exits 2"
else
    fail "broken workflow (rc=$RC): $OUT"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
