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
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LINT="$SCRIPT_DIR/check-macos-floor-legs.sh"
FIXTURES="$SCRIPT_DIR/check-macos-floor-legs/fixtures"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-macos-floor-legs-test.XXXXXX") || exit 1
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
ktg_on_exit cleanup

RC=0
OUT=""
# The fixtures call `demo` and `other` suites, which a stand-in runner defines
# through the same --suites and --scripts queries the real one answers.
lint() { # lint <workflow>...
    RC=0
    OUT=$(CHECK_MACOS_FLOOR_RUNNER="$FIXTURES/bin/check-bash-floor.sh" "$LINT" "$@" 2>&1) || RC=$?
}

has() { grep -qF -- "$1" <<<"$OUT"; }
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
    && has "bash scripts/two_test.sh" \
    && has 'step "Run the scan by path": scripts/demo-scan.sh' \
    && has 'step "Run the scan with sudo": scripts/demo-scan.sh' \
    && [ "$(count 'step "')" -eq 4 ]; then
    pass "a suite by path, one chained after cd, and a registered non-test script by path or behind sudo all fail"
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
    && has ": scripts/other-scan.sh" \
    && has "in none of its floor suites (demo)" && ! has "assert-koto-floor.sh" \
    && [ "$(count 'step "')" -eq 2 ]; then
    pass "a harness or another suite's script run on Linux but missing from the floor suite fails; a non-floor script passes"
else
    fail "drift fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/weak-floor.yml"
if [ "$RC" -eq 1 ] \
    && has 'job allowed-to-fail: step "(whole job)": no floor step' \
    && has 'job compound-if: step "Run tests with a flag": bash -e skills/demo/scripts/one_test.sh' \
    && has 'job compound-if: step "(whole job)": floor suite nosuch' \
    && has 'job compound-if: step "Run tests on the floor (macOS)": bash skills/demo/scripts/two_test.sh' \
    && ! has "job chained-after-floor" \
    && [ "$(count 'step "')" -eq 4 ]; then
    pass "a floor step allowed to fail, a compound if, bash -e, an unknown suite and a suite chained after a floor call fail; all and a comment pass"
else
    fail "weak-floor fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/not-macos.yml"
if [ "$RC" -eq 0 ]; then
    pass "a Linux-only job, and a macOS job that runs no suite (only names one in a comment), pass"
else
    fail "not-macos fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/runtime-suite.yml"
if [ "$RC" -eq 0 ]; then
    pass "a floor call naming its suite at run time (env var or matrix expression) passes"
else
    fail "runtime-suite fixture (rc=$RC): $OUT"
fi

lint "$FIXTURES/no-concurrency.yml"
if [ "$RC" -eq 1 ] && has "no-concurrency.yml: concurrency: the workflow runs shell suites on macOS (job test)" \
    && has "cancel-in-progress: \${{ github.event_name == 'pull_request' }}" \
    && [ "$(count 'step "')" -eq 0 ]; then
    pass "a workflow that runs suites on macOS without the concurrency block fails, naming the block"
else
    fail "no-concurrency fixture (rc=$RC): $OUT"
fi

# A block that differs from #941's, here one that never cancels, fails too.
sed "s/cancel-in-progress: .*/cancel-in-progress: false/" "$FIXTURES/clean.yml" >"$T/weak-concurrency.yml"
lint "$T/weak-concurrency.yml"
if [ "$RC" -eq 1 ] && has "weak-concurrency.yml: concurrency:"; then
    pass "a concurrency block that never cancels a superseded run fails"
else
    fail "weak-concurrency workflow (rc=$RC): $OUT"
fi

lint "$FIXTURES/draft-gate.yml"
if [ "$RC" -eq 1 ] \
    && has "draft-gate.yml: draft: job test runs shell suites on macOS for a draft pull request" \
    && has "draft-gate.yml: draft: the pull_request trigger lacks opened, synchronize, reopened, ready_for_review" \
    && has "github.event.pull_request.draft" \
    && [ "$(count 'step "')" -eq 0 ]; then
    pass "a suite workflow on pull_request with a fixed macOS matrix and no types fails, naming both"
else
    fail "draft-gate fixture (rc=$RC): $OUT"
fi

# The same workflow with no pull_request trigger has no draft to wait for.
sed "s/^on: .*/on: [push]/" "$FIXTURES/draft-gate.yml" >"$T/push-only.yml"
lint "$T/push-only.yml"
if [ "$RC" -eq 0 ]; then
    pass "a suite workflow with no pull_request trigger keeps its fixed macOS matrix"
else
    fail "push-only workflow (rc=$RC): $OUT"
fi

# Naming types without ready_for_review leaves a draft's macOS leg unrun.
sed "s/, ready_for_review//" "$FIXTURES/clean.yml" >"$T/no-ready.yml"
lint "$T/no-ready.yml"
if [ "$RC" -eq 1 ] && has "no-ready.yml: draft: the pull_request trigger lacks ready_for_review;" \
    && ! has "no-ready.yml: draft: job"; then
    pass "a pull_request trigger without ready_for_review fails"
else
    fail "no-ready workflow (rc=$RC): $OUT"
fi

# The draft matrix with a runner that names macOS outright still runs it.
sed 's/runs-on: \${{ matrix.os }}/runs-on: macos-latest/' "$FIXTURES/clean.yml" >"$T/fixed-runner.yml"
lint "$T/fixed-runner.yml"
if [ "$RC" -eq 1 ] && has "fixed-runner.yml: draft: job test runs shell suites on macOS"; then
    pass "a job whose runs-on names macOS instead of the matrix fails"
else
    fail "fixed-runner workflow (rc=$RC): $OUT"
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
