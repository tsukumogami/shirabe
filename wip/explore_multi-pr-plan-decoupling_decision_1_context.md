# Decision Context: How should a repo-level PR-delivery preference relate to principle P1?

## Question

Should a repo-level PR-delivery preference be able to override principle P1's
single-PR default outright, or should reviewability instead become a named split
trigger with a configurable threshold under P1 -- generalizing the
Coarsest-Legal-Grouping Rule from coordinated multi-repo efforts up to the
plan-level single-pr/multi-pr decision?

## Complexity

critical

Amending or reinterpreting a numbered workflow principle changes how every
future plan is reasoned about, and P1 is cited by name from skill surfaces
(`skills/plan/SKILL.md`), phase files, and at least one prior design decision.
The choice also determines whether the downstream work is one design or two, and
whether the "should" gate is even specifiable. The internal contradiction the
decision must resolve is live and shipped in both directions.

## Constraints

- The resolution must reconcile a contradiction that already exists in the tree,
  not merely pick a preference. `references/workflow-principles.md` P1 says split
  "only for a hard constraint or genuine incremental value, never by mechanism,"
  which excludes reviewability. `references/coordination-strategy.md`'s
  Coarsest-Legal-Grouping Rule lists "a single PR would exceed the configured
  reviewability ceiling" as a legitimate recorded split trigger, and shirabe's own
  `CLAUDE.md` ships `## Reviewability Ceiling: default` to configure it.
- Whatever is chosen must be expressible on the existing preference-resolution
  stack: `flag > CLAUDE.md-header > default`. A new config channel is ruled out;
  `DESIGN-roadmap-issueless-preference.md` already rejected `.shirabe.toml` as
  disproportionate.
- The name `Execution Mode` is unavailable -- that CLAUDE.md header already means
  autonomy (`auto|interactive`) and collides with the unrelated `execution_mode`
  PLAN frontmatter enum.
- Must amend rather than contradict `DESIGN-roadmap-plan-standardization.md`
  Decision 6, the current owner of the single-pr/multi-pr rule, which already
  de-conflated decomposition strategy from execution mode and re-anchored the
  roadmap case on value rather than mechanism.
- The tooling side must be expressible through existing machinery: a
  `PostureClass::DraftTolerable` finding in `crates/shirabe-validate` (notice in
  draft, error at ready) plus `advisory.rs`'s advisory-never-gates layer. No new
  enforcement subsystem.
- The stated author goal is that a `multi-pr` plan in a prefer-single repo becomes
  trustworthy evidence that no other option existed. Any option that leaves
  "multi-pr" ambiguous between "was forced" and "was preferred" fails that goal.

## Known Options

1. **P1 becomes a repo-invertible default.** A new header (e.g.
   `## PR Delivery Preference: consolidated|atomic`) lets a repo invert the
   default. Under `atomic`, plans decompose into the smallest independently
   reviewable increments; under `consolidated`, today's behavior holds. P1's
   "default to one PR" is restated as the default *of the default*, not a
   universal.

2. **Reviewability becomes a named trigger under P1, with a configurable
   threshold.** P1 stays universal: never split by mechanism, split only on a
   recorded trigger. The trigger list is lifted from the Coarsest-Legal-Grouping
   Rule up to plan level, and `## Reviewability Ceiling:` -- which already exists
   -- becomes the tunable an org sets low to get atomic behavior. No principle is
   inverted; an existing trigger's scope widens.

3. **Split the axis: cardinality stays value-anchored, reviewability becomes its
   own principle.** P1 is left untouched and a sibling principle is added
   covering review ergonomics as a first-class, org-tunable concern. The
   single-pr/multi-pr decision then has two independent inputs rather than one
   rule with an exception list.

4. **Do nothing to P1; make only tracking configurable.** Accept that the
   "should" gate is not specifiable without a principle change, ship the tracking
   decoupling alone (which has proven precedent and a narrow blast radius), and
   defer the decomposition preference to separate work.

## Background

`/plan` chooses `execution_mode` (`single-pr | multi-pr | coordinated`) in
`skills/plan/references/phases/phase-3-decomposition.md` step 3.6, via a 4-way
branch that fuses a hard-constraint check (a "can" fact) with an
"each PR is independently useful" check (a value judgment). The surfaced rule
lives in `skills/plan/SKILL.md` and is anchored on P1.

`references/workflow-principles.md` P1 -- "Usable value is the unit of work" --
reads: "Every PR and every roadmap feature delivers observable value on its own.
Default to one PR; split only for a hard constraint or genuine incremental value,
never by mechanism." P2 ("Default to the lowest ceremony") derives "One PR over
many" and "A self-contained PLAN doc over GitHub issues when the work is
single-pr" from it.

`references/coordination-strategy.md` Coarsest-Legal-Grouping Rule, applying to
coordinated multi-repo efforts, reads: per-repo implementation is grouped to the
coarsest legal unit -- one PR per repository -- and "a repo splits into more than
one PR only on a recorded trigger: the slices are independently mergeable, or the
slices are independently rollback-able, or a single PR would exceed the
configured reviewability ceiling, or a split is required to break a contraction
cycle in the merge-order DAG. Absent a recorded trigger, do not split."

So shirabe already operates a coarsest-legal-with-named-triggers model, with a
configurable reviewability threshold, one altitude above the decision in
question -- while the plan-level rule forbids reviewability as a reason.

The exploration that produced this decision is recorded in
`wip/explore_multi-pr-plan-decoupling_findings.md`. Its relevant conclusions: the
tracking half of the work is nearly shovel-ready (proven `## Roadmap Issues:`
precedent, one consumer, milestones carry almost no functional weight); the
decomposition half is blocked on exactly this question; and the "can" gate's
trustworthiness additionally depends on generalizing cross-repo Gate nodes to
same-repo plans, which does not exist today.

The author's own position: as sole contributor to tsukumogami they want every
plan that can be one PR to be one PR, and they want multi-pr to be reliable
evidence that no other option existed -- but they explicitly recognize that orgs
with many reviewers may legitimately prefer small atomic increments, and want
that to be honored configuration rather than a fork of the skill.
