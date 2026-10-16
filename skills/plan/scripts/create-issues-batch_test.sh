#!/usr/bin/env bash
#
# create-issues-batch_test.sh - Tests for create-issues-batch.sh
#
# Exercises the per-issue needs_label merge with global --labels in dry-run mode.
# No GitHub API calls are made -- all tests use --dry-run.
#
# Usage:
#   bash create-issues-batch_test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATCH_SCRIPT="$SCRIPT_DIR/create-issues-batch.sh"
TEST_DIR=""
PASS_COUNT=0
FAIL_COUNT=0

setup() {
    TEST_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_DIR"
}

fail() {
    local test_name="$1"
    local reason="$2"
    echo "FAIL: $test_name - $reason" >&2
    ((FAIL_COUNT++)) || true
}

pass() {
    local test_name="$1"
    echo "PASS: $test_name" >&2
    ((PASS_COUNT++)) || true
}

# Write a minimal issue body file (no frontmatter)
write_body() {
    local path="$1"
    local content="${2:-Test issue body}"
    echo "$content" > "$path"
}

# ── Test: needs_label present merges with global labels ──
test_needs_label_merges_with_global() {
    local name="needs_label merges with global labels"
    setup

    write_body "$TEST_DIR/body1.md" "Issue 1 body"
    cat > "$TEST_DIR/manifest.json" <<'MANIFEST'
[
  {
    "issue_id": "1",
    "title": "feat: add X",
    "complexity": "testable",
    "file": "body1.md",
    "status": "PASS",
    "dependencies": [],
    "needs_label": "needs-design"
  }
]
MANIFEST

    local stderr_output
    stderr_output=$("$BATCH_SCRIPT" \
        --manifest "$TEST_DIR/manifest.json" \
        --labels "priority:high" \
        --dry-run 2>&1 >/dev/null) || true

    # The create-issue.sh dry-run should show merged labels
    if echo "$stderr_output" | grep -q 'Labels: priority:high,needs-design'; then
        pass "$name"
    else
        fail "$name" "Expected 'Labels: priority:high,needs-design' in output. Got: $(echo "$stderr_output" | grep 'Labels:')"
    fi

    teardown
}

