#!/usr/bin/env bash
# Tests for validate-template-mermaid.sh
# Usage: bash scripts/validate-template-mermaid_test.sh

set -euo pipefail

SCRIPT="$(dirname "$0")/validate-template-mermaid.sh"
PASS=0
FAIL=0
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

run_test() {
    local name="$1"
    local expected_exit="$2"
    local dir="$3"
    local template="$4"

    local actual_exit=0
    bash "$SCRIPT" "$dir/$template" > /dev/null 2>&1 || actual_exit=$?

    if [[ "$actual_exit" -eq "$expected_exit" ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
# Check 1: state consistency
# ---------------------------------------------------------------------------

# Passing: YAML states match mermaid states
T=$(mktemp -d "$TMPDIR_ROOT/check1-pass.XXXXXX")
cat > "$T/tpl.md" <<'EOF'
---
name: test-wf
states:
  entry:
    terminal: true
  done:
    terminal: true
---
## entry
noop
EOF
cat > "$T/tpl.mermaid.md" <<'EOF'
```mermaid
stateDiagram-v2
    [*] --> entry
    entry --> done
    done --> [*]
```
EOF
run_test "check1: matching states passes" 0 "$T" "tpl.md"

# Failing: YAML has state not in mermaid
T=$(mktemp -d "$TMPDIR_ROOT/check1-fail-yaml-extra.XXXXXX")
cat > "$T/tpl.md" <<'EOF'
---
name: test-wf
states:
  entry:
    terminal: true
  done:
    terminal: true
  orphan:
    terminal: true
---
## entry
noop
EOF
cat > "$T/tpl.mermaid.md" <<'EOF'
```mermaid
stateDiagram-v2
    [*] --> entry
    entry --> done
    done --> [*]
```
EOF
run_test "check1: YAML-only state fails" 1 "$T" "tpl.md"

# Failing: mermaid has state not in YAML
T=$(mktemp -d "$TMPDIR_ROOT/check1-fail-mermaid-extra.XXXXXX")
cat > "$T/tpl.md" <<'EOF'
---
name: test-wf
states:
  entry:
    terminal: true
  done:
    terminal: true
---
## entry
noop
EOF
cat > "$T/tpl.mermaid.md" <<'EOF'
```mermaid
stateDiagram-v2
    [*] --> entry
    entry --> done
    entry --> ghost_state
    done --> [*]
```
EOF
run_test "check1: mermaid-only state fails" 1 "$T" "tpl.md"

# Passing: no mermaid companion — check 1 skipped
T=$(mktemp -d "$TMPDIR_ROOT/check1-no-mermaid.XXXXXX")
cat > "$T/tpl.md" <<'EOF'
---
name: test-wf
states:
  entry:
    terminal: true
---
## entry
noop
EOF
run_test "check1: no mermaid companion skipped (passes)" 0 "$T" "tpl.md"

# ---------------------------------------------------------------------------
# Check 2: default_template references
# ---------------------------------------------------------------------------

# Passing: referenced template exists
T=$(mktemp -d "$TMPDIR_ROOT/check2-pass.XXXXXX")
touch "$T/child.md"
cat > "$T/tpl.md" <<'EOF'
---
name: test-wf
states:
  spawn:
    materialize_children:
      default_template: child.md
---
## spawn
noop
EOF
run_test "check2: existing default_template passes" 0 "$T" "tpl.md"

# Failing: referenced template missing
T=$(mktemp -d "$TMPDIR_ROOT/check2-fail.XXXXXX")
cat > "$T/tpl.md" <<'EOF'
---
name: test-wf
states:
  spawn:
    materialize_children:
      default_template: missing.md
---
## spawn
noop
EOF
run_test "check2: missing default_template fails" 1 "$T" "tpl.md"

# ---------------------------------------------------------------------------
# Check 3: hardcoded workflow names
# ---------------------------------------------------------------------------

# Passing: uses {{SESSION_NAME}}
T=$(mktemp -d "$TMPDIR_ROOT/check3-pass.XXXXXX")
cat > "$T/tpl.md" <<'EOF'
---
name: my-workflow
states:
  run:
    terminal: true
---
## run
Use `koto next {{SESSION_NAME}}` to advance.
EOF
run_test "check3: SESSION_NAME passes" 0 "$T" "tpl.md"

# Failing: hardcoded name in koto next
T=$(mktemp -d "$TMPDIR_ROOT/check3-fail.XXXXXX")
cat > "$T/tpl.md" <<'EOF'
---
name: my-workflow
states:
  run:
    terminal: true
---
## run
Use `koto next my-workflow` to advance.
EOF
run_test "check3: hardcoded name fails" 1 "$T" "tpl.md"

# Passing: template with no name field — check 3 skipped
T=$(mktemp -d "$TMPDIR_ROOT/check3-no-name.XXXXXX")
cat > "$T/tpl.md" <<'EOF'
---
states:
  run:
    terminal: true
---
## run
noop
EOF
run_test "check3: no name in frontmatter skipped (passes)" 0 "$T" "tpl.md"

# ---------------------------------------------------------------------------
# Check 4: gate commands shared across templates stay identical
# ---------------------------------------------------------------------------

# Runs the validator over several templates at once, since check 4 only has
# something to compare when it sees more than one.
run_multi_test() {
    local name="$1"
    local expected_exit="$2"
    shift 2

    local actual_exit=0
    bash "$SCRIPT" "$@" > /dev/null 2>&1 || actual_exit=$?

    if [[ "$actual_exit" -eq "$expected_exit" ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

# Writes a template carrying a single `ci_passing` gate with the given command.
write_gate_template() {
    local path="$1"
    local command="$2"
    cat > "$path" <<EOF
---
name: gate-wf
states:
  ci_monitor:
    gates:
      ci_passing:
        type: command
        command: "${command}"
---
## ci_monitor
noop
EOF
}

GATE_CMD='gh pr checks --json bucket --jq [.[]|select(.bucket != \"pass\")]|length == 0'

# Passing: both templates carry the same command
T=$(mktemp -d "$TMPDIR_ROOT/check4-pass.XXXXXX")
write_gate_template "$T/a.md" "$GATE_CMD"
write_gate_template "$T/b.md" "$GATE_CMD"
run_multi_test "check4: identical shared gate passes" 0 "$T/a.md" "$T/b.md"

# Failing: one template's copy has drifted
T=$(mktemp -d "$TMPDIR_ROOT/check4-drift.XXXXXX")
write_gate_template "$T/a.md" "$GATE_CMD"
write_gate_template "$T/b.md" 'gh pr checks --json state --jq [.[]|select(.state != \"SUCCESS\")]|length == 0'
run_multi_test "check4: drifted shared gate fails" 1 "$T/a.md" "$T/b.md"

# Passing: gate names that appear in only one template are not compared
T=$(mktemp -d "$TMPDIR_ROOT/check4-unique.XXXXXX")
write_gate_template "$T/a.md" "$GATE_CMD"
cat > "$T/b.md" <<'EOF'
---
name: gate-wf
states:
  ci_monitor:
    gates:
      merge_state_clean:
        type: command
        command: "test -n \"$BRANCH\""
---
## ci_monitor
noop
EOF
run_multi_test "check4: unshared gate names are not compared" 0 "$T/a.md" "$T/b.md"

# Passing: a single template has nothing to compare against
T=$(mktemp -d "$TMPDIR_ROOT/check4-single.XXXXXX")
write_gate_template "$T/a.md" "$GATE_CMD"
run_multi_test "check4: single template skipped (passes)" 0 "$T/a.md"

# Failing: the same gate name drifts within one template
T=$(mktemp -d "$TMPDIR_ROOT/check4-intrafile.XXXXXX")
cat > "$T/a.md" <<'EOF'
---
name: gate-wf
states:
  first:
    gates:
      on_branch:
        type: command
        command: "test -n \"$A\""
  second:
    gates:
      on_branch:
        type: command
        command: "test -n \"$B\""
---
## first
noop
## second
noop
EOF
write_gate_template "$T/b.md" "$GATE_CMD"
run_multi_test "check4: gate drifting within one template fails" 1 "$T/a.md" "$T/b.md"

# Failing: a block scalar puts the command body out of reach, so two different
# commands would compare as equal. The check must refuse to read it rather than
# pass on it.
T=$(mktemp -d "$TMPDIR_ROOT/check4-blockscalar.XXXXXX")
cat > "$T/a.md" <<'EOF'
---
name: gate-wf
states:
  ci_monitor:
    gates:
      ci_passing:
        type: command
        command: >
          gh pr checks --json bucket
---
## ci_monitor
noop
EOF
cat > "$T/b.md" <<'EOF'
---
name: gate-wf
states:
  ci_monitor:
    gates:
      ci_passing:
        type: command
        command: >
          gh pr checks --json state
---
## ci_monitor
noop
EOF
run_multi_test "check4: block-scalar gate command is refused, not silently compared" 1 "$T/a.md" "$T/b.md"

# The real templates must agree. This pins acceptance criterion 3 of issue #244
# against the checked-in files rather than against fixtures.
run_multi_test "check4: repository templates agree on shared gates" 0 \
    "$(dirname "$0")/../skills/work-on/koto-templates/work-on.md" \
    "$(dirname "$0")/../skills/execute/koto-templates/execute.md"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
