#!/usr/bin/env bash
#
# plan-to-tasks_test.sh - Tests for plan-to-tasks.sh
#
# Exercises multi-pr parsing, single-pr parsing, and diamond dependency graphs.
#
# Usage:
#   bash plan-to-tasks_test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER_SCRIPT="$SCRIPT_DIR/plan-to-tasks.sh"
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

# ── Fixture A: multi-pr mode ──
# Two issues: #10 has no deps, #11 depends on #10.
test_multi_pr_basic() {
    local name="multi-pr basic dependency"
    setup

    cat > "$TEST_DIR/plan-multi.md" <<'FIXTURE'
---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "Test Milestone"
issue_count: 2
---

# PLAN: test

## Status

Active

## Scope Summary

Test plan for multi-pr mode parsing.

## Decomposition Strategy

Horizontal.

## Issue Outlines

_(omitted in multi-pr mode)_

## Implementation Issues

| Issue | Title | Complexity | Dependencies |
|-------|-------|------------|--------------|
| #10 | feat: add foundation | testable | None |
| #11 | feat: add extension | simple | #10 |

## Dependency Graph

```mermaid
graph LR
    I10["#10: add foundation"]
    I11["#11: add extension"]
    I10 --> I11
```

## Implementation Sequence

Critical path: Issue 10 -> Issue 11.
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan-multi.md" 2>/dev/null)

    # Assert: valid JSON array with 2 elements
    local count
    count=$(echo "$output" | jq 'length' 2>/dev/null) || true
    if [[ "$count" != "2" ]]; then
        fail "$name" "expected 2 elements, got: $count (output: $output)"
        teardown
        return
    fi
    pass "$name (array length)"

    # Assert: issue-10 has no waits_on
    local waits_10
    waits_10=$(echo "$output" | jq -r '.[] | select(.name == "issue-10") | .waits_on | length' 2>/dev/null) || true
    if [[ "$waits_10" != "0" ]]; then
        fail "$name" "issue-10 should have empty waits_on, got length: $waits_10"
    else
        pass "$name (issue-10 waits_on empty)"
    fi

    # Assert: issue-11 has waits_on: ["issue-10"]
    local waits_11
    waits_11=$(echo "$output" | jq -r '.[] | select(.name == "issue-11") | .waits_on[0]' 2>/dev/null) || true
    if [[ "$waits_11" != "issue-10" ]]; then
        fail "$name" "issue-11 should wait on issue-10, got: $waits_11"
    else
        pass "$name (issue-11 waits_on issue-10)"
    fi

    # Assert: ISSUE_SOURCE is github
    local issue_source
    issue_source=$(echo "$output" | jq -r '.[] | select(.name == "issue-10") | .vars.ISSUE_SOURCE' 2>/dev/null) || true
    if [[ "$issue_source" != "github" ]]; then
        fail "$name" "expected ISSUE_SOURCE=github, got: $issue_source"
    else
        pass "$name (ISSUE_SOURCE=github)"
    fi

    # Assert: ISSUE_NUMBER correct
    local issue_number
    issue_number=$(echo "$output" | jq -r '.[] | select(.name == "issue-10") | .vars.ISSUE_NUMBER' 2>/dev/null) || true
    if [[ "$issue_number" != "10" ]]; then
        fail "$name" "expected ISSUE_NUMBER=10, got: $issue_number"
    else
        pass "$name (ISSUE_NUMBER=10)"
    fi

    teardown
}

