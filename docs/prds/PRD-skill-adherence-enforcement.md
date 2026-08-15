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

**As an author whose work was handed to a worker by another agent**, I want the
worker held to the workflow even though the brief it received never named one,
so that a method the coordinating agent forgot to specify is not a method the
run gets to skip.

**As a reviewer establishing what a branch went through**, I want a definite
answer from a durable trace, so that I am not left inferring from commit shape,
which a competent hand-rolled implementation reproduces exactly.

## Requirements

### Defined terms

These four terms carry the requirements and are used with exactly these meanings
throughout. They name properties, not mechanisms; how each is recognized belongs
to the DESIGN.

- **Plan-scale execution.** A session is performing plan-scale execution when it
  is implementing the issues of a PLAN document, whether or not it invoked any
  skill to do so. The definition is deliberately independent of skill
  invocation, because the second field incident and the never-invoked case both
  turn on a session doing this work without having entered the skill.
- **Orchestrator role.** Within plan-scale execution, the session that owns the
  plan as a whole, as distinct from a session it delegates a single issue to. A
  delegated single-issue session is not in the orchestrator role.
- **Registered.** An orchestration session exists and is bound to the PLAN
  document under execution.
- **Delegated.** Every issue whose implementation the run produced was
  implemented by a session other than the orchestrator.

### Functional

**R1.** The system SHALL determine, for a session that performed plan-scale
execution, whether that session ran under the sanctioned workflow. The
determination SHALL be derived only from state that no tool call issued by the
session under evaluation produced. Output of a script the session ran is
therefore not admissible evidence.

**R2.** A session SHALL be reported as conforming only when it was both
registered and delegated. A session that invoked the skill, executed its
scripts, and implemented one or more of the plan's issues in the orchestrator
role SHALL be reported as non-conforming. Invocation SHALL NOT satisfy the
check, and neither SHALL partial delegation.

**R3.** The system SHALL refuse a filesystem write when all three hold: the
session is performing plan-scale execution, the session is in the orchestrator
role, and the write target falls outside the closed write-target set the
plan-execution skill declares for itself. The refusal SHALL occur at the point
the write is attempted, rather than at a later self-administered check.

**R4.** The system SHALL arm R3 on a signal that the session is performing
plan-scale execution in the orchestrator role, and that signal SHALL NOT be the
invocation of the plan-execution skill. A session handed plan-scale work by
another agent, whose instructions never named a workflow, SHALL be armed on the
same footing as one whose author invoked the skill by name.

**R5.** A refusal under R3 SHALL carry a reason naming the refused target and
the sanctioned alternative for that target, in a form the refused session
receives and can act on within the same turn. The reason SHALL be specific to
the refused write rather than a single constant emitted for every refusal.

**R6.** The refusal SHALL hold in non-interactive and permission-bypassing
sessions, and SHALL NOT depend on a human being available to answer a prompt.

**R7.** For a coordinated multi-repository run, which by design has no single
orchestration session, the system SHALL report a distinct coordinated-path
outcome. It SHALL NOT report failure, and SHALL NOT report the plain conforming
outcome, so that a reader can tell a carve-out from a verified run.

**R8.** Where the system cannot establish that a session is performing plan-scale
execution in the orchestrator role, it SHALL NOT arm R3, and the write SHALL
proceed.

**R9.** Where the system has armed but cannot establish whether a session was
registered and delegated, it SHALL report an indeterminate outcome. It SHALL NOT
report conformance on unresolved evidence.

**R10.** When a session determines that a session-level or workspace-level
instruction forbids a step the workflow requires, it SHALL record the conflict
before proceeding by either route, and the system SHALL provide a route that is
available when no orchestration session yet exists. Departing from the workflow
without a recorded conflict SHALL itself be a non-conforming outcome under R2.

**R11.** The conflict record under R10 SHALL identify the instruction, the
workflow step it conflicts with, and the course the session intends to take, and
SHALL be surfaced to the author without the author querying the session.

**R12.** Every behavior in R1 through R11 SHALL apply to sessions launched by
another agent, not only to sessions a human started interactively.

**R13.** The plan-execution skill's description SHALL name the situations in
which the skill applies. It SHALL contain no term that does not appear in the
skill's own user-facing documentation.

**R14.** The system SHALL provide a recorded, re-runnable set of plan-shaped
prompts and a procedure that reports the rate at which the plan-execution skill
is selected across that set. The same set SHALL be used before and after any
change made under R13, and the set SHALL be committed so a later reader can
re-run it.

**R15.** The system SHALL provide an operator-reachable means of disabling the
in-band refusal under R3, without editing skill or workflow content. The
read-only determination under R1 SHALL remain available when the refusal is
disabled.

### Non-functional

**R16.** The in-band refusal under R3 SHALL add no more than 100ms at the 95th
percentile to any tool call it observes.