# ── Test: needs_label present without global labels ──
test_needs_label_without_global() {
    local name="needs_label without global labels"
    setup

    write_body "$TEST_DIR/body1.md" "Issue 1 body"
    cat > "$TEST_DIR/manifest.json" <<'MANIFEST'
[
  {
    "issue_id": "1",
    "title": "feat: add X",
    "complexity": "simple",
    "file": "body1.md",
    "status": "PASS",
    "dependencies": [],
    "needs_label": "needs-prd"
  }
]
MANIFEST

    local stderr_output
    stderr_output=$("$BATCH_SCRIPT" \
        --manifest "$TEST_DIR/manifest.json" \
        --dry-run 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -q 'Labels: needs-prd'; then
        pass "$name"
    else
        fail "$name" "Expected 'Labels: needs-prd' in output. Got: $(echo "$stderr_output" | grep 'Labels:')"
    fi

    teardown
}

# ── Test: needs_label absent uses only global labels ──
test_no_needs_label_uses_global_only() {
    local name="no needs_label uses global labels only"
    setup

    write_body "$TEST_DIR/body1.md" "Issue 1 body"
    cat > "$TEST_DIR/manifest.json" <<'MANIFEST'
[
  {
    "issue_id": "1",
    "title": "feat: add X",
    "complexity": "simple",
    "file": "body1.md",
    "status": "PASS",
    "dependencies": []
  }
]
MANIFEST

    local stderr_output
    stderr_output=$("$BATCH_SCRIPT" \
        --manifest "$TEST_DIR/manifest.json" \
        --labels "priority:high" \
        --dry-run 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -q 'Labels: priority:high'; then
        pass "$name"
    else
        fail "$name" "Expected 'Labels: priority:high' in output. Got: $(echo "$stderr_output" | grep 'Labels:')"
    fi

    # Should NOT log a per-issue label line
    if echo "$stderr_output" | grep -q 'Per-issue label:'; then
        fail "$name (no per-issue log)" "Should not log per-issue label when needs_label is absent"
    else
        pass "$name (no per-issue log)"
    fi

    teardown
}

# ── Test: needs_label absent and no global labels ──
test_no_labels_at_all() {
    local name="no needs_label and no global labels"
    setup

    write_body "$TEST_DIR/body1.md" "Issue 1 body"
    cat > "$TEST_DIR/manifest.json" <<'MANIFEST'
[
  {
    "issue_id": "1",
    "title": "feat: add X",
    "complexity": "simple",
    "file": "body1.md",
    "status": "PASS",
    "dependencies": []
  }
]
MANIFEST

    local stderr_output
    stderr_output=$("$BATCH_SCRIPT" \
        --manifest "$TEST_DIR/manifest.json" \
        --dry-run 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -q 'Labels: <none>'; then
        pass "$name"
    else
        fail "$name" "Expected 'Labels: <none>' in output. Got: $(echo "$stderr_output" | grep 'Labels:')"
    fi

    teardown
}

# ── Test: mixed manifest (some with needs_label, some without) ──
test_mixed_manifest() {
    local name="mixed manifest with and without needs_label"
    setup

    write_body "$TEST_DIR/body1.md" "Issue 1 body"
    write_body "$TEST_DIR/body2.md" "Issue 2 body"
    write_body "$TEST_DIR/body3.md" "Issue 3 body"
    cat > "$TEST_DIR/manifest.json" <<'MANIFEST'
[
  {
    "issue_id": "1",
    "title": "feat: foundation",
    "complexity": "simple",
    "file": "body1.md",
    "status": "PASS",
    "dependencies": []
  },
  {
    "issue_id": "2",
    "title": "feat: with design label",
    "complexity": "testable",
    "file": "body2.md",
    "status": "PASS",
    "dependencies": ["1"],
    "needs_label": "needs-design"
  },
  {
    "issue_id": "3",
    "title": "feat: with prd label",
    "complexity": "simple",
    "file": "body3.md",
    "status": "PASS",
    "dependencies": ["1"],
    "needs_label": "needs-prd"
  }
]
MANIFEST

    local stderr_output
    stderr_output=$("$BATCH_SCRIPT" \
        --manifest "$TEST_DIR/manifest.json" \
        --labels "repo:tsuku" \
        --dry-run 2>&1 >/dev/null) || true

    # Issue 1: only global labels
    local issue1_labels
    issue1_labels=$(echo "$stderr_output" | grep -A5 'Creating issue 1:' | grep 'Labels:' | head -1)
    if echo "$issue1_labels" | grep -q 'Labels: repo:tsuku$'; then
        pass "$name (issue 1: global only)"
    else
        fail "$name (issue 1: global only)" "Expected 'Labels: repo:tsuku'. Got: $issue1_labels"
    fi

    # Issue 2: global + needs-design
    local issue2_labels
    issue2_labels=$(echo "$stderr_output" | grep -A5 'Creating issue 2:' | grep 'Labels:' | head -1)
    if echo "$issue2_labels" | grep -q 'Labels: repo:tsuku,needs-design'; then
        pass "$name (issue 2: merged)"
    else
        fail "$name (issue 2: merged)" "Expected 'Labels: repo:tsuku,needs-design'. Got: $issue2_labels"
    fi

    # Issue 3: global + needs-prd
    local issue3_labels
    issue3_labels=$(echo "$stderr_output" | grep -A5 'Creating issue 3:' | grep 'Labels:' | head -1)
    if echo "$issue3_labels" | grep -q 'Labels: repo:tsuku,needs-prd'; then
        pass "$name (issue 3: merged)"
    else
        fail "$name (issue 3: merged)" "Expected 'Labels: repo:tsuku,needs-prd'. Got: $issue3_labels"
    fi

    teardown
}

# ── Test: dry-run output includes per-issue label log line ──
test_dryrun_logs_per_issue_label() {
    local name="dry-run logs per-issue label"
    setup

    write_body "$TEST_DIR/body1.md" "Issue 1 body"
    cat > "$TEST_DIR/manifest.json" <<'MANIFEST'
[
  {
    "issue_id": "1",
    "title": "feat: add X",
    "complexity": "simple",
    "file": "body1.md",
    "status": "PASS",
    "dependencies": [],
    "needs_label": "needs-spike"
  }
]
MANIFEST

    local stderr_output
    stderr_output=$("$BATCH_SCRIPT" \
        --manifest "$TEST_DIR/manifest.json" \
        --dry-run 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -q 'Per-issue label: needs-spike'; then
        pass "$name"
    else
        fail "$name" "Expected 'Per-issue label: needs-spike' in batch output"
    fi

    teardown
}

# ── Test: help text mentions needs_label ──
test_help_mentions_needs_label() {
    local name="help text documents needs_label"

    local stderr_output
    stderr_output=$("$BATCH_SCRIPT" --help 2>&1 || true)

    if echo "$stderr_output" | grep -q 'needs_label'; then
        pass "$name"
    else
        fail "$name" "Help text does not mention needs_label"
    fi
}

# ── Test: milestone creation uses gh api (no cross-plugin dependency) ──
# Validates that milestone handling uses self-contained gh api calls.
# A mock gh binary captures invocations; the test verifies the correct
# API endpoint is called without referencing any sibling plugin script.
test_milestone_uses_gh_api_directly() {
    local name="milestone path uses gh api directly"
    setup

    # Create a mock gh that records calls and simulates responses
    local mock_dir
    mock_dir=$(mktemp -d)
    local mock_log="$mock_dir/gh.log"
    cat > "$mock_dir/gh" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG}"
case "$*" in
    *repo\ view*)
        echo 'owner/repo'
        ;;
    *milestones*GET*)
        # Simulate: no existing milestone
        echo '[]'
        ;;
    *milestones*POST*)
        # Simulate: milestone created
        echo '{"number":1,"title":"M1"}'
        ;;
    *issue\ create*)
        echo "https://github.com/owner/repo/issues/42"
        ;;
    *)
        echo '{}'
        ;;
