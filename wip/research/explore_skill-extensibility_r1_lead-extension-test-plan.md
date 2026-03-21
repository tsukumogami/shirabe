# Test Plan: @ Include Extension Mechanism

Feature: shirabe skill extensibility via `@.claude/skill-extensions/<name>.md`
Date: 2026-03-17

## Scope

Validates that `@` file includes in SKILL.md are resolved deterministically
by Claude Code, with missing files silently ignored and present files injected
into skill context without an LLM roundtrip.

## Test Infrastructure

All tests use `claude -p` (headless, non-interactive) with `--plugin-dir` to
load a test plugin. The test plugin contains minimal skills for controlled
validation.

### Fixture: base plugin

```
/tmp/shirabe-test-plugin/
  plugin.json
  skills/
    test-ext/
      SKILL.md
```

`plugin.json`:
```json
{"name": "shirabe-test", "version": "0.1.0", "skills": ["skills/test-ext"]}
```

`skills/test-ext/SKILL.md`:
```markdown
---
name: test-ext
description: Validates @ include extension mechanism
---

@.claude/skill-extensions/test-ext.md

Say exactly: "BASE" and nothing else.
```

### Run command template

```bash
claude -p "/test-ext" \
  --plugin-dir /tmp/shirabe-test-plugin \
  --dangerously-skip-permissions \
  [--tools ""] \
  [--output-format stream-json]
```

### Setup script

```bash
#!/usr/bin/env bash
# tests/setup-test-plugin.sh

set -euo pipefail

PLUGIN_DIR=/tmp/shirabe-test-plugin

mkdir -p "$PLUGIN_DIR/skills/test-ext"

cat > "$PLUGIN_DIR/plugin.json" <<'EOF'
{"name": "shirabe-test", "version": "0.1.0", "skills": ["skills/test-ext"]}
EOF

cat > "$PLUGIN_DIR/skills/test-ext/SKILL.md" <<'EOF'
---
name: test-ext
description: Validates @ include extension mechanism
---

@.claude/skill-extensions/test-ext.md

Say exactly: "BASE" and nothing else.
EOF

echo "Test plugin created at $PLUGIN_DIR"
```

---

## Test Cases

### TC-001: No extension file — base skill executes unmodified

**Precondition:** `.claude/skill-extensions/test-ext.md` does not exist.
**Command:**
```bash
claude -p "/test-ext" --plugin-dir /tmp/shirabe-test-plugin \
  --tools "" --dangerously-skip-permissions
```
**Expected output:** `BASE`
**Pass criteria:** Output is exactly `BASE`. No error. No mention of the
missing extension file path.

---

### TC-002: Extension file present — content injected and applied

**Precondition:** Create `.claude/skill-extensions/test-ext.md`:
```markdown
Instead of saying "BASE", say "EXTENDED"
```
**Command:**
```bash
claude -p "/test-ext" --plugin-dir /tmp/shirabe-test-plugin \
  --tools "" --dangerously-skip-permissions
```
**Expected output:** `EXTENDED`
**Pass criteria:** Output is `EXTENDED`. Confirms extension content reached
the LLM and took effect.

---

### TC-003: Resolution is client-side — no tool calls

**Precondition:** TC-002 setup (extension file present).
**Command:**
```bash
claude -p "/test-ext" --plugin-dir /tmp/shirabe-test-plugin \
  --tools "" --output-format stream-json --dangerously-skip-permissions \
  | grep -c "tool_use"
```
**Expected output:** `0` (or command exits with non-zero, grep finds nothing)
**Pass criteria:** Zero `tool_use` events in stream output. Confirms no Read
tool call was made to load the extension file.

---

### TC-004: Path resolves from workspace root, not plugin dir

**Precondition:** Extension file at `.claude/skill-extensions/test-ext.md`
relative to cwd (workspace root). Plugin installed at `/tmp/shirabe-test-plugin/`.
**Command:** Same as TC-002.
**Expected output:** `EXTENDED`
**Pass criteria:** Same as TC-002. Confirms the `@` path is resolved relative
to the process working directory, not relative to the SKILL.md file.

---

### TC-005: Extension additive — base instruction still applies when extension doesn't override

**Precondition:** Create `.claude/skill-extensions/test-ext.md`:
```markdown
Before responding, prepend "EXTENDED:"
```
**Command:** `claude -p "/test-ext" --plugin-dir /tmp/shirabe-test-plugin --tools "" --dangerously-skip-permissions`
**Expected output:** `EXTENDED: BASE`
**Pass criteria:** Output contains both the extension prefix and the base
instruction. Confirms extension appends to rather than replaces base skill.

---

### TC-006: Multiple extensions — two present files both loaded

**Precondition:** SKILL.md includes two @ lines:
```
@.claude/skill-extensions/test-ext.md
@.claude/skill-extensions/test-ext-2.md
```
Both files present. `test-ext.md` says "prepend A:". `test-ext-2.md` says "append :B".
**Expected output:** `A: BASE :B`
**Pass criteria:** Both extensions applied. Confirms multiple @ includes work.

---

