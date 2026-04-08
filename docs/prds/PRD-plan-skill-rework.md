---
status: In Progress
problem: |
  The /plan skill produces a separate PLAN doc when consuming roadmaps,
  duplicating information the roadmap already has. The roadmap format
  reserves positions for an Issues table and Mermaid dependency graph,
  but /plan writes them into a separate PLAN doc instead of enriching
  the roadmap directly.
goals: |
  Rework /plan's roadmap mode to enrich the roadmap directly (no separate
  PLAN doc), always use multi-pr, and create per-feature GitHub issues.
  Preserve existing behavior for design doc and PRD inputs.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Plan Skill Rework

## Status

In Progress

## Problem statement

When /plan consumes a roadmap, it creates a separate PLAN doc that
duplicates the roadmap's feature list, dependencies, and sequencing. The
PLAN doc adds an Issues table and Mermaid dependency graph, but these
should live in the roadmap itself — the format already reserves positions
for them (added in F2). The current flow forces users to track two
documents for one initiative.

The duplication also creates a maintenance problem: when features are
added, reordered, or dropped, both the roadmap and the PLAN doc need
updating. The roadmap is the source of truth for features; the PLAN doc
is a derivative that adds only the issue links and dependency graph.
Those belong in the roadmap.

## Goals

- /plan enriches roadmaps directly instead of producing separate PLAN docs
- Roadmap mode is always multi-pr (features are independent work items)
- Per-feature GitHub issues created with needs-* labels
- Existing /plan behavior for design docs and PRDs is unchanged

## User stories

1. As a user who planned a roadmap, I want the issues table and dependency
   graph to live in the roadmap itself so I have one document to track
   instead of two.

2. As a user adding or dropping features from a roadmap, I want one place
   to update instead of keeping a roadmap and PLAN doc in sync.

3. As a contributor picking up a roadmap feature, I want a GitHub issue
   with the right needs-* label so I know what artifact to produce next.

## Requirements

### Functional

**R1. Roadmap mode: enrich instead of produce.** When /plan consumes a
roadmap (`input_type: roadmap`), it writes the Implementation Issues table
and Mermaid dependency graph directly into the roadmap document at the
reserved positions (defined in `roadmap-format.md`). Creates GitHub
milestone and per-feature issues with needs-* labels. No separate PLAN
doc produced.

Note: the roadmap must already be Active when /plan consumes it. This
matches the existing validation rule in /plan's Phase 1 (roadmaps must
be Active). The roadmap's Draft -> Active transition happens via
`/roadmap activate` before /plan runs, not during /plan execution.

**R2. Roadmap mode is always multi-pr.** Each roadmap feature becomes an
independent GitHub issue with a needs-* label. Single-pr mode doesn't
apply — roadmap features are independently scoped and may be worked on by
different people or in different repos. If `--single-pr` is passed with
a roadmap input, /plan should reject it with an error explaining why.

**R3. Consistent upstream status transitions.** When /plan runs on each
input type:
- Roadmap: no status change (already Active, stays Active)
- Design doc: Accepted -> Planned (existing behavior, preserved)
- PRD consumed directly by /plan: no status change (PRD lifecycle
  transitions are owned by /prd and the completion cascade, not /plan)

### Non-functional

**R4. Backward compatible.** Existing PLAN docs, /implement workflows,
and design-doc-based planning are unaffected. Changes only affect
roadmap-mode behavior in /plan's Phase 7.

**R5. No Go code changes for roadmap mode.** Roadmap enrichment is
handled in the skill's Phase 7, not in the Go binary. `parsePlanDoc()`
continues to parse PLAN docs only — it doesn't need to parse enriched
roadmaps.

## Acceptance criteria

- [ ] /plan consuming a roadmap writes Issues table + Mermaid graph into
      the roadmap document at reserved positions (no PLAN doc produced)
- [ ] /plan consuming a roadmap creates milestone + per-feature issues
      with needs-* labels
- [ ] /plan consuming a roadmap does not change roadmap status (already
      Active)
- [ ] Roadmap mode is always multi-pr (single-pr rejected with error)
- [ ] Design doc and PRD modes continue to produce PLAN docs (unchanged)
- [ ] Existing /implement and /work-on workflows are unaffected
- [ ] /plan's Phase 1 validation still requires Active roadmaps

## Out of scope

- Completion cascade automation (see F8 in roadmap)
- /prd reading upstream from plan issue context (see F9 in roadmap)
- Progress consistency enforcement (see F10 in roadmap)
- PRD transition script (see F11 in roadmap)
- Changes to /implement's controller loop or issue state machine
- Go code changes to parsePlanDoc() or workflow-tool
- New artifact types or lifecycle states
- Retroactive changes to existing PLAN docs or roadmaps

## Decisions and trade-offs

**Roadmap stays Active, /plan doesn't transition it.** The original draft
had /plan transitioning roadmaps Draft -> Active. Review found this
contradicts /plan's Phase 1 validation rule (roadmaps must already be
Active). The roadmap's Draft -> Active transition is owned by `/roadmap
activate`, which validates feature count and requires human approval.
/plan consumes an already-Active roadmap and enriches it.

**Progress consistency deferred.** The principle ("issue closure should
propagate to upstream artifact status") is real but the mechanism (hook,
skill step, CI check) needs its own design. Including it here would
conflate a clear plan-skill change with an unsolved orchestration
problem. See F10.

**Cascade deferred.** The completion cascade has blocking design questions
surfaced by review: milestone completion detection (who triggers it?),
feature identification (how does the cascade know which feature
completed?), and the "dropped" path (what status do abandoned artifacts
get?). These need their own PRD. See F8.

## Known limitations

- Without the completion cascade (F8), upstream artifact status updates
  after implementation remain manual. The memory note
  (`feedback_completion_cascade.md`) documents the steps.
- Without /prd issue-context detection (F9), users must pass `--upstream`
  manually when running /prd from a plan issue.

## Related

- **ROADMAP-strategic-pipeline.md** — Feature 5 describes this work
- **PRD-roadmap-skill.md** (Done) — defined the roadmap format including
  reserved positions for Implementation Issues and Dependency Graph that
  R1 populates
- **DESIGN-artifact-traceability.md** (Current) — F3 added the upstream
  fields that future cascade work (F8) relies on
- **F8 (Completion Cascade Automation)** — formalizes the cascade as a
  skill-driven step with milestone detection and dropped-feature handling
- **F9 (Upstream Context Propagation)** — /prd reads upstream from plan
  issue body automatically
- **F10 (Progress Consistency)** — issue closure propagates to upstream
  artifact tracking sections
- **F11 (Lifecycle Script Hardening)** — PRD transition script, design
  doc validate_transition(), dropped states
