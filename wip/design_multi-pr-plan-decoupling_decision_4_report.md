# Decision Report: Split-Rule Single-Sourcing

<!-- decision:start id="split-rule-single-source" status="confirmed" -->

## Context

`references/workflow-principles.md` P1 states the split rule as two escape
conditions ("a hard constraint forces multiple PRs" or "each PR is
independently useful") and `skills/plan/SKILL.md`'s Execution Mode Decision
restates the same two conditions on the always-loaded skill surface (per
Decision 6 of `DESIGN-roadmap-plan-standardization.md`). `references/
coordination-strategy.md`'s Coarsest-Legal-Grouping Rule states a *different*
four-trigger list for the coordinated altitude, one of which — "a single PR
would exceed the configured reviewability ceiling" — has no counterpart in
P1. The PRD driving this design (`docs/prds/PRD-multi-pr-plan-decoupling.md`)
adds a third, new branch: a repository-stated delivery preference
(`atomic`/`consolidated`, R1–R6), and requires (R5) that the governing
principle be amended so a reviewability-motivated split is expressible
without being mischaracterized as incremental value, and so P1 and
coordination-strategy stop disagreeing. R13/R14 require a PLAN frontmatter
field naming which of the rule's branches produced a non-default shape, and
R14 requires the rule to have exactly three branches so the third is "part
of the rule rather than standing beside it": a hard constraint, an
incremental-value judgment, or the repository's stated delivery preference.

## Assumptions

- `references/split-triggers.md` (new) is read by both P1 and the
  Coarsest-Legal-Grouping Rule at authoring/planning time, the same way
  `issues-table.md` and `dependency-diagram.md` are read by the plan and
  roadmap skills — a reference file, not a principle file, is where a full
  enumerated shape belongs.
- The PLAN's `split_rationale` (R13) field takes free text (R20: "not a
  closed enumeration"), but that free text names one of the three branches
  by the short names this decision fixes, so the field is auditable without
  a schema migration if a fourth branch is ever needed.
- Coordination's "independently mergeable" and "independently rollback-able"
  triggers were never independently load-bearing at the coordinated
  altitude either — they were gesturing at a repo boundary or landing-order
  constraint, i.e. **Hard Constraint** under a different name — and can be
  retired as separate bullets without losing any real case coordination-
  strategy.md currently covers.

## Chosen

**Alternative A** — extract a shared `references/split-triggers.md` that
both P1 and the Coarsest-Legal-Grouping Rule cite, parameterized by altitude
the way `issues-table.md` is parameterized by profile.

**The three branch names** (short, unambiguous, exactly what the PLAN's
`split_rationale` field cites):

1. **Hard Constraint** — a named, non-optional forcing condition (cross-repo
   landing order, a workflow that must reach main before it can be invoked,
   a merge gate between steps, a merge-order DAG contraction requirement).
2. **Incremental Value** — each resulting unit is independently useful to a
   reader landed alone, per the existing value-confirmation guard (step
   3.5a) — unchanged, still runs regardless of which branch produced the
   default.
3. **Stated Preference** — the repository has said, on the durable
   CLAUDE.md convention channel, that it wants this shape: the plan-altitude
   `atomic` delivery-shape header (PRD R1–R2), or the coordinated-altitude
   `## Reviewability Ceiling:` setting. Reviewability is *always* expressed
   through this branch at both altitudes — this is the sentence that
   resolves R5's disagreement.

**Shared core (`split-triggers.md`):** the three branches above, each with
a one-paragraph definition and the plan-vs-coordinated framing of what
"counts" as an instance (mirroring `issues-table.md`'s "Shared Core" +
"Shared Rendering" sections).

**Plan profile:** all three branches apply as-is; this is what P1 and
`skills/plan/SKILL.md`'s Execution Mode Decision cite. `SKILL.md` keeps its
short always-loaded *summary* naming the three branches (Decision 6's
surfacing rationale still holds — see Consequences), but the definitions and
worked examples live only in `split-triggers.md`.

**Coordinated profile:** the three shared branches, plus one
profile-specific fourth branch that does not exist at plan altitude —
**Merge-Order Necessity**: a split is required to break a contraction cycle
in the merge-order DAG. This is the only coordination trigger that survives
as a *distinct* branch; "independently mergeable" and "independently
rollback-able" are retired as free-standing triggers and folded into Hard
Constraint's coordinated-altitude examples (a repo boundary or landing-order
requirement is what actually makes a slice independently mergeable/
rollback-able — the old wording named the symptom, not the cause). The
"configured reviewability ceiling" trigger is retired as a fourth trigger
and folded into Stated Preference, which is now the one place reviewability
is named at any altitude.

