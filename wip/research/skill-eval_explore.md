# Skill Evaluation: /explore — Migration to shirabe

## Current State Assessment

### Description

Current description (SKILL.md lines 3–5):
```
Artifact type selection framework and freeform exploration workflow.
  Use when advising which command or artifact type fits a situation, or when running
  structured exploration via /explore.
```

**Issues:**
- Generic but slightly vague — "artifact type selection framework" is accurate but not evocative enough to reliably trigger. A user who types "I don't know whether to write a PRD or a design doc" or "help me figure out what to build" might not obviously map their intent to this description.
- The phrase "when advising which command or artifact type fits a situation" implies a passive/advisory role. Skill-creator guidance warns against undertriggering — the description should be "a little pushy."
- No explicit list of user phrasings that should trigger it. The description catches `/explore` invocations reliably but may miss natural-language entry points like "I don't know where to start" or "should I write a PRD or a design doc first?"

### Body length

SKILL.md: 453 lines. The skill-creator guideline is <500 lines, with a note to add hierarchy and pointers when approaching the limit. At 453 lines, the skill is near that ceiling. It's structured well — uses deferred loading for the phase files — but the body has some density that could be trimmed.

Phase files total an additional 1,537 lines. These are already correctly organized as bundled references loaded on demand.

### Token efficiency

The body carries several sections that are well-structured but could be more concise:

1. **Handoff Artifact Formats** (SKILL.md lines 127–219): This section duplicates content from Phase 5 (`phase-5-produce.md`). The full handoff templates — for `/prd`, `/design`, `/plan`, and "no artifact" — live in the phase file with more detail. In SKILL.md, the abbreviated versions don't add enough beyond what the phase file provides. These templates occupy ~90 lines in SKILL.md. The summary table at lines 419–428 plus a single pointer to `phase-5-produce.md` would do the same job.

2. **Crystallize Framework Summary** (lines 52–73): Reasonable summary. The table is useful as a quick reference before Phase 4 loads the full framework. Keep.

3. **Lead Conventions** (lines 74–95): Good content. Keep.

4. **Convergence Patterns** (lines 97–119): Good content. Keep.

5. **wip/ Artifact Naming** (lines 380–428): The naming tables are valuable for the orchestrator. The decisions file format block (lines 393–416) is detailed and could move to a reference file, but it's under 25 lines and the orchestrator needs it inline. Keep.

6. **Output** section (lines 430–439): Four bullet points restate what Phase 5 already covers. Cut or reduce to a one-line pointer.

---

## Migration Changes Required

### 1. Extension slot lines (add immediately after frontmatter)

After the closing `---` of the YAML frontmatter (currently line 7), add two lines:

```
@.claude/shirabe-extensions/explore.md
@.claude/shirabe-extensions/explore.local.md
```

Full frontmatter block becomes:
```
---
name: explore
description: <new description — see below>
argument-hint: '<topic or issue number>'
---

@.claude/shirabe-extensions/explore.md
@.claude/shirabe-extensions/explore.local.md
```

### 2. Replace `helpers/writing-style.md` reference

**Line 19:**
```
**Writing style:** Read `../../helpers/writing-style.md` for guidance.
```

Replace with:
```
**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.
```

Note: the path `skills/writing-style/SKILL.md` is relative to the shirabe plugin root, which is how cross-skill references resolve in the shirabe context. The writing-style skill already exists at `/home/dangazineu/dev/workspace/tsuku/tsuku-5/public/shirabe/skills/writing-style/SKILL.md`.

### 3. Replace `helpers/decision-presentation.md` references

There are two references to this helper:

**SKILL.md line 352:**
```
following the pattern in `../../helpers/decision-presentation.md`.
```

Replace with:
```
following the pattern in `references/decision-presentation.md`.
```

**phase-3-converge.md line 84:**
```
Follow the guidance in `../../helpers/decision-presentation.md` for how to frame
recommendations without false neutrality.
```

Replace with:
```
Follow the guidance in `references/decision-presentation.md` for how to frame
recommendations without false neutrality.
```

**phase-5-produce.md line 227:**
```
`../../../../helpers/decision-presentation.md`.
```

Replace with:
```
`references/decision-presentation.md`.
```

This requires a `references/decision-presentation.md` file in the shirabe explore skill directory (copy from `helpers/decision-presentation.md` in tsukumogami).

### 4. Replace `helpers/label-reference.md` reference (phase-0-setup.md)

**phase-0-setup.md line 11:**
```
**Label vocabulary reference:** `../../../../helpers/label-reference.md`
```

The `label-reference.md` helper is project-specific — it documents tsukumogami's label vocabulary (`needs-triage`, `needs-design`, etc.). This content is not project-specific in concept, but the labels themselves are part of the shirabe workflow system. Two options:

