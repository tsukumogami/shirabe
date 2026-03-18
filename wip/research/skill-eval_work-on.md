# Skill Evaluation: /work-on Migration to shirabe

## Current State Assessment

### Files in scope

- `SKILL.md` — 137 lines (including frontmatter)
- `references/phases/phase-0-context-injection.md` — 48 lines
- `references/phases/phase-1-setup.md` — 81 lines
- `references/phases/phase-2-introspection.md` — 96 lines
- `references/phases/phase-3-analysis.md` — 49 lines (orchestration file)
- `references/agent-instructions/phase-3-analysis.md` — 157 lines
- `references/phases/phase-4-implementation.md` — 134 lines
- `references/phases/phase-5-finalization.md` — 152 lines
- `references/phases/phase-6-pr.md` — 148 lines
- `references/scripts/extract-context.sh` — 353 lines

**Total SKILL.md body:** 131 lines (below 500-line limit — no splitting needed)

### Description quality

Current description:
```
Execute complete feature development workflow for a GitHub issue
```

This is functionally accurate but weak for triggering. It describes the *output* (complete workflow) rather than the *input signals* — the user phrases and contexts that should trigger it. A user saying "work on issue 47" or "implement #83" won't see obvious alignment with "Execute complete feature development workflow."

The skill-creator framework notes that Claude tends to undertrigger, so descriptions should be specific about input contexts. This one needs to enumerate the entry points: issue numbers, milestone references, URLs.

### Body structure

SKILL.md at 131 lines is well under the 500-line limit. Progressive disclosure is working as intended — the 7 phase files stay in `references/phases/` and are loaded on demand. The agent-instructions file (`references/agent-instructions/phase-3-analysis.md`) is correctly separated.

The structure follows good progressive disclosure:
1. Input resolution (always needed)
2. Handling edge cases (triage, blocking labels)
3. Workflow overview table (scan-friendly)
4. Resume logic (code + prose)
5. Execution (brief phase pointers to reference files)
6. Critical requirements
7. Begin instruction

No structural problems. The phase-pointer pattern is clean.

### Token efficiency

The SKILL.md body is tight. The main inefficiency is content that belongs in extension files, not prose bloat. Specific issues:

- The `needs-triage` handling block (lines 20-33) is 14 lines of project-specific inline triage logic that references two tools-internal skills (`upstream-context`, `/triage`). This should be an extension-layer hook.
- The blocking labels section (lines 36-54) is 19 lines of tsuku-specific label vocabulary with tsuku-specific routing messages. Extension layer.
- The label names appear again in the "Begin" instruction (line 136), which will need updating too.
- Line 97 hardcodes `go-development` and `pr-creation` skill invocations.

The phase files have minor Go-specific traces (see per-file analysis below).

---

## Migration Changes Required

### SKILL.md

**After frontmatter (after line 5), add extension slot lines:**

Current (line 5):
```
---
```

Replace the end of frontmatter block — insert these two lines immediately after the closing `---`:

```
@.claude/shirabe-extensions/work-on.md
@.claude/shirabe-extensions/work-on.local.md
```

So lines 1-7 become:
```yaml
---
name: work-on
description: <new description — see below>
argument-hint: '<issue_number | #issue | issue-url | M<milestone> | milestone-url | "Milestone Name">'
---
@.claude/shirabe-extensions/work-on.md
@.claude/shirabe-extensions/work-on.local.md
```

---

**Lines 20-33 — Remove inline triage block entirely:**

Current text to remove:
```markdown
### Handling `needs-triage` Issues

If the selected issue has a `needs-triage` label, run inline triage before proceeding:

1. Invoke the `upstream-context` skill to gather context
2. Run the jury-based assessment from `/triage` (3 agents evaluate: needs-design vs needs-breakdown vs ready)
3. Present recommendation to user with AskUserQuestion

Based on user's choice:
- **Needs Design**: Update label to `needs-design`, stop and suggest `/explore` instead
- **Needs Breakdown**: Create sub-issues, update parent as blocked, stop and suggest `/work-on` for a sub-issue
- **Ready**: Remove `needs-triage` label, proceed with /work-on workflow

See `/triage` command for full triage logic details.
```

