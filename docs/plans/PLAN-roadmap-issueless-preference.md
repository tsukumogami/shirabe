---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Issueless roadmap mode"
issue_count: 6
upstream: docs/designs/DESIGN-roadmap-issueless-preference.md
---

# PLAN: roadmap-issueless-preference

## Status

Draft

Single-pr plan decomposing `docs/designs/DESIGN-roadmap-issueless-preference.md`
(Accepted) into six atomic issues across the design's three batches. No GitHub
issues or milestone are materialized; the implementing agent works the outlines
below in dependency order on one branch and ships one PR.

## Scope Summary

Add an issueless, feature-keyed roadmap mode to shirabe as a repo/org
preference. A `## Roadmap Issues: optional` CLAUDE.md header (default
`required`) is read by the roadmap skill; when `optional`, `shirabe roadmap
populate` renders the Implementation Issues table and Dependency Graph from the
Features section with no `gh issue create` and no R14 gate, and the
"Do not fill manually" instruction is conditioned on the preference.
Dependencies cells in issueless mode are bare feature keys, so the validator is
left unchanged (the issueless shape validates clean today). The implementation
contract: preference plumbing and docs (Batch 1), the issueless render path and
skill branch (Batch 2), and chain framing plus evals (Batch 3).

## Decomposition Strategy

Feature-by-feature within a walking-skeleton spine, sliced along the design's
three batches and grouped by the unit each touches:

- **Batch 1 (preference plumbing + docs)** -- one issue for the header
  definition and roadmap-format documentation, one for the skill reading the
  header. Lands the preference as a documented, hand-authorable mode before any
  tooling.
- **Batch 2 (issueless render path)** -- one issue for the CLI subcommand mode
  (Rust + tests), one for branching the skill's populate path and R14 gate on
  the preference. Makes the sections tool-generated.
- **Batch 3 (framing + evals)** -- one issue for the chain/SKILL prose, one for
  evals proving both modes.

Grouping rule: one issue per unit of change (one doc surface, one skill read,
one subcommand mode, one skill branch, one prose surface, one eval set). The
CLI subcommand issue (I3) is the walking-skeleton risk and can proceed in
parallel with the header/skill-read issues.

## Issue Outlines

### Issue 1: docs(roadmap): add `## Roadmap Issues:` header and issueless authoring rules

**Goal**: Define the `## Roadmap Issues: optional | required` convention header
and document the issueless mode's authoring rules so a clean issueless roadmap
can be hand-produced even before the subcommand lands.

**Acceptance Criteria**:
- `references/fixes/claude-md-conventions.md` lists `## Roadmap Issues:` with
  values `optional | required`, default `required` when absent, alongside the
  other convention headers (so FC-CONVENTIONS recognizes it).
- `skills/roadmap/references/roadmap-format.md` documents the issueless branch:
  under `optional` the reserved sections are populated from feature context, and
  Dependencies cells are bare feature keys (`F1`, `F1, F2`, `None`) -- annotated
  forms (`F1 (soft)`, `None (ext: ...)`) are called out as FC06-rejected, with
  soft/external nuance directed to feature prose and Sequencing Rationale.
- The two `<!-- ... Do not fill manually. -->` markers are conditioned on the
  preference rather than stating issue-population unconditionally.
- `shirabe validate` is clean on a feature-keyed bare-key roadmap fixture.

**Dependencies**: None

**Files**: `references/fixes/claude-md-conventions.md`,
`skills/roadmap/references/roadmap-format.md`

### Issue 2: feat(roadmap-skill): read `## Roadmap Issues:` preference during discovery

**Goal**: Teach the roadmap skill to read the preference into run context,
mirroring the existing `## Execution Mode:` read, defaulting to `required`.

**Acceptance Criteria**:
- The roadmap skill's discovery/setup reads `## Roadmap Issues:` from CLAUDE.md
  and records the resolved value (`optional` or `required`) in run context.
- Absent header or unrecognized value resolves to `required` (fail-closed).
- The read mirrors the `## Execution Mode:` mechanism (same grep-and-default
  shape), with no validator involvement.

**Dependencies**: Issue 1 (the header must be defined and documented)

**Files**: `skills/roadmap/SKILL.md`, `skills/roadmap/references/phases/phase-1-scope.md`

### Issue 3: feat(cli): issueless render mode for `shirabe roadmap populate`

**Goal**: Add an issueless mode (e.g. `--no-issues`) to `shirabe roadmap
populate` that renders a feature-keyed Implementation Issues table and an
`F`-node Dependency Graph from the Features section, skipping `gh issue create`.

**Acceptance Criteria**:
- The subcommand accepts the issueless flag; in that mode it reuses the shared
  feature parser, table renderer, diagram renderer, and structural
  section-replacement writer, omitting the issue-creation loop.
- Output: Issues column carries each feature's `needs-*` label, diagram nodes
  are `F<n>`, dependency edges derive from Features-section deps as bare keys.
- The issue-creating path is unchanged when the flag is absent.
- Unit tests cover the issueless render (table shape, `F`-node diagram, no
  GitHub calls) and a generated fixture validates clean via `shirabe validate`.

**Dependencies**: None

**Files**: `crates/` (the `roadmap populate` subcommand and its tests)

### Issue 4: feat(roadmap-skill): branch populate path and R14 gate on the preference

**Goal**: Wire the skill's populate input mode to the preference: `required`
keeps the issue-creating path plus the R14 approval gate; `optional` calls the
issueless render and skips R14.

**Acceptance Criteria**:
- Under `required` (or absent header), `/roadmap populate` behaves exactly as
  today (issue creation, R14 gate).
- Under `optional`, `/roadmap populate` invokes the issueless subcommand mode,
  creates no issues, and does not present the R14 gate.
- The branch is covered by the skill's documented behavior in SKILL.md.

**Dependencies**: Issue 2, Issue 3

**Files**: `skills/roadmap/SKILL.md`, `skills/roadmap/references/phases/`

### Issue 5: docs(roadmap): present both populate modes in chain and SKILL framing

**Goal**: Update prose that presents issue creation as the only populate
outcome to present the two modes, including the `/charter` chain framing.

**Acceptance Criteria**:
- The roadmap SKILL populate section and the `/charter` chain text describe both
  the issue-creating and issueless modes and when each applies.
- No remaining prose implies issue creation is the only populate outcome.

**Dependencies**: Issue 4

**Files**: `skills/roadmap/SKILL.md`, `skills/charter/SKILL.md`

### Issue 6: test(roadmap): evals for issueless and issue-creating populate

**Goal**: Add/refresh roadmap skill evals proving an `optional`-repo run does
an issueless populate (no issue creation, clean validation) and a
`required`-repo run is unchanged.

**Acceptance Criteria**:
- `skills/roadmap/evals/evals.json` has a scenario for an `optional`-repo
  issueless populate and asserts no `gh issue create` and a clean validate.
- The existing issue-creating populate scenario still passes unchanged.
- Evals are executed per the repo's eval discipline before merge.

**Dependencies**: Issue 4

**Files**: `skills/roadmap/evals/evals.json`

## Implementation Sequence

Open with **I1** (header + docs) and **I3** (CLI issueless render) in parallel --
they are the two roots and carry the only real risk (I3 is the Rust subcommand
mode). Then **I2** (skill reads the preference) once I1 lands the header
definition. **I4** (skill populate + R14 branch) is the integration point and
waits on both I2 and I3; it is where the two tracks meet and the feature first
works end-to-end. Finish with **I5** (framing) and **I6** (evals), which both
depend only on I4 and can run in parallel to close out. Critical path:
I1 → I2 → I4 → I6 (or I5).
