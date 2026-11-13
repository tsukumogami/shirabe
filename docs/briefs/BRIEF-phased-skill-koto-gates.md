---
schema: brief/v1
status: Draft
problem: |
  Nine of shirabe's ten phased skills keep their koto session in one state from
  start to finish, so nothing outside the agent's reading of the instructions
  stops a run from skipping a phase or leaving one without its evidence, and
  nobody can ask koto which phase a run is in.
outcome: |
  Anyone running or checking one of the ten skills can ask koto which phase a
  run is in, a move past a phase whose evidence is missing is refused with the
  missing piece named, and a host without koto is told how to install it
  before any work starts.
motivating_context: |
  work-on already runs on a koto template of its own whose states are its
  phases, and it is the only one of the ten that does. The other nine moved
  their working state into koto session keys but kept a one-state store
  template, which records what a run wrote and not where it stands.
---

# BRIEF: Phased skills that can't skip a phase

## Status

Draft

Framing for the phased-skill gates feature, written under `/scope`.

## Problem Statement

shirabe's phased skills are written as a sequence: `/design` decomposes the
question, researches each part, cross-checks, writes the architecture, checks
security and then reviews; `/plan` analyses, decomposes, orders, reviews and
only then files. Each phase asks for something before the next one starts, a
research file, a reviewer's verdict, a confirmation. A person who runs one of
these skills is trusting the run to have done every phase, in order, with
what each phase asked for.

Today that trust rests on the agent alone for nine of the ten skills that
work this way: explore, prd, design, plan, decision, review-plan, roadmap,
vision and release. Each run has a koto session, and its working state lives
in that session's keys, but the session runs on the shared store template,
which has one working state. Three things follow.

1. Nobody can ask where a run is. koto reports the same state at the first
   phase and the last. A person checking on a long run can't tell how far it
   got, and a parent chain resuming an interrupted child has to guess its
   place from which keys happen to exist, which is how a resumed run repeats
   a phase or skips one.
2. Nothing refuses a skipped phase. An agent under pressure, or one that has
   lost its place after a long context, can go straight to writing the final
   document. No check fires; the gap shows only if someone reads the result
   closely enough to notice the missing research or review.
3. A host without koto gets a dead end. The skill-load check reports that
   koto is missing, but on a host without tsuku it can't name a way to
   install it, and the user is left to work that out.

work-on, the tenth, shows the difference: it runs on its own template whose
states are its phases, and koto refuses to let it leave its last states
without the evidence they need.

## User Outcome

A person running any of the ten skills, or a reviewer checking a run
afterwards, can ask koto which phase the run is in and gets the phase by
name, without reading the run's keys. When a run tries to move past a phase
without the evidence that phase asks for, koto refuses the move and says
what's missing, so a skipped step is caught at the moment it happens rather
than in review. A first-time user on a host without koto is stopped before
any work starts and told that koto is required and how to install it.

Parent chains don't notice the change: `/scope` and `/charter` still dispatch
their children, read their results and close them at the end.

## User Journeys

### A reviewer checks a run's position

A reviewer in a fresh repository with koto installed starts `/design` on a
topic and, partway through, asks koto for the status of the run's session.
The answer names the phase the run is in, such as the security phase, rather
than one state that covers the whole run. The same check works for each of
the ten skills.

### An agent tries to skip ahead

Midway through `/plan`, the agent running it tries to go straight to the
phase that files issues, without the review the current phase asks for. koto
refuses the move and names the evidence or check that's missing. The run
stays where it was, and the agent has to do the phase rather than claim it.

### A new user without koto

A user who installed the shirabe plugin but not koto invokes `/prd`. Before
any phase runs, the skill says that koto is required and gives a concrete
way to install it that works on that host, including a host without tsuku.
Nothing is written.

### A parent chain resumes a child

An author's `/scope` run is interrupted while its `/design` hop is in its
third phase. When the author invokes `/scope` again, the run picks up in that
third phase, because the phase is recorded rather than guessed, and nothing
before it is redone or skipped. At the end the chain closes the child as it
does today.

## Scope Boundary

**In:**

- All ten skills named above: a koto session per run whose state names the
  current phase, for each of explore, prd, design, plan, work-on, decision,
  review-plan, roadmap, vision and release. work-on already meets this; it
  stays in the list so the check covers it.
- Refusing a move past a phase whose evidence is missing, with koto naming
  what's missing, for each of the ten.
- The koto-absent path for the ten: stop before work, name koto as required,
  and give an install route that works without tsuku.
- Runs nested inside another skill's run, such as a decision made during a
  design or a plan review during planning: their phase has to be findable
  too.
- Keeping what already ships working: the shared session rules the nine
  skills follow, work-on's own workflow, and the way parent chains hand work
  to a child and close it when they finish.

**Out:**

- Keeping delegated agents' work in koto while it runs. It covers
  a different set of skills and a different property, a fan-out that survives
  a crash, and it needs per-skill phase states to exist first. It is a
  follow-on, not part of this feature.
- Skills outside the ten: brief, strategy, comp, scope, charter, deliver,
  execute and coordinate. brief and strategy share the phase shape of prd and
  vision and could follow later; scope, charter, deliver and coordinate
  already run on templates of their own.
- Changes to koto itself. The feature uses the refusals and evidence checks
  koto has today; a koto change it turns out to need is a separate request
  to koto.
- Judging the quality of a phase's evidence. The feature makes sure the
  evidence exists and has the declared shape; whether a review was a good one
  stays with the review seats.
- Testing phase-skip behaviour with a model acting as a judge. A reader
  might expect the refusal to be proven that way; whatever verifies this
  feature has to run as a script, without a paid model.

## Open Questions

- Whether each skill carries its own workflow template or the skills share
  one parameterised template, and how a live session opened on the store
  template moves to the new one.
- How a phase's evidence is encoded so that koto, rather than the agent,
  decides whether it is present, and which of those checks can't be
  overridden.
- Where a nested `/decision` or `/review-plan` run records its phase: a
  session of its own, or state in its host's session.

## References

- `references/skill-session-convention.md`: the session and key rules the
  nine skills follow today.
- `koto-templates/skill-session.md`: the shared store template.
- `skills/work-on/koto-templates/work-on.md`: the one phased skill that
  already runs on its own template.
- `docs/designs/current/DESIGN-scope-koto-adoption.md`: names per-hop child
  workflows as the follow-on this feature takes up.
- `docs/designs/current/DESIGN-koto-default-action-adoption.md`: the rules a
  new template follows when koto runs a step itself.
