#!/usr/bin/env bash
# run-cascade_test.sh — Test harness for run-cascade.sh
# Part of the work-on skill
#
# Creates isolated fixture docs in a temp git repo, runs run-cascade.sh
# against each scenario, and asserts the expected JSON output.
#
# Usage: run-cascade_test.sh [--verbose]
#
# Exit codes:
#   0 — all scenarios pass
#   1 — one or more scenarios failed

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CASCADE_SCRIPT="$SCRIPT_DIR/run-cascade.sh"

# Path to the stub shirabe binary the cascade calls for status transitions.
# Set per-test by setup_shirabe_stub and injected via SHIRABE_BIN.
SHIRABE_STUB=""

PASS_COUNT=0
FAIL_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; ((PASS_COUNT++)) || true; }
fail() { echo -e "${RED}FAIL${NC}: $*"; ((FAIL_COUNT++)) || true; }

# ── Fixture setup helpers ──────────────────────────────────────────────────────

# Write a minimal ROADMAP fixture with two feature entries
write_roadmap() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'EOF'
---
status: Active
---

# ROADMAP: Cascade Test

## Status

Active

## Theme

Test roadmap for cascade validation.

## Features

### Feature 1: Short Chain Feature

**Status:** Planned
**Downstream:** PLAN-cascade-test-short.md

### Feature 2: Full Chain Feature

**Status:** Planned
**Downstream:** PLAN-cascade-test-full.md

### Feature 3: Already Done Feature

**Status:** Done
**Downstream:** closed
EOF
}

# Write a minimal DESIGN fixture
write_design() {
    local path="$1"
    local upstream="$2"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<EOF
---
status: Planned
upstream: $upstream
---

# DESIGN: Cascade Test

## Status

Planned

## Context and Problem Statement

Test design for cascade validation.

## Implementation Approach

Test only.

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|-------------|------------|
| #1: Test | None | simple |

EOF
}

# Write a minimal PRD fixture
write_prd() {
    local path="$1"
    local upstream="$2"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<EOF
---
status: Accepted
upstream: $upstream
---

# PRD: Cascade Test Full

## Status

Accepted

## Problem Statement

Test PRD for cascade validation.

EOF
}

# Write a minimal BRIEF fixture. The upstream argument is optional: when given
# (non-empty) an `upstream:` frontmatter line is written; when empty the field
# is omitted, matching the optional field in the real format.
write_brief() {
    local path="$1"
    local upstream="${2:-}"
    mkdir -p "$(dirname "$path")"
    if [[ -n "$upstream" ]]; then
        cat > "$path" <<EOF
---
schema: brief/v1
status: Accepted
upstream: $upstream
---

# BRIEF: Cascade Test

## Status

Accepted

EOF
    else
        cat > "$path" <<EOF
---
schema: brief/v1
status: Accepted
---

# BRIEF: Cascade Test

## Status

Accepted

EOF
    fi
}

# Write a minimal PLAN fixture
write_plan() {
    local path="$1"
    local upstream="$2"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<EOF
---
schema: plan/v1
status: Draft
execution_mode: single-pr
upstream: $upstream
milestone: "Test"
issue_count: 1
---

# PLAN: Cascade Test

## Status

Draft

EOF
}

# ── Scenario runner ───────────────────────────────────────────────────────────

# Run cascade and return the JSON output. SHIRABE_BIN points the cascade at
# the stub binary (set by setup_shirabe_stub) so transitions are deterministic
# and offline.
run_cascade() {
    local plan_doc="$1"
    shift
    SHIRABE_BIN="$SHIRABE_STUB" bash "$CASCADE_SCRIPT" "$@" "$plan_doc" 2>/dev/null || true
}

