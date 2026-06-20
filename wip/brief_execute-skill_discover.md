# /brief Discovery: execute-skill

## Problem Candidate
An author who has finished planning a piece of work has no single coordinator that
carries the whole plan to merged code at the implementation altitude. The strategic
and tactical chains each give the author a coherent parent-skill experience — one
conversation that holds state, delegates each step, and inspects only what it needs
to. At the implementation altitude that coherence breaks down: the author can drive
one unit of work at a time, but nothing holds the across-unit picture for a plan
whose units land as several coordinated pull requests — what has merged, what is
blocked, what comes next, and whether the whole coordinated set is finished. The
author ends up being the coordinator, tracking that picture by hand across many PRs,
and loses their place entirely if the session is interrupted.

## Outcome Candidate
Once the feature exists, an author finishes a plan and hands the whole thing off in
one move. From there they get the same rhythm the strategic and tactical chains
already gave them: one conversation that holds state, delegates each unit of work,
and reports progress against the whole — without the author tracking which PR merges
next or whether the coordinated set is done. A single-unit plan runs straight
through to a merged PR; a multi-unit coordinated plan walks its merge order to a
single, unambiguous "done." If the author steps away and comes back, the coordinator
resumes exactly where it left off, even on a different branch, because the plan's own
durable coordination state — not a session file — is the source of truth.

## Grounding Anchor
Conversation only (public framing). Related public artifacts the BRIEF may cite:
the progression-authoring design (DESIGN-shirabe-progression-authoring.md), the
coordinated execution-mode work (shirabe#196), and the /charter + /scope parent
skills as precedent. The motivating exploration is non-durable wip on another
branch and is NOT cited.

## Journey Sketch
- Author has a single-unit (single-PR) plan -> invokes the coordinator -> it runs
  the one unit to a merged PR and reports done.
- Author has a coordinated multi-unit plan -> invokes the coordinator -> it walks
  the merge-order of units, delegating each to the existing implementation flow,
  surfaces progress against the whole, and signals done when the coordinating PR
  merges last.
- Author is interrupted mid-execution -> re-invokes the coordinator -> it resumes
  from the plan's durable coordination state (across branches), picking up the next
  unit rather than starting over.

## Open Questions for Drafting
- Naming: the feature introduces a new implementation-altitude parent skill
  (working name /execute). Confirm the BRIEF frames the capability, leaving the
  in-place-rename-vs-new-skill call to the downstream design.
- Scope boundary precision: keep the work-on-internals migration, the koto
  folder-lease substrate, the redirect mechanism, and non-coordinated multi-PR
  fan-out explicitly OUT.
