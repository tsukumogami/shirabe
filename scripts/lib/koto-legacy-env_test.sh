#!/usr/bin/env bash
# koto-legacy-env_test.sh -- tests for scripts/lib/koto-legacy-env.sh, the
# helper a test harness sources to turn on koto-open.sh's legacy-environment
# knob only when its koto accepts the flag.
#
# Usage: bash scripts/lib/koto-legacy-env_test.sh
# Needs no koto: two stand-ins answer `init --help`, one listing
# --legacy-environment and one not.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/koto-legacy-env.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/koto-legacy-env-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/new" "$T/old"
cat >"$T/new/koto" <<'STUB'
#!/bin/sh
[ "$1 $2" = "init --help" ] || exit 2
echo "      --attach-live          Attach to a running session"
echo "      --legacy-environment   Run this session's commands with the caller's whole environment"
STUB
cat >"$T/old/koto" <<'STUB'
#!/bin/sh
[ "$1 $2" = "init --help" ] || exit 2
echo "      --attach-live          Attach to a running session"
STUB
chmod +x "$T/new/koto" "$T/old/koto"

# probe <label> <env assignments...> -- source the helper in a clean shell
# (set -u on, as the harnesses run) and print the knob, how many words the
# flag argument expands to unquoted, and those words.
probe() {
    env -u SHIRABE_KOTO_LEGACY_ENVIRONMENT -u KOTO_BIN "$@" bash -c '
        set -u
        . "$0"
        koto_legacy_env_enable
        set -- $KOTO_LEGACY_ENV_ARG
        printf "%s|%s|%s\n" "${SHIRABE_KOTO_LEGACY_ENVIRONMENT-unset}" "$#" "$*"
    ' "$LIB"
}

check() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}

check "a koto that lists the flag turns the knob on" \
    "1|1|--legacy-environment" "$(probe PATH="$T/new:/usr/bin:/bin")"
check "a koto that doesn't list it leaves the knob unset" \
    "unset|0|" "$(probe PATH="$T/old:/usr/bin:/bin")"
check "no koto at all leaves the knob unset" \
    "unset|0|" "$(probe PATH="/usr/bin:/bin")"
check "KOTO_BIN is the koto probed, not PATH's" \
    "1|1|--legacy-environment" "$(probe PATH="$T/old:/usr/bin:/bin" KOTO_BIN="$T/new/koto")"
check "an explicit 0 is kept, even on a koto with the flag" \
    "0|0|" "$(probe PATH="$T/new:/usr/bin:/bin" SHIRABE_KOTO_LEGACY_ENVIRONMENT=0)"
check "an explicit 1 is kept, and fills the flag argument" \
    "1|1|--legacy-environment" "$(probe PATH="$T/old:/usr/bin:/bin" SHIRABE_KOTO_LEGACY_ENVIRONMENT=1)"

# The helper only probes: it never writes a koto session or runs anything but
# `init --help`. The stand-ins exit 2 on any other call, which the probe would
# have turned into an unset knob, so the first case above already covers it.

echo "koto-legacy-env_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
