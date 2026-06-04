---
schema: brief/v1
status: Accepted
problem: |
  shirabe plans and roadmaps render a feature's structure in two
  parallel surfaces -- the Implementation Issues table and the
  Dependency Graph mermaid block -- authored separately by hand,
  reconciled by no validator check. Drift across node set, edge set,
  and class-vs-Status passes CI unnoticed (a recent hand-fix PR
  corrected a real case by hand), and the longer the corpus
  accumulates the drift the more expensive a later one-shot
  reconciliation becomes.
outcome: |
  A doc author who edits a plan or roadmap sees the validator surface
  a specific notice the moment the diagram and the table fall out of
  agreement across any of the three dimensions. The notice level
  keeps CI green while the corpus reconciles; promotion to error is
  a one-line change once the docs are clean. The diagram becomes a
  trustworthy render of the table by construction.
upstream: docs/designs/DESIGN-roadmap-plan-standardization.md
---

# BRIEF: table-diagram-reconciliation

## Status

Accepted

## Problem Statement

shirabe plans and roadmaps describe a feature's structure twice, in
two surfaces that have to agree but are authored independently. The
Implementation Issues table carries the key column, a Dependencies
column, and a Status marker (an explicit value in the roadmap
profile, a strikethrough-on-done convention in the plan profile).
The Dependency Graph mermaid block carries node declarations, edges,
and class assignments that are supposed to mirror the same shape.
The two surfaces are authored by hand, edited at different times,
and reconciled by no automated check.

The validator already parses the table (the parsed `Table` the
prior table-parser increment landed) and already dispatches checks
like FC05 (schema) and FC06 (cross-reference) over it in the plan
and roadmap arms. It has no equivalent reader for the diagram, so
it cannot reconcile the two surfaces along any axis. A doc author
who renames an issue,
closes a dependency, marks an entity done, or rewrites a dependency
edge has to update both surfaces consistently across three
dimensions and verify the agreement by eye. There is no fallback if
they miss one.

The drift is not hypothetical. A recent hand-fix PR against
`docs/plans/PLAN-roadmap-plan-standardization.md` corrected a
class-vs-Status disagreement where closed issues stayed classed
`blocked` long after the rows went to a terminal state; no check
fired and the disagreement only surfaced on a manual reading. The
node-set and edge dimensions have the same exposure -- a table key
with no diagram node, or a
Dependencies entry with no matching edge, passes CI today. Every
plan and roadmap in the corpus is one rename away from the same
defect.

The gap has two costs. A reader who trusts the diagram as a faithful
render of the table can be led to the wrong picture of which work is
ready, which is blocked, and which dependencies bind. And the longer
the corpus accumulates drift before any reconciliation check exists,
the larger the one-shot retrofit becomes -- which is precisely why
the parent design staged the check behind a feasibility spike and a
notice-then-error rollout rather than landing it strict on day one.

## User Outcome

A doc author edits a plan or roadmap. They rename an issue in the
table without adding the new node to the diagram; CI surfaces a
notice naming the missing diagram node. They strike through an
entity row to mark it done while the diagram still classes the node
`blocked`; CI surfaces a class-vs-Status mismatch naming the node,
its declared class, the observed table state, and the expected
class. They add an entry to a Dependencies cell without the
corresponding `-->` edge in the diagram; CI surfaces a notice
naming the missing edge. Each defect names the specific cell or
line the author has to revisit, so the fix path is mechanical.

The author no longer has to mentally diff the two surfaces. The
validator does the reconciliation across all three dimensions --
node set, edge set, class-vs-Status -- in one check, and the
diagram becomes a trustworthy render of the table by construction.

Because the check ships as a notice rather than an error, CI stays
green while the existing committed corpus reconciles row by row.
The volume of notices drops as the corpus is cleaned up, and a
maintainer flips the one-line `IsNotice` membership to promote the
check to error in the same PR that finishes the cleanup. The
shipping path does not force a one-shot retrofit, and the corpus
gets a reliable contract once the cleanup is done.

