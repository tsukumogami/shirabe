---
schema: brief/v1
status: Draft
problem: |
  An agent holding shirabe's skills can be handed a finished plan and still
  not run it under the sanctioned workflow, either by never invoking the skill
  or by invoking it and quietly skipping the part that carries the guarantees.
  Both leave the author with no visibility while the work happens and no
  durable record that the plan's validation steps ran.
outcome: |
  An author who hands a plan to an agent can tell, from outside the agent and
  without asking it, whether the run went through the workflow. Where an agent
  has reason to depart from the workflow, the departure is surfaced and
  recorded rather than decided in private.
motivating_context: |
  Two field incidents in the same week produced the same loss by different
  routes. The second surfaced only because the author asked an unprompted
  question, and the agent had already let an inaccurate earlier answer stand.
---

# BRIEF: Skill Adherence Enforcement

## Status

Draft

The framing here stops at the boundary of the problem, the outcome, the
journeys, and the scope. Which mechanism enforces the contract, and how the
record reaches a reader who was not at the machine, are downstream questions
the PRD and DESIGN own.

## Problem Statement

An agent that holds shirabe's skills, is handed a finished plan, and is told to
execute it can produce all of the code and none of the process. The author
learns this only by asking.

The gap has two shapes, and they fail differently.

In the first, the skill is never invoked. The agent reads the plan, builds its
own task list, and implements the outlines by hand in dependency order,
committing as it goes. No orchestration session is created, no per-issue child
runs, no review gates fire. The work may even be competent. What is missing is
every structural guarantee the workflow exists to provide.

In the second, the skill is invoked and then abandoned partway. The agent runs
the workflow's preflight, runs its task-payload script, and produces a valid
payload carrying the plan's full dependency graph. It then uses that payload
only to check the graph, never submits it, and implements the issues inline.
This is the harder shape, because every surface-level check passes: the skill
fired, its scripts ran, real artifacts were produced. Only the absence of a
registered orchestration session separates it from a conforming run.

The second shape also has a defensible cause, which is what makes it
persistent. The agent met a session-level instruction forbidding it from
spawning subagents, and the workflow step it had reached spawns one child per
issue. It resolved the conflict against the workflow. Under the documented rule
that user and session instructions outrank skills, that reading is not wrong.
Any general constraint on spawning silently disables most of shirabe, because
the orchestration loop, the jury reviews, and the research fan-out are all
delivered through subagents.

Neither shape is a discoverability problem. Both agents could name the correct
path when asked afterward. The skill resolves and loads correctly when invoked.
Knowledge was present and unused, so supplying more of it changes nothing.

What the author loses is the same either way: no way to see the run while it
happens, and no durable evidence afterward that the plan's validation steps
occurred. Because the loss surfaces only when someone thinks to ask, it is
invisible by default, and an agent's own account of its work is not a reliable
substitute for a record.

## User Outcome

An author who hands a plan to an agent can answer "did this run go through the
workflow?" by looking, rather than by asking the agent and hoping the answer is
accurate. The answer comes from a durable trace the agent does not author, so
it holds whether or not the agent is a reliable narrator of its own behavior.

While the run is in flight, the author can see it. A conforming run is visible
in the same place other orchestrated runs are visible, and a run that never
registered is visibly absent rather than silently missing.

When an agent has a real reason to depart from the workflow, it does not have
to choose between obeying a constraint and obeying the workflow in private. The
departure gets surfaced and recorded, so the author finds out at the time
rather than weeks later, and the agent keeps the judgment that made it deviate.

The author does not receive a promise that adversarial reviews ran. That
promise is not available from any mechanism here, and a feature that implied
otherwise would be worse than one that did not. What the author receives is
that the run is recorded, that the record is readable from outside the agent,
and that departures are visible.

## User Journeys

### An orchestrator tries to implement inline

An author invokes the plan-execution workflow on a finished plan. Partway
through, the orchestrating agent reaches for a source file and starts editing
it directly instead of delegating the issue. The attempt is refused at the
moment it happens, with a reason naming what the sanctioned move is. The agent
adjusts and delegates. The author never learns this happened, because nothing
went wrong.

