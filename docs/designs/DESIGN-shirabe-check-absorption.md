---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-shirabe-check-absorption.md
problem: |
  Deterministic document checks are implemented in more than one place -- the
  shirabe validate engine, external CI shell scripts, and rules restated in
  skill prose -- and the copies drift. Three families exist on both sides.
  The engine must become the single authority by absorbing the in-scope
  external checks and reconciling the overlaps to one behavior.
decision: |
  Add absorbed checks as first-class checks in the engine's existing check
  registry under stable codes; govern absorption with a written determinism
  rubric and a per-check disposition record; reconcile each overlapping
  family to one behavior with a bash-vs-Rust parity harness over a captured
  corpus; retire each external copy as its absorption lands; and point
  mechanized skill prose at the engine check by code.
rationale: |
  Reusing the existing checks.rs dispatch and the per-check registry keeps
  absorption additive; a captured-corpus parity harness makes each
  reconciliation auditable rather than a silent reimplementation; the rubric
  turns the absorb/defer/keep-out boundary into a stated rule; and retiring
  each external copy as it lands keeps duplication falling, never tripling.
---

# DESIGN: Deterministic check absorption

## Status

Proposed

## Context and Problem Statement

The validate engine (`crates/shirabe-validate`) already runs the project's
deterministic document checks as first-class Rust checks: `validate_file`
dispatches the FC-family (frontmatter fields, status match, required
sections, issues-table shape and consistency, and more) and the R-family
(visibility-gated content), each emitting a `ValidationError` carrying a
stable code. SR6 added a per-check selection registry (`is_known_check_code`)
so a consumer can run one named check.

The same kind of deterministic checks are also implemented outside the
engine, as external CI shell scripts (copied across repositories by a sync
mechanism) and as rules restated in the workflow skills' prose. In three
families -- frontmatter, required sections, and the issues table -- the
external scripts and the engine implement the same rule twice; in other
families the external scripts implement a check the engine does not have yet
(document location vs status, strikethrough state, and a large diagram
validator). The duplication drifts: the two implementations of an
overlapping family can disagree on an edge, and a skill's prose paraphrase of
a rule can fall out of step with what the engine enforces.

The technical problem is to make the engine the single definition site for
the deterministic checks in scope -- adding the absorbed checks into the
existing dispatch and registry, reconciling each overlapping family to one
authoritative behavior, proving each absorbed check faithful to the source it
replaces, and retiring the external copy as the absorption lands -- while
leaving out the checks a determinism rubric places out of scope (a
cost-deferred diagram validator; any judgment-dependent check). The hard part
is not translation but reconciliation: settling, per disagreeing edge, which
behavior is authoritative.

## Decision Drivers

- **Reconcile, do not port twice.** For the three overlapping families, the
  end state is one implementation, not two; each previously-divergent edge
  needs a defined verdict (PRD R3).
- **Provable parity.** Each absorbed check must be shown faithful to the
  source it replaces over a representative corpus, or its deliberate
  divergence named (PRD R4) -- a silent behavior change during absorption is
  the failure mode to prevent.
- **A stated rubric, not reflex.** The absorb / cost-defer / keep-out
  boundary is a written rule applied per check, with the disposition recorded
  (PRD R2, R7).
- **Additive over rewrite.** Absorbed checks join the existing `checks.rs`
  dispatch and the per-check registry; the existing checks' behavior and the
  annotation/exit contracts are preserved except where a reconciliation
  deliberately settles an overlap (PRD R9).
- **Individually invocable.** Each absorbed check is selectable through the
  per-check surface SR6 shipped, under a stable code in the existing
  code-family style (PRD R1, R8).
- **Duplication falls, never triples.** Each external copy is retired as the
  engine absorbs it; no check is implemented in three places at any committed
  point (PRD R5).
- **Prose references the check.** Mechanized skill-prose rules point at the
  engine check by code instead of restating the rule (PRD R6).
- **Public visibility.** The artifact names only shirabe's own checks and
  describes the external sources generically; no private paths or names.
