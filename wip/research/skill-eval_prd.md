# Migration Evaluation: /prd Skill

Source: `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/skills/prd/`
Target: shirabe public plugin

---

## Current State Assessment

### File inventory

| File | Lines |
|------|-------|
| `SKILL.md` | 340 |
| `references/phases/phase-1-scope.md` | 118 |
| `references/phases/phase-2-discover.md` | 182 |
| `references/phases/phase-3-draft.md` | 161 |
| `references/phases/phase-4-validate.md` | 250 |
| **Total** | **1,051** |

### SKILL.md body length

At 340 lines, SKILL.md is within the 500-line budget. After the extension slot lines
are added and project-specific content is removed, the body will shrink slightly. No
restructuring needed to stay under budget.

### Description quality

Current description (SKILL.md frontmatter, lines 3-6):

```
description: PRD structure, validation rules, lifecycle, and creation workflow.
  Use when writing, reviewing, validating, or transitioning docs/prds/PRD-*.md
  files, or when creating new PRDs via /prd.
```

Issues:
- The path pattern `docs/prds/PRD-*.md` is a project convention, not a universal path.
  It helps trigger for this project but will fail to trigger for users whose PRDs live
  elsewhere (e.g., `requirements/`, `specs/`, root level).
- "transitioning" is vague -- the description doesn't name the lifecycle states, so
  it won't trigger when a user says "mark this PRD as accepted."
- Missing: no mention of the multi-phase research workflow, which is the most
  distinguishing feature. A user who types "help me do requirements discovery for X"
  won't see a match.
- "via /prd" is circular -- users don't know the skill name yet when triggering.
- Under-triggers on natural language like "write requirements for," "define the scope
  of," "what should we build for," or "draft a spec."

### Token efficiency

The body is well-organized. Most content is necessary. Two areas have efficiency
problems:

1. **Label Lifecycle section (SKILL.md lines 108-133)**: ~26 lines describing GitHub
   label mechanics tied to tsukumogami's internal `/triage` and `/plan` skills. This
   is project-specific wiring, not generic PRD workflow. Must be removed or moved to
   an extension slot.

2. **Repo Visibility section (SKILL.md lines 224-230)**: References
   `../../helpers/private-content.md` and `../../helpers/public-content.md` via
   relative paths into a private plugin. These paths are wrong outside tsukumogami.
   Must be updated to shirabe skill references.

3. **helper references throughout**: Three helpers are referenced by relative path --
   all need updating.

4. **Common Pitfalls bullet (line 201)**: "Too broad ('Improve tsuku')" -- names the
   tsuku project directly. Must be generalized.

5. **phase-2-discover.md line 143**: References
   `../../../../helpers/decision-presentation.md` -- four levels up, into the
   tsukumogami plugin tree. Must be updated.

6. **phase-3-draft.md line 72**: Same helper path issue: `../../helpers/decision-presentation.md`.

7. **phase-4-validate.md lines 201-208**: The `needs-prd` label removal step and the
   `swap-to-tracking.sh` script reference (from SKILL.md lines 130-133) are wired to
   tsukumogami's label vocabulary. The label removal in phase-4-validate.md (lines
   201-207) is acceptable as a generic GitHub label workflow (it reads `source_issue`
   from frontmatter). The swap script reference in SKILL.md is the problematic part.

8. **Internal skill references**: SKILL.md references `/triage`, `/plan`,
   `/work-on`, `/just-do-it` as internal skill paths. These need to become generic
   references without internal path syntax.

9. **Downstream routing table (SKILL.md lines 218-220)**: Refers to `/plan` and
   `/implement` as internal skills. These are fine as generic workflow names but
   shouldn't use slash-command syntax that implies a specific plugin.

---

## Migration Changes Required

### SKILL.md

**Line 3-6: Description** -- Replace (see Proposed New Description below)

**After frontmatter (after line 7)** -- Add extension slots:

```
@.claude/shirabe-extensions/prd.md
@.claude/shirabe-extensions/prd.local.md
```

**Line 15: writing-style helper** -- Replace:

```
**Writing style:** Read `../../helpers/writing-style.md` for guidance.
```

with:

```
**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.
```

**Lines 108-133: Label Lifecycle section** -- Remove entirely. This block is
project-specific wiring between `/triage`, `/plan`, and an internal label vocabulary.
The generic PRD workflow doesn't prescribe label names. The `source_issue` frontmatter
field and the Phase 4 label-removal step (phase-4-validate.md lines 201-207) can
remain -- they describe a reasonable general pattern. What must go is:

- The explanation of how `/triage` assigns `needs-prd` (lines 113-115)
- The `needs-prd -> tracks-plan` transition description (lines 122-128)
- The swap script reference (lines 130-133)
- The label reference helper link (lines 111-112)

The section title and transition trigger description (lines 108-126) should be
reduced to: the `source_issue` field is optional and, if set, the agent will
remove a corresponding label from the issue on acceptance. This keeps the generic
behavior without naming specific labels.

**Lines 113-115** (full text to remove):

```
**Trigger:** `/triage` (two-stage jury) assigns `needs-prd` when requirements are
unclear or contested -- the issue needs requirements definition before design or
implementation can begin.
```

**Lines 122-128** (full text to remove):

```
3. **needs-prd -> tracks-plan:** When the PRD leads to a plan, `/plan` Phase 7 calls
   `swap-to-tracking.sh`, which removes `needs-prd` and applies `tracks-plan`. The
   `tracksPlan` Mermaid class replaces `needsPrd` in any parent diagram.
```

**Lines 130-133** (full text to remove):