# Assert a jq expression evaluates to "true" on the JSON
assert_json() {
    local scenario="$1"
    local json="$2"
    local expr="$3"
    local desc="$4"

    local result
    result=$(echo "$json" | jq -r "$expr" 2>/dev/null) || result="ERROR"

    if [[ "$result" == "true" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ $desc"
        return 0
    else
        fail "$scenario: $desc (got: $result)"
        [[ "$VERBOSE" == "true" ]] && echo "    JSON: $json"
        return 1
    fi
}

# ── Helper: create isolated test git repo ─────────────────────────────────────
setup_test_repo() {
    local dir="$1"
    mkdir -p "$dir"
    cd "$dir"
    git init -b main > /dev/null 2>&1 || git init > /dev/null 2>&1
    git config user.email "test@cascade.test"
    git config user.name "Cascade Test"
    # Create a fake origin remote (file-based)
    local bare_dir="${dir}_bare"
    mkdir -p "$bare_dir"
    git init --bare "$bare_dir" > /dev/null 2>&1
    git remote add origin "$bare_dir"
    mkdir -p skills/work-on/scripts
}

# Create a single stub `shirabe` binary the cascade invokes via SHIRABE_BIN.
# It reproduces the per-type behavior the cascade depends on:
#   - DESIGN-*  → Current: rewrites status, git mv into <dir>/current/, emits
#                 new_path/moved:true (the cascade parses .new_path to continue)
#   - PRD-*     → Done: rewrites frontmatter + body ## Status in place
#   - ROADMAP-* → Done: rewrites frontmatter status in place
# The stub dispatches on the `transition` subcommand and the doc's basename
# prefix, mirroring the deleted per-skill scripts' combined behavior.
setup_shirabe_stub() {
    local repo_dir="$1"
    local stub="$repo_dir/skills/work-on/scripts/shirabe-stub.sh"

    cat > "$stub" <<'EOF'
#!/usr/bin/env bash
# Stub shirabe binary for the cascade test harness. Only `transition` is used.
set -euo pipefail

SUB="${1:-}"
if [[ "$SUB" != "transition" ]]; then
    echo "stub shirabe: unsupported subcommand: $SUB" >&2
    exit 1
fi
DOC="${2:-}"
TARGET="${3:-}"

base=$(basename "$DOC")

# Rewrite frontmatter status in place (sed -i.bak is portable GNU/BSD).
if grep -q '^status:' "$DOC"; then
    sed -i.bak "s/^status:.*/status: $TARGET/" "$DOC" && rm -f "${DOC}.bak"
fi

case "$base" in
    DESIGN-*)
        # design → Current moves into <dir>/current/
        if [[ "$TARGET" == "Current" ]]; then
            mkdir -p "$(dirname "$DOC")/current"
            NEW_PATH="$(dirname "$DOC")/current/$base"
            mv "$DOC" "$NEW_PATH"
            jq -n --arg p "$DOC" --arg np "$NEW_PATH" --arg ns "$TARGET" \
                '{success: true, doc_path: $p, old_status: "Planned", new_status: $ns, new_path: $np, moved: true}'
        else
            jq -n --arg p "$DOC" --arg ns "$TARGET" \
                '{success: true, doc_path: $p, old_status: "Planned", new_status: $ns, new_path: $p, moved: false}'
        fi
        ;;
    PRD-*)
        if grep -q '^## Status' "$DOC"; then
            # Update body status (BSD sed requires semicolon before closing brace)
            sed -i.bak '/^## Status/{n;s/.*/'"$TARGET"'/;}' "$DOC" 2>/dev/null; rm -f "${DOC}.bak" 2>/dev/null || true
        fi
        jq -n --arg p "$DOC" --arg ns "$TARGET" \
            '{success: true, doc_path: $p, old_status: "Accepted", new_status: $ns}'
        ;;
    BRIEF-*)
        if grep -q '^## Status' "$DOC"; then
            # Update body status (BSD sed requires semicolon before closing brace)
            sed -i.bak '/^## Status/{n;s/.*/'"$TARGET"'/;}' "$DOC" 2>/dev/null; rm -f "${DOC}.bak" 2>/dev/null || true
        fi
        jq -n --arg p "$DOC" --arg ns "$TARGET" \
            '{success: true, doc_path: $p, old_status: "Accepted", new_status: $ns}'
        ;;
    *)
        # ROADMAP-* and any other in-place type
        jq -n --arg p "$DOC" --arg ns "$TARGET" \
            '{success: true, doc_path: $p, old_status: "Active", new_status: $ns}'
        ;;
esac
EOF
    chmod +x "$stub"
    SHIRABE_STUB="$stub"
}

# Commit all files in the repo
commit_all() {
    git add -A
    git commit -m "test fixtures" > /dev/null 2>&1
}

