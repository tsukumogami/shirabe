#!/usr/bin/env bash
set -euo pipefail

# Tests for check-template-directives.sh.
#
# The two fixtures the check exists for are here rather than in a fixtures
# directory, following check-template-interpolation_test.sh: a fixture template
# living under skills/*/koto-templates/ would be picked up by the repository's
# other template checks, and one living anywhere else is only reachable from a
# test anyway.
#
# The /scope-shaped fixture matters beyond the usual reason. /scope's real
# template does not exist yet, so without it rule two would ship unfalsifiable
# -- passing because it had nothing to look at, and indistinguishable from a
# rule that never fires.
#
# Usage:
#   bash scripts/check-template-directives_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check-template-directives.sh"

TEST_DIR=""
PASS_COUNT=0
FAIL_COUNT=0

setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/skills/demo/koto-templates"
    mkdir -p "$TEST_DIR/skills/scope/koto-templates"
    : > "$TEST_DIR/allow"
}

teardown() {
    [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
    TEST_DIR=""
}

fail() {
    echo "FAIL: $1 - $2" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "PASS: $1" >&2
    PASS_COUNT=$((PASS_COUNT + 1))
}

demo_template() {
    cat > "$TEST_DIR/skills/demo/koto-templates/demo.md"
}

scope_template() {
    cat > "$TEST_DIR/skills/scope/koto-templates/scope.md"
}

# Runs the check over one fixture, with the test's own allowlist so the four
# shipped-template deferrals cannot mask a fixture result.
run_check() {
    TEMPLATE_DIRECTIVES_ALLOWLIST="$TEST_DIR/allow" "$CHECK_SCRIPT" "$@" 2>&1
}

assert_fails() {
    local name="$1" needle="$2"
    shift 2
    local output status=0
    output=$(run_check "$@") || status=$?

    if [ "$status" -eq 0 ]; then
        fail "$name" "expected a non-zero exit, got 0. Output: $output"
        return
    fi
    case "$output" in
        *"$needle"*) pass "$name" ;;
        *) fail "$name" "expected output containing '$needle'. Output: $output" ;;
    esac
}

assert_passes() {
    local name="$1"
    shift
    local output status=0
    output=$(run_check "$@") || status=$?

    if [ "$status" -ne 0 ]; then
        fail "$name" "expected exit 0, got $status. Output: $output"
        return
    fi
    pass "$name"
}

# ---------------------------------------------------------------------------
# Fixture one: the deliberately malformed non-terminal state
# ---------------------------------------------------------------------------

# A non-terminal state that accepts evidence and routes unconditionally. koto
# advances through it on entry, so its directive never reaches the agent.
test_malformed_state_fails() {
    local name="malformed non-terminal state fails rule one"
    setup
    demo_template <<'EOF'
---
name: demo
version: "1.0"
description: Fixture for the unguarded-evidence rule.
initial_state: gather

states:
  gather:
    accepts:
      outcome:
        type: enum
        values: [landed, refused]
        required: true
    transitions:
      - target: done

  done:
    terminal: true
---

# Demo
EOF
    assert_fails "$name" "state 'gather' accepts evidence with no guarded transition" \
        "$TEST_DIR/skills/demo/koto-templates/demo.md"
    teardown
}

# The same state, guarded. This is the shape the rule asks for.
test_guarded_state_passes() {
    local name="guarded transition passes rule one"
    setup
    demo_template <<'EOF'
---
name: demo
version: "1.0"
initial_state: gather

states:
  gather:
    accepts:
      outcome:
        type: enum
        values: [landed, refused]
        required: true
    transitions:
      - target: done
        when:
          outcome: landed
      - target: done_blocked
        when:
          outcome: refused

  done:
    terminal: true

  done_blocked:
    terminal: true
---
EOF
    assert_passes "$name" "$TEST_DIR/skills/demo/koto-templates/demo.md"
    teardown
}

# A terminal cannot carry a transition, so it can never satisfy the rule.
# done_blocked in the shipped templates has exactly this shape.
test_terminal_with_accepts_passes() {
    local name="terminal state with an accepts block is exempt"
    setup
    demo_template <<'EOF'
---
name: demo
version: "1.0"
initial_state: done_blocked

states:
  done_blocked:
    terminal: true
    accepts:
      failure_reason:
        type: string
        required: true
---
EOF
    assert_passes "$name" "$TEST_DIR/skills/demo/koto-templates/demo.md"
    teardown
}