```
**Label swap script** (called by /plan Phase 7):
```bash
${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/swap-to-tracking.sh <issue-number> [--repo <owner/repo>]
```
```

**Lines 111-112** (full text to remove):

```
Issues labeled `needs-prd` follow a label lifecycle that connects triage to artifact
creation and optional plan tracking. See `../../helpers/label-reference.md`
for the complete label vocabulary and triage routing rules.
```

**Line 201: tsuku-specific pitfall example** -- Replace:

```
- Too broad ("Improve tsuku") -- narrow to specific capability
```

with:

```
- Too broad ("Improve the app") -- narrow to a specific capability or user need
```

**Lines 224-230: Repo Visibility section** -- Replace helper paths:

```
- **Private repos:** Read `../../helpers/private-content.md`
- **Public repos:** Read `../../helpers/public-content.md`
```

with:

```
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`
```

**Line 103: Lifecycle table row** -- The reference to `/design`, `/plan`, and
`/work-on` as status transition triggers:

```
| In Progress | Being implemented via /design, /plan, or /work-on | Downstream workflow started |
```

This is acceptable -- it uses generic workflow names, not internal paths. No change
needed.

**Lines 218-220: Downstream routing table** -- The table references `/plan`,
`/implement`, and `/design` with slash-command syntax:

```
| Simple | PRD -> /plan -> /implement |
| Medium | PRD -> /plan -> /implement |
| Complex | PRD -> /design -> design doc -> /plan -> /implement |
```

Replace with generic workflow names to avoid implying specific internal plugins:

```
| Simple | PRD -> plan -> implement |
| Medium | PRD -> plan -> implement |
| Complex | PRD -> design -> design doc -> plan -> implement |
```

**Lines 325-330: Output routing options** -- Same issue with slash-command syntax:

```
| Simple (clear requirements, few moving parts) | `/plan` |
| Medium (needs issue breakdown) | `/plan` |
| Complex (needs technical design first) | `/design` |
```

Replace:

```
| Simple (clear requirements, few moving parts) | plan skill |
| Medium (needs issue breakdown) | plan skill |
| Complex (needs technical design first) | design skill |
```

**Lines 241-242: Unlike /explore reference** -- This sentence reads:

```
Unlike `/explore` (which is open-ended and can produce any artifact type), `/prd`
always produces a PRD. Use `/prd` when you know you need requirements definition.
Use `/explore` when you don't know what artifact type you need.
```

In shirabe, `/explore` is a sibling skill. The cross-skill reference is fine as a
generic mention. Change slash-command syntax to generic names:

```
Unlike an explore workflow (which is open-ended and can produce any artifact type),
/prd always produces a PRD. Use /prd when you know you need requirements definition.
Use an explore workflow when you don't know what artifact type you need yet.
```

**Lines 214-216: Complexity routing in Phase 4 note** -- "Suggest `/work-on` or
`/just-do-it`" (phase-4-validate.md line 212) -- these are internal skill names.
See phase-4-validate.md changes below.

---

### phase-2-discover.md

**Line 143: decision-presentation helper** -- Replace:

```
Present the loop decision using AskUserQuestion
following the pattern in `../../../../helpers/decision-presentation.md`.
```

with:

```
Present the loop decision using AskUserQuestion
following the pattern in `references/decision-presentation.md`.
```

---

### phase-3-draft.md

**Line 72: decision-presentation helper** -- Replace:

```
Read `../../helpers/decision-presentation.md` for how to structure decisions.
```

with:

```
Read `references/decision-presentation.md` for how to structure decisions.
```

---

### phase-4-validate.md

**Lines 201-207: needs-prd label removal** -- This is acceptable generic behavior
(the agent reads `source_issue` from frontmatter and removes a label). The label
name `needs-prd` is generic enough. No change needed.

**Line 212: Internal skill names in routing** -- Replace:

```
- **Simple** (few requirements, clear scope, could be a single PR): Suggest `/work-on`
  or `/just-do-it`
- **Medium** (multiple requirements, needs issue breakdown): Suggest `/plan`
- **Complex** (needs technical design decisions): Suggest `/design`
```

with:

```
- **Simple** (few requirements, clear scope, could be a single PR): Suggest direct
  implementation
- **Medium** (multiple requirements, needs issue breakdown): Suggest a planning
  workflow
- **Complex** (needs technical design decisions): Suggest a design workflow first
```

**Quality Checklist line 241** -- "needs-prd label removed from source issue" is
acceptable as a generic pattern. No change needed.

---

## Quality Improvements to Make Alongside Migration

### 1. Description: add a `references/decision-presentation.md` file

The phase files reference `references/decision-presentation.md` after migration. This
file needs to exist in the shirabe prd skill tree. It should contain the pattern for
presenting decisions with a recommendation, alternatives, and reasoning -- the same
content currently in the tsukumogami helper, but as a bundled reference.

### 2. Phase 4 routing: remove internal skill coupling entirely

The routing suggestions in Phase 4 currently name internal skills. After generalizing,
the agent should describe the *type* of next step, not a specific skill name. Users
will have their own plugin ecosystem.

### 3. Lifecycle table: `source_issue` documentation

The `source_issue` frontmatter field (line 35 in SKILL.md) is described as "GitHub
issue number that triggered this PRD, used for label management." After removing the
Label Lifecycle section, this description should be simplified: "GitHub issue number
that triggered this PRD." The "used for label management" rationale should move into
the frontmatter field comment or the Validation section.

### 4. No new files needed in SKILL.md body

The body size is healthy (340 lines, well under 500). No restructuring of the three-
level loading hierarchy is needed. The progressive disclosure works: SKILL.md covers
structure, lifecycle, validation, and workflow orchestration, while the phase files
carry the detailed execution instructions.

---

## Proposed New Description

The current description under-triggers on natural-language entry points. The new
description adds: the multi-phase discovery workflow, common natural-language triggers,
and lifecycle transitions -- without over-specifying paths.

```
description: >-
  Structured workflow for creating and managing Product Requirements Documents (PRDs).
  Use this skill when writing new PRDs, reviewing or validating existing ones, or
  transitioning a PRD through its lifecycle (Draft -> Accepted -> In Progress -> Done).
  Trigger on prompts like: "write requirements for X", "define scope for Y", "draft a
  spec", "what should we build for Z", "I need a PRD", "validate this PRD", "mark this
  PRD as accepted", or any request to define WHAT to build and WHY before implementation
  begins. This skill drives a multi-phase workflow: conversational scoping, parallel
  research agents, structured drafting, and a 3-agent jury review.
```

This description:
- Names the skill's artifact clearly (PRD)
- Covers lifecycle transitions so it triggers on status changes
- Lists realistic natural-language entry points
- Calls out the multi-phase workflow (distinguishes it from simple doc writing)
- Avoids path patterns that don't generalize

---

## Content That Should Be Cut or Moved

### Cut entirely

- **Label Lifecycle section** (SKILL.md lines 108-133, ~26 lines): The `needs-prd`
  label, the swap script, the reference to `helpers/label-reference.md`, and the
  description of how `/triage` assigns labels. This is pure tsukumogami internal
  wiring. The generic behavior (remove a label on acceptance if `source_issue` is set)
  is already described in phase-4-validate.md and needs no section of its own.

- **Tsuku-specific pitfall** (SKILL.md line 201, 1 line): "Too broad ('Improve
  tsuku')" -- replace with a generic project name.

### Move to extension slot (not in base skill)

- Any project-specific label vocabulary (`needs-prd`, `tracks-plan`)
- Project-specific downstream skill names (`/triage`, `/work-on`, `/just-do-it`)
- Project-specific path conventions beyond `docs/prds/` (which is already generic
  enough to keep)

### Keep as-is

- The `docs/prds/PRD-<name>.md` file location convention -- this is a reasonable
  default that users can override via extension
- The `source_issue` frontmatter field -- useful generic pattern for any GitHub-based
  workflow
- The `needs-prd` label in phase-4-validate.md step 4.6 -- it's illustrative and the
  step is clearly conditional on `source_issue` being set
- All phase file structure and content beyond the helper path references
- The lifecycle states (Draft, Accepted, In Progress, Done) -- these are generic
- The 3-agent jury validation pattern -- this is the skill's core differentiator

---

## Summary of All Changes by File

### SKILL.md (net: ~26 lines removed, 2 extension lines added)

| Location | Change |
|----------|--------|
| Lines 3-6 (description) | Replace with expanded description (see above) |
| After line 7 (frontmatter end) | Add 2 extension slot lines |
| Line 15 | `../../helpers/writing-style.md` -> `skills/writing-style/SKILL.md` |
| Lines 108-133 (Label Lifecycle) | Remove section entirely (~26 lines) |
| Line 201 | `"Improve tsuku"` -> `"Improve the app"` |
| Lines 218-220 | Remove `/` prefix from skill names in routing table |
| Lines 224-228 | `../../helpers/private-content.md` / `public-content.md` -> `skills/private-content/SKILL.md` / `skills/public-content/SKILL.md` |
| Lines 241-242 | Remove `/` prefix from `/explore` references |
| Lines 325-330 | Remove `/` prefix from skill names in routing table |

### phase-2-discover.md (net: 1 line changed)

| Location | Change |
|----------|--------|
| Line 143 | `../../../../helpers/decision-presentation.md` -> `references/decision-presentation.md` |

### phase-3-draft.md (net: 1 line changed)

| Location | Change |
|----------|--------|
| Line 72 | `../../helpers/decision-presentation.md` -> `references/decision-presentation.md` |

### phase-4-validate.md (net: 3 lines changed)

| Location | Change |
|----------|--------|
| Line 212-214 | Replace `/work-on`, `/just-do-it`, `/plan`, `/design` with generic descriptions |

### New file required

| File | Purpose |
|------|---------|
| `references/decision-presentation.md` | Pattern for presenting decisions with recommendation + alternatives. Copy from tsukumogami helpers, removing any project-specific examples. |
