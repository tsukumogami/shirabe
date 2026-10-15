# Phase 1: Source Document Analysis

Understand the source document's scope and identify implementation components or features.

## Resume Check

If key `work/analysis.md` exists in `plan-<topic>`, read it (`koto context get
plan-<topic> work/analysis.md`) and skip to Phase 2.

## Goal

Extract from the source document:
- What needs to be built
- Key components (design/prd) or features (roadmap) and their boundaries
- Implementation phases defined in the document
- Success criteria that translate to acceptance criteria

## Steps

### 1.0 Determine Input Type

Detect the input type from the source document path:

| Path Pattern | input_type | Expected Status |
|-------------|------------|-----------------|
| `docs/designs/DESIGN-*.md` | design | Accepted |
| `docs/prds/PRD-*.md` | prd | Accepted |
| `docs/roadmaps/ROADMAP-*.md` | roadmap | Active |

Store the `input_type` for use in subsequent steps and phases.

### 1.0a Resolve the Plan Version

Decide which plan version this run writes, before anything else is read or
written. Run the resolver and copy its answer; do not apply the precedence
yourself:

```bash
${CLAUDE_SKILL_DIR}/scripts/resolve-plan-version.sh \
  [--plan-version=<value>] \
  [--claude-md <repo-root>/CLAUDE.md]
```

Pass `--plan-version` with the value exactly as the run was given it, when it
was given, and `--claude-md` when the repository root has a `CLAUDE.md`. The
script prints one line, `v1` or `v2`: the flag wins, then a
`## Plan Version: v1|v2` header in that CLAUDE.md (outside fenced code), then
the default, which is `v1`.

**A non-zero exit stops the run** with the script's stderr line: a value other
than `v1` or `v2` (an empty one included), or two `## Plan Version:` headers in
CLAUDE.md. Nothing has been written at that point and nothing is. A run given
`--plan-version` never reads the header, so a bad header does not stop it.

Store the version for every later phase:

- **`v1`** -- the run is exactly the `plan/v1` run the rest of this skill
  describes. Phases 3, 4 and 7 take their `plan/v1` paths.
- **`v2`** -- the run writes a `plan/v2` step plan. Phase 3 decomposes into
  steps, Phase 4 details steps 1 and 2 only, and Phase 7 writes
  `schema: plan/v2`. Roadmap input does not apply: a roadmap plans one
  planning issue per feature, which a step plan has no form for, so with
  `input_type: roadmap` and `v2` stop with "a roadmap is planned with
  `--plan-version=v1`; step plans are for designs, PRDs and topics" before
  anything is written.

### 1.1 Validate Source Document Status

Read the source document at the path provided in $ARGUMENTS and check the Status field.

**For design docs and PRDs** (input_type: design or prd):

**Invoke the `design-doc` skill** and validate against "/plan phase-1" requirements:
- Status MUST be "Accepted"
- All required sections must be present

This phase does not transition the DESIGN, with or without a parent's
dispatch key: a DESIGN `/scope`'s design hop leaves at
`Accepted` passes the check below as it is, and Phase 7's step 7.5 is the one
place `/plan` moves it to `Planned`.

**STOP and inform user if status is not "Accepted".** The consumable-status
rule is owned by the chain-status lifecycle check (`shirabe validate
--lifecycle-chain <design-path>`); the messages below are the per-status
guidance shown when that gate stops, not a second copy of the rule:

| Status | Error Message |
|--------|--------------|
| Proposed | "This design has status 'Proposed'. It must be reviewed and changed to 'Accepted' before creating issues. Submit a PR for review." |
| Planned | "This design has status 'Planned'. Issues have already been created. Use `gh issue list --search 'Design: <path>'` to find them." |
| Current | "This design has status 'Current'. Implementation is complete. No new issues needed." |
| Superseded | "This design has status 'Superseded'. It has been replaced by a newer design. Check the superseding document." |

Do NOT proceed with issue creation unless status is "Accepted".

**For roadmaps** (input_type: roadmap):

**Invoke the `roadmap` skill** and validate against "/plan phase-1" requirements:
- Status MUST be "Active"
- All required sections must be present (Status, Theme, Features, Sequencing Rationale, Progress)

**STOP and inform user if status is not "Active":**

| Status | Error Message |
|--------|--------------|
| Draft | "This roadmap has status 'Draft'. The feature list must be locked and approved before planning. Change status to 'Active'." |
| Done | "This roadmap has status 'Done'. All features are already delivered. No new planning needed." |

