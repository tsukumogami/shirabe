#!/usr/bin/env bash
set -euo pipefail

# Tests for check-public-content.sh. Every refused shape is planted in a
# scratch file built here. The denylist cases use a list of made-up terms,
# written to a scratch directory outside the checkout at run time, so no real
# term appears here in any form.
#
# Usage:
#   bash scripts/ablation/check-public-content_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-public-content.sh"

PASS_COUNT=0
FAIL_COUNT=0
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

fail() { echo "FAIL: $1 - $2" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "PASS: $1" >&2; PASS_COUNT=$((PASS_COUNT + 1)); }

DENY="$TEST_DIR/deny.txt"
printf '# made-up terms for the test\nzorblatt-private\nacme/secretrepo\n' > "$DENY"

run() {
    STATUS=0
    ERR=$("$SUT" --denylist "$DENY" "$@" 2>&1 >/dev/null) || STATUS=$?
}

# Each planted line must be refused with its class and line number.
expect_refused() {
    local name="$1" line="$2" class="$3" f="$TEST_DIR/case.txt"
    printf 'clean first line\n%s\n' "$line" > "$f"
    run "$f"
    case "$STATUS:$ERR" in
        1:*"case.txt:2: $class"*) pass "$name" ;;
        *) fail "$name" "status $STATUS: $ERR" ;;
    esac
}

# The planted strings are split with "" so this file's own text never matches:
# the public-content job runs the check over the lines a pull request adds,
# this file included.
expect_refused "a linux home path" "see /ho""me/someone/dev/x" "home-directory path"
expect_refused "a macOS home path" "at /Us""ers/someone/Library" "home-directory path"
expect_refused "a tilde dot-directory" "read ~""/.config/thing" "home-directory path"
expect_refused "a wip path naming a file" "left in wi""p/plan_foo_state.md" "wip/ path"
expect_refused "a uuid" "session 3f2a9c1e""-1b2c-4d5e-8f90-a1b2c3d4e5f6 ran" "uuid-shaped identifier"
expect_refused "an instance name after +" "in repo+some_task""-0a1b2c3d" "instance or job name"
expect_refused "a session name" "ask some_coordinator""-deadbeef now" "instance or job name"
expect_refused "a job path" "under /jo""bs/0a1b2c3d/tmp" "instance or job name"
expect_refused "a session id" "id session""_01AbCdEfGhIjKlMnOp" "instance or job name"
expect_refused "a hosted-session url" "https://claude.ai/code/""session_abc" "hosted-session url"
expect_refused "a GitHub token" "token gh""p_abcdefghijklmnopqrstuvwxyz0123" "secret shape"
expect_refused "a private key header" "-----BEGIN OPENSSH PRIV""ATE KEY-----" "secret shape"
expect_refused "a denylisted term" "mentions Zorblatt-Private here" "denylisted term"
expect_refused "a denylisted owner/name" "see acme/secretrepo:docs/x.md" "denylisted term"

CLEAN="$TEST_DIR/clean.txt"
cat > "$CLEAN" <<'EOF'
Nothing committed contains a `wip/` path or a home-directory path.
The fixture rule: a template directory component starting `shirabe-ablation.`.
A commit 2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10 and secretrepo alone are fine.
EOF
run "$CLEAN"
if [ "$STATUS" -eq 0 ]; then
    pass "clean prose passes, including rule statements about wip/"
else
    fail "clean prose passes" "status $STATUS: $ERR"
fi

# --diff checks only the lines HEAD adds, and names file and new line number.
REPO="$TEST_DIR/repo"
mkdir -p "$REPO"
g() { git -C "$REPO" -c user.email=t@example.invalid -c user.name=t "$@"; }
g init -q -b main
printf 'old line mentioning /ho''me/someone/x\n' > "$REPO/a.md"
g add -A
g commit -q -m base
printf 'ok\nnew line in wi''p/leftover.md\n' >> "$REPO/a.md"
g commit -q -am change
STATUS=0
ERR=$(cd "$REPO" && "$SUT" --denylist "$DENY" --diff HEAD~1 2>&1 >/dev/null) || STATUS=$?
case "$STATUS:$ERR" in
    *"home-directory path"*) fail "--diff checks only added lines" "flagged a pre-existing line: $ERR" ;;
    1:*"a.md:3: wip/ path"*) pass "--diff checks only added lines, by file and new line number" ;;
    *) fail "--diff checks only added lines" "status $STATUS: $ERR" ;;
