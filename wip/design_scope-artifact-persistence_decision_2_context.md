# Decision Context: Who authors a contribution section?

## Question

Is a contribution section authored by the child skill at drafting time, or by
the parent (`/scope` Stage 3) at fold time?

## Complexity

standard (Tier 3, fast path: phases 0, 1, 2, 6; --auto)

## Constraints

- **R13 (settled).** The carry check is evaluated against contribution text that
  already exists, never against a prediction. Whichever actor writes it, the text
  exists before the check runs.
- **R7 (settled wording).** The adequacy criterion is two-sided: too-long reads as
  a rewrite of the upstream; too-thin means the survivor's own argument does not
  stand without it. Lifted from `strategy-format.md`'s Strategic Context contract.
- **R12 (settled).** No independent reviewer, human confirmation, or
  mode-conditional gate is added to the *verdict*. This question is about
  authorship of prose, which is distinct — but the structural finding behind R12
  (`/scope` owns no team at its own layer, no sub-agent spawn site in any of its
  seven phase files, no dispatch-binding row) may constrain a parent-authored path.
- **R27 (settled).** The consolidation judgment stays the only artifact-set
  reduction mechanism.
- **R2 (settled).** The judgment fires only where this run produced both documents.
- **R6 (settled).** Contributions accumulate transitively and appear in chain order.
- **R29 (settled).** Documents already on disk validate unchanged; the added checks
  emit nothing on a document declaring no absorption.

## Known Options

1. **Child authors at drafting time (unconditional).** Every BRIEF/PRD/DESIGN/PLAN
   writes its own contribution section as part of its normal draft phase.
2. **Parent authors at fold time.** `/scope` Stage 3 writes the contribution
   section into the survivor when an absorb is decided.
3. **Child authors lazily (propagation-only).** A document writes a contribution
   section only for an ancestor that was actually absorbed into it — that is, the
   section for its own upstream appears only when the upstream folded.

## Background

`/scope` walks BRIEF → PRD → DESIGN → PLAN, deciding per hop whether the upstream
folds into the downstream. Under this PRD, a survivor carries the absorbed
ancestor's contribution as one fixed-heading section placed after `## Status`.

The exploration decision `contribution-section-depth` (D1) chose a two-sided
consumer-anchored adequacy test and explicitly flagged this authorship fork as the
thing that decides whether that criterion rides an existing quality jury or needs a
new fold-time reviewer agent (D1's rejected Alternative 3). D1 assumed child-side
authoring but marked the assumption open.

Precedent named for verification: `/prd` Phase 3.2 has the child read its upstream
BRIEF and draw sections from its body, naming the downstream carry check as the
reason. `strategy-format.md`'s Strategic Context is a contribution section in all
but name and already ships, child-authored.

Secondary question the PLAN's decomposition depends on: under the recommendation,
does each child skill need a new consumption instruction of its own, and how many
files does that touch?
