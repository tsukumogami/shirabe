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

# A whole-line comment in an invoked script is not a read. The first real
# script this check ever followed was flagged for the line documenting that it
# never reads the state file, so the rule fired on a script's own statement that
# it complies. The pair below is the point: the comment must pass and a real
# read in the same file must still fail, or the fix traded one silent wrong
# answer for another.
write_clean_scope_fixture() {
    scope_template <<'EOF'
---
name: scope
version: "1.0"
description: Fixture whose only gate invokes a script.
initial_state: design_hop

variables:
  TOPIC_SLUG:
    description: The topic slug
    required: true

states:
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
}

test_scope_invoked_script_comment_passes() {
    local name="a wip/scope_ mention in an invoked script's comment is not a read"
    setup
    write_clean_scope_fixture
    cat > "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh" <<'EOF'
#!/usr/bin/env bash
# Reads only the artifact tree. Never reads wip/scope_<topic>_state.md.
set -euo pipefail
hop="$1"
slug="$2"
test -f "docs/${hop}s/${slug}.md"
EOF
    chmod +x "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh"
    assert_passes "$name" "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# The resume ladder reads the state key from the session now, so the probe
# left ROUTING_SCRIPTS: a probe that reads the old state file is a finding
# like any other script's.
test_scope_probe_state_read_fails() {
    local name="a resume probe reading the old state path is scanned like any other script"
    setup
    write_clean_scope_fixture
    cat > "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bash "skills/scope/scripts/resume-probe.sh" "$@"
EOF
    cat > "$TEST_DIR/skills/scope/scripts/resume-probe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test -f "wip/scope_${2}_state.md"
EOF
    assert_fails "$name" "invoked script reads the run's own state file" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# The one script still named in ROUTING_SCRIPTS keeps its carve-out.
test_scope_routing_script_read_passes() {
    local name="the publish script named in ROUTING_SCRIPTS may name the state prefix"
    setup
    write_clean_scope_fixture
    cat > "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bash "skills/scope/scripts/publish-scoping-pr.sh" "$@"
EOF
    cat > "$TEST_DIR/skills/scope/scripts/publish-scoping-pr.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git rm --cached -- "wip/scope_${2}_state.md" 2>/dev/null || true
EOF
    chmod +x "$TEST_DIR/skills/scope/scripts/publish-scoping-pr.sh"
    assert_passes "$name" "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

test_scope_routing_script_callee_still_scanned() {
    local name="a script the routing script invokes is still scanned"
    setup
    write_clean_scope_fixture
    cat > "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bash "skills/scope/scripts/resume-probe.sh" "$@"
EOF
    cat > "$TEST_DIR/skills/scope/scripts/resume-probe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bash "skills/scope/scripts/fixture-inner.sh" "$@"
EOF
    cat > "$TEST_DIR/skills/scope/scripts/fixture-inner.sh" <<'EOF'
#!/usr/bin/env bash
grep -q landed "wip/scope_${2}_state.md"
EOF
    assert_fails "$name" "invoked script reads the run's own state file" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# The other half. A trailing comment is NOT stripped, because finding where code
# ends needs a shell parser, so a real read keeps its finding even with a `#`
# later on the line.
test_scope_invoked_script_trailing_comment_still_read() {
    local name="a read with a trailing comment is still a read"
    setup
    write_clean_scope_fixture
    cat > "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
hop="$1"
slug="$2"
grep -q "^${hop}: landed" "wip/scope_${slug}_state.md"  # deliberate
EOF
    chmod +x "$TEST_DIR/skills/scope/scripts/fixture-hop-complete.sh"
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

# The children keep their state as session keys, so a gate command that looks
# in the staging folder decides on files nothing writes any more
# (staging-folder-read, the rule's second limb).
test_gate_wip_path_flagged() {
    local name="a gate command naming a wip/ path is flagged"
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
        command: "ls wip/*_state.md"
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
    assert_fails "$name" "gate command names the staging folder" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# The folder read without a slash -- `find wip -name ...` -- is the shape the
# bail gate actually had, so the limb matches the bare path word too.
test_gate_bare_wip_flagged() {
    local name="a gate command reading the folder without a slash is flagged"
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
        command: "find wip -maxdepth 2 -name 'brief_x_*' -print 2>/dev/null | grep -q ."
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
    assert_fails "$name" "gate command names the staging folder" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# An identifier that merely contains the letters is not the folder: the
# wip_paths= report line and similar names stay legal in a gate command.
test_gate_wip_identifier_passes() {
    local name="an identifier containing wip is not a staging-folder read"
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
        command: "grep -q wip_paths= out.txt"
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

# A file that merely ends in the letters is not the folder.
test_gate_wip_file_name_passes() {
    local name="a gate command reading a wip.txt file is not a staging-folder read"
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
        command: "cat wip.txt"
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

# The folder behind a leading ./ or an interpolated prefix is still the folder.
test_gate_dot_slash_wip_flagged() {
    local name="a gate command reading ./wip is flagged"
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
        command: "ls ./wip"
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
    assert_fails "$name" "gate command names the staging folder" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# A name merely containing the letters, with its own leading characters, is
# not the folder: the left boundary is word-shaped.
test_gate_swip_prefix_passes() {
    local name="a path whose segment merely ends in wip is not a staging-folder read"
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
        command: "cat swip/x"
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

# A hyphenated identifier is not the folder: the right boundary is word-shaped
# in the hyphen direction too, not only for wip_paths.
test_gate_wip_hyphen_identifier_passes() {
    local name="a hyphenated identifier containing wip is not a staging-folder read"
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
        command: "grep -q wip-paths out.txt"
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

# The folder behind an interpolated prefix is still the folder, with the bare
# word at the end of the command string.
test_gate_var_slash_wip_flagged() {
    local name="a gate command reading an interpolated \$R/wip is flagged"
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
        command: "ls $R/wip"
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
    assert_fails "$name" "gate command names the staging folder" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# The matcher's own header comment promises the interpolated $ROOT/wip case: a
# path under the folder behind a variable prefix, mid-command.
test_gate_root_var_wip_path_flagged() {
    local name="a gate command reading a path under an interpolated \$ROOT/wip is flagged"
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
        command: "test -f $ROOT/wip/brief_x_state.md && echo present"
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
    assert_fails "$name" "gate command names the staging folder" \
        "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# The limb reads the gate's own command string only: a script the gate invokes
# may still name the folder (the publish untrack step does), and only the
# parent state-file prefix limb applies inside it.
test_invoked_script_staging_not_flagged() {
    local name="an invoked script's own wip/ read is not a staging-folder finding"
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
        command: "skills/scope/scripts/fixture-untrack.sh demo"
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
    mkdir -p "$TEST_DIR/skills/scope/scripts"
    cat > "$TEST_DIR/skills/scope/scripts/fixture-untrack.sh" <<'EOF'
#!/usr/bin/env bash
# The gate command is clean; this script's own folder read stays legal.
set -euo pipefail
slug="$1"
ls "wip/brief_${slug}_notes.md"
EOF
    chmod +x "$TEST_DIR/skills/scope/scripts/fixture-untrack.sh"
    assert_passes "$name" "$TEST_DIR/skills/scope/koto-templates/scope.md"
    teardown
}

# A staging-folder-read allowlist record defers the finding like the other
# rules' records do.
test_gate_staging_allowlisted_passes() {
    local name="an allowlisted staging-folder read is deferred, not failed"
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
        command: "ls wip/*_state.md"
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
    local rel="${TEST_DIR}/skills/scope/koto-templates/scope.md"
    printf 'staging-folder-read\t%s\tchild_intermediate_present\towner/repo#7\tdeferred for the test\n' \
        "$rel" > "$TEST_DIR/allow"
    assert_passes "$name" "$rel"
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
    assert_fails "$name" "known rules: unguarded-evidence, state-file-read" "$rel"
    teardown
}

# The loader is shared with check-directive-invocations.sh (scripts/lib/
# allowlist.sh); this check's records still name a template in field 2, and the
# error says so.
test_allowlist_untabbed_record_fails() {
    local name="an allowlist record that is not tab-separated is an error naming the template field"
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
    printf 'unguarded-evidence %s gather owner/repo#7 spaces, not tabs\n' "$rel" > "$TEST_DIR/allow"
    assert_fails "$name" "expected: <rule><TAB><template><TAB><subject>" "$rel"
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

    # The line of each state's key, read from the template rather than written
    # down: the findings name a line, and an edit anywhere above a state moves
    # it without changing which states are flagged.
    local exec_tpl="$REPO_ROOT/skills/execute/koto-templates/execute.md"
    local workon_tpl="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
    state_line() { grep -n "^  $2:[[:space:]]*\$" "$1" | head -1 | cut -d: -f1; }

    local expected
    for expected in \
        "work-on.md:$(state_line "$workon_tpl" research) state 'research'" \
        "execute.md:$(state_line "$exec_tpl" escalate) state 'escalate'" \
        "execute.md:$(state_line "$exec_tpl" escalate_dirty_merge_state) state 'escalate_dirty_merge_state'" \
        "execute.md:$(state_line "$exec_tpl" escalate_upstream_drift) state 'escalate_upstream_drift'"
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
test_scope_invoked_script_comment_passes
test_scope_probe_state_read_fails
test_scope_routing_script_read_passes
test_scope_routing_script_callee_still_scanned
test_scope_invoked_script_trailing_comment_still_read
test_scope_block_scalar_command_is_read
test_template_variable_is_not_evidence
test_malformed_interpolation_terminates
test_gate_wip_path_flagged
test_gate_bare_wip_flagged
test_gate_wip_identifier_passes
test_gate_wip_file_name_passes
test_gate_dot_slash_wip_flagged
test_gate_swip_prefix_passes
test_gate_wip_hyphen_identifier_passes
test_gate_var_slash_wip_flagged
test_gate_root_var_wip_path_flagged
test_invoked_script_staging_not_flagged
test_gate_staging_allowlisted_passes
test_rule_two_does_not_apply_elsewhere
test_unresolvable_invoked_script_fails

test_allowlist_suppresses_named_state
test_allowlist_record_without_issue_fails
test_allowlist_unknown_rule_fails
test_allowlist_untabbed_record_fails

test_shipped_templates_pass
test_shipped_templates_have_four_known_violations

echo ""
echo "check-template-directives_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