# ── Fixture B: single-pr mode ──
# Two issues: Issue 1 has no deps, Issue 2 blocked by Issue 1.
test_single_pr_basic() {
    local name="single-pr basic dependency"
    setup

    cat > "$TEST_DIR/plan-single.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Test Milestone"
issue_count: 2
---

# PLAN: test

## Status

Draft

## Scope Summary

Test plan for single-pr mode parsing.

## Decomposition Strategy

Horizontal.

## Issue Outlines

### Issue 1: feat: add core parser

**Complexity**: testable

**Goal**: Implement the core parser module.

**Acceptance Criteria**:
- [ ] Parser exists

**Dependencies**: None.

---

### Issue 2: feat: add validator

**Complexity**: simple

**Goal**: Add validation on top of the parser.

**Acceptance Criteria**:
- [ ] Validator exists

**Dependencies**: Blocked by Issue 1.

## Dependency Graph

```mermaid
graph LR
    I1["#1: add core parser"]
    I2["#2: add validator"]
    I1 --> I2
```

## Implementation Sequence

Critical path: Issue 1 -> Issue 2.
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan-single.md" 2>/dev/null)

    # Assert: valid JSON array with 2 elements
    local count
    count=$(echo "$output" | jq 'length' 2>/dev/null) || true
    if [[ "$count" != "2" ]]; then
        fail "$name" "expected 2 elements, got: $count (output: $output)"
        teardown
        return
    fi
    pass "$name (array length)"

    # Assert: names start with o-
    local name1
    name1=$(echo "$output" | jq -r '.[0].name' 2>/dev/null) || true
    if [[ ! "$name1" =~ ^o- ]]; then
        fail "$name" "expected name to start with 'o-', got: $name1"
    else
        pass "$name (name starts with o-)"
    fi

    # Assert: ISSUE_SOURCE=plan_outline
    local issue_source
    issue_source=$(echo "$output" | jq -r '.[0].vars.ISSUE_SOURCE' 2>/dev/null) || true
    if [[ "$issue_source" != "plan_outline" ]]; then
        fail "$name" "expected ISSUE_SOURCE=plan_outline, got: $issue_source"
    else
        pass "$name (ISSUE_SOURCE=plan_outline)"
    fi

    # Assert: Issue 2 waits_on contains Issue 1's name
    local issue1_name
    issue1_name=$(echo "$output" | jq -r '.[0].name' 2>/dev/null) || true
    local issue2_waits
    issue2_waits=$(echo "$output" | jq -r '.[1].waits_on[0]' 2>/dev/null) || true
    if [[ "$issue2_waits" != "$issue1_name" ]]; then
        fail "$name" "Issue 2 should wait on '${issue1_name}', got: $issue2_waits"
    else
        pass "$name (issue 2 waits_on issue 1)"
    fi

    # Assert: Issue 1 has no waits_on
    local waits_1
    waits_1=$(echo "$output" | jq -r '.[0].waits_on | length' 2>/dev/null) || true
    if [[ "$waits_1" != "0" ]]; then
        fail "$name" "Issue 1 should have empty waits_on, got length: $waits_1"
    else
        pass "$name (issue 1 waits_on empty)"
    fi

    teardown
}

