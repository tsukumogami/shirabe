---
schema: brief/v1
status: Draft
problem: |
  The four koto-templated skills (work-on, execute, scope, deliver) and the
  references they and scope's child hops load tell the agent incompatible
  things about the same situation, and often disagree with what koto or a
  script already enforces. They also carry prose no run acts on.
outcome: |
  A maintainer can point at any rule these skills load and name the one file
  that states it. Policy disagreements have been decided by a person, the
  rest follow the file that matches what the code does, and prose nothing
  needs is gone without losing the last copy of any rule still in force.
---

# BRIEF: Contradiction Settlement

## Status

Draft

Framed under `/scope`; the approval step is the parent's.

## Problem Statement

An agent running `/work-on`, `/execute`, `/scope` or `/deliver` reads a skill
file, the koto template's state directives, and whichever references those
point it at. For `/scope` that also means the references `/brief`, `/prd`,
`/design` and `/plan` load at each hop. Those files were written at different
times and several of them now disagree.

Some disagreements are plain staleness. A phase file tells the agent to commit
a file that moved into koto context and no longer exists on disk. A reference
tells the agent to fetch, rebase and record a result that the state it was
loaded from already recorded. A format reference lists PLAN complexity values
the validator rejects, and the validator's own failure message points the
agent back at that reference. The agent can't tell which side is current, so it
either picks one or does both, and a reviewer can't tell from the output which
instruction it followed.

Other disagreements are real choices nobody has made. One file says to
force-push with lease after a rebase and ask the user after a few failures;
the state that loads it says to push, record and never stop under `--auto`.
Retry caps differ between files. Whether a child skill runs its own approval,
push and pull-request steps when `/scope` invokes it is stated two ways. Under
`--auto`, one path files GitHub issues and a milestone with no approval step.
Picking a winner in these cases changes what the workflow is allowed to do,
so it's a decision for a person rather than an edit.

On top of that, a large share of what these skills load is prose the agent
takes no action from: history of earlier revisions, rationale for choices
already made, a retry-clearing block repeated in several places, and
descriptions of what koto or a script does on its own. It costs context on
every run and makes the contradictions harder to see.

Later work depends on these disagreements being resolved: gates that check a
rule need to know which statement of it is the rule, and measuring what
happens when prose leaves default context needs the duplicates gone first.
Today that work has nothing stable to depend on, because no disagreement has a
location or a name anyone can cite.

## User Outcome

A maintainer who wants to change one of these rules can find every place the
rule is stated and knows which one is authoritative. An agent running these
skills gets one instruction per situation, and a reviewer reading its output
can tell which rule it followed. Work that depends on one disagreement being
resolved can cite that one and move when it lands. The policy ones
reach a person as decisions with a recommendation, and none of them is settled
by an edit before that person answers. Once the baseline pin merges,
execution can remove the losing statements and the dead prose in small,
reviewable changes, and each deletion either removes a duplicate or waits for
the later ablation feature, which tests whether a rule can leave default context.

## User Journeys

### A maintainer settles a mechanical contradiction

A shirabe maintainer picks the next unblocked item from the plan. The item
names both locations at a fixed commit, the file that wins and why, so the
change is one edit to the losing file plus a check that the winning file still
says what the plan claims. The reviewer can verify the reason against the
script or template it cites without re-deriving the finding.

### A person decides a policy call

The shirabe maintainer who owns workflow policy receives a decision for force-push after a rebase: what each
file says, what each option would allow, and one recommended option. They pick
one. Only then does the plan item that edits the losing file become startable,
and the edit carries the decision rather than an agent's guess.

### A later gate feature cites one contradiction

Someone scoping per-state gates wants to gate on "decisions are recorded
through koto, not in wip blocks." They cite that item's identifier as a
prerequisite instead of waiting on this whole feature, and can tell from the
plan whether it has landed.

### Deleting prose without losing a rule

An implementer removing the repeated retry-clearing block keeps the one copy
the plan names and deletes the rest. When a planned deletion would remove the
only statement of a rule that still applies, the plan has already marked it as
out of this feature, so the implementer leaves it for the later ablation feature.

## Scope Boundary

**In:**

- Every cross-file contradiction in `/work-on`, `/execute`, `/scope` and
  `/deliver`, the references they load, and the references `/scope`'s hops
  load through `/brief`, `/prd`, `/design` and `/plan`, including a script,
  validator or template side where the prose disagrees with it.
- For each: both locations at a fixed commit, the proposed winner and reason,
  and a mechanical-or-policy label.
- Policy calls written as decisions with one recommendation, carried open.
- An inventory of dead prose by category, with each skill's share of load.
- A plan that sequences the mechanical fixes and the deletions, with a stable
  identifier per item.
- Carrying out that plan once the baseline pin has merged. The baseline pin
  is the separate change that records, at a fixed commit, which templates
  these skills ship and how many instruction tokens each skill loads, so the
  effect of every later edit can be measured against it.

**Out:**

- Any skill, reference or template edit before the baseline pin merges. The
  scoping pull request carries documents only.
- Settling a policy call. The plan waits on the decision.
- Removing the last statement of a rule that is still in force. That is
  withholding, which belongs to a later ablation feature.
- Per-state reference loading, gates, and a rule registry, which are separate
  features.
- The `/coordinate` skill, which is still changing under its own roadmap.
