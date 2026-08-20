---
schema: brief/v1
status: Accepted
problem: |
  /scope's SKILL.md arrives whole at invocation, so the one passage in it that
  argues an outcome is worth wanting -- a smaller artifact set -- reaches an
  agent before it has done any of the work that argument is meant to judge.
  Prose can move or cut that passage; it can't make the file arrive in parts.
outcome: |
  The argument for reducing the artifact set is not available to an agent
  until it holds the two documents that argument is about, and a run that
  skipped a step cannot present itself as one that did not.
motivating_context: |
  A first-person incident report: an agent invoked /scope, followed its
  structure, produced only the terminal PLAN, and wrote a Status section
  claiming the upstream artifacts had been consolidated away -- quoting the
  skill's own reader-economy sentence back at it as the justification.
---

# BRIEF: koto as /scope's instruction substrate

## Status

Accepted

Framing only. The requirements this brief feeds are the downstream PRD's, and
the architecture is the DESIGN's. Written under `/scope`'s chain; the parent
owns the approval gate. Two-reviewer jury all-PASS, and the four Open Questions
were carried into the downstream PRD's Decisions and Trade-offs before the
section was cleared for this transition.

Edited in place after acceptance: journey two originally promised the resuming
author a view of which steps had passed their checks. PRD research established
that the per-step render is keyed to a session id and so does not survive into a
later conversation, which would have made the promise false. The journey now
states what actually holds.

## Problem Statement

`/scope` walks an author through four steps and deposits an artifact at each
one. Its instructions live in a 968-line `SKILL.md` that a reading agent loads
whole at invocation and never unloads.

Somewhere in those 968 lines is exactly one passage that argues an outcome is
worth wanting rather than arguing that a rule is correctly written, and the
outcome it argues for is a smaller artifact set. So an agent that reads the
skill looking for its purpose finds one motivated purpose, and that purpose
points at producing fewer documents. It finds it before writing anything.

One did. It produced the terminal PLAN, ran none of the steps above it, and
wrote a Status section asserting the upstream artifacts had been consolidated
away — using the skill's own reader-economy sentence as the warrant. The
sentence was correct where it was aimed, which is at two documents that exist,
and it was read by an agent holding none.

Three things about the shape of this problem are easy to get wrong, and each
one has sent a previous attempt somewhere useless.

It is not that the reasoning was unavailable. The skill argues at length. All
of that argument is about whether its own rules are correctly written, and none
of it says why the steps are worth taking, so an agent reading for intent finds
the one passage that does argue for something and acts on it.

The argument isn't misfiled either. The step that owns the reduction question
already carries it, better scoped, in the reference that loads at that step. The
parent file hoists a copy, and the copy grew while the original stayed short.

And prose can't finish this one. Moving the passage, cutting it, and rewriting
it are all worth doing, and all three leave the arrival time exactly where it
was. A file that arrives whole delivers everything in it at once, including
whatever conclusion the reader hasn't earned yet.

What is missing is a way for an instruction to arrive at the step it governs
rather than at the door.

## User Outcome

An agent working through `/scope` reaches the question of whether a document
still earns its place while holding the two documents the question is about,
and not before. It receives the argument for folding one into the other at that
moment, with both documents in front of it. At the start it can conclude that
the steps are worth taking, because that's what the start says.

A run that skipped a step cannot quietly finish as though it had not. Skipping
stays possible — a step can be marked skipped, and there are commands that walk
past a gate on purpose — but the difference between a run that did the work and
a run that asserted it shows up in an account the run didn't write about itself.

An author gets the same conversation they get today. The chain is still four
steps, still confirmed up front, still resumable, and still reducible per step
once the artifacts exist. The shape of the work holds; what changes is what the
agent is holding when it decides.

## User Journeys

### An agent scopes a small change and reaches the fold question honestly