**R17.** Where a component of the enforcement is absent, fails to run, or
implements a contract version older than the one the session's skill declares,
the system SHALL permit the action rather than block the session.

**R18.** No requirement in this document SHALL be satisfied by a mechanism that
asserts skills outrank user or session instructions. This constraint is verified
by review rather than by an executable test.

**R19.** The conflict record under R10 and R11, which is written to a durable
surface, SHALL NOT embed content from a private repository when the repository
it is written to is public.

## Acceptance Criteria

The check's output domain is exactly four values: `conforming`,
`non-conforming`, `coordinated`, and `indeterminate`. Every criterion below that
names an outcome names one of these.

**The determination (R1, R2, R7, R9)**

- [ ] AC1. Given a session that registered and delegated every issue, the check
      reports `conforming`. (R1, R2)
- [ ] AC2. Given a session that invoked the skill, ran its preflight and
      task-payload scripts, produced a valid payload, and then implemented the
      issues in the orchestrator role, the check reports `non-conforming`. This
      is the second field incident replayed and is the discriminating case. (R2)
- [ ] AC3. Given a session that never invoked the skill and implemented the plan
      by hand, the check reports `non-conforming`. (R2)
- [ ] AC4. Given a session that delegated five of six issues and implemented the
      sixth in the orchestrator role, the check reports `non-conforming`. (R2,
      partial-delegation bar)
- [ ] AC5. Given a run whose only evidence of conformance is a file the session
      itself produced by running a script, the check does not count that file and
      reports `non-conforming` or `indeterminate`. (R1, admissibility)
- [ ] AC6. Given a coordinated multi-repository run that completed correctly, the
      check reports `coordinated`, and not `conforming` and not
      `non-conforming`. (R7)
- [ ] AC7. Given a session armed under R4 whose registration evidence is missing
      or unreadable, the check reports `indeterminate` and never `conforming`.
      (R9)

**The refusal (R3, R4, R5, R6, R8, R15)**

- [ ] AC8. An attempt to write a source file from a session in the orchestrator
      role, to a path outside the declared write-target set, is refused before
      the write lands. (R3)
- [ ] AC9. A write inside the declared write-target set is permitted, including
      the workflow's own state file, its scratch, and its pull-request
      operations. (R3, negative control)
- [ ] AC10. A write from a delegated single-issue session to that issue's source
      files is permitted. (R3, orchestrator-role scoping)
- [ ] AC11. A session handed plan-scale work by another agent, whose instructions
      never named a workflow and which never invoked the skill, is refused on its
      first out-of-set write. (R4, the arming case)
- [ ] AC12. Two refusals of different targets in the same session carry different
      reason text, each naming its own refused target. (R5)
- [ ] AC13. The refused session proceeds correctly on its next attempt with no
      human input and no further refusal for the same target. (R5)
- [ ] AC14. The refusal occurs in a session running with permissions bypassed and
      with no interactive human present. (R6)
- [ ] AC15. A session doing work that is not plan-scale execution writes freely to
      any path, with no refusal. (R8, the fail-open case)
- [ ] AC16. With the enforcement component absent, a session performing plan-scale
      execution runs to completion unblocked. (R17)
- [ ] AC17. With an enforcement component reporting a contract version older than
      the session's skill declares, the session runs to completion unblocked.
      (R17, staleness)
- [ ] AC18. With the refusal disabled through its operator switch, no refusal
      occurs, the session completes, and the read-only determination under R1 is
      still runnable. (R15)

**The conflict route (R10, R11, R19)**

- [ ] AC19. A session that departs from the workflow after recording a conflict
      produces a record naming the instruction, the conflicting step, and the
      intended course. (R10, R11)
- [ ] AC20. That record is visible to the author without the author querying the
      session. (R11)
- [ ] AC21. The conflict route is exercisable in a session that has not created
      an orchestration session. (R10)
- [ ] AC22. A session that departs from the workflow without recording a conflict
      is reported `non-conforming` by the check. (R10, the teeth)
- [ ] AC23. A conflict record written into a public repository contains no path,
      repository name, or issue number belonging to a private repository. (R19)

**Coverage and measurement (R12, R13, R14, R16)**

- [ ] AC24. Every criterion above that concerns a session behavior passes
      identically when the session was launched by another agent rather than
      typed by a human. (R12)
- [ ] AC25. Every term in the plan-execution skill's description appears in that
      skill's user-facing documentation. (R13, replacing a subjective judgment
      with a set-membership test)
- [ ] AC26. The plan-shaped prompt set is committed to the repository, and
      re-running the measurement procedure against it twice without intervening
      changes produces the same rate. (R14)
- [ ] AC27. The measurement is run against the committed set before and after the
      R13 change, and both rates are recorded. (R14)