**If status is valid:** Continue to step 1.2.

### 1.2 Extract Key Information

**For design docs and PRDs** (input_type: design or prd):

Identify and document:

- **Scope Summary**: 1-2 sentence summary of what this design delivers
- **Components**: List each component with brief description
- **Implementation Phases**: Copy from design's Implementation Approach section
- **Success Metrics**: Copy from design's Consequences/Success Criteria sections

**For roadmaps** (input_type: roadmap):

Identify and document:

- **Scope Summary**: 1-2 sentence summary from the roadmap's Theme and Scope
- **Features**: List each feature from the Features section with:
  - Feature name
  - Brief description (1-2 sentences)
  - `needs_label`: the `needs-*` label this feature requires (needs-prd, needs-design,
    needs-spike, or needs-decision). Determine from:
    1. Explicit annotation in the roadmap (if the feature references its downstream
       artifact type or notes what's needed next)
    2. Feature description content (requirements unclear -> needs-prd, approach
       unclear -> needs-design, feasibility unknown -> needs-spike, single choice
       between options -> needs-decision)
    3. If ambiguous, use AskUserQuestion for each unclear feature. Do not present
       the labels as a bare list: pick the one the feature description best
       supports, mark it "(Recommended)", and ground the pick in the specific
       wording that decided it (quote the phrase from the feature description or
       roadmap annotation). Give each alternative a short reason for ranking
       lower. If the description genuinely doesn't discriminate, say so, still
       recommend one, and name the tiebreaker -- default to the earlier-stage
       artifact (needs-prd before needs-design, needs-design before needs-spike)
  - Reference to your project's label vocabulary (see `## Label Vocabulary` in your CLAUDE.md)
- **Sequencing Rationale**: Copy from roadmap's Sequencing Rationale section
- **Progress**: Current state from roadmap's Progress section

### 1.3 Note Dependencies

**For design docs and PRDs**: Identify external dependencies (other designs, existing code/features, required skills or commands).

**For roadmaps**: Note cross-feature dependencies from the Sequencing Rationale section. These will be imported in Phase 5.

### 1.4 Write Artifact

Write key `work/analysis.md` in `plan-<topic>` (`koto context add plan-<topic> work/analysis.md`,
the content on stdin).

**For design docs and PRDs** (input_type: design or prd):

```markdown
# Plan Analysis: <doc-name>

## Source Document
Path: <path-to-doc>
Status: Accepted
Input Type: <design|prd>
Plan Version: <v1|v2>

## Scope Summary
<1-2 sentence summary of what this design delivers>

## Components Identified
- <Component 1>: <brief description>
- <Component 2>: <brief description>
- <Component 3>: <brief description>

## Implementation Phases (from design)
<Copy the Implementation Approach section verbatim>

## Success Metrics
<Copy Consequences/Success Criteria sections>

## External Dependencies
- <dependency 1>: <why needed>
- <dependency 2>: <why needed>
```

**For roadmaps** (input_type: roadmap):

```markdown
# Plan Analysis: <roadmap-name>

## Source Document
Path: <path-to-roadmap>
Status: Active
Input Type: roadmap
Plan Version: v1

## Scope Summary
<1-2 sentence summary from Theme and Scope>

## Features Identified
- <Feature 1>: <brief description>
  - needs_label: <needs-prd|needs-design|needs-spike|needs-decision>
- <Feature 2>: <brief description>
  - needs_label: <needs-prd|needs-design|needs-spike|needs-decision>
- <Feature 3>: <brief description>
  - needs_label: <needs-prd|needs-design|needs-spike|needs-decision>

## Sequencing Rationale (from roadmap)
<Copy the Sequencing Rationale section verbatim>

## Progress
<Copy the Progress section verbatim>

## Cross-Feature Dependencies
- <Feature A> depends on <Feature B>: <why>
- <Feature C> depends on <Feature A>: <why>
```

## Quality Checklist

Before proceeding:
- [ ] Source document status is valid ("Accepted" for design/prd, "Active" for roadmap)
- [ ] Full source document read
- [ ] `input_type` field recorded (design, prd, or roadmap)
- [ ] `Plan Version` recorded, copied from `resolve-plan-version.sh`

## Next Phase

Proceed to Phase 2: Milestone (`phase-2-milestone.md`)
