#!/usr/bin/env bash
# check-koto-release_test.sh -- test harness for scripts/check-koto-release.sh.
#
# Every case runs the script against a stand-in koto, so no case depends on the
# koto a developer has installed. The stand-in answers `koto version` with a
# chosen version and `koto template compile <file>` with a chosen verdict:
#
#   the minimum, every compile clean, the floor mutation refused  -> exit 0
#   a koto at another version                                     -> exit 1,
#                                                                    "want exactly"
#   a declared template that does not compile                     -> exit 1,
#                                                                    koto's output
#   a koto that lets the floor mutation through                   -> exit 1,
#                                                                    "did not refuse"
#
# The stand-in tells the mutated copy from the original by the `mode: auto` the
# script writes into it, which no shipped template carries.
#
# Usage: bash scripts/check-koto-release_test.sh
#
# Exit codes:
#   0 -- all cases pass, or yq (mikefarah v4) is absent and the run skipped
#   1 -- one or more cases failed, or yq is absent and
#        CHECK_KOTO_RELEASE_REQUIRE_YQ=1 says it must not be (the Linux CI leg
#        sets it, so a runner image that drops yq fails rather than skipping)
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-koto-release.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# The script refuses to run without mikefarah yq v4, and so does this test.
case "$(yq --version 2>&1)" in
    *mikefarah/yq*' version v4.'* | *mikefarah/yq*' version 4.'*) ;;
    *)
        if [ "${CHECK_KOTO_RELEASE_REQUIRE_YQ-}" = 1 ]; then
            echo "FAIL: mikefarah yq v4 not on PATH, and CHECK_KOTO_RELEASE_REQUIRE_YQ=1 requires it"
            exit 1
        fi
        echo "SKIP: mikefarah yq v4 not on PATH -- check-koto-release.sh cannot run"
        exit 0
        ;;
esac

MINIMUM=$("$BASH_BIN" "$SCRIPT_DIR/assert-koto-floor.sh" --print-floor 2>/dev/null)
if [ -z "$MINIMUM" ]; then
    echo "FAIL: cannot read the koto minimum from scripts/assert-koto-floor.sh" >&2
    exit 1
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/check-koto-release-test.XXXXXX")
T=$(cd "$T" && pwd -P)
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

# stub <version> <compile-behaviour>: writes $T/koto. Behaviours:
#   clean      every compile succeeds, the mutated copy fails with E-DECIDER-FLOOR
#   broken     every compile of work-on.md fails with a parse error
#   permissive every compile succeeds, the mutated copy included
stub() {
    cat >"$T/koto" <<STUB
#!/bin/sh
case "\$1" in
    version) echo "koto $1 (0000000 2026-01-01T00:00:00Z)"; exit 0 ;;
    template)
        f="\$3"
        case "$2" in
            broken)
                case "\$f" in *work-on.md) echo "error: E-PARSE stub refuses \$f"; exit 1 ;; esac ;;
            clean)
                if grep -q 'mode: auto' "\$f"; then
                    echo "error: E-DECIDER-FLOOR an auto answer routes to validation_exit"; exit 1
                fi ;;
        esac
        echo "/stub/cache/compiled.json"; exit 0 ;;
esac
exit 2
STUB
    chmod +x "$T/koto"
}

RC=0
OUT=""
run() {
    RC=0
    OUT=$(KOTO_RELEASE_BIN="$T/koto" "$BASH_BIN" "$CHECK" 2>&1) || RC=$?
}

stub "$MINIMUM" clean
run
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "compile on koto $MINIMUM"; then
    pass "the minimum, with every template compiling and the mutation refused, passes"
else
    fail "a clean run at the minimum did not pass (rc=$RC): $OUT"
fi

stub 0.1.0 clean
run
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "want exactly the koto minimum $MINIMUM"; then
    pass "a koto at another version is refused, naming the minimum"
else
    fail "a koto at another version was not refused (rc=$RC): $OUT"
fi

stub "$MINIMUM" broken
run
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'E-PARSE stub refuses'; then
    pass "a declared template that does not compile fails the check and shows koto's output"
else
    fail "a compile failure was not surfaced (rc=$RC): $OUT"
fi

stub "$MINIMUM" permissive
run
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'the floor did not refuse'; then
    pass "a koto that compiles the auto-exit mutation fails the check"
else
    fail "a koto that let the mutation through was not caught (rc=$RC): $OUT"
fi

KOTO_RELEASE_BIN=relative/koto "$BASH_BIN" "$CHECK" >/dev/null 2>&1
if [ "$?" -eq 1 ]; then
    pass "a relative KOTO_RELEASE_BIN is refused"
else
    fail "a relative KOTO_RELEASE_BIN was accepted"
fi

echo
echo "check-koto-release_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