Replace with:
```markdown
### Handling `needs-triage` Issues

If the selected issue has a `needs-triage` label, the issue needs classification before implementation. Check your project's label vocabulary (defined in `## Label Vocabulary` in CLAUDE.md) for the routing options available. If your project's extension file defines a triage workflow, invoke it now. Otherwise, ask the user whether to proceed directly or reclassify the issue.
```

Rationale: The `upstream-context` skill, jury-based `/triage`, and specific routing actions (sub-issues, blocked labels) are all tsuku-specific. A shirabe consumer may have no triage skill at all. The generalized version preserves the intent (don't blindly start implementation on unclassified issues) without hardcoding tsuku's machinery.

---

**Lines 36-54 — Remove the blocking labels section entirely:**

Current text to remove:
```markdown
### Handling Blocking Labels

After resolving the issue and reading it with `gh issue view`, check for blocking labels before proceeding. See `helpers/label-reference.md` for the full label vocabulary.

#### Tracking Labels

If the issue has a **`tracks-design`** or **`tracks-plan`** label: display "This issue tracks a child design/plan. Use /implement-doc on the child artifact instead." and **stop execution**.

These issues have already spawned a child artifact whose implementation is in progress -- the correct workflow is `/implement-doc` on the child design or plan doc.

#### Needs-* Labels

If the issue has any `needs-*` label, it is not directly implementable. Check which label is present and display the appropriate routing message, then **stop execution**:

| Label | Routing Message |
|-------|-----------------|
| `needs-design` | "This issue requires architectural design. Use /explore to create a design first." |
| `needs-prd` | "This issue requires requirements definition. Create a PRD to clarify requirements first." |
| `needs-spike` | "This issue requires feasibility investigation. Run a spike to evaluate feasibility first." |
| `needs-decision` | "This issue requires an architectural decision. Create a decision record first." |
```

Replace with:
```markdown
### Handling Blocking Labels

After resolving the issue and reading it with `gh issue view`, check for blocking labels before proceeding. Your project's label vocabulary is defined in `## Label Vocabulary` in CLAUDE.md.

If the issue has any label indicating it is not yet ready for implementation (such as labels requiring design, requirements definition, or feasibility investigation), display the appropriate routing message and **stop execution**.

If the issue has a label indicating it tracks a child artifact whose implementation is underway, stop and direct the user to work on the child artifact instead.

