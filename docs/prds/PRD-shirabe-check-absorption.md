---
schema: prd/v1
status: Accepted
problem: |
  Deterministic document checks are implemented in more than one place --
  the shirabe validate engine, external CI shell scripts copied across
  repositories, and rules restated in skill prose. Three families exist on
  both sides, so the copies disagree at the edges and a rule change has to be
  made several times.
goals: |
  Make the validate engine the single authority for these checks: absorb the
  deterministic external checks into it as first-class checks under a
  determinism rubric, reconcile the families that exist on both sides to one
  behavior, point skill prose at the engine's check, and retire each external
  copy as it is absorbed -- each with a parity test against the source it
  replaces.
upstream: docs/briefs/BRIEF-shirabe-check-absorption.md
---

# PRD: Deterministic check absorption

## Status

Accepted

## Problem Statement

`shirabe validate` already implements a large set of the project's
deterministic document checks as first-class Rust checks -- the FC-family
(frontmatter fields, status match, required sections, issues-table shape and
consistency, and more) and the R-family (visibility-gated content). It is
intended to be the one authority for these rules.

It is not yet the only place the rules live. The same kind of deterministic
checks are also implemented as external CI shell scripts, copied across more
than one repository, and as rules restated in prose inside the workflow
skills. The external scripts cover document location, frontmatter,
section structure, the issues table, diagram consistency, and
strikethrough state; the skill prose restates frontmatter-field lists,
section-ordering rules, a path-hygiene scan, and Phase-0 validation steps.

In three families -- frontmatter, required sections, and the issues table --
the external scripts and the engine implement the same rule twice. Because
the rule lives in several places, the places drift: a document can pass the
shell script and fail the engine (or the reverse) when the two
implementations disagree on an edge; a maintainer who corrects a rule has to
find and fix every copy; and skill prose that restates a rule can fall out
of step with what the validator actually enforces. The engine cannot become
the single authority by sitting alongside the duplicates -- the external
deterministic checks have to be absorbed into it, and the overlapping
families have to be reconciled to one behavior. Some external checks,
though, should not be absorbed: a large diagram validator is too expensive
to run inline, and any judgment-dependent check does not belong in an
offline validator at all. The feature needs a principled boundary, not a
wholesale port.

## Goals

- The validate engine is the single definition site for the deterministic
  checks in scope: a check is defined once and every consumer runs that one
  definition.
- A determinism rubric decides what is absorbed, so the engine takes on the
  checks that belong in an offline authority and leaves out the ones that do
  not -- by a rule anyone can apply, not by reflex.
- The families that exist on both sides are reconciled to one authoritative
  behavior, so a document gets one verdict rather than two that can
  disagree.
- Each absorbed check is provably faithful to the source it replaces (or its
  deliberate divergence is named), and the external copy is retired as the
  absorption lands, so duplication falls rather than grows.
- Skill prose that restated a deterministic rule references the engine's
  check instead, so the written rule and the executed rule cannot drift.

## User Stories

- As a **maintainer**, I correct a deterministic rule once in the engine and
  every consumer (CI on every repo, the skills, local hooks) picks up the
  corrected behavior, with no second copy to find and fix.

- As a **contributor**, I get one consistent verdict on my document instead
  of two tools that can disagree on an edge case, because the overlapping
  check family was reconciled to a single authoritative behavior.

- As a **skill author**, I enforce a deterministic rule by invoking the
  engine's check and reading its verdict, instead of restating the rule in
  prose that can drift from what the validator enforces.

- As a **maintainer deciding scope**, I apply the determinism rubric to a
  candidate external check and get a clear absorb / defer / keep-out answer,
  so the engine does not take on checks that are too expensive to run inline
  or that need human judgment.

## Requirements

### Functional

- **R1 -- Absorb the in-scope external checks.** The engine SHALL implement,
  as first-class checks, the deterministic checks that currently live only
  in external CI shell scripts and pass the determinism rubric (R2). Each
  absorbed check SHALL be addressable by a stable check code consistent with
  the engine's existing code families, so consumers reference it the same
  way they reference the existing checks.

- **R2 -- Determinism rubric governs absorption.** A documented rubric SHALL
  classify each candidate check and decide its disposition: a check that is
  a pure function of the document on disk, or deterministic over external
  state that an orchestrator injects (the way the existing git-backed and
  GitHub-state checks already work), is in scope to absorb; a check that is
  deterministic but too expensive to run inline, or that requires human or
  model judgment, is out of scope. The disposition of every candidate check
  SHALL be recorded against the rubric.

- **R3 -- Reconcile the overlapping families to one behavior.** For each
  check family implemented on both sides (frontmatter, required sections,
  the issues table), the feature SHALL settle one authoritative behavior,
  resolving each edge-case disagreement, rather than leaving two
  implementations that can disagree. The reconciled behavior SHALL be the
  single definition; the external copy SHALL NOT remain as a second
  implementation.

- **R4 -- Parity test per absorbed check.** Each absorbed check SHALL carry
  a test that asserts its verdict matches the source it replaces across a
  representative corpus of inputs. Where the reconciled behavior
  deliberately differs from a source, the test SHALL assert the chosen
  behavior and the divergence SHALL be named explicitly, not left implicit.

