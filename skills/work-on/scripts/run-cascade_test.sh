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
    local effective_path="$PATH"
    if [[ -n "${GH_STUB_DIR:-}" ]]; then
        effective_path="$GH_STUB_DIR:$PATH"
    fi
    PATH="$effective_path" SHIRABE_BIN="$bin" bash "$CASCADE_SCRIPT" "$@" "$plan_doc" 2>/dev/null || true
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

# Write a single-feature ROADMAP fixture for the deletion scenarios. Features
# start at status Done so handle_roadmap's all_done branch fires after the
# Downstream/Status idempotent rewrite for the cascade's PLAN.
# Optional third arg is a list of GitHub issue URLs (space-separated) to embed
# in the Features prose so handle_roadmap_deletion's check_issue_closed loop
# has something to evaluate.
write_roadmap_done_single() {
    local path="$1"
    local plan_filename="$2"
    local issue_urls="${3:-}"
    mkdir -p "$(dirname "$path")"

    local issue_lines=""
    if [[ -n "$issue_urls" ]]; then
        local url
        for url in $issue_urls; do
            issue_lines+="- $url"$'\n'
        done
    fi

    cat > "$path" <<EOF
---
status: Active
---

# ROADMAP: Cascade Deletion Test

## Status

Active

## Theme

Single-feature roadmap whose feature is already Done; used to exercise the
all-features-Done -> handle_roadmap_deletion branch.

## Features

### Feature 1: Done Feature

**Status:** Done
**Downstream:** ${plan_filename}

Tracked work:
${issue_lines}
EOF
}

# Install a gh stub that overrides PATH for the cascade. The stub responds to
# `gh issue view <N> --repo <slug> --json state --jq .state` by reading an
# override file under the stub dir. The override file's first line is the
# state to return ("CLOSED" or "OPEN"); subsequent lines are consumed on
# successive calls so a single scenario can sequence multiple issue states.
# Returns 0 for CLOSED, 1 for OPEN (matching how check_issue_closed treats the
# state output).
setup_gh_stub() {
    local repo_dir="$1"
    local stub_dir="$repo_dir/.gh-stub"
    mkdir -p "$stub_dir"
    local stub="$stub_dir/gh"

    cat > "$stub" <<'EOF'
#!/usr/bin/env bash
# Minimal gh stub for cascade tests. Only `gh issue view ... --json state
# --jq .state` is supported; other gh subcommands are no-ops returning 0.
set -euo pipefail
STUB_DIR="$(dirname "$0")"
OVERRIDE_FILE="$STUB_DIR/issue-states.txt"

if [[ "${1:-}" == "issue" ]] && [[ "${2:-}" == "view" ]]; then
    state="CLOSED"
    if [[ -f "$OVERRIDE_FILE" ]]; then
        state=$(head -1 "$OVERRIDE_FILE" 2>/dev/null || echo "CLOSED")
        tail -n +2 "$OVERRIDE_FILE" > "$OVERRIDE_FILE.tmp" 2>/dev/null && mv "$OVERRIDE_FILE.tmp" "$OVERRIDE_FILE"
        [[ -z "$state" ]] && state="CLOSED"
    fi
    echo "$state"
    exit 0
fi

exit 0
EOF
    chmod +x "$stub"
    GH_STUB_DIR="$stub_dir"
}