Your project's extension file (`.claude/shirabe-extensions/work-on.md`) defines the specific label names and routing messages to use.
```

Rationale: The specific label names (`tracks-design`, `tracks-plan`, `needs-design`, `needs-prd`, `needs-spike`, `needs-decision`), the routing messages with specific skill names (`/implement-doc`, `/explore`), and the `helpers/label-reference.md` reference are all tsuku-specific. The replacement preserves the decision logic (check for blocking labels, stop if found) and defers vocabulary to CLAUDE.md and extension files.

---

**Line 97 — Remove hardcoded skill invocations:**

Current:
```markdown
Invoke the `go-development` skill for code quality requirements and the `pr-creation` skill for PR requirements, then execute phases sequentially:
```

Replace with:
```markdown
If your project's extension file defines a language skill or PR creation skill, invoke those now for project-specific quality and PR requirements. Then execute phases sequentially:
```

Rationale: `go-development` is entirely Go/tsuku-specific. `pr-creation` is a tools-internal skill. Both belong in the extension file for tsuku consumers. A generic shirabe consumer gets no language-specific quality checks by default — they must supply them via extension.

---

**Line 136 — Update the "Begin" instruction:**

Current:
```markdown
First, resolve the input using the Input Resolution section above. Once you have an issue number, read the issue with `gh issue view <issue-number>`. Check for blocking labels (`tracks-design`, `tracks-plan`, `needs-design`, `needs-prd`, `needs-spike`, `needs-decision`) and stop if present. Otherwise, start Phase 0.
```

Replace with:
```markdown
First, resolve the input using the Input Resolution section above. Once you have an issue number, read the issue with `gh issue view <issue-number>`. Check for blocking labels as defined in your project's label vocabulary (CLAUDE.md `## Label Vocabulary`) and stop if any are present. Otherwise, start Phase 0.
```

Rationale: Removes the hardcoded label list, which repeats the project-specific vocabulary from the removed blocking labels section.

---

### references/phases/phase-1-setup.md

**Line 28 — Remove Go-specific parenthetical:**

Current:
```markdown
Run the project's test suite to establish a clean starting state. Use project-specific commands from the relevant skill (e.g., go-development for Go projects).
```

Replace with:
```markdown
Run the project's test suite to establish a clean starting state. Use project-specific commands from the language skill defined in your extension file, or from the project's CLAUDE.md.
```

Rationale: The `go-development` example hardcodes Go as the expected language.

---

**Lines 41-62 — Template uses `.go` file path examples:**

The baseline template shows `path/to/file1.go` and `path/to/file2.go`. These aren't Go-specific in a harmful way (they're visually illustrative), but they do implicitly suggest a Go codebase. Change to language-neutral extensions:

Current:
```markdown
## Changes Made
- `path/to/file1.go`: <what changed>
- `path/to/file2.go`: <what changed>
```

Replace with:
```markdown
## Changes Made
- `path/to/file1`: <what changed>
- `path/to/file2`: <what changed>
```

This appears in the summary template in phase-5-finalization.md as well — apply the same change there.

---

### references/phases/phase-3-analysis.md (orchestration file)

**Lines 24-35 — Remove `go-development` conditional skill loading:**

Current:
```markdown
### Conditional Skill Loading

To minimize agent context:
- **Pass `go-development` skill**: Only for full-plan issues (bug/enhancement/refactor)
- **Skip skills**: For simplified-plan issues (docs/config/chore)

### Agent Inputs

Provide the agent with:
- Issue details (JSON from `gh issue view <N>`)
- Baseline file path: `wip/issue_<N>_baseline.md`
- Issue type classification: "full-plan" or "simplified-plan"
- Agent instructions: `../agent-instructions/phase-3-analysis.md`
- Conditional: `go-development` skill path (full-plan only)
```

Replace with:
```markdown
### Conditional Skill Loading

To minimize agent context, only pass the language skill for full-plan issues (bug/enhancement/refactor). Check the project extension file for the language skill path. Skip for simplified-plan issues (docs/config/chore).

### Agent Inputs

Provide the agent with:
- Issue details (JSON from `gh issue view <N>`)
- Baseline file path: `wip/issue_<N>_baseline.md`
- Issue type classification: "full-plan" or "simplified-plan"
- Agent instructions: `../agent-instructions/phase-3-analysis.md`
- Conditional: language skill path from extension file (full-plan only, if defined)
```

---

### references/agent-instructions/phase-3-analysis.md

**Line 12 — Remove `go-development` from agent inputs description:**

Current:
```markdown
- Project skill (conditional): May include `go-development` or similar
```

Replace with:
```markdown
- Project skill (conditional): Language skill from the project extension file, if defined
```

**Lines 32-34 — The full plan template uses `.go` file extensions:**

Current:
```markdown
## Files to Modify
- `path/to/file1.go` - <what changes>
- `path/to/file2.go` - <what changes>
```

Replace with:
```markdown
## Files to Modify
- `path/to/file1` - <what changes>
- `path/to/file2` - <what changes>
```

---

### references/phases/phase-4-implementation.md

**Lines 38-39 — Remove Go-specific reference:**

Current:
```markdown
For Go projects, see `go-development` skill for specific commands.
For other projects, check the project's CLAUDE.md or pre-commit requirements.
```

Replace with:
```markdown
Check your project's language skill (defined in the extension file) or CLAUDE.md for the specific commands.
```

Rationale: The Go-first framing implies Go is the expected/primary language. The replacement is neutral and still points to the right sources.

---

### references/phases/phase-5-finalization.md

**Line 36 — Remove language-specific debug statement examples:**

Current:
```markdown
- Debug statements (`console.log`, `fmt.Println` for debugging)
```

Replace with:
```markdown
- Debug statements (language-specific print/log calls used for debugging, not production logging)
```

Rationale: `fmt.Println` is Go-specific. `console.log` is JavaScript. The replacement describes the concept rather than specific functions, which works across any language.

**Lines 61-62 — The summary template uses `.go` file extensions (same fix as phase-1):**

Current:
```markdown
## Changes Made
- `path/to/file1.go`: <what changed>
- `path/to/file2.go`: <what changed>
```

Replace with:
```markdown
## Changes Made
- `path/to/file1`: <what changed>
- `path/to/file2`: <what changed>
```

**Lines 100-105 — Remove `coverage.out` / `coverage.html` Go-specific cleanup:**

Current:
```bash
# Remove wip/ directory (includes context file from Phase 0)
rm -rf wip/

