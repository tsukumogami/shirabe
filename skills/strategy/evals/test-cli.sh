#!/usr/bin/env bash
# test-cli.sh — deterministic CLI checks for the strategy skill.
#
# Complements skills/strategy/evals/evals.json (transcript-graded skill
# evals) by exercising `shirabe validate` and `shirabe transition` behavior
# against the committed fixtures. The transcript-graded evals cover
# authoring intent; this script covers binary CLI behavior.
#
# Usage: bash skills/strategy/evals/test-cli.sh
# Exit codes: 0 all checks pass; 1 one or more checks fail.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

# Resolve the shirabe binary. Precedence: $SHIRABE, then a locally built
# release/debug binary, then `shirabe` on PATH. The CLI is a Rust crate, so a
# missing binary is built with cargo.
SHIRABE="${SHIRABE:-}"
if [[ -z "$SHIRABE" ]]; then
    if [[ -x "$REPO_ROOT/target/release/shirabe" ]]; then
        SHIRABE="$REPO_ROOT/target/release/shirabe"
    elif [[ -x "$REPO_ROOT/target/debug/shirabe" ]]; then
        SHIRABE="$REPO_ROOT/target/debug/shirabe"
    elif command -v shirabe >/dev/null 2>&1; then
        SHIRABE="shirabe"
    else
        cargo build --release --bin shirabe || { echo "FAIL: could not build shirabe binary"; exit 1; }
        SHIRABE="$REPO_ROOT/target/release/shirabe"
    fi
fi

FIXTURES_DIR="skills/strategy/evals/fixtures"

pass_count=0
fail_count=0

check() {
    local name="$1"
    local actual="$2"
    local expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS  $name"
        pass_count=$((pass_count + 1))
    else
        echo "  FAIL  $name (expected '$expected', got '$actual')"
        fail_count=$((fail_count + 1))
    fi
}

# ----- shirabe validate behavior -----

echo "[shirabe validate]"

"$SHIRABE" validate "$FIXTURES_DIR/STRATEGY-happy.md" >/dev/null 2>&1
check "happy path validates (exit 0)" "$?" "0"

"$SHIRABE" validate "$FIXTURES_DIR/STRATEGY-missing-section.md" >/dev/null 2>&1
check "missing-section rejects (exit 1, FC04)" "$?" "1"

out=$("$SHIRABE" validate "$FIXTURES_DIR/STRATEGY-missing-section.md" 2>&1)
if [[ "$out" == *"[FC04]"* ]]; then
    echo "  PASS  missing-section error includes [FC04] tag"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  missing-section error does not include [FC04] tag (got: $out)"
    fail_count=$((fail_count + 1))
fi

"$SHIRABE" validate "$FIXTURES_DIR/STRATEGY-invalid-status.md" >/dev/null 2>&1
check "invalid-status rejects (exit 1, FC02)" "$?" "1"

out=$("$SHIRABE" validate "$FIXTURES_DIR/STRATEGY-invalid-status.md" 2>&1)
if [[ "$out" == *"[FC02]"* ]]; then
    echo "  PASS  invalid-status error includes [FC02] tag"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  invalid-status error does not include [FC02] tag"
    fail_count=$((fail_count + 1))
fi

"$SHIRABE" validate --visibility public "$FIXTURES_DIR/STRATEGY-public-leak.md" >/dev/null 2>&1
check "public-leak rejects with --visibility public (exit 1, R8)" "$?" "1"

out=$("$SHIRABE" validate --visibility public "$FIXTURES_DIR/STRATEGY-public-leak.md" 2>&1)
if [[ "$out" == *"[R8]"* ]]; then
    echo "  PASS  public-leak error includes [R8] tag"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  public-leak error does not include [R8] tag"
    fail_count=$((fail_count + 1))
fi

"$SHIRABE" validate --visibility private "$FIXTURES_DIR/STRATEGY-private-allowed.md" >/dev/null 2>&1
check "private-allowed accepts with --visibility private (exit 0, gate bidirectionality)" "$?" "0"

# Empty visibility fails closed (R8 fires on Competitive Considerations even without an explicit flag).
"$SHIRABE" validate "$FIXTURES_DIR/STRATEGY-public-leak.md" >/dev/null 2>&1
check "public-leak rejects with empty visibility (fail-closed)" "$?" "1"

# ----- shirabe transition behavior -----

echo ""
echo "[shirabe transition]"

# Copy fixture into docs/strategies/ so the directory comparison matches.
mkdir -p docs/strategies docs/strategies/sunset
tmp_accepted="docs/strategies/STRATEGY-test-accepted-to-active.md"
cp "$FIXTURES_DIR/STRATEGY-accepted-to-active.md" "$tmp_accepted"

