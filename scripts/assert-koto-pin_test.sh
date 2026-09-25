#!/usr/bin/env bash
# assert-koto-pin_test.sh -- test harness for scripts/assert-koto-pin.sh.
#
# Usage: bash scripts/assert-koto-pin_test.sh
#
# Every case runs against a stand-in koto that prints a chosen version line, so
# no case depends on the koto a developer has installed. The last case checks
# the committed .tsuku.toml pins an exact version rather than "latest".
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ASSERT="$SCRIPT_DIR/assert-koto-pin.sh"
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/assert-koto-pin-test.XXXXXX")
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

manifest() { printf '[tools]\n"tsukumogami/koto" = "%s"\n' "$1" >"$T/m.toml"; }
stub() {
    printf '#!/bin/sh\n[ "$1" = version ] && echo "%s"\n' "$1" >"$T/koto"
    chmod +x "$T/koto"
}

RC=0
OUT=""
run() {
    RC=0
    OUT=$(KOTO_BIN="$1" "$BASH_BIN" "$ASSERT" "$T/m.toml" 2>&1) || RC=$?
}

manifest 0.13.0
stub "koto 0.13.0 (b4db451 2026-09-24T23:34:00Z)"
run "$T/koto"
[ "$RC" -eq 0 ] && pass "the pinned release passes" || fail "the pinned release failed: $OUT"
case "$OUT" in *"koto 0.13.0 (b4db451"*) pass "the koto version line is printed" ;; *) fail "no version line: $OUT" ;; esac

stub "koto 0.12.2 (1ca8c98 2026-08-24T23:46:46Z)"
run "$T/koto"
[ "$RC" -eq 1 ] && pass "an older koto fails" || fail "an older koto passed: $OUT"

stub "koto 0.13.1 (0000000 2026-10-01T00:00:00Z)"
run "$T/koto"
[ "$RC" -eq 1 ] && pass "a newer koto fails: the pin is exact" || fail "a newer koto passed: $OUT"

run "$T/no-such-koto"
[ "$RC" -eq 1 ] && pass "a missing koto fails, so a skipped suite cannot pass as green" || fail "a missing koto passed: $OUT"

manifest latest
stub "koto 0.13.0 (b4db451 2026-09-24T23:34:00Z)"
run "$T/koto"
[ "$RC" -eq 1 ] && pass "\"latest\" is refused as a pin" || fail "\"latest\" passed as a pin: $OUT"

manifest v0.13.0
run "$T/koto"
[ "$RC" -eq 0 ] && pass "a v-prefixed pin is accepted" || fail "a v-prefixed pin failed: $OUT"

PIN=$(sed -n 's/^[[:space:]]*"tsukumogami\/koto"[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' "$REPO/.tsuku.toml" | head -1)
if printf '%s' "$PIN" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "the committed .tsuku.toml pins koto to an exact release ($PIN)"
else
    fail "the committed .tsuku.toml does not pin koto to an exact release: [$PIN]"
fi

echo
echo "assert-koto-pin_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