# Remove any coverage output files
rm -f coverage.out coverage.html
```

Replace with:
```bash
# Remove wip/ directory (includes context file from Phase 0)
rm -rf wip/

# Remove any coverage output files generated by your project's test commands
# (e.g., coverage.out, coverage.html, .coverage, lcov.info — varies by language)
```

Rationale: `coverage.out` and `coverage.html` are Go-specific coverage artifact names. The comment makes the pattern explicit without being prescriptive.

---

### references/phases/phase-6-pr.md

**Line 147 — Writing style reference:**

Current:
```markdown
## Writing Style

See the `pr-creation` skill for writing style guidelines. Key: no emojis, no AI references, active voice.
```

Replace with:
```markdown
## Writing Style

See `skills/writing-style/SKILL.md` for writing style guidelines. Key: no emojis, no AI references, active voice.
```

Rationale: `pr-creation` is a tools-internal skill not present in shirabe. The writing-style skill is already in shirabe and is the right reference.

---

### references/scripts/extract-context.sh

This script searches for `docs/DESIGN-*.md` files using a pattern hardcoded to the tsuku design doc naming convention. It also uses `tier` terminology (`simple`, `testable`, `critical`) which maps to the tsuku complexity classification system.

The script is self-contained and functional for any project that uses `DESIGN-*.md` naming and an Implementation Issues table in those docs. It doesn't reference Go or tsuku-specific content beyond naming conventions. The `tier` variable name is an internal variable, not user-visible prose.

**No changes required to this script.** Projects that use different naming conventions will get degraded-mode behavior (issue body as context), which is the intended fallback. This is acceptable for a public plugin.

---

## Helper Reference Changes

### label-reference.md

The SKILL.md currently references `helpers/label-reference.md` at line 37 (within the now-removed blocking labels section). After removing that section, there is no remaining reference to this helper anywhere in the skill. No action needed — the label vocabulary is now delegated to CLAUDE.md `## Label Vocabulary` and extension files.

### writing-style.md

The SKILL.md does not directly reference writing-style. It's referenced in phase-6-pr.md (line 147, updated above). The shirabe path is `skills/writing-style/SKILL.md`.

### private-content.md / public-content.md

Neither file is referenced anywhere in work-on SKILL.md or its phase files. No changes needed here.

---

## Quality Improvements to Make Alongside Migration

### 1. Description — optimize for triggering

The current description is too generic to trigger reliably on natural user input. See proposed description below.

### 2. Clarify the extension hook pattern

After the migration, the SKILL.md will have three places that say "check your extension file." This could be confusing for users who haven't set one up. Add a note in the "Begin" section:

After the updated Begin instruction, add:
```markdown
If no extension file exists at `.claude/shirabe-extensions/work-on.md`, the skill proceeds with generic behavior: no language-specific quality checks, no label blocking (blocking label check is skipped if no label vocabulary is defined in CLAUDE.md).
```

### 3. Phase-2-introspection.md internal skill path

