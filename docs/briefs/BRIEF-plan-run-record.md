---
schema: brief/v1
status: Draft
problem: |
  After a plan's work merges, shirabe deletes the PLAN and koto may remove the sessions
  that ran it, on every host sharing the session store. Someone who starts from a merged
  pull request can't get back to how the plan ran: the plan at each step, each step's
  proof, the departures taken, and who decided what. And the PR text can't carry the way back.
outcome: |
  A reviewer, auditor or later agent with the tools starts from a merged PR's repository
  and number, reaches the session that ran its plan and every PR the plan produced, and
  reads the plan's evidence there, weeks later, from a fresh workspace. Nothing removes
  that session while it holds the evidence, and the PR stays free of workflow content.
motivating_context: |
  shirabe already treats a PLAN as a working document that its completion step deletes,
  and its koto sessions already keep each run's per-hop record past the terminal tick.
  The two halves don't meet: once the PLAN is gone, nothing tells a reader which session
  was the record, and nothing stops a routine prune from taking it. koto's session pin,
  specified in tsukumogami/koto#444 and not yet landed, gives the retention half a
  mechanism to state its need against.
---

# BRIEF: A plan's run outlives the plan as its record

## Status

Draft

## Problem Statement

A plan in shirabe is a working document. `/plan` writes it, `/execute` (or `/work-on`
for a multi-pr plan) carries it out, and the completion step deletes it once its work
merges. That's deliberate: a PLAN on the default branch after its work landed would be
a second, stale account of what happened. The account is meant to be the run itself.
The koto session that drove the plan, `execute-<topic>` for a single-pr or coordinated
plan, holds the per-step record each `/work-on` child produced.

Nothing connects a merged pull request to that session. The people who need the record
arrive from the PR: a reviewer asking why a step took the shape it did, an auditor
checking that each step was proved, a later agent picking up a follow-up. Once the PLAN
is gone they have a repository and a PR number and nothing that names the session. The
obvious place to put a pointer is the PR's own text, and that's ruled out. PRs carry
nothing from koto, shirabe or niwa unless the repository opted in through workspace
config. Today's `/execute` PRs break that rule in one place: they carry a hidden run
marker line whether or not the repository opted in.

Even a reader who knew the session's name might not find it. koto keeps a finished
session only while something live in its hierarchy holds it, plus a retention period.
After that, the next prune, cleanup, terminal tick or same-name replace takes it, and
under the cloud session store that removal reaches every host. An operator's routine
prune on a second host deletes the record of work it never ran.

What the reader is after is also spread out. `/execute` hands each step to a `/work-on`
child session, so the step's proof and the decisions made inside it sit in the child,
not the root. A reader who reaches the root still has to know where the rest lives.

Finally, shirabe's own references disagree about the lifecycle. The planning skill says
a PLAN is deleted when its work finishes. The plan format reference says a PLAN stays in
`docs/plans/` through every state, `Done` included. A reader who goes looking for the
record by following the documentation is sent to the wrong place.

## User Outcome

A reviewer, auditor or later agent who has shirabe, koto and access to the session store
starts from a merged PR, giving only its repository and number. They reach the koto
session that ran the plan, and from it every PR that carried the plan out, none missing
and none extra. In that session they read the plan as it stood when each step began,
each step's proof, every departure recorded against the step it changed, and each
decision with the actor who made it. It works weeks later, after the run's host and
instance are gone, from a fresh workspace with no local copy.

An operator who prunes finished sessions on any host doesn't have to know which ones
matter. A session holding a merged plan's evidence is kept, and the prune says why. A
finished session from the same run that holds no such evidence is removed as it is today.

A repository maintainer gets PRs that describe the change and how it was checked, with
no session reference, run marker or workflow record in the title, description, comments
or squash message. One who wants the session reference in PRs turns it on in workspace
config, and a run started after they turn it off writes none.

A plan author reading shirabe's planning skill, the plan format reference and the
completion step finds one lifecycle for a PLAN and a ROADMAP, and is sent to the run's
session, not the plan, for the record of how the work went.

## User Journeys

### A reviewer follows a merged PR back to its run

