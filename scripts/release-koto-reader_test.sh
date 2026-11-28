#!/usr/bin/env bash
# release-koto-reader_test.sh -- test harness for scripts/release-koto-reader.sh.
#
# Each case writes a throwaway repository root holding a
# crates/shirabe/Cargo.toml and a Cargo.lock, runs the check against it, and
# reads its exit code and output:
#
#   a tag pin the lock agrees with                -> exit 0, the release line
#   a branch pin, a rev pin, a path dependency    -> exit 1
#   a lock at another tag than the manifest pins  -> exit 1
#   a lock with no full commit hash               -> exit 1
#   the repository's own files                    -> exit 0, the release line
#
# Usage: bash scripts/release-koto-reader_test.sh
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/release-koto-reader.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/release-koto-reader-test.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */release-koto-reader-test.*) rm -rf "$T" ;; esac; return 0; }
ktg_on_exit cleanup

REPO="https://github.com/tsukumogami/koto"
SHA="0123456789abcdef0123456789abcdef01234567"

# fixture <dependency line> <lock source>: writes the manifest and the lock
# under $T/root.
fixture() {
    rm -rf "$T/root"
    mkdir -p "$T/root/crates/shirabe" || exit 1
    cat >"$T/root/crates/shirabe/Cargo.toml" <<EOF
[package]
name = "shirabe"

[dependencies]
libc = "0.2"
$1
EOF
    cat >"$T/root/Cargo.lock" <<EOF
version = 4

[[package]]
name = "koto-session-reader"
version = "0.42.0"
source = "$2"
dependencies = [
 "anyhow",
]

[[package]]
name = "shirabe"
version = "0.0.0"
dependencies = [
 "koto-session-reader",
]
EOF
}

run() {
    OUT=$("$BASH_BIN" "$CHECK" "$@" 2>&1)
    RC=$?
}

PINNED="koto-session-reader = { git = \"$REPO\", tag = \"v0.42.0\" }"
LOCKED="git+$REPO?tag=v0.42.0#$SHA"

fixture "$PINNED" "$LOCKED"
run "$T/root"
if [ "$RC" -eq 0 ] && [ "$OUT" = "koto session reader: koto v0.42.0 (01234567)" ]; then
    pass "a tag pin the lock agrees with passes and names the release"
else
    fail "a tag pin did not pass (rc=$RC): $OUT"
fi

# refused <what> <dependency line> <lock source> <text the reason holds>
refused() {
    fixture "$2" "$3"
    run "$T/root"
    if [ "$RC" -eq 1 ] && grep -qF -- "$4" <<<"$OUT"; then
        pass "$1 is refused"
    else
        fail "$1 was not refused (rc=$RC): $OUT"
    fi
}

refused "a branch pin" \
    "koto-session-reader = { git = \"$REPO\", branch = \"main\" }" \
    "git+$REPO?branch=main#$SHA" "pinned by branch"
refused "a rev pin" \
    "koto-session-reader = { git = \"$REPO\", rev = \"$SHA\" }" \
    "git+$REPO?rev=$SHA#$SHA" "pinned by rev"
refused "a tag pin that also names a rev" \
    "koto-session-reader = { git = \"$REPO\", tag = \"v0.42.0\", rev = \"$SHA\" }" \
    "$LOCKED" "pinned by rev"
refused "a path dependency" \
    'koto-session-reader = { path = "../koto/koto-session-reader" }' \
    "$LOCKED" "pinned by path"
refused "a git dependency on another repository" \
    'koto-session-reader = { git = "https://github.com/someone/koto", tag = "v0.42.0" }' \
    "$LOCKED" "isn't a git dependency on $REPO"
refused "a tag that isn't a release tag" \
    "koto-session-reader = { git = \"$REPO\", tag = \"latest\" }" \
    "git+$REPO?tag=latest#$SHA" 'no tag = "vX.Y.Z"'
refused "a lock at another tag than the manifest pins" \
    "$PINNED" "git+$REPO?tag=v0.41.0#$SHA" "pins $REPO at v0.42.0"
refused "a lock source with no full commit hash" \
    "$PINNED" "git+$REPO?tag=v0.42.0#0123abc" "no full commit hash"

fixture "" "$LOCKED"
run "$T/root"
if [ "$RC" -eq 1 ] && grep -qF "has 0 koto-session-reader dependency lines" <<<"$OUT"; then
    pass "a manifest without the dependency is refused"
else
    fail "a manifest without the dependency was not refused (rc=$RC): $OUT"
fi

run "$T/root" extra
if [ "$RC" -eq 2 ]; then
    pass "a second argument is a usage error"
else
    fail "a second argument was not a usage error (rc=$RC): $OUT"
fi

# The repository's own pin and lock agree.
run
if [ "$RC" -eq 0 ] && grep -qE '^koto session reader: koto v[0-9]+\.[0-9]+\.[0-9]+ \([0-9a-f]{8}\)$' <<<"$OUT"; then
    pass "the repository's own pin and lock name one release"
else
    fail "the repository's own pin and lock did not pass (rc=$RC): $OUT"
fi

echo
echo "release-koto-reader_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