### TC-007: Multiple extensions — mixed present and absent

**Precondition:** SKILL.md as TC-006. `test-ext.md` present. `test-ext-2.md` absent.
**Expected output:** `A: BASE`
**Pass criteria:** Present extension applies, absent one doesn't disrupt.

---

### TC-008: Missing extension with tools available — no spurious Read

**Precondition:** Extension file absent. No `--tools ""` flag (default tools).
**Command:**
```bash
claude -p "/test-ext" --plugin-dir /tmp/shirabe-test-plugin \
  --output-format stream-json --dangerously-skip-permissions \
  | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            for block in obj.get('message',{}).get('content',[]):
                if block.get('type') == 'tool_use' and block.get('name') == 'Read':
                    inp = block.get('input',{})
                    if 'skill-extensions' in str(inp):
                        print('SPURIOUS_READ:', inp)
    except: pass
"
```
**Expected output:** No output (no spurious Read calls for the extension file).
**Pass criteria:** LLM does not autonomously attempt to read the missing
extension file even when Read tool is available.

---

### TC-009: Worktree isolation — extension file behavior in worktree

**Precondition:** TC-002 setup. Run in a git worktree (`--worktree` flag).
**Command:**
```bash
claude -p "/test-ext" --plugin-dir /tmp/shirabe-test-plugin \
  --tools "" --dangerously-skip-permissions --worktree
```
**Expected output:** Depends on whether the extension file is in the worktree.
**Pass criteria:** Documents behavior. If worktrees get their own `.claude/`,
extension files may not be present by default — callers must be aware.

---

### TC-010: Installed plugin (registry) vs local --plugin-dir

**Precondition:** shirabe installed as a registered plugin (via `claude plugin install`).
Extension file at `.claude/skill-extensions/test-ext.md`.
**Command:** `claude -p "/shirabe:test-ext" --dangerously-skip-permissions`
**Expected output:** `EXTENDED`
**Pass criteria:** Same behavior as with `--plugin-dir`. Confirms mechanism
works with installed plugins, not just local ones.

Note: TC-010 requires shirabe to be published/installable. Run after skill
extraction, not during initial design validation.

---

## Regression Tests

Run TC-001 through TC-008 after each of:
- Claude Code version upgrade
- Changes to any base SKILL.md that includes `@` lines
- Changes to the skill loading path in plugin.json

---

## Test Runner Script

```bash
#!/usr/bin/env bash
# tests/run-extension-tests.sh

set -euo pipefail

PLUGIN_DIR=/tmp/shirabe-test-plugin
EXT_DIR=".claude/skill-extensions"
PASS=0
FAIL=0

run_test() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS $name"
        ((PASS++))
    else
        echo "FAIL $name: expected='$expected' got='$actual'"
        ((FAIL++))
    fi
}

# Setup
bash tests/setup-test-plugin.sh
mkdir -p "$EXT_DIR"

# TC-001
rm -f "$EXT_DIR/test-ext.md"
result=$(claude -p "/test-ext" --plugin-dir "$PLUGIN_DIR" --tools "" --dangerously-skip-permissions 2>&1)
run_test "TC-001 no-extension-file" "BASE" "$result"

# TC-002
echo 'Instead of saying "BASE", say "EXTENDED"' > "$EXT_DIR/test-ext.md"
result=$(claude -p "/test-ext" --plugin-dir "$PLUGIN_DIR" --tools "" --dangerously-skip-permissions 2>&1)
run_test "TC-002 extension-present" "EXTENDED" "$result"

# TC-003
tool_calls=$(claude -p "/test-ext" --plugin-dir "$PLUGIN_DIR" --tools "" \
    --output-format stream-json --dangerously-skip-permissions 2>&1 | grep -c "tool_use" || true)
run_test "TC-003 no-tool-calls" "0" "$tool_calls"

# TC-008
rm -f "$EXT_DIR/test-ext.md"
spurious=$(claude -p "/test-ext" --plugin-dir "$PLUGIN_DIR" \
    --output-format stream-json --dangerously-skip-permissions 2>&1 \
    | python3 -c "
import sys, json
found = False
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            for b in obj.get('message',{}).get('content',[]):
                if b.get('type') == 'tool_use' and b.get('name') == 'Read':
                    if 'skill-extensions' in str(b.get('input',{})):
                        found = True
    except: pass
print('SPURIOUS' if found else 'CLEAN')
")
run_test "TC-008 no-spurious-reads" "CLEAN" "$spurious"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

---

## Known Limitations

1. **Not truly silent on missing files.** The raw `@path` text remains in
   the SKILL.md content presented to the LLM. In practice the LLM ignores it,
   but this is a behavioral property not a platform guarantee.

2. **No semver contract.** Claude Code's skill loading mechanism is undocumented.
   The test suite serves as a regression harness for version upgrades.

3. **Model-dependent.** If Anthropic ships a model update that treats `@path`
   references as actionable instructions, TC-008 would fail. The suite catches
   this.

4. **Worktree behavior uncharted.** TC-009 is exploratory — expected behavior
   not yet established.
