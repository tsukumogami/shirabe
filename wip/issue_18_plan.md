# Issue 18 Implementation Plan

## Approach

Rewrite SKILL.md to replace the manual orchestration wrapper (resume logic +
phase dispatch) with a koto-driven loop. The template is already on the branch.
Phase reference files remain unchanged — they provide agent guidance that koto
directives reference but don't replace.

## Changes

### 1. Rewrite skills/work-on/SKILL.md

**Keep unchanged:**
- Frontmatter (name, description, argument-hint)
- Extension file references (@.claude/shirabe-extensions/...)
- Title and goal statement
- Input Resolution section (issue/milestone parsing)
- Handling needs-triage and Blocking Labels sections

**Replace:**
- Workflow Overview table — update to reference koto states instead of phases
- Resume Logic (~22 lines) — delete entirely, koto handles via gates
- Execution section (~31 lines) — replace with koto orchestration loop
- Begin section — update to: resolve input, detect visibility, init koto, enter loop

**New content:**
- Koto Orchestration section: how to init, loop on `koto next`, submit evidence
- State-to-Phase mapping: which reference file to read for each koto state
- Evidence submission examples for key states

### 2. No phase file changes

Phase files are agent guidance. Their resume checks at the top are redundant with
koto gates but harmless. No modifications needed.

### 3. No new scripts needed

koto is already a CLI. The agent calls `koto init`, `koto next`, `koto transition`
directly. No wrapper scripts.

## File list

- `skills/work-on/SKILL.md` — rewrite (the only file that changes)

## Risk

- Evidence field names in SKILL.md instructions must match template `accepts` blocks exactly
- State names in the mapping must match template state names exactly
