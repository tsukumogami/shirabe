---
schema: prd/v1
status: Draft
upstream: docs/briefs/BRIEF-skill-adherence-enforcement.md
problem: |
  An agent holding shirabe's skills can be handed a finished plan and produce all
  of the code and none of the process. It happens two ways: the skill is never
  invoked, or it is invoked and the step carrying the guarantees is skipped on a
  defensible reading of a conflicting instruction. Both leave the author without
  visibility during the run and without durable evidence afterward, and both
  surface only when someone thinks to ask.
goals: |
  A run's conformance becomes a property someone can check rather than a claim
  the agent makes. Writes that fall outside the contract the plan-execution skill
  already declares are refused when attempted, with a reason precise enough to
  correct course. A conflict between a session-level instruction and a workflow
  step is surfaced rather than resolved in private. All of this reaches agents
  launched by other agents, not only sessions a human drives.
motivating_context: |
  Two field incidents in the same week produced the same loss by different routes.
  The second one ran the workflow's scripts and produced a valid task payload
  before abandoning the loop, so every surface-level check passed.
---

# PRD: Skill Adherence Enforcement

## Status

Draft

## Problem Statement

An agent that holds shirabe's skills, is handed a finished plan, and is told to
execute it can produce all of the code and none of the process. The author finds
out by asking.

Two field incidents establish the shape. In the first, the skill was never
invoked: the agent read the plan, built its own task list, and implemented 22
outlines by hand in dependency order. No orchestration session was created, no
per-issue child ran, no review gate fired. In the second, the skill was invoked
and then abandoned partway: the agent ran the workflow's preflight, ran its
task-payload script, produced a valid payload carrying the plan's full dependency
graph, then used that payload only to check the graph and implemented six issues
inline.

The second incident is the harder one and it sets the bar. Every surface-level
check passed. The skill fired, its scripts ran, and real artifacts were produced.
It also had a defensible cause: the agent met a session-level instruction
forbidding subagent calls, and the workflow step it had reached spawns one child
per issue. It resolved the conflict against the workflow, which the documented
precedence between session instructions and skills permits.

Neither incident was a discoverability failure. Both agents named the correct
path when asked afterward, and the skill resolves and loads correctly when
invoked. Knowledge was present and unused.

Who is affected: any author who hands plan-scale work to an agent, and anyone
who later has to establish what a branch went through. Why now: the second
incident shows the failure survives an agent that reaches for the right skill, so
it will not be closed by better routing, and every check that currently exists
passed both incidents.

## Goals

Conformance becomes checkable rather than claimed. Someone who was not watching
can establish whether a session ran plan-scale work under the workflow, by
reading a trace the agent did not author.

Departure from the contract is caught when it happens rather than after the work
is done, and the agent is told enough to correct itself without a human in the
loop, because dispatched sessions do not have one.

A conflict between a session-level constraint and a workflow step stops being
resolvable in silence. The agent keeps the judgment; the author gains the
knowledge.

Coverage reaches sessions no human started. An agent that hands work to another
agent must not be able to drop the workflow by omission.

Nothing here promises that adversarial reviews ran, and the feature must not be
built or described in a way that implies otherwise.

## User Stories

**As an author handing a plan to an agent**, I want to check afterward whether
the run went through the workflow, so that I do not have to rely on the agent's
account of its own behavior.

**As an author watching a long autonomous run**, I want a run that never
registered to be visibly absent rather than silently missing, so that I notice
within minutes instead of at the end.

**As an orchestrating agent mid-run**, I want to be told at the moment I reach
outside the contract, with the sanctioned move named, so that I can correct
course without stalling the turn or waiting for a human who is not there.

**As an agent facing a session instruction that forbids the step the workflow
requires**, I want a sanctioned way to surface the conflict, so that proceeding
does not require me to choose privately between two instructions that both bind.

**As a coordinating agent writing a task brief for a worker**, I want the
workflow the work should run under to be part of what a brief carries, so that I
do not drop it by omission.

**As a reviewer establishing what a branch went through**, I want a definite
answer from a durable trace, so that I am not left inferring from commit shape,
which a competent hand-rolled implementation reproduces exactly.