esac
MOCK
    chmod +x "$mock_dir/gh"

    write_body "$TEST_DIR/body1.md" "Issue body"
    cat > "$TEST_DIR/manifest.json" <<'MANIFEST'
[
  {
    "issue_id": "1",
    "title": "feat: add X",
    "complexity": "simple",
    "file": "body1.md",
    "status": "PASS",
    "dependencies": []
  }
]
MANIFEST

    local stderr_output
    stderr_output=$(env MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" \
        "$BATCH_SCRIPT" \
            --manifest "$TEST_DIR/manifest.json" \
            --milestone "M1" \
            2>&1) || true

    # Verify gh api was called for milestone operations (not manage-milestone.sh)
    if grep -q 'api repos/owner/repo/milestones' "$mock_log" 2>/dev/null; then
        pass "$name (gh api called for milestones)"
    else
        fail "$name (gh api called for milestones)" "Expected 'api repos/owner/repo/milestones' in gh calls. Got: $(cat "$mock_log" 2>/dev/null)"
    fi

    # Verify no reference to manage-milestone.sh in the script
    if grep -q 'manage-milestone.sh' "$BATCH_SCRIPT"; then
        fail "$name (no manage-milestone.sh reference)" "Script still references manage-milestone.sh"
    else
        pass "$name (no manage-milestone.sh reference)"
    fi

    rm -rf "$mock_dir"
    teardown
}

# ── Run all tests ──
echo "Running create-issues-batch.sh tests..." >&2
echo "" >&2

test_needs_label_merges_with_global
test_needs_label_without_global
test_no_needs_label_uses_global_only
test_no_labels_at_all
test_mixed_manifest
test_dryrun_logs_per_issue_label
test_help_mentions_needs_label
test_milestone_uses_gh_api_directly

echo "" >&2
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed" >&2

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
