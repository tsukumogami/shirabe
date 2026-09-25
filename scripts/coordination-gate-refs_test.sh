#!/usr/bin/env bash
# Tests for scripts/coordination-gate-refs.sh, the ref extraction and
# self-reference filter behind lifecycle.yml's coordination merge-last gate.
#
# The coordination PR under test is tsukumogami/shirabe#500. Its index can name
# itself in a single-repo effort; that entry must be dropped while every other
# ref survives.
#
# Usage: bash scripts/coordination-gate-refs_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUT="$SCRIPT_DIR/coordination-gate-refs.sh"

SELF_REPO="tsukumogami/shirabe"
SELF_NUMBER="500"

PASS=0
FAIL=0

# run_refs <body> -> prints the script's output for the fixed self PR.
run_refs() {
    printf '%s\n' "$1" | bash "$SUT" "$SELF_REPO" "$SELF_NUMBER"
}

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "PASS: $name"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $name"
        echo "  expected: $(printf '%s' "$expected" | tr '\n' ' ')"
        echo "  actual:   $(printf '%s' "$actual" | tr '\n' ' ')"
    fi
}

NL='
'

# --- self-reference dropped, same-repo other PR kept ---
BODY="> This is a **coordination PR** for a coordinated effort.

## PR Index

- pr-1 | tsukumogami/shirabe:docs/plans/PLAN-x.md#498 | open
- pr-2 | tsukumogami/shirabe:docs/plans/PLAN-x.md#499 | merged
- coord | tsukumogami/shirabe:docs/plans/PLAN-x.md#500 | open"
assert_eq "self-ref dropped, same-repo other PRs kept" \
    "tsukumogami/shirabe:docs/plans/PLAN-x.md#498${NL}tsukumogami/shirabe:docs/plans/PLAN-x.md#499" \
    "$(run_refs "$BODY")"

# --- same number in another repository is kept ---
BODY="- pr-1 | tsukumogami/koto:docs/plans/PLAN-y.md#500 | open
- coord | tsukumogami/shirabe:docs/plans/PLAN-x.md#500 | open"
assert_eq "same number in another repo kept" \
    "tsukumogami/koto:docs/plans/PLAN-y.md#500" \
    "$(run_refs "$BODY")"

# --- self-reference matched case-insensitively (GitHub slugs are) ---
BODY="- coord | Tsukumogami/Shirabe:docs/plans/PLAN-x.md#500 | open
- pr-1 | tsukumogami/shirabe:docs/plans/PLAN-x.md#5000 | open"
assert_eq "self-ref matched case-insensitively; #5000 is not #500" \
    "tsukumogami/shirabe:docs/plans/PLAN-x.md#5000" \
    "$(run_refs "$BODY")"

# --- self-reference-only index is empty ---
BODY="- coord | tsukumogami/shirabe:docs/plans/PLAN-x.md#500 | open"
assert_eq "self-ref-only index prints nothing (empty index)" "" "$(run_refs "$BODY")"

# --- no refs at all is empty, not an error ---
assert_eq "body with no refs prints nothing" "" "$(run_refs "no index here")"

# --- duplicates collapse ---
BODY="- a | tsukumogami/koto:docs/x.md#7 | open
- b | tsukumogami/koto:docs/x.md#7 | open"
assert_eq "duplicate refs collapse" "tsukumogami/koto:docs/x.md#7" "$(run_refs "$BODY")"

# --- usage errors ---
if printf '' | bash "$SUT" "$SELF_REPO" "abc" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1)); echo "FAIL: non-numeric pr-number rejected"
else
    PASS=$((PASS + 1)); echo "PASS: non-numeric pr-number rejected"
fi
if printf '' | bash "$SUT" "$SELF_REPO" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1)); echo "FAIL: missing argument rejected"
else
    PASS=$((PASS + 1)); echo "PASS: missing argument rejected"
fi

echo ""
echo "coordination-gate-refs: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
