# Explore Scope: plan-review

## Core Question

What should an adversarial plan review skill look like — its review framework, loop-back
protocol, and wip/ artifact schema — so it can be both a required phase inside `/plan`
and a standalone callable skill, analogous to how `/decision` is called by `/design`?

## Context

shirabe's pipeline is `explore → prd → design → plan → work-on`. There's currently no
step that adversarially challenges what `/plan` produced before coding starts. The `/plan`
skill has a lightweight Phase 6 review (AI validates completeness and sequencing) but
it's passive. Issue #7 calls for replacing it with a structured challenge.

The skill should sit symmetrically between `/plan` (creates all issues, plan-level) and
`/work-on` (handles one issue at a time, issue-level): `/review-plan` operates at the
plan level and challenges the whole plan before any single issue is implemented.

Key design decisions already settled in scoping:
- **Input**: the PLAN doc (or milestone) — same thing `/plan` produced
- **Position**: replaces `/plan`'s current Phase 6; also callable standalone
- **Architecture**: analogous to `/decision` — invokable standalone, called as sub-op
- **Artifact**: wip/ only (not committed to repo); consumed by `/plan` for loop-back
  verdict and by `/work-on` Phase 0 context injection
- **Loop-back**: if review finds critical issues, `/plan` loops back to appropriate
  earlier phase (design contradiction → Phase 1 Analysis; AC problems → Phase 3
  Decomposition; scope → anywhere)

Issue #19 provides a concrete failure example the review should have caught:
1. AC anchored to fixture data — passed for both correct and incorrect implementation
2. Design contradiction inherited unchanged into plan (ListRecipes vs ListCached)
3. Must-run QA scenario deferred and treated as low-priority

gstack (https://github.com/garrytan/gstack) provides prior art: `/plan-ceo-review`,
`/plan-eng-review`, cross-model second opinion via Codex. Key patterns:
- Scope challenge as mandatory Step 0 before content review
- Premise challenge separate from solution quality review
- Multi-persona review with explicit cognitive frames per role
- `VERDICT: NO REVIEWS YET` state as explicit gate signal

## In Scope

- Design of the `/review-plan` skill (phases, framework, output format)
- Which review categories are mandatory vs optional
- Loop-back protocol: how findings map to `/plan` phases, how verdict is communicated
- wip/ artifact schema for both `/plan` consumption and `/work-on` Phase 0 injection
- Integration with `/plan` as a required Phase 6 replacement
- Eval criteria for measuring review effectiveness

## Out of Scope

- Design contradiction fixes in the `/design` skill itself (issue #19, separate)
- QA-phase improvements (issue #19, different phase)
- Implementation of the skill (this explore produces the design doc)
- Per-issue review (this operates at plan/milestone level, not issue level)

## Research Leads

1. **AC quality patterns**
   What are the systematic failure modes where ACs look valid but don't distinguish
   correct from incorrect implementations? Issue #19 gives fixture-anchored ACs as
   one example — are there others? What does a practical check look like?

2. **Review framework categories**
   gstack separates scope challenge (Step 0) from premise challenge from solution
   review. Which categories are mandatory for shirabe's plan review, and what does
   each check specifically? How do these map to the failure modes in issue #19?

3. **Loop-back protocol**
   How does the review verdict map back to `/plan` phases? Which findings trigger
   which loop targets, and what information does the skill need to communicate
   to the calling workflow to enable the loop?

4. **wip/ artifact schema**
   What must the review artifact contain for (a) `/plan` to act on the loop-back
   verdict and (b) `/work-on` Phase 0 to surface useful context to the implementer?
   How does this compare to how `/decision` artifacts are structured and consumed?