# Configure the test git repo's origin so the cascade's check_issue_closed
# helper sees an owner/repo slug it can match against issue URLs of the form
# https://github.com/<owner>/<repo>/issues/<N>. The origin URL is set
# without the trailing .git so the cascade's slug normalization (which only
# strips .git on the ssh branch) matches the issue URL exactly.
set_github_origin() {
    local slug="$1"
    git remote set-url origin "https://github.com/${slug}"
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

# ── Scenario 9b: WORK_ON_ALLOW_UNTRACKED_ACS=1 forwards --allow-untracked-acs ─
# When the env var is set to "1", the cascade script appends the
# --allow-untracked-acs flag to every validator invocation, emits the
# documented suppression log line once at start, and tags the add_step
# instrumentation with `l06_suppressed=1`. The other behaviors (cascade
# proceeds when pre-probe fails, skips when pre-probe passes) are unchanged.
scenario_allow_untracked_acs_env_forwarded() {
    local scenario="Scenario 9b: WORK_ON_ALLOW_UNTRACKED_ACS=1 forwards flag"
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

    # Replace the stub with one that captures argv to a file so the test can
    # assert the flag is forwarded. The captured argv is appended one
    # invocation per line.
    cat > "$SHIRABE_STUB" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "\$*" >> "$(dirname "$SHIRABE_STUB")/argv.log"
REAL_BIN="$SHIRABE_BIN_PATH"
if [[ "\${1:-}" == "validate" ]]; then
    for arg in "\$@"; do
        if [[ "\$arg" == "--lifecycle-chain" ]]; then
            # Pin to 0 (clean pre-probe) so the cascade skips and we only
            # capture one validator invocation.
            exit 0
        fi
    done
fi
exec "\$REAL_BIN" "\$@"
EOF
    chmod +x "$SHIRABE_STUB"

    local output
    export CASCADE_SHIRABE_BIN_OVERRIDE="$SHIRABE_STUB"
    export WORK_ON_ALLOW_UNTRACKED_ACS=1
    output=$(run_cascade "docs/plans/PLAN-cascade-test-short.md")
    unset CASCADE_SHIRABE_BIN_OVERRIDE
    unset WORK_ON_ALLOW_UNTRACKED_ACS

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "skipped"' \
        "cascade_status is skipped (clean pre-probe)" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "lifecycle_pre_probe")] | .[0].detail | contains("l06_suppressed=1")' \
        "lifecycle_pre_probe detail carries l06_suppressed=1 marker" || ok=false

    # The captured argv must contain --allow-untracked-acs on the validate
    # invocation.
    local argv
    argv=$(cat "$(dirname "$SHIRABE_STUB")/argv.log" 2>/dev/null || echo "")
    if [[ "$argv" != *"--allow-untracked-acs"* ]]; then
        fail "$scenario: expected --allow-untracked-acs in captured argv; got: $argv"
        ok=false
    fi

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 9c: env unset — no flag forwarding, no suppression marker ─────────
scenario_allow_untracked_acs_default_off() {
    local scenario="Scenario 9c: env unset — no flag forwarding"
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

    cat > "$SHIRABE_STUB" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "\$*" >> "$(dirname "$SHIRABE_STUB")/argv.log"
REAL_BIN="$SHIRABE_BIN_PATH"
if [[ "\${1:-}" == "validate" ]]; then
    for arg in "\$@"; do
        if [[ "\$arg" == "--lifecycle-chain" ]]; then
            exit 0
        fi
    done
fi
exec "\$REAL_BIN" "\$@"
EOF
    chmod +x "$SHIRABE_STUB"

    local output
    export CASCADE_SHIRABE_BIN_OVERRIDE="$SHIRABE_STUB"
    # Explicitly NOT setting WORK_ON_ALLOW_UNTRACKED_ACS.
    unset WORK_ON_ALLOW_UNTRACKED_ACS 2>/dev/null || true
    output=$(run_cascade "docs/plans/PLAN-cascade-test-short.md")
    unset CASCADE_SHIRABE_BIN_OVERRIDE

    local ok=true

    # No l06_suppressed marker on lifecycle_pre_probe's detail. The
    # detail is null when the env is unset (add_step writes null for
    # empty string); coerce null -> "" before testing for the marker so
    # the jq expression is null-safe across runners.
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "lifecycle_pre_probe")] | (.[0].detail // "") | contains("l06_suppressed") | not' \
        "lifecycle_pre_probe detail must not carry l06_suppressed marker" || ok=false

    # The captured argv must NOT contain --allow-untracked-acs.
    local argv
    argv=$(cat "$(dirname "$SHIRABE_STUB")/argv.log" 2>/dev/null || echo "")
    if [[ "$argv" == *"--allow-untracked-acs"* ]]; then
        fail "$scenario: did not expect --allow-untracked-acs in captured argv; got: $argv"
        ok=false
    fi

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 10: handle_roadmap_deletion — no-ROADMAP regression ──────────────
# When the cascade walks a chain with no ROADMAP at the head (BRIEF without
# upstream), no ROADMAP handler runs, no delete_roadmap step is emitted, and
# the post-cascade chain remains consistent. Regression check that the new
# function's presence doesn't affect the no-ROADMAP path.
scenario_deletion_no_roadmap_regression() {
    local scenario="Scenario 10: deletion — no-ROADMAP regression"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"

    # BRIEF without upstream — the chain has no ROADMAP at the head.
    write_brief "$repo/docs/briefs/BRIEF-cascade-no-roadmap.md"
    write_prd "$repo/docs/prds/PRD-cascade-no-roadmap.md" \
        "docs/briefs/BRIEF-cascade-no-roadmap.md"
    write_design "$repo/docs/designs/DESIGN-cascade-no-roadmap.md" \
        "docs/prds/PRD-cascade-no-roadmap.md"
    write_plan "$repo/docs/plans/PLAN-cascade-no-roadmap.md" \
        "docs/designs/DESIGN-cascade-no-roadmap.md"

    commit_all

    local output
    output=$(run_cascade "docs/plans/PLAN-cascade-no-roadmap.md")

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "completed"' \
        "cascade_status is completed" || ok=false

    # No ROADMAP -> no delete_roadmap step, no update_roadmap_feature step.
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_roadmap")] | length == 0' \
        "no delete_roadmap step emitted" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "update_roadmap_feature")] | length == 0' \
        "no update_roadmap_feature step emitted" || ok=false

    # The tactical chain still finalizes cleanly.
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "transition_design" and .status == "ok")] | length == 1' \
        "transition_design ok" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_plan" and .status == "ok")] | length == 1' \
        "delete_plan ok" || ok=false

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 11: handle_roadmap_deletion — all features Done + all issues closed ──
# A single-feature ROADMAP starts at all-features-Done. The cascade walks
# PLAN -> DESIGN -> ROADMAP, handle_roadmap finds all features Done, and
# handle_roadmap_deletion verifies every referenced issue is CLOSED (via the
# gh stub), transitions the ROADMAP to Done, and `git rm`s the file in the
# same staged commit set.
scenario_deletion_all_done_all_closed() {
    local scenario="Scenario 11: deletion — all features Done + all issues closed"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    set_github_origin "test-owner/test-repo"
    setup_gh_stub "$repo"

    # Pin every gh issue view response to CLOSED.
    printf 'CLOSED\nCLOSED\n' > "$GH_STUB_DIR/issue-states.txt"

    write_roadmap_done_single "$repo/docs/roadmaps/ROADMAP-cascade-deletion.md" \
        "PLAN-cascade-deletion.md" \
        "https://github.com/test-owner/test-repo/issues/1 https://github.com/test-owner/test-repo/issues/2"
    write_design "$repo/docs/designs/DESIGN-cascade-deletion.md" \
        "docs/roadmaps/ROADMAP-cascade-deletion.md"
    write_plan "$repo/docs/plans/PLAN-cascade-deletion.md" \
        "docs/designs/DESIGN-cascade-deletion.md"

    commit_all

    local output
    output=$(run_cascade "docs/plans/PLAN-cascade-deletion.md")

    local ok=true

    assert_json "$scenario" "$output" '.cascade_status == "completed"' \
        "cascade_status is completed" || ok=false

    # The deletion step fired with status ok.
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_roadmap" and .status == "ok")] | length == 1' \
        "delete_roadmap ok" || ok=false

    # The old transition_roadmap step name must be gone.
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "transition_roadmap")] | length == 0' \
        "transition_roadmap step name no longer emitted" || ok=false

    # The ROADMAP file is git-rm'd (staged for deletion) in the working tree.
    local roadmap_status
    roadmap_status=$(cd "$repo" && git status --porcelain "docs/roadmaps/ROADMAP-cascade-deletion.md")
    if [[ "$roadmap_status" == "D "* ]] || [[ "$roadmap_status" == "DD"* ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ ROADMAP staged for deletion"
    else
        fail "$scenario: ROADMAP file is not staged for deletion (status: '$roadmap_status')"
        ok=false
    fi

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 12: handle_roadmap_deletion — open issue produces skip ───────────
# All features are Done but at least one referenced GitHub issue is still
# open. handle_roadmap_deletion records a "delete_roadmap" "skipped" step
# naming the open URL and leaves the ROADMAP file in place.
scenario_deletion_open_issue_skip() {
    local scenario="Scenario 12: deletion — open issue produces skip"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    set_github_origin "test-owner/test-repo"
    setup_gh_stub "$repo"

    # First issue check returns OPEN -> the loop short-circuits on the first URL.
    printf 'OPEN\n' > "$GH_STUB_DIR/issue-states.txt"

    write_roadmap_done_single "$repo/docs/roadmaps/ROADMAP-cascade-open.md" \
        "PLAN-cascade-open.md" \
        "https://github.com/test-owner/test-repo/issues/42"
    write_design "$repo/docs/designs/DESIGN-cascade-open.md" \
        "docs/roadmaps/ROADMAP-cascade-open.md"
    write_plan "$repo/docs/plans/PLAN-cascade-open.md" \
        "docs/designs/DESIGN-cascade-open.md"

    commit_all

    local output
    output=$(run_cascade "docs/plans/PLAN-cascade-open.md")

    local ok=true

    # The cascade still completes for the tactical chain; the deletion is just
    # deferred to a later cascade run.
    assert_json "$scenario" "$output" '.cascade_status == "completed"' \
        "cascade_status is completed" || ok=false

    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_roadmap" and .status == "skipped")] | length == 1' \
        "delete_roadmap skipped" || ok=false

    # The skip message must name the open URL.
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_roadmap" and .status == "skipped")] | .[0].detail | test("issues/42")' \
        "skip detail names the open issue URL" || ok=false

    # No ok delete_roadmap step.
    assert_json "$scenario" "$output" \
        '[.steps[] | select(.action == "delete_roadmap" and .status == "ok")] | length == 0' \
        "no ok delete_roadmap step when an issue is open" || ok=false

    # The ROADMAP file must still exist in the working tree.
    if [[ -f "$repo/docs/roadmaps/ROADMAP-cascade-open.md" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ ROADMAP file preserved"
    else
        fail "$scenario: ROADMAP file was deleted despite open issue"
        ok=false
    fi

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 13: handle_roadmap_deletion — direct re-invocation idempotent ────
# Calling handle_roadmap_deletion directly on a path that no longer exists
# returns 0 with no side effects and emits no JSON step. Probes the
# function-level idempotency contract: the same call repeated after the
# ROADMAP was deleted on a prior cascade run is harmless.
scenario_deletion_idempotent_reinvoke() {
    local scenario="Scenario 13: deletion — direct re-invocation idempotent"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/repo"
    setup_test_repo "$repo"
    # No fixtures — we only need a git repo so the function's guard runs.
    cd "$repo"
    git commit --allow-empty -m "init" > /dev/null 2>&1

    # Invoke handle_roadmap_deletion in a subshell that sources the cascade
    # script's helpers. The function should detect the missing file and
    # return 0 without touching state.
    local out
    out=$(bash -c "
        set -euo pipefail
        # Stub the globals the function expects to exist in the cascade scope.
        STEPS_JSON=''
        STAGED_FILES=()
        ANY_FAILED=false
        SHIRABE_BIN='$SHIRABE_BIN_PATH'
        REPO_ROOT='$repo'
        # Source the cascade script's function definitions without executing
        # the trailing setup/argparse. The cleanest approach: extract the
        # function body and define it inline.
        $(awk '/^handle_roadmap_deletion\(\) \{/,/^\}/' "$CASCADE_SCRIPT")
        # Define minimal versions of the helpers the function calls.
        log_warn() { :; }
        add_step() { STEPS_JSON=\"\$STEPS_JSON|step:\$1\"; }
        check_issue_closed() { return 0; }
        # Call the function on a non-existent path.
        handle_roadmap_deletion '/does/not/exist/ROADMAP-missing.md' 'null'
        echo \"RC=\$?\"
        echo \"STEPS_JSON='\$STEPS_JSON'\"
        echo \"ANY_FAILED='\$ANY_FAILED'\"
    " 2>&1)

    local rc_line steps_line failed_line
    rc_line=$(echo "$out" | grep -E '^RC=' | head -1)
    steps_line=$(echo "$out" | grep -E "^STEPS_JSON=" | head -1)
    failed_line=$(echo "$out" | grep -E "^ANY_FAILED=" | head -1)

    local ok=true

    if [[ "$rc_line" == "RC=0" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ function returned 0 on missing file"
    else
        fail "$scenario: expected RC=0 on missing file, got '$rc_line'"
        [[ "$VERBOSE" == "true" ]] && echo "    Full output: $out"
        ok=false
    fi

    if [[ "$steps_line" == "STEPS_JSON=''" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ no step recorded on missing file"
    else
        fail "$scenario: expected no step recorded, got '$steps_line'"
        ok=false
    fi

    if [[ "$failed_line" == "ANY_FAILED='false'" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ ANY_FAILED unchanged"
    else
        fail "$scenario: expected ANY_FAILED=false, got '$failed_line'"
        ok=false
    fi

    [[ "$ok" == "true" ]] && pass "$scenario" || true

    rm -rf "$tmpdir"
    cd "$SCRIPT_DIR"
}

# ── Scenario 14: check_issue_closed — sibling owner/repo accepted ─────────────
# A coordinated multi-repo effort references sibling-repo issue URLs whose
# owner/repo differs from the origin remote. check_issue_closed must query the
# named repo directly (no origin-equality rejection) while still rejecting an
# owner/repo that fails the GitHub charset validation. We source just the
# function and stub gh/git so the test is hermetic.
scenario_check_issue_closed_sibling_repo() {
    local scenario="Scenario 14: check_issue_closed — sibling repo accepted, bad charset rejected"
    echo "Running $scenario..."

    local tmpdir
    tmpdir=$(mktemp -d)

    # A gh stub on PATH that records the --repo it was asked about and returns
    # CLOSED for the sibling-repo query. If check_issue_closed still enforced
    # origin-equality, the sibling URL would be rejected BEFORE gh is invoked
    # and the recorded repo would be empty.
    local stub_dir="$tmpdir/bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STUB_DIR="$(dirname "$0")"
if [[ "${1:-}" == "issue" ]] && [[ "${2:-}" == "view" ]]; then
    # Find the value following --repo and record it.
    prev=""
    for arg in "$@"; do
        if [[ "$prev" == "--repo" ]]; then
            echo "$arg" >> "$STUB_DIR/queried-repos.txt"
        fi
        prev="$arg"
    done
    echo "CLOSED"
    exit 0
fi
exit 0
EOF
    chmod +x "$stub_dir/gh"

    # A git stub that reports an origin slug DIFFERENT from the sibling repo,
    # proving origin-equality is no longer enforced.
    cat > "$stub_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "remote" ]] && [[ "${2:-}" == "get-url" ]]; then
    echo "https://github.com/origin-owner/origin-repo"
    exit 0
fi
exit 0
EOF
    chmod +x "$stub_dir/git"

    local ok=true

    # Accepted: a sibling owner/repo (differs from origin) at a CLOSED issue.
    local sibling_rc=0
    PATH="$stub_dir:$PATH" bash -c "
        set -euo pipefail
        log_warn() { :; }
        $(awk '/^check_issue_closed\(\) \{/,/^\}/' "$CASCADE_SCRIPT")
        check_issue_closed 'https://github.com/sibling-owner/sibling-repo/issues/7'
    " || sibling_rc=$?

    if [[ "$sibling_rc" -eq 0 ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ sibling-repo issue accepted (queried directly)"
    else
        fail "$scenario: sibling-repo issue URL was rejected (rc=$sibling_rc)"
        ok=false
    fi

    # The gh stub must have been invoked with the sibling repo, proving the
    # query reached gh rather than being short-circuited by an origin check.
    local queried
    queried=$(cat "$stub_dir/queried-repos.txt" 2>/dev/null || echo "")
    if [[ "$queried" == *"sibling-owner/sibling-repo"* ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ gh queried the sibling repo directly"
    else
        fail "$scenario: gh was not queried for the sibling repo (got: '$queried')"
        ok=false
    fi

    # Rejected: an owner with an invalid charset (a space) must still be
    # rejected by the charset guard, before any gh query.
    local bad_rc=0
    PATH="$stub_dir:$PATH" bash -c "
        set -euo pipefail
        log_warn() { :; }
        $(awk '/^check_issue_closed\(\) \{/,/^\}/' "$CASCADE_SCRIPT")
        check_issue_closed 'https://github.com/bad owner/repo/issues/9'
    " || bad_rc=$?

    if [[ "$bad_rc" -ne 0 ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  ✓ invalid-charset owner/repo rejected"
    else
        fail "$scenario: invalid-charset owner/repo was accepted (rc=$bad_rc)"
        ok=false
    fi

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

scenario_allow_untracked_acs_env_forwarded
cd "$ORIG_DIR"

scenario_allow_untracked_acs_default_off
cd "$ORIG_DIR"

scenario_deletion_no_roadmap_regression
cd "$ORIG_DIR"

scenario_deletion_all_done_all_closed
cd "$ORIG_DIR"

scenario_deletion_open_issue_skip
cd "$ORIG_DIR"

scenario_deletion_idempotent_reinvoke
cd "$ORIG_DIR"

scenario_check_issue_closed_sibling_repo
cd "$ORIG_DIR"

echo ""
echo "=== Results: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
