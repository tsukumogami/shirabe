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

Launch three review agents in parallel using the Agent tool with `run_in_background: true`.

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

**Structural-format reviewer:**
```
Review the design document's artifact-shape conformance against the
canonical DESIGN format reference.

Reference: skills/design/references/design-format.md.

Questions covering the four named items:
1. Section presence and order: do all nine required sections appear
   in the canonical order (Status, Context and Problem Statement,
   Decision Drivers, Considered Options, Decision Outcome, Solution
   Architecture, Implementation Approach, Security Considerations,
   Consequences)?
2. Frontmatter field order: are the four required fields (status,
   problem, decision, rationale) declared in the canonical order with
   the documented YAML literal block scalar shape? Are optional
   fields (upstream, spawned_from, motivating_context) placed
   consistently with the format reference?
3. Section-altitude conformance: does each section contain the
   altitude of content the reference prescribes (no PRD-altitude
   requirements, no PLAN-altitude atomic issues)?
4. R19 budget-vs-spec: heuristic check on section length. If any
   section's prose exceeds the reference's documented budget by
   more than 50%, flag the overshoot and ask whether content
   belongs at a different altitude. The >50% threshold avoids
   flagging healthy detail and surfaces only meaningful overshoot.

The reviewer dereferences references/fixes/sub-agent-dispatch.md
when the parent_orchestration sentinel is present in
wip/scope_<topic>_state.md (serial-self-jury fallback applies when
parallel spawn is not available).

[Include all nine required sections plus the frontmatter]

Write full analysis to wip/research/design_<topic>_phase6_structural-format-review.md.
Return only key findings and recommendations.
```

The structural-format reviewer is "in addition to" the existing
architecture and security reviewers (per AC4.4). Reach for it on
every design; the reviewer's checks are mechanically applicable
against the format reference and surface drift the discretionary
reviewers do not catch.

### 6.2 Process Review Feedback

After all three agents complete, consolidate feedback:

| Source | Feedback | Action | Applied |
|--------|----------|--------|---------|
| Architecture | <finding> | <action> | [ ] |
| Security | <finding> | <action> | [ ] |
| Structural-Format | <finding> | <action> | [ ] |

Apply changes to the design doc. If a review finding requires significant rework,
discuss with the user before making changes.

### 6.3 Strawman Check

Read the "Considered Options" section. For each rejected alternative, verify:
- Does it have a genuine explanation of why it was rejected?
- Could someone reading only the rejected alternative understand what it proposed?
- Does the rejection reference real weaknesses from the decision evaluation?

If any rejected alternative reads like a strawman (vague description, superficial
rejection, no evidence of investigation), flag it and strengthen using the decision
reports from Phase 2 (`wip/design_<topic>_decision_<N>_report.md`) and the
Considered Options already written in Phase 3.

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

**Reference Hygiene Checks:**

Run this grep from the repo root:

```bash
git grep -nE 'wip/' -- docs/designs/DESIGN-<topic>.md || true
```

- [ ] No `wip/...` paths appear in the committed frontmatter or prose. The
  only acceptable matches are quoted statements OF the wip-hygiene rule
  itself; any path-shaped reference is a hard fail.
- [ ] `upstream:` value resolves on disk via `git ls-files <path>`, OR is a
  valid public `owner/repo:path` cross-repo reference, OR is omitted (per
  Phase 0 step 0.4a). See
  `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`.
- [ ] No references in the design body to staging artifacts that will be
  deleted by Phase 6.9 cleanup (search for `wip/design_`, `wip/research/`).

**STOP if any check fails.** Fix before proceeding.

### 6.5 Write Frontmatter

Add YAML frontmatter using the wip/ summary. Each field is 1 paragraph, using
YAML literal block scalars (`|`):

