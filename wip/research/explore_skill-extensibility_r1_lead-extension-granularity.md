# Extension Granularity: Repo, Local, and Phase-Level

Research for: skill-extensibility, extension granularity
Date: 2026-03-17

## Questions

1. Does the `.local.md` variant work for gitignored personal overrides?
2. Does `@` resolve client-side in files loaded via the Read tool (phase files)?
3. Can phase-level extensions be loaded deterministically from SKILL.md up-front?

---

## Key Finding: Two Resolution Modes

`@` include behavior differs depending on WHERE the `@` appears:

| Location | Resolution | Tool calls | Deterministic |
|----------|-----------|------------|---------------|
| SKILL.md (initial attachment) | Client-side by Claude Code | 0 | YES |
| Phase file (loaded via Read tool) | LLM-driven — model sees raw `@path` and decides to read it | 1 per extension | NO |

This is the central constraint that shapes the extension model.

---

## Test Results

### Skill-level: repo (`@name.md`)

Already confirmed in prior research. `@.claude/skill-extensions/<name>.md` in
SKILL.md is resolved client-side. Present → content injected. Missing → raw
`@path` visible to LLM but silently ignored in practice.

**Confirmed: deterministic, 0 tool calls.**

---

### Skill-level: local (`@name.local.md`)

SKILL.md includes both:
```
@.claude/skill-extensions/test-local.md
@.claude/skill-extensions/test-local.local.md
```

Test B1: repo extension only → `REPO_EXTENDED`
Test B2: repo + local → `LOCAL: REPO_EXTENDED`

Both `@` lines resolve client-side. Missing `.local.md` is silent.

**Confirmed: deterministic, 0 tool calls. Layering works — local overrides repo.**

Gitignore implication: `.claude/skill-extensions/*.local.md` can be gitignored
without breaking the mechanism. The `@` line in SKILL.md still resolves silently
when the file is absent.

---

### Phase-level: `@` in phase files (Read-loaded)

SKILL.md instructs: "Read `phases/phase-1.md` and follow its instructions."
Phase file contains: `@.claude/skill-extensions/test-phase-ext/phase-1.md`

Test A1 (extension absent): LLM reported "the @ include file doesn't exist" and
fell back to base instruction. **LLM saw the raw `@path` text and commented on it.**

Test A2 (extension present): stream-json showed 2 Read tool calls:
1. LLM reads `phases/phase-1.md` (as instructed by SKILL.md)
2. LLM autonomously reads `.claude/skill-extensions/test-phase-ext/phase-1.md`
   after seeing the raw `@path` text in the phase file content.

**Not deterministic.** The LLM decided to read the extension file. This is
model-dependent behavior — a future model or context might not make the same
decision. Requires Read tool to be available.

---

### Phase-level: up-front loading in SKILL.md

SKILL.md includes phase extensions directly:
```
@.claude/skill-extensions/test-upfront/phase-1.md

Read `phases/phase-1.md` and follow its instructions.
```

Test C: stream-json showed 1 Read tool call:
- LLM reads `phases/phase-1.md` (as instructed)
- No Read call for the extension file — it was already injected client-side

Result: `PHASE1_UPFRONT_EXTENDED` — phase extension content reached the LLM
before the phase file was read, and took effect.

**Confirmed: deterministic, 0 tool calls for extension loading.**

---

## Resulting Extension Model

All `@` includes that should be deterministic MUST live in SKILL.md, not in
phase files. This means phase extensions are declared up-front in SKILL.md,
loaded into context at skill start, and available when the LLM later reads the
phase file.

### Three-layer structure

```
SKILL.md:
  @.claude/skill-extensions/<name>.md           # skill-level, repo (committed)
  @.claude/skill-extensions/<name>.local.md     # skill-level, local (gitignored)
  @.claude/skill-extensions/<name>/phase-0.md   # phase-0, repo
  @.claude/skill-extensions/<name>/phase-0.local.md  # phase-0, local
  @.claude/skill-extensions/<name>/phase-1.md   # phase-1, repo
  ... (one pair per phase)
```

All lines are always present in SKILL.md. Missing files are silently skipped.
Only downstream consumers who create extension files pay the context cost.

### Naming convention

Phase extensions use stable semantic names (not internal file names):
- `phase-0.md` not `phase-0-setup.md` — insulates extensions from internal
  refactors that rename phase files
- Or function-based: `setup.md`, `scope.md`, `discover.md`, etc.

The convention must be documented in shirabe's public API.

### Context cost

Each missing `@` include contributes only the raw `@path` text to skill context
(one line, ~50 tokens). Present extensions contribute the file content.

For a 6-phase skill with no downstream extensions: 6 pairs × ~50 tokens =
~600 tokens overhead. Acceptable. For a downstream consumer with 2 phase
extensions: the 2 files contribute their content; the other 4 pairs contribute
the raw `@path` lines only.

---

## Gitignore Implications

`.local.md` files need to be in `.gitignore`. Recommended pattern:
```
# In .gitignore:
.claude/skill-extensions/*.local.md
.claude/skill-extensions/**/*.local.md
```

These files are intentionally excluded — they carry personal workflow
preferences (custom phases, local paths, debug instrumentation) that don't
belong in the shared repo.

---

## Phase Naming: Stable API Surface

Skill phase names become a public API once phase-level extensions are supported.
Renaming or reordering phases in the base skill is a breaking change for
downstream consumers with phase extensions.

Implications for extraction:
- Phase names must be finalized before extension mechanism ships
- Phase names should reflect function, not implementation detail
- A CHANGELOG entry is needed if a phase is renamed or its contract changes

---

## Open Questions

1. **How many phase extension slots to expose?** Not every phase needs an
   extension point. For /explore, Phase 0 (Setup) and Phase 5 (Produce) are
   the most project-specific. Phases 1-4 are largely generic. Could expose
   only the high-customization phases initially and add more as needed.

2. **Should phase extensions be additive or can they suppress base behavior?**
   With the up-front model, phase extensions are in context before the phase
   file is read. The extension can say "skip step X" or "instead of Y, do Z",
   but the LLM will have seen both instructions. In practice, later instructions
   (phase file) tend to win unless the extension uses strong language.

3. **What's the precedence order when skill-level and phase-level extensions
   conflict?** Current model: skill-level loaded first, phase-level loaded
   after. Phase-level wins on conflicts (later = higher weight). Document this.

4. **Is the raw `@path` text in phase files a problem?** Phase files read via
   Read tool will show the raw `@path` to the LLM. The LLM may try to read the
   file (as seen in Test A2). This is useful if extensions are present, but
   adds a spurious Read call if they're not. A mitigation: phase files don't use
   `@` at all — only SKILL.md does. The up-front model already achieves this.
