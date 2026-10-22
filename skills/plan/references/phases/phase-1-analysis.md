# Phase 1: Source Document Analysis

Understand the source document's scope and identify implementation components or features.

## Resume Check

If key `work/analysis.md` exists in `plan-<topic>`, read it (`koto context get
plan-<topic> work/analysis.md`), check a `--plan-version` the new invocation
carries against its recorded version (step 1.0a, "On a resume"), and skip to
Phase 2.

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
${CLAUDE_SKILL_DIR}/scripts/resolve-plan-version.sh --with-source \
  [--plan-version=<value>] \
  [--claude-md <repo-root>/CLAUDE.md] \
  [--needs-v1=roadmap]
```

Pass `--plan-version` with the value exactly as the run was given it, when it
was given, `--claude-md` when the repository root has a `CLAUDE.md`, and
`--needs-v1=roadmap` when `input_type` is `roadmap`. The script prints two
lines, `plan_version=<v1|v2>` and `plan_version_source=<flag|header|default>`:
the flag wins, then a `## Plan Version: v1|v2` header in that CLAUDE.md
(outside fenced code), then the default, which is `v2`. Record both in
`work/analysis.md` as `Plan Version:` and `Plan Version Source:`.

**The default gives way to `v1` where a step plan can't run:** on roadmap
input, or when that CLAUDE.md's `## Tracking Level:` header names `issues` or
`issues-and-milestone`. The script then prints `v1` with the source still
`default`, and one stderr line saying why; repeat that line to the author as
it stands, so nobody is surprised by a `plan/v1` plan. Step 3.6's step 5a does
the same for a split that resolves to `coordinated`. A flag or header that
asks for `v2` never gives way.

**On a resume the recorded version stands.** When the Resume Check above
finds `work/analysis.md`, don't resolve the version again; the flag and header
are not read a second time. If the new invocation carries `--plan-version`,
check it against the record. This check runs on every resume, at whichever
phase SKILL.md's Resume Logic re-enters, not only when the run comes back
through Phase 1:

```bash
${CLAUDE_SKILL_DIR}/scripts/resolve-plan-version.sh --with-source \
  --stored-version=<Plan Version> --stored-source=<Plan Version Source> \
  --plan-version=<value>
```

The same version prints it back with source `flag`: the author has now asked
for it, so write `Plan Version Source: flag` into `work/analysis.md`, and a
`v2` that came from the default no longer gives way. A different version exits non-zero ("this run started with plan version ...;
resume it with ... or start a fresh run"). Stop with that line and change
nothing. A fresh run starts once the interrupted session is closed, with
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close plan-<topic> abandoned`:
the next `/plan` on the topic then opens a new session instead of resuming.
Say so to the author, and leave the closing to them; the run itself never
discards its own record. An analysis with no `Plan Version Source:` line was written before
the source was recorded. Read it as `flag`, since `v2` could only be asked for
then and a `v1` never gives way.

**A non-zero exit stops the run** with the script's stderr line: a value other
than `v1` or `v2` (an empty one included), two `## Plan Version:` headers in
CLAUDE.md, or roadmap input with `v2` asked for by flag or header ("a roadmap
is planned with --plan-version=v1; step plans are for designs, PRDs and
topics"). Nothing has been written at that point and nothing is. A run given
`--plan-version` never reads the header, so a bad header does not stop it.

Store the version for every later phase:

- **`v1`** -- the run is exactly the `plan/v1` run the rest of this skill
  describes. Phases 3, 4 and 7 take their `plan/v1` paths.
- **`v2`** -- the run writes a `plan/v2` step plan. Phase 3 decomposes into
  steps, Phase 4 details steps 1 and 2 only, and Phase 7 writes
  `schema: plan/v2`. A roadmap never reaches it: a roadmap plans one
  planning issue per feature, which a step plan has no form for, so the
  resolver either gave way to `v1` or stopped the run above.

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
- **Features**: List each feature from the Features section (the Milestones
  section on a `roadmap/v3` roadmap, whose items are milestones) with:
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
Plan Version Source: <flag|header|default>

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
Plan Version Source: <flag|header|default>

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
- [ ] `Plan Version` and `Plan Version Source` recorded, copied from `resolve-plan-version.sh --with-source`

## Next Phase

Proceed to Phase 2: Milestone (`phase-2-milestone.md`)