A downstream sub-DESIGN author who lands on this brief cold picks
up the three reconciliation dimensions and the notice-then-error
shape without re-reading the spike. The framing the spike settled
-- per-dimension strictness, the tolerated non-issue-keyed node
exception, the class-vs-Status truth table -- is recorded here as
the boundary the sub-DESIGN refines, not as content the sub-DESIGN
has to re-derive.

## User Journeys

The feature is exercised from four entry points. Each names the
user, the trigger that brings them to the check, and the outcome
the validator surfaces.

### Journey 1: Doc author renames an issue in the table

A plan author updates the Implementation Issues table -- a rename,
a new row, or a removal -- without touching the Dependency Graph
mermaid block. They open the PR. The validator runs `checkFC07`
in the plan arm alongside FC05 and FC06; the node-set reconciliation
fires a notice naming the table key with no diagram node, or the
diagram node with no table key. The notice is non-blocking, so CI
exits 0, but the PR carries a visible signal the author can act on
before merge.

This journey validates that the node-set dimension fires on the
common edit shape (table changes, diagram untouched) and that the
notice level is honored.

### Journey 2: Doc author closes an entity but leaves the class stale

A plan author strikes through an entity row to mark it done (the
plan-profile terminal marker) but leaves the diagram class as
`blocked` or `ready`. This is the exact defect the recent hand-fix corrected.
The validator runs `checkFC07`, the class-vs-Status dimension
detects that the row is in a terminal state while the declared
class is non-`done`, and a notice fires naming the node, the
observed table state (`done`), the declared class (`blocked`), and
the expected class (`done`). The same dimension fires symmetrically
when a `done` class is declared on an open row, or a `ready` class
on a row with unmet dependencies.

This journey validates that the class-vs-Status dimension closes
the specific gap the milestone surfaced and would have prevented
the recent manual fix.

### Journey 3: Doc author edits a Dependencies cell

A plan author adds an entry to a Dependencies cell -- a new
blocker -- without adding the corresponding `-->` edge to the
diagram. The validator runs `checkFC07`, the edge-agreement
dimension detects the missing edge over the reconciling node
subset, and a notice fires naming the source and destination of
the missing edge. The same dimension fires symmetrically when an
edge exists in the diagram but the destination row's Dependencies
cell does not list the source.

This journey validates that the edge dimension fires on
Dependencies-side and diagram-side asymmetry alike, and that the
reconciling-node-subset tolerance (non-`I<n>` ids excluded from
both directions) keeps the corpus's existing `O<n>` and `K<n>`
shapes from producing false-positive notices.

### Journey 4: Maintainer reconciles the corpus and promotes the check

A maintainer surveys the existing committed plans and roadmaps,
sees the `checkFC07` notice volume drop to zero across the
corpus, and opens a cleanup PR that fixes the last remaining
disagreements. In the same PR they add the `FC07` code to the
notice-membership exclusion in `IsNotice` (a one-line change) so
the next run promotes the check to error-level. From that point
on, a fresh table-diagram disagreement reddens CI rather than
just emitting a notice. The notice-then-error rollout completes
without the day-one breakage a strict-from-day-one shipping path
would have caused.

This journey validates that the staged rollout the parent design's
Decision 3 chose has an executable end state and the one-line
promotion seam is real.

## Scope Boundary

This brief frames a single validator check, `checkFC07`, that
reconciles the parsed Implementation Issues table against the
extracted Dependency Graph mermaid block across three dimensions.
It is the final increment of the parent
`roadmap-plan-standardization` milestone, picking up after the
table parser and the mermaid-parser feasibility spike have landed.

The scope holds the following inside:

- The mermaid extractor (a single function in
  `internal/validate/mermaid.go`) that produces the four parallel
  views the spike enumerated: node set, edge set, class statements,
  and `classDef` set. Stdlib-only over the corpus subset; no full
  mermaid grammar; no new dependency. Scope shaped by the spike's
  extractor-scope recommendation.
