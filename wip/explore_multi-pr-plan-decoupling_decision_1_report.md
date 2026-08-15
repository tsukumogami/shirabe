<!-- decision:start id="pr-delivery-preference-vs-p1" status="assumed" -->
### Decision: How a repo-level PR-delivery preference relates to principle P1

**Context**

`/plan` chooses `execution_mode` in one branch (`phase-3-decomposition.md` step
3.6) that fuses a hard-constraint check with an "each PR is independently useful"
value judgment, and `phase-7-creation.md` then treats GitHub issue and milestone
creation as an automatic consequence of the answer. The author wants the forced
case, the preferred case, and the tracking mechanism separated, with the latter
two bound to repo preferences.

The blocking question was a contradiction already shipped in the tree. Principle
P1 (`references/workflow-principles.md`) says split "only for a hard constraint
or genuine incremental value, never by mechanism," which excludes reviewability.
The Coarsest-Legal-Grouping Rule (`references/coordination-strategy.md`) lists "a
single PR would exceed the configured reviewability ceiling" as a legitimate
recorded split trigger, and shirabe's own `CLAUDE.md` ships
`## Reviewability Ceiling:` to configure it. An org preferring small atomic
increments is making a reviewability argument -- forbidden at plan altitude,
blessed one altitude up.

Research established that P1 is prohibitive rather than silent, but not for the
reason first supposed: its "never by mechanism" example targets
input-artifact-derived splitting, while the actual gate is an exhaustive
two-branch affirmative test that reviewability satisfies neither branch of. Two
gaps then reframed the whole decision. `grep -n "trigger"
crates/shirabe-validate/src/*.rs` returns zero hits and no PLAN or coordination
artifact has a field to hold a trigger, so "recorded trigger" is prose-only at
both altitudes. And no file in the tree defines a concrete reviewability ceiling
-- `CLAUDE.md` defers to `coordination-strategy.md`, which names the trigger and
never states a value.

**Assumptions**

- The `scope` skill's `P1`/`P2`/`P3` are unrelated local gate predicates, not the
  workflow principles. If wrong, the blast radius of amending P1 is larger.
- No adopter repo outside this one cites P1 by exact wording.
- A rescaled default unit under `atomic` can clear 3.5a's standalone-value bar
  without a carve-out. Untested; this is the chosen option's stated abandonment
  condition.
- The trigger vocabulary can be left unnamed for now without the free-text slot
  degrading into a non-emptiness check, provided a structural check requires the
  entry to name which branch fired. That structural check is not yet specified.

**Chosen: Record the reason first, then an invertible posture -- as two separable
decisions on one shared mechanism**

Three parts, in order.

*First, build the recording slot.* Add a `split_rationale` frontmatter field to
`plan/v1`, required when `execution_mode != single-pr`, holding free text that
names which branch of the SKILL.md test fired -- a hard constraint, a value
statement, or a posture default -- plus its justification. Enforce it as a new
`PostureClass::DraftTolerable` lifecycle finding: a notice while the PR is draft,
an error at ready. This closes a requirement `skills/plan/SKILL.md` already states
("the constraint must be named in the PLAN doc") and that no schema slot exists
to hold. Free text rather than an enum, because the plan-altitude trigger
taxonomy is not settled and an enum would pre-decide it and lock a
migration-costly schema.

*Second, make the default posture repo-invertible.* A new
`## PR Delivery Preference: consolidated|atomic` CLAUDE.md header on the existing
`flag > CLAUDE.md-header > default` stack, defaulting to `consolidated`. Under
`atomic`, the default unit of work is redefined as the smallest independently
reviewable increment; the 3.5a value guard is unchanged and asks its same
question of that rescaled unit. P1's prose is amended to describe the single-PR
default as the shipped default of a configurable posture rather than a universal.
The name matters: `Execution Mode` is taken by the unrelated `auto|interactive`
header and would be a shipped bug, not a style choice.

*Third, treat tracking as a separate decision on the same mechanism.* Whether a
multi-pr PLAN files GitHub issues and a milestone binds to its own preference,
following the shipped `## Roadmap Issues: optional|required` precedent, and is
recorded in its own frontmatter key. It is a P2-derived rule, not a P1 one, and
posture does not imply it -- an `atomic` repo may want small PRs without issue
overhead, and a `consolidated` repo may want issues for its rare multi-pr plans.

