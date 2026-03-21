# Extension Mechanism Validation: @ Include in SKILL.md

Research for: skill-extensibility, extension mechanism testing
Date: 2026-03-17

## Hypothesis

`@path/to/file` in SKILL.md is resolved deterministically by Claude Code
before the LLM processes the skill content. Missing files are silently ignored.
No LLM roundtrip is required for extension loading.

## Test Setup

Minimal test plugin created at `/tmp/test-plugin/` with a single skill
(`/test-include`) containing `@.claude/skill-extensions/test-include.md`
in the SKILL.md body. Run via `claude -p /test-include --plugin-dir /tmp/test-plugin`.

## Tests and Results

### T1: Missing extension file — behavior with no tools

SKILL.md:
```
@.claude/skill-extensions/test-include.md
Say exactly: "BASE_SKILL_EXECUTED" and nothing else.
```
Extension file: absent.
Command: `claude -p "/test-include" --tools "" --dangerously-skip-permissions`

Result: `BASE_SKILL_EXECUTED`
**PASS** — missing @ include does not disrupt skill execution.

---

### T2: Present extension file — content loaded and applied

Extension file content: "Instead of saying 'BASE_SKILL_EXECUTED', say
'EXTENSION_LOADED_AND_EXECUTED'"
Command: same as T1 but with extension file present, --tools ""

Result: `EXTENSION_LOADED_AND_EXECUTED`
**PASS** — extension content loaded and took effect over base instruction.

---

### T3: No tool calls — resolution is client-side

Command: T2 setup + `--output-format stream-json`, searched for `tool_use` events.

Result: 0 tool_use events.
**PASS** — @ include resolved before LLM sees content. No Read tool call.

---

### T4: Path relative to workspace root

Extension file at `.claude/skill-extensions/test-include.md` in the shirabe
working directory. Plugin installed at `/tmp/test-plugin/`. Paths are not
relative to the plugin directory.

Result: `EXTENSION_LOADED_AND_EXECUTED`
**PASS** — @ resolves relative to cwd (workspace root), not relative to
the SKILL.md file location.

---

### T5: Mixed present + missing @ includes

SKILL.md:
```
@.claude/skill-extensions/test-include.md      # present
@.claude/skill-extensions/nonexistent-skill.md # absent
List every instruction you have received.
```

Result: LLM listed all instructions. The present extension appeared as loaded
content. The missing extension appeared as the literal `@path` text with
annotation "(file not found; no instructions loaded)".

**PARTIAL** — the missing @ include does not cause errors or tool calls, but
the raw `@path` text remains visible to the LLM (it is not stripped out).
The LLM correctly inferred it was a nonexistent file.

---

### T6: Raw @ text visibility when file missing

Confirmed via T5 and a dedicated test: when the file is missing, the LLM
sees the raw `@.claude/skill-extensions/nonexistent-skill.md` text in the
skill content. It is NOT replaced with empty string.

---

### T7: Missing @ with default tools (real-world condition)

Command: T1 setup but with default tools (Read available).

Result: `BASE_SKILL_EXECUTED` — LLM did not attempt to Read the missing file.

**PASS in practice** — the raw `@path` text in context did not trigger
autonomous file-read behavior when combined with explicit skill instructions.

Note: this is behavioral, not guaranteed. A sufficiently instruction-following
model in a different context might attempt to read the path. Not a hard
guarantee.

---

## Summary

| Property | Result |
|----------|--------|
| @ resolved client-side (no LLM roundtrip) | CONFIRMED |
| Present file content injected | CONFIRMED |
| Missing file causes no error | CONFIRMED |
| Missing file causes no tool calls | CONFIRMED |
| Missing file leaves raw @path visible to LLM | CONFIRMED (not true silent) |
| Path resolves relative to workspace root | CONFIRMED |
| LLM ignores raw @path in practice | CONFIRMED (behavioral) |

## Implication for Extension Mechanism

The `@.claude/skill-extensions/<name>.md` pattern works as a deterministic
extension mechanism. No "check if file exists and read it" instruction needed
in SKILL.md. Base skills include the `@` reference directly; downstream
consumers create the file to activate extensions.

The one impurity: missing files leave raw `@path` text rather than nothing.
In practice this is harmless — skills don't show degraded behavior. If this
becomes an issue (LLM tries to act on the raw path), a mitigation is wrapping
the include in a comment-style convention, or documenting that SKILL.md should
place the `@` include in a dedicated "Project Extensions" section that LLMs
learn to treat as optional context.

## Residual Questions (for design doc)

1. Does this behavior survive Claude Code version updates? (No semver contract
   on the plugin system — needs periodic regression testing.)
2. Does the mechanism work the same when shirabe is installed from a plugin
   registry vs. local path? (Only tested local `--plugin-dir`.)
3. Is the workspace root always the resolution base, or does it change when
   running in a worktree? (`--worktree` creates an isolated copy — extension
   files may not be present there without explicit setup.)