"$SHIRABE" transition "$tmp_accepted" Active >/dev/null 2>&1
check "Accepted -> Active transitions cleanly (exit 0)" "$?" "0"

new_status=$(grep "^status:" "$tmp_accepted" | sed 's/status: //')
check "frontmatter status is Active after transition" "$new_status" "Active"

if [[ -f "$tmp_accepted" ]]; then
    echo "  PASS  file remains at docs/strategies/ (no movement for Accepted -> Active)"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  file was moved unexpectedly"
    fail_count=$((fail_count + 1))
fi
rm -f "$tmp_accepted"

# Sunset with reason (the lifecycle refinement: Accepted -> Sunset).
# git add is required for git mv to succeed; real STRATEGY files are tracked.
tmp_sunset="docs/strategies/STRATEGY-test-accepted-to-sunset.md"
cp "$FIXTURES_DIR/STRATEGY-accepted-to-sunset.md" "$tmp_sunset"
git add "$tmp_sunset" >/dev/null 2>&1
"$SHIRABE" transition "$tmp_sunset" Sunset --reason "Upstream VISION pivoted" >/dev/null 2>&1
check "Accepted -> Sunset (lifecycle refinement) succeeds (exit 0)" "$?" "0"

if [[ -f "docs/strategies/sunset/STRATEGY-test-accepted-to-sunset.md" ]]; then
    echo "  PASS  file moved to docs/strategies/sunset/"
    pass_count=$((pass_count + 1))
    sunset_status=$(grep "^status:" "docs/strategies/sunset/STRATEGY-test-accepted-to-sunset.md" | sed 's/status: //')
    check "frontmatter status is Sunset after transition" "$sunset_status" "Sunset"
    sunset_reason=$(grep "^sunset_reason:" "docs/strategies/sunset/STRATEGY-test-accepted-to-sunset.md" | sed 's/sunset_reason: //')
    check "sunset_reason captured in frontmatter" "$sunset_reason" "Upstream VISION pivoted"
else
    echo "  FAIL  file was not moved to docs/strategies/sunset/"
    fail_count=$((fail_count + 1))
fi
# Clean up: rm the file and reset the index entry left over from `git add`/`git mv`.
git rm --cached -f "docs/strategies/sunset/STRATEGY-test-accepted-to-sunset.md" >/dev/null 2>&1 || true
rm -f "docs/strategies/sunset/STRATEGY-test-accepted-to-sunset.md"

# Reason sanitization.
tmp_sanitize="docs/strategies/STRATEGY-test-sanitize.md"
cp "$FIXTURES_DIR/STRATEGY-accepted-to-sunset.md" "$tmp_sanitize"

"$SHIRABE" transition "$tmp_sanitize" Sunset --reason "evil/path" >/dev/null 2>&1
check "reason with forward-slash rejected (exit 2)" "$?" "2"

"$SHIRABE" transition "$tmp_sanitize" Sunset --reason "evil&payload" >/dev/null 2>&1
check "reason with ampersand rejected (exit 2)" "$?" "2"

"$SHIRABE" transition "$tmp_sanitize" Sunset --reason "evil\\backslash" >/dev/null 2>&1
check "reason with backslash rejected (exit 2)" "$?" "2"

"$SHIRABE" transition "$tmp_sanitize" Sunset --reason "" >/dev/null 2>&1
check "empty reason rejected (exit 2)" "$?" "2"

"$SHIRABE" transition "$tmp_sanitize" Sunset --reason "boundary --- delimiter" >/dev/null 2>&1
check "reason with frontmatter delimiter rejected (exit 2)" "$?" "2"

rm -f "$tmp_sanitize"

# Downgrade rejection.
tmp_downgrade="docs/strategies/STRATEGY-test-downgrade.md"
cp "$FIXTURES_DIR/STRATEGY-accepted-to-active.md" "$tmp_downgrade"
"$SHIRABE" transition "$tmp_downgrade" Draft >/dev/null 2>&1
check "Accepted -> Draft downgrade rejected (exit 2)" "$?" "2"
rm -f "$tmp_downgrade"

# Direct Draft -> Sunset rejection (must go through Accepted first).
tmp_draft="docs/strategies/STRATEGY-test-draft.md"
cp "$FIXTURES_DIR/STRATEGY-happy.md" "$tmp_draft"
"$SHIRABE" transition "$tmp_draft" Sunset --reason "anything" >/dev/null 2>&1
check "Draft -> Sunset rejected (exit 2)" "$?" "2"
rm -f "$tmp_draft"

echo ""
echo "[summary] $pass_count passed, $fail_count failed"
if [[ $fail_count -gt 0 ]]; then
    exit 1
fi
exit 0
