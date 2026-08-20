# /prd Scope: scope-koto-adoption

## Invocation Context

Invoked under `/scope`'s chain with `docs/briefs/BRIEF-scope-koto-adoption.md`
as the positional argument (Input Mode 2), so the BRIEF is the upstream and
`--upstream` is not required. `parent_orchestration.rationale: fresh-chain`,
`suppress_status_aware_prompt: true`. Visibility: Public.

Fallback shapes that apply (from `references/fixes/sub-agent-dispatch.md`):
Phase 4 jury runs as three parallel reviewers — parallel dispatch is available
in this session, so serial-self-jury is not needed. Phase 5 finalize is
parent-delegated-approval: this run writes the PRD in Draft and hands back.

## Inherited Open Questions

The BRIEF deferred four questions and named this PRD's Decisions and Trade-offs
as their closure surface. They are carried here verbatim before the BRIEF's
Open Questions section is cleared for its Draft -> Accepted transition, so the
record survives the clear. Each must resolve into a recorded decision, or its
absence must itself be recorded as a remaining unknown this PRD owns.

1. Does `/scope` keep the state file it writes today alongside what a koto
   session tracks, or does one absorb the other? Both hold the run's position,
   and keeping both means keeping them in agreement.
2. What does a run anchor its resumability to, given that `/scope` has no pull
   request open while its chain is in flight and a koto session's own record
   lives on one machine?
3. Does the existing resume behaviour get carried across as-is, or replaced by
   what koto already does? The answer reaches the shared parent-skill contract,
   and through it the other parent.
4. What does a test that can catch this failure actually assert? It has to grade
   what a run produced rather than what it said, and nothing in the current
   suite does that.

## Problem Statement

Carried from the BRIEF. `/scope`'s `SKILL.md` arrives whole at invocation, so
the one passage in it that argues an outcome is worth wanting — a smaller
artifact set — reaches an agent before it has done any of the work that argument
is meant to judge. Prose can move or cut that passage; it can't make the file
arrive in parts.

## Research Leads

Phase 2 research is largely pre-done: two `/explore` rounds and eleven leads
established the substrate's mechanics, its limits, and the costs. The findings
are on this branch under the exploration's own artifacts and are not re-derived.

What still needs investigating before requirements can be written, one lead each:

1. **State ownership.** What exactly does `/scope`'s 255-line state schema hold,
   field by field, and which fields have a koto equivalent? Answers question 1
   and constrains question 2.
2. **Resume surface.** What does `/scope`'s resume ladder key on, row by row,
   and which rows survive if koto holds the run position? Answers question 3.
3. **Eval shape.** What can the current eval harness actually assert, what would
   an artifact-grading scenario need, and what are the three known harness
   defects? Answers question 4.

## Coverage Notes

Settled upstream and not re-opened here: the adoption shape (phase substrate,
children inline), the exclusion of per-child materialization, the exclusion of
post-hoc validation, that skipping stays possible, that context economy is not a
justification, that hop states carry an ungated skip route with the binding on
the exit, and that the machine-local per-step render is the audit surface.