A reviewer opens a fresh workspace weeks after a single-pr plan merged. Its run's host
is gone and the PLAN was deleted at completion. They have the repository and the PR
number. With shirabe's tools and read access to the cloud session store, they reach the
`execute-<topic>` session that ran the plan and the list of PRs it opened. They open the
step that puzzles them and read the plan as it stood when that step began, the step's
proof, the departure the run recorded against it, and the decision behind it with the
actor who made it.

This validates the lookup from the PR alone and the reach from the root session into
each step.

### An operator prunes on a second host

An operator on a second host that shares the cloud bucket runs koto's prune of finished
sessions. The root session of a merged plan and the `/work-on` children holding its step
proof are kept, each listed with the reason it was kept. Two finished sessions from the
same run that hold no evidence, such as a scoping hop's leftover child, are removed as
they would be today. The operator didn't have to look anything up first.

This validates retention as a property of the sessions themselves, read by every removal
on every host.

### A multi-pr plan's PRs lead to the same record

A plan in multi-pr mode lands as three PRs over two weeks, one `/work-on` run each. A
reader starts from the second PR. They reach the session that drove the plan and, from
it, all three PRs, including the one that merged after theirs.

This validates that "the session that ran the plan" is defined for every plan mode, not
only for `/execute`.

### A maintainer turns the session reference on, then off

A maintainer whose team wants the session named in every PR turns the opt-in on in the
workspace config that generates the repository's local context. The next run's PRs
carry the session reference. Later the team turns it off. A run started after that
writes no session reference, while a PR opened earlier keeps what it had.

This validates the default-off posture and the switch's effect on runs started after it
changes.

### A plan author reads the lifecycle

A new contributor reads the plan format reference to learn where a finished plan goes.
It says the PLAN and the ROADMAP are deleted when their work finishes, and that a
multi-pr PLAN is the only one that reaches the default branch, where it stays while its
PRs land. It sends them to the run's session for the record. The planning skill and the
completion step say the same thing.

This validates that the documentation and the behavior agree.

## Scope Boundary

### In scope

- The lookup from a merged PR's repository and number to the koto session that ran its
  plan, and from that session to each of its PRs, for single-pr, coordinated and
  multi-pr plans.
- What the run's sessions hold as the record: the plan at the start of each step, each
  step's proof, each recorded departure against its step, and each decision with its
  actor, plus how a reader gets from the root session to the per-step child sessions.
- Keeping the sessions that hold a merged plan's evidence through every removal koto
  applies, stated as a requirement on koto's session pin, with which sessions are kept,
  when, why, and who may release them.
- Reaching the record from a fresh workspace through the cloud session store alone,
  after the run's host and instance are gone.
- The default that PRs carry no koto, shirabe or niwa content, including today's hidden
  run marker, and the workspace-config opt-in that adds a session reference.
- One stated lifecycle for PLAN and ROADMAP across the plan format reference, the
  planning skill and the completion step, each pointing a reader at the run's session.

### Out of scope

- Building or changing koto's session pin. Its contract is set in koto's own PRD and
  design. This feature states its need against that contract and waits on it to land.
- Runs that finished before this lands. Their sessions may already be gone, and nothing
  here reconstructs them.
- Where the record lives for a team that doesn't use the cloud session store, and how a
  reader without the store's credentials reaches it. Both are real limits. This feature
  names them and leaves them to later work.
- A display of who had the authority to make each decision. Until one exists, "who" is
  the actor koto recorded.
- A checkout-free source for the PR opt-in. The existing reader works from a checkout. If
  the opt-in turns out to need a source that doesn't, that's a separate proposal.

## Open Questions

- Does the PR-to-session lookup belong to shirabe or to koto? The PRD's Decisions and
  Trade-offs should settle where it lives. The design settles how it works.
- Can every removal path be covered by the pin as specified, including subtree removal
  and a parent sweep that meets a pinned child? The PRD should confirm that against the
  pin's requirements.

None of these questions block the brief.

## References

- `skills/plan/references/plan-format.md`: the plan format reference whose Lifecycle
  section this feature brings into line.
- `references/koto-session-retention.md`: why every `koto next` carries `--no-cleanup`.
- `scripts/pr-workflow-content.sh`: the reader of the repository's PR content opt-in.
- `skills/execute/scripts/run-id.sh`: where today's hidden run marker comes from.
