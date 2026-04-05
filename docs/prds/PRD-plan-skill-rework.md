---
status: Draft
problem: |
  The /plan skill produces a separate PLAN doc when consuming roadmaps,
  duplicating information the roadmap already has. The completion cascade
  (what happens when all planned work finishes) is practiced manually but
  not formalized in any skill. Progress consistency between issue closure
  and upstream artifact status is also manual.
goals: |
  Rework /plan to enrich roadmaps directly (no separate PLAN doc),
  formalize the completion cascade as a skill-driven step, and close the
  /prd upstream propagation gap from plan issue context.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Plan Skill Rework

## Status

Draft

## Problem statement

Three problems, in priority order:

**1. Roadmap enrichment produces a redundant artifact.** When /plan
consumes a roadmap, it creates a separate PLAN doc that duplicates the
roadmap's feature list, dependencies, and sequencing. The PLAN doc adds
an Issues table and Mermaid dependency graph, but these should live in
the roadmap itself — the format already reserves positions for them
(added in F2). The current flow forces users to track two documents for
one initiative.

**2. The completion cascade is manual and error-prone.** When all planned
work finishes, the upstream artifacts need status updates: PLAN docs get
deleted, design docs move to Current, PRDs move to Done, roadmap progress
tables update. We've done this manually after F1, F2, F3, and F4 — and
forgotten it twice until reminded. The steps are well-understood but no
skill owns them.

**3. /prd doesn't read upstream from plan issue context.** F3 added
`--upstream` flag support to /prd, but when /prd is invoked from a plan
issue (e.g., a needs-prd issue from a roadmap), it doesn't read the
`Roadmap:` line that /plan already puts in the issue body. The user has to
pass `--upstream` manually. This is a small gap identified in the F3
design as a "follow-up."

## Goals

- /plan enriches roadmaps directly instead of producing separate PLAN docs
- The completion cascade becomes a skill-driven step, not manual memory
- /prd reads upstream from plan issue context automatically
- Existing /plan behavior for design docs and PRDs is unchanged

## User stories

1. As a user who planned a roadmap, I want the issues table and dependency
   graph to live in the roadmap itself so I have one document to track
   instead of two.

2. As a user finishing all planned work, I want a command or skill step
   that runs the completion cascade so I don't have to remember the four
   steps manually.

3. As a user running /prd from a needs-prd plan issue, I want the PRD's
   upstream field automatically set to the roadmap path from the issue
   body so the traceability chain stays connected.

## Requirements

### Functional

**R1. Roadmap mode: enrich instead of produce.** When /plan consumes a
roadmap (`input_type: roadmap`), it writes the Implementation Issues table
and Mermaid dependency graph directly into the roadmap document at the
reserved positions. Creates GitHub milestone and per-feature issues with
needs-* labels. Transitions roadmap Draft -> Active via transition script.
No separate PLAN doc produced.

**R2. Roadmap mode is always multi-pr.** Each roadmap feature becomes an
independent GitHub issue with a needs-* label. Single-pr mode doesn't
apply — roadmap features are independently scoped and may be worked on by
different people or in different repos.

**R3. Consistent upstream status transitions.** When /plan runs on each
input type:
- Roadmap: Draft -> Active (feature list locked, planning complete)
- Design doc: Accepted -> Planned (existing behavior, preserved)
- PRD consumed directly by /plan: no status change by /plan (PRDs get
  transitioned to In Progress by /design Phase 0, not by /plan)