- [ ] AC28. Measured over a run of tool calls the refusal observes, the added
      latency at the 95th percentile does not exceed 100ms. (R16)

R18 has no acceptance criterion by construction: it constrains the class of
mechanism an implementation may use, which is verified at design and code review
rather than by an executable test.

## Out of Scope

- **Guaranteeing that adversarial reviews or validation steps ran.** The
  orchestration engine records that evidence was submitted in the expected order
  and does not verify the evidence itself. Its spawn primitive is a stub and its
  review gates are directive text. No requirement here closes that gap, and the
  companion obligation is that nothing in the implementation may imply it does.
- **A workspace-level policy surface for declaring required skills.** Making the
  enforcement configurable per workspace by an organization owner is a separate
  concern with an unresolved placement question, and it collides with a
  deliberate decision about which configuration layers may alter what a
  contributor's run does.
- **Changing the documented precedence between session instructions and skills.**
  R10 obliges a session to record a conflict before departing, which leaves the
  departure available to it. It does not reorder the precedence, and R18 forbids
  any implementation that does.
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

R15's operator switch is, by construction, reachable by an agent with the ability
to change configuration. The switch exists because an enforcement mechanism with
no escape hatch gets removed wholesale the first time it is wrong; the trade-off
is accepted rather than solved.

R13 and AC25 test the skill description by set membership against the skill's own
user-facing documentation, which is mechanical but coarse. A description could
pass by using only documented terms and still be a poor trigger. R14's measured
selection rate is what actually decides whether the change worked; AC25 only
stops the description regressing to internal vocabulary.

## Decisions and Trade-offs

These close the three Open Questions the upstream BRIEF deferred here, plus five
decisions the requirements themselves forced.

**Where the enforcement lives, and who can turn it off.** Deferred to DESIGN as a
mechanism choice, but the requirement is settled: R15 fixes that an operator
route to disable the refusal must exist and that the read-only determination
survives it, and R12 fixes that coverage must reach agent-launched sessions. Two
placements were considered. Carrying it with the skill reaches every adopter and
needs no workspace configuration, but binds the enforcement's lifetime to the
skill's. Distributing it through the workspace manager gives an organization
owner a configuration point, but reaches only adopters who use that manager and
raises a placement question about which configuration layer may change a
contributor's run. The requirement is written so either satisfies it.

**What the check asserts for a plan spanning more than one repository.** Resolved
into R7 as a carve-out with its own outcome value rather than left open. The
coordinated execution path runs without a single orchestration session by design,
so a check that assumes one reports a correct run as a failure. The carve-out
reports `coordinated` rather than `conforming`, because telling a reader "this
path is exempt" and "this run was verified" are different answers and collapsing
them would hide an unverified run behind an exemption.

**Whether the conflict route needs a durable record of its own.** Resolved yes,
in R10 and R11, and the reason is the second incident: that agent conceded
afterward that it should have flagged the conflict when it made the decision and
did not. Surfacing without recording relies on the author being present at the
moment it happens, which for a dispatched run they are not. The alternative
considered was surfacing in-session only, which is cheaper and was rejected on
that ground.

**Invocation is not the unit of measurement.** R2 exists because the second
incident invoked the skill and ran its scripts. Any check keyed on "did the skill
fire" passes that incident, so the requirement names the discriminator directly.
R1's admissibility clause extends the same reasoning: that incident's payload was
produced by a script the agent ran, so evidence traceable to the session's own
tool calls cannot count, or the discriminator is defeated by the artifact the
failure produced.

**Partial delegation is non-conforming.** R2 requires every issue to have been
delegated. The looser bar, at least one delegation, was rejected because a run
that delegates five of six and implements the sixth in the orchestrator role is
most of the failure being fixed, and would pass.

**Arming is separate from determination, and only one of them fails open.** The
draft conflated these and the two clauses contradicted each other: a worker that
never invoked the skill is precisely the ambiguous case, so a blanket
fail-open permitted the write that the never-invoked journey requires be refused.
They are now split. R8 fails open on arming, so a session that is not doing
plan-scale execution is never impeded. R9 does not fail open on determination:
an armed session with unreadable evidence reports `indeterminate`, never
`conforming`. The asymmetry is deliberate, because permitting an action and
asserting a run was correct carry very different costs when wrong.

**Recording the conflict is obligatory, not merely available.** R10 was drafted
as providing a route. The field incident is an agent that had the judgment and
did not use it, so a route nobody is obliged to take does not address it. R10 now
obliges the record and R2 gives it teeth by making an unrecorded departure
non-conforming. This stops short of forbidding the departure itself, which R18
would prohibit.

## Downstream Artifacts

- `docs/designs/DESIGN-skill-adherence-enforcement.md` picks the mechanisms that
  satisfy these requirements.