## Rationale

**Why A over B (leave separate, add cross-references).** P4 in
`workflow-principles.md` is explicit: "Each shared shape ... has a single
source both workflows consume. Per-skill restatement is the drift source the
standardization removes." B leaves the shape itself — the enumerated trigger
list — duplicated in two files; a cross-reference paragraph acknowledging
the other rule's existence doesn't stop either file's trigger list from
drifting out of sync with the other, which is the exact defect this decision
exists to close (R5's "no longer disagree"). B is rejected on P4's own text.

**Why A over C (rewrite P1 to carry all three branches inline; coordination
cites P1).** This is the shape P4 forbids from the other direction: P4's own
precedent for a shared enumerated shape is a dedicated `references/*.md`
file (`issues-table.md`, `dependency-diagram.md`), not a principle file.
`workflow-principles.md`'s own framing states the principles file is
"intentionally small enough to hold in mind" and used "to reason at the
edges" — it is not the document that carries worked-out trigger definitions
and altitude parameterization; that's exactly what `references/*.md` files
are for elsewhere in this corpus. Growing P1 to carry three enumerated
branches with per-branch definitions also has nowhere principled to put the
coordinated-only fourth branch (Merge-Order Necessity) without either (a)
polluting a principle file with coordinated-mode-specific graph vocabulary,
or (b) leaving coordination-strategy.md to restate a fourth trigger next to
a citation of P1's three — which is restatement, the thing being removed.

**Why A over D (coordination-strategy cites P1's three branches plus its own
DAG-specific fourth).** D is a half-step toward A: it correctly keeps the
DAG trigger local to coordination-strategy.md (this decision agrees — see
Merge-Order Necessity above), but it still requires P1 to be the carrier of
the three-branch shape, which is C's problem restated. D also has no answer
for *why* P1, a principles file, becomes the reference every other altitude
cites for a detailed trigger taxonomy, when the corpus's own established
pattern (P4, `issues-table.md`) already says shared shapes get their own
reference file. A gets D's correct DAG-locality without D's flaw: P1 cites
`split-triggers.md` exactly the way it already implicitly should, and
coordination-strategy.md cites the same file for its three shared branches
before adding its one local one.

**Why the four coordination triggers don't transfer verbatim.**
"Independently mergeable" and "independently rollback-able," read literally,
fire on almost any well-decomposed plan at single-repo altitude — atomic
issue decomposition already produces units that are, in isolation,
mergeable and rollback-able. Importing them as free-standing plan-altitude
triggers would make Stated Preference and Incremental Value redundant (an
author could always claim the default two-branch condition and route around
P1's "default to single-pr"), which breaks P1's stated default outright.
"Breaks a contraction cycle in the merge-order DAG" refers to a graph
(`plan-to-tasks.sh`'s `(repo, pr_group)`-level DAG) that is a coordinated-
mode-only artifact; there is no merge-order DAG at plan altitude for a
trigger to reference. Both facts are why the shared core is three branches,
not four, and why the fourth stays local to the coordinated profile.

## Alternatives Considered

- **B — leave separate, add cross-reference paragraphs.** Rejected: doesn't
  single-source the shape (P4's own text), so the two rules can still drift;
  a cross-reference is an acknowledgment, not a fix.
- **C — rewrite P1 to carry all three branches inline, coordination cites
  P1.** Rejected: makes a principles file the carrier of a detailed,
  altitude-parameterized enumerated shape, contrary to the corpus's
  established pattern of dedicated `references/*.md` files for that role,
  and has no clean home for the coordinated-only fourth branch.
- **D — coordination-strategy cites P1's three branches plus its own
  DAG-specific fourth.** Rejected for the same reason as C (P1 still has to
  carry the three-branch shape); A achieves D's one correct instinct
  (keep the DAG trigger local) without inheriting C's flaw.

## Consequences

- New file `references/split-triggers.md`: shared core (three branches,
  each defined once) + plan profile (all three, cited by P1 and
  `skills/plan/SKILL.md`) + coordinated profile (the three plus Merge-Order
  Necessity, cited by `references/coordination-strategy.md`'s
  Coarsest-Legal-Grouping Rule, which drops its old four-bullet list).
- `references/workflow-principles.md` P1's "Rules derived from this" bullet
  is rewritten to name the three branches and cite `split-triggers.md`
  for the definitions, instead of spelling out "a hard constraint ... or
  each PR is independently useful" inline.
- `skills/plan/SKILL.md`'s Execution Mode Decision section keeps its
  always-loaded summary (Decision 6's surfacing rationale — R10's
  buried-reference fix — still holds; this is a pointer-plus-short-summary,
  not the restatement P4 forbids, the same relationship the plan/roadmap
  skills already have with `issues-table.md`), but the summary now names
  three branches and points at `split-triggers.md`, not two branches stated
  inline.
- `skills/plan/references/phases/phase-3-decomposition.md` steps 3.5a/3.6
  gain the Stated Preference branch (reading the resolved delivery-shape
  preference per PRD R1) alongside the existing hard-constraint and
  incremental-value handling, and step 3.6's recorded rationale now names
  one of the three `split-triggers.md` branches for R13/R14.
- `docs/designs/current/DESIGN-roadmap-plan-standardization.md`'s Decision 6
  gains an appended `## Amendment — 2026-08-15` section (see next field);
  its original text is left unedited.
- The PLAN's `split_rationale` field (R13/R14) has exactly three names to
  choose among — **Hard Constraint**, **Incremental Value**, **Stated
  Preference** — plus, for coordinated plans only, **Merge-Order Necessity**
  as a fourth, altitude-local value.

<!-- decision:end -->

## Amendment mechanism: note appended to the existing design, not a new decision record

**Precedent check.** Two prior amendment shapes exist in this corpus:

1. `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` carries
   an appended `## Amendment — 2026-08-15` section (added by the separate,
   later `DESIGN-scope-artifact-persistence.md`) that leaves the original
   Decision 8/9 text unedited and adds a dated section stating which
   conclusions are falsified, which survive on different grounds, and why —
   quoting the original decision's wording before correcting it.
2. `docs/designs/current/DESIGN-shirabe-scope-skill.md` amends a *live
   governing reference* (`references/parent-skill-pattern.md`'s L13 rule)
   directly — rewriting the reference file's operative prose in place — and
   records the rationale for the edit inline in its own new decision, citing
   "the L13 amendment" as something this design's Decision 3 does, not as a
   retrospective note left in an old file.

**Which applies here, and why both halves are used.** Decision 6 of
`DESIGN-roadmap-plan-standardization.md` is a decision record whose stated
conclusion — "its named escape conditions (a hard constraint, or each PR
independently useful)" — is a factual claim about the rule's shape that this
decision supersedes in part: the rule now has three branches, and Decision 6
did not know about (and did not resolve) the P1-vs-coordination-strategy
disagreement R5 names. That is the same situation `DESIGN-scope-artifact-
persistence.md` faced with Decision 8/9: a past decision's *stated content*
becomes incomplete/wrong, not merely superseded in spirit. Per that
precedent, the fix is a `## Amendment — 2026-08-15` section appended to
`DESIGN-roadmap-plan-standardization.md`, quoting Decision 6's "two named
escape conditions" claim, stating it is now three, and pointing at this
design's own decision (the one in this report) as the authority — the
original Decision 6 text is left unedited.

Separately, and not in tension with the above: the *operative* rule text —
`workflow-principles.md` P1, `coordination-strategy.md`'s Coarsest-Legal-
Grouping Rule, and `skills/plan/SKILL.md`'s Execution Mode Decision — are
live governing references, not decision records. Per the L13 precedent,
those get their prose rewritten directly (not left in place with a pointer
to an amendment note), because a skill reads the live reference at runtime,
not the historical design doc's Decision 6 section.

**No new `docs/decisions/DECISION-*.md` file.** Neither precedent used a
freestanding decision record to amend a prior design's decision; both used
in-document mechanisms (an appended section in the old design, or an inline
rewrite-plus-citation in the new one). The existing `docs/decisions/`
corpus is reserved for narrower point decisions (cascade-trigger-mechanism,
lifecycle-strict-mode-interface, etc.), none of which amend a prior design's
Decision N section — that pattern lives inside the design docs themselves.
This decision follows the same shape: amend Decision 6 via an appended
section in its own file, and amend the live references directly.