**R4. Completion cascade as a skill step.** Formalize the completion
cascade as a defined step in /implement's Phase 2 (complete). The cascade
runs after all issues are implemented and before the PR is finalized.
The steps, based on 4 iterations of manual practice:
- Delete the PLAN doc (if one exists — roadmap mode doesn't produce one)
- Move the upstream DESIGN doc to `docs/designs/current/` with Current
  status (via transition script)
- Update the upstream PRD status to Done
- Update the upstream ROADMAP progress table to reflect the feature as
  Done

The cascade reads the traceability chain from `upstream` frontmatter
fields (added in F3) to find the artifacts to update.

**R5. /prd reads upstream from plan issue context.** When /prd is invoked
in the context of a plan issue (e.g., from /work-on on a needs-prd issue),
the /prd skill reads the `Roadmap:` line from the issue body and uses it
as the upstream path in frontmatter. This supplements the `--upstream`
flag (which still works for standalone invocations).

**R6. Progress consistency principle.** When a planned issue is closed,
the upstream artifact's tracking section should reflect it. For roadmaps:
Progress section feature status. For PLAN docs: Issues table
strikethrough. The principle is documented; the enforcement mechanism is
left to the implementer (could be a /work-on completion step, a hook, or
manual convention).

### Non-functional

**R7. Backward compatible.** Existing PLAN docs, /implement workflows,
and design-doc-based planning are unaffected. Changes only affect
roadmap-mode behavior, the completion cascade, and /prd's issue-context
detection.

**R8. No Go code changes for roadmap mode.** Roadmap enrichment is
handled in the skill's Phase 7, not in the Go binary. `parsePlanDoc()`
continues to parse PLAN docs only — it doesn't need to parse enriched
roadmaps.

## Acceptance criteria

- [ ] /plan consuming a roadmap writes Issues table + Mermaid graph into
      the roadmap document at reserved positions (no PLAN doc produced)
- [ ] /plan consuming a roadmap creates milestone + per-feature issues
      with needs-* labels
- [ ] /plan consuming a roadmap transitions it Draft -> Active via
      transition script
- [ ] Roadmap mode is always multi-pr (single-pr rejected for roadmaps)
- [ ] Design doc and PRD modes continue to produce PLAN docs (unchanged)
- [ ] Completion cascade runs as a defined step in /implement Phase 2
- [ ] Cascade reads upstream chain from frontmatter fields
- [ ] /prd reads `Roadmap:` line from plan issue body when invoked from
      issue context
- [ ] Existing /implement and /work-on workflows are unaffected

## Out of scope

- Changes to /implement's controller loop or issue state machine
- Go code changes to parsePlanDoc() or workflow-tool
- New artifact types or lifecycle states
- Automatic issue-closure-to-progress-update enforcement (R6 documents
  the principle; enforcement mechanism is a design decision)
- Retroactive changes to existing PLAN docs or roadmaps

## Decisions and trade-offs

**Cascade as /implement Phase 2 step, not standalone command.** The
cascade always runs after implementation completes. Making it a step in
/implement Phase 2 rather than a separate `/cascade` command keeps it
in the workflow where it's needed. A standalone command would be used
only when someone forgets — and the point is to not forget.

**R6 documents principle, defers enforcement.** We've done progress
updates manually 4 times. The pattern is clear but the mechanism (hook,
skill step, CI check) isn't. Specifying the principle without the
mechanism lets the design choose the right approach.

**/prd issue-context detection is narrow scope.** R5 only adds reading
the `Roadmap:` line from plan issue bodies. It doesn't add a general
"detect context from any source" system. This is the smallest change
that closes the F3 gap.

## Known limitations

- The completion cascade (R4) assumes the upstream chain is traceable
  via `upstream` frontmatter fields. Artifacts created before F3 (which
  added upstream propagation) may lack these fields, requiring manual
  cascade steps for older work.
- Progress consistency (R6) is a documented principle, not enforced.
  Until enforcement ships, manual updates remain necessary.

## Related

- **ROADMAP-strategic-pipeline.md** — Feature 5 describes this work
- **PRD-roadmap-skill.md** (Done) — defined the roadmap format including
  reserved positions for Implementation Issues and Dependency Graph that
  R1 populates
- **DESIGN-artifact-traceability.md** (Current) — F3 added the upstream
  fields that R4's cascade relies on for chain traversal
- **PRD-complexity-routing-expansion.md** (Done) — F4 added the Strategic
  routing level that sends work through VISION -> Roadmap -> /plan
