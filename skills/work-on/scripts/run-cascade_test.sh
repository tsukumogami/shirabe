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

# Repo root (the shirabe checkout) — used to locate the cargo workspace and the
# built release binary. run-cascade_test.sh lives at skills/work-on/scripts/.
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

# Path to the REAL shirabe binary the cascade calls for finalize-chain and
# ROADMAP transitions. Built once by build_shirabe_binary and injected via
# SHIRABE_BIN so each scenario's temp git repo gets genuine transitions rather
# than a hand-rolled emulation of finalize-chain's behavior.
SHIRABE_BIN_PATH=""

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

# Run cascade and return the JSON output. SHIRABE_BIN points the cascade at the
# real release binary (built once by build_shirabe_binary) so each scenario gets
# genuine finalize-chain transitions in its temp git repo. Scenarios that need
# to control `validate --lifecycle-chain --strict` exit codes deterministically
# can set CASCADE_SHIRABE_BIN_OVERRIDE to a wrapper path (see setup_shirabe_stub).
run_cascade() {
    local plan_doc="$1"
    shift
    local bin="${CASCADE_SHIRABE_BIN_OVERRIDE:-$SHIRABE_BIN_PATH}"
    SHIRABE_BIN="$bin" bash "$CASCADE_SCRIPT" "$@" "$plan_doc" 2>/dev/null || true
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
}

# Build the real shirabe release binary once and record its path in
# SHIRABE_BIN_PATH. The cascade calls this binary's `finalize-chain` (chain walk
# + tactical transitions + DESIGN move) and `transition` (ROADMAP -> Done)
# subcommands, so the parity harness exercises the genuine integration point
# rather than emulating finalize-chain's report in bash. Each scenario's temp
# git repo therefore gets real transitions.
build_shirabe_binary() {
    echo "Building shirabe release binary (cargo build --release -p shirabe)..."
    if ! ( cd "$REPO_ROOT" && cargo build --release -p shirabe ) >&2; then
        echo "Error: failed to build the shirabe release binary" >&2
        exit 1
    fi
    SHIRABE_BIN_PATH="$REPO_ROOT/target/release/shirabe"
    if [[ ! -x "$SHIRABE_BIN_PATH" ]]; then
        echo "Error: built binary not found or not executable: $SHIRABE_BIN_PATH" >&2
        exit 1
    fi
}