**Rationale**

The recording slot goes first because it is the only part that delivers the
author's stated goal. A multi-pr plan becomes trustworthy evidence when the
artifact says why it is multi-pr, not when a header says what the repo prefers.
Every validator, including the two whose own alternatives it did not advance,
reached this independently, and two of them conceded their option's trust claim
is unenforceable without it.

The posture header beats promoting reviewability into P1 on one clean technical
ground: it rescales the default unit rather than adding a non-value third branch
to an exhaustive value test, so the 3.5a value-confirmation guard needs no
carve-out. Promoting the ceiling imports a size trigger into a context that has a
guard the coordination altitude lacks -- a per-repo PR is a natural value unit by
construction, a plan-level slice forced by size is not -- and the collision has no
resolution that does not weaken the guard or accept that ceiling-triggered splits
can legitimately fail it. It also avoids depending on a ceiling that is defined
nowhere.

Splitting cardinality from tracking as two decisions on one mechanism is what the
cross-examination converged on. They rest on different principles and are
independently triggered, but they share the header stack, the frontmatter, the
Phase 7 branch, and the advisory pattern -- so the shared mechanism is authored
once and the two decisions ride it, rather than either fusing them or building
the same stack twice.

**Alternatives Considered**

- **Reviewability as a named trigger under P1.** The most principled-looking
  option and the one P4's single-source argument favors, but it requires four
  things scoped together -- a concrete pre-diff ceiling metric, explicit 3.5a
  wiring, a trigger-recording field and check, and a P4-conformant extraction of
  the trigger list into a shared reference. Its own advocate stated that shipping
  the principle text without all four is worse than not touching P1. The
  decisive objection is the 3.5a collision: the other three coordination triggers
  cannot be lifted verbatim either, since "independently mergeable" and
  "independently rollback-able" over-fire on almost any well-decomposed plan and
  the DAG-cycle trigger has no referent at plan altitude. Rejected as a
  one-item transplant priced as a four-item lift.
- **A sibling principle for review ergonomics.** The most honest structural
  description of what shirabe already does, but it reintroduces the fusion this
  work removes unless the precedence between two principles competing on one
  decision is specified, and `workflow-principles.md` states its set as five by
  count in prose cited elsewhere. Rejected as more ripple for no additional
  expressiveness.
- **Defer -- ship tracking decoupling only.** A real, non-foreclosing deferral,
  and its P2-vs-P1 separability argument is what established that the two halves
  are independently triggered. Rejected only as a complete answer: it leaves the
  fused step 3.6 branch untouched and makes no progress on the trust goal. Its
  substance survives as the third part of the chosen option.

**Consequences**

`multi-pr` stops being silently uniform and starts being legible: the artifact
records which regime produced it, which is checkable rather than prose-only.
Overrides in either direction -- a `consolidated` repo splitting, an `atomic` repo
consolidating -- become the cases where the record carries the most weight, and
pinning the posture as-of-authoring protects against a live mutable header
drifting away from a point-in-time plan.

What gets harder: `FormatSpec`'s `required_fields` is unconditional, so a
conditional-required-field mechanism has to be built alongside
`execution_mode_required_sections`, which no blast-radius estimate priced. The
Draft->Active approval gate loses its stated justification once tracking is
independent and must be re-keyed from `execution_mode` onto "does this run create
GitHub artifacts," amending
`DECISION-multi-pr-posture-detection-2026-06-06.md`. And `plan-to-tasks.sh`
parses `#N` GitHub references at task extraction for multi-pr rows, so an
issueless multi-pr PLAN needs a third source-var scheme in
`plan-to-tasks-contract.md` before it is schedulable -- the single largest
underpriced item in the tracking half.

`DESIGN-roadmap-plan-standardization.md` Decision 6 is amended rather than
reversed: its de-conflation of decomposition strategy from execution mode
survives unchanged, and the amendment records that the default itself is now
posture-conditional.
<!-- decision:end -->