- **Option A (preferred):** Move the label vocabulary to a `references/label-reference.md` file within the explore skill. Replace the path reference accordingly:
  ```
  **Label vocabulary reference:** `references/label-reference.md`
  ```
  The content of `label-reference.md` is appropriate to ship with shirabe — it defines the shared vocabulary for the artifact workflow system.

- **Option B:** Remove the reference and inline the key vocabulary in the Phase 0 file itself. Heavier edit, not necessary.

### 5. Remove cross-repo issue example with tsukumogami/tsuku hard-coded org name

**SKILL.md lines 237–240** (Input Detection section):
```
For cross-repo issues (e.g., `tsukumogami/tsuku#42`), use `gh` commands:
```bash
gh issue view 42 --repo tsukumogami/tsuku --json title,body,labels
```
```

The example is merely illustrative — the instruction itself is generic. Replace the org/repo names with placeholders:

```
For cross-repo issues (e.g., `owner/repo#42`), use `gh` commands:
```bash
gh issue view 42 --repo owner/repo --json title,body,labels
```
```

### 6. Remove Competitive Analysis matrix referencing "Tsuku"

**phase-5-produce.md lines 500–505** (Comparative Matrix template):
```
| Dimension | Tsuku | <Competitor 1> | <Competitor 2> |
|-----------|-------|----------------|----------------|
| <dim 1> | | | |
| <dim 2> | | | |
```

Replace `Tsuku` with a generic placeholder:
```
| Dimension | <Our product> | <Competitor 1> | <Competitor 2> |
|-----------|---------------|----------------|----------------|
| <dim 1> | | | |
| <dim 2> | | | |
```

### 7. Replace `upstream-context` skill invocation in phase-0-setup.md

**phase-0-setup.md line 46:**
```
invoke the upstream-context skill (`../../../upstream-context/SKILL.md`) to gather context from
upstream strategic issues and design docs. Then proceed to Phase 1.
```

And line 197:
```
If the chosen type is `needs-design`, invoke the upstream-context skill, then proceed to Phase 1.
```

The `upstream-context` skill is a tsukumogami-specific cross-skill invocation. If `upstream-context` is not being migrated alongside `/explore`, this step becomes a gap. Two options:

- **Option A (if upstream-context migrates to shirabe):** Update the path to match the shirabe skill path.
- **Option B (if upstream-context does NOT migrate):** Replace with a generic instruction to gather context from upstream issues and design docs without invoking a named skill:

  ```
  Gather context from upstream strategic issues and design docs by reading any
  linked issues, related design docs referenced in the issue body, and upstream
  artifacts noted in the codebase. Then proceed to Phase 1.
  ```

  And on line 197:
  ```
  If the chosen type is `needs-design`, gather upstream context from linked issues and
  existing design docs before proceeding to Phase 1.
  ```

This is the most substantive migration decision. The label-reference and upstream-context are the two places where tsukumogami's project scaffolding bleeds through.

### 8. Replace `prd`, `design`, `plan`, `roadmap`, `spike-report`, `decision-record` skill path references in phase-5-produce.md

Multiple steps in `phase-5-produce.md` reference sibling skills via relative paths like `../../../prd/SKILL.md`, `../../../design/SKILL.md`, etc. These work only if those skills are co-installed in the same plugin.

- **Lines 88–89:** `../../../prd/SKILL.md` → should reference wherever the /prd skill lives in shirabe
- **Lines 152–153:** `../../../design/SKILL.md`
- **Lines 248:** `../../../roadmap/SKILL.md`
- **Lines 310:** `../../../spike-report/SKILL.md`
- **Lines 379:** `../../../decision-record/SKILL.md`
- **Lines 466:** `../../../competitive-analysis/SKILL.md`

If these skills ship as part of shirabe, the paths stay correct (assuming same directory structure). If they don't ship, the references should be softened to instructions like "Read the /prd skill if available" or the handoff instructions should describe the expected artifact format without relying on a live skill read.

This is a structural decision for the shirabe migration roadmap, not a line-level fix. Flag it as a dependency.

---

## Quality Improvements to Make Alongside Migration

### 1. Trim the Handoff Artifact Formats section in SKILL.md

The section at lines 127–219 (~90 lines) provides abbreviated handoff templates that are already fully specified in `phase-5-produce.md`. Reduce to a summary:

**Proposed replacement for the entire "Handoff Artifact Formats" section:**

```markdown
## Handoff Artifact Formats

When /explore crystallizes to a target type, Phase 5 writes artifacts matching
that command's expected format. The full templates live in `references/phases/phase-5-produce.md`.

Summary of handoffs by target:

| Target | Handoff artifact(s) |
|--------|---------------------|
| /prd | `wip/prd_<topic>_scope.md` |
| /design | `docs/designs/DESIGN-<topic>.md` + `wip/design_<topic>_summary.md` |
| /plan | None (user runs `/plan <topic>` directly) |
| No artifact | None (summarize findings, suggest next steps) |
| Roadmap, Spike, ADR, Competitive Analysis | Produced directly in Phase 5 |

