# Phase 7: PLAN Artifact Creation

Create the PLAN artifact and (in multi-pr mode) GitHub milestone and issues.

## Table of Contents

- [Resume Check](#resume-check)
- [Prerequisites](#prerequisites)
- [multi-pr Mode](#multi-pr-mode): 7.1 Create GitHub Issues, 7.2 Write PLAN Artifact, 7.3 Verify Creation, 7.4 Validate Traceability
- [single-pr Mode](#single-pr-mode): 7.1 Write PLAN Artifact, 7.2 Suggest Next Steps
- [Common Steps](#common-steps-both-modes): 7.5 Status Transition, 7.6 Cleanup, 7.7 Report Summary, 7.8 Upstream Issue Update

## Resume Check

Check if `docs/plans/PLAN-<topic>.md` exists.

| Existing Status | Action |
|-----------------|--------|
| Active | Skip -- already complete |
| Done | Skip -- already complete |
| Draft | Ask user: continue editing or overwrite |
| _(does not exist)_ | Proceed normally |

## Prerequisites

Read all topic-scoped wip/ artifacts:
- `wip/plan_<topic>_analysis.md` -- design doc path and scope
- `wip/plan_<topic>_milestones.md` -- milestone definitions
- `wip/plan_<topic>_decomposition.md` -- issue outlines and strategy (includes `execution_mode` in YAML frontmatter)
- `wip/plan_<topic>_manifest.json` -- generated issue bodies and file references
- `wip/plan_<topic>_dependencies.md` -- dependency graph
- `wip/plan_<topic>_review.md` -- review approval

**STOP** if `wip/plan_<topic>_manifest.json` does not exist. Phase 4 (Agent Generation) must run first.

Read the `execution_mode` from the decomposition artifact's YAML frontmatter, then branch to the appropriate section below.

---

## multi-pr Mode

Steps 7.1 through 7.4 apply when `execution_mode: multi-pr`.

### 7.1 Create GitHub Issues Using Batch Script

Use the batch script to create all issues in dependency order.

**Script**: `${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh`

Read `wip/plan_<topic>_milestones.md` for the milestone name and description, then run the batch script. The invocation varies by input type.

**For design/prd input types:**

```bash
${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh \
  --manifest wip/plan_<topic>_manifest.json \
  --milestone "<Milestone Name>" \
  --milestone-description "Design: \`<design-doc-path>\`" \
  --output-map wip/plan_<topic>_mapping.json
```

**For roadmap input type:**

The milestone description references the roadmap (not a design doc). Per-issue `needs_label` values from the manifest are applied automatically by the batch script (see Issue 3: each manifest entry's `needs_label` field is merged with global labels).

```bash
${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh \
  --manifest wip/plan_<topic>_manifest.json \
  --milestone "<Milestone Name>" \
  --milestone-description "Roadmap: \`<roadmap-path>\`" \
  --output-map wip/plan_<topic>_mapping.json
```

The manifest must include `needs_label` for each issue (populated during Phase 3 roadmap decomposition). The batch script applies these per-issue labels alongside any global `--labels`.

Options:
- `--milestone <name>` -- assign all issues to this milestone (created if it doesn't exist)
- `--milestone-description <desc>` -- milestone description (include source doc path)
- `--labels <labels>` -- comma-separated labels for all issues
- `--output-map <file>` -- write the final ID-to-GitHub-number mapping
- `--dry-run` -- preview without creating

**Strategic scope:** Add strategic labels:
```bash
${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh \
  --manifest wip/plan_<topic>_manifest.json \
  --milestone "<Milestone Name>" \
  --milestone-description "Design: \`<design-doc-path>\`" \
  --labels "needs-design,repo:<target-repo>" \
  --output-map wip/plan_<topic>_mapping.json
```

#### Handle Failures

If the script reports failures:
1. Check error output for details
2. Fix the body file and re-run, or create individually:

```bash
${CLAUDE_SKILL_DIR}/scripts/create-issue.sh \
  --file wip/plan_<topic>_issue_<id>_body.md \
  --title "<title>" \
  --complexity <complexity> \
  --map wip/plan_<topic>_mapping.json \
  --milestone "<Milestone Name>"
```

#### Placeholder Substitution

The batch script handles `<<ISSUE:N>>` placeholders in three passes:

1. **Create**: Issues created with placeholders intact. ID-to-GitHub-number mapping built as each issue is created.
2. **Update**: All issue bodies re-read, placeholders substituted using the complete mapping, GitHub issues updated via `gh issue edit`.
3. **Verify**: Each issue fetched and checked for unresolved placeholders.

This handles forward references -- an issue can reference any other issue in the batch.

#### Apply Complexity Labels

Complexity labels are applied via: `${CLAUDE_SKILL_DIR}/scripts/apply-complexity-label.sh`

### 7.2 Write PLAN Artifact

Create `docs/plans/PLAN-<topic>.md` with the following structure.

**Frontmatter:**

```yaml
---
schema: plan/v1
status: Active
execution_mode: multi-pr
upstream: <source-doc-path>   # design doc, PRD, or roadmap path
milestone: "<Milestone Name>"
issue_count: <N>
---
```

**Required sections** (in order):

1. **Status** -- `Active`
2. **Scope Summary** -- from `wip/plan_<topic>_analysis.md`
3. **Decomposition Strategy** -- from `wip/plan_<topic>_decomposition.md`:
   - design/prd: "Walking skeleton" or "Horizontal decomposition" with rationale
   - roadmap: "Feature-by-feature planning" with rationale
4. **Implementation Issues** -- table with GitHub issue links, dependencies, complexity. Include description rows below each issue. Follow the format in `../quality/plan-doc-structure.md`.
5. **Dependency Graph** -- Mermaid diagram following these rules:
   - Use `graph TD` (not `flowchart`)
   - Node IDs: `I<issue-number>`, labels in `["..."]`
   - Edges MUST be outside subgraphs
   - `classDef` definitions at the end -- include the full expanded set: `done`, `ready`, `blocked`, `needsDesign`, `needsPrd`, `needsSpike`, `needsDecision`, `tracksDesign`, `tracksPlan`
   - For roadmap planning issues: each node's initial class matches its `needs_label` (e.g., `needsPrd`, `needsDesign`)
   - Class assignments use `class` directive (not inline `:::`)
   - Include legend line after diagram
6. **Implementation Sequence** -- critical path, parallelization opportunities, recommended order

Reference `../quality/plan-doc-structure.md` for detailed format rules.

### 7.3 Verify Creation

```bash
gh issue list --milestone "<Milestone Name>"
```

Verify:
- [ ] All issues created
- [ ] Milestone assignments correct
- [ ] Dependencies reference correct issue numbers

### 7.4 Validate Traceability References

#### Strategic scope (design/prd input)

Verify every needs-design issue body contains a `Design:` reference line:

1. Read each body file from the manifest
2. Check for `Design: \`<path>\`` (backtick-quoted path to the parent design doc)
3. If missing, add it to the Context section and re-run the batch script for that issue

This reference is required to locate the parent design doc when accepting a child design.

#### Roadmap input

Verify every planning issue body contains both traceability references:

1. Read each body file from the manifest
2. Check for `Roadmap: \`<path>\`` (backtick-quoted path to the parent roadmap)
3. Check for `Feature: <feature-name>` identifying which roadmap feature this issue plans
4. If either is missing, add it to the Context section and re-run the batch script for that issue

These references enable traceability from planning issues back to the source roadmap and specific feature.

---

## single-pr Mode

Steps 7.1 through 7.2 apply when `execution_mode: single-pr`.

No GitHub milestone or issues are created in single-pr mode.

### 7.1 Write PLAN Artifact

Create `docs/plans/PLAN-<topic>.md` with the following structure.

**Frontmatter:**

```yaml
---
schema: plan/v1
status: Draft
execution_mode: single-pr
upstream: <design-doc-path>
milestone: "<Milestone Name>"
issue_count: <N>
---
```

**Required sections** (in order):

1. **Status** -- `Draft`
2. **Scope Summary** -- from `wip/plan_<topic>_analysis.md`
3. **Decomposition Strategy** -- from `wip/plan_<topic>_decomposition.md` (walking skeleton, horizontal, or feature-by-feature planning, with rationale)
4. **Issue Outlines** -- read from body files (`wip/plan_<topic>_issue_<id>_body.md`), format as structured outlines with these subsections per issue:
   - **Goal** -- what the issue delivers
   - **Acceptance Criteria** -- how to verify completion
   - **Dependencies** -- which internal IDs this blocks on
5. **Dependency Graph** -- same Mermaid format as multi-pr, but nodes use internal IDs (`I1`, `I2`, ...) instead of GitHub issue numbers. Same `classDef` rules apply.
6. **Implementation Sequence** -- critical path, parallelization opportunities, recommended order

No Implementation Issues table in single-pr mode.

### 7.2 Suggest Next Steps

Recommend running `/implement-doc docs/plans/PLAN-<topic>.md` to begin implementation.

---

## Common Steps (Both Modes)

These steps run after the mode-specific steps above.

### 7.5 Source Document Status Transition

**For design docs and PRDs** (input_type: design or prd):

Transition the upstream design doc from Accepted to Planned:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/transition-status.sh <design-doc-path> Planned
```

**Important constraints:**
- This is a status-only change
- Do NOT insert an Implementation Issues section into the design doc
- Do NOT modify the design doc body in any way
- Only the status line changes (Accepted -> Planned)

**For roadmaps** (input_type: roadmap):

Roadmaps stay at "Active" status. The PLAN artifact tracks the planning work, but the roadmap itself isn't transitioned -- it remains Active until all features are delivered. No status change is needed.

### 7.6 Cleanup

Delete topic-scoped wip/ artifacts on success:

```bash
rm -f wip/plan_<topic>_analysis.md
rm -f wip/plan_<topic>_milestones.md
rm -f wip/plan_<topic>_decomposition.md
rm -f wip/plan_<topic>_dependencies.md
rm -f wip/plan_<topic>_review.md
rm -f wip/plan_<topic>_issue_*.md
rm -f wip/plan_<topic>_manifest.json
rm -f wip/plan_<topic>_mapping.json
```

Do NOT delete on failure -- artifacts are needed for resume.

### 7.7 Report Summary

Summarize what was created:

**multi-pr:**
```markdown
## Created Artifacts

### Milestone: [<Name>](<milestone-url>)

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#N: <title>](<url>) | None | simple |
| [#M: <title>](<url>) | [#N](<url>) | testable |

### Dependency Graph

[Mermaid diagram]

**Legend**: Green = done, Blue = ready, Yellow = blocked, Purple = needs-design, Orange = tracks-design

### Next Steps
Start with issues that have no dependencies (marked `ready` in diagram):
- [#N](<url>): <title>
```

**single-pr:**
```markdown
## Created Artifacts

PLAN document: `docs/plans/PLAN-<topic>.md`
Design doc status: Planned

### Next Steps
Run `/implement-doc docs/plans/PLAN-<topic>.md` to begin implementation.
```

### 7.8 Upstream Issue Update

Ask the user if there's an upstream issue that should be updated:

```
Is there an upstream issue that should be updated to link to these newly created issues?

If yes, provide the issue reference in <owner>/<repo>#<number> format.
```

**If user provides an upstream issue:**

1. **Verify visibility direction**: Only update if the upstream issue is in a repo with SAME or MORE PRIVATE visibility. Never add references from public issues to private issues.

2. **Append implementation tracking**:
   ```bash
   CURRENT_BODY=$(gh issue view <number> --repo <owner>/<repo> --json body --jq '.body')

   gh issue edit <number> --repo <owner>/<repo> --body "$CURRENT_BODY

   ---
   ## Implementation Issues (in <current-repo>)

   - [#<N>](<issue-url>): <title>
   - [#<N>](<issue-url>): <title>
   "
   ```

3. **If the upstream issue still has `needs-design` label**, remove it now.

**Visibility rule**: Public issues must NEVER reference private issues. Only private issues can reference public issues.

**Strategic scope note:** After creating the milestone and issues, note that these are placeholder issues with `needs-design` label. The user should run `/work-on` on individual issues to create tactical designs when ready.

## Quality Checklist

Before completing:
- [ ] PLAN artifact created at `docs/plans/PLAN-<topic>.md`
- [ ] Frontmatter includes all required fields (`schema`, `status`, `execution_mode`, `milestone`, `issue_count`)
- [ ] multi-pr: all issues created, milestone assigned, status is Active
- [ ] single-pr: Issue Outlines populated, no GitHub artifacts, status is Draft
- [ ] Design doc transitioned to Planned (status-only, no body edits)
- [ ] wip/ artifacts cleaned up
- [ ] Summary reported

## Next Phase

This is the final phase of the /plan command.
