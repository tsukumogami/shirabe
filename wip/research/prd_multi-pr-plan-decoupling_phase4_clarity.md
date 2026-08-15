# Verdict: FAIL

## 1. Ambiguity

**New contradiction: R13 vs R19 and Goals bullet 5 — a "no preference stated"
plan can now fail validation for the first time.** R13 requires the shape
record "whenever either condition holds: its `execution_mode` is not
`single-pr`, or its `execution_mode` is not what the resolved delivery
preference would have produced." The first branch has no carve-out for
whether any preference was stated at all, and Decisions and Trade-offs
confirms this is deliberate: "`not single-pr` as an additional trigger so a
multi-PR plan always carries a reason **regardless of preference**." Take a
repository that states no delivery preference (default `consolidated` per
R2/R4) and plans a change with a genuine forcing constraint — today's
ordinary multi-pr case, unchanged by this PRD's own R4. That plan validates
today with no reason field. After this ships, R13's first branch fires
(execution_mode is not single-pr) regardless of the fact that no preference
was ever stated, so the plan now needs the new field, and R16 makes its
absence blocking once the PR is ready for review. That is exactly what R19
promises won't happen: "A repository that states neither preference SHALL
observe behavior identical to today's: no new prompts, and **no new required
frontmatter field on any plan that would have validated before this
change**." It's also what Goals bullet 5 promises: "A repository that states
no preference gets exactly the behavior it gets now." R13's condition 1 and
R19/Goals-5 cannot both be true for this case. (The old draft didn't have
this problem — its equivalent no-change promise, old R17, was scoped only to
single-PR plans, so it didn't collide with the field requirement on
non-single-pr plans. R19's wording this round is broader, and now collides
with R13's own "regardless of preference" framing.)

**R7 vs R9 — reworded, not resolved.** My prior finding was that R6(old)'s
default ("today's behavior") was itself a function of `execution_mode`,
contradicting R4(old)'s independence requirement. The fix replaced "today's
behavior" with a concrete value — but the concrete value is *still* branched
on `execution_mode`: R9 reads "the resolved level SHALL be
`issues-and-milestone` for `multi-pr` plans and `none` for `single-pr`
plans." R7 requires the tracking level to resolve "independently of the
delivery-shape preference and independently of the resolved `execution_mode`"
with no stated exception. R9's default rule takes `execution_mode` as an
input to produce two different outputs — the literal thing R7 forbids. Making
the default concrete was progress (it's testable now, and the AC under
"Tracking preference" pins the two outputs), but the contradiction with R7's
blanket "independently... of the resolved `execution_mode`" is still there in
the requirement text itself, just easier to spot. Fix: either add "except for
the unstated default in R9" to R7, or drop "and independently of the resolved
`execution_mode`" from R7 and let R9 alone govern the unstated case.

**R4/R6 — two different uses of "value" sit close enough to misread as
conflicting.** R4 says atomic-mode splits don't need to be "justified as
incremental value." R6 says "No delivery preference may create an exemption
from [the value-confirmation guard]." Read quickly, these look like they
contradict each other on whether atomic splits get any value check at all.
They don't, once you also read the AC under "Delivery-shape preference"
("a unit that fails [the value-confirmation guard] is reported as a
mis-decomposition rather than accepted because the preference is atomic") —
R4 is about what the *recorded reason* for splitting is allowed to be, R6 is
about a *per-unit quality gate* that runs regardless of the reason. That's a
real and defensible distinction, but it's carried entirely by the AC right
now; the requirement text of R4 and R6 would benefit from one clause each
making the distinction explicit, since a reader who stops at the Requirements
section (before reaching Acceptance Criteria) has no way to resolve it.

**R17 is filed under the wrong subsection.** "### Functional — the shape
record" contains R13–R17, but R17 ("Both preferences SHALL be documented in
`references/fixes/claude-md-conventions.md`...") is about documenting the two
*preferences* from the earlier subsections, not about the shape record R13
introduces. Minor, but worth moving under a general/cross-cutting heading so
the section grouping matches what each requirement is actually about.

## 2. Undefined terms

The new Definitions section resolves the three terms flagged last round
("delivery shape," "reviewable increment," and the old "remote GitHub
artifacts" is gone from R11 entirely, replaced with "will create GitHub
issues"). I checked the one term Definitions itself introduces that wasn't
already in the PRD — "decomposition-strategy question" — against the rest of
the repo: it's an established term (`skills/plan/references/phases/
phase-3-decomposition.md`, `skills/plan/SKILL.md`,
`skills/plan/references/quality/plan-doc-structure.md`, and multiple DESIGN
docs all use "decomposition strategy" the same way), so it's fine as used.
No new undefined terms found. This criterion now passes.

## 3. Internal consistency

Covered above: R13 vs R19/Goals-5 is the headline break, R7 vs R9 is the
carried-over one, R4/R6 is resolved in the ACs but not in the requirement
prose itself. Everything else cross-checks cleanly — R13/R15's positive/
negative pairing is exact, R14's three-branch language matches R5's amendment
instruction, R8's six reachable combinations match the ACs, and the
"Decisions and Trade-offs" entries each map to a requirement (R8's "three
tracking levels," R13/R15's "record on departure," R20's "free text") with no
drift between the decision's stated reasoning and the requirement it
justifies.

## 4. Writing style

Still clean. No banned-vocabulary hits (tier/tiered, robust, leverage,
comprehensive/holistic, facilitate). Em dash count is 28 across ~3,470 words,
essentially the same rate as the prior draft and consistent with this repo's
own house style. "Principle P1" (Problem Statement) checks out against
`references/workflow-principles.md`, which does head its first principle
"## P1: Usable value is the unit of work" — accurate, not invented. No hedging
phrases, no hollow gerunds, no title-case headings. Passes.

## 5. Reader test

Substantially improved. The Problem Statement now names concrete files at
first use (`phase-3-decomposition.md`, `phase-7-creation.md`,
`workflow-principles.md`, `coordination-strategy.md`) and no longer leans on
"wip-hygiene rule" or "altitude" jargon in that section — a cold reader can
now go find every document the Problem Statement claims contradicts another.
One residual note, not a Problem Statement issue: "altitude" survives outside
that section — in Decisions and Trade-offs ("The coordinated altitude is a
follow-on") and R20 ("the plan-altitude trigger vocabulary is not settled").
Since the PRD-format stand-alone obligation applies specifically to the
Problem Statement, this doesn't reopen the original finding, but it's a
half-finished cleanup worth another pass if "altitude" wasn't meant to be
kept as an accepted term of art (it isn't in this repo's `## Prose
Vocabulary:` list, which currently only declares tier/journey/underscore).

## Required Changes

1. Resolve R13 vs R19/Goals-5: either scope R13's first branch ("execution_mode
   is not single-pr") to fire only when a delivery preference is actually
   stated, or narrow R19/Goals-5 to acknowledge that non-single-pr plans
   always need the record even under a stated or unstated `consolidated`
   default. Add an Acceptance Criterion for "no preference stated, plan is
   multi-pr via forcing constraint" so the intended behavior is pinned down
   either way.
2. Resolve R7 vs R9: add an explicit exception to R7 for R9's default, or
   rewrite R7 to scope its independence claim to the case where a tracking
   level is actually stated.
3. Add one clause each to R4 and R6 making explicit that R4 governs the
   recorded justification and R6 governs a separate per-unit quality gate
   that runs regardless of it, so the distinction doesn't live only in the
   Acceptance Criteria.
4. Move R17 out of "### Functional — the shape record" into a cross-cutting
   or "documentation" grouping.