esac

# Pathspecs after -- narrow --diff to those paths: a line added outside them is
# not read, and one added inside them still is.
mkdir -p "$REPO/code"
printf 'cache under ~''/.cache/thing\n' > "$REPO/code/b.sh"
g add -A
g commit -q -m outside
STATUS=0
ERR=$(cd "$REPO" && "$SUT" --denylist "$DENY" --diff HEAD~2 -- '*.md' 2>&1 >/dev/null) || STATUS=$?
case "$STATUS:$ERR" in
    *"b.sh"*) fail "--diff pathspecs narrow the check" "read a line outside the pathspec: $ERR" ;;
    1:*"a.md:3: wip/ path"*) pass "--diff pathspecs narrow the check to those paths" ;;
    *) fail "--diff pathspecs narrow the check" "status $STATUS: $ERR" ;;
esac
STATUS=0
ERR=$(cd "$REPO" && "$SUT" --denylist "$DENY" --diff HEAD~1 -- code 2>&1 >/dev/null) || STATUS=$?
case "$STATUS:$ERR" in
    1:*"code/b.sh:1: home-directory path"*) pass "--diff pathspecs still check the lines added inside them" ;;
    *) fail "--diff pathspecs still check the lines added inside them" "status $STATUS: $ERR" ;;
esac

STATUS=0
ERR=$(cd "$REPO" && "$SUT" --denylist "$DENY" --diff HEAD~1 code/b.sh 2>&1 >/dev/null) || STATUS=$?
case "$STATUS:$ERR" in
    2:*"--diff takes no files"*) pass "--diff with a bare file argument is a usage error" ;;
    *) fail "--diff with a bare file argument is a usage error" "status $STATUS: $ERR" ;;
esac

STATUS=0
ERR=$(cd "$REPO" && "$SUT" --denylist "$DENY" --diff nosuchref 2>&1 >/dev/null) || STATUS=$?
case "$STATUS:$ERR" in
    2:*"not a commit"*) pass "--diff with an unknown base is a usage error" ;;
    *) fail "--diff with an unknown base is a usage error" "status $STATUS: $ERR" ;;
esac

run
case "$STATUS:$ERR" in
    2:*"nothing to check"*) pass "no input is a usage error" ;;
    *) fail "no input is a usage error" "status $STATUS: $ERR" ;;
esac

# Without a list the check runs everything else and says plainly that the
# term check did not run.
STATUS=0
OUT=$("$SUT" "$CLEAN" 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    0:*"denylist not provided: denylisted-term check did not run"*"secret shapes"*) pass "no list: the term check is reported as not run" ;;
    *) fail "no list: the term check is reported as not run" "status $STATUS: $OUT" ;;
esac
printf 'mentions Zorblatt-Private here\n' > "$TEST_DIR/term.txt"
STATUS=0
OUT=$("$SUT" "$TEST_DIR/term.txt" 2>&1) || STATUS=$?
case "$STATUS" in
    0) pass "no list: a term is not refused, since the term check did not run" ;;
    *) fail "no list: a term is not refused" "status $STATUS: $OUT" ;;
esac

# The list can come from the environment.
STATUS=0
OUT=$(ABLATION_DENYLIST="$DENY" "$SUT" "$TEST_DIR/term.txt" 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    1:*"term.txt:1: denylisted term"*) pass "ABLATION_DENYLIST supplies the list" ;;
    *) fail "ABLATION_DENYLIST supplies the list" "status $STATUS: $OUT" ;;
esac

# --require-denylist makes a missing list an error.
STATUS=0
OUT=$("$SUT" --require-denylist "$CLEAN" 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    2:*"no denylist given"*) pass "--require-denylist without a list is refused" ;;
    *) fail "--require-denylist without a list is refused" "status $STATUS: $OUT" ;;
esac

# A list inside the checkout is refused: the list must not live in the repository.
STATUS=0
OUT=$("$SUT" --denylist "$SCRIPT_DIR/check-public-content.sh" "$CLEAN" 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    2:*"inside the checkout"*) pass "a list inside the checkout is refused" ;;
    *) fail "a list inside the checkout is refused" "status $STATUS: $OUT" ;;
esac

echo "check-public-content_test: $PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]
