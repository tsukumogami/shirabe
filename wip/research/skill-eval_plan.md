# Skill Evaluation: /plan Migration to shirabe

## Current State Assessment

### Description Quality

Current description (SKILL.md lines 3-6):

```
Implementation planning workflow. Breaks a source document or a directly-
scoped topic into atomic issues with dependency sequencing, complexity levels, and
milestone tracking. Use when decomposing a DESIGN-*.md, PRD-*.md, or ROADMAP-*.md,
or when /explore produced a clear scope with no open decisions remaining.
```

The description names concrete file patterns (`DESIGN-*.md`, `PRD-*.md`, `ROADMAP-*.md`) which is helpful for triggering. However it mentions milestone tracking as a feature without clarifying that milestones are only created in multi-pr mode. More critically, it doesn't mention the direct-topic planning path prominently enough. A user typing "plan out this feature" without a doc path may not trigger the skill.

The skill-creator framework notes that Claude tends to under-trigger and descriptions should be "a little bit pushy." This description is understated. It should also call out the argument-hint patterns more directly.

### Body Length

SKILL.md body: approximately 400 lines (lines 10-400). This is within the 500-line limit but leaves little room for additions. The extension slot lines (`@` references) add 2 lines -- still fine.

### Token Efficiency

The body has several verbosity issues:

1. **Lines 17**: `**Writing style:** Read \`../../helpers/writing-style.md\` for guidance.` -- cross-skill path that must change and is an aside that breaks the opening flow.

2. **Lines 109-137 (Validation Rules by Consumer Phase)**: The section "Validation Rules by Consumer Phase" (~30 lines) partially duplicates information already defined in phase files. The `During /plan Phase 1` and `During /plan Phase 6` subsections belong in those phase files, not in SKILL.md. The `During /work-on` and `During /implement-doc` sections define contract requirements for *other* skills -- these are useful as a quick reference for downstream consumers but add bulk to SKILL.md. Recommend moving this whole section to a reference file.

3. **Lines 362-364 (Roadmap output mode note)**: The `Roadmap input (either mode)` block at the end of the Output section repeats information covered in Decomposition Strategies and Phase 3. It could be cut to one sentence.

4. **Phase Execution (lines 299-334)**: This is clear and well-structured but the table at lines 278-282 and the detailed phase list (lines 303-334) contain significant overlap. The table alone is sufficient; the expanded list adds only the artifact filenames, which could be kept but the prose introductions per phase are redundant.

### Triggering Accuracy

The description would trigger reliably when users provide a doc path. It's less reliable for:

- Users typing "break down this design into issues"
- Users typing "plan the implementation of X"
- Users saying "/plan" with no arguments (asks for input, which is fine)

The `argument-hint` field is well-chosen and will help users who discover the skill via autocomplete.

---

## Migration Changes Required

### SKILL.md Changes

**Line 17** -- Writing style helper reference:

Current:
```markdown
**Writing style:** Read `../../helpers/writing-style.md` for guidance.
```

Replace with:
```markdown
**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.
```

**After frontmatter (after line 8)** -- Add extension slots:

Current (line 8 ends the frontmatter, line 10 begins the body):
```markdown
---

# Plan Skill
```

Replace with:
```markdown
---

@.claude/shirabe-extensions/plan.md
@.claude/shirabe-extensions/plan.local.md

# Plan Skill
```

**Lines 3-6** -- Description (see proposed new description below).

### Phase File Changes

**phase-1-analysis.md, line 96**:

Current:
```markdown
  - Reference to `helpers/label-reference.md` for label definitions
```

Replace with:
```markdown
  - Reference to your project's label vocabulary (see `## Label Vocabulary` in your CLAUDE.md)