# Directives are block scalars full of indented markdown. A list item reading
# "  gather:" inside one is prose, not a state.
test_directive_prose_is_not_parsed_as_states() {
    local name="markdown inside a directive block scalar is not read as states"
    setup
    demo_template <<'EOF'
---
name: demo
version: "1.0"
initial_state: gather

states:
  gather:
    directive: |
      Walk the tree and report.

      states:
        ghost:
          accepts:
            outcome:
              type: string
          transitions:
            - target: nowhere
    accepts:
      outcome:
        type: string
        required: true
    transitions:
      - target: done
        when:
          outcome: landed

  done:
    terminal: true
---
EOF
    assert_passes "$name" "$TEST_DIR/skills/demo/koto-templates/demo.md"
    teardown
}

# A mermaid companion has no frontmatter and no states to check.
test_no_frontmatter_is_skipped() {
    local name="a file without frontmatter is skipped, not failed"
    setup
    cat > "$TEST_DIR/skills/demo/koto-templates/demo.mermaid.md" <<'EOF'
# Demo state graph

```mermaid
stateDiagram-v2
    [*] --> gather
    gather --> done
```
EOF
    assert_passes "$name" "$TEST_DIR/skills/demo/koto-templates/demo.mermaid.md"
    teardown
}

# ---------------------------------------------------------------------------
# Fixture two: the /scope-shaped template
# ---------------------------------------------------------------------------

# One gate reads wip/scope_, one reads an evidence field, and one calls out to
# a script that reads wip/scope_ while its own command string looks clean.
# All three must fail.
write_scope_fixture() {
    scope_template <<'EOF'
---
name: scope
version: "1.0"
description: Fixture for the hop-completion rule.
initial_state: brief_hop

variables:
  TOPIC_SLUG:
    description: The topic slug
    required: true

states:
  brief_hop:
    gates:
      brief_complete:
        type: command
        command: "grep -q 'brief: landed' wip/scope_{{TOPIC_SLUG}}_state.md"
    accepts:
      outcome:
        type: enum
        values: [landed, folded]
        required: true
    transitions:
      - target: prd_hop
        when:
          outcome: landed
          gates.brief_complete.exit_code: 0

  prd_hop:
    gates:
      prd_complete:
        type: command
        command: "test '${evidence.prd_landed}' = 'true'"
    accepts:
      outcome:
        type: enum
        values: [landed, folded]
        required: true
    transitions:
      - target: design_hop
        when:
          outcome: landed
          gates.prd_complete.exit_code: 0

  design_hop:
    gates:
      design_complete:
        type: command
        command: "skills/scope/scripts/fixture-hop-complete.sh design {{TOPIC_SLUG}}"
    accepts:
      outcome:
        type: enum
        values: [landed, folded]
        required: true
    transitions:
      - target: done
        when:
          outcome: landed
          gates.design_complete.exit_code: 0

  done:
    terminal: true
---

# Scope fixture
EOF

    mkdir -p "$TEST_DIR/skills/scope/scripts"
    cat > "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh" <<'EOF'
#!/usr/bin/env bash
# The gate command invoking this script is clean. The read is in here.
set -euo pipefail
hop="$1"
slug="$2"
grep -q "^${hop}: landed" "wip/scope_${slug}_state.md"
EOF
    chmod +x "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh"
}