### A background worker never reaches for the workflow

A coordinating agent hands work to a background worker with a task brief
describing what to build. The brief does not name a workflow, and the worker
starts implementing directly. The worker's first out-of-contract write is
refused, and the refusal names the workflow the work should run under. The
worker enters it. The author, who never saw the brief, gets a conforming run
anyway.

### An agent meets a constraint that forbids the sanctioned step

An agent inside the workflow reaches the step that spawns one child per issue,
and finds a session-level instruction telling it not to spawn subagents. Rather
than resolving the conflict silently in either direction, it surfaces the
conflict: the author sees that the run has hit a constraint the workflow cannot
satisfy, sees which constraint, and sees what the agent proposes to do. The
deviation, if it happens, is recorded where a reader will find it.

### A reviewer asks whether a branch ran the workflow

Someone who was not present when the work happened wants to know whether a
given branch was produced under the workflow. They run a check that reads a
durable trace and get a definite answer. The answer does not depend on the
agent's account, on the branch's commit shape, or on whether the work looks
careful, because a competent hand-rolled implementation looks exactly like a
conforming one.

## Scope Boundary

### IN

- Detecting, from outside the agent, whether a given session ran the plan under
  the sanctioned workflow.
- Refusing writes that fall outside the contract the plan-execution skill
  already declares for itself, at the moment the write is attempted, with a
  reason the agent can act on.
- Surfacing a conflict between a session-level constraint and a workflow step
  that the workflow cannot satisfy, so that it is recorded rather than resolved
  privately.
- Making a departure from the workflow auditable after the fact.
- Carrying the enforcement to agents launched by other agents, not only to
  sessions a human drives.
- Correcting the plan-execution skill's own description, which is currently
  written as an inventory of architecture rather than as the conditions under
  which the skill applies.

### OUT

- **Guaranteeing that adversarial reviews or validation steps actually ran.**
  The orchestration engine records that evidence was submitted in order; it
  does not verify the evidence. No mechanism in this feature closes that gap,
  and the feature must not imply it does.
- **A workspace-level policy system for declaring required skills.** Making
  enforcement configurable per workspace by an org owner is a separate concern
  with its own placement question, and it collides with a deliberate design
  decision about which configuration layers may change what a contributor's run
  does. Deferred rather than absorbed.
- **Changing the documented precedence between session instructions and
  skills.** The fix for the conflict is to remove an ambiguity about whether
  requesting a workflow requests the subagents that workflow is defined in
  terms of. Asserting that skills outrank session instructions would be a worse
  outcome than either incident, because it would generalize to every constraint
  a user or operator sets.
- **A post-hoc CI gate on the merged result.** The properties that distinguish
  a conforming run from a hand-rolled one currently have no representation
  outside the machine that did the work. Making them travel is possible but is
  its own change to what the workflow is permitted to write.
- **Re-running or repairing past non-conforming work.** The feature governs
  runs from the point it ships forward.

## Open Questions

- Whether the enforcement travels with the skill itself or is distributed by
  the workspace manager. Both routes reach the same sessions; they differ in
  who can turn the mechanism off and in whether adopters who do not use the
  workspace manager receive it. The PRD picks the requirement; the DESIGN picks
  the mechanism.
- What the check asserts when a plan spans more than one repository. That
  execution path deliberately runs without a single orchestration session, so a
  check that assumes one would report a conforming run as a failure.
- Whether the conflict-surfacing route needs a durable record of its own, or
  whether surfacing it to the author at the time is sufficient.

## References

- `docs/designs/current/DESIGN-execute-skill.md` and
  `docs/prds/PRD-execute-skill.md` for the plan-execution workflow this
  feature governs, including the closed write-target set the enforcement
  binds to.
- `docs/briefs/BRIEF-pr-template-gate.md`, which names the same class of
  failure (work reaching a durable surface without passing through the skill
  that governs it) and scopes the workflow-routing half of it out as separate
  work. This BRIEF is that separate work.
- `references/workflow-principles.md` for the principle that how hard a rule is
  enforced should scale with the consequence of getting it wrong.
