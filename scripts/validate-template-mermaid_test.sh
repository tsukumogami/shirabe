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
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