Line 35 contains:
```markdown
- The `issue-introspection` skill path: `../../../../skills/issue-introspection/SKILL.md`
```

This relative path (`../../../../`) assumes the tsukumogami plugin directory layout. In shirabe, the relative path to sibling skills changes. If `issue-introspection` is not bundled with shirabe (it's not one of the five initial skills), this reference will fail.

Replace with a note that the introspection step requires the `issue-introspection` skill from the same plugin, or skip this step if unavailable:

Current line 35:
```markdown
- The `issue-introspection` skill path: `../../../../skills/issue-introspection/SKILL.md`
```

Replace with:
```markdown
- The `issue-introspection` skill path: `${CLAUDE_PLUGIN_ROOT}/skills/issue-introspection/SKILL.md`
```

Using `${CLAUDE_PLUGIN_ROOT}` makes the path plugin-relative, which is the koto infrastructure standard already used elsewhere in the skill (phase-2 uses `${CLAUDE_PLUGIN_ROOT}/skills/issue-staleness/scripts/check-staleness.sh`). This works regardless of where the plugin is installed.

### 4. Milestone input — `M<milestone>` format note

The argument-hint shows `M<milestone>` but the input resolution section only describes `M3`, `M#3`, milestone URL, and `"Milestone Name"`. The `M<milestone>` in the argument-hint is a template variable, not a literal format — this could confuse users. This is a minor clarity issue but not a migration blocker.

---

## Content to Cut Entirely

The following content should be removed with no replacement (already covered above):

1. **Full `needs-triage` jury invocation** (lines 21-33 of SKILL.md) — references two non-shirabe skills (`upstream-context`, `/triage`). Replaced with generic hook.
2. **Full blocking labels table** (lines 43-54 of SKILL.md) — six tsuku-specific labels and routing messages. Replaced with generic delegation pattern.
3. **`helpers/label-reference.md` reference** (line 37 of SKILL.md) — removed as part of the blocking labels section.
4. **`go-development` and `pr-creation` explicit invocations** (line 97 of SKILL.md) — replaced with generic extension hook.
5. **`go-development` conditional skill loading** in phase-3 orchestration — replaced with language-agnostic equivalent.

---

## Proposed New Description

Current:
```
Execute complete feature development workflow for a GitHub issue
```

Proposed:
```
Implement a GitHub issue end-to-end: branch creation, analysis, coding, tests, and pull request with CI monitoring. Use when given an issue number, issue URL, milestone reference, or asked to work on / implement / fix a specific issue. Handles the full cycle from reading the issue to merging a passing PR.
```

Reasoning:
- Opens with what the user gets (branch through PR), not the abstract category ("workflow")
- Lists concrete input forms the user might type: issue number, URL, milestone
- Includes the verb forms users actually say: "work on", "implement", "fix"
- Ends with a concrete scope marker (reading issue through passing CI) so near-misses (e.g., "just create the PR") don't trigger it inappropriately
- Stays under 50 words — short enough to scan, dense enough to trigger on the right inputs

---

## Migration Summary

| File | Lines changed | Type |
|------|--------------|------|
| SKILL.md | +2 (extension slots), ~45 removed, ~15 rewritten | Migration |
| phase-1-setup.md | ~5 lines | Generalization |
| phase-3-analysis.md (orchestration) | ~10 lines | Generalization |
| agent-instructions/phase-3-analysis.md | ~5 lines | Generalization |
| phase-4-implementation.md | ~3 lines | Generalization |
| phase-5-finalization.md | ~6 lines | Generalization |
| phase-6-pr.md | 1 line | Reference fix |
| extract-context.sh | 0 | No change needed |

**Estimated total reduction in SKILL.md:** ~45 lines removed, ~15 lines net new (extension hooks + clarifying notes). Net body size after migration: ~100 lines. Well within the 500-line budget.

**Phase files:** Each has a handful of Go-specific traces. Total cross-file edits are small — roughly 30 lines across 5 files.

**No phase file needs to move to a reference subdirectory.** The existing `references/phases/` structure is already correct progressive disclosure.