Do NOT delete wip/ research files after routing. The target skill's phases may
reference them. Cleanup happens when the target workflow completes or when the
user runs `/cleanup`.
```

This removes ~75 lines from the SKILL.md body while losing no information (Phase 5 has the full templates).

### 2. Trim the "Output" section

**Lines 430–439:**
```markdown
### Output

After Phase 5 completes, /explore has either:

1. **Handed off to /prd** -- session continues in /prd workflow at Phase 2
2. **Handed off to /design** -- session continues in /design workflow at Phase 1
3. **Told user to run /plan** -- user runs `/plan <artifact-path>` in a new session
4. **Suggested no artifact** -- user acts directly (issue, /work-on, or revisit later)

The exploration research files remain in wip/ for the target workflow to use.
```

This is a trailing summary of what's already described. Cut entirely or reduce to one line appended to the workflow phase table.

---

## Proposed New Description

The current description undertriggers on natural-language entry points. Proposed replacement:

```
Structured exploration workflow and artifact-type routing advisor. Use when the
user isn't sure what to build, doesn't know which workflow fits their situation,
or wants to research before committing to a PRD, design doc, or plan. Also triggers
on explicit /explore invocations and on questions like "should I write a PRD or a
design doc?" or "I don't know where to start." Runs a discover-converge loop with
research agents, then recommends the right artifact type based on findings.
```

**What changed:**
- Added explicit example phrases ("should I write a PRD or a design doc?", "I don't know where to start") that a user would naturally say
- Named the mechanism (discover-converge loop with research agents) so the model understands the depth of commitment
- Added the advisory role explicitly alongside the active workflow role
- More specific about what it produces (artifact type recommendation based on findings)

---

## Content to Move to a Reference File or Cut

### Move to `references/decision-presentation.md`

The `decision-presentation.md` content from tsukumogami's `helpers/` directory should be copied verbatim to `references/decision-presentation.md` within the explore skill bundle. Both SKILL.md and phase files reference it; it's load-on-demand, not always-in-context, which is the right model for a reference file.

### Move label vocabulary to `references/label-reference.md`

Same treatment as decision-presentation. The label vocabulary defines the shared contract for the workflow system. It belongs in references/ inside the explore skill bundle.

### Cut from SKILL.md body

| Section | Lines | Recommendation |
|---------|-------|----------------|
| Handoff Artifact Formats (full templates) | 127–219 (~90 lines) | Replace with summary table + pointer to phase-5-produce.md |
| Output (trailing summary) | 430–439 (~10 lines) | Cut entirely |

Net reduction: ~100 lines, bringing SKILL.md from 453 to ~353 lines. Well within the <500 guideline and with comfortable room for growth.

### Do not cut

- Crystallize Framework Summary (lines 52–73) — useful quick reference before Phase 4
- Lead Conventions (lines 74–95) — orchestrator needs this inline
- Convergence Patterns (lines 97–119) — orchestrator needs this inline
- Phase execution instructions (lines 337–378) — the orchestrator's core loop
- wip/ Artifact Naming (lines 380–428) — naming conventions needed inline

---

## Summary of Required Changes by File

| File | Change | Type |
|------|--------|------|
| `SKILL.md` | Add extension slot lines after frontmatter | Migration |
| `SKILL.md` | Update description | Quality + Migration |
| `SKILL.md` | Replace `../../helpers/writing-style.md` → `skills/writing-style/SKILL.md` | Migration |
| `SKILL.md` | Replace `../../helpers/decision-presentation.md` → `references/decision-presentation.md` | Migration |
| `SKILL.md` | Replace `tsukumogami/tsuku#42` example → `owner/repo#42` | Migration |
| `SKILL.md` | Trim Handoff Artifact Formats section to summary table | Quality |
| `SKILL.md` | Cut trailing Output section (lines 430–439) | Quality |
| `phase-0-setup.md` | Replace `../../../../helpers/label-reference.md` → `references/label-reference.md` | Migration |
| `phase-0-setup.md` | Replace upstream-context skill invocation (lines 46, 197) | Migration (dependency) |
| `phase-3-converge.md` | Replace `../../helpers/decision-presentation.md` → `references/decision-presentation.md` | Migration |
| `phase-5-produce.md` | Replace `../../../../helpers/decision-presentation.md` → `references/decision-presentation.md` | Migration |
| `phase-5-produce.md` | Replace `Tsuku` in Comparative Matrix template → `<Our product>` | Migration |
| `phase-5-produce.md` | Review sibling skill paths (`../../../prd/SKILL.md` etc.) | Migration (dependency) |
| `references/decision-presentation.md` | Create — copy from tsukumogami helpers | Migration |
| `references/label-reference.md` | Create — copy from tsukumogami helpers | Migration |
