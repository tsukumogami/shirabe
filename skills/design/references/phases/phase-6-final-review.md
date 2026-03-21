# Phase 6: Final Review + Finalize

Validate the complete design doc, add frontmatter, commit, and route to next step.

## Goal

Ensure the design doc is complete and ready for approval:
- Launch review agents (architecture + security)
- Validate all required sections
- Check that rejected alternatives have genuine depth (strawman check)
- Add frontmatter, commit, create PR
- Route to next step based on complexity

## Resume Check

If the design doc has YAML frontmatter with status "Proposed", skip to step 6.5
(present for approval).

## Steps

### 6.1 Launch Review Agents

Launch two review agents in parallel using the Agent tool with `run_in_background: true`.

**Architecture reviewer:**
```
Review the solution architecture for this design document.

Questions:
1. Is the architecture clear enough to implement?
2. Are there missing components or interfaces?
3. Are the implementation phases correctly sequenced?
4. Are there simpler alternatives we overlooked?

[Include Solution Architecture and Implementation Approach sections]

Write full analysis to wip/research/design_<topic>_phase6_architecture-review.md.
Return only key findings and recommendations.
```

**Security reviewer:**
```
Review the security analysis for this design.

Questions:
1. Are there attack vectors not considered?
2. Are mitigations sufficient for identified risks?
3. Are any "not applicable" justifications actually applicable?
4. Is there residual risk that should be escalated?

[Include Security Considerations section]

Write full analysis to wip/research/design_<topic>_phase6_security-review.md.
Return only key findings and recommendations.
```

### 6.2 Process Review Feedback

After both agents complete, consolidate feedback:

| Source | Feedback | Action | Applied |
|--------|----------|--------|---------|
| Architecture | <finding> | <action> | [ ] |
| Security | <finding> | <action> | [ ] |

Apply changes to the design doc. If a review finding requires significant rework,
discuss with the user before making changes.

### 6.3 Strawman Check

Read the "Considered Options" section. For each rejected alternative, verify:
- Does it have a genuine explanation of why it was rejected?
- Could someone reading only the rejected alternative understand what it proposed?
- Does the rejection reference real weaknesses (from the advocate's investigation)?

If any rejected alternative reads like a strawman (vague description, superficial
rejection, no evidence of investigation), flag it and rewrite using the advocate
report from `wip/research/design_<topic>_phase1_advocate-*.md`.

### 6.4 Validate Document Structure

Check all required sections are present and well-formed:

**Required Sections:**
- [ ] Status (must be "Proposed")
- [ ] Context and Problem Statement
- [ ] Decision Drivers
- [ ] Considered Options (at least 1 alternative per decision)
- [ ] Decision Outcome
- [ ] Solution Architecture
- [ ] Implementation Approach
- [ ] Security Considerations (content per Phase 5 outcome)
- [ ] Consequences (positive, negative, mitigations)

**STOP if any check fails.** Fix before proceeding.

### 6.5 Write Frontmatter

Add YAML frontmatter using the wip/ summary. Each field is 1 paragraph, using
YAML literal block scalars (`|`):

```markdown
---
status: Proposed
upstream: docs/prds/PRD-<name>.md   # Only if PRD mode (check wip/ summary)
problem: |
  <1 paragraph: what technical problem this solves>
decision: |
  <1 paragraph: what approach was chosen and key properties>
rationale: |
  <1 paragraph: why this approach over alternatives>
---
```

The frontmatter must be the first content in the file, before the `# DESIGN:` heading.

### 6.6 Commit and PR

1. Commit: `docs(design): add design for <topic>`
2. Push and create PR
   - If spawned from an issue: use `Ref #<N>` in PR body (not `Fixes`)
   - Title: `docs(design): design for <topic>`

### 6.7 Present for Approval

Display the design summary:

```
## Design Summary

**Problem:** <frontmatter problem field>

**Decision:** <frontmatter decision field>

**Rationale:** <frontmatter rationale field>
```

Ask user for approval using AskUserQuestion:
- **Approved**: The design is ready
- **Needs iteration**: Specify what needs to change

### 6.8 Handle Approval

**If approved:**

1. Change status from "Proposed" to "Accepted" (frontmatter and body)
2. Commit: `docs(design): accept design for <topic>`
3. **Remove blocking label from source issue.** Skip if there is no source issue.
   Check your project's label vocabulary (CLAUDE.md `## Label Vocabulary`) for
   which labels to remove on design acceptance. If no vocabulary is defined, look
   for any `needs-*` label and remove it. The tracking label is applied later by
   /plan, not here.
4. **Update parent design doc** (only when the design doc has `spawned_from` in its frontmatter).
   If your project defines a label lifecycle in the extension file
   (`@.claude/shirabe-extensions/design.md`), follow those instructions for
   parent doc updates (Mermaid diagram class changes, child reference rows,
   spawned_from metadata). If no extension defines this, skip parent doc updates.
5. **PR body convention.** If spawned from an issue, use `Ref #<N>` in the PR
   body, NOT `Fixes #<N>`. The issue stays open until implementation completes.
6. Run the complexity assessment and routing from the design SKILL.md "Output" section (the table comparing Simple vs Complex criteria, followed by the AskUserQuestion presenting Plan vs Approve options). Use `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md` for the AskUserQuestion formatting pattern.

### 6.9 Clean Up wip/ Artifacts

After approval and routing, remove temporary artifacts:
- `wip/design_<topic>_summary.md`
- `wip/research/design_<topic>_*.md` (all phase research files)

Commit: `chore: clean up wip/ artifacts for <topic>`

**If needs iteration:**
- Discuss what needs changes with user
- Return to the relevant phase
- Re-run Phase 6 when changes are complete

## Quality Checklist

Before declaring the phase complete:
- [ ] Strawman check passed (rejected alternatives have genuine depth)
- [ ] Validation per `references/lifecycle.md` rules passed
- [ ] All actionable feedback addressed

## Artifact State

Final design document at `docs/designs/DESIGN-<topic>.md` with:
- YAML frontmatter (status, problem, decision, rationale)
- All required sections complete
- Status: Proposed (or Accepted after approval)