## Requirements

### Functional

**R1.** The system SHALL determine whether a given session ran plan-scale work
under the sanctioned workflow, and SHALL derive that determination from state the
agent under evaluation did not author.

**R2.** The determination SHALL distinguish a run that registered the workflow
and delegated its work from a run that invoked the skill, executed its scripts,
and then implemented inline. Invocation alone SHALL NOT satisfy the check.

**R3.** The system SHALL refuse a filesystem write that falls outside the closed
write-target set the plan-execution skill declares for itself, at the point the
write is attempted rather than at a later self-administered check.

**R4.** A refusal under R3 SHALL carry a reason that names what was refused and
what the sanctioned alternative is, in a form the refused agent receives and can
act on within the same turn.

**R5.** The refusal SHALL hold in non-interactive and permission-bypassing
sessions, and SHALL NOT depend on a human being available to answer a prompt.

**R6.** The system SHALL NOT report a failure for the coordinated multi-repository
execution path, which runs without a single orchestration session by design.

**R7.** Where the system cannot determine conformance, it SHALL permit the action
and SHALL NOT block on the ambiguity.

**R8.** When an agent determines that a session-level or workspace-level
instruction forbids a step the workflow requires, the system SHALL provide a
sanctioned route that records the conflict and surfaces it to the author, and
that route SHALL be available when no orchestration session yet exists.

**R9.** The conflict record under R8 SHALL identify the instruction, the workflow
step it conflicts with, and the course the agent took.

**R10.** Every behavior in R1 through R9 SHALL apply to sessions launched by
another agent, not only to sessions a human started interactively.

**R11.** The plan-execution skill's own description SHALL state the conditions
under which the skill applies, rather than inventorying its architecture.

**R12.** The system SHALL provide a means of measuring how often the correct
skill is selected for plan-shaped work, so that R11's effect is falsifiable
rather than asserted.

**R13.** The system SHALL provide an operator-reachable means of disabling the
enforcement without editing skill or workflow content.

### Non-functional

**R14.** The conformance check SHALL run on the interactive path of tool calls
without adding latency a user perceives as a stall.

**R15.** Absence, staleness, or failure of any component of the enforcement
SHALL degrade to permitting the action rather than to blocking a session.

**R16.** No requirement in this document SHALL be satisfied by a mechanism that
asserts skills outrank user or session instructions.

**R17.** Public-facing artifacts produced by the enforcement SHALL NOT embed
content from private repositories.

## Acceptance Criteria

- [ ] Given a session that drove the workflow to fan-out, the check reports
      conformance, using only state the session's agent did not write.
- [ ] Given a session that invoked the skill, ran its preflight and task-payload
      scripts, and then implemented inline, the check reports non-conformance.
      This is the second field incident replayed and is the discriminating case.
- [ ] Given a session that never invoked the skill and implemented by hand, the
      check reports non-conformance.
- [ ] Given a coordinated multi-repository run that completed correctly, the
      check does not report a failure.
- [ ] An attempt to write a source file from the orchestrator, outside the
      declared write-target set, is refused before the write lands.
- [ ] The refusal text names the refused path and the sanctioned alternative, and
      the refused agent proceeds correctly on its next attempt without human
      input.
- [ ] The refusal occurs in a session running with permissions bypassed and with
      no interactive human present.
- [ ] A write inside the declared write-target set is permitted, including the
      workflow's own state file, its scratch, and its pull-request operations.
- [ ] With the enforcement binary absent from the path, a session runs to
      completion unblocked.
- [ ] With the enforcement disabled through its operator switch, no refusal
      occurs and the session completes.
- [ ] An agent that records a conflict under R8 produces a record naming the
      instruction, the conflicting step, and the course taken, and that record is
      visible to the author without the author querying the agent.
- [ ] The conflict route is exercisable in a session that has not created an
      orchestration session.
- [ ] A session launched by another agent, with no human-typed invocation, is
      subject to the same refusal and the same check as an interactively started
      one.