```markdown
---
status: Proposed
upstream: docs/prds/PRD-<name>.md   # Only if PRD mode AND step 0.4a resolved to a usable path. OMIT if 0.4a resolved to "omit" (private cross-repo) or if no upstream PRD exists.
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

Ask user for the verdict using AskUserQuestion. The prompt copy MUST advise
the author that any rejection rationale becomes part of the repository's
permanent git history, so private content must not be included:

> Rationale will be committed to git history. Do not include secrets,
> customer identifiers, or content you intend to keep private.

Options:

- **Approved**: The design is ready; proceed to acceptance and routing.
- **Reject**: Terminal verdict. The Draft DESIGN is discarded via `git rm`
  and a discard commit lands on the current branch. No DESIGN ships. The
  discard commit is the durable observable signal of rejection in both
  in-chain (`/scope` reads it from `git log`) and out-of-chain (author
  re-reads the same commit) contexts per AC30c.
- **Continue-revising**: The design needs more work. Specify what needs to
  change; the workflow loops back to the relevant phase and re-runs Phase 6
  when changes are complete. (This is the existing "Needs iteration"
  behavior, renamed.)

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

**If continue-revising:**
- Discuss what needs changes with user
- Return to the relevant phase
- Re-run Phase 6 when changes are complete

**If reject:**

The Reject branch is a terminal verdict. It discards the Draft DESIGN and
exits the phase. The Reject branch fires AFTER step 6.6 (Commit and PR) has
already committed the Draft to the branch — the commit-then-approve ordering
is load-bearing because it preserves Draft durability across session
interruptions. Reject pays the `git rm` cost in exchange for that durability
guarantee. Do not reorder 6.6 and 6.7.

Run the following ordered actions; do not skip steps.

1. **Capture the rationale.** Prompt the author for a one-sentence rationale
   explaining why the DESIGN is being discarded. Restate the public-history
   disclaimer ("Rationale will be committed to git history") in the prompt
   so the author has a second opportunity to redact private content.

2. **Write the rationale to a tmpfile.** Author-supplied rationale strings
   are free-form and may contain shell metacharacters (quotes, backticks,
   dollar signs). Persist the rationale to a temporary file rather than
   passing it through any shell argument:

   ```bash
   RATIONALE_FILE=$(mktemp)
   cat > "$RATIONALE_FILE" <<EOF
   docs(design): discard DESIGN draft for <topic>

   <rationale captured at step 1>
   EOF
   ```

   The first line is the conventional-commit subject (the literal substring
   `/scope`'s Component 7.7 git-log search reads); a blank line separates
   the subject from the rationale body.

3. **Remove the durable DESIGN artifact.**

   ```bash
   git rm docs/designs/DESIGN-<topic>.md
   ```

4. **Remove the wip working artifacts** for this invocation. `/design`
   writes intermediate artifacts to BOTH the top-level `wip/design_<topic>_*`
   set AND the per-phase research set under `wip/research/design_<topic>_*`,
   so the Reject branch must clean both:

   ```bash
   rm -f wip/design_<topic>_*.md
   rm -f wip/research/design_<topic>_*.md
   ```

5. **Commit the discard via `git commit -F`** (file path), never `-m`:

   ```bash
   git commit -F "$RATIONALE_FILE"
   rm -f "$RATIONALE_FILE"
   ```

   Equivalent stdin form (`git commit -F -` reading from a here-document)
   is acceptable when scripting inline; the invariant is that the rationale
   never transits a `-m "..."` shell argument. The discard commit lands on
   the current branch and is the durable observable signal of rejection per
   AC30c.

6. **Exit the phase.** Do not flip status from Proposed to Accepted; do not
   run the Approved-path complexity assessment or routing; do not run step
   6.9 (the Reject branch handled its own wip cleanup inline in step 4).
   No DESIGN ships; the discard commit is the only artifact. The gate
   behaves identically in-chain and out-of-chain — `/design`'s
   responsibility stops at the discard commit. (Any `/scope`-side handling
   is the parent skill's concern, not this phase's.)

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