test_scope_gate_reading_state_file_fails() {
    local name="/scope gate reading wip/scope_ fails rule two"
    setup
    write_scope_fixture
    assert_fails "$name" "gate 'brief_complete': gate reads the run's own state file" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

test_scope_gate_reading_evidence_fails() {
    local name="/scope gate reading an evidence field fails rule two"
    setup
    write_scope_fixture
    assert_fails "$name" "gate 'prd_complete': gate reads an agent-submitted evidence field" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# The limb the design calls out: the gate string is clean and the read is one
# level down, inside the script the gate invokes.
test_scope_invoked_script_read_fails() {
    local name="/scope gate whose invoked script reads wip/scope_ fails rule two"
    setup
    write_scope_fixture
    assert_fails "$name" "invoked script reads the run's own state file" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# A gate command written as a block scalar puts the command on the following
# lines. Skipping those the way a directive is skipped would hide the read.
test_scope_block_scalar_command_is_read() {
    local name="/scope gate with a block-scalar command is still read"
    setup
    scope_template <<'EOF'
---
name: scope
version: "1.0"
initial_state: brief_hop

states:
  brief_hop:
    gates:
      brief_complete:
        type: command
        command: >
          grep -q 'brief: landed' wip/scope_topic_state.md
    accepts:
      outcome:
        type: string
        required: true
    transitions:
      - target: done
        when:
          outcome: landed

  done:
    terminal: true
---
EOF
    assert_fails "$name" "gate 'brief_complete': gate reads the run's own state file" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# The false positive that would make the shipped templates unpassable:
# work-on.md interpolates {{PLAN_SLUG}} into a gate command today.
test_template_variable_is_not_evidence() {
    local name="a {{VAR}} interpolation is not an evidence field"
    setup
    scope_template <<'EOF'
---
name: scope
version: "1.0"
initial_state: brief_hop

variables:
  TOPIC_SLUG:
    description: The topic slug
    required: true

states:
  brief_hop:
    gates:
      brief_complete:
        type: command
        command: "test -f docs/briefs/BRIEF-{{TOPIC_SLUG}}.md"
    accepts:
      outcome:
        type: string
        required: true
    transitions:
      - target: done
        when:
          outcome: landed

  done:
    terminal: true
---
EOF
    assert_passes "$name" "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# A line where a `}}` precedes a `{{` hung an earlier version of the
# interpolation stripper: the rejoin reintroduced text the cut had removed and
# the string grew on every pass. A lint that hangs on malformed input is worse
# than one that misreads it, so the case is pinned with a timeout.
test_malformed_interpolation_terminates() {
    local name="a }} before a {{ does not hang the interpolation stripper"
    setup
    scope_template <<'EOF'
---
name: scope
version: "1.0"
initial_state: brief_hop

variables:
  TOPIC_SLUG:
    description: The topic slug
    required: true

states:
  brief_hop:
    gates:
      brief_complete:
        type: command
        command: "test -f 'docs/}}odd{{TOPIC_SLUG}}.md'"
    accepts:
      outcome:
        type: string
        required: true
    transitions:
      - target: done
        when:
          outcome: landed

  done:
    terminal: true
---
EOF
    local status=0
    timeout 20 env TEMPLATE_DIRECTIVES_ALLOWLIST="$TEST_DIR/allow" \
        "$CHECK_SCRIPT" "$TEST_DIR/skills/scope/koto-templates/scope.md" >/dev/null 2>&1 || status=$?

    if [ "$status" -eq 124 ]; then
        fail "$name" "the check timed out, so the stripper did not terminate"
    else
        pass "$name"
    fi
    teardown
}

# The bail state legitimately reads child-intermediate wip/ prefixes. Only the
# parent's own wip/scope_ prefix is the state file.
test_child_wip_prefix_passes() {
    local name="a wip/ read that is not wip/scope_ passes"
    setup
    scope_template <<'EOF'
---
name: scope
version: "1.0"
initial_state: bail

states:
  bail:
    gates:
      child_intermediate_present:
        type: command
        command: "ls wip/prd_*_state.md"
    accepts:
      bail_mode:
        type: string
        required: true
    transitions:
      - target: done
        when:
          bail_mode: force_materialize

  done:
    terminal: true
---
EOF
    assert_passes "$name" "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# Rule two is /scope's. The same gate in another skill's template is not a
# finding -- wip/scope_ there would be a different skill reading a file it does
# not own, which is a different problem.
test_rule_two_does_not_apply_elsewhere() {
    local name="rule two does not apply outside /scope's template"
    setup
    demo_template <<'EOF'
---
name: demo
version: "1.0"
initial_state: check

states:
  check:
    gates:
      state_present:
        type: command
        command: "test -f wip/scope_demo_state.md"
    accepts:
      outcome:
        type: string
        required: true
    transitions:
      - target: done
        when:
          outcome: landed

  done:
    terminal: true
---
EOF
    assert_passes "$name" "$TEST_DIR/skills/demo/koto-templates/demo.md"
    teardown
}

# A gate calling a script the check cannot find leaves rule two unenforced on
# that script. Reporting it clean would overstate the coverage.
test_unresolvable_invoked_script_fails() {
    local name="an unresolvable invoked script is an error, not a pass"
    setup
    scope_template <<'EOF'
---
name: scope
version: "1.0"
initial_state: brief_hop

states:
  brief_hop:
    gates:
      brief_complete:
        type: command
        command: "skills/scope/scripts/absent-predicate.sh brief"
    accepts:
      outcome:
        type: string
        required: true
    transitions:
      - target: done
        when:
          outcome: landed

  done:
    terminal: true
---
EOF
    assert_fails "$name" "which was not found" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# ---------------------------------------------------------------------------
# The allowlist
# ---------------------------------------------------------------------------

test_allowlist_suppresses_named_state() {
    local name="an allowlist record suppresses the state it names"
    setup
    demo_template <<'EOF'
---
name: demo
version: "1.0"
initial_state: gather

states:
  gather:
    accepts:
      outcome:
        type: string
        required: true
    transitions:
      - target: done

  done:
    terminal: true
---
EOF
    local rel="${TEST_DIR}/skills/demo/koto-templates/demo.md"
    printf 'unguarded-evidence\t%s\tgather\towner/repo#7\tdeferred for the test\n' \
        "$rel" > "$TEST_DIR/allow"
    assert_passes "$name" "$rel"
    teardown
}

test_allowlist_record_without_issue_fails() {
    local name="an allowlist record with no issue reference is itself an error"
    setup
    demo_template <<'EOF'
---
name: demo
version: "1.0"
initial_state: done

states:
  done:
    terminal: true
---
EOF
    local rel="${TEST_DIR}/skills/demo/koto-templates/demo.md"
    printf 'unguarded-evidence\t%s\tgather\t\tno ticket behind this\n' \
        "$rel" > "$TEST_DIR/allow"
    assert_fails "$name" "has no issue reference" "$rel"
    teardown
}

test_allowlist_unknown_rule_fails() {
    local name="an allowlist record naming an unknown rule is an error"
    setup
    demo_template <<'EOF'
---
name: demo
version: "1.0"
initial_state: done

states:
  done:
    terminal: true
---
EOF
    local rel="${TEST_DIR}/skills/demo/koto-templates/demo.md"
    printf 'no-such-rule\t%s\tgather\towner/repo#7\treason\n' "$rel" > "$TEST_DIR/allow"
    assert_fails "$name" "names an unknown rule" "$rel"
    teardown
}

# ---------------------------------------------------------------------------
# The shipped templates
# ---------------------------------------------------------------------------

# With the real allowlist, the repository is clean. This is the criterion the
# check has to satisfy to land at all.
test_shipped_templates_pass() {
    local name="the shipped templates pass with the repository's allowlist"
    local output status=0
    output=$("$CHECK_SCRIPT" 2>&1) || status=$?

    if [ "$status" -ne 0 ]; then
        fail "$name" "expected exit 0, got $status. Output: $output"
        return
    fi
    pass "$name"
}

# And the allowlist is absorbing exactly the four known violations rather than
# something wider. Emptying it must surface all four and nothing else.
test_shipped_templates_have_four_known_violations() {
    local name="emptying the allowlist surfaces exactly the four known violations"
    local output status=0 count
    output=$(TEMPLATE_DIRECTIVES_ALLOWLIST=/dev/null "$CHECK_SCRIPT" 2>&1) || status=$?

    if [ "$status" -eq 0 ]; then
        fail "$name" "expected a non-zero exit with the allowlist emptied"
        return
    fi

    count=$(printf '%s\n' "$output" | grep -c '^FAIL:' || true)
    if [ "$count" -ne 4 ]; then
        fail "$name" "expected 4 findings, got $count. Output: $output"
        return
    fi

    local expected
    for expected in \
        "work-on.md:125 state 'research'" \
        "execute.md:314 state 'escalate'" \
        "execute.md:275 state 'escalate_dirty_merge_state'" \
        "execute.md:136 state 'escalate_upstream_drift'"
    do
        case "$output" in
            *"$expected"*) ;;
            *) fail "$name" "missing expected finding: $expected"; return ;;
        esac
    done

    pass "$name"
}

# ---------------------------------------------------------------------------

test_malformed_state_fails
test_guarded_state_passes
test_terminal_with_accepts_passes
test_directive_prose_is_not_parsed_as_states
test_no_frontmatter_is_skipped

test_scope_gate_reading_state_file_fails
test_scope_gate_reading_evidence_fails
test_scope_invoked_script_read_fails
test_scope_block_scalar_command_is_read
test_template_variable_is_not_evidence
test_malformed_interpolation_terminates
test_child_wip_prefix_passes
test_rule_two_does_not_apply_elsewhere
test_unresolvable_invoked_script_fails

test_allowlist_suppresses_named_state
test_allowlist_record_without_issue_fails
test_allowlist_unknown_rule_fails

test_shipped_templates_pass
test_shipped_templates_have_four_known_violations

echo ""
echo "check-template-directives_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