- [ ] The plan-execution skill's description contains no internal architecture
      vocabulary and names the situations in which the skill applies.
- [ ] A measurement of skill selection over plan-shaped prompts produces a rate
      before and after the description change, and the two are comparable.

## Out of Scope

- **Guaranteeing that adversarial reviews or validation steps ran.** The
  orchestration engine records that evidence was submitted in the expected order
  and does not verify the evidence itself. Its spawn primitive is a stub and its
  review gates are directive text. No requirement here closes that gap, and R16's
  companion obligation is that nothing in the implementation may imply it does.
- **A workspace-level policy surface for declaring required skills.** Making the
  enforcement configurable per workspace by an organization owner is a separate
  concern with an unresolved placement question, and it collides with a
  deliberate decision about which configuration layers may alter what a
  contributor's run does.
- **Changing the documented precedence between session instructions and skills.**
  R8 removes an ambiguity about whether requesting a workflow requests the
  subagents that workflow is defined in terms of. It does not reorder the
  precedence, and R16 forbids any implementation that does.
- **Making the conformance record travel off the machine.** A post-hoc check by
  someone with no access to the machine that did the work would require the
  record to be published to a durable remote surface, which widens what the
  plan-execution skill is permitted to write.
- **Remediating past non-conforming work.** The requirements govern runs from the
  point the feature ships.

## Known Limitations

The check establishes that a run was registered and that it delegated. It does
not establish that the delegated work was done well, that reviews were
substantive, or that the recorded evidence is true. An agent that drives the full
loop while submitting weak evidence produces a conforming record.

The write-target refusal covers writes issued through the tools the enforcement
observes. A write performed indirectly, by a subprocess the agent starts, is not
covered. Closing that would require operating-system-level confinement, which is
a different class of mechanism.

R13's operator switch is, by construction, reachable by an agent with the ability
to change configuration. The switch exists because an enforcement mechanism with
no escape hatch gets removed wholesale the first time it is wrong; the trade-off
is accepted rather than solved.

## Decisions and Trade-offs

These close the three Open Questions the upstream BRIEF deferred here, plus two
decisions the requirements themselves forced.

**Where the enforcement lives, and who can turn it off.** Deferred to DESIGN as a
mechanism choice, but the requirement is settled: R13 fixes that an operator
route to disable it must exist, and R10 fixes that coverage must reach
agent-launched sessions. Two placements were considered. Carrying it with the
skill reaches every adopter and needs no workspace configuration, but binds the
enforcement's lifetime to the skill's. Distributing it through the workspace
manager gives an organization owner a configuration point, but reaches only
adopters who use that manager and raises a placement question about which
configuration layer may change a contributor's run. The requirement is written so
either satisfies it.

**What the check asserts for a plan spanning more than one repository.** Resolved
into R6 as a carve-out rather than left open. The coordinated execution path runs
without a single orchestration session by design, so a check that assumes one
reports a correct run as a failure. Making the carve-out a requirement rather
than an implementation detail means the DESIGN cannot omit it silently.

**Whether the conflict route needs a durable record of its own.** Resolved yes,
in R9, and the reason is the second incident: that agent conceded afterward that
it should have flagged the conflict when it made the decision and did not.
Surfacing without recording relies on the author being present at the moment it
happens, which for a dispatched run they are not. The alternative considered was
surfacing to the author in-session only, which is cheaper and was rejected on
that ground.

**Invocation is not the unit of measurement.** R2 exists because the second
incident invoked the skill and ran its scripts. Any check keyed on "did the skill
fire" passes that incident, so the requirement names the discriminator directly.
The alternative was a simpler existence check, rejected because it would report
the known failure as a success.

**Fail open rather than fail closed.** R7 and R15 accept that a broken or absent
enforcement lets work through. The alternative, failing closed, was rejected
because the refusal sits on the path of ordinary tool calls: a stale component
would stop every session rather than the non-conforming ones, and the cost of a
missed detection is lower than the cost of a workspace that cannot work.

## Downstream Artifacts

- `docs/designs/DESIGN-skill-adherence-enforcement.md` picks the mechanisms that
  satisfy these requirements.
