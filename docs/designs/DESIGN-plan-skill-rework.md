---
status: Proposed
upstream: docs/prds/PRD-plan-skill-rework.md
problem: |
  Phase 7 of the /plan skill produces a PLAN doc for every input type,
  but roadmaps already reserve sections for the Implementation Issues table
  and Dependency Graph. This creates a redundant PLAN doc that duplicates
  information belonging in the roadmap.
decision: |
  When input_type is roadmap, Phase 7 writes directly into the roadmap's
  reserved sections instead of creating a PLAN doc. The Implementation
  Issues table uses the roadmap's own format (Feature/Issues/Status) with
  needs-* labels in the Status column. Design doc and PRD modes are unchanged.
rationale: |
  The reserved sections were designed as /plan's write target. Populating
  them directly avoids dual sources of truth, fulfills the format contract,
  and follows the input_type branching pattern already established in Phase 3.
---

# DESIGN: Plan Skill Rework

## Status

Proposed

## Context and Problem Statement

The /plan skill's Phase 7 always produces a PLAN doc, regardless of input type.
For design docs and PRDs this works: the PLAN doc adds decomposition structure
(issues table, dependency graph, implementation sequence) that the upstream
artifact shouldn't carry. For roadmaps it's redundant. The roadmap format
already reserves an Implementation Issues section and a Dependency Graph section
(added in F2), but Phase 7 writes these into a separate PLAN doc instead.

The result is two documents tracking the same initiative. The roadmap has the
features, sequencing rationale, and progress tracking. The PLAN doc has the
GitHub issue links and dependency graph. When features change, both need
updating. The roadmap is the source of truth for what's planned; the PLAN doc
is a derivative that adds only the issue mapping.

The technical change is scoped to Phase 7's output path. Phases 1-6 already
handle roadmap input correctly: Phase 1 validates Active status, Phase 3 uses
feature-by-feature decomposition, Phase 4 generates planning issues with
needs-* labels. Only Phase 7's "write a PLAN doc" step needs to branch on
input type.

## Decision Drivers

- Phase 7 must branch cleanly on `input_type` without affecting existing
  single-pr and multi-pr paths for design docs and PRDs
- The roadmap's reserved sections have a specific format contract (defined in
  `roadmap-format.md`) that the output must match
- GitHub issue creation (batch script, placeholder substitution) is unchanged;
  only where the Issues table and Mermaid graph are written changes
- Roadmap mode is always multi-pr (features are independent work items handled
  by different people or in different repos)
- `parsePlanDoc()` in Go only parses PLAN docs and must not need changes
- The roadmap stays Active after enrichment (no status transition)
- Backward compatibility: existing PLAN docs and /implement workflows are
  unaffected

## Considered Options

### Decision 1: Phase 7 branching and write target

Phase 7 currently writes a PLAN doc for every input type. For roadmap input,
this creates a redundant artifact -- the roadmap already reserves sections for
the same content. The question is whether Phase 7 should write into the roadmap
directly, keep producing PLAN docs, or do both.

The decomposition artifact's frontmatter carries `input_type`, and Phase 3
already branches on it. So the pattern of input-type-based branching is
established in the skill.

Key assumptions:
- No external tooling besides parsePlanDoc() consumes PLAN docs for
  roadmap-sourced plans
- The HTML comment markers in reserved sections are stable anchors for
  locate-and-replace
- Downstream planning issues from roadmaps go through /plan individually,
  not /implement-doc

#### Chosen: Direct roadmap enrichment

When `input_type: roadmap`, Phase 7 writes directly into the roadmap's
reserved sections instead of creating a PLAN doc. The branching works:

1. Read `input_type` from decomposition artifact frontmatter (already available)
2. At the top of the multi-pr path, branch on input_type: design/prd/topic
   goes to the existing PLAN-doc path, roadmap goes to the enrichment path
3. Step 7.1 (issue creation via batch script) is shared -- it's
   input-type-agnostic
4. Step 7.2 diverges: for roadmaps, locate the reserved sections by their
   HTML comment markers and replace the empty stubs with populated content
5. Steps 7.3-7.4 (verify, traceability) run unchanged
6. No status transition for roadmaps (stays Active)
7. Resume logic checks whether the roadmap's Implementation Issues table
   has content rows beyond the header

#### Alternatives considered

**PLAN doc alongside roadmap**: Produce a PLAN doc and leave the roadmap's
reserved sections empty. Rejected because it violates the reserved section
contract, leaves dead stubs in every roadmap, and forces users to find a
separate document for information that belongs in the roadmap.

