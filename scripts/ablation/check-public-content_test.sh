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

# The repository's committed allow file stays out of every case unless a test
# opts in: an empty override reads as no records.
export PUBLIC_CONTENT_ALLOWLIST=""

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

# An added line whose text starts with "++ " reads "+++ ..." in the diff, the
# same as a file header. It is still checked, under its own file and line, and
# the file after it keeps its own name. A file name with a space, which git
# ends with a tab in the header, is reported with its line number.
printf 'first\n++ see /ho''me/someone/x\n' > "$REPO/c.md"
printf 'one\ntwo at /ho''me/someone/y\n' > "$REPO/d e.md"
g add -A
g commit -q -m plusplus
STATUS=0
ERR=$(cd "$REPO" && "$SUT" --denylist "$DENY" --diff HEAD~1 2>&1 >/dev/null) || STATUS=$?
case "$STATUS:$ERR" in
    1:*"c.md:2: home-directory path"*) pass "--diff checks an added line that starts with ++" ;;
    *) fail "--diff checks an added line that starts with ++" "status $STATUS: $ERR" ;;
esac
case "$ERR" in
    *"d e.md:2: home-directory path"*) pass "--diff names a file with a space and its line" ;;
    *) fail "--diff names a file with a space and its line" "status $STATUS: $ERR" ;;
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

# --- the allow file ----------------------------------------------------------
# Planted wip strings below are split with "" like the rest of this file, so
# the public-content job never refuses this suite's own text.

ALLOW="$TEST_DIR/allow.tsv"
CASE_A="$TEST_DIR/listed-case.txt"
CASE_B="$TEST_DIR/unlisted-case.txt"
printf 'left in wi''p/plan_foo_state.md\n' > "$CASE_A"
printf 'left in wi''p/plan_foo_state.md\n' > "$CASE_B"
printf 'wip-path\t%s\ttsukumogami/shirabe#738\tthe fixture tests the rule itself\n' "$CASE_A" > "$ALLOW"

STATUS=0
OUT=$(env PUBLIC_CONTENT_ALLOWLIST="$ALLOW" "$SUT" --denylist "$DENY" "$CASE_A" 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    0:*"allowed: $CASE_A:1: wip/ path (tsukumogami/shirabe#738)"*) pass "a listed file's literal passes with an allowed notice naming the issue" ;;
    *) fail "a listed file's literal passes with an allowed notice naming the issue" "status $STATUS: $OUT" ;;
esac

STATUS=0
OUT=$(env PUBLIC_CONTENT_ALLOWLIST="$ALLOW" "$SUT" --denylist "$DENY" "$CASE_B" 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    1:*"$CASE_B:1: wip/ path"*) pass "an unlisted file's literal still fails" ;;
    *) fail "an unlisted file's literal still fails" "status $STATUS: $OUT" ;;
esac

expect_allow_error() { # expect_allow_error <name> <record> <needle>
    local name="$1" rec="$2" needle="$3" f="$TEST_DIR/allow-err.tsv"
    printf '%s\n' "$rec" > "$f"
    STATUS=0
    OUT=$(env PUBLIC_CONTENT_ALLOWLIST="$f" "$SUT" --denylist "$DENY" "$CASE_B" 2>&1) || STATUS=$?
    case "$STATUS:$OUT" in
        2:*"$needle"*) pass "$name" ;;
        *) fail "$name" "status $STATUS: $OUT" ;;
    esac
}

expect_allow_error "a record for a non-allowlistable class is an error" \
    "$(printf 'secret\t%s\ttsukumogami/shirabe#738\tnever\n' "$CASE_A")" \
    "not allowlistable"
expect_allow_error "a record with a malformed issue is an error" \
    "$(printf 'wip-path\t%s\tdone\treason\n' "$CASE_A")" \
    "issue must be owner/repo#N"
expect_allow_error "a record missing fields is an error" \
    "$(printf 'wip-path\t%s\n' "$CASE_A")" \
    "expected 4 tab-separated fields"
expect_allow_error "a record carrying a refused shape is itself an error" \
    "$(printf 'wip-path\t%s\ttsukumogami/shirabe#738\tsee wi''p/plan_foo_state.md\n' "$CASE_A")" \
    "may quote the rule, never the content"

printf 'wip-path\t%s\ttsukumogami/shirabe#738\tone\nwip-path\t%s\ttsukumogami/shirabe#738\ttwo\n' "$CASE_A" "$CASE_A" > "$ALLOW"
STATUS=0
OUT=$(env PUBLIC_CONTENT_ALLOWLIST="$ALLOW" "$SUT" --denylist "$DENY" "$CASE_A" 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    2:*"duplicate record"*) pass "a duplicate class-and-file record is an error" ;;
    *) fail "a duplicate class-and-file record is an error" "status $STATUS: $OUT" ;;
esac

# The committed allow file is the default: the lint's own test file holds old
# staging literals on purpose, and an invocation with no override reads the
# record for it; disabling the allowlist refuses the same file.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUS=0
OUT=$(cd "$REPO_ROOT" && env -u PUBLIC_CONTENT_ALLOWLIST "$SUT" --denylist "$DENY" scripts/check-template-directives_test.sh 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    0:*"allowed: scripts/check-template-directives_test.sh:"*) pass "the committed allow file covers the lint's own fixtures by default" ;;
    *) fail "the committed allow file covers the lint's own fixtures by default" "status $STATUS: $(printf '%s' "$OUT" | head -3)" ;;
esac
STATUS=0
OUT=$(cd "$REPO_ROOT" && env PUBLIC_CONTENT_ALLOWLIST="" "$SUT" --denylist "$DENY" scripts/check-template-directives_test.sh 2>&1) || STATUS=$?
case "$STATUS:$OUT" in
    1:*"wip/ path"*) pass "with the allowlist disabled the same file is refused" ;;
    *) fail "with the allowlist disabled the same file is refused" "status $STATUS: $(printf '%s' "$OUT" | head -3)" ;;
esac

echo "check-public-content_test: $PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]
