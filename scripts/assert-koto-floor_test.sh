#!/usr/bin/env bash
# assert-koto-floor_test.sh -- test harness for scripts/assert-koto-floor.sh.
#
# Usage: bash scripts/assert-koto-floor_test.sh
#
# Every case runs against a stand-in koto that prints a chosen version line, so
# no case depends on the koto a developer has installed. The relational cases
# set KOTO_FLOOR to a fixed value so they keep meaning the same thing when the
# script's floor moves; one case runs against the script's own floor. The last
# cases check the committed .tsuku.toml tracks a koto major version rather than
# pinning an exact release (which would downgrade a newer koto) or "latest".
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ASSERT="$SCRIPT_DIR/assert-koto-floor.sh"
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/assert-koto-floor-test.XXXXXX")
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

stub() {
    printf '#!/bin/sh\n[ "$1" = version ] && echo "%s"\n' "$1" >"$T/koto"
    chmod +x "$T/koto"
}

RC=0
OUT=""
# run <koto-bin> [<floor>] -- an empty floor runs the script's own default.
run() {
    RC=0
    if [ -n "${2:-}" ]; then
        OUT=$(KOTO_BIN="$1" KOTO_FLOOR="$2" "$BASH_BIN" "$ASSERT" 2>&1) || RC=$?
    else
        OUT=$(env -u KOTO_FLOOR KOTO_BIN="$1" "$BASH_BIN" "$ASSERT" 2>&1) || RC=$?
    fi
}

expect() { # expect <rc> <label>
    if [ "$RC" -eq "$1" ]; then pass "$2"; else fail "$2 (rc=$RC): $OUT"; fi
}

# The script's own floor, read from its one definition.
DEFAULT_FLOOR=$(sed -n 's/^FLOOR="\${KOTO_FLOOR:-\([0-9.]*\)}"$/\1/p' "$ASSERT" | head -1)
if printf '%s' "$DEFAULT_FLOOR" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "the script defines its floor in one place ($DEFAULT_FLOOR)"
else
    fail "cannot read the floor from $ASSERT: [$DEFAULT_FLOOR]"
fi

stub "koto $DEFAULT_FLOOR (b4db451 2026-09-24T23:34:00Z)"
run "$T/koto"
expect 0 "koto at the script's own floor passes"
case "$OUT" in *"koto $DEFAULT_FLOOR (b4db451"*) pass "the koto version line is printed" ;; *) fail "no version line: $OUT" ;; esac

stub "koto 1.4.2 (0000000 2026-10-01T00:00:00Z)"
run "$T/koto" 1.4.2
expect 0 "a koto equal to the floor passes"

stub "koto 1.4.10 (0000000 2026-10-01T00:00:00Z)"
run "$T/koto" 1.4.2
expect 0 "a newer patch passes, compared numerically (10 > 2)"

stub "koto 1.12.0 (0000000 2026-10-01T00:00:00Z)"
run "$T/koto" 1.4.2
expect 0 "a newer minor passes, compared numerically (12 > 4)"

stub "koto 2.0.0 (0000000 2026-10-01T00:00:00Z)"
run "$T/koto" 1.4.2
expect 0 "a newer major passes"

stub "koto v1.5.0 (0000000 2026-10-01T00:00:00Z)"
run "$T/koto" v1.4.2
expect 0 "v-prefixed versions and floors are accepted"

stub "koto 1.4.1 (1ca8c98 2026-08-24T23:46:46Z)"
run "$T/koto" 1.4.2
expect 1 "an older patch fails"

stub "koto 1.3.9 (1ca8c98 2026-08-24T23:46:46Z)"
run "$T/koto" 1.4.2
expect 1 "an older minor fails"

stub "koto 0.99.99 (1ca8c98 2026-08-24T23:46:46Z)"
run "$T/koto" 1.4.2
expect 1 "an older major fails"

stub "koto 0.12.2 (1ca8c98 2026-08-24T23:46:46Z)"
run "$T/koto" 0.13.0
expect 1 "koto 0.12.2 fails a 0.13.0 floor"

run "$T/no-such-koto"
expect 1 "a missing koto fails, so a skipped suite cannot pass as green"

stub "something else entirely"
run "$T/koto" 1.4.2
expect 1 "an unreadable version line fails"

stub "koto 1.5.0 (0000000 2026-10-01T00:00:00Z)"
run "$T/koto" latest
expect 1 "a floor that is not MAJOR.MINOR.PATCH is refused"

# The manifest tracks a koto major version: `tsuku install` resolves "0" to the
# newest 0.x, so it never downgrades a newer koto the way an exact pin would.
PIN=$(sed -n 's/^[[:space:]]*"tsukumogami\/koto"[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' "$REPO/.tsuku.toml" | head -1)
if printf '%s' "$PIN" | grep -Eq '^[0-9]+$'; then
    pass "the committed .tsuku.toml tracks a koto major version ($PIN)"
else
    fail "the committed .tsuku.toml must track a koto major version such as \"0\", not [$PIN]"
fi
if [ "$PIN" = "${DEFAULT_FLOOR%%.*}" ]; then
    pass "the tracked major ($PIN) is the floor's major (${DEFAULT_FLOOR%%.*})"
else
    fail "the tracked major [$PIN] differs from the floor's major [${DEFAULT_FLOOR%%.*}]"
fi

echo
echo "assert-koto-floor_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