- **R5 -- Retire each external copy as it is absorbed.** When the engine
  absorbs a check, that check SHALL be removed from its external source as
  the absorption lands, so the work reduces the number of implementations
  rather than adding a third.

- **R6 -- Mechanize prose-restated rules.** Deterministic rules currently
  restated in skill prose and passing the rubric SHALL be implemented as
  engine checks, and the prose SHALL be updated to reference the engine's
  check (by its code) instead of restating the rule. A rule that the rubric
  places out of scope MAY remain as prose, but the rationale SHALL be
  recorded.

- **R7 -- Record cost-deferred checks as deferrals.** A deterministic check
  left out on cost grounds (a large diagram validator is the example) SHALL
  be explicitly recorded as a cost deferral, distinct from a
  determinism-based exclusion, and SHALL remain on the external mechanism
  until a later effort absorbs it.

- **R8 -- Absorbed checks are individually invocable.** Each absorbed check
  SHALL be selectable individually through the engine's existing per-check
  selection surface, so a consumer can run one absorbed check rather than
  the whole pass.

### Non-functional

- **R9 -- No regression in existing checks.** Absorption SHALL NOT change the
  behavior of the engine's existing checks except where a reconciliation
  (R3) deliberately settles an overlap. The existing output and exit-code
  contracts are preserved (the annotation parity bar continues to hold).

- **R10 -- Architectural design required.** The per-check absorb / defer /
  keep-out decisions, the reconciliation method for each overlapping family,
  the prose-mechanization list, and the retirement order are architectural
  choices that warrant a downstream DESIGN before implementation.

## Acceptance Criteria

- [ ] Every candidate external check has a recorded disposition (absorb /
      cost-defer / keep-out) justified against the determinism rubric.
- [ ] Each check absorbed under "absorb" is implemented in the engine,
      addressable by a stable check code in the existing code-family style,
      and runnable individually via per-check selection.
- [ ] For each of the three overlapping families (frontmatter, required
      sections, issues table), one authoritative behavior is settled and
      only one implementation remains; each previously-divergent edge case
      has a defined verdict.
- [ ] Each absorbed check has a test asserting verdict parity with the source
      it replaces over a representative corpus; any deliberate divergence is
      named in the test and the design record.
- [ ] Each absorbed check is removed from its external source as part of the
      change that absorbs it (no check is implemented in three places at any
      committed point).
- [ ] Each in-scope prose-restated rule that this feature mechanizes is
      implemented as an engine check and the corresponding prose references
      it by code rather than restating the rule (at least one such rule is
      mechanized); any in-scope-looking prose rule deliberately left as prose
      carries a recorded rationale.
- [ ] The downstream DESIGN exists and records, against the determinism
      rubric, each candidate's disposition, the reconciliation method for
      every overlapping family, the prose-mechanization list, and the
      external-source retirement order.
- [ ] The cost-deferred diagram validator is recorded as a cost deferral
      (not a determinism exclusion) and is not absorbed by this feature.
- [ ] The engine's existing checks behave identically before and after,
      except at the specific edges a reconciliation deliberately settles; the
      annotation parity corpus stays green.

## Out of Scope

- **The cost-deferred checks.** The large diagram validator and any other
  check deferred on cost grounds are not absorbed here. They remain on the
  external mechanism until a later effort takes them on. This is a cost
  decision, not a determinism one.
- **Judgment-only checks.** Any check that needs a human or model call is
  out by definition -- it does not belong in an offline validator -- and is
  neither absorbed nor reconciled here.
- **The output and selection surface.** The output modes, per-check
  selection, and exit-code contract already exist. This feature populates
  that surface with absorbed checks; it does not reshape the surface.
- **Distribution.** Making the engine reachable on every consumer's path is
  separate downstream work and is not part of absorption.
- **The per-check decisions themselves.** Which checks absorb vs defer vs
  keep out, the reconciliation method for each overlap, the prose-
  mechanization list, and the retirement order are settled by the downstream
  DESIGN, not fixed by this PRD.

## Decisions and Trade-offs

- **Reconcile, do not port twice.** For the three families that exist on
  both sides, the choice is to settle one behavior rather than port the
  external version alongside the engine version. The alternative -- port
  each external check verbatim -- was rejected because it would preserve the
  very duplication the feature exists to remove and would leave the edge-case
  disagreements unsettled. The cost is that reconciliation requires deciding
  each disagreement deliberately, which is design work; that work is the
  point, not overhead.

- **A rubric instead of a wholesale port.** Absorption is bounded by an
  explicit determinism rubric rather than "port everything external." The
  alternative -- absorb every external check -- was rejected because some
  checks are too expensive to run inline and others need judgment that an
  offline validator cannot supply. The rubric makes the boundary a stated
  rule rather than a series of ad-hoc calls.

- **Parity tests as the absorption contract.** Each absorbed check must prove
  it matches the source it replaces (or name its divergence). The
  alternative -- absorb and trust the reimplementation -- was rejected
  because a silent behavior change during absorption would surface as a
  contributor's document passing or failing differently with no recorded
  reason.

## Known Limitations

- Absorption proceeds check-by-check, so during the feature's lifetime the
  external mechanism shrinks gradually rather than disappearing at once; the
  duplication is fully gone only when the last in-scope check lands.
- The cost-deferred checks keep the external mechanism alive until a later
  effort absorbs them, so this feature reduces but does not by itself
  eliminate the external check surface.