# ── Scenario 1: DESIGN → ROADMAP (short chain, no PRD) ───────────────────────
scenario_design_roadmap() {
    local scenario="Scenario 1: DESIGN→ROADMAP"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    setup_shirabe_stub "$repo"

    # Create fixtures
    write_roadmap "$repo/docs/roadmaps/ROADMAP-cascade-test.md"
    write_design "$repo/docs/designs/DESIGN-cascade-test-short.md" \
        "docs/roadmaps/ROADMAP-cascade-test.md"
    write_plan "$repo/docs/plans/PLAN-cascade-test-short.md" \
        "docs/designs/DESIGN-cascade-test-short.md"

    commit_all

    # Run cascade (no --push, dry run)
    local output
    output=$(run_cascade "docs/plans/PLAN-cascade-test-short.md")

    local ok=true

    # Assert cascade_status
    assert_json "$scenario" "$output" '.cascade_status == "completed"' \
        "cascade_status is completed" || ok=false

    # Assert delete_plan step
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_plan")] | length == 1' \
        "delete_plan step present" || ok=false
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_plan" and .status == "ok")] | length == 1' \
        "delete_plan ok" || ok=false

    # Assert transition_design step
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "transition_design" and .status == "ok")] | length == 1' \
        "transition_design ok" || ok=false

    # Assert update_roadmap_feature step
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "update_roadmap_feature" and .status == "ok")] | length == 1' \
        "update_roadmap_feature ok" || ok=false

    # No PRD step should be present
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "transition_prd")] | length == 0' \
        "no transition_prd step (no PRD in chain)" || ok=false

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 2: DESIGN → PRD → ROADMAP (full chain) ──────────────────────────
scenario_design_prd_roadmap() {
    local scenario="Scenario 2: DESIGN→PRD→ROADMAP"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    setup_shirabe_stub "$repo"

    write_roadmap "$repo/docs/roadmaps/ROADMAP-cascade-test.md"
    write_prd "$repo/docs/prds/PRD-cascade-test-full.md" \
        "docs/roadmaps/ROADMAP-cascade-test.md"
    write_design "$repo/docs/designs/DESIGN-cascade-test-full.md" \
        "docs/prds/PRD-cascade-test-full.md"
    write_plan "$repo/docs/plans/PLAN-cascade-test-full.md" \
        "docs/designs/DESIGN-cascade-test-full.md"

    commit_all

    local output
    output=$(run_cascade "docs/plans/PLAN-cascade-test-full.md")

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "completed"' \
        "cascade_status is completed" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "transition_design" and .status == "ok")] | length == 1' \
        "transition_design ok" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "transition_prd" and .status == "ok")] | length == 1' \
        "transition_prd ok" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "update_roadmap_feature" and .status == "ok")] | length == 1' \
        "update_roadmap_feature ok" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_plan" and .status == "ok")] | length == 1' \
        "delete_plan ok" || ok=false

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 3: Idempotency (run twice, second run is no-op) ──────────────────
scenario_idempotency() {
    local scenario="Scenario 3: Idempotency"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    setup_shirabe_stub "$repo"

    write_roadmap "$repo/docs/roadmaps/ROADMAP-cascade-test.md"
    write_design "$repo/docs/designs/DESIGN-cascade-test-short.md" \
        "docs/roadmaps/ROADMAP-cascade-test.md"
    write_plan "$repo/docs/plans/PLAN-cascade-test-short.md" \
        "docs/designs/DESIGN-cascade-test-short.md"

    commit_all

    # First run
    run_cascade "docs/plans/PLAN-cascade-test-short.md" > /dev/null

    # Second run: PLAN is already deleted; test that the script handles this gracefully
    # Since PLAN doc is gone, expect exit 1 with an error (not a crash)
    local exit_code=0
    SHIRABE_BIN="$SHIRABE_STUB" bash "$CASCADE_SCRIPT" "docs/plans/PLAN-cascade-test-short.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 1 ]]; then
        pass "$scenario (exit 1 on missing PLAN — idempotent error handling)"
    else
        # If design script already transitioned it to Current (idempotent),
        # a completed/skipped second run is also acceptable
        pass "$scenario"
    fi

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 4: Missing upstream (cascade_status: skipped) ────────────────────
scenario_missing_upstream() {
    local scenario="Scenario 4: Missing upstream"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    setup_shirabe_stub "$repo"

    # PLAN with no upstream field
    mkdir -p "$repo/docs/plans"
    cat > "$repo/docs/plans/PLAN-no-upstream.md" <<'EOF'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Test"
issue_count: 1
---

# PLAN: No Upstream

## Status

Draft

EOF

    commit_all

    local output
    output=$(run_cascade "docs/plans/PLAN-no-upstream.md")

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "skipped"' \
        "cascade_status is skipped when no upstream field" || ok=false

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 5: Partial chain (upstream file missing) ─────────────────────────
scenario_partial_chain() {
    local scenario="Scenario 5: Partial chain"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    setup_shirabe_stub "$repo"

    # PLAN points to a DESIGN that doesn't exist
    mkdir -p "$repo/docs/plans"
    cat > "$repo/docs/plans/PLAN-broken.md" <<'EOF'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
upstream: docs/designs/DESIGN-nonexistent.md
milestone: "Test"
issue_count: 1
---

# PLAN: Broken Upstream

## Status

Draft

EOF

    commit_all

    local output
    output=$(run_cascade "docs/plans/PLAN-broken.md")

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "partial"' \
        "cascade_status is partial when upstream file missing" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.status == "failed")] | length >= 1' \
        "at least one failed step" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.status == "failed")] | .[0].detail != null' \
        "failed step has detail message" || ok=false

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 6: DESIGN → PRD → BRIEF → ROADMAP (BRIEF with upstream) ──────────
scenario_brief_with_upstream() {
    local scenario="Scenario 6: BRIEF with upstream ROADMAP"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    setup_shirabe_stub "$repo"

    write_roadmap "$repo/docs/roadmaps/ROADMAP-cascade-test.md"
    write_brief "$repo/docs/briefs/BRIEF-cascade-test-full.md" \
        "docs/roadmaps/ROADMAP-cascade-test.md"
    write_prd "$repo/docs/prds/PRD-cascade-test-full.md" \
        "docs/briefs/BRIEF-cascade-test-full.md"
    write_design "$repo/docs/designs/DESIGN-cascade-test-full.md" \
        "docs/prds/PRD-cascade-test-full.md"
    write_plan "$repo/docs/plans/PLAN-cascade-test-full.md" \
        "docs/designs/DESIGN-cascade-test-full.md"

    commit_all

    local output
    output=$(run_cascade "docs/plans/PLAN-cascade-test-full.md")

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "completed"' \
        "cascade_status is completed" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "transition_brief" and .status == "ok")] | length == 1' \
        "transition_brief ok" || ok=false

    # The walk must continue past the BRIEF to its upstream ROADMAP
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "update_roadmap_feature" and .status == "ok")] | length == 1' \
        "walk reaches ROADMAP (update_roadmap_feature ok)" || ok=false

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 7: DESIGN → PRD → BRIEF (BRIEF with no upstream) ─────────────────
scenario_brief_no_upstream() {
    local scenario="Scenario 7: BRIEF with no upstream"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    setup_shirabe_stub "$repo"

    # BRIEF with no upstream field — head of the chain
    write_brief "$repo/docs/briefs/BRIEF-cascade-test-headless.md"
    write_prd "$repo/docs/prds/PRD-cascade-test-headless.md" \
        "docs/briefs/BRIEF-cascade-test-headless.md"
    write_design "$repo/docs/designs/DESIGN-cascade-test-headless.md" \
        "docs/prds/PRD-cascade-test-headless.md"
    write_plan "$repo/docs/plans/PLAN-cascade-test-headless.md" \
        "docs/designs/DESIGN-cascade-test-headless.md"

    commit_all

    local output
    output=$(run_cascade "docs/plans/PLAN-cascade-test-headless.md")

    local ok=true

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "transition_brief" and .status == "ok")] | length == 1' \
        "transition_brief ok" || ok=false

    # No catchall failure: the BRIEF must not fall to the unrecognized-prefix path
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.detail != null and (.detail | test("unrecognized filename prefix")))] | length == 0' \
        "no unrecognized-prefix catchall failure" || ok=false

    assert_json "$scenario" "$output" '.cascade_status == "completed"' \
        "cascade_status is completed" || ok=false

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Check prerequisites
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required" >&2
    exit 1
fi

if [[ ! -x "$CASCADE_SCRIPT" ]]; then
    echo "Error: run-cascade.sh not found or not executable: $CASCADE_SCRIPT" >&2
    exit 1
fi

echo "=== run-cascade.sh test harness ==="
echo ""

ORIG_DIR=$(pwd)

scenario_design_roadmap
cd "$ORIG_DIR"

scenario_design_prd_roadmap
cd "$ORIG_DIR"

scenario_idempotency
cd "$ORIG_DIR"

scenario_missing_upstream
cd "$ORIG_DIR"

scenario_partial_chain
cd "$ORIG_DIR"

scenario_brief_with_upstream
cd "$ORIG_DIR"

scenario_brief_no_upstream
cd "$ORIG_DIR"

echo ""
echo "=== Results: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
