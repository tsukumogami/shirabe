# Explore Scope: work-on-standalone-completeness

## Visibility

Public

## Core Question

`/work-on` invoked on its own runs the work and opens a pull request, then stops
short of everything that turns an open PR into a mergeable one. Those steps exist
only in `/execute`. Before anyone can decide whether to fold `/work-on` into
`/execute` or migrate the finishing logic the other way, somebody has to produce
the list: what exactly does `/execute` do that `/work-on` does not, derived from
the code rather than from recollection, and which items on that list are
per-change finishing logic versus per-plan orchestration.

## Context

Tracking issue: tsukumogami/shirabe#361 (labelled `bug`). It carries a first-pass
list assembled from reading both `SKILL.md` files, both koto templates and both
script directories on `main` (9f84fa7). This exploration's job is to verify,
correct and complete that list from the code, then route the work.

Evidence that prompted it: three dispatched worker sessions on 2026-09-12 and
2026-09-13 each ran `/work-on` standalone and each needed a supervising session
to supply steps by hand -- opening the PR, putting `Fixes #N` in the body,
watching CI, and noticing that a document chain needed scoping before the PR
could merge. In two separate repos `/work-on`'s definition-of-done gate returned
`cannot_verify`.

Two candidate directions are live and neither is pre-decided:

1. Fold `/work-on` into `/execute`, so it stops being a standalone entry point.
2. Keep `/work-on` standalone and complete, migrating the finishing logic into it
   (or into a shared component), leaving `/execute` as orchestration across
   issues.

The structural constraint either direction has to face: `/execute` already calls
back into `/work-on` per issue. Moving finishing logic into `/work-on` means the
cascade and the draft-to-ready transition would run per issue rather than once
per plan -- a behaviour change for a multi-issue run, not just a relocation.

Two filed defects sit in the same family and a change here touches both:
shirabe#360 (neither skill passes `--no-cleanup` on the terminal `koto next`, so
a run that ends blocked destroys its own context record) and shirabe#352 (no gate
can observe whether a review panel ran).

## In Scope

- The full, code-derived inventory of what `/execute` does that `/work-on` does
  not: koto template states, SKILL.md prose steps, scripts, references.
- Classifying each item as per-change finishing logic, per-plan orchestration, or
  shared machinery.
- The call boundary between the two skills today, and what a redrawn boundary
  would do to it.
- Everything that depends on the current boundary: other skills, docs, the
  `multi-pr` PLAN mode, validation and CI.
- What #360 and #352 imply for wherever the boundary lands.
- The `cannot_verify` definition-of-done gate, as evidence about the boundary.

## Out of Scope

- Implementing either direction. This run ends at the exploration report and its
  routing decision.
- The v0.19.2 release and anything release-shaped.
- The cascade-script work in PR #353 and its follow-ups (#354, #355, #356).
- The eval harness and its failing runs (#351) -- eval output is not evidence in
  either direction right now.
- Any repo other than `tsukumogami/shirabe`.
- Filing new issues.

## Research Leads

1. **What is the complete, code-derived inventory of states, prose steps, scripts
   and references in each skill, and what does `/execute` have that `/work-on`
   lacks?**
   This is the deliverable everything else depends on. The issue body has a
   first pass; it needs verifying line by line and completing. The answer must be
   a table keyed to file:line, not a recollection.

2. **For each item on that inventory, is it per-change finishing logic, per-plan
   orchestration, or shared machinery -- and what is the cadence consequence of
   moving it?**
   The draft-to-ready transition and the completion cascade are the sharp cases:
   run per issue they change behaviour for a multi-issue run. Each item needs its
   own answer, not a blanket one.

3. **How does `/execute` invoke `/work-on` today -- what crosses the boundary, and
   what does each side assume the other has done?**
   The circularity objection to folding, and the double-cascade risk in the other
   direction, both turn on this. Needs the actual invocation site, the template
   assertion (`assert-child-template.sh`), and whatever context is handed over.

4. **What does a standalone `/work-on` run actually produce today, traced through
   its koto template from entry to every terminal state?**
   The issue asserts it stops after `pr_creation` / `ci_monitor`. Trace every
   terminal route, including the blocked ones, and record what state the
   repository and the PR are left in at each.

5. **What else depends on the current boundary?**
   Other skills that invoke either one, the `multi-pr` PLAN mode that routes to
   `/work-on` rather than `/execute`, the routing tables in `/explore` and the
   repo's own CLAUDE.md, docs, validation rules and CI. A redrawn boundary that
   breaks a documented route is a cost either direction pays.

6. **What do shirabe#360 and shirabe#352 imply for a redrawn boundary, and should
   they be fixed with it or separately?**
   #360 is about terminal states retaining their context record; #352 about gates
   observing that a panel ran. Both are properties of the states being moved.
   Needs a recommendation with reasoning, not just an observation.

7. **Does this repo already have a pattern for machinery shared between two
   skills, and what do its own authoring conventions say about where shared logic
   belongs?**
   If `/scope` or the chain skills already solved a version of this, the answer
   may be a precedent rather than an invention. The CLAUDE.md CLI-surface rule
   ("artifacts are authored by skills, validation lives in the CLI") is a
   constraint on any answer that proposes moving logic into a script or the
   binary.

8. **Why does `/work-on`'s definition-of-done gate return `cannot_verify`, and is
   that the same defect or an independent one?**
   It fired in two repos. `skills/work-on/references/verification-map.md` is where
   it reads from. If the gate is unverifiable because the map is absent, that is a
   separate bug; if it is unverifiable because `/work-on` never reaches the state
   that would populate it, it is this one.
