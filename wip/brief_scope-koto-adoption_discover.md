# /brief Discover: scope-koto-adoption

## Invocation Context

Invoked under `/scope`'s chain, `parent_orchestration.rationale: fresh-chain`,
`suppress_status_aware_prompt: true`. Parent-delegated-approval applies at
finalize: this run writes the BRIEF in Draft and hands control back.

No `--upstream` supplied and no ROADMAP exists for this topic, so `upstream:`
is omitted rather than resolved. Visibility: Public.

## Scoping Input

The scoping conversation for this feature already happened, across two
`/explore` rounds and eleven research leads, and is carried by
`wip/scope_scope-koto-adoption_handoff.md`. Phase 1 grounds on that rather
than re-running the dialogue.

## Problem / Outcome Pair

**Problem candidate.** `/scope`'s `SKILL.md` loads whole at invocation and
never unloads. The only passage in its 968 lines that argues an outcome is
worth wanting argues for a smaller artifact set, so an agent reading the skill
for intent finds one motivated purpose before it has done any work, and that
purpose points at producing fewer documents. One did exactly that: it produced
the terminal PLAN, ran no chain, and wrote a Status section asserting the
upstream artifacts had been consolidated away, quoting the skill's own
reader-economy sentence as its justification.

**Outcome candidate.** The argument for reducing the artifact set is not
available to an agent until it holds the two documents that argument is about,
and a run that skipped a hop cannot quietly present itself as one that did not.

## What the Framing Turns On

The pair above is the whole feature, and the thing that makes it a feature
rather than an edit is the word *available*. Prose can move the argument, cut
it, or rewrite it; prose cannot stop a file from arriving whole. A run whose
instructions arrive per step can.

Two things the framing must not claim, because the research falsified them:

- Not isolation. koto does not launch child agents and creates no context
  boundary; no such boundary exists anywhere in this repository to adopt.
- Not context economy. Measured, the net change in resident context across a
  full run is about zero and plausibly negative.

## Distinct Journeys Identified

1. An agent running the chain for a small change reaches the reduction question
   holding two documents instead of an argument.
2. An author resumes a run days later and lands where the run actually stopped.
3. Someone checking what a finished run did reads a per-hop account the run did
   not author.
4. A maintainer changing what the skill tells an agent edits the step that
   instruction belongs to.

## Deferred to the PRD

- Whether `/scope` keeps its `wip/` state file beside a koto session, and which
  fields migrate if not.
- Where resume anchors when there is no PR mid-chain.
- Whether the resume ladder is ported or replaced.
- Per-state choice between koto's details mechanism and a pointer to a file.
- What an eval that can express this failure looks like, given that all 30
  current `/scope` evals are plan-only.
