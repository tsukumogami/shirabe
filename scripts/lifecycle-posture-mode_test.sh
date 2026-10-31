#!/usr/bin/env bash
# Tests for scripts/lifecycle-posture-mode.sh, the posture-to-mode resolution
# behind lifecycle.yml's `posture` input.
#
# shirabe's own lifecycle caller uses the default `auto`, so the `draft` path
# never runs in this repository's CI except here.
#
# Usage: bash scripts/lifecycle-posture-mode_test.sh

set -euo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUT="$SCRIPT_DIR/lifecycle-posture-mode.sh"

T="$(mktemp -d "${TMPDIR:-/tmp}/lifecycle-posture-mode.XXXXXX")" || {
    echo "mktemp failed" >&2
    exit 1
}
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0

# resolve <posture> <pr_draft> -> sets OUT and RC from one run of the script.
resolve() {
    local rc=0
    OUT="$(cd "$T" && POSTURE="$1" PR_DRAFT="$2" bash "$SUT" 2>&1)" || rc=$?
    RC="$rc"
}

check() {
    local name="$1" ok="$2"
    if [ "$ok" = "yes" ]; then
        PASS=$((PASS + 1))
        echo "PASS: $name"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $name"
        echo "  exit: $RC"
        echo "  output: $OUT"
    fi
}

is() { if [ "$1" = "$2" ]; then echo yes; else echo no; fi; }

# --- accepted values ---
resolve auto false
check "auto on a ready PR runs ready posture" "$(is "$RC:$OUT" "0:--mode=ready")"

resolve auto true
check "auto on a draft PR runs draft posture" "$(is "$RC:$OUT" "0:")"

resolve draft true
check "draft on a draft PR runs draft posture" "$(is "$RC:$OUT" "0:")"

resolve draft false
check "draft on a ready PR never yields --mode=ready" "$(is "$RC:$OUT" "0:")"

resolve auto ""
check "auto with no draft state (non-PR trigger) runs draft posture" "$(is "$RC:$OUT" "0:")"

# --- rejected values: exit 1, one ::error:: naming both values, no echo ---
reject() {
    local name="$1" value="$2"
    rm -f "$T/x"
    resolve "$value" false
    local ok=yes
    [ "$RC" = "1" ] || ok=no
    case "$OUT" in
        "::error::"*"'auto'"*"'draft'"*) ;;
        *) ok=no ;;
    esac
    [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = "1" ] || ok=no
    [ ! -e "$T/x" ] || ok=no
    # The error never repeats the rejected value back.
    if [ -n "$value" ] && [ "$value" != "draft" ] && [ "$value" != "auto" ]; then
        case "$OUT" in
            *"$value"*) ok=no ;;
        esac
    fi
    check "$name" "$ok"
}

reject "empty posture is rejected" ""
reject "ready is not a posture value" "ready"
reject "a value carrying a command separator is rejected and runs nothing" 'draft; touch "$T/x"'
reject "a value carrying a command substitution is rejected and runs nothing" '$(touch "$T/x")'
reject "case matters: Draft is rejected" "Draft"

# Unset POSTURE entirely, as a caller that drops the env line would.
rc=0
OUT="$(cd "$T" && env -u POSTURE PR_DRAFT=false bash "$SUT" 2>&1)" || rc=$?
RC="$rc"
check "unset posture is rejected" "$(is "$RC" "1")"

echo
echo "lifecycle-posture-mode: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