- The `checkFC07` reconciliation check, dispatched in the plan and
  roadmap arms of `ValidateFile` alongside FC05 and FC06, that
  reconciles across all three dimensions in a single pass: node-set
  bijection (modulo the tolerated non-`I<n>` exception), edge
  agreement over the reconciling node subset, and class-vs-Status
  agreement over the Status-bearing class palette.
- Notice-level shipping via the existing `IsNotice` membership the
  schema check already uses, so an unreconciled committed diagram
  does not redden CI. The one-line promotion-to-error seam is in
  scope (the change site exists); the actual promotion is out (see
  below).
- Per-defect notice messages naming the specific cell, line, or
  node the author has to revisit -- mirroring the FC05/FC06 voice.
- Bounded-iteration behavior over malformed diagram input (no index
  panics, no unbounded loops) -- the SECURITY criterion the
  scheduling row names.
- A sub-DESIGN that references parent
  `DESIGN-roadmap-plan-standardization.md` Decision 3, refining its
  later-increment shape in light of the spike and the FC08 scope
  extension rather than superseding it.

The scope explicitly excludes:

- **The actual promotion of `checkFC07` to error-level.** Promotion
  happens after the committed-diagram corpus is reconciled (zero
  notice volume), in a separate cleanup PR that flips the one-line
  `IsNotice` membership. This brief ships the seam, not the flip.
- **A retrofit of the committed-diagram corpus.** The
  notice-then-error rollout exists precisely so corpus reconciliation
  happens incrementally after the check ships. Bulk-fixing the
  current corpus is out; an author who hits a notice fixes it in
  their own PR.
- **Reconciling roadmaps' `needs-*` annotations against diagram
  `needsDesign`/`needsPrd`/`needsSpike`/`needsDecision`/`tracksDesign`/`tracksPlan`
  classes.** The spike's truth table records these as
  pipeline-position metadata the issues table does not carry, so
  `checkFC07` records the class but does not reconcile it. A later
  feature can extend the reconciliation if pipeline-position
  tracking moves into the table.
- **Inline class syntax (`I488:::ready --> I489:::blocked`), edge
  labels, arrow variants other than `-->`, `subgraph`/`end`
  blocks, and `flowchart` headers.** The dependency-diagram
  reference either forbids or doesn't require these; the spike
  records the extractor's tolerance behavior (skip, ignore, or
  emit a header-shape notice) but the brief does not extend the
  extractor to handle them.
- **A general mermaid parser usable beyond this check.** The
  parent design rejected pulling in a full grammar; the extractor
  is line-oriented and shaped to the corpus subset. A future caller
  needing more grammar coverage replaces the extractor; this brief
  does not generalize it.
- **Cross-repo node id forms (`owner/repo#N`) as first-class
  diagram node ids.** The corpus uses local mnemonic ids (`K<n>`)
  for cross-repo references and the spike confirmed no
  `owner/repo#N` literal appears as a diagram node id. The
  reconciling-node-subset tolerance covers the `K<n>` shape;
  recognizing `owner/repo#N` is out for v1.

## References

- Feasibility spike (extractor scope and per-dimension strictness):
  `docs/spikes/SPIKE-mermaid-parser.md`.
- Parent design (the staged-reconciliation Decision 3 the sub-DESIGN
  refines): `docs/designs/DESIGN-roadmap-plan-standardization.md`.
- Parent plan (the row that schedules this increment):
  `docs/plans/PLAN-roadmap-plan-standardization.md`.
- Parent PRD (R8 staged-reconciliation, R9 spike requirement, R20
  notice-then-error contract):
  `docs/prds/PRD-roadmap-plan-standardization.md`.
- Canonical issues-table conventions (the Status column for the
  roadmap profile, strikethrough-on-done for the plan profile):
  `references/issues-table.md`.
- Canonical dependency-diagram conventions (the graph subset, the
  status-class palette, the forbidden forms):
  `references/dependency-diagram.md`.