# ── Fixture C: diamond dependency (single-pr) ──
# Four issues: 1->2, 1->3, 2->4, 3->4
test_single_pr_diamond() {
    local name="single-pr diamond dependency"
    setup

    cat > "$TEST_DIR/plan-diamond.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Diamond Test"
issue_count: 4
---

# PLAN: diamond-test

## Status

Draft

## Scope Summary

Diamond dependency test plan.

## Decomposition Strategy

Horizontal.

## Issue Outlines

### Issue 1: feat: foundation layer

**Complexity**: testable

**Goal**: Build the foundation.

**Acceptance Criteria**:
- [ ] Foundation exists

**Dependencies**: None.

---

### Issue 2: feat: left branch

**Complexity**: simple

**Goal**: Left branch implementation.

**Acceptance Criteria**:
- [ ] Left branch exists

**Dependencies**: Blocked by Issue 1.

---

### Issue 3: feat: right branch

**Complexity**: simple

**Goal**: Right branch implementation.

**Acceptance Criteria**:
- [ ] Right branch exists

**Dependencies**: Blocked by Issue 1.

---

### Issue 4: feat: integration layer

**Complexity**: testable

**Goal**: Integrate left and right branches.

**Acceptance Criteria**:
- [ ] Integration exists

**Dependencies**: Blocked by Issue 2, Issue 3.

## Dependency Graph

```mermaid
graph LR
    I1["#1: foundation layer"]
    I2["#2: left branch"]
    I3["#3: right branch"]
    I4["#4: integration layer"]
    I1 --> I2
    I1 --> I3
    I2 --> I4
    I3 --> I4
```

## Implementation Sequence

Critical path: Issue 1 -> Issue 2 -> Issue 4.
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan-diamond.md" 2>/dev/null)

    # Assert: valid JSON array with 4 elements
    local count
    count=$(echo "$output" | jq 'length' 2>/dev/null) || true
    if [[ "$count" != "4" ]]; then
        fail "$name" "expected 4 elements, got: $count (output: $output)"
        teardown
        return
    fi
    pass "$name (array length)"

    # Assert: issue 4 has 2 entries in waits_on
    local issue4_waits_count
    # Find the outline for issue 4 (the integration layer)
    issue4_waits_count=$(echo "$output" | jq '[.[] | select(.name | test("integration"))] | .[0].waits_on | length' 2>/dev/null) || true
    if [[ "$issue4_waits_count" != "2" ]]; then
        fail "$name" "issue 4 (integration) should have 2 waits_on, got: $issue4_waits_count"
    else
        pass "$name (issue 4 has 2 waits_on)"
    fi

    # Assert: issue 1 has no waits_on
    local issue1_waits
    issue1_waits=$(echo "$output" | jq '[.[] | select(.name | test("foundation"))] | .[0].waits_on | length' 2>/dev/null) || true
    if [[ "$issue1_waits" != "0" ]]; then
        fail "$name" "issue 1 (foundation) should have 0 waits_on, got: $issue1_waits"
    else
        pass "$name (issue 1 has 0 waits_on)"
    fi

    # Assert: issues 2 and 3 each have 1 waits_on (issue 1)
    local issue2_waits
    issue2_waits=$(echo "$output" | jq '[.[] | select(.name | test("left"))] | .[0].waits_on | length' 2>/dev/null) || true
    if [[ "$issue2_waits" != "1" ]]; then
        fail "$name" "issue 2 (left branch) should have 1 waits_on, got: $issue2_waits"
    else
        pass "$name (issue 2 has 1 waits_on)"
    fi

    local issue3_waits
    issue3_waits=$(echo "$output" | jq '[.[] | select(.name | test("right"))] | .[0].waits_on | length' 2>/dev/null) || true
    if [[ "$issue3_waits" != "1" ]]; then
        fail "$name" "issue 3 (right branch) should have 1 waits_on, got: $issue3_waits"
    else
        pass "$name (issue 3 has 1 waits_on)"
    fi

    teardown
}

# ── Test: exit 1 on missing file ──
test_missing_file_exit_code() {
    local name="exit 1 on missing file"

    local exit_code=0
    "$PARSER_SCRIPT" "/nonexistent/path/PLAN.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 1 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit code 1, got: $exit_code"
    fi
}

# ── Test: exit 2 on wrong schema ──
test_wrong_schema_exit_code() {
    local name="exit 2 on wrong schema"
    setup

    cat > "$TEST_DIR/bad-schema.md" <<'FIXTURE'
---
schema: plan/v2
status: Draft
execution_mode: single-pr
milestone: "Test"
issue_count: 1
---

# PLAN: test
FIXTURE

    local exit_code=0
    "$PARSER_SCRIPT" "$TEST_DIR/bad-schema.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 2 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit code 2, got: $exit_code"
    fi

    teardown
}

# ── Test: exit 2 on missing execution_mode ──
test_missing_execution_mode() {
    local name="exit 2 on missing execution_mode"
    setup

    cat > "$TEST_DIR/no-mode.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
milestone: "Test"
issue_count: 1
---

# PLAN: test
FIXTURE

    local exit_code=0
    "$PARSER_SCRIPT" "$TEST_DIR/no-mode.md" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 2 ]]; then
        pass "$name"
    else
        fail "$name" "expected exit code 2, got: $exit_code"
    fi

    teardown
}

