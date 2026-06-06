---
schema: prd/v1
status: In Progress
problem: |
  The completion cascade is a bash script that re-implements lifecycle knowledge
  the Rust transition engine already owns -- frontmatter parsing, per-artifact-type
  dispatch, and the per-type terminal-transition decision. The two copies drift,
  and the bash copy cannot explain engine rejections: it captures only the first
  line of the engine's JSON error and surfaces a bare brace. Maintainers who change
  a type's lifecycle must edit both copies or the cascade silently diverges.
goals: |
  Make the engine the single authority for the cascade's lifecycle decisions: the
  chain walk, per-node type resolution, and the legal terminal transition move into
  a shirabe subcommand backed by the existing engine, which returns a typed result
  and typed, type-aware errors. The cascade script shrinks to git orchestration
  around that subcommand, with its externally consumed output preserved unchanged.
upstream: docs/briefs/BRIEF-finalize-chain.md
---

# PRD: finalize-chain

## Status

In Progress

## Problem Statement

The post-implementation completion cascade (`skills/work-on/scripts/run-cascade.sh`)
walks a finished PLAN's `upstream` frontmatter chain and brings each node to its
terminal lifecycle state: the PLAN is deleted, a DESIGN moves to its Current state,
and a PRD and a BRIEF move to Done. To do that, the bash script re-implements three
things the Rust transition engine already owns: an inline awk frontmatter reader, a
filename-prefix `case` that mirrors the engine's format detection, and a per-branch
hardcoding of the legal target status for each artifact type.

Two copies of the same lifecycle knowledge, in two languages, are free to drift. The
drift is observable today: every cascade handler captures only the first line of the
engine's output (`head -1`) as its failure detail, and because the engine reports
rejections as JSON, that first line is a bare `{`. The cascade emits a brace as its
error message, with no awareness of why the transition was refused -- for instance,
that the rejected artifact is an ordered, graph-constrained type (where skipping a
state is illegal) rather than a membership type (where any state is reachable). The
engine holds that distinction; the bash glue structurally cannot. A maintainer who
adds an artifact type or retargets a type's terminal state must remember to edit both
the engine and the bash, or the cascade silently falls out of step with the authority.

Who is affected: the skill maintainers who own the cascade and the transition engine,
and the engineers who run the cascade at the end of a PLAN's implementation and have
to debug it when a chain node will not transition.

## Goals

- The engine becomes the single authority for the cascade's lifecycle decisions:
  walking the chain, resolving each node's artifact type, and deciding the legal
  terminal transition all happen in one place, so there is no second copy to drift.
- A cascade that hits a refused transition produces a typed, type-aware explanation
  rather than a fragment of an internal payload.
- The cascade script keeps the exact external output its callers depend on, so moving
  the logic into the engine is invisible to everything downstream of the cascade.

## User Stories

- As a skill maintainer, I want to change a type's terminal lifecycle behavior in one
  place (the engine) so that the cascade inherits the change with no parallel bash
  edit and no risk of the two diverging.
- As an engineer running a cascade that refuses a transition, I want a message naming
  the node, its type, the attempted transition, and the reason, so that I can fix the
  offending document instead of decoding a one-character error.
- As a maintainer of the cascade script, I want the script reduced to invoking the
  subcommand and performing git operations, so that the lifecycle logic and the
  version-control actions are cleanly separated and the script is small enough to read.
- As a consumer of the cascade's output (the implementation workflow that runs it), I
  want the cascade's emitted status contract unchanged, so that nothing downstream has
  to be re-wired when the internals move.

## Requirements

Functional:

- **R1.** A `shirabe` subcommand SHALL accept a PLAN document path and walk its
  `upstream` frontmatter chain, resolving each node's artifact type using the engine's
  existing format detection -- without any frontmatter parsing or type dispatch outside
  the engine.
- **R2.** For each resolved chain node, the subcommand SHALL determine the legal
  terminal transition for that artifact type from the engine's transition spec (a
  DESIGN to its Current state, a PRD and a BRIEF to Done) and apply it through the
  engine's existing transition logic.
- **R3.** The subcommand SHALL treat the originating PLAN as a delete-not-transition
  node (the engine carries no PLAN type) and report it as such. The subcommand SHALL
  NOT perform the deletion itself.
- **R4.** The subcommand SHALL NOT perform any version-control operation. It SHALL
  report the documents it modified, the documents it moved (with both the source and
  destination path), and the PLAN marked for deletion, so the calling layer can stage
  exactly those paths.
- **R5.** On success the subcommand SHALL emit a machine-readable result enumerating
  each chain node, its resolved artifact type, the transition applied (the prior and
  the new status), and any path move, following the JSON-envelope style of the existing
  single-document transition output.
- **R6.** When a node's transition is refused, the subcommand SHALL emit a structured
  error that names the node path, its artifact type, the attempted transition, and the
  engine's reason for refusing it. It SHALL NOT surface a bare fragment of an internal
  payload as the error.
- **R7.** The subcommand SHALL distinguish, by exit code, a clean success from a
  lifecycle violation (an illegal or precondition-failing transition) from a tool error
  (a missing, unreadable, or unparseable input), consistent with the exit-code levels
  the existing single-document transition already uses.
- **R8.** `run-cascade.sh` SHALL continue to emit its current stdout contract -- a
  `cascade_status` of `completed`, `partial`, or `skipped`, and a `steps` array whose
  objects carry `action` (one of `delete_plan`, `transition_design`, `transition_prd`,
  `transition_brief`, `update_roadmap_feature`, `transition_roadmap`), `target`,
  `found_in`, `status`, and `detail` -- and SHALL preserve its current exit-code
  behavior: exit 0 whenever the cascade ran (including the `partial` case), and exit 1
  only on a setup or precondition failure that prevents the cascade from running at all
  (for example: the PLAN document is missing or fails path validation, the working
  directory is not a git repository, or the `shirabe` binary cannot be resolved). It
  MAY derive this output by translating the subcommand's typed result.
