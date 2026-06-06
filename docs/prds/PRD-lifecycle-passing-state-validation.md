---
schema: prd/v1
status: Done
problem: |
  shirabe's existing validator runs as a diff-scoped pass on the files
  touched by the PR under review, plus the L01 and L02 stateless lifecycle
  checks that read each doc in isolation. Neither lens catches the case
  where a chain of BRIEF, PRD, DESIGN, and PLAN docs drifts out of step
  with itself — a single-pr chain ships and the BRIEF and PRD stay at
  Accepted, a multi-pr PLAN reaches Done but the deletion commit never
  lands, a BRIEF gets written but its PRD never does. Two recent corpus
  reconciliation PRs (FC09 and FC08) demonstrate the drift the team needs
  the validator to catch.
goals: |
  Deliver a `shirabe validate --lifecycle <root>` mode that walks the doc
  tree, identifies artifact chains via inverse `upstream:` traversal,
  computes each chain's posture, and verifies every chain member is at
  its passing state. Reconcile the FC08 and FC09 chain corpus in the same
  PR. Replace the parent PRD's R17 and R18 two-stateless-checks framing
  with the chain-aware passing-state model. Keep the `Lnn` check-code
  family.
upstream: docs/briefs/BRIEF-lifecycle-passing-state-validation.md
source_issue: 116
complexity: Complex
---

# PRD: lifecycle-passing-state-validation

## Status

Done

The PRD operationalizes the upstream BRIEF and the two pre-settled
decision records named in the References section. The DESIGN that
follows picks the architectural alternatives left open here.

## Problem Statement

shirabe contributors land doc-tree changes in two execution modes —
multi-pr chains where N child PRs deliver the work over time before a
final verify-then-delete PR retires the PLAN, and single-pr chains
where the whole feature ships in one PR. The validator has two passes
today: a diff-scoped pass that examines files the PR touches, and the
L01/L02 stateless lifecycle pass that flags any present non-Active
multi-pr doc or any present single-pr PLAN at merge. Neither pass
relates a doc's state to the chain it belongs to.

The result is a class of drift the validator misses entirely. A multi-
pr work-completing PR that transitions the PLAN to Done but forgets the
deletion commit fails L01 today, which is correct, but only because
L01 happens to coincide with the right answer for that one case. A
single-pr chain that ships with the BRIEF and PRD stuck at Accepted
passes every check today — both L01 and L02 — because no rule says the
BRIEF and PRD should have moved to Done. The two recent corpus
reconciliation PRs both shipped this drift, and the absence of a chain-
aware check is what let them land.

The team needs a check that knows the chain a doc belongs to, the
posture that chain is in for the current PR, and the state every doc
in the chain should be at given that posture. The check needs to fail
non-zero on any drift between actual state and that posture-derived
expected state. It needs to handle orphans cleanly — long-lived
terminal-status framing artifacts that survived after their PLAN was
deleted — and it needs to handle the in-flight ROADMAP-rooted PRD that
has not yet reached its DESIGN altitude. Both of those cases exist in
the corpus today; an orphan-strict rule that fails them mass-fails the
corpus.

## Goals

A contributor running `shirabe validate --lifecycle .` on any branch
gets a deterministic verdict about whether every artifact chain in the
tree is coherent for the PR's posture. The verdict is read from the
working tree alone — no git introspection, no GitHub round-trip, no
external state — and the failure message names the file, the current
state, and the expected passing state.

The same PR that ships the new check also reconciles the FC08 and FC09
corpus drift, so the check passes on its own delivery PR. The parent
PRD R17 and R18 carry the chain-aware passing-state model in their
text, so the model is the named contract the team enforces. The check
codes stay `Lnn`.

## User Stories

### As a contributor opening an in-flight multi-pr child PR

I want the `--lifecycle` check to pass when my PR closes one child
issue from a multi-pr milestone whose PLAN is at Active and whose
BRIEF/PRD/DESIGN are at their in-flight passing states, so that the
validator doesn't false-positive on the normal mid-chain shape.

### As a contributor opening the multi-pr work-completing PR

I want the check to pass once I've transitioned the PLAN Active to
Done, deleted the PLAN, transitioned the BRIEF and PRD to Done, and
the DESIGN is at Current — all in the same atomic PR — so that the
chain ships when every chain member is at the at-merge passing state.

### As a contributor who forgot the deletion commit

I want the check to fail with an explicit `Lnn` error naming the
present-at-Done PLAN and the expected DELETED state, so the forcing
function drives me to add the `git rm` rather than letting the chain
land with the PLAN still in the tree.

### As a contributor on a single-pr chain mid-PR