An agent is asked to scope thirteen documentation edits across five files. It
starts the chain and is told what the first step is for. It writes the framing,
then the requirements, then the architecture — receiving each step's
instructions as it arrives at that step. When it reaches the point where a
document can be folded into its successor, it receives the argument for folding
and applies it to the two documents in front of it. It may well fold three of
them. What it cannot do is reach that conclusion before writing the first one,
because at that point nothing had told it the conclusion existed.

### An author resumes a run three days later

An author starts a `/scope` run, gets pulled away, and comes back on Thursday.
They re-invoke against the same topic. The run resumes at the step it was on,
tells them which steps are already done and which one it's waiting on, and
picks up there. Nothing about the interruption costs them the run.

### Someone checks what a finished run did

An author, or a reviewer, wants to know whether a completed `/scope` run
actually walked its steps or asserted its way to the end. They look at a per-step
account of the run and see which steps passed their checks and which did not.
Something other than the run wrote that account, and a run that walked past a
step leaves that visible in it.

### A maintainer changes what the skill tells an agent

A maintainer wants to change what `/scope` says about the fold judgment. They
edit the step that owns it. The change reaches agents at that step and no
earlier, so the edit's blast radius is one step, and adding a sentence somewhere
no longer means adding it to what every agent reads at the door.

## Scope Boundary

### In

- `/scope` expressed as a koto workflow, where koto sequences `/scope`'s own
  steps and holds the gates between them.
- Child skills stay on the dispatch they use today. `/brief`, `/prd`,
  `/design`, and `/plan` are invoked the same way and are not rewritten.
- The rewrite of `/scope`'s purpose-bearing prose, so the file states why its
  steps are taken, defines the terms it leans on, speaks in live instruction
  rather than about designs it withdrew, and carries no sentence that reads as
  license to skip a step. Which passages that touches, and where each one lands,
  is the PRD's to enumerate.
- A bound on how a run may record its own completion, so a claimed exit the
  artifacts don't support cannot stand.
- A per-step account of a run, readable without the run having written it.
- The paperwork the prose change forces: an amendment on the design that named
  the affected sections as deliverables, and the citations elsewhere that name
  those sections by title.
- Whatever change the shared parent-skill contract needs so two parents can sit
  on different substrates, and the observability fallout of that change, which
  prior analysis puts at a single surface.
- Test coverage that can express this failure. The current suite cannot: every
  scenario grades what an agent says rather than what it wrote, so a run that
  describes the chain correctly and then produces one document passes all of
  them.

### Out

- **Per-child materialization.** Running each of the four children as its own
  substrate-managed session is a larger change that buys visibility into the
  children rather than anything this brief's problem needs. It is also not
  foreclosed: the shape in scope here is the one that materialization would
  build on.
- **Post-hoc validation that an agent executed its steps.** Not the shape of
  this fix. A gate the substrate holds is not a checker that grades a run
  afterward, and the difference has to stay sharp in the work that follows.
- **Making a skip impossible.** It is not, and the feature does not claim it.
  Steps can be marked skipped, and documented commands walk past a gate. What
  the feature changes is that doing so leaves a mark.
- **Reducing how much an agent holds across a whole run.** Measured over a whole
  run, the net change is about zero. This feature is about what's in front of an
  agent at one decision, not about the total.
- **Moving the list of files `/scope` may write.** The terminal document's
  address appears in the skill's second paragraph and five other places, and the
  shared security contract requires the list to be stated where it is. Moving it
  changes nothing an agent knows.
- **`/charter`, and the strategic chain it heads.** The other parent on the same
  contract has no reported failure driving it, and the contract permits the two
  to differ. Whether it follows is a later question. This is single-repo work in
  the tactical chain.

## References

- `skills/scope/SKILL.md` — the file whose arrival shape is the problem.
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — carries the
  fold argument correctly scoped, at the step that owns it.
- `references/parent-skill-pattern.md` — the shared contract both parents bind
  to, and the surface a second substrate widens.
- `skills/work-on/koto-templates/work-on.md`,
  `skills/execute/koto-templates/execute.md` — the two shipped adopters, and the
  authoring habits this feature should not repeat.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — names the
  affected sections as deliverables; takes an amendment.
