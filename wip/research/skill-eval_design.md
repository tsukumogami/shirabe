# Skill Evaluation: /design Migration to shirabe

**Source:** `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/skills/design/`
**Target:** shirabe public plugin
**Date:** 2026-03-17

---

## Current State Assessment

### Description

Current frontmatter:

```yaml
name: design
description: Design document structure, validation rules, lifecycle, and creation
  workflow. Use when writing, reviewing, validating, or transitioning
  docs/designs/DESIGN-*.md files, or when creating new design documents via /design.
argument-hint: '<PRD path or topic>'
```

**Problems with the current description:**

1. It leads with structure/rules rather than the workflow action users invoke. Someone typing `/design authentication overhaul` doesn't think "I need design document structure and validation rules."

2. The file-path hint (`docs/designs/DESIGN-*.md`) is project-specific. External consumers won't know to use that path pattern until they've already read the skill body.

3. It doesn't mention the expansion-contraction workflow (multi-agent advocate pattern), which is the skill's most distinctive feature and the strongest reason to trigger it. A user asking Claude to "research three approaches to X and help me pick one" would benefit from this skill, but the description doesn't signal that.

4. "via /design" is circular — it's in the description of the /design skill.

5. It under-triggers. Someone who says "help me decide how to implement versioned configuration" won't hit this skill because the description focuses on the artifact format rather than the decision-making workflow.

### Body Length

SKILL.md: **340 lines** — well under the 500-line guideline. No progressive disclosure concerns.

Phase files (loaded on demand): 112 + 123 + 161 + 143 + 158 + 136 + 157 + 216 = **1,206 lines** across 8 files. This is appropriate — phases are loaded one at a time and the total is never in context simultaneously.

The 340-line body includes ~65 lines of project-specific content that will be removed, bringing the migrated skill to ~275 lines. That's lean.

### Token Efficiency