# ── Test: <<ISSUE:N>> placeholder dependencies (single-pr) ──
test_single_pr_placeholder_deps() {
    local name="single-pr <<ISSUE:N>> placeholder deps"
    setup

    cat > "$TEST_DIR/plan-placeholder.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Placeholder Test"
issue_count: 3
---

# PLAN: placeholder-test

## Status

Draft

## Scope Summary

Test plan for placeholder dependency format.

## Decomposition Strategy

Horizontal.

## Issue Outlines

### Issue 1: feat: add base component

**Goal**: Build the base.

**Dependencies**: None.

---

### Issue 2: feat: add middle layer

**Goal**: Add middle layer.

**Dependencies**: None.

---

### Issue 3: feat: add top layer

**Goal**: Add top layer dependent on Issue 2.

**Dependencies**: <<ISSUE:2>>

## Dependency Graph

(omitted)

## Implementation Sequence

Critical path: Issue 2 -> Issue 3.
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan-placeholder.md" 2>/dev/null)

    # Assert: valid JSON array with 3 elements
    local count
    count=$(echo "$output" | jq 'length' 2>/dev/null) || true
    if [[ "$count" != "3" ]]; then
        fail "$name" "expected 3 elements, got: $count (output: $output)"
        teardown
        return
    fi
    pass "$name (array length)"

    # Assert: Issue 3 waits_on Issue 2's generated name
    local issue2_name issue3_waits
    issue2_name=$(echo "$output" | jq -r '.[1].name' 2>/dev/null) || true
    issue3_waits=$(echo "$output" | jq -r '.[2].waits_on[0]' 2>/dev/null) || true
    if [[ "$issue3_waits" != "$issue2_name" ]]; then
        fail "$name" "Issue 3 should wait on '${issue2_name}', got: $issue3_waits"
    else
        pass "$name (<<ISSUE:2>> resolves to issue 2 name)"
    fi

    # Assert: Issue 1 and Issue 2 have no waits_on
    local waits_1 waits_2
    waits_1=$(echo "$output" | jq -r '.[0].waits_on | length' 2>/dev/null) || true
    waits_2=$(echo "$output" | jq -r '.[1].waits_on | length' 2>/dev/null) || true
    if [[ "$waits_1" != "0" || "$waits_2" != "0" ]]; then
        fail "$name" "Issues 1 and 2 should have empty waits_on, got: $waits_1, $waits_2"
    else
        pass "$name (issues 1 and 2 have no waits_on)"
    fi

    teardown
}

# ── Test: section-header ### Dependencies format (single-pr) ──
test_single_pr_section_header_deps() {
    local name="single-pr section-header ### Dependencies deps"
    setup

    cat > "$TEST_DIR/plan-section-deps.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Section Header Test"
issue_count: 2
---

# PLAN: section-header-test

## Status

Draft

## Scope Summary

Test plan for section-header dependency format.

## Decomposition Strategy

Horizontal.

## Issue Outlines

### Issue 1: feat: add foundation layer

**Goal**: Build the foundation.

**Dependencies**: None.

---

### Issue 2: feat: add extension layer

**Goal**: Add extension.

### Dependencies

Issue 1

## Dependency Graph

(omitted)

## Implementation Sequence

Critical path: Issue 1 -> Issue 2.
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan-section-deps.md" 2>/dev/null)

    # Assert: valid JSON array with 2 elements
    local count
    count=$(echo "$output" | jq 'length' 2>/dev/null) || true
    if [[ "$count" != "2" ]]; then
        fail "$name" "expected 2 elements, got: $count (output: $output)"
        teardown
        return
    fi
    pass "$name (array length)"

    # Assert: Issue 2 waits_on Issue 1's generated name
    local issue1_name issue2_waits
    issue1_name=$(echo "$output" | jq -r '.[0].name' 2>/dev/null) || true
    issue2_waits=$(echo "$output" | jq -r '.[1].waits_on[0]' 2>/dev/null) || true
    if [[ "$issue2_waits" != "$issue1_name" ]]; then
        fail "$name" "Issue 2 should wait on '${issue1_name}', got: $issue2_waits"
    else
        pass "$name (### Dependencies section resolves to issue 1 name)"
    fi

    # Assert: Issue 1 has no waits_on
    local waits_1
    waits_1=$(echo "$output" | jq -r '.[0].waits_on | length' 2>/dev/null) || true
    if [[ "$waits_1" != "0" ]]; then
        fail "$name" "Issue 1 should have empty waits_on, got length: $waits_1"
    else
        pass "$name (issue 1 waits_on empty)"
    fi

    teardown
}

