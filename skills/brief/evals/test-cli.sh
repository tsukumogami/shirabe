#!/usr/bin/env bash
# test-cli.sh — deterministic CLI checks for the brief skill.
#
# Complements skills/brief/evals/evals.json (transcript-graded skill
# evals) by exercising shirabe validate behavior and the transition-status
# script against the committed fixtures. The transcript-graded evals
# cover authoring intent; this script covers binary CLI behavior.
#
# Usage: bash skills/brief/evals/test-cli.sh
# Exit codes: 0 all checks pass; 1 one or more checks fail.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

SHIRABE="${SHIRABE:-shirabe}"
if ! command -v "$SHIRABE" >/dev/null 2>&1; then
    # Build the binary if it is not on PATH.
    SHIRABE=/tmp/shirabe-cli-test
    go build -o "$SHIRABE" ./cmd/shirabe || { echo "FAIL: could not build shirabe binary"; exit 1; }
fi

FIXTURES_DIR="skills/brief/evals/fixtures"
TRANSITION="skills/brief/scripts/transition-status.sh"

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

"$SHIRABE" validate "$FIXTURES_DIR/BRIEF-happy.md" >/dev/null 2>&1
check "happy path validates (exit 0)" "$?" "0"

"$SHIRABE" validate "$FIXTURES_DIR/BRIEF-missing-section.md" >/dev/null 2>&1
check "missing-section rejects (exit 1, FC04)" "$?" "1"

out=$("$SHIRABE" validate "$FIXTURES_DIR/BRIEF-missing-section.md" 2>&1)
if [[ "$out" == *"[FC04]"* ]]; then
    echo "  PASS  missing-section error includes [FC04] tag"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  missing-section error does not include [FC04] tag (got: $out)"
    fail_count=$((fail_count + 1))
fi

"$SHIRABE" validate "$FIXTURES_DIR/BRIEF-invalid-status.md" >/dev/null 2>&1
check "invalid-status rejects (exit 1, FC02)" "$?" "1"

out=$("$SHIRABE" validate "$FIXTURES_DIR/BRIEF-invalid-status.md" 2>&1)
if [[ "$out" == *"[FC02]"* ]]; then
    echo "  PASS  invalid-status error includes [FC02] tag"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  invalid-status error does not include [FC02] tag"
    fail_count=$((fail_count + 1))
fi

# The happy fixture's body ## Status first line matches its frontmatter status,
# so it passes FC03 (the bare-status-word convention).
"$SHIRABE" validate "$FIXTURES_DIR/BRIEF-happy.md" >/dev/null 2>&1
check "matching-body-status happy brief passes FC03 (exit 0)" "$?" "0"

# ----- transition-status.sh behavior -----

echo ""
echo "[transition-status.sh]"

# Copy fixture into docs/briefs/ so the script's path resolution matches a
# real brief location. Briefs never move directories on any transition.
mkdir -p docs/briefs
tmp_accept="docs/briefs/BRIEF-test-accept.md"
cp "$FIXTURES_DIR/BRIEF-accept.md" "$tmp_accept"

bash "$TRANSITION" "$tmp_accept" Accepted >/dev/null 2>&1
check "Draft -> Accepted transitions cleanly (exit 0)" "$?" "0"

fm_status=$(grep "^status:" "$tmp_accept" | sed 's/status: //')
check "frontmatter status is Accepted after transition" "$fm_status" "Accepted"

body_status=$(grep -A 3 '^## Status' "$tmp_accept" | grep -E '^(Draft|Accepted|Done)' | head -1)
check "body ## Status first line is Accepted after transition" "$body_status" "Accepted"

if [[ -f "$tmp_accept" ]]; then
    echo "  PASS  file remains at docs/briefs/ (no movement for Draft -> Accepted)"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  file was moved unexpectedly"
    fail_count=$((fail_count + 1))
fi

# Continue the lifecycle: Accepted -> Done on the same in-place file.
bash "$TRANSITION" "$tmp_accept" Done >/dev/null 2>&1
check "Accepted -> Done transitions cleanly (exit 0)" "$?" "0"

done_fm_status=$(grep "^status:" "$tmp_accept" | sed 's/status: //')
check "frontmatter status is Done after transition" "$done_fm_status" "Done"

if [[ -f "$tmp_accept" ]]; then
    echo "  PASS  file remains at docs/briefs/ (no movement for Accepted -> Done)"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  file was moved unexpectedly"
    fail_count=$((fail_count + 1))
fi
rm -f "$tmp_accept"

# Downgrade rejection: Accepted -> Draft is forbidden.
tmp_downgrade="docs/briefs/BRIEF-test-downgrade.md"
cp "$FIXTURES_DIR/BRIEF-accept.md" "$tmp_downgrade"
bash "$TRANSITION" "$tmp_downgrade" Accepted >/dev/null 2>&1
bash "$TRANSITION" "$tmp_downgrade" Draft >/dev/null 2>&1
rc=$?
if [[ "$rc" -ne 0 ]]; then
    echo "  PASS  Accepted -> Draft downgrade rejected (nonzero)"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  Accepted -> Draft downgrade should be rejected (got exit 0)"
    fail_count=$((fail_count + 1))
fi
rm -f "$tmp_downgrade"

# Skip rejection: Draft -> Done is forbidden (must accept first).
tmp_skip="docs/briefs/BRIEF-test-skip.md"
cp "$FIXTURES_DIR/BRIEF-accept.md" "$tmp_skip"
bash "$TRANSITION" "$tmp_skip" Done >/dev/null 2>&1
rc=$?
if [[ "$rc" -ne 0 ]]; then
    echo "  PASS  Draft -> Done rejected (nonzero, must accept first)"
    pass_count=$((pass_count + 1))
else
    echo "  FAIL  Draft -> Done should be rejected (got exit 0)"
    fail_count=$((fail_count + 1))
fi
rm -f "$tmp_skip"

echo ""
echo "[summary] $pass_count passed, $fail_count failed"
if [[ $fail_count -gt 0 ]]; then
    exit 1
fi
exit 0
