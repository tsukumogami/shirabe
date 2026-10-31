---
schema: brief/v1
status: Draft
problem: |
  At a finishing step the coordinate skill decides who settles the step from
  rules of its own: a bound coordinator hands it to its dispatcher, a root one
  to a person. A workspace can't declare that a step needs review and have a
  coordinator that holds the grant for it route the step anyway.
outcome: |
  At each finishing step a manager or director asks the workspace's authority
  answer who settles the step and acts on that answer. Where the workspace
  declares the step needs review, the step goes to the settler the answer
  names, grant or no grant; without the declaration it proceeds as the grant allows.
---

# BRIEF: Coordinator Authority-Settled Steps

## Status

Draft

## Problem Statement

A coordinator, whether a manager running one lane or a director over managers,
reaches finishing steps: merging a pull request, closing an issue, cutting a
release, tearing down a worker's instance. At each one something has to say who
settles the step. Today the coordinate skill says it itself. Since
tsukumogami/shirabe#1449 its text sends a step a coordinator can't take to "the
coordinator that dispatched you when your session is bound, and to a person
only when you are a root coordinator", and defines its reviewer the same way.
That is a rule about parents, written into the skill.

The workspace is meant to own that answer. The owner's line is that what a
session is expected to do is fixed in skills and roles, and what it is allowed
to do is configured per workspace. Who settles a step is the second kind. A
workspace that wants every merge reviewed before it lands, even by a
coordinator holding the merge grant, has nowhere in the skill to say so: the
skill reads the grant, finds `merge-pr`, and merges after its own land-step
review. A workspace that wants the opposite, a supervised lane merging on its
own grant, gets the skill's fixed routing instead.

The skill already asks niwa a question at start. `posture-read.sh` runs
`niwa authority check` with `--point merge-pr --point close-issue --point
cut-release` and folds each point's answer into one verdict per step: permit,
confirm, deny. A deny then routes by the skill's bound-or-root rule, not by
anything the answer said, and the answer that drove it is a copy in the
coordinator's own session record. A coordinator that edits that record can
change what its next step reads. tsukumogami/shirabe#1473 already holds the
standing rules to the same line (a rule in the record can narrow the grant and
never widen it) but nothing holds the finishing steps to it yet.

## User Outcome

A workspace admin declares, in the workspace, that merging needs review. A
supervised manager holding the merge grant reaches a merge and sends it to its
dispatcher; a root director reaches the same step and sends it to a person.
Neither looks up a level, a parent or a rule of the skill's own to get there:
each reads who settles the step from the workspace's answer and goes there.
With the declaration removed, both merge as their grants allow.

A reviewer reading the skill afterwards finds no rule about levels, parents or
who may decide a step, only the reading of the authority answer. A coordinator
that writes into its own record that a review happened finds its next step
routed exactly as before, because the routing never came from the record.

## User Journeys

### A declared merge from a supervised manager

**Trigger:** A supervised manager holding `merge-pr`, in a workspace that
declares merging needs review, reaches its land step on a worker's pull
request that passed every check.

**Outcome shape:** The manager asks the authority answer who settles the
merge, reads its dispatcher there, and sends the pull request to its
dispatcher with its own reading, leaving the merge to that settler. It does
not merge, though its grant names the step.

### The same merge from a root director

**Trigger:** A director a person started, with no dispatcher, reaches the same
merge in the same workspace.

**Outcome shape:** The answer names a person as the settler, and the director
puts the pull request in front of the person. Nothing in the skill says "root
means a person"; the answer said it.

### No declaration

**Trigger:** The admin removes the declaration, and both coordinators reach a
merge again.

**Outcome shape:** The answer leaves the merge to each session's grant. The
manager merges after its land-step review because it holds `merge-pr`; a
coordinator without the grant hands the step to whoever the answer names.

### A forged claim in the record

**Trigger:** A supervised coordinator writes a row into its own record saying
its dispatcher already reviewed the pull request, then reaches the merge.

**Outcome shape:** The routing is unchanged. The step is read from the
authority answer at the step, and a row in the record can only narrow that
answer, never widen it.

### An answer that can't be read

**Trigger:** niwa is missing, times out, or prints a document the skill
doesn't recognise when the coordinator reaches a finishing step.

**Outcome shape:** The coordinator doesn't take the step. It holds it and
reports the failed read, as it treats an unreadable posture today.

## Scope Boundary

**IN:**

- Which finishing steps ask the authority answer, and which point each one
  asks about, including teardown and the other steps the skill hands over.
- When the answer is read: at the step itself, so a declaration changed during
  a run applies at once.
- How the answer reaches the coordinator's record: what is written, and that
  nothing written there is read back to decide a later step.
- Replacing the skill's bound-or-root routing with the settler the answer
  names, wherever the skill sends a finishing step.
- Where this meets tsukumogami/shirabe#1449 (review before merge as the
  skill's own expectation, a coordinator's own reading when it may not merge)
  and tsukumogami/shirabe#1473 (whether a standing rule stands under the
  session's grant, and a rule narrowing that grant but never widening it).
- What the coordinator does when the answer can't be read.

**OUT:**

- Defining the review-before-merge declaration, levels, escalation targets,
  level caps or any grant. Those are the workspace authority work's; this
  feature only reads its answer and says nothing about how it is computed.
- Changes to niwa. Where the answer this feature reads isn't shipped yet, the
  plan names the dependency rather than assuming it; tsukumogami/niwa#422 is
  one.
- A grant model in shirabe. The skill keeps none, as #1473 already holds.
- Workers' own finishing steps. A worker brief's `Named authority:` line and
  what it tells a granted worker stay as #1449 left them.
- Changes to skill text or scripts in this unit. The implementation is a later
  unit and waits on the authority answer it reads.

## Open Questions

- Which point names teardown and the other handed-over steps ask about, when
  the authority answer may not carry a point for them yet. The PRD settles
  which steps ask now and which wait.
- Whether a step the skill always expects reviewed (a coordinator's own
  milestone verdict pull request, under #1449) takes its reviewer from the
  same answer when that answer leaves the step to the session. The PRD
  settles where the expectation and the answer meet.

## References

- `docs/prds/PRD-coordinator-dispatcher-review.md`: the reviewer definition and
  the review-before-merge expectation this feature builds on.
- `skills/coordinate/scripts/posture-read.sh`: the start read of the authority
  answer and the verdict per step.
- `skills/coordinate/scripts/land-merge.sh`: the merge's re-read of the posture.