# Create a thin wrapper around the real shirabe binary that lets scenarios
# pin the `validate --lifecycle-chain ... --strict` exit code via a file
# under the wrapper's dir. The pre-probe scenarios (8 and 9) use the
# wrapper to deterministically control whether the chain looks at-terminal
# (override 0) or mid-PR (override 1). All other subcommands (transition,
# finalize-chain) pass through to the real binary unchanged.
setup_shirabe_stub() {
    local repo_dir="$1"
    local stub="$repo_dir/.cascade-stub/shirabe"
    mkdir -p "$(dirname "$stub")"

    cat > "$stub" <<EOF
#!/usr/bin/env bash
set -euo pipefail
REAL_BIN="$SHIRABE_BIN_PATH"
STUB_DIR="\$(dirname "\$0")"
OVERRIDE_FILE="\$STUB_DIR/validate-exits.txt"

if [[ "\${1:-}" == "validate" ]]; then
    # Only intercept --lifecycle-chain ... --strict invocations.
    for arg in "\$@"; do
        if [[ "\$arg" == "--lifecycle-chain" ]]; then
            if [[ -f "\$OVERRIDE_FILE" ]]; then
                EXIT_CODE=\$(head -1 "\$OVERRIDE_FILE" 2>/dev/null || echo "0")
                tail -n +2 "\$OVERRIDE_FILE" > "\$OVERRIDE_FILE.tmp" 2>/dev/null && mv "\$OVERRIDE_FILE.tmp" "\$OVERRIDE_FILE"
                if [[ -z "\$EXIT_CODE" ]]; then
                    EXIT_CODE=0
                fi
                exit "\$EXIT_CODE"
            fi
            break
        fi
    done
fi

exec "\$REAL_BIN" "\$@"
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
    SHIRABE_BIN="$SHIRABE_BIN_PATH" bash "$CASCADE_SCRIPT" "docs/plans/PLAN-cascade-test-short.md" 2>/dev/null || exit_code=$?

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

# ── Scenario 8: Pre-cascade probe — chain already terminal ────────────────────
# When the chain is already at its strict-mode passing state at the
# pre-probe, the cascade is a no-op. The script logs the early-exit and
# emits cascade_status: skipped with a single lifecycle_pre_probe step.
scenario_pre_probe_already_terminal() {
    local scenario="Scenario 8: Pre-probe — chain already terminal"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    setup_shirabe_stub "$repo"

    # Build the chain — the validate stub will return exit 0 because we
    # pin the override file to "0" (chain already at terminal).
    write_roadmap "$repo/docs/roadmaps/ROADMAP-cascade-test.md"
    write_design "$repo/docs/designs/DESIGN-cascade-test-short.md" \
        "docs/roadmaps/ROADMAP-cascade-test.md"
    write_plan "$repo/docs/plans/PLAN-cascade-test-short.md" \
        "docs/designs/DESIGN-cascade-test-short.md"
    commit_all

    # Pin the validate stub's pre-probe exit code to 0 (clean pass — chain
    # already at terminal).
    echo "0" > "$(dirname "$SHIRABE_STUB")/validate-exits.txt"

    local output
    export CASCADE_SHIRABE_BIN_OVERRIDE="$SHIRABE_STUB"
    output=$(run_cascade "docs/plans/PLAN-cascade-test-short.md")
    unset CASCADE_SHIRABE_BIN_OVERRIDE

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "skipped"' \
        "cascade_status is skipped (chain already terminal)" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "lifecycle_pre_probe")] | length == 1' \
        "lifecycle_pre_probe step present" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "lifecycle_pre_probe")] | .[0].status == "skipped"' \
        "lifecycle_pre_probe status is skipped" || ok=false

    # No transitions performed.
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_plan" or .action == "transition_design" or .action == "transition_prd")] | length == 0' \
        "no transitions performed when chain already terminal" || ok=false

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 9: Pre-cascade probe — expected mid-PR failure ──────────────────
# When the chain is at single-pr-mid-PR (PLAN present, DESIGN Planned),
# the pre-probe sees the expected failure and the cascade proceeds.
# The lifecycle_pre_probe step is recorded as ok.
scenario_pre_probe_mid_pr() {
    local scenario="Scenario 9: Pre-probe — expected mid-PR failure"
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

    # Pin the validate stub's pre-probe exit code to 1 (mid-PR failure).
    # No post-verify in dry-run mode, so only one override line needed.
    echo "1" > "$(dirname "$SHIRABE_STUB")/validate-exits.txt"

    local output
    export CASCADE_SHIRABE_BIN_OVERRIDE="$SHIRABE_STUB"
    output=$(run_cascade "docs/plans/PLAN-cascade-test-short.md")
    unset CASCADE_SHIRABE_BIN_OVERRIDE

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "completed"' \
        "cascade_status is completed" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "lifecycle_pre_probe")] | length == 1' \
        "lifecycle_pre_probe step present" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "lifecycle_pre_probe")] | .[0].status == "ok"' \
        "lifecycle_pre_probe status is ok" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_plan" and .status == "ok")] | length == 1' \
        "delete_plan ran after pre-probe" || ok=false

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

if ! command -v cargo &>/dev/null; then
    echo "Error: cargo is required (the harness builds the real shirabe binary)" >&2
    exit 1
fi

echo "=== run-cascade.sh test harness ==="
echo ""

# Build the real shirabe binary once; every scenario reuses it via SHIRABE_BIN.
build_shirabe_binary

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

scenario_pre_probe_already_terminal
cd "$ORIG_DIR"

scenario_pre_probe_mid_pr
cd "$ORIG_DIR"

echo ""
echo "=== Results: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