# ── Test: long title is truncated to 64 chars (single-pr) ──
test_single_pr_name_truncation() {
    local name="single-pr long title truncated to 64 chars"
    setup

    cat > "$TEST_DIR/plan-long-name.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Truncation Test"
issue_count: 1
---

# PLAN: truncation-test

## Status

Draft

## Scope Summary

Test plan for name truncation.

## Decomposition Strategy

Horizontal.

## Issue Outlines

### Issue 1: fix(plan-to-tasks): fix placeholder parsing dependency format and name truncation to avoid koto length errors

**Goal**: Fix all the parsing bugs.

**Dependencies**: None.

## Dependency Graph

(omitted)

## Implementation Sequence

Single issue.
FIXTURE

    local output stderr_output
    stderr_output=$("$PARSER_SCRIPT" "$TEST_DIR/plan-long-name.md" 2>&1 >/dev/null) || true
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan-long-name.md" 2>/dev/null)

    # Assert: script emits a truncation warning to stderr
    if echo "$stderr_output" | grep -qi "truncat"; then
        pass "$name (truncation warning emitted)"
    else
        fail "$name" "expected truncation warning on stderr, got: $stderr_output"
    fi

    # Assert: valid JSON (script should not die)
    local count
    count=$(echo "$output" | jq 'length' 2>/dev/null) || true
    if [[ "$count" != "1" ]]; then
        fail "$name" "expected 1 element, got: $count (output: $output)"
        teardown
        return
    fi
    pass "$name (array length)"

    # Assert: generated name is at most 64 chars
    local generated_name name_len
    generated_name=$(echo "$output" | jq -r '.[0].name' 2>/dev/null) || true
    name_len=${#generated_name}
    if [[ $name_len -gt 64 ]]; then
        fail "$name" "expected name length <= 64, got: $name_len (name: $generated_name)"
    else
        pass "$name (name length ${name_len} <= 64)"
    fi

    # Assert: name still starts with o-
    if [[ ! "$generated_name" =~ ^o- ]]; then
        fail "$name" "expected name to start with 'o-', got: $generated_name"
    else
        pass "$name (name starts with o-)"
    fi

    teardown
}

# ── Run all tests ──
# ── Fixture: Type and Files annotations ──

test_single_pr_type_annotation() {
    local name="single-pr **Type**: annotation"
    setup

    cat > "$TEST_DIR/plan.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Test"
issue_count: 2
---

## Issue Outlines

### Issue 1: code issue

**Goal**: Code work.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None

**Type**: code

### Issue 2: docs issue

**Goal**: Doc work.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None

**Type**: docs
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan.md" 2>/dev/null)

    local i1_type
    i1_type=$(echo "$output" | jq -r '.[0].vars.ISSUE_TYPE // "absent"')
    if [[ "$i1_type" == "code" ]]; then
        pass "$name (Issue 1 ISSUE_TYPE=code)"
    else
        fail "$name (Issue 1 ISSUE_TYPE)" "expected 'code', got '$i1_type'"
    fi

    local i2_type
    i2_type=$(echo "$output" | jq -r '.[1].vars.ISSUE_TYPE // "absent"')
    if [[ "$i2_type" == "docs" ]]; then
        pass "$name (Issue 2 ISSUE_TYPE=docs)"
    else
        fail "$name (Issue 2 ISSUE_TYPE)" "expected 'docs', got '$i2_type'"
    fi

    teardown
}

test_single_pr_missing_type() {
    local name="single-pr missing **Type**: produces no ISSUE_TYPE"
    setup

    cat > "$TEST_DIR/plan.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Test"
issue_count: 1
---

## Issue Outlines

### Issue 1: no type

**Goal**: No type annotation.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan.md" 2>/dev/null)

    local has_type
    has_type=$(echo "$output" | jq -r '.[0].vars | has("ISSUE_TYPE")')
    if [[ "$has_type" == "false" ]]; then
        pass "$name (no ISSUE_TYPE key)"
    else
        fail "$name (ISSUE_TYPE key present)" "expected key absent, got: has_key=$has_type"
    fi

    teardown
}

test_single_pr_files_waits_on() {
    local name="single-pr **Files**: shared file generates waits_on"
    setup

    cat > "$TEST_DIR/plan.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Test"
issue_count: 3
---

## Issue Outlines

### Issue 1: writes shared file

**Goal**: First.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None

**Files**: `shared/output.md`

### Issue 2: also writes shared file

**Goal**: Second.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None

**Files**: `shared/output.md`, `other/file.md`

### Issue 3: writes different file

**Goal**: Third.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None

**Files**: `unique/file.md`
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan.md" 2>/dev/null)

    # Issue 1 has no waits_on (it's the first owner of shared/output.md)
    local i1_waits
    i1_waits=$(echo "$output" | jq -r '.[0].waits_on | length')
    if [[ "$i1_waits" == "0" ]]; then
        pass "$name (Issue 1 waits_on empty)"
    else
        fail "$name (Issue 1 waits_on)" "expected 0, got $i1_waits"
    fi

    # Issue 2 waits on Issue 1 because they share shared/output.md
    local i2_waits
    i2_waits=$(echo "$output" | jq -r '.[1].waits_on | length')
    if [[ "$i2_waits" == "1" ]]; then
        pass "$name (Issue 2 waits_on length=1)"
    else
        fail "$name (Issue 2 waits_on length)" "expected 1, got $i2_waits"
    fi

    local i2_waits_name
    i2_waits_name=$(echo "$output" | jq -r '.[1].waits_on[0]')
    if [[ "$i2_waits_name" == "o-writes-shared-file" ]]; then
        pass "$name (Issue 2 waits_on references Issue 1)"
    else
        fail "$name (Issue 2 waits_on target)" "expected 'o-writes-shared-file', got '$i2_waits_name'"
    fi

    # Issue 3 has no shared files, no waits_on
    local i3_waits
    i3_waits=$(echo "$output" | jq -r '.[2].waits_on | length')
    if [[ "$i3_waits" == "0" ]]; then
        pass "$name (Issue 3 no shared file, waits_on empty)"
    else
        fail "$name (Issue 3 waits_on)" "expected 0, got $i3_waits"
    fi

    teardown
}

# ── Test: mixed-case **Type**: annotation normalized to lowercase ──
test_single_pr_type_annotation_mixed_case() {
    local name="single-pr **Type**: mixed-case normalized to lowercase"
    setup

    cat > "$TEST_DIR/plan.md" <<'FIXTURE'
---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Test"
issue_count: 3
---

## Issue Outlines

### Issue 1: code issue mixed case

**Goal**: Code work.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None

**Type**: Code

### Issue 2: docs issue mixed case

**Goal**: Doc work.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None

**Type**: Docs

### Issue 3: task issue mixed case

**Goal**: Task work.

**Acceptance Criteria**:
- [ ] AC

**Dependencies**: None

**Type**: Task
FIXTURE

    local output
    output=$("$PARSER_SCRIPT" "$TEST_DIR/plan.md" 2>/dev/null)

    local i1_type
    i1_type=$(echo "$output" | jq -r '.[0].vars.ISSUE_TYPE // "absent"')
    if [[ "$i1_type" == "code" ]]; then
        pass "$name (Issue 1 ISSUE_TYPE=code from 'Code')"
    else
        fail "$name (Issue 1 ISSUE_TYPE)" "expected 'code', got '$i1_type'"
    fi

    local i2_type
    i2_type=$(echo "$output" | jq -r '.[1].vars.ISSUE_TYPE // "absent"')
    if [[ "$i2_type" == "docs" ]]; then
        pass "$name (Issue 2 ISSUE_TYPE=docs from 'Docs')"
    else
        fail "$name (Issue 2 ISSUE_TYPE)" "expected 'docs', got '$i2_type'"
    fi

    local i3_type
    i3_type=$(echo "$output" | jq -r '.[2].vars.ISSUE_TYPE // "absent"')
    if [[ "$i3_type" == "task" ]]; then
        pass "$name (Issue 3 ISSUE_TYPE=task from 'Task')"
    else
        fail "$name (Issue 3 ISSUE_TYPE)" "expected 'task', got '$i3_type'"
    fi

    teardown
}

echo "Running plan-to-tasks.sh tests..." >&2
echo "" >&2

test_multi_pr_basic
test_single_pr_basic
test_single_pr_diamond
test_missing_file_exit_code
test_wrong_schema_exit_code
test_missing_execution_mode
test_single_pr_placeholder_deps
test_single_pr_section_header_deps
test_single_pr_name_truncation
test_single_pr_type_annotation
test_single_pr_missing_type
test_single_pr_files_waits_on
test_single_pr_type_annotation_mixed_case

echo "" >&2
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed" >&2

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