I want the check to pass when BRIEF and PRD are at Accepted, DESIGN is
at Current, and PLAN is at Draft, so the natural mid-PR working-tree
state of a single-pr chain is recognized as the passing single-pr-mid-
PR posture.

### As an author reading the orphan-doc rule

I want the check to pass on a long-lived orphan BRIEF at Done — the
post-completion record of a feature whose PLAN was deleted — and to
fail on an orphan BRIEF at Accepted — the framing-stalled drift case —
so the rule encodes the discipline rather than mass-failing healthy
corpus shapes.

### As a contributor working on a ROADMAP-rooted PRD

I want the check to pass on an orphan PRD at Accepted whose own
`upstream:` points at an Active ROADMAP, so the ROADMAP-rooted in-
flight case isn't falsely flagged as stalled framing.

## Requirements

### Functional Requirements

**R1: `--lifecycle <root>` CLI flag and exit semantics.** The
`shirabe validate` command accepts a `--lifecycle <root>` mode in
which the `<root>` argument is a path to the doc-tree root (typically
the repo root, but a sub-tree is acceptable for testing). The command
walks the doc tree under the root, runs the chain-aware passing-state
check, and exits zero on pass, non-zero on any chain-member-not-at-
passing-state condition. The mode runs alongside (not replacing) the
existing diff-scoped validator pass; the DESIGN picks whether the
mode runs as a separate CLI invocation or composes into a single
pass.

**R2: Chain-walker semantics.** From each PLAN file at
`docs/plans/PLAN-*.md` and each ROADMAP at `docs/roadmaps/ROADMAP-*.md`,
the walker follows the inverse `upstream:` edge to discover the
BRIEF, PRD, and DESIGN docs that form the chain. The walker handles
both scalar (`upstream: docs/path/file.md`) and list (`upstream: [...]`
or YAML-list form) shapes. The walker also discovers DESIGNs at
`docs/designs/current/DESIGN-*.md` and `docs/designs/DESIGN-*.md`. The
walker is defensive against malformed frontmatter, missing parent
files, and `upstream:` cycles — the DESIGN picks whether a cycle is a
hard error or a warn-and-bail-walk.

**R3: Posture inference.** Each chain's posture is inferred from the
PLAN's `execution_mode` and `status` per the multi-pr posture-
detection decision record. The five postures the check distinguishes:

| Posture | Detection signal |
|---------|------------------|
| Multi-pr in-flight | execution_mode multi-pr, PLAN present at Active |
| Multi-pr work-completing-but-not-yet-deleted | execution_mode multi-pr, PLAN present at Done |
| Multi-pr at-merge | execution_mode multi-pr, PLAN absent (chain rooted at DESIGN's known PLAN slug not in the tree) |
| Single-pr mid-PR | execution_mode single-pr, PLAN present at Draft |
| Single-pr at-merge | execution_mode single-pr, PLAN absent |

The multi-pr at-merge posture is reachable by the walker only when a
ROADMAP rooted at the same parent points at a PRD pointing at a
DESIGN whose original PLAN slug can be inferred from the chain. For
the v1 check, multi-pr at-merge is reached via direct ROADMAP roots
in the tree; PLAN-absence per se is the at-merge signal.

**R4: Passing-state per artifact type per posture.** The check
computes each chain member's passing state from the chain's posture
per the table below:

| Posture | BRIEF | PRD | DESIGN | PLAN |
|---------|-------|-----|--------|------|
| Multi-pr in-flight | Accepted | Accepted | Current | Active |
| Multi-pr work-completing | Done | Done | Current | DELETED (fails until git rm) |
| Multi-pr at-merge | Done | Done | Current | (absent) |
| Single-pr mid-PR | Accepted | Accepted | Current | Draft |
| Single-pr at-merge | Done | Done | Current | (absent) |

The DESIGN target state is `Current` — a DESIGN is at terminal state
when it lives in `docs/designs/current/`. A DESIGN at `Planned` in
the parent `docs/designs/` directory is in-flight.

**R5: Orphan-doc rule.** Per the orphan-doc-passing-state-rule
decision record. An orphan BRIEF, PRD, or DESIGN — a doc with no
downstream `upstream:` reference from any other doc — has passing
state defined by its target state:

- Orphan at target state (BRIEF Done, PRD Done, DESIGN Current):
  passes.
- Orphan at non-terminal status whose own `upstream:` points at an
  Active ROADMAP: passes. The ROADMAP-rooted in-flight case.
- Every other orphan: fails. The error names the file, its current
  state, and the expected passing state (the target state for the
  artifact type).

**R6: `Lnn` check-code family and error-message format.** Lifecycle
check codes use the `Lnn` family (L01, L02, ...) — distinct from the
content-format `FCnn` family. The DESIGN assigns concrete numbers to
each failure mode. Every error message names:

- The file path (repo-relative).
- The current state (the frontmatter status, or `(absent)` when the
  file is missing from the expected location, or `(orphan)` when the
  orphan rule fires).
- The expected passing state for this chain's posture.

A representative error: `L01 docs/plans/PLAN-foo.md is present at
status 'Done'; expected DELETED for multi-pr work-completing posture
(forcing function for deletion)`.

**R7: Corpus reconciliation in the delivery PR.** The PR landing this
PRD's implementation also lands four frontmatter transitions to
reconcile the FC08 and FC09 chain drift documented in the BRIEF:

- `docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md`: Accepted
  to Done.
- `docs/prds/PRD-doc-vs-github-state-reconciliation.md`: Accepted to
  Done.
- `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md`: Accepted
  to Done.
- `docs/prds/PRD-legend-vs-classdef-reconciliation.md`: Accepted to
  Done.

FC07 — `docs/briefs/BRIEF-table-diagram-reconciliation.md` and its
PRD — already sit at Done; no transition is required for that chain.
The four FC08 and FC09 transitions use the existing `shirabe
transition` subcommand and ship as part of the same PR as the chain-
walker code, so the new check passes on its own delivery PR.

**R8: Parent PRD amendment in the delivery PR.** The PR amends
`docs/prds/PRD-roadmap-plan-standardization.md` R17 and R18 to codify
the chain-aware passing-state model. The amendment replaces the two-
stateless-checks framing (Check A and Check B as separate stateless
rules) with the unified chain-aware passing-state rule of which the
old checks are degenerate cases. The `Lnn` check-code family name
stays. The amendment is part of this delivery PR, not a separate one,
so the check passes on its delivery PR against the amended parent
PRD.

**R9: Walk bounded to the root.** The walker SHALL NOT follow
symlinks that escape the root path. Path-traversal style inputs (a
`<root>` whose canonical path escapes the repo working tree, an
`upstream:` value that walks `..` past the root) MUST be rejected.
The walker MUST NOT panic on any malformed input: empty `upstream:`
fields, list shapes mixed with scalar shapes, cycles in the upstream
graph, missing parent files, and frontmatter that fails to parse all
produce structured errors, not panics. The DESIGN picks the exact
cycle-handling stance (hard error with diagnostic vs warn-and-bail-
walk).

**R10: Table-driven tests.** The implementation ships table-driven
tests over synthetic chain fixtures covering at minimum these
scenarios from the issue's Acceptance Criteria:

- Multi-pr in-flight chain (PLAN Active; BRIEF/PRD Accepted; DESIGN
  Current): passes.
- Multi-pr work-completing PR with all transitions consistent (PLAN
  absent or about to be deleted; BRIEF/PRD Done; DESIGN Current):
  passes.
- Single-pr chain mid-PR (BRIEF/PRD Accepted; DESIGN Current; PLAN
  Draft): passes.
- Single-pr chain at merge-time (PLAN deleted in this PR; BRIEF/PRD
  Done; DESIGN Current): passes.
- Present Draft multi-pr PLAN: fails.
- Present Done multi-pr PLAN: fails (deletion forcing function).
- Single-pr PLAN present at merge: fails.
- BRIEF stuck at Accepted while its multi-pr PLAN is Done: fails.
- Orphan terminal-status (BRIEF Done with no downstream): passes.
- Orphan non-terminal-status (BRIEF Accepted with no downstream and
  no Active-ROADMAP upstream): fails.
- ROADMAP-rooted in-flight PRD orphan (PRD Accepted, no downstream
  DESIGN, upstream points at Active ROADMAP): passes.

### Non-Functional Requirements

**R11: Doc-tree-only execution.** The check executes against the
working tree alone. It MUST NOT shell out to `git`, MUST NOT make a
network request, and MUST NOT depend on the existence of a `.git/`
directory or a configured remote. The validator behavior is identical
in local pre-commit runs, CI runs, and runs against a copy of the
doc tree.

**R12: Reuse existing validation infrastructure.** R1-R10 extend the
existing `crates/shirabe-validate/` Rust crate and run through the
existing `shirabe validate` CLI. The DESIGN picks the exact module
placement.

**R13: Incremental delivery.** The chain-walker, the posture
inference, the passing-state computation, the orphan rule, the Lnn
error format, the corpus reconciliation, and the parent PRD amendment
all ship in one delivery PR per the upstream issue's "Must deliver"
stance.
The PR is single-pr execution; the PLAN that drives it is ephemeral
and is deleted before the PR can merge.

**R14: Public-visibility cleanliness.** All references, surfaced
rules, and validation messages are public-repo clean: no private
repos, paths, filenames, issue numbers in committed prose, or pre-
announcement features. Commit messages may carry the standard
`Closes #N` reference; the PR body may reference issue numbers in
its closing-references section. Document body prose carries no
numeric issue references.

## Acceptance Criteria

- [ ] `shirabe validate --lifecycle <root>` walks the doc tree,
  identifies artifact chains via inverse `upstream:` traversal, and
  computes the passing state per chain posture (single-pr vs multi-
  pr; in-flight vs work-completing for multi-pr).
- [ ] The mode fails non-zero if any doc in any chain isn't at its
  passing state, naming the offending file, its current state, and
  its expected passing state.
- [ ] L01 (a multi-pr PLAN at non-Active in the tree) and L02 (a
  single-pr PLAN present in the tree at merge time) are subsumed as
  degenerate cases of "doc isn't at passing state for this chain's
  posture."
- [ ] BRIEF and PRD passing-state validation: walks the chain from
  each PLAN/ROADMAP and verifies BRIEF and PRD are at the correct
  state given the chain's posture.
- [ ] The orphan-doc rule fires per the orphan-doc-passing-state-rule
  decision record: terminal-status orphans pass; non-terminal-status
  orphans pass only when their own `upstream:` points at an Active
  ROADMAP; every other orphan fails.
- [ ] Corpus reconciliation lands in this PR: FC09 BRIEF and PRD
  transition Accepted to Done; FC08 BRIEF and PRD transition Accepted
  to Done. FC07 verified already at Done.
- [ ] Parent PRD `docs/prds/PRD-roadmap-plan-standardization.md` R17
  and R18 amended in this PR to codify the chain-aware passing-state
  model. The two-stateless-checks framing is replaced; the `Lnn`
  check-code family name stays.
- [ ] Check codes use the `Lnn` family.
- [ ] The walker is bounded to the given root with no symlink escape;
  malformed frontmatter (empty fields, mixed list-vs-scalar, cycles,
  missing parent files) produces structured errors, not panics.
- [ ] Table-driven tests cover the scenarios named in R10.
- [ ] `cargo build` and `cargo test` pass at HEAD.

## Out of Scope

- CI wiring that runs `--lifecycle` on every PR. The downstream CI
  integration is owned by a separate issue and reuses the
  `--lifecycle <root>` interface defined here unchanged.
- ROADMAP-lifecycle checks beyond what the orphan-rule's Active-
  ROADMAP exception requires. A stale-ROADMAP forcing function is
  separate downstream work.
- Extending `shirabe transition` to cover the Plan format. The v1
  author gesture for the work-completing PR is a manual frontmatter
  edit of the PLAN's status field. A future transition-tool
  extension is separately sequenced.
- Cross-repo chain validation. The walker walks only the doc tree
  under the given root; `upstream:` references that point at a
  different repo are out of scope for this iteration.
- Auto-fixing drifted docs. The check reports drift; the author
  drives the chain forward. Auto-fix is a separate value
  proposition.

## Decisions and Trade-offs

The two genuinely contested decisions for this work — the orphan-doc
rule and the multi-pr posture-detection mechanism — have been settled
in advance of this PRD via `/shirabe:decision`. The PRD operationalizes
both decisions but does not re-litigate them. Each Decision Record
carries its own Context, Options Considered, and Consequences
sections; this PRD names the records and consumes their outcomes.

A small number of architectural alternatives stay open for the DESIGN
to settle:

- Chain-walker module placement — new `crates/shirabe-validate/src/lifecycle.rs`
  module vs extending the existing `checks.rs` or `validate.rs`.
- Target-state map shape — per-format-spec field added to
  `formats.rs` vs centralized lookup in the new module.
- Cycle handling in upstream traversal — hard error with a structured
  diagnostic vs warn-and-bail-walk that emits a notice and continues.
- How `--lifecycle` composes with the existing diff-scoped validator
  — a separate CLI mode flag invoked independently vs an always-on
  additional pass.
- Concrete `Lnn` check-code numbering — L01, L02, L03 assigned to
  specific failure modes (posture-vs-state mismatch, orphan-non-
  terminal, present-Done-multi-pr, present-single-pr-at-merge,
  cycle detected, etc.).

The DESIGN picks all five. None of them changes the requirements
above.

## References

- `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` — the
  upstream BRIEF this PRD operationalizes.
- `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`
  — the orphan-doc passing-state rule R5 encodes.
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`
  — the multi-pr posture-detection mechanism R3 encodes.
- `docs/prds/PRD-roadmap-plan-standardization.md` — the parent PRD
  this work amends (R17 and R18, per R8).
- `docs/designs/DESIGN-roadmap-plan-standardization.md` — the parent
  DESIGN whose Decision 5 the chain-aware model reshapes.