- **R9.** After the change, `run-cascade.sh` SHALL contain no per-artifact-type dispatch
  and no frontmatter parsing of its own. Its remaining responsibilities are invoking the
  subcommand and performing the git operations (remove, move, stage, commit, push) the
  subcommand's report directs.

Non-functional:

- **R10.** The cascade's observable lifecycle behavior SHALL be preserved: which nodes
  transition to which states, the removal of a DESIGN node's `## Implementation Issues`
  section before it transitions, the `cascade_status` outcome for each currently covered
  scenario, idempotency on a second run, and the skipped and partial cases. Whether the
  Implementation-Issues removal runs as an engine body-edit or as a step in the cascade
  script is left to the design; its observable result is preserved either way.
  Preservation SHALL be verified by keeping the existing cascade test scenarios green
  (updated only where an output change is deliberate and documented in the change's own
  PR description and tests) and by paired tests covering the new subcommand directly.
- **R11.** The subcommand SHALL be deterministic and SHALL operate only on local files;
  it SHALL NOT perform network access. (External-state-dependent cascade behavior is out
  of scope -- see Out of Scope.)

## Acceptance Criteria

- [ ] A subcommand exists that takes a PLAN path, walks its `upstream` chain, and
      resolves each node's type via the engine's format detection (R1).
- [ ] For a chain containing a DESIGN, a PRD, and a BRIEF, the subcommand applies
      DESIGN-to-Current, PRD-to-Done, and BRIEF-to-Done via the engine (R2).
- [ ] The subcommand reports the originating PLAN as a delete node and does not itself
      remove it (R3).
- [ ] The subcommand performs no git command; its output names every modified path,
      every move as a source/destination pair, and the PLAN-to-delete (R4).
- [ ] On success the subcommand emits machine-readable JSON enumerating per-node type,
      applied transition (old and new status), and any move (R5).
- [ ] Given a node whose current status cannot legally reach its terminal state, the
      subcommand emits a structured error naming the node, its type, the attempted
      transition, and the reason -- and never a bare brace (R6).
- [ ] The subcommand returns distinct exit codes for clean success, a lifecycle
      violation, and a tool error, matching the level scheme the single-document
      transition already uses, so a caller can branch on them (R7).
- [ ] `run-cascade.sh` emits the same `cascade_status` values and `steps` object shape
      as before, and the same exit codes, verified against the existing test scenarios (R8).
- [ ] `run-cascade.sh` no longer contains an artifact-type `case` block or a frontmatter
      parser; grepping the script for those constructs finds none (R9).
- [ ] All existing cascade test scenarios pass unchanged except where an output change is
      deliberately documented; new tests exercise the subcommand directly (R10).
- [ ] The subcommand makes no network calls (R11).

## Out of Scope

- **Git operations.** Remove, move, stage, commit, and push stay in the cascade script;
  the CLI deliberately does not own version control.
- **ROADMAP feature-status updates and the completion guard.** Editing a roadmap's
  feature-status body content, and the "all features done plus all referenced issues
  closed" check that guards a full roadmap transition, stay in the cascade script. That
  work edits body prose and consults external issue-tracker state, which is not a
  deterministic local single-document transition; folding any of it into the engine is a
  separate question this PRD does not take on.
- **Workflow orchestration.** When the cascade runs, the dry-run-versus-push behavior,
  and how the cascade is wired into the surrounding skill, remain the skill's concern.
- **The single-document transition contract.** The existing per-document transition
  subcommand's behavior and output are reused, not changed.
- **A strategic-chain analog.** Any equivalent finalization for the strategic chain is a
  separate effort with a different shape (no deletable terminal artifact, no discrete
  completion trigger) and is not addressed here.

## Decisions and Trade-offs

- **Execute-and-report over plan-only.** The subcommand applies the transitions and
  reports what it changed, rather than only deciding them and leaving the cascade script
  to apply each one. Alternative considered: a plan-of-record that the script applies
  node by node. Execute-and-report won because the goal is for the script to shrink to
  pure git orchestration; a plan-only design would leave per-node transition dispatch in
  the script, which is most of what this change is trying to remove. Trade-off: the
  subcommand mutates several documents in one invocation, whereas the single-document
  transition mutates one. That is acceptable -- the single-document transition keeps its
  single-document shape, and the new subcommand orchestrates it across the chain.
- **Preserve the cascade script's output contract.** The script keeps its existing
  `cascade_status` and `steps` output rather than adopting the subcommand's richer result
  as its own. Alternative considered: surface the subcommand's output directly. Preserve
  won because the implementation workflow that runs the cascade consumes `cascade_status`;
  changing it would ripple into that workflow for no user benefit. The subcommand's
  output is new surface with no compatibility burden, so the richer detail lives there.
- **Error contract follows the existing transition output.** The subcommand's structured
  errors and exit-code levels mirror the single-document transition's existing JSON
  envelope and exit codes rather than inventing a separate convention, so the binary
  presents one consistent contract. (How the subcommand reuses the engine internally --
  calling the transition logic in-process versus another path -- is left to the design.)

## Known Limitations

- The ROADMAP node and its external-state completion guard stay in the cascade script, so
  that portion of the cascade's logic is not consolidated by this work. This is a
  deliberate boundary: those steps depend on issue-tracker state and edit body prose, and
  are not deterministic local transitions. If a later effort brings external-state checks
  under the engine, the roadmap portion can be revisited then.