**Hybrid (PLAN doc + roadmap enrichment)**: Produce both. Rejected because
dual sources of truth require synchronization, no consumer needs the redundant
PLAN doc, and the added complexity is unjustified.

### Decision 2: Implementation Issues table format

The roadmap's reserved Implementation Issues section has a documented template
(`Feature | Issues | Status` from roadmap-format.md). The PLAN doc uses a
different format (`Issue | Dependencies | Complexity` with description rows).
These serve different audiences and the enriched roadmap's table doesn't need
to match parsePlanDoc's expectations since /implement never reads roadmaps.

For roadmap planning issues, Dependencies and Complexity carry no useful
information: dependencies are in the Mermaid graph, and complexity is uniformly
"simple." The useful metadata is which feature, which issue, and what the
issue needs next.

Key assumptions:
- The 1:1 feature-to-issue mapping holds for all roadmap enrichments
- The needs-* label is the most useful per-issue metadata for roadmap readers

#### Chosen: Roadmap reserved format with needs-label in Status

Use the roadmap-format.md template as-is: `Feature | Issues | Status`. The
Feature column carries the feature name (matching the Features section
headings), Issues carries the GitHub issue link, and Status carries the
needs-* label or completion state.

Example:
```markdown
| Feature | Issues | Status |
|---------|--------|--------|
| Review-plan fast-path | [#49](url) | needs-design |
| Decision (degraded) | [#50](url) | needs-design |
| File koto requests | ~~[#51](url)~~ | Done |
```

When a feature has a needs-* label, Status shows it. When the issue is
complete, Status shows "Done" and the row is struck through.

#### Alternatives considered

**PLAN doc format (Issue | Dependencies | Complexity)**: Consistent with PLAN
docs but two of three columns carry no varying information for roadmap planning
issues. Rejected for low information density.

**Roadmap-native format (Issue | Label | Status)**: Drops the Feature column.
Rejected because it breaks the roadmap-format.md contract and loses
traceability to the Features section headings.

**Extended format (Feature | Issues | Label | Status)**: Adds a dedicated
Label column. Rejected because the Status column can carry the label without
an extra column.

## Decision Outcome

Phase 7 gains a conditional branch at the start of its multi-pr path. When
the decomposition artifact says `input_type: roadmap`, Phase 7 skips PLAN doc
creation and writes directly into the roadmap file. Step 7.1 (batch issue
creation with placeholder substitution) runs unchanged -- it doesn't care
where the output table ends up. Step 7.2 locates the roadmap's reserved
sections by their HTML comment markers and replaces the empty stubs with
populated content.

The Implementation Issues table uses the roadmap's own format
(`Feature | Issues | Status`), not the PLAN doc's issue-centric format.
Each row maps a roadmap feature to its planning issue, with the Status column
carrying the needs-* label. The Dependency Graph section gets the same Mermaid
diagram that would have gone into a PLAN doc, with node classes matching the
needs-* labels.

For design docs and PRDs, nothing changes. They continue producing PLAN docs
with the existing format. parsePlanDoc() in Go is untouched. /implement
workflows are unaffected since they read PLAN docs, not roadmaps.

The combination works because it respects the existing separation: roadmaps
are the source of truth for multi-feature initiatives, and enriching them
directly avoids the split-brain problem. The reserved sections were designed
for exactly this write pattern. The table format matches what /roadmap stamps
into every roadmap, so there's no format divergence to maintain.

## Solution Architecture

### Overview

Phase 7 gains an `input_type` check at the start of its multi-pr path. When
the input is a roadmap, step 7.2 writes into the roadmap file instead of
creating a PLAN doc. All other steps (issue creation, verification,
traceability) are shared.

### Components

```
skills/plan/
  SKILL.md                       <-- MODIFIED: update Output section and resume logic
  references/phases/
    phase-7-creation.md          <-- MODIFIED: add roadmap branch in step 7.2
  references/quality/
    plan-doc-structure.md        <-- UNCHANGED (PLAN doc format for design/prd)
  scripts/
    create-issues-batch.sh       <-- UNCHANGED (input-type-agnostic)

skills/roadmap/
  references/
    roadmap-format.md            <-- UNCHANGED (defines the reserved section contract)
```

### Key Interfaces

**Input: decomposition artifact frontmatter**

Phase 7 reads `input_type` and `upstream` from the decomposition artifact.
For roadmap input: `input_type: roadmap`, `upstream: docs/roadmaps/ROADMAP-<name>.md`.

**Branching point in step 7.2**