```

**phase-3-decomposition.md, line 260**:

Current:
```markdown
- [ ] `needs_label` is a valid label from `helpers/label-reference.md`
```

Replace with:
```markdown
- [ ] `needs_label` is a valid label from your project's label vocabulary (see `## Label Vocabulary` in your CLAUDE.md)
```

**phase-7-creation.md, line 241** -- `transition-status.sh` reference:

Current:
```markdown
${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/transition-status.sh <design-doc-path> Planned
```

This reference is correct for shirabe because `transition-status.sh` lives in the `design` skill within the same plugin. Keep as-is; it uses `${CLAUDE_PLUGIN_ROOT}` which is the portable reference pattern.

**phase-7-creation.md, line 313** -- Upstream issue update prompt:

Current:
```markdown
Is there an upstream issue (e.g., in a private repo) that should be updated to link to these newly created issues?
```

The parenthetical "(e.g., in a private repo)" is project-specific context. Replace with:

```markdown
Is there an upstream issue that should be updated to link to these newly created issues?
```

### References to Remove or Generalize

**plan-doc-structure.md, lines 177 and 331** -- References to `tracks-plan` label and CI validation rule MM21:

The `tracks-plan` label and `MM21` CI rule are project-specific. The label itself (`tracksPlan` Mermaid class and `tracks-plan` GitHub label) is fine to keep as a vocabulary item in the plan-doc-structure reference -- it's a logical concept any consumer might implement. However the reference to "CI enforces this bidirectionally via **MM21**" is internal CI rule naming and should be generalized:

Line 177, current:
```markdown
The `^` prefix distinguishes child reference rows from description rows, making them parseable by CI. Only issues with a tracking label (`tracks-design` or `tracks-plan`) and correspondingly the `tracksDesign` or `tracksPlan` Mermaid class may have a child reference row. CI enforces this bidirectionally via **MM21**: `tracksDesign`/`tracksPlan` nodes must have a child reference row, and nodes without a tracking class must not have one.
```

Replace with:
```markdown
The `^` prefix distinguishes child reference rows from description rows. Only issues with a tracking label (`tracks-design` or `tracks-plan`) and correspondingly the `tracksDesign` or `tracksPlan` Mermaid class may have a child reference row. This invariant is bidirectional: tracking-class nodes must have a child reference row, and nodes without a tracking class must not have one. Projects may enforce this in CI.
```

Line 331, current:
```markdown
### CI Validation Rule MM21

`tracksDesign` and `tracksPlan` nodes must have a corresponding child reference row in the Implementation Issues table. Nodes without a tracking class (`tracksDesign` or `tracksPlan`) must not have a child reference row. CI enforces this bidirectionally.
```

Replace with:
```markdown
### Child Reference Row Invariant

`tracksDesign` and `tracksPlan` nodes must have a corresponding child reference row in the Implementation Issues table. Nodes without a tracking class must not have a child reference row.
```

**label-reference.md, line 23** -- `swap-to-tracking.sh` reference:

Current:
```markdown
4. If `/plan` creates a PLAN document, `tracks-plan` is applied (via `swap-to-tracking.sh`)
```

Replace with:
```markdown
4. If `/plan` creates a PLAN document, `tracks-plan` is applied (invoke your project's label transition script if configured)
```

**label-reference.md** -- Overall: This file is a project-specific label vocabulary. In shirabe, label vocabulary moves to the consumer's CLAUDE.md under a `## Label Vocabulary` section. The `label-reference.md` file should either:

- **Option A (preferred)**: Remove from the skill bundle entirely. Replace all references with "see `## Label Vocabulary` in your CLAUDE.md." Consumers define their own labels.
- **Option B**: Keep as a starter template with a note at the top explaining it's a default vocabulary that consumers should copy into their CLAUDE.md and customize.

Option A is cleaner for a public plugin. The label names (`needs-design`, `needs-prd`, etc.) are documented inline in plan-doc-structure.md's Mermaid classDef blocks, which is sufficient.

**plan-doc-structure.md, lines 40-46** -- Coordinated lifecycle table:

Current:
```markdown
**Coordinated lifecycle with design docs:**

| Design doc | PLAN doc | Trigger |
|------------|----------|---------|
| Accepted | _(doesn't exist)_ | /design or /explore approval |
| Planned | Draft | /plan creates the PLAN artifact |
| Planned | Active | /plan finishes (issues created or /implement-doc starts) |
| Planned | _(updated per issue)_ | Issues implemented via /work-on |
| Current | Done | /complete-milestone (all issues closed) |
```

The trigger column references specific skill names (`/design`, `/explore`, `/complete-milestone`). In shirabe these are real skill names but the table should clarify these are examples:

Replace the Trigger column values with: `design/explore approval`, `/plan creates the PLAN artifact`, `/plan finishes (multi-pr: issues created; single-pr: /implement-doc starts)`, `issues implemented`, `/complete-milestone (all issues closed)`. No prose change needed here -- skill names in a trigger column are accurate for this plugin.

**plan-doc-structure.md, line 159** -- Cutoff date:

Current:
```markdown
Every issue row must have a description row immediately after it (or after the child reference row, if one is present). This is enforced by II07 for design docs created after the cutoff date (2026-02-16).
```

The `II07` rule number and cutoff date are project-internal. Replace:
```markdown
Every issue row must have a description row immediately after it (or after the child reference row, if one is present).
```

---

## Quality Improvements to Make Alongside Migration

### 1. Move "Validation Rules by Consumer Phase" to a reference file

The SKILL.md section "Validation Rules by Consumer Phase" (lines 107-137) defines what downstream consumers validate. This is reference material, not primary workflow guidance. Move it to a new file: `references/quality/consumer-validation-rules.md` and add a line to the reference table:

```
| `references/quality/consumer-validation-rules.md` | When implementing a consuming skill that must validate PLAN artifacts |
```

This saves ~30 lines in SKILL.md.

### 2. Consolidate the Phase Execution section

Lines 299-334 duplicate the phase table at lines 270-282. The expanded phase list adds artifact filenames but uses identical phrasing. Trim the per-phase expanded entries to just the artifact filename (removing the repeated purpose descriptions that appear in the table). This saves ~18 lines.

### 3. Output section cleanup

The Output section (lines 345-364) has three subsections. The "Roadmap input (either mode)" subsection repeats information from Decomposition Strategies. Replace it with a forward reference: "Roadmap input produces planning issues regardless of mode; see Decomposition Strategies above."

---

## Proposed New Description

```
Implementation planning skill. Decomposes a design doc, PRD, roadmap, or directly-stated
topic into atomic, sequenced issues with dependency graphs and complexity classifications.
Use when given a DESIGN-*.md, PRD-*.md, or ROADMAP-*.md to plan, when the user says "break
this design into issues", "plan the implementation", "create issues for this", or when
/explore has produced a clear scope with no open decisions. Also use for direct topic
planning without a source document when the user asks to plan a well-understood set of
capabilities. Produces either a self-contained PLAN doc (single-pr) or GitHub milestone
and issues (multi-pr).
```

This description:
- Adds casual phrasings that trigger on "break this into issues" and "create issues for this"
- Clarifies both output modes so users understand what they get
- Retains the file-pattern triggers
- Explicitly covers the topic-without-document path
- Stays within the description field's practical length

---

## Content That Should Move to a Reference File or Be Cut Entirely

| Content | Location | Recommendation |
|---------|----------|----------------|
| Validation Rules by Consumer Phase | SKILL.md lines 107-137 | Move to `references/quality/consumer-validation-rules.md` |
| `label-reference.md` helper | `helpers/label-reference.md` (referenced from phases) | Remove; consumers define labels in CLAUDE.md `## Label Vocabulary` |
| `swap-to-tracking.sh` specific reference | `label-reference.md` line 23 | Replace with generic instruction |
| CI rule names (MM21, II07) | `plan-doc-structure.md` lines 177, 159, 331 | Remove rule codes, keep rule descriptions |
| Cutoff date (2026-02-16) | `plan-doc-structure.md` line 159 | Remove; the description row requirement is unconditional in shirabe |
| "(e.g., in a private repo)" | `phase-7-creation.md` line 313 | Remove parenthetical |
| `../../helpers/writing-style.md` path | `SKILL.md` line 17 | Replace with `skills/writing-style/SKILL.md` |
| `helpers/label-reference.md` path | `phase-1-analysis.md` line 96, `phase-3-decomposition.md` line 260 | Replace with CLAUDE.md reference |

### What Is Already Generic and Can Stay Unchanged

- All seven phase files except the specific lines noted above: solid, generalized workflow logic
- The walking skeleton / horizontal decomposition decision framework
- The execution mode selection heuristics
- All script references using `${CLAUDE_SKILL_DIR}` or `${CLAUDE_PLUGIN_ROOT}` (already portable)
- The Mermaid classDef vocabulary and syntax rules
- The complexity classification table (simple / testable / critical)
- The placeholder convention (`<<ISSUE:N>>`)
- The resume logic (wip/ artifact detection)
- The plan-doc-structure.md examples (generic enough; "Homebrew Builder" example works as an illustration without being project-specific)