The body is generally efficient. The main inefficiency is the Label Lifecycle section (lines 113–161, ~49 lines): it reads like operational documentation for a specific GitHub label setup, complete with Mermaid class names and bash script syntax. This content is simultaneously too detailed (tsuku-specific) and too thin (doesn't help generic users). Removing it doesn't leave a gap that needs filling for external consumers; it just removes a tsuku-specific workflow integration that belongs in an extension file.

The security section (lines 193–208, ~16 lines) is similarly efficient as tsuku-specific guidance but becomes noise for external users who don't build package managers.

The cross-references to `../../helpers/` paths need updating but otherwise carry their weight.

### Structure Quality

The document has good layering: frontmatter → structure rules → lifecycle → validation → quality guidance → workflow creation section → reference table. The "Creating a Design Document" section cleanly separates reference information (the first half) from workflow invocation (the second half). This is the right split.

The `## Repo Visibility` section (lines 221–227) is only 7 lines and carries important guidance: "before writing content, determine visibility." It's worth keeping in some form but the helper paths will change.

---

## Migration Changes Required

### 1. Add extension slot lines after frontmatter (SKILL.md, after line 7)

**Insert after line 7** (the closing `---` of frontmatter):

```
@.claude/shirabe-extensions/design.md
@.claude/shirabe-extensions/design.local.md
```

These give consumers a hook to inject project-specific content (tsuku's security dimensions, label lifecycle, etc.) without modifying the base skill.

---

### 2. Update writing-style helper reference (SKILL.md, line 15)

**Current (line 15):**
```
**Writing style:** Read `../../helpers/writing-style.md` for guidance.
```

**Replace with:**
```
**Writing style:** Read the `writing-style` skill for guidance.
```

Rationale: In shirabe, writing-style is a peer skill (`skills/writing-style/SKILL.md`), not a helper file in a `helpers/` directory. The skill reference pattern avoids a fragile relative path.

---

### 3. Remove tsuku-specific "NEVER empty for tsuku" qualifier (SKILL.md, line 68)

**Current (line 68):**
```
8. **Security Considerations** -- NEVER empty for tsuku (see Security below)
```

**Replace with:**
```
8. **Security Considerations** -- always include; see Security Considerations guidance below
```

Rationale: The absolute prohibition is still worth signaling, but "for tsuku" is a project qualifier that doesn't belong in the base. The redirect keeps the link to the quality guidance section.

---

### 4. Remove `planning-context` skill reference (SKILL.md, line 71)

**Current (line 71):**
```
Additional sections based on scope and visibility (use the `planning-context` skill):
```

**Replace with:**
```
Additional sections based on scope and visibility (detect from CLAUDE.md `## Repo Visibility:` and `## Planning Context:` fields):
```

Rationale: `planning-context` is a tools-internal skill not packaged in shirabe. The detection mechanism is already described in the Context Resolution section of the workflow; pointing directly to CLAUDE.md fields is both accurate and generic.

---

### 5. Remove the tsuku-specific Security section (SKILL.md, lines 193–208)

**Current (lines 193–208):**
```markdown
### Security (tsuku-specific)

Security Considerations must address four dimensions:
- **Download verification** -- how binaries are validated
- **Execution isolation** -- required permissions, escalation risks
- **Supply chain risks** -- source trust, upstream compromise
- **User data exposure** -- local data accessed, data transmitted

Each dimension needs analysis OR explicit "Not applicable" with justification.
Never blank or bare "N/A".
```

**Replace with:**
```markdown
### Security Considerations

The Security Considerations section must not be empty. For each dimension that
applies to the design, document risks and mitigations. For dimensions that don't
apply, write a brief explicit justification ("Not applicable because this design
only produces markdown files and executes no external code").

Consumer projects should define domain-specific security dimensions in their
extension file (`@.claude/shirabe-extensions/design.md`).
```

Rationale: The base skill should mandate a non-empty section and explain the N/A justification pattern, but the specific four dimensions (download verification, execution isolation, supply chain, user data) are tsuku-specific. A project building a design tool, a CLI, or a web app would have different dimensions.

---

### 6. Update Common Pitfalls section (SKILL.md, lines 204–208)

**Current (lines 204–208):**
```markdown
### Common Pitfalls
- Too broad ("Improve tsuku") -- narrow to specific capability
- Strawman options -- alternatives that exist only to justify the preferred choice
- Missing security -- never skip for tsuku
- No consequences -- every decision has trade-offs
```

**Replace with:**
```markdown
### Common Pitfalls
- Too broad ("Improve the system") -- narrow to a specific capability
- Strawman options -- alternatives that exist only to justify the preferred choice
- Empty or bare "N/A" security section -- always justify non-applicability
- No consequences -- every decision has trade-offs
```

Rationale: Remove "tsuku" from the example (it's just an example; any project name works). The third pitfall rewords from "never skip for tsuku" to a generic rule that matches the updated Security section guidance.

---

### 7. Remove the Label Lifecycle section (SKILL.md, lines 113–161)

**Current (lines 113–161):** The entire "Label Lifecycle" subsection, from `### Label Lifecycle` through the end of the "Superseded child design" block, including the `swap-to-tracking.sh` reference.

**Replace with:**

```markdown
### Label Lifecycle

If your project uses GitHub labels to track design status (e.g., `needs-design`,
`tracks-plan`), the label transitions for this skill are:

- **Design accepted (Phase 6):** Remove whatever `needs-*` label the source issue
  carries. The tracking label is applied by the planning skill, not here.
- **Child design superseded:** Revert the parent issue to its pre-design label
  state and update the parent design doc accordingly.

Define your project's specific label names in CLAUDE.md under
`## Label Vocabulary`.
```

Rationale: The label lifecycle section contains ~49 lines of tsuku-specific content: specific label names (`needs-design`, `tracks-design`, `tracks-plan`), Mermaid class names (`needsDesign`, `tracksDesign`, `tracksPlan`), and direct `swap-to-tracking.sh` invocations. All of this belongs in the consumer's extension file. The replacement preserves the conceptual structure (when to remove labels, what a superseded child does) without hardcoding tsuku's vocabulary.

Note: The `swap-to-tracking.sh` reference in the Label Lifecycle section is **not** the same as the `transition-status.sh` reference. `swap-to-tracking.sh` is called in the label lifecycle, and the label lifecycle is being moved to the extension layer. So this script reference is removed from the base skill.

The `transition-status.sh` reference in the "Status Transition Script" block (lines 106–110) is a generic utility and stays.

---

### 8. Update Status Transition Script path (SKILL.md, line 108)

**Current (line 108):**
```
${CLAUDE_SKILL_DIR}/scripts/transition-status.sh <path> <target> [superseding-doc]
```

**Replace with:**
```
${CLAUDE_PLUGIN_ROOT}/scripts/transition-status.sh <path> <target> [superseding-doc]
```

Rationale: The migration instructions specify using `${CLAUDE_PLUGIN_ROOT}/scripts/transition-status.sh` as the stable sub-operation path. The current form uses `${CLAUDE_SKILL_DIR}` which is also present in the Reference Files table at the bottom and described as the stable form — update the inline usage to be consistent.

---

### 9. Remove `swap-to-tracking.sh` from Reference Files table (SKILL.md, lines 340–341)

**Current (lines 339–341):**
```markdown
| `${CLAUDE_SKILL_DIR}/scripts/transition-status.sh` | Status transitions with file movement (**stable sub-operation**: callable via `${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/transition-status.sh`) |
| `${CLAUDE_SKILL_DIR}/scripts/swap-to-tracking.sh` | needs-* to tracks-plan label lifecycle (**stable sub-operation**: callable via `${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/swap-to-tracking.sh`) |
```

**Replace with:**
```markdown
| `${CLAUDE_PLUGIN_ROOT}/scripts/transition-status.sh` | Status transitions with file movement |
```

Rationale: `swap-to-tracking.sh` is the label lifecycle script. Since the label lifecycle section is moving to the extension layer, this script reference is no longer needed in the base skill's reference table. The transition-status.sh reference stays and its path is updated to use the `${CLAUDE_PLUGIN_ROOT}` form consistently.

---

### 10. Update `helpers/label-reference.md` reference in Label Lifecycle (covered by change 7)

The reference to `../../helpers/label-reference.md` on line 117 is inside the label lifecycle block being removed in change 7. No separate action needed.

---

### 11. Update `design-approval-routing.md` reference (SKILL.md, line 308)

**Current (line 308):**
```
See `../../helpers/design-approval-routing.md` for shared routing logic.
```

**Replace with:**
```
See `references/decision-presentation.md` for shared routing logic.
```

Wait — the migration instructions say: replace references to `helpers/design-approval-routing.md` with **inline content** (this helper is being inlined per design decision). So:

**Replace with:** Remove the "See" pointer entirely and inline the routing logic in the Output section:

```markdown
After completion, present the design summary and offer next steps.

Run a complexity assessment based on the design's implementation scope:

| Criterion | Simple | Complex |
|-----------|--------|---------|
| Files to modify | 1-3 | 4+ |
| New tests | Updates only | New test infrastructure |
| API changes | None | Surface changes |
| Cross-package | No | Yes |

Present an AskUserQuestion with the assessment and options:
- If Simple: "Plan (Recommended)" / "Approve only"
- If Complex: "Plan (Recommended)" / "Approve only"

**"Plan":** suggest running `/plan <design-doc-path>` to create implementation issues.
The PR should NOT be merged yet — `/plan` will add an "Implementation Issues" section.

**"Approve only":** stop here; the user handles implementation manually.
```

Rationale: The migration instruction specifies inlining `design-approval-routing.md`. The helper is brief (52 lines total, but the actual routing logic is ~30 lines). Inlining avoids an unresolvable relative path to a helper that doesn't exist in shirabe's layout.

---

### 12. Update `helpers/decision-presentation.md` references in phase files

Phase 2 (line 14), Phase 3 (lines 93, 101, 105, 132), Phase 4 (lines 88, 90) all reference:
```
`../../helpers/decision-presentation.md`
```

In shirabe, this helper moves to `references/decision-presentation.md` within the skill directory. Each phase file must update its reference:

**Replace all occurrences of:**
```
`../../helpers/decision-presentation.md`
```
**With:**
```
`references/decision-presentation.md`
```

This affects:
- `references/phases/phase-2-present-approaches.md` — lines 14, 58
- `references/phases/phase-3-deep-investigation.md` — lines 93, 101, 105, 132
- `references/phases/phase-4-architecture.md` — lines 88, 90

---

### 13. Update tsuku-specific security framing in phase-5-security.md

**Current (phase-5-security.md, lines 6–9):**
```markdown
## Why This Phase is Mandatory

Tsuku downloads and executes binaries from the internet. Every design must be
reviewed for security implications. This phase is NOT optional -- skip it and
the design doc will fail validation in Phase 6.
```

**Replace with:**
```markdown
## Why This Phase is Mandatory

Every design carries security implications. This phase is NOT optional -- skip it
and the design doc will fail validation in Phase 6.
```

**Current (phase-5-security.md, lines 36–38):**
```markdown
You are a security researcher reviewing a technical design for tsuku, a package
manager that downloads and executes binaries from the internet.
```

**Replace with:**
```markdown
You are a security researcher reviewing a technical design.
```

**Current (phase-5-security.md, lines 43–52):** The four fixed security dimensions in the researcher prompt (Download Verification, Execution Isolation, Supply Chain Risks, User Data Exposure) should be generalized:

**Replace the "## Security Dimensions" block:**
```markdown
## Security Dimensions

Analyze each dimension that applies to this design. Common dimensions include:

1. **External artifact handling**: Does this design download, execute, or process
   external inputs? How are they validated?
2. **Permission scope**: What filesystem, network, or process permissions does
   this feature require? Any escalation risks?
3. **Supply chain or dependency trust**: Where do dependencies or artifacts come
   from? How is source authenticity verified?
4. **Data exposure**: What user or system data does this feature access or
   transmit?

If your project has defined additional domain-specific security dimensions (via
`@.claude/shirabe-extensions/design.md`), apply those as well.

For each dimension: if it applies, assess severity and suggest mitigations.
If it doesn't apply, explain concretely why not.
```

Rationale: The four tsuku-specific dimensions (download verification, execution isolation, supply chain, user data) are reasonable defaults but framed for a binary package manager. Generalizing them makes the security review applicable to any project while keeping the same analytical structure.

---

### 14. Update `writing-style.md` reference in SKILL.md

**Current (line 15):**
```
**Writing style:** Read `../../helpers/writing-style.md` for guidance.
```

Already covered in change 2 above.

---

### 15. Update Repo Visibility helper references (SKILL.md, lines 222–226)

**Current (lines 221–227):**
```markdown
## Repo Visibility

Before writing content, determine visibility:
- **Private repos:** Read `../../helpers/private-content.md`
- **Public repos:** Read `../../helpers/public-content.md`

Public designs must not reference private artifacts.
```

In shirabe, these helpers move to the `references/` directory within each skill (or a shared location). The exact path depends on where they land in the shirabe layout, but the relative-path form to `../../helpers/` is broken. If they move to `references/private-content.md` and `references/public-content.md`:

**Replace with:**
```markdown
## Repo Visibility

Before writing content, determine visibility from CLAUDE.md (`## Repo Visibility: Public|Private`):
- **Private repos:** Read `references/private-content.md`
- **Public repos:** Read `references/public-content.md`

Public designs must not reference private artifacts.
```

If the content governance helpers are placed at a different path in shirabe, adjust accordingly.

---

## Quality Improvements to Make Alongside Migration

### A. Improve the description for triggering accuracy

The current description under-triggers. Someone exploring an architectural decision won't think "I need design document structure." The description should front-load the workflow, not the artifact format.

See "Proposed New Description" section below.

### B. Remove circularity from `implementation-diagram` skill reference (SKILL.md, line 219)

**Current (line 219):**
```
See the `implementation-diagram` skill for construction rules.
```

`implementation-diagram` is a tools-internal skill not packaged in shirabe. Replace with:

```
See your project's diagram convention, or follow the format: an issues table with a
Mermaid dependency diagram showing issue relationships.
```

### C. Clarify that `planning-context` detection is via CLAUDE.md

Already covered in change 4. The context-aware sections table (lines 72–86) references scope and visibility without explaining how to detect them. After removing the `planning-context` skill reference, add a note:

```
Detect scope and visibility from CLAUDE.md:
- `## Repo Visibility: Private|Public`
- `## Planning Context: Strategic|Tactical` (or `## Default Scope:`)
```

This is a one-line addition after the table.

### D. The `argument-hint` field is generic and stays as-is

```yaml
argument-hint: '<PRD path or topic>'
```

This is fine for shirabe — it's not project-specific.

---

## Proposed New Description

The current description:
> Design document structure, validation rules, lifecycle, and creation workflow. Use when writing, reviewing, validating, or transitioning docs/designs/DESIGN-*.md files, or when creating new design documents via /design.

**Proposed replacement:**
> Create or review technical design documents. Use when deciding how to implement something — the skill fans out multiple approaches via advocate agents, presents trade-offs side by side, and produces a structured design doc with the chosen approach. Also use when reviewing, validating, or transitioning an existing design doc through its lifecycle (Proposed → Accepted → Planned → Current). Triggers on: "help me design X", "compare approaches for Y", "write a design doc for Z", review or approve a design doc, or status transitions on DESIGN-*.md files.

**Reasoning:**
- Leads with the workflow value ("deciding how to implement something") not the artifact structure
- Names the distinctive mechanism (advocate agents, side-by-side comparison) that makes this skill worth triggering
- Covers the review/lifecycle use case explicitly
- Lists concrete trigger phrases at the end, following the skill-creator guidance to be "pushy" and enumerate scenarios
- Removes the project-specific file path pattern; consumers will learn the convention from the skill body
- Stays within a length that won't dominate the context

---

## Content to Move to a Reference File vs. Cut Entirely

### Move to `references/decision-presentation.md` (new file in skill bundle)

The content of `helpers/decision-presentation.md` should become `references/decision-presentation.md` within the design skill bundle. Phase files already reference it heavily. This keeps the agent decision philosophy close to the skill that uses it.

The content of this helper is entirely generic (no project-specific references) and moves verbatim.

### Inline into SKILL.md: `helpers/design-approval-routing.md`

Per the migration decision, this helper's content gets inlined into the Output section of the workflow (see change 11). The helper's content is ~30 lines of actual logic; at that size, inlining is reasonable and avoids a broken path reference.

### New file `references/private-content.md` and `references/public-content.md`

These helpers move from `../../helpers/` into the skill's `references/` directory. Both are generic and move verbatim (with the one reword noted in the extraction audit: `public-content.md` must remove the prohibition on mentioning `/explore`, `/work-on`, `/plan`, since those are shirabe's own skills).

### Cut entirely from base: `helpers/label-reference.md` reference

The label-reference helper is project-specific (tsuku label vocabulary). The label lifecycle section that referenced it is being removed (change 7). No replacement file needed in the shirabe base.

### Cut entirely from base: `swap-to-tracking.sh`

Referenced only in the label lifecycle section (removed in change 7) and the reference table (removed in change 9). The script itself may still ship with shirabe as an optional utility that consumers can use if they adopt the label workflow, but it shouldn't be referenced in the base skill text.

---

## Summary of Changes by File

| File | Change type | Lines affected |
|------|-------------|----------------|
| `SKILL.md` | Add extension slot lines | +2 after frontmatter |
| `SKILL.md` | Update description | ~5 lines replaced |
| `SKILL.md` | Update writing-style reference (line 15) | 1 line |
| `SKILL.md` | Update planning-context reference (line 71) | 1 line |
| `SKILL.md` | Update security section heading (line 68) | 1 line |
| `SKILL.md` | Remove label lifecycle section (lines 113–161) | -49 lines, +12 generic replacement |
| `SKILL.md` | Replace tsuku security block (lines 193–208) | -16 lines, +9 generic replacement |
| `SKILL.md` | Update common pitfalls (lines 204–208) | 2 lines changed |
| `SKILL.md` | Inline design-approval-routing (line 308) | -1 pointer, +15 inlined |
| `SKILL.md` | Update transition-status.sh path (line 108) | 1 line |
| `SKILL.md` | Update reference table (lines 339–341) | -1 row, update path |
| `SKILL.md` | Update implementation-diagram reference (line 219) | 1 line |
| `SKILL.md` | Update Repo Visibility helper paths (lines 222–226) | 2 lines |
| `phase-2-present-approaches.md` | Update decision-presentation refs (lines 14, 58) | 2 lines |
| `phase-3-deep-investigation.md` | Update decision-presentation refs (lines 93, 101, 105, 132) | 4 lines |
| `phase-4-architecture.md` | Update decision-presentation refs (lines 88, 90) | 2 lines |
| `phase-5-security.md` | Remove tsuku framing, generalize dimensions (lines 6–52) | ~20 lines replaced |
| New: `references/decision-presentation.md` | Move from helpers, verbatim | new file |
| New: `references/private-content.md` | Move from helpers, verbatim | new file |
| New: `references/public-content.md` | Move from helpers, one reword | new file |

**Net effect on SKILL.md:** ~340 lines → ~275 lines (~19% reduction, matching the extraction audit's ~65 line estimate).

The skill stays well under 500 lines. No progressive disclosure changes needed in SKILL.md itself. Phase files remain as separate reference files — their total line count (1,206 lines) is acceptable because only one is loaded at a time.
