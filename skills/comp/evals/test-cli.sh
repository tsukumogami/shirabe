#!/usr/bin/env bash
# test-cli.sh — deterministic CLI checks for the comp skill.
#
# Complements skills/comp/evals/evals.json (transcript-graded skill evals)
# by exercising shirabe validate behavior and the transition-status script
# against the committed fixtures. COMP is private-only, so the structural
# checks run with --visibility private; the R9 checks run without it.
#
# Usage: bash skills/comp/evals/test-cli.sh
# Exit codes: 0 all checks pass; 1 one or more checks fail.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

SHIRABE="${SHIRABE:-shirabe}"
if ! command -v "$SHIRABE" >/dev/null 2>&1; then
    # Build the Rust binary if shirabe is not already on PATH.
    cargo build -p shirabe || { echo "FAIL: could not build shirabe binary"; exit 1; }
    SHIRABE="target/debug/shirabe"
fi

FIXTURES_DIR="skills/comp/evals/fixtures"
TRANSITION="skills/comp/scripts/transition-status.sh"

pass_count=0
fail_count=0

check() {
    local name="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS  $name"
        pass_count=$((pass_count + 1))
    else
        echo "  FAIL  $name (expected '$expected', got '$actual')"
        fail_count=$((fail_count + 1))
    fi
}

contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS  $name"
        pass_count=$((pass_count + 1))
    else
        echo "  FAIL  $name (output missing '$needle': $haystack)"
        fail_count=$((fail_count + 1))
    fi
}

not_contains() {
    local name="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  PASS  $name"
        pass_count=$((pass_count + 1))
    else
        echo "  FAIL  $name (output unexpectedly contains '$needle': $haystack)"
        fail_count=$((fail_count + 1))
    fi
}

# ----- shirabe validate behavior (COMP is private-only) -----

echo "[shirabe validate]"

# Scenario 1: structural happy path validates under private visibility.
"$SHIRABE" validate --visibility private "$FIXTURES_DIR/COMP-happy.md" >/dev/null 2>&1
check "happy path validates under private (exit 0)" "$?" "0"

# Scenario 2: FC04 missing-section rejects under private visibility.
"$SHIRABE" validate --visibility private "$FIXTURES_DIR/COMP-missing-section.md" >/dev/null 2>&1
check "missing-section rejects under private (exit 1)" "$?" "1"
out=$("$SHIRABE" validate --visibility private "$FIXTURES_DIR/COMP-missing-section.md" 2>&1)
contains "missing-section error includes [FC04] tag" "$out" "[FC04]"

# Scenario 3: FC02 invalid-status rejects under private visibility.
"$SHIRABE" validate --visibility private "$FIXTURES_DIR/COMP-invalid-status.md" >/dev/null 2>&1
check "invalid-status rejects under private (exit 1)" "$?" "1"
out=$("$SHIRABE" validate --visibility private "$FIXTURES_DIR/COMP-invalid-status.md" 2>&1)
contains "invalid-status error includes [FC02] tag" "$out" "[FC02]"

# Scenario 4: R9 rejects a well-formed COMP under public visibility.
"$SHIRABE" validate --visibility public "$FIXTURES_DIR/COMP-r9-public.md" >/dev/null 2>&1
check "well-formed COMP rejected under public (exit 1)" "$?" "1"
out=$("$SHIRABE" validate --visibility public "$FIXTURES_DIR/COMP-r9-public.md" 2>&1)
contains "public rejection includes [R9] tag" "$out" "[R9]"

# Scenario 5: R9 fails closed under unset visibility.
"$SHIRABE" validate "$FIXTURES_DIR/COMP-happy.md" >/dev/null 2>&1
check "well-formed COMP rejected under unset visibility (exit 1)" "$?" "1"
out=$("$SHIRABE" validate "$FIXTURES_DIR/COMP-happy.md" 2>&1)
contains "unset-visibility rejection includes [R9] tag (fail-closed)" "$out" "[R9]"

# Scenario 6: R9 fires before FC — a structurally broken COMP under public
# shows only R9, not FC04.
out=$("$SHIRABE" validate --visibility public "$FIXTURES_DIR/COMP-missing-section.md" 2>&1)
contains "R9-before-FC: broken COMP under public shows [R9]" "$out" "[R9]"
not_contains "R9-before-FC: FC04 is short-circuited under public" "$out" "[FC04]"

# ----- transition-status.sh behavior -----

echo ""
echo "[transition-status.sh]"

mkdir -p docs/competitive
# Scenario 7: Draft -> Accepted transitions cleanly in place.
tmp_accept="docs/competitive/COMP-test-accept.md"
cp "$FIXTURES_DIR/COMP-draft-to-accepted.md" "$tmp_accept"
bash "$TRANSITION" "$tmp_accept" Accepted >/dev/null 2>&1
check "Draft -> Accepted transitions cleanly (exit 0)" "$?" "0"
fm_status=$(grep "^status:" "$tmp_accept" | sed 's/status: //')
check "frontmatter status is Accepted after transition" "$fm_status" "Accepted"
body_status=$(grep -A 3 '^## Status' "$tmp_accept" | grep -E '^(Draft|Accepted|Done)' | head -1)
check "body status is Accepted after transition" "$body_status" "Accepted"
if [[ -f "$tmp_accept" ]]; then
    echo "  PASS  file remains at docs/competitive/ (no movement)"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  file was moved unexpectedly"
    fail_count=$((fail_count + 1))
fi
rm -f "$tmp_accept"

echo ""
echo "[summary] $pass_count passed, $fail_count failed"
if [[ $fail_count -gt 0 ]]; then
    exit 1
fi
exit 0