```
IF input_type == "roadmap":
  0. Validate: the roadmap has reserved sections (HTML comment markers
     present). If missing, fail with an error explaining the roadmap
     predates the format spec and needs the reserved sections added.
  1. Enforce multi-pr: if --single-pr was passed, reject with an error
     explaining roadmap features are independently scoped.
  2. Read the roadmap file at the upstream path.
  3. Locate the Implementation Issues section by its HTML comment marker:
     <!-- Populated by /plan during decomposition. Do not fill manually. -->
  4. Replace everything from the comment marker to the next ## heading
     (exclusive) with the populated table, preserving the comment marker.
  5. Locate the Dependency Graph section by its comment marker.
  6. Replace everything from the comment marker to the next ## heading
     (exclusive) with the full Mermaid diagram, preserving the comment.
  7. Write the modified roadmap back.
  8. Skip PLAN doc creation entirely.
ELSE:
  (existing PLAN doc creation -- unchanged)
```

**Implementation Issues table population**

From the issue mapping (output of step 7.1's batch script) and the manifest's
feature-to-issue mapping:

```markdown
## Implementation Issues

### Milestone: [<Name>](<milestone-url>)

| Feature | Issues | Status |
|---------|--------|--------|
| <Feature 1 name> | [#N](<url>) | needs-prd |
| <Feature 2 name> | [#M](<url>) | needs-design |
```

Feature names come from the decomposition artifact's feature list. Issue links
come from the batch script's output mapping. Status comes from each issue's
`needs_label` in the manifest.

**Dependency Graph population**

Same Mermaid format used for PLAN docs. Node IDs use `I<issue-number>`, labels
include issue number and short title, edges reflect feature dependencies from
the decomposition, and class assignments match needs-* labels.

### Data Flow

```
Decomposition artifact (input_type, features, manifest)
  |
  v
Step 7.1: create-issues-batch.sh --> GitHub issues + mapping.json
  |
  v
Step 7.2 (roadmap branch):
  Read roadmap file
  --> Locate reserved sections by HTML comment markers
  --> Build Implementation Issues table from mapping + manifest
  --> Build Mermaid graph from dependencies + mapping
  --> Write enriched roadmap
  |
  v
Steps 7.3-7.4: verify + traceability (shared, unchanged)
```

**Resume detection**

For roadmap input, Phase 7 is complete when the roadmap's Implementation
Issues section has content rows beyond the header. Check by reading the
roadmap and looking for issue links in the table.

## Implementation Approach

### Phase 1: Phase 7 roadmap branch

Add the `input_type` check, reserved section validation, multi-pr
enforcement, and roadmap-specific write path to `phase-7-creation.md`. This
is the core change: validate, locate reserved sections, build the table and
graph, write back.

Deliverables:
- `skills/plan/references/phases/phase-7-creation.md` (modified)

### Phase 2: SKILL.md and resume logic

Update the plan SKILL.md's Output section and resume logic to reflect that
roadmap input produces enriched roadmaps, not PLAN docs. Add roadmap-aware
completion detection: if `input_type: roadmap` and the roadmap file has a
populated Implementation Issues table, Phase 7 is complete.

Deliverables:
- `skills/plan/SKILL.md` (Output section and resume logic updated)
- `skills/plan/references/phases/phase-7-creation.md` (resume section updated)

### Phase 3: Evals

Add eval scenarios testing roadmap enrichment: verify the roadmap file
contains the populated table and graph, verify no PLAN doc was created.

Deliverables:
- `skills/plan/evals/evals.json` (new scenarios)

## Security Considerations

No security dimensions apply. This design modifies a skill's markdown phase
instructions to branch on input type and write into a different target file.
No external inputs are processed beyond what Phase 7 already handles. No
permissions change. No dependencies added. No user data flows change.

## Consequences

### Positive

- Roadmaps become the single location for implementation tracking, replacing
  the split between roadmap and PLAN doc
- The reserved section contract (from roadmap-format.md) is fulfilled as
  designed
- No changes to the Go binary, PLAN doc format, or /implement workflows
- The table format matches what /roadmap already stamps, avoiding format
  divergence

### Negative

- Phase 7's branching surface increases (one more conditional path)
- Resume logic needs a roadmap-aware check (reading the roadmap file instead
  of checking for a PLAN doc)
- The existing ROADMAP-koto-adoption.md uses a non-standard Implementation
  Issues format and would need updating separately

### Mitigations

- The branching follows the same pattern Phase 3 already uses for input_type,
  so it's not a new pattern to maintain
- Resume detection is a simple check (populated table rows) that mirrors
  the existing PLAN doc existence check
- The koto-adoption roadmap update is a separate cleanup, not a blocker
