---
schema: brief/v1
status: Accepted
problem: |
  A director that dispatched a lane can learn what the lane may do only by
  asking it, or by trusting the brief it wrote; neither is what niwa enforces,
  and both go stale when the workspace changes a grant. And a lane's worker cap
  can be moved by any session that runs the skill, with no authority checked.
outcome: |
  A director reads a lane's grants and level from niwa's records, without the
  lane telling it, and sees the answer change when the workspace changes the
  grant. A session without niwa's cap-change authority that tries to move
  another lane's cap is refused by that authority's name.
---

# BRIEF: Director Reads Lane Authority

## Status

Accepted

The brief stops before requirements. The PRD this feeds settles what the
director reports and how a refusal reads.

## Problem Statement

Coordinators come in two roles. A manager runs one lane: it dispatches workers,
verifies what they push and lands it. A director sits over managers and
dispatches them. "Coordinator" means either.

A director that has dispatched a manager has two ways today to say what that
manager may do. It can ask the manager, which costs a message and returns a
claim the manager makes about itself. Or it can reread the brief it wrote,
which says what the director meant to grant, not what the session holds. Both
miss the same thing: niwa decides what a dispatched session holds, and it
resolves that answer when asked. A role's grant comes from what the workspace
declares for that role at the moment of the check, and it's kept inside the
current grant ceiling and inside what the dispatcher holds now. So a workspace
that narrows a role, or lowers the ceiling, changes what every lane under it
may do, and nothing the director remembers or the lane reports moves with it.

There are two separate questions here. What a session is expected to do is
written in the skill and in the role it plays. What it's allowed to do is
configured per workspace and host, and niwa is where that configuration is
read. A director that reasons about a lane's allowances from its own text
quietly turns an allowance into an expectation, and the two drift apart the
first time the workspace changes.

The second half of the problem is the lane's cap. The coordinate skill caps
each lane's active workers (`--cap`, five by default), and today any session
running the skill can set that number for a lane, its own or a sibling's.
Moving another lane's cap changes how much work that lane carries, which is an
authority question, and the skill checks no authority before doing it. The
obvious fix, a rule in the skill about who may move a cap, would give the skill
an authority model of its own. That's the thing to avoid: allowances belong to
the workspace, and a skill that defines one has a second source of truth that
niwa can't see and the workspace can't change.

## User Outcome

A director asked what a lane it dispatched may do answers from niwa's record
of that lane: its grants, its level and where the level came from, read
without involving the lane. When the workspace changes what the lane's role
grants, the director's next answer shows the change, because the director
reads again rather than remembering.

A session that tries to move another lane's cap through the skill is checked
against niwa. If niwa doesn't grant it the cap-change authority, the skill
refuses and names that authority, so the person reading the refusal knows
which grant is missing and where to change it. The skill contains no
definition of that authority, no rule for who gets it and no level logic: it
names the authority as something niwa grants and acts on niwa's answer.

## User Journeys

### A director checks what a lane may do

A director has three managers running. Before handing one a unit that ends in
a merge, it wants to know whether that manager may merge. It reads the
manager's authority from niwa by the manager's instance and session, without
messaging the manager, and reports the manager's grants and level. The answer
also says which dispatch launched the manager, so the director can see the
manager is one it dispatched.

### The workspace narrows a grant

The workspace owner removes an authority from the role the manager was
dispatched with. The manager is still running and its brief still says it was
dispatched with that role. The director, asked again, reads niwa again, and
its answer no longer lists the removed authority.

### A lane tries to move a sibling's cap

One manager, short of work, tries to raise a sibling manager's worker cap
through the skill. It doesn't hold the cap-change authority. The skill refuses
before anything changes and the refusal names the authority it lacks. The
sibling's cap is unchanged.

### The authority can't be read

A director asks about a session that niwa reports as not dispatched, or whose
record is unusable, or the read fails or times out. The director says it
can't tell what that session may do and why, rather than falling back to the
brief or to the lane's own claim. A cap move whose check can't be read is
refused the same way.

### A maintainer looks for the cap-change rule

A maintainer reading the coordinate skill wants to know who may move a cap.
The skill sends them to niwa: it names the cap-change authority as one niwa
grants and has no definition, level rule or grant table of its own.

## Scope Boundary

### In

- A director reading a dispatched lane's grants and level from niwa's
  authority record, by the lane's instance and session, without the lane's
  involvement.
- Reading fresh each time the question is asked, so a workspace change shows
  up in the next answer.
- What the director does when the answer isn't a bound session, or can't be
  read: it says so and assumes nothing.
- Refusing a move of another lane's cap through the skill when niwa doesn't
  grant the moving session the cap-change authority, with the authority named.
- Where this meets the other places a coordinator already asks niwa about
  authority: about itself when it starts, about who settles each finishing
  step, and about whether a standing rule holds under its grant.

### Out

- Defining the cap-change authority, levels, grants, ceilings or how niwa
  computes any of them. The workspace authority work owns those; this feature
  reads niwa's answer.
- A session moving its own cap. The question here is one lane acting on
  another.
- Changing a grant from the skill. The workspace changes grants; the director
  only observes the change.
- Making a lane's answer visible to sessions outside the workspace, or across
  hosts.
- Closing the gap where a session without a grant can launch a child that
  holds one, with a record that looks like an operator launched it
  (tsukumogami/niwa#422). That's niwa's fix; this feature depends on it for
  the dispatcher niwa records to be the one that really dispatched the lane.
- The finishing-step settler reads themselves (merge, close, release), which
  have their own scoping.

## References

- `skills/coordinate/SKILL.md`, Bounds and Authority: the lane cap and the
  start read of the session's own authority.
- `docs/plans/PLAN-coordinator-standing-rule-provenance.md`: the grant fields
  a standing rule carries.
