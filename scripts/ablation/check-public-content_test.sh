#!/usr/bin/env bash
set -euo pipefail

# Tests for check-public-content.sh. Every refused shape is planted in a
# scratch file built here; the denylist case builds its own hashed list from a
# made-up term, so this file names no real term either.
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

sha256_of_string() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{ print $1 }'
    else
        printf '%s' "$1" | shasum -a 256 | awk '{ print $1 }'
    fi
}

DENY="$TEST_DIR/deny.txt"
{ echo "# test list"; sha256_of_string "zorblatt-private"; sha256_of_string "acme/secretrepo"; } > "$DENY"

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

expect_refused "a linux home path" "see /home/someone/dev/x" "home-directory path"
expect_refused "a macOS home path" "at /Users/someone/Library" "home-directory path"
expect_refused "a tilde dot-directory" "read ~/.config/thing" "home-directory path"
expect_refused "a wip path naming a file" "left in wip/plan_foo_state.md" "wip/ path"
expect_refused "a uuid" "session 3f2a9c1e-1b2c-4d5e-8f90-a1b2c3d4e5f6 ran" "uuid-shaped identifier"
expect_refused "an instance name after +" "in repo+some_task-0a1b2c3d" "instance or job name"
expect_refused "a session name" "ask some_coordinator-deadbeef now" "instance or job name"
expect_refused "a hosted-session url" "https://claude.ai/code/session_abc" "hosted-session url"
expect_refused "a GitHub token" "token ghp_abcdefghijklmnopqrstuvwxyz0123" "secret shape"
expect_refused "a private key header" "-----BEGIN OPENSSH PRIVATE KEY-----" "secret shape"
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
printf 'old line mentioning /home/someone/x\n' > "$REPO/a.md"
g add -A
g commit -q -m base
printf 'ok\nnew line in wip/leftover.md\n' >> "$REPO/a.md"
g commit -q -am change
STATUS=0
ERR=$(cd "$REPO" && "$SUT" --denylist "$DENY" --diff HEAD~1 2>&1 >/dev/null) || STATUS=$?
case "$STATUS:$ERR" in
    *"home-directory path"*) fail "--diff checks only added lines" "flagged a pre-existing line: $ERR" ;;
    1:*"a.md:3: wip/ path"*) pass "--diff checks only added lines, by file and new line number" ;;
    *) fail "--diff checks only added lines" "status $STATUS: $ERR" ;;
esac

run
case "$STATUS:$ERR" in
    2:*"nothing to check"*) pass "no input is a usage error" ;;
    *) fail "no input is a usage error" "status $STATUS: $ERR" ;;
esac

# The committed list is well formed: comments, blanks, or 64 lowercase hex.
BAD=$(grep -vE '^(#.*|[0-9a-f]{64}|)$' "$SCRIPT_DIR/public-content-denylist.txt" || true)
if [ -z "$BAD" ] && grep -qE '^[0-9a-f]{64}$' "$SCRIPT_DIR/public-content-denylist.txt"; then
    pass "the committed denylist holds only hashes and comments"
else
    fail "the committed denylist holds only hashes and comments" "[$BAD]"
fi

echo "check-public-content_test: $PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]
